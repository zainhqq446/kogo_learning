import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/app_session.dart';
import '../../core/curriculum/curriculum.dart';
import '../../core/motion/motion.dart';
import '../../core/theme/kogo_colors.dart';
import '../../core/widgets/kogo_widgets.dart';
import '../../data/progress_repository.dart';
import '../../services/audio/audio_service.dart';
import '../../services/audio/voice_lines.dart';
import '../../services/audio/voice_service.dart';
import '../games/game_page.dart';
import '../games/game_widgets.dart';

/// Peta petualangan (Stage Map, proposal Gambar 3.24): jalur berliku yang
/// menghubungkan permainan; node dibuka bertahap setelah node sebelumnya selesai.
class StageMapPage extends StatefulWidget {
  const StageMapPage({super.key, required this.materi});

  final Materi materi;

  static Route<void> route(Materi materi) => MaterialPageRoute(
    settings: RouteSettings(name: 'map/${materi.code}'),
    builder: (_) => StageMapPage(materi: materi),
  );

  @override
  State<StageMapPage> createState() => _StageMapPageState();
}

class _StageMapPageState extends State<StageMapPage> {
  final _scroll = ScrollController();
  late final List<LearningNode> _nodes = Curriculum.nodesOf(widget.materi);
  Map<int, int> _stars = const {};
  bool _loaded = false;
  int _shakeNode = -1;
  int _shake = 0;
  bool _opening = false;

  static const _nodeSize = 104.0;
  static const _rowHeight = 196.0;
  static const _bannerHeight = 120.0;
  static const _topPadding = 24.0;
  static const _xPattern = [0.30, 0.70, 0.36, 0.70, 0.30, 0.62, 0.36, 0.68, 0.48];

  int get _current => ProgressRepository.currentNodeIndex(_stars, _nodes.length);

  @override
  void initState() {
    super.initState();
    unawaited(_load(first: true));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool first = false}) async {
    final learner = AppSession.instance.learner;
    final stars = learner == null ? <int, int>{} : await AppSession.instance.progress.starsFor(learner.id, widget.materi);
    if (!mounted) return;
    setState(() {
      _stars = stars;
      _loaded = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent(animate: !first));
    if (first && stars.isEmpty) {
      final line = VoiceLines.materiIntro(widget.materi);
      unawaited(VoiceService.instance.say(line.text, mood: line.mood));
    }
  }

  void _scrollToCurrent({required bool animate}) {
    if (!_scroll.hasClients) return;
    final index = math.min(_current, _nodes.length - 1);
    final target = (_nodeTop(index) - _scroll.position.viewportDimension * 0.35).clamp(0.0, _scroll.position.maxScrollExtent);
    if (animate) {
      unawaited(_scroll.animateTo(target, duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic));
    } else {
      _scroll.jumpTo(target);
    }
  }

  double _nodeTop(int index) {
    final unitsBefore = _nodes[index].unit.index + 1;
    return _topPadding + unitsBefore * _bannerHeight + index * _rowHeight;
  }

  double get _contentHeight => _nodeTop(_nodes.length - 1) + _rowHeight + 200;

  Future<void> _tapNode(LearningNode node) async {
    if (_opening) return;
    if (!ProgressRepository.isUnlocked(_stars, node.index)) {
      AudioService.instance.play(Sfx.wrong);
      setState(() {
        _shakeNode = node.index;
        _shake++;
      });
      final line = VoiceLines.locked();
      unawaited(VoiceService.instance.say(line.text, mood: line.mood));
      return;
    }
    _opening = true;
    AudioService.instance.play(Sfx.pop);
    await VoiceService.instance.stop();
    if (!mounted) return;
    await Navigator.of(context).push(GamePage.route(node));
    _opening = false;
    final before = _current;
    await _load();
    if (mounted && _current > before && _current < _nodes.length) AudioService.instance.play(Sfx.unlock);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: KogoBackground(
        colors: const [KogoColors.sky100, KogoColors.blue50, KogoColors.purple100],
        decorations: const [
          FloatingDecoration('☁️', left: 24, top: 110, size: 40, tilt: 0, duration: Duration(seconds: 3)),
          FloatingDecoration('⭐', right: 40, top: 140, size: 30, lift: 15, spin: true, duration: Duration(seconds: 4)),
          FloatingDecoration('✨', right: 56, top: 280, size: 36, lift: 25, tilt: 0, duration: Duration(milliseconds: 3500), delay: Duration(seconds: 1)),
        ],
        child: Column(
          children: [
            KogoHeader(
              title: widget.materi.title,
              translucent: true,
              onBack: () => Navigator.of(context).maybePop(),
              trailing: Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Text(
                  '⭐ ${_stars.values.fold(0, (a, b) => a + b)}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: KogoColors.yellow600),
                ),
              ),
            ),
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(controller: _scroll, child: _buildMap(constraints.maxWidth)),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap(double width) {
    final centers = <Offset>[for (var i = 0; i < _nodes.length; i++) Offset(_xFor(i, width), _nodeTop(i) + _nodeSize / 2)];
    final current = _current;
    final allDone = current >= _nodes.length;
    return SizedBox(
      width: width,
      height: _contentHeight,
      child: Stack(
        children: [
          Positioned.fill(child: _AnimatedTrail(centers: centers)),
          for (final unit in Curriculum.unitsOf(widget.materi))
            Positioned(
              left: 24,
              right: 24,
              top: _nodeTop(_nodes.indexWhere((n) => n.unit.index == unit.index)) - _bannerHeight + 8,
              height: _bannerHeight - 24,
              child: _UnitBanner(unit: unit),
            ),
          for (var i = 0; i < _nodes.length; i++)
            Positioned(
              left: centers[i].dx - 80,
              top: _nodeTop(i),
              width: 160,
              child: Entrance.pop(
                delay: Duration(milliseconds: 120 * (i % 8)),
                child: Shake(
                  trigger: _shakeNode == i ? _shake : 0,
                  child: _MapNode(
                    node: _nodes[i],
                    stars: _stars[i] ?? 0,
                    status: (_stars[i] ?? 0) > 0
                        ? _NodeStatus.completed
                        : i == current
                        ? _NodeStatus.current
                        : _NodeStatus.locked,
                    size: _nodeSize,
                    onTap: () => unawaited(_tapNode(_nodes[i])),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            top: _nodeTop(_nodes.length - 1) + _rowHeight + 10,
            child: Entrance.pop(
              delay: const Duration(milliseconds: 1500),
              child: Column(
                children: [
                  Text(allDone ? '🏆' : '🎊', style: const TextStyle(fontSize: 64)),
                  Text(
                    allDone ? 'Hebat! Semua selesai!' : 'Terus Lanjut!',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: KogoColors.purple600),
                  ),
                  Text(
                    allDone ? 'Kamu sudah menyelesaikan ${widget.materi.title}.' : 'Lebih banyak petualangan menantimu!',
                    style: const TextStyle(fontSize: 15, color: KogoColors.gray600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _xFor(int index, double width) {
    final fraction = _xPattern[index % _xPattern.length];
    const margin = _nodeSize / 2 + 16;
    return (width * fraction).clamp(margin, width - margin);
  }
}

enum _NodeStatus { completed, current, locked }

class _MapNode extends StatelessWidget {
  const _MapNode({required this.node, required this.stars, required this.status, required this.size, required this.onTap});

  final LearningNode node;
  final int stars;
  final _NodeStatus status;
  final double size;
  final VoidCallback onTap;

  static IconData iconFor(GameType game) => switch (game) {
    GameType.listenRepeat => Icons.mic_rounded,
    GameType.findObject => Icons.image_search_rounded,
    GameType.missingLetter => Icons.text_fields_rounded,
    GameType.matching => Icons.sports_esports_rounded,
    GameType.listening => Icons.headphones_rounded,
    GameType.fillBlank => Icons.edit_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final colors = switch (status) {
      _NodeStatus.completed => const [KogoColors.green400, KogoColors.emerald500],
      _NodeStatus.current => const [KogoColors.yellow400, KogoColors.orange500],
      _NodeStatus.locked => const [KogoColors.gray300, KogoColors.gray400],
    };
    final circle = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: KogoColors.br(colors.first, colors.last),
        border: Border.all(color: KogoColors.white, width: 4),
        boxShadow: [BoxShadow(color: colors.last.withValues(alpha: 0.45), blurRadius: 22, offset: const Offset(0, 10))],
      ),
      child: Icon(
        status == _NodeStatus.locked ? Icons.lock_rounded : iconFor(node.game),
        size: status == _NodeStatus.locked ? size * 0.42 : size * 0.5,
        color: status == _NodeStatus.locked ? KogoColors.gray600 : KogoColors.white,
      ),
    );

    final button = SizedBox(
      width: size + 24,
      height: size + 12,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (status == _NodeStatus.current)
            Loop(
              duration: const Duration(seconds: 2),
              scale: const [1, 1.4, 1],
              opacity: const [0.6, 0, 0.6],
              child: Container(
                width: size,
                height: size,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: KogoColors.yellow300),
              ),
            ),
          status == _NodeStatus.current ? Loop.bob(height: 10, child: circle) : circle,
          if (status == _NodeStatus.completed)
            Positioned(
              top: -4,
              right: 2,
              child: Entrance(
                delay: const Duration(milliseconds: 300),
                fromScale: 0,
                fromTurns: -1,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: KogoColors.yellow400,
                    border: Border.all(color: KogoColors.white, width: 4),
                    boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))],
                  ),
                  child: const Icon(Icons.star_rounded, color: KogoColors.white, size: 24),
                ),
              ),
            ),
        ],
      ),
    );

    return Semantics(
      button: true,
      label: '${node.game.title}${status == _NodeStatus.locked ? ', terkunci' : ''}${stars > 0 ? ', $stars bintang' : ''}',
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.9,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            button,
            const SizedBox(height: 6),
            Text(
              node.game.mapLabel,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: status == _NodeStatus.locked ? KogoColors.gray400 : KogoColors.gray800),
            ),
            if (status == _NodeStatus.completed) StarRow(stars: stars, size: 18),
            if (status == _NodeStatus.current)
              Loop(
                duration: const Duration(milliseconds: 1500),
                opacity: const [0.5, 1, 0.5],
                child: const Text(
                  'Mulai Di Sini! 👆',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: KogoColors.orange600),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnitBanner extends StatelessWidget {
  const _UnitBanner({required this.unit});

  final LearningUnit unit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: KogoColors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          Text(
            'Petualangan\n${unit.index + 1}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: KogoColors.purple600, height: 1.2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (final item in unit.items)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: WordPicture(item: item, size: 52, radius: 14),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Jalur putus-putus bergradien (amber → pink → ungu) yang tergambar perlahan
/// seperti `pathLength: 0 → 1` pada desain Figma.
class _AnimatedTrail extends StatefulWidget {
  const _AnimatedTrail({required this.centers});

  final List<Offset> centers;

  @override
  State<_AnimatedTrail> createState() => _AnimatedTrailState();
}

class _AnimatedTrailState extends State<_AnimatedTrail> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 2));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.value == 0 && !_c.isAnimating) {
      Motion.of(context) ? _c.forward() : _c.value = 1;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _TrailPainter(widget.centers, CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      ),
    );
  }
}

class _TrailPainter extends CustomPainter {
  _TrailPainter(this.centers, this.progress) : super(repaint: progress);

  final List<Offset> centers;
  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (centers.length < 2) return;
    final path = Path()..moveTo(centers.first.dx, centers.first.dy);
    for (var i = 1; i < centers.length; i++) {
      final a = centers[i - 1];
      final b = centers[i];
      final midY = (a.dy + b.dy) / 2;
      path.cubicTo(a.dx, midY, b.dx, midY, b.dx, b.dy);
    }
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..shader = ui.Gradient.linear(
        Offset(0, centers.first.dy),
        Offset(0, centers.last.dy),
        [KogoColors.amber500.withValues(alpha: 0.45), KogoColors.pink500.withValues(alpha: 0.45), KogoColors.violet500.withValues(alpha: 0.45)],
        const [0, 0.5, 1],
      );
    const dash = 20.0;
    const gap = 15.0;
    for (final metric in path.computeMetrics()) {
      final drawn = metric.length * progress.value;
      var d = 0.0;
      while (d < drawn) {
        canvas.drawPath(metric.extractPath(d, math.min(d + dash, drawn)), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_TrailPainter old) => old.centers != centers;
}
