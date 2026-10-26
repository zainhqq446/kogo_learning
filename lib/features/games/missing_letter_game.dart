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

/// Permainan Huruf Hilang (Missing Letter): lengkapi huruf yang hilang pada
/// kata (proposal Gambar 3.8, 3.16, 3.26). Huruf yang salah dikosongkan
/// kembali sehingga anak dapat mencoba lagi.
class MissingLetterGame extends StatefulWidget {
  const MissingLetterGame({super.key, required this.props});

  final GameProps props;

  @override
  State<MissingLetterGame> createState() => _MissingLetterGameState();
}

class _MissingLetterGameState extends State<MissingLetterGame> {
  late final List<MissingLetterRound> _rounds = GameContent.missingLetter(widget.props.node);
  final _lines = VoiceLines();
  int _index = 0;
  String? _filled;
  bool? _filledCorrect;
  final Set<String> _used = {};
  int _shake = 0;
  bool _busy = false;
  Timer? _clearTimer;

  MissingLetterRound get _round => _rounds[_index];

  @override
  void initState() {
    super.initState();
    unawaited(_intro());
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    super.dispose();
  }

  Future<void> _intro() async {
    final intro = VoiceLines.gameIntro(widget.props.node.game);
    await VoiceService.instance.say(intro.text, mood: intro.mood);
  }

  Future<void> _choose(String letter) async {
    if (_busy) return;
    final round = _round;
    final correct = letter == round.answer;
    unawaited(widget.props.controller.record(itemIndex: _index, target: round.item, answer: letter, correct: correct));
    _clearTimer?.cancel();
    if (correct) {
      _busy = true;
      AudioService.instance.play(Sfx.correct);
      setState(() {
        _filled = letter;
        _filledCorrect = true;
      });
      final line = _lines.correct();
      final word = round.item.letter?.text ?? round.item.text;
      await VoiceService.instance.say('${line.text} $word!', mood: line.mood);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (mounted) await _advance();
    } else {
      AudioService.instance.play(Sfx.wrong);
      setState(() {
        _filled = letter;
        _filledCorrect = false;
        _used.add(letter);
        _shake++;
      });
      final line = _lines.wrong();
      unawaited(VoiceService.instance.say(line.text, mood: line.mood));
      _clearTimer = Timer(const Duration(milliseconds: 900), () {
        if (mounted && _filledCorrect == false) {
          setState(() {
            _filled = null;
            _filledCorrect = null;
          });
        }
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
      _filled = null;
      _filledCorrect = null;
      _used.clear();
      _busy = false;
    });
    widget.props.onProgress(_index);
  }

  @override
  Widget build(BuildContext context) {
    final round = _round;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 96),
      child: Column(
        children: [
          Entrance(
            key: ValueKey('pic-$_index'),
            fromScale: 0,
            fromTurns: -0.5,
            fromOpacity: 0,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: KogoColors.br(KogoColors.red400, KogoColors.pink500),
                borderRadius: BorderRadius.circular(28),
                boxShadow: const [BoxShadow(color: Color(0x33EC4899), blurRadius: 24, offset: Offset(0, 12))],
              ),
              child: WordPicture(item: round.item, size: 124, radius: 20),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Flexible(
                child: Text(
                  'Isi huruf yang hilang:',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: KogoColors.gray700),
                ),
              ),
              const SizedBox(width: 10),
              SpeakerButton(size: 20, onTap: () => unawaited(VoiceService.instance.sayWord(round.item.letter ?? round.item))),
            ],
          ),
          const SizedBox(height: 18),
          Shake(
            trigger: _shake,
            child: WordTiles(
              key: ValueKey('tiles-$_index'),
              word: round.word,
              tileBuilder: (i, size) {
                if (i != round.blankIndex) return LetterTile(size: size, letter: round.word[i]);
                return LetterTile(
                  size: size,
                  letter: _filled,
                  state: _filledCorrect == null
                      ? LetterTileState.blank
                      : _filledCorrect!
                      ? LetterTileState.correct
                      : LetterTileState.wrong,
                );
              },
            ),
          ),
          const SizedBox(height: 26),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            alignment: WrapAlignment.center,
            children: [
              for (var i = 0; i < round.options.length; i++)
                Entrance.pop(
                  key: ValueKey('key-$_index-$i'),
                  delay: Duration(milliseconds: 400 + 100 * i),
                  child: LetterKey(
                    letter: round.options[i],
                    enabled: !_used.contains(round.options[i]) && _filledCorrect != true,
                    onTap: () => unawaited(_choose(round.options[i])),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 110,
            child: _filledCorrect == true
                ? const FeedbackBadge(correct: true, title: 'Sempurna!')
                : _filledCorrect == false
                ? FeedbackBadge(key: ValueKey('w$_shake'), correct: false)
                : null,
          ),
        ],
      ),
    );
  }
}
