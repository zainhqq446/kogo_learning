import 'dart:async';

import 'package:flutter/material.dart';

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

/// Permainan Isi Huruf Kosong (desain Figma "Fill the Blanks"): beberapa
/// huruf vokal dikosongkan; anak mengisinya lalu menekan "Periksa".
class FillBlankGame extends StatefulWidget {
  const FillBlankGame({super.key, required this.props});

  final GameProps props;

  @override
  State<FillBlankGame> createState() => _FillBlankGameState();
}

class _FillBlankGameState extends State<FillBlankGame> {
  late final List<FillBlankRound> _rounds = GameContent.fillBlank(widget.props.node);
  final _lines = VoiceLines();
  int _index = 0;
  final Map<int, String> _answers = {};
  Set<int> _wrongSlots = {};
  bool _checked = false;
  bool _solved = false;
  bool _showHint = false;
  int _shake = 0;

  FillBlankRound get _round => _rounds[_index];
  bool get _complete => _round.blanks.every(_answers.containsKey);

  @override
  void initState() {
    super.initState();
    unawaited(_intro());
  }

  Future<void> _intro() async {
    final intro = VoiceLines.gameIntro(widget.props.node.game);
    await VoiceService.instance.say(intro.text, mood: intro.mood);
    if (mounted) await VoiceService.instance.sayWord(_round.item);
  }

  void _type(String letter) {
    if (_solved) return;
    final slot = _round.blanks.where((b) => !_answers.containsKey(b)).firstOrNull;
    if (slot == null) return;
    AudioService.instance.play(Sfx.pop);
    setState(() {
      _answers[slot] = letter;
      _checked = false;
      _wrongSlots = {};
    });
  }

  void _erase() {
    if (_solved || _answers.isEmpty) return;
    final last = _round.blanks.lastWhere(_answers.containsKey, orElse: () => -1);
    if (last < 0) return;
    AudioService.instance.play(Sfx.tap);
    setState(() {
      _answers.remove(last);
      _checked = false;
      _wrongSlots = {};
    });
  }

  Future<void> _check() async {
    if (!_complete || _solved) return;
    final round = _round;
    final wrong = round.blanks.where((b) => _answers[b] != round.word[b]).toSet();
    final filled = [for (var i = 0; i < round.word.length; i++) _answers[i] ?? round.word[i]].join();
    final correct = wrong.isEmpty;
    unawaited(widget.props.controller.record(itemIndex: _index, target: round.item, answer: filled.toLowerCase(), correct: correct));
    setState(() {
      _checked = true;
      _wrongSlots = wrong;
      _solved = correct;
    });
    if (correct) {
      AudioService.instance.play(Sfx.correct);
      final line = _lines.correct();
      await VoiceService.instance.say('${line.text} ${round.item.text}!', mood: line.mood);
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) await _advance();
    } else {
      AudioService.instance.play(Sfx.wrong);
      setState(() {
        _shake++;
        _showHint = true;
      });
      final line = _lines.wrong();
      await VoiceService.instance.say(line.text, mood: line.mood);
      // Huruf yang salah dikosongkan kembali; huruf yang benar tetap.
      if (!mounted || _solved) return;
      setState(() {
        for (final slot in wrong) {
          _answers.remove(slot);
        }
        _checked = false;
        _wrongSlots = {};
      });
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
      _answers.clear();
      _wrongSlots = {};
      _checked = false;
      _solved = false;
      _showHint = false;
    });
    widget.props.onProgress(_index);
    await VoiceService.instance.sayWord(_round.item);
  }

  @override
  Widget build(BuildContext context) {
    final round = _round;
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 96),
          child: Column(
            children: [
              Entrance(
                key: ValueKey('pic-$_index'),
                fromScale: 0,
                fromTurns: -0.5,
                fromOpacity: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: KogoColors.br(KogoColors.green400, KogoColors.teal500),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: KogoColors.white, width: 4),
                    boxShadow: const [BoxShadow(color: Color(0x3314B8A6), blurRadius: 24, offset: Offset(0, 12))],
                  ),
                  child: WordPicture(item: round.item, size: 116, radius: 20),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SpeakerButton(size: 20, onTap: () => unawaited(VoiceService.instance.spell(round.item))),
                  const SizedBox(width: 10),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: _showHint ? 1 : 0,
                    child: Text(
                      '(${round.item.text})',
                      style: const TextStyle(fontSize: 18, color: KogoColors.gray600, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Isi huruf yang kosong! ✏️',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: KogoColors.gray700),
              ),
              const SizedBox(height: 12),
              Shake(
                trigger: _shake,
                child: WordTiles(
                  key: ValueKey('tiles-$_index'),
                  word: round.word,
                  maxTile: 56,
                  tileBuilder: (i, size) {
                    if (!round.blanks.contains(i)) return LetterTile(size: size, letter: round.word[i]);
                    final value = _answers[i];
                    final state = value == null
                        ? LetterTileState.blank
                        : _solved
                        ? LetterTileState.correct
                        : _checked && _wrongSlots.contains(i)
                        ? LetterTileState.wrong
                        : LetterTileState.plain;
                    return value == null
                        ? Loop(
                            duration: const Duration(milliseconds: 1500),
                            opacity: const [0.6, 1, 0.6],
                            child: LetterTile(size: size, state: state),
                          )
                        : LetterTile(size: size, letter: value, state: state);
                  },
                ),
              ),
              const SizedBox(height: 18),
              if (!_solved)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final key = ((constraints.maxWidth - 4 * 10) / 5).clamp(44.0, 60.0);
                    return Column(
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: [
                            for (var i = 0; i < round.keyboard.length; i++)
                              Entrance.pop(
                                key: ValueKey('k-$_index-$i'),
                                delay: Duration(milliseconds: 300 + 50 * i),
                                child: LetterKey(letter: round.keyboard[i], size: key, onTap: () => _type(round.keyboard[i])),
                              ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: GradientButton(
                                label: 'Hapus',
                                icon: Icons.backspace_rounded,
                                colors: const [KogoColors.orange400, KogoColors.red500],
                                fontSize: 16,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                onTap: _answers.isEmpty ? null : _erase,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GradientButton(
                                label: 'Periksa',
                                icon: Icons.check_circle_rounded,
                                fontSize: 16,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                onTap: _complete ? () => unawaited(_check()) : null,
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                )
              else
                const FeedbackBadge(correct: true, title: 'Sempurna!', subtitle: 'Kerja bagus! 🌟'),
            ],
          ),
        ),
        if (_solved) const Positioned.fill(child: ConfettiRain(count: 18)),
      ],
    );
  }
}
