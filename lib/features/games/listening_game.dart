import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/curriculum/vocabulary.dart';
import '../../core/motion/motion.dart';
import '../../core/theme/kogo_colors.dart';
import '../../services/audio/audio_service.dart';
import '../../services/audio/voice_lines.dart';
import '../../services/audio/voice_service.dart';
import 'game_content.dart';
import 'game_page.dart';
import 'game_scaffold.dart';
import 'game_widgets.dart';

/// Permainan Dengar & Pilih (desain Figma "Listen Carefully"): dengarkan
/// kata, lalu pilih tulisan yang sesuai.
class ListeningGame extends StatefulWidget {
  const ListeningGame({super.key, required this.props});

  final GameProps props;

  @override
  State<ListeningGame> createState() => _ListeningGameState();
}

class _ListeningGameState extends State<ListeningGame> {
  late final List<ChoiceRound> _rounds = GameContent.listening(widget.props.node);
  final _lines = VoiceLines();
  int _index = 0;
  final Set<String> _wrong = {};
  String? _correct;
  int _shake = 0;
  bool _playing = false;
  bool _busy = false;

  ChoiceRound get _round => _rounds[_index];

  @override
  void initState() {
    super.initState();
    unawaited(_intro());
  }

  Future<void> _intro() async {
    final intro = VoiceLines.gameIntro(widget.props.node.game);
    await VoiceService.instance.say(intro.text, mood: intro.mood);
    if (mounted) await _play();
  }

  Future<void> _play() async {
    setState(() => _playing = true);
    await VoiceService.instance.sayWord(_round.target);
    if (mounted) setState(() => _playing = false);
  }

  Future<void> _choose(VocabItem option) async {
    if (_busy || _correct != null || _wrong.contains(option.text)) return;
    final round = _round;
    final correct = option.text == round.target.text;
    unawaited(widget.props.controller.record(itemIndex: _index, target: round.target, answer: option.text, correct: correct));
    if (correct) {
      _busy = true;
      AudioService.instance.play(Sfx.correct);
      setState(() => _correct = option.text);
      final line = _lines.correct();
      await VoiceService.instance.say(line.text, mood: line.mood);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted) await _advance();
    } else {
      AudioService.instance.play(Sfx.wrong);
      setState(() {
        _wrong.add(option.text);
        _shake++;
      });
      final line = _lines.wrong();
      await VoiceService.instance.say(line.text, mood: line.mood);
      if (mounted && _correct == null) await _play();
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
    await _play();
  }

  @override
  Widget build(BuildContext context) {
    final round = _round;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
      child: Column(
        children: [
          const Entrance.slide(
            child: Text(
              'Dengarkan baik-baik dan pilih kata yang kamu dengar! 👂',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: KogoColors.gray700),
            ),
          ),
          const SizedBox(height: 28),
          Semantics(
            button: true,
            label: 'Putar suara',
            child: Pressable(
              onTap: () => unawaited(_play()),
              child: _playing
                  ? Loop(duration: const Duration(milliseconds: 500), scale: const [1, 1.15, 1], rotateDeg: const [0, 8, -8, 0], child: _playButton(true))
                  : _playButton(false),
            ),
          ),
          const SizedBox(height: 36),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 16) / 2;
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (var i = 0; i < round.options.length; i++)
                    Entrance.pop(
                      key: ValueKey('opt-$_index-$i'),
                      delay: Duration(milliseconds: 100 * i),
                      child: _option(round.options[i], width),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 110,
            child: _correct != null
                ? const FeedbackBadge(correct: true, title: 'Luar Biasa!')
                : _wrong.isNotEmpty
                ? FeedbackBadge(key: ValueKey('w$_shake'), correct: false)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _playButton(bool playing) {
    return Container(
      width: 150,
      height: 150,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: playing ? KogoColors.br(KogoColors.orange500, KogoColors.red500) : KogoColors.br(KogoColors.blue500, KogoColors.purple600),
        boxShadow: [BoxShadow(color: (playing ? KogoColors.red500 : KogoColors.purple600).withValues(alpha: 0.4), blurRadius: 30, offset: const Offset(0, 12))],
      ),
      child: Icon(playing ? Icons.volume_up_rounded : Icons.play_arrow_rounded, size: 80, color: KogoColors.white),
    );
  }

  Widget _option(VocabItem option, double width) {
    final isCorrect = _correct == option.text;
    final isWrong = _wrong.contains(option.text);
    final colors = isCorrect
        ? KogoColors.correct
        : isWrong
        ? KogoColors.wrong
        : KogoColors.neutralChoice;
    return Shake(
      trigger: isWrong ? _shake : 0,
      child: Pressable(
        onTap: () => unawaited(_choose(option)),
        enabled: !isWrong && _correct == null,
        semanticLabel: option.text,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: isWrong ? 0.55 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: width,
            height: 96,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: KogoColors.br(colors.first, colors.last),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: colors.last.withValues(alpha: 0.35), blurRadius: 12, offset: const Offset(0, 5))],
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                option.display,
                style: TextStyle(fontSize: option.isLetter ? 40 : 22, fontWeight: FontWeight.bold, color: KogoColors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
