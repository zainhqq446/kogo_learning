import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/curriculum/vocabulary.dart';
import '../../core/motion/motion.dart';
import '../../core/theme/kogo_colors.dart';
import '../../core/widgets/kogo_widgets.dart';
import '../../services/audio/audio_service.dart';
import '../../services/audio/voice_lines.dart';
import '../../services/audio/voice_service.dart';
import 'game_content.dart';
import 'game_page.dart';
import 'game_scaffold.dart';
import 'game_widgets.dart';

/// Permainan Cari Objek (Find Object): pilih gambar yang namanya diawali
/// huruf tertentu (proposal Gambar 3.7, 3.15, 3.28). Pilihan salah dinonaktifkan
/// dan anak mencoba lagi hingga benar.
class FindObjectGame extends StatefulWidget {
  const FindObjectGame({super.key, required this.props});

  final GameProps props;

  @override
  State<FindObjectGame> createState() => _FindObjectGameState();
}

class _FindObjectGameState extends State<FindObjectGame> {
  late final List<FindObjectRound> _rounds = GameContent.findObject(widget.props.node);
  final _lines = VoiceLines();
  int _index = 0;
  final Set<String> _wrong = {};
  String? _correct;
  int _shake = 0;
  bool _busy = false;

  FindObjectRound get _round => _rounds[_index];

  @override
  void initState() {
    super.initState();
    unawaited(_intro());
  }

  Future<void> _intro() async {
    final intro = VoiceLines.gameIntro(widget.props.node.game);
    await VoiceService.instance.say(intro.text, mood: intro.mood);
    if (mounted) await _prompt();
  }

  Future<void> _prompt() {
    final line = VoiceLines.findObjectPrompt(_round.letter);
    return VoiceService.instance.say(line.text, mood: line.mood, emphasize: line.emphasize);
  }

  String _nameOf(VocabItem item) => item.letter?.text ?? item.text;

  Future<void> _choose(VocabItem option) async {
    if (_busy || _correct != null || _wrong.contains(option.text)) return;
    final round = _round;
    final correct = option.text == round.target.text;
    unawaited(widget.props.controller.record(itemIndex: _index, target: round.target, answer: _nameOf(option), correct: correct));
    if (correct) {
      _busy = true;
      AudioService.instance.play(Sfx.correct);
      setState(() => _correct = option.text);
      final line = _lines.correct();
      await VoiceService.instance.say('${_nameOf(option)}! ${line.text}', mood: line.mood);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      await _advance();
    } else {
      AudioService.instance.play(Sfx.wrong);
      setState(() {
        _wrong.add(option.text);
        _shake++;
      });
      final line = _lines.wrong();
      unawaited(VoiceService.instance.say('Itu ${_nameOf(option)}. ${line.text}', mood: line.mood));
    }
  }

  Future<void> _advance() async {
    if (_index + 1 >= _rounds.length) {
      widget.props.onProgress(_rounds.length);
      await widget.props.onComplete();
      return;
    }
    AudioService.instance.play(Sfx.whoosh);
    setState(() {
      _index++;
      _wrong.clear();
      _correct = null;
      _busy = false;
    });
    widget.props.onProgress(_index);
    await _prompt();
  }

  @override
  Widget build(BuildContext context) {
    final round = _round;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
      child: Column(
        children: [
          Entrance.slide(
            key: ValueKey('q-$_index'),
            fromOffset: const Offset(0, -20),
            child: KogoCard(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Column(
                children: [
                  const Text(
                    'Cari objek yang dimulai dengan:',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: KogoColors.gray800),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Loop.pulse(
                        child: Text(
                          round.letter,
                          style: const TextStyle(fontSize: 72, fontWeight: FontWeight.bold, color: KogoColors.purple600, height: 1.1),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SpeakerButton(onTap: () => unawaited(_prompt()), size: 20),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final tile = (constraints.maxWidth - 16) / 2;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (var i = 0; i < round.options.length; i++)
                    Entrance.pop(
                      key: ValueKey('opt-$_index-$i'),
                      delay: Duration(milliseconds: 100 * i),
                      child: _optionCard(round.options[i], tile),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 110,
            child: _correct != null
                ? const FeedbackBadge(correct: true)
                : _wrong.isNotEmpty
                ? FeedbackBadge(key: ValueKey('wrong-$_shake'), correct: false)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _optionCard(VocabItem option, double size) {
    final isCorrect = _correct == option.text;
    final isWrong = _wrong.contains(option.text);
    final colors = isCorrect
        ? KogoColors.correct
        : isWrong
        ? KogoColors.wrong
        : KogoColors.neutralChoice;
    final name = _nameOf(option);
    return Shake(
      trigger: isWrong ? _shake : 0,
      child: Pressable(
        onTap: () => unawaited(_choose(option)),
        semanticLabel: name,
        enabled: !isWrong && _correct == null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: isWrong ? 0.55 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: size,
            height: size,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: KogoColors.br(colors.first, colors.last),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: colors.last.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))],
            ),
            child: Column(
              children: [
                Expanded(child: FittedWordPicture(item: option)),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    name[0].toUpperCase() + name.substring(1),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: KogoColors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
