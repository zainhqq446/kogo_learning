import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Pengaturan global animasi.
///
/// Animasi berulang (bob, pulse, dsb.) otomatis dimatikan bila
/// [enabled] bernilai `false` (dipakai di widget test agar `pumpAndSettle`
/// tidak menunggu animasi tak berujung) atau bila pengguna mengaktifkan
/// "kurangi animasi" di pengaturan aksesibilitas perangkat.
class Motion {
  Motion._();

  static bool enabled = true;

  static bool of(BuildContext context) => enabled && !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  /// Kurva pegas yang meniru `type: "spring", stiffness: 200` pada desain Figma.
  static const Curve spring = Curves.easeOutBack;
}

/// Animasi masuk satu kali: skala, rotasi, geser, dan opasitas dengan jeda.
class Entrance extends StatefulWidget {
  const Entrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 600),
    this.curve = Motion.spring,
    this.fromScale = 1,
    this.fromTurns = 0,
    this.fromOffset = Offset.zero,
    this.fromOpacity = 0,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final Curve curve;
  final double fromScale;

  /// Rotasi awal dalam putaran penuh (contoh: -0.5 = -180°).
  final double fromTurns;
  final Offset fromOffset;
  final double fromOpacity;

  /// Preset "spring pop" (scale 0 → 1) yang sering dipakai pada Figma.
  const Entrance.pop({super.key, required this.child, this.delay = Duration.zero, this.duration = const Duration(milliseconds: 600), this.fromTurns = 0})
    : curve = Motion.spring,
      fromScale = 0,
      fromOffset = Offset.zero,
      fromOpacity = 0;

  /// Preset geser + fade (contoh `initial: { y: 20, opacity: 0 }`).
  const Entrance.slide({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 450),
    this.fromOffset = const Offset(0, 20),
  }) : curve = Curves.easeOutCubic,
       fromScale = 1,
       fromTurns = 0,
       fromOpacity = 0;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.duration);
  Timer? _delayTimer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!Motion.of(context)) {
      _controller.value = 1;
    } else if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _delayTimer = Timer(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = widget.curve.transform(_controller.value);
        final linear = _controller.value;
        final opacity = (widget.fromOpacity + (1 - widget.fromOpacity) * linear).clamp(0.0, 1.0);
        final scale = widget.fromScale + (1 - widget.fromScale) * t;
        final offset = Offset.lerp(widget.fromOffset, Offset.zero, t)!;
        final angle = widget.fromTurns * (1 - t) * 2 * math.pi;
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: offset,
            child: Transform.rotate(
              angle: angle,
              child: Transform.scale(scale: math.max(scale, 0), child: child),
            ),
          ),
        );
      },
    );
  }
}

/// Animasi berulang berbasis keyframe (setara `animate: { y: [0, -20, 0] }`
/// dengan `repeat: Infinity` pada framer-motion).
class Loop extends StatefulWidget {
  const Loop({
    super.key,
    required this.child,
    this.duration = const Duration(seconds: 2),
    this.delay = Duration.zero,
    this.dy = const [0],
    this.dx = const [0],
    this.rotateDeg = const [0],
    this.scale = const [1],
    this.opacity = const [1],
    this.linear = false,
  });

  final Widget child;
  final Duration duration;
  final Duration delay;
  final List<double> dy;
  final List<double> dx;
  final List<double> rotateDeg;
  final List<double> scale;
  final List<double> opacity;

  /// `true` untuk rotasi konstan (contoh bintang berputar 360°).
  final bool linear;

  /// Gerak naik-turun lembut seperti maskot beruang di Figma.
  Loop.bob({
    super.key,
    required this.child,
    this.duration = const Duration(seconds: 2),
    this.delay = Duration.zero,
    double height = 20,
    this.rotateDeg = const [0],
  }) : dy = [0, -height, 0],
       dx = const [0],
       scale = const [1],
       opacity = const [1],
       linear = false;

  /// Denyut skala (contoh huruf target "A" pada Cari Objek).
  Loop.pulse({super.key, required this.child, this.duration = const Duration(seconds: 2), this.delay = Duration.zero, double to = 1.1})
    : dy = const [0],
      dx = const [0],
      rotateDeg = const [0],
      scale = [1, to, 1],
      opacity = const [1],
      linear = false;

  @override
  State<Loop> createState() => _LoopState();
}

class _LoopState extends State<Loop> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.duration);
  Timer? _delayTimer;
  bool _active = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldAnimate = Motion.of(context);
    if (shouldAnimate == _active) return;
    _active = shouldAnimate;
    _delayTimer?.cancel();
    if (!shouldAnimate) {
      _controller.stop();
      _controller.value = 0;
      return;
    }
    if (widget.delay == Duration.zero) {
      _controller.repeat();
    } else {
      _delayTimer = Timer(widget.delay, () {
        if (mounted && _active) _controller.repeat();
      });
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  double _sample(List<double> frames, double t) {
    if (frames.length == 1) return frames.first;
    final segments = frames.length - 1;
    final pos = t * segments;
    final index = math.min(pos.floor(), segments - 1);
    final local = pos - index;
    final eased = widget.linear ? local : Curves.easeInOut.transform(local);
    return frames[index] + (frames[index + 1] - frames[index]) * eased;
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        return Opacity(
          opacity: _sample(widget.opacity, t).clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(_sample(widget.dx, t), _sample(widget.dy, t)),
            child: Transform.rotate(
              angle: _sample(widget.rotateDeg, t) * math.pi / 180,
              child: Transform.scale(scale: _sample(widget.scale, t), child: child),
            ),
          ),
        );
      },
    );
  }
}

/// Pembungkus tombol dengan efek `whileTap: { scale }` dan semantik aksesibel.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap, this.pressedScale = 0.92, this.semanticLabel, this.enabled = true});

  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final String? semanticLabel;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  bool get _interactive => widget.enabled && widget.onTap != null;

  void _setPressed(bool value) {
    if (_pressed == value || !mounted) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    // Label eksplisit menggantikan teks anak agar pembaca layar tidak membaca ganda.
    return Semantics(
      button: true,
      enabled: _interactive,
      label: widget.semanticLabel,
      excludeSemantics: widget.semanticLabel != null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _interactive ? (_) => _setPressed(true) : null,
        onTapCancel: _interactive ? () => _setPressed(false) : null,
        onTapUp: _interactive ? (_) => _setPressed(false) : null,
        onTap: _interactive ? widget.onTap : null,
        child: AnimatedScale(
          scale: _pressed ? widget.pressedScale : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Hujan konfeti emoji (🎊 🎉 ⭐ ✨) saat anak berhasil.
class ConfettiRain extends StatefulWidget {
  const ConfettiRain({super.key, this.count = 20, this.seed = 7});

  final int count;
  final int seed;

  @override
  State<ConfettiRain> createState() => _ConfettiRainState();
}

class _ConfettiRainState extends State<ConfettiRain> with SingleTickerProviderStateMixin {
  static const _symbols = ['🎊', '🎉', '⭐', '✨'];
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    final random = math.Random(widget.seed);
    _particles = List.generate(widget.count, (i) {
      return _Particle(
        x: random.nextDouble(),
        start: random.nextDouble() * 0.2,
        speed: 0.55 + random.nextDouble() * 0.45,
        spin: (random.nextDouble() - 0.5) * 4,
        symbol: _symbols[random.nextInt(_symbols.length)],
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.of(context) && !_controller.isAnimating && _controller.value == 0) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Motion.of(context)) return const SizedBox.shrink();
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              return Stack(
                children: [
                  for (final p in _particles)
                    if (t >= p.start)
                      Positioned(
                        left: p.x * (w - 32),
                        top: -40 + ((t - p.start) / (1 - p.start) / p.speed).clamp(0.0, 1.0) * (h + 80),
                        child: Transform.rotate(
                          angle: (t - p.start) * p.spin * 2 * math.pi,
                          child: Text(p.symbol, style: const TextStyle(fontSize: 28)),
                        ),
                      ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _Particle {
  const _Particle({required this.x, required this.start, required this.speed, required this.spin, required this.symbol});

  final double x;
  final double start;
  final double speed;
  final double spin;
  final String symbol;
}
