import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/curriculum/vocabulary.dart';
import '../../core/motion/motion.dart';
import '../../core/theme/kogo_colors.dart';
import '../../core/widgets/kogo_widgets.dart';
import '../../services/audio/audio_service.dart';
import '../../services/audio/voice_lines.dart';
import '../../services/audio/voice_service.dart';
import '../../services/speech/pronunciation_evaluator.dart';
import '../../services/speech/speech_listener.dart';
import '../../services/system_settings.dart';
import 'game_content.dart';
import 'game_page.dart';
import 'game_widgets.dart';

enum _Phase { ready, listening, success, retry, revealed, blocked }

/// Permainan Dengar & Ulangi (Listen & Repeat) — implementasi voice
/// recognition pada proposal (Gambar 3.6, 3.14, 3.25): anak mendengar contoh
/// pelafalan, menekan mikrofon, lalu sistem menilai ucapannya.
class ListenRepeatGame extends StatefulWidget {
  const ListenRepeatGame({super.key, required this.props, required this.listener});

  final GameProps props;
  final SpeechListener listener;

  static const maxTries = 3;

  @override
  State<ListenRepeatGame> createState() => _ListenRepeatGameState();
}

class _ListenRepeatGameState extends State<ListenRepeatGame> {
  late final List<VocabItem> _items = GameContent.listenRepeat(widget.props.node);
  final _lines = VoiceLines();

  int _index = 0;
  int _tries = 0;
  int _streak = 0;
  _Phase _phase = _Phase.ready;
  PronunciationResult? _result;
  String _partial = '';
  double _level = 0;
  ListenError? _blockedBy;
  int _token = 0;

  VocabItem get _item => _items[_index];

  @override
  void initState() {
    super.initState();
    unawaited(_intro());
  }

  @override
  void dispose() {
    _token++;
    unawaited(widget.listener.cancel());
    super.dispose();
  }

  Future<void> _intro() async {
    final intro = VoiceLines.gameIntro(widget.props.node.game);
    final token = _token;
    await VoiceService.instance.say(intro.text, mood: intro.mood);
    if (!mounted || token != _token) return;
    await _prompt();
  }

  Future<void> _prompt() {
    final line = VoiceLines.listenRepeatPrompt(_item);
    return VoiceService.instance.say(line.text, mood: line.mood, emphasize: line.emphasize);
  }

  Future<void> _onMic() async {
    if (_phase == _Phase.listening) {
      await widget.listener.cancel();
      return;
    }
    if (_phase == _Phase.success || _phase == _Phase.revealed) return;
    final token = ++_token;
    setState(() {
      _phase = _Phase.listening;
      _partial = '';
      _result = null;
      _level = 0;
    });
    await VoiceService.instance.stop();
    AudioService.instance.play(Sfx.micOn);
    await AudioService.instance.setListening(true);
    final item = _item;
    final outcome = await widget.listener.listen(
      accept: (alts) => PronunciationEvaluator.evaluate(item, alts).isCorrect,
      onLevel: (level) {
        if (mounted && token == _token) setState(() => _level = level);
      },
      onPartial: (text) {
        if (mounted && token == _token) setState(() => _partial = text);
      },
    );
    await AudioService.instance.setListening(false);
    if (!mounted || token != _token) return;
    AudioService.instance.play(Sfx.micOff);
    await _handle(outcome, item);
  }

  Future<void> _handle(ListenOutcome outcome, VocabItem item) async {
    final error = outcome.error;
    if (error == ListenError.permissionDenied || error == ListenError.notAvailable) {
      await widget.props.controller.record(
        itemIndex: _index,
        target: item,
        answer: '',
        correct: false,
        responseMs: outcome.responseMs,
        sttError: error!.name,
        countsAsTry: false,
      );
      setState(() {
        _phase = _Phase.blocked;
        _blockedBy = error;
      });
      return;
    }

    final result = PronunciationEvaluator.evaluate(item, outcome.alternates);
    final systemError = error == ListenError.network || error == ListenError.busy || error == ListenError.unknown;
    final noSpeech = result.band == SpeechBand.noSpeech;
    await widget.props.controller.record(
      itemIndex: _index,
      target: item,
      answer: result.heard,
      correct: result.isCorrect,
      similarity: noSpeech ? null : result.similarity,
      responseMs: outcome.responseMs,
      sttError: noSpeech ? (error ?? ListenError.noSpeech).name : null,
      countsAsTry: !noSpeech && !systemError,
    );
    if (!mounted) return;

    if (result.isCorrect) {
      _streak++;
      AudioService.instance.play(Sfx.correct);
      setState(() {
        _phase = _Phase.success;
        _result = result;
      });
      final line = _streak >= 3 && _streak % 3 == 0 ? _lines.streak() : _lines.correct();
      unawaited(VoiceService.instance.say(line.text, mood: line.mood));
      return;
    }

    _streak = 0;
    if (noSpeech || systemError) {
      setState(() {
        _phase = _Phase.retry;
        _result = result;
      });
      final line = _lines.noSpeech();
      unawaited(VoiceService.instance.say(line.text, mood: line.mood));
      return;
    }

    _tries++;
    AudioService.instance.play(Sfx.wrong);
    if (_tries >= ListenRepeatGame.maxTries) {
      setState(() {
        _phase = _Phase.revealed;
        _result = result;
      });
      final line = VoiceLines.reveal(item);
      unawaited(VoiceService.instance.say(line.text, mood: line.mood, emphasize: line.emphasize));
      return;
    }
    setState(() {
      _phase = _Phase.retry;
      _result = result;
    });
    final line = result.band == SpeechBand.almost ? _lines.almost() : _lines.wrong();
    final token = _token;
    await VoiceService.instance.say(line.text, mood: line.mood);
    if (mounted && token == _token) await VoiceService.instance.sayWord(item);
  }

  Future<void> _next() async {
    _token++;
    await VoiceService.instance.stop();
    if (_index + 1 >= _items.length) {
      widget.props.onProgress(_items.length);
      await widget.props.onComplete();
      return;
    }
    AudioService.instance.play(Sfx.whoosh);
    setState(() {
      _index++;
      _tries = 0;
      _phase = _Phase.ready;
      _result = null;
      _partial = '';
      _blockedBy = null;
    });
    widget.props.onProgress(_index);
    await _prompt();
  }

  Future<void> _skipBlocked() async {
    await _next();
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final title = item.display;
    final subtitle = item.isLetter ? 'Huruf ${item.display} · ${item.display} untuk ${_capitalize(item.letter!.text)}' : item.syllables.join(' · ');
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 560;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 96),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 104),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Entrance.pop(
                  key: ValueKey('pic-$_index'),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: KogoColors.br(KogoColors.yellow300, KogoColors.orange400),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [BoxShadow(color: Color(0x33F97316), blurRadius: 24, offset: Offset(0, 12))],
                    ),
                    child: WordPicture(item: item, size: compact ? 112 : 140, radius: 20),
                  ),
                ),
                SizedBox(height: compact ? 12 : 24),
                Entrance.slide(
                  key: ValueKey('word-$_index'),
                  delay: const Duration(milliseconds: 150),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                title,
                                style: TextStyle(fontSize: compact ? 38 : 48, fontWeight: FontWeight.bold, color: KogoColors.gray800),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SpeakerButton(onTap: () => unawaited(VoiceService.instance.sayWord(item)), label: 'Dengarkan ${item.text}'),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Pressable(
                        onTap: () => unawaited(VoiceService.instance.spell(item)),
                        semanticLabel: 'Dengarkan per suku kata',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          child: Text(
                            subtitle,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 20, color: KogoColors.gray600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: compact ? 12 : 22),
                _statusText(),
                SizedBox(height: compact ? 12 : 22),
                _actionArea(compact),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statusText() {
    final heard = _result?.heard ?? '';
    final String text;
    Color color = KogoColors.gray700;
    switch (_phase) {
      case _Phase.ready:
        text = 'Tekan mikrofon dan ucapkan!';
      case _Phase.listening:
        text = _partial.isEmpty ? 'Mendengarkan... 🎤' : '🎤 $_partial';
        color = KogoColors.red600;
      case _Phase.success:
        text = 'Bagus sekali! 🎉';
        color = KogoColors.green600;
      case _Phase.retry:
        text = _result?.band == SpeechBand.noSpeech
            ? 'Suaramu belum terdengar. Coba lagi, ya!'
            : _result?.band == SpeechBand.almost
            ? 'Hampir benar! Coba lagi 💪'
            : 'Belum tepat. Coba lagi, ya!';
        color = KogoColors.orange600;
      case _Phase.revealed:
        text = 'Tidak apa-apa! Ayo lanjut 🌟';
        color = KogoColors.purple600;
      case _Phase.blocked:
        text = _blockedBy == ListenError.permissionDenied ? 'Kogo butuh izin mikrofon 🎤' : 'Pengenalan suara belum tersedia di perangkat ini';
        color = KogoColors.red600;
    }
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: Text(
            text,
            key: ValueKey(text),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color),
          ),
        ),
        if ((_phase == _Phase.retry || _phase == _Phase.revealed) && heard.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Kogo mendengar: “$heard”',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: KogoColors.gray500),
          ),
        ],
      ],
    );
  }

  Widget _actionArea(bool compact) {
    switch (_phase) {
      case _Phase.success:
      case _Phase.revealed:
        return Entrance.pop(
          key: ValueKey('next-$_index-$_phase'),
          child: Column(
            children: [
              if (_phase == _Phase.success) const Icon(Icons.check_circle_outline_rounded, size: 88, color: KogoColors.green500),
              const SizedBox(height: 8),
              Loop.pulse(
                duration: const Duration(milliseconds: 1400),
                to: 1.05,
                child: GradientButton(label: 'Lanjutkan', icon: Icons.check_rounded, onTap: () => unawaited(_next())),
              ),
            ],
          ),
        );
      case _Phase.blocked:
        return Column(
          children: [
            if (_blockedBy == ListenError.permissionDenied)
              GradientButton(
                label: 'Buka Pengaturan',
                icon: Icons.settings_rounded,
                colors: const [KogoColors.blue500, KogoColors.purple500],
                onTap: () => unawaited(SystemSettings.openAppSettings()),
              ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _phase = _Phase.ready),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Coba lagi'),
                ),
                TextButton.icon(onPressed: () => unawaited(_skipBlocked()), icon: const Icon(Icons.skip_next_rounded), label: const Text('Lewati')),
              ],
            ),
          ],
        );
      case _Phase.ready:
      case _Phase.listening:
      case _Phase.retry:
        return _MicButton(listening: _phase == _Phase.listening, level: _level, size: compact ? 112 : 128, onTap: () => unawaited(_onMic()));
    }
  }

  static String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

/// Tombol mikrofon besar (Figma: 128px, ungu→pink; merah berdenyut saat mendengar)
/// dengan cincin yang membesar mengikuti volume suara anak.
class _MicButton extends StatelessWidget {
  const _MicButton({required this.listening, required this.level, required this.size, required this.onTap});

  final bool listening;
  final double level;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // speech_to_text Android melaporkan level kira-kira -2..10 dB.
    final normalized = ((level + 2) / 12).clamp(0.0, 1.0);
    final ring = listening ? 1.0 + normalized * 0.45 : 1.0;
    final button = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: listening ? KogoColors.br(KogoColors.red500, KogoColors.pink500) : KogoColors.br(KogoColors.purple500, KogoColors.pink500),
        boxShadow: [
          BoxShadow(color: (listening ? KogoColors.red500 : KogoColors.purple500).withValues(alpha: 0.4), blurRadius: 30, offset: const Offset(0, 12)),
        ],
      ),
      child: Icon(listening ? Icons.stop_rounded : Icons.mic_rounded, size: size * 0.5, color: KogoColors.white),
    );
    return Semantics(
      button: true,
      label: listening ? 'Berhenti mendengarkan' : 'Tekan untuk berbicara',
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.92,
        child: SizedBox(
          width: size * 1.5,
          height: size * 1.5,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: size * ring,
                height: size * ring,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (listening ? KogoColors.red400 : KogoColors.purple400).withValues(alpha: listening ? 0.3 : 0),
                ),
              ),
              listening ? Loop(duration: const Duration(milliseconds: 500), scale: const [1, 1.08, 1], child: button) : button,
            ],
          ),
        ),
      ),
    );
  }
}
