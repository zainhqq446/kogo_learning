import 'dart:async';
import 'dart:math' as math;

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
import 'game_widgets.dart';

/// Permainan Cocokkan (Matching Object): pasangkan kata dengan gambarnya
/// (proposal Gambar 3.9, 3.17, 3.27). Indikator "Cocok: x / n".
class MatchingGame extends StatefulWidget {
  const MatchingGame({super.key, required this.props});

  final GameProps props;

  @override
  State<MatchingGame> createState() => _MatchingGameState();
}

class _MatchingGameState extends State<MatchingGame> {
  late final _board = GameContent.matching(widget.props.node);
  late final List<VocabItem> _items = widget.props.node.unit.items;
  final _lines = VoiceLines();
  final Set<String> _matched = {};
  String? _word;
  String? _picture;
  String? _mismatch;
  int _shake = 0;
  bool _celebrate = false;

  @override
  void initState() {
    super.initState();
    final intro = VoiceLines.gameIntro(widget.props.node.game);
    unawaited(VoiceService.instance.say(intro.text, mood: intro.mood));
  }

  String _label(VocabItem item) => item.display;

  void _tapWord(VocabItem item) {
    if (_matched.contains(item.text) || _celebrate) return;
    AudioService.instance.play(Sfx.tap);
    unawaited(VoiceService.instance.sayWord(item));
    setState(() {
      _word = item.text;
      _mismatch = null;
    });
    _check();
  }

  void _tapPicture(VocabItem item) {
    if (_matched.contains(item.text) || _celebrate) return;
    AudioService.instance.play(Sfx.tap);
    setState(() {
      _picture = item.text;
      _mismatch = null;
    });
    _check();
  }

  void _check() {
    final word = _word;
    final picture = _picture;
    if (word == null || picture == null) return;
    final index = _items.indexWhere((i) => i.text == word);
    final target = _items[index];
    final correct = word == picture;
    unawaited(widget.props.controller.record(itemIndex: index, target: target, answer: picture, correct: correct));
    if (correct) {
      AudioService.instance.play(Sfx.correct);
      setState(() {
        _matched.add(word);
        _word = null;
        _picture = null;
      });
      widget.props.onProgress(_matched.length);
      if (_matched.length == _items.length) {
        unawaited(_finish());
      } else {
        final line = _lines.correct();
        unawaited(VoiceService.instance.say(line.text, mood: line.mood));
      }
    } else {
      AudioService.instance.play(Sfx.wrong);
      setState(() {
        _mismatch = word;
        _shake++;
        _word = null;
        _picture = null;
      });
      final line = _lines.wrong();
      unawaited(VoiceService.instance.say(line.text, mood: line.mood));
    }
  }

  Future<void> _finish() async {
    setState(() => _celebrate = true);
    AudioService.instance.play(Sfx.star);
    await VoiceService.instance.say(VoiceLines.allMatched.text, mood: VoiceLines.allMatched.mood);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (mounted) await widget.props.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final n = _items.length;
            final tileHeight = math.min(96.0, math.max(64.0, (constraints.maxHeight - 220) / n - 14));
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
              child: Column(
                children: [
                  const Entrance.slide(
                    child: Text(
                      'Cocokkan kata dengan gambar! 🎯',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: KogoColors.gray700),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            for (var i = 0; i < _board.words.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Entrance(
                                  delay: Duration(milliseconds: 100 * i),
                                  fromOffset: const Offset(-50, 0),
                                  fromOpacity: 0,
                                  curve: Curves.easeOutCubic,
                                  child: _tile(
                                    item: _board.words[i],
                                    height: tileHeight,
                                    selected: _word == _board.words[i].text,
                                    onTap: () => _tapWord(_board.words[i]),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                        child: Text(
                                          _label(_board.words[i]),
                                          style: TextStyle(
                                            fontSize: _board.words[i].isLetter ? 40 : 22,
                                            fontWeight: FontWeight.bold,
                                            color: _matched.contains(_board.words[i].text) || _word == _board.words[i].text
                                                ? KogoColors.white
                                                : KogoColors.gray800,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          children: [
                            for (var i = 0; i < _board.pictures.length; i++)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Entrance(
                                  delay: Duration(milliseconds: 100 * i),
                                  fromOffset: const Offset(50, 0),
                                  fromOpacity: 0,
                                  curve: Curves.easeOutCubic,
                                  child: _tile(
                                    item: _board.pictures[i],
                                    height: tileHeight,
                                    selected: _picture == _board.pictures[i].text,
                                    onTap: () => _tapPicture(_board.pictures[i]),
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: FittedWordPicture(item: _board.pictures[i], radius: 14),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cocok: ${_matched.length} / ${_items.length}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: KogoColors.gray600),
                  ),
                ],
              ),
            );
          },
        ),
        if (_celebrate)
          Positioned.fill(
            child: IgnorePointer(
              child: Entrance(
                fromOpacity: 0,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.5),
                  alignment: Alignment.center,
                  child: Loop(
                    duration: const Duration(seconds: 1),
                    scale: const [1, 1.2, 1],
                    rotateDeg: const [0, 10, -10, 0],
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('🎉', style: TextStyle(fontSize: 110)),
                        Text(
                          'Sempurna!',
                          style: TextStyle(fontSize: 38, fontWeight: FontWeight.bold, color: KogoColors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _tile({required VocabItem item, required double height, required bool selected, required VoidCallback onTap, required Widget child}) {
    final matched = _matched.contains(item.text);
    final List<Color>? colors = matched
        ? KogoColors.correct
        : selected
        ? KogoColors.selected
        : null;
    return Shake(
      trigger: _mismatch == item.text ? _shake : 0,
      child: Pressable(
        onTap: matched ? null : onTap,
        semanticLabel: item.text,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 200),
          scale: selected ? 1.05 : 1,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: height,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors == null ? KogoColors.white : null,
              gradient: colors == null ? null : KogoColors.br(colors.first, colors.last),
              borderRadius: BorderRadius.circular(18),
              boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 12, offset: Offset(0, 5))],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
