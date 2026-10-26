import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../curriculum/vocabulary.dart';
import '../motion/motion.dart';
import '../theme/kogo_colors.dart';

/// Latar halaman bergradien vertikal dengan dekorasi emoji melayang
/// (bintang, kilau, awan) seperti pada desain Figma.
class KogoBackground extends StatelessWidget {
  const KogoBackground({super.key, required this.colors, required this.child, this.decorations = const []});

  final List<Color> colors;
  final Widget child;
  final List<FloatingDecoration> decorations;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: KogoColors.b(colors)),
      child: Stack(
        children: [
          for (final d in decorations)
            Positioned(
              left: d.left,
              right: d.right,
              top: d.top,
              bottom: d.bottom,
              child: IgnorePointer(
                child: Opacity(
                  opacity: d.opacity,
                  child: Loop(
                    duration: d.duration,
                    delay: d.delay,
                    dy: [0, -d.lift, 0],
                    dx: d.drift == 0 ? const [0] : [0, d.drift, 0],
                    rotateDeg: d.spin ? const [0, 360] : [0, d.tilt, 0],
                    linear: d.spin,
                    child: Text(d.emoji, style: TextStyle(fontSize: d.size)),
                  ),
                ),
              ),
            ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class FloatingDecoration {
  const FloatingDecoration(
    this.emoji, {
    this.left,
    this.right,
    this.top,
    this.bottom,
    this.size = 32,
    this.opacity = 1,
    this.lift = 20,
    this.drift = 0,
    this.tilt = 10,
    this.spin = false,
    this.duration = const Duration(seconds: 3),
    this.delay = Duration.zero,
  });

  final String emoji;
  final double? left, right, top, bottom;
  final double size;
  final double opacity;
  final double lift;
  final double drift;
  final double tilt;
  final bool spin;
  final Duration duration;
  final Duration delay;
}

/// Header putih dengan tombol "Kembali" dan judul di tengah (Figma activity header).
class KogoHeader extends StatelessWidget {
  const KogoHeader({super.key, required this.title, this.onBack, this.trailing, this.translucent = false});

  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final bool translucent;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: translucent ? KogoColors.white.withValues(alpha: 0.9) : KogoColors.white,
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              SizedBox(
                width: 108,
                child: onBack == null
                    ? null
                    : Pressable(
                        onTap: onBack,
                        semanticLabel: 'Kembali',
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                          child: Row(
                            children: [
                              Icon(Icons.chevron_left_rounded, size: 28, color: KogoColors.gray700),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'Kembali',
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: KogoColors.gray700),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    title,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: KogoColors.gray800),
                  ),
                ),
              ),
              SizedBox(
                width: 108,
                child: Align(alignment: Alignment.centerRight, child: trailing),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tombol pil bergradien (contoh "Lanjutkan ✓", "Ulangi", "Selesai").
class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    required this.onTap,
    this.colors = const [KogoColors.green500, KogoColors.emerald600],
    this.icon,
    this.expand = false,
    this.fontSize = 18,
    this.padding = const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
  });

  final String label;
  final VoidCallback? onTap;
  final List<Color> colors;
  final IconData? icon;
  final bool expand;
  final double fontSize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[Icon(icon, color: enabled ? KogoColors.white : KogoColors.gray500, size: fontSize + 4), const SizedBox(width: 8)],
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: enabled ? KogoColors.white : KogoColors.gray500),
          ),
        ),
      ],
    );
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      pressedScale: 0.95,
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: padding,
        decoration: BoxDecoration(
          gradient: enabled ? KogoColors.r(colors.first, colors.last) : null,
          color: enabled ? null : KogoColors.gray300,
          borderRadius: BorderRadius.circular(999),
          boxShadow: enabled ? [BoxShadow(color: colors.last.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))] : null,
        ),
        child: content,
      ),
    );
  }
}

/// Gambar kosakata. Gambar dataset memuat tulisan kata di bagian bawah,
/// sehingga hanya area gambar (jendela persegi atas) yang ditampilkan agar
/// jawaban tidak terlihat pada permainan menebak.
class WordPicture extends StatelessWidget {
  const WordPicture({super.key, required this.item, this.size = 120, this.radius = 24});

  final VocabItem item;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final asset = item.pictureAsset;
    final Widget picture;
    if (asset != null) {
      picture = FittedBox(
        fit: BoxFit.cover,
        child: ClipRect(
          child: Align(
            alignment: const Alignment(0, -0.733),
            widthFactor: 0.70,
            heightFactor: 0.70,
            child: Image.asset(
              asset,
              width: 512,
              height: 512,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) => _EmojiFallback(emoji: item.pictureEmoji ?? '🖼️', size: 512),
            ),
          ),
        ),
      );
    } else {
      picture = _EmojiFallback(emoji: item.pictureEmoji ?? '🖼️', size: size);
    }
    return Semantics(
      image: true,
      label: 'Gambar',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox.square(dimension: size, child: picture),
      ),
    );
  }
}

/// [WordPicture] persegi yang otomatis mengisi ruang tersedia (untuk kartu).
class FittedWordPicture extends StatelessWidget {
  const FittedWordPicture({super.key, required this.item, this.radius = 18});

  final VocabItem item;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final side = math.min(box.maxWidth, box.maxHeight);
        return Center(
          child: WordPicture(item: item, size: side.isFinite ? side : 96, radius: radius),
        );
      },
    );
  }
}

class _EmojiFallback extends StatelessWidget {
  const _EmojiFallback({required this.emoji, required this.size});

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: KogoColors.sky100,
      alignment: Alignment.center,
      child: Text(emoji, style: TextStyle(fontSize: size * 0.6)),
    );
  }
}

/// Maskot beruang Kogo yang bergoyang (🐻 pada desain Figma).
class Mascot extends StatelessWidget {
  const Mascot({super.key, this.size = 64, this.speaking = false, this.onTap});

  final double size;
  final bool speaking;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bear = Loop(
      duration: Duration(milliseconds: speaking ? 600 : 2400),
      dy: speaking ? const [0, -6, 0] : const [0, -15, 0],
      rotateDeg: speaking ? const [0, 6, -6, 0] : const [0, 10, -10, 0],
      scale: speaking ? const [1, 1.08, 1] : const [1],
      child: Text('🐻', style: TextStyle(fontSize: size)),
    );
    if (onTap == null) return ExcludeSemantics(child: bear);
    return Pressable(onTap: onTap, semanticLabel: 'Kogo si beruang', child: bear);
  }
}

/// Deretan bintang terisi/kosong.
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.stars, this.max = 3, this.size = 18});

  final int stars;
  final int max;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$stars dari $max bintang',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < max; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Icon(
                i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                size: size,
                color: i < stars ? KogoColors.yellow500 : KogoColors.gray300,
              ),
            ),
        ],
      ),
    );
  }
}

/// Kartu putih membulat dengan bayangan lembut (`bg-white rounded-3xl shadow-xl`).
class KogoCard extends StatelessWidget {
  const KogoCard({super.key, required this.child, this.padding = const EdgeInsets.all(24), this.margin});

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: KogoColors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 24, offset: Offset(0, 10))],
      ),
      // Lapisan Material agar ListTile/InkWell di dalam kartu tetap menampilkan efek sentuh.
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// Lingkaran ikon bergradien (avatar statistik, lencana hadiah).
class GradientCircle extends StatelessWidget {
  const GradientCircle({super.key, required this.colors, required this.child, this.size = 48, this.border = 0});

  final List<Color> colors;
  final Widget child;
  final double size;
  final double border;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: KogoColors.br(colors.first, colors.last),
        border: border > 0 ? Border.all(color: KogoColors.white, width: border) : null,
        boxShadow: [BoxShadow(color: colors.last.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// Gerbang orang tua sederhana (soal penjumlahan) sebelum membuka menu
/// pengaturan/peneliti agar tidak diubah anak secara tidak sengaja.
class ParentalGate {
  ParentalGate._();

  static Future<bool> ask(BuildContext context, {int? seed}) async {
    final random = math.Random(seed);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ParentalGateDialog(a: 3 + random.nextInt(6), b: 2 + random.nextInt(6)),
    );
    if (ok == false && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Jawaban belum tepat.')));
    }
    return ok ?? false;
  }
}

class _ParentalGateDialog extends StatefulWidget {
  const _ParentalGateDialog({required this.a, required this.b});

  final int a;
  final int b;

  @override
  State<_ParentalGateDialog> createState() => _ParentalGateDialogState();
}

class _ParentalGateDialogState extends State<_ParentalGateDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(int.tryParse(_controller.text.trim()) == widget.a + widget.b);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Khusus Orang Tua/Guru'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Berapa hasil ${widget.a} + ${widget.b}?'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Jawaban'),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
        FilledButton(onPressed: _submit, child: const Text('Lanjut')),
      ],
    );
  }
}
