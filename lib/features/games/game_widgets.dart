import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/motion/motion.dart';
import '../../core/theme/kogo_colors.dart';

/// Tombol speaker biru kecil untuk mendengar ulang (Figma: `bg-blue-500 p-3 rounded-full`).
class SpeakerButton extends StatelessWidget {
  const SpeakerButton({super.key, required this.onTap, this.size = 24, this.label = 'Dengarkan lagi'});

  final VoidCallback onTap;
  final double size;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      pressedScale: 0.9,
      child: Container(
        padding: EdgeInsets.all(size * 0.5),
        decoration: const BoxDecoration(
          color: KogoColors.blue500,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: Color(0x553B82F6), blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: Icon(Icons.volume_up_rounded, color: KogoColors.white, size: size),
      ),
    );
  }
}

/// Menggoyangkan anak widget ke kiri-kanan setiap [trigger] berubah (jawaban salah).
class Shake extends StatefulWidget {
  const Shake({super.key, required this.trigger, required this.child});

  final int trigger;
  final Widget child;

  @override
  State<Shake> createState() => _ShakeState();
}

class _ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void didUpdateWidget(Shake old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger && Motion.of(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final dx = math.sin(_c.value * math.pi * 6) * 10 * (1 - _c.value);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
    );
  }
}

/// Satu ubin huruf pada kata.
class LetterTile extends StatelessWidget {
  const LetterTile({super.key, required this.size, this.letter, this.state = LetterTileState.plain});

  final double size;
  final String? letter;
  final LetterTileState state;

  @override
  Widget build(BuildContext context) {
    final height = size * 1.2;
    final BoxDecoration decoration;
    Color textColor = KogoColors.gray800;
    switch (state) {
      case LetterTileState.plain:
        decoration = BoxDecoration(color: KogoColors.white, borderRadius: BorderRadius.circular(size * 0.25), boxShadow: _shadow);
      case LetterTileState.blank:
        decoration = BoxDecoration(
          gradient: KogoColors.br(KogoColors.yellow300, KogoColors.orange400),
          borderRadius: BorderRadius.circular(size * 0.25),
          border: Border.all(color: KogoColors.orange600, width: 3),
          boxShadow: _shadow,
        );
        textColor = KogoColors.orange600;
      case LetterTileState.correct:
        decoration = BoxDecoration(
          gradient: KogoColors.br(KogoColors.green400, KogoColors.emerald500),
          borderRadius: BorderRadius.circular(size * 0.25),
          boxShadow: _shadow,
        );
        textColor = KogoColors.white;
      case LetterTileState.wrong:
        decoration = BoxDecoration(
          gradient: KogoColors.br(KogoColors.red400, KogoColors.pink500),
          borderRadius: BorderRadius.circular(size * 0.25),
          boxShadow: _shadow,
        );
        textColor = KogoColors.white;
    }
    return Container(
      width: size,
      height: height,
      decoration: decoration,
      alignment: Alignment.center,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, a) => ScaleTransition(
          scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
          child: RotationTransition(turns: Tween(begin: -0.25, end: 0.0).animate(a), child: child),
        ),
        child: Text(
          letter ?? (state == LetterTileState.blank ? '?' : ''),
          key: ValueKey('${letter ?? '?'}-$state'),
          style: TextStyle(fontSize: size * 0.5, fontWeight: FontWeight.bold, color: textColor),
        ),
      ),
    );
  }

  static const _shadow = [BoxShadow(color: Color(0x1F000000), blurRadius: 10, offset: Offset(0, 4))];
}

enum LetterTileState { plain, blank, correct, wrong }

/// Menata huruf-huruf sebuah kata/frasa. Ukuran ubin menyesuaikan lebar layar
/// dan frasa dipecah per kata agar kata panjang tetap muat.
class WordTiles extends StatelessWidget {
  const WordTiles({super.key, required this.word, required this.tileBuilder, this.maxTile = 64});

  final String word;
  final Widget Function(int index, double size) tileBuilder;
  final double maxTile;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final groups = <List<int>>[];
        var current = <int>[];
        for (var i = 0; i < word.length; i++) {
          if (word[i] == ' ') {
            groups.add(current);
            current = [];
          } else {
            current.add(i);
          }
        }
        groups.add(current);
        final longest = groups.fold<int>(0, (m, g) => math.max(m, g.length));
        const gap = 8.0;
        final fit = (constraints.maxWidth - gap * (longest - 1)) / math.max(longest, 1);
        final size = fit.clamp(26.0, maxTile);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final group in groups)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final i in group)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: gap / 2),
                        child: word[i] == '-'
                            ? SizedBox(
                                width: size * 0.5,
                                child: Text(
                                  '-',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: size * 0.6, fontWeight: FontWeight.bold),
                                ),
                              )
                            : Entrance(
                                delay: Duration(milliseconds: 60 * i),
                                fromOffset: const Offset(0, -20),
                                fromOpacity: 0,
                                curve: Curves.easeOut,
                                child: tileBuilder(i, size),
                              ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Tombol huruf pilihan (Figma: `bg-gradient-to-br from-purple-400 to-pink-500 rounded-2xl`).
class LetterKey extends StatelessWidget {
  const LetterKey({super.key, required this.letter, required this.onTap, this.size = 64, this.enabled = true});

  final String letter;
  final VoidCallback onTap;
  final double size;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: enabled ? onTap : null,
      semanticLabel: 'Huruf $letter',
      pressedScale: 0.88,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: enabled ? 1 : 0.35,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: KogoColors.br(KogoColors.purple400, KogoColors.pink500),
            borderRadius: BorderRadius.circular(size * 0.28),
            boxShadow: const [BoxShadow(color: Color(0x40EC4899), blurRadius: 10, offset: Offset(0, 4))],
          ),
          child: Text(
            letter,
            style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.bold, color: KogoColors.white),
          ),
        ),
      ),
    );
  }
}
