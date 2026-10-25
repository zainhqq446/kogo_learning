import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../data/models/lesson_model.dart';
import '../../../../data/models/stage_model.dart';
import '../../../../data/repositories/lesson_repository.dart';
import '../../../../data/repositories/progress_repository.dart';
import '../../../../services/auth/session_manager.dart';
import '../../../progress/presentation/pages/child_progress_page.dart';
import 'checkpoint_session_page.dart';



/// Path Painter untuk menggambar jalur petualangan berkelok-kelok (seperti Duolingo Map)
class _LearningPathPainter extends CustomPainter {
  final List<Offset> points;

  _LearningPathPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8.0
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [Color(0xFFFBBF24), Color(0xFFF472B6), Color(0xFFA855F7)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);

    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final midX = (p0.dx + p1.dx) / 2;
      final midY = (p0.dy + p1.dy) / 2;

      path.quadraticBezierTo(p0.dx, midY, midX, midY);
      path.quadraticBezierTo(p1.dx, midY, p1.dx, p1.dy);
    }

    // Gambar jalur putus-putus
    const dashLength = 12.0;
    const dashSpace = 8.0;

    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final currentDash = math.min(dashLength, metric.length - distance);
        final extractPath = metric.extractPath(distance, distance + currentDash);
        canvas.drawPath(extractPath, paint);
        distance += dashLength + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LearningPathPainter oldDelegate) {
    return oldDelegate.points != points;
  }
}

/// Metadata checkpoint sesi campuran (Duolingo-style Unit Checkpoint)
class CheckpointInfo {
  final int number;
  final String title;
  final String subtitle;
  final String badgeIcon;

  const CheckpointInfo({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.badgeIcon,
  });
}

/// Halaman Map Kategori Duolingo-style dengan Mixed-Game Checkpoints
class LessonPage extends StatefulWidget {
  final StageModel stage;

  const LessonPage({
    super.key,
    required this.stage,
  });

  @override
  State<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends State<LessonPage> with SingleTickerProviderStateMixin {
  final LessonRepository _repository = LessonRepository();
  final ProgressRepository _progressRepository = ProgressRepository();

  late Future<List<LessonModel>> _lessonsFuture;
  late final AnimationController _pulseController;

  int _unlockedCheckpointCount = 1;
  int _selectedCheckpointIndex = 0;

  late final List<CheckpointInfo> _checkpoints;

  static List<CheckpointInfo> _generateCheckpoints(int stageId) {
    final count = stageId == 1 ? 5 : 25;
    const badgeIcons = ['⭐', '🚀', '🎯', '🔥', '👑', '🌈', '🎨', '🦁', '🍎', '🧩', '💎', '🏆'];
    return List.generate(count, (index) {
      final num = index + 1;
      final icon = badgeIcons[index % badgeIcons.length];
      return CheckpointInfo(
        number: num,
        title: 'Checkpoint $num',
        subtitle: 'Sesi Pembelajaran $num',
        badgeIcon: icon,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _checkpoints = _generateCheckpoints(widget.stage.id ?? 1);
    _lessonsFuture = _repository.getByStageId(widget.stage.id!);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _loadCheckpointLockStatus();
  }


  Future<void> _loadCheckpointLockStatus() async {
    final childId = SessionManager.instance.currentChild?.id ?? 1;
    final stageId = widget.stage.id ?? 1;

    int unlocked = 1;
    for (int i = 2; i <= _checkpoints.length; i++) {
      final isUnlocked = await _progressRepository.isCheckpointUnlocked(
        childId: childId,
        stageId: stageId,
        checkpointOrderIndex: i,
      );
      if (isUnlocked) {
        unlocked = i;
      } else {
        break;
      }
    }

    if (mounted) {
      setState(() {
        _unlockedCheckpointCount = unlocked;
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  List<Color> _getNodeGradient(int index, bool isUnlocked) {
    if (!isUnlocked) {
      return [const Color(0xFF9CA3AF), const Color(0xFF6B7280)]; // Grayscale Muted
    }
    final gradients = [
      [const Color(0xFFFF6B4A), const Color(0xFFFF8E72)], // Coral Orange
      [const Color(0xFF3B82F6), const Color(0xFF60A5FA)], // Sky Blue
      [const Color(0xFF10B981), const Color(0xFF34D399)], // Green
      [const Color(0xFFEC4899), const Color(0xFFF472B6)], // Pink
      [const Color(0xFF8B5CF6), const Color(0xFFA78BFA)], // Purple
      [const Color(0xFFF59E0B), const Color(0xFFFBBF24)], // Amber
    ];
    return gradients[index % gradients.length];
  }


  void _showLockedCheckpointDialog(int checkpointNumber) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.lock_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 8),
            Text('Checkpoint Terkunci 🔒'),
          ],
        ),
        content: Text(
          'Selesaikan semua aktivitas pada Checkpoint ${checkpointNumber - 1} terlebih dahulu untuk membuka petualangan ini!',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Siap, Mengerti! 🚀', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: false,
      appBar: AppBar(
        backgroundColor: Colors.white.withValues(alpha: 0.95),
        elevation: 1,
        title: Text(
          widget.stage.title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        leading: const BackButton(color: Color(0xFF374151)),
        actions: [
          IconButton(
            icon: const Icon(Icons.military_tech_rounded, color: Color(0xFFD97706)),
            tooltip: 'Progress & Pencapaian',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ChildProgressPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // Background Gradient (Mirip LessonMapScreen bg-gradient-to-b from-sky-100 via-blue-50 to-purple-100)
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFE0F2FE), // Sky-100
                    Color(0xFFEFF6FF), // Blue-50
                    Color(0xFFF3E8FF), // Purple-100
                  ],
                ),
              ),
            ),
          ),

          // Dekorasi mengambang (Awan, Bintang, Kilau)
          _buildFloatingDecorations(),

          // Konten Path Map
          FutureBuilder<List<LessonModel>>(
            future: _lessonsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Terjadi kesalahan:\n${snapshot.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              final lessons = snapshot.data ?? [];

              if (lessons.isEmpty) {
                return const Center(
                  child: Text(
                    'Belum ada aktivitas belajar.',
                    style: TextStyle(fontSize: 16, color: Color(0xFF6B7280)),
                  ),
                );
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  final screenWidth = constraints.maxWidth;
                  const itemHeight = 175.0;
                  final totalHeight = (_checkpoints.length * itemHeight) + 380.0;

                  // Hitung koordinat titik node untuk jalur berkelok-kelok (Duolingo Zig-Zag)
                  final points = <Offset>[];
                  final nodeAlignments = <double>[];

                  for (int i = 0; i < _checkpoints.length; i++) {
                    final patternIndex = i % 3;
                    double xPercent;
                    if (patternIndex == 0) {
                      xPercent = 0.30;
                    } else if (patternIndex == 1) {
                      xPercent = 0.70;
                    } else {
                      xPercent = 0.50;
                    }

                    nodeAlignments.add(xPercent);
                    final y = 80.0 + (i * itemHeight) + 42.0;
                    final x = screenWidth * xPercent;
                    points.add(Offset(x, y));
                  }

                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: SizedBox(
                      width: screenWidth,
                      height: totalHeight,
                      child: Stack(
                        children: [
                          // 1. Jalur melengkung Petualangan Checkpoint (Background layer)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                size: Size(screenWidth, totalHeight),
                                painter: _LearningPathPainter(points: points),
                              ),
                            ),
                          ),

                          // 2. Header Progres Pembelajaran di Bagian Atas Peta
                          Positioned(
                            top: 12,
                            left: 20,
                            right: 20,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.95),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                                border: Border.all(color: const Color(0xFFDBEAFE), width: 1.5),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.explore_rounded, color: Color(0xFF2563EB), size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              widget.stage.title,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF1E3A8A),
                                              ),
                                            ),
                                            Text(
                                              '$_unlockedCheckpointCount/${_checkpoints.length} Terbuka',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFF2563EB),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: LinearProgressIndicator(
                                            value: (_unlockedCheckpointCount / _checkpoints.length).clamp(0.0, 1.0),
                                            backgroundColor: const Color(0xFFE2E8F0),
                                            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                                            minHeight: 7,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // 3. Node-node Checkpoint pada Peta (Duolingo style bersih tanpa kotak besar)
                          ...List.generate(_checkpoints.length, (index) {
                            final checkpoint = _checkpoints[index];
                            final xCenter = screenWidth * nodeAlignments[index];
                            final yTop = 80.0 + (index * itemHeight);
                            final isUnlocked = index < _unlockedCheckpointCount;
                            final isCompleted = index + 1 < _unlockedCheckpointCount;
                            final isCurrentActive = index + 1 == _unlockedCheckpointCount;
                            final isSelected = index == _selectedCheckpointIndex;
                            final gradient = _getNodeGradient(index, isUnlocked);

                            return Positioned(
                              top: yTop,
                              left: xCenter - 80,
                              width: 160,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Tombol Lingkaran Besar Checkpoint
                                  GestureDetector(
                                    onTap: () {
                                      if (isUnlocked) {
                                        setState(() {
                                          _selectedCheckpointIndex = index;
                                        });
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => CheckpointSessionPage(
                                              stageId: widget.stage.id ?? 1,
                                              checkpointNumber: checkpoint.number,
                                              stageTitle: widget.stage.title,
                                              checkpointTitle: checkpoint.title,
                                              onCheckpointCompleted: () {
                                                _loadCheckpointLockStatus();
                                              },
                                            ),
                                          ),
                                        ).then((_) {
                                          _loadCheckpointLockStatus();
                                        });
                                      } else {
                                        _showLockedCheckpointDialog(checkpoint.number);
                                      }
                                    },

                                    child: AnimatedBuilder(
                                      animation: _pulseController,
                                      builder: (context, child) {
                                        final scale = (isCurrentActive || isSelected) && isUnlocked
                                            ? 1.0 + (_pulseController.value * 0.08)
                                            : 1.0;
                                        return Transform.scale(
                                          scale: scale,
                                          child: child,
                                        );
                                      },
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        alignment: Alignment.center,
                                        children: [
                                          // Efek glow untuk node aktif yang dipilih
                                          if ((isCurrentActive || isSelected) && isUnlocked)
                                            Container(
                                              width: 96,
                                              height: 96,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.amber.withValues(alpha: 0.35),
                                              ),
                                            ),

                                          // Node Utama Checkpoint
                                          Container(
                                            width: 84,
                                            height: 84,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: gradient,
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 4,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: gradient.first.withValues(alpha: isUnlocked ? 0.4 : 0.2),
                                                  blurRadius: 16,
                                                  offset: const Offset(0, 8),
                                                ),
                                              ],
                                            ),
                                            child: Center(
                                              child: isUnlocked
                                                  ? Text(
                                                      checkpoint.badgeIcon,
                                                      style: const TextStyle(fontSize: 34),
                                                    )
                                                  : const Icon(
                                                      Icons.lock_rounded,
                                                      size: 34,
                                                      color: Colors.white70,
                                                    ),
                                            ),
                                          ),

                                          // Badge status (Centang hijau jika selesai, Bintang jika aktif, Gembok jika locked)
                                          Positioned(
                                            top: -2,
                                            right: -2,
                                            child: Container(
                                              padding: const EdgeInsets.all(5),
                                              decoration: BoxDecoration(
                                                gradient: LinearGradient(
                                                  colors: isCompleted
                                                      ? [const Color(0xFF10B981), const Color(0xFF059669)]
                                                      : (isUnlocked
                                                          ? [const Color(0xFFFBBF24), const Color(0xFFF59E0B)]
                                                          : [const Color(0xFF9CA3AF), const Color(0xFF6B7280)]),
                                                ),
                                                shape: BoxShape.circle,
                                                border: Border.all(color: Colors.white, width: 2),
                                              ),
                                              child: Icon(
                                                isCompleted
                                                    ? Icons.check_rounded
                                                    : (isUnlocked ? Icons.star_rounded : Icons.lock_outline_rounded),
                                                color: Colors.white,
                                                size: 16,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  // Label Checkpoint
                                  GestureDetector(
                                    onTap: () {
                                      if (isUnlocked) {
                                        setState(() {
                                          _selectedCheckpointIndex = index;
                                        });
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => CheckpointSessionPage(
                                              stageId: widget.stage.id ?? 1,
                                              checkpointNumber: checkpoint.number,
                                              stageTitle: widget.stage.title,
                                              checkpointTitle: checkpoint.title,
                                              onCheckpointCompleted: () {
                                                _loadCheckpointLockStatus();
                                              },
                                            ),
                                          ),
                                        ).then((_) {
                                          _loadCheckpointLockStatus();
                                        });
                                      } else {
                                        _showLockedCheckpointDialog(checkpoint.number);
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.95),
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.06),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            checkpoint.title,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: isUnlocked ? const Color(0xFF1F2937) : const Color(0xFF9CA3AF),
                                            ),
                                          ),
                                          if (isCompleted)
                                            const Text(
                                              '⭐⭐⭐',
                                              style: TextStyle(fontSize: 11),
                                            )
                                          else if (isCurrentActive)
                                            const Text(
                                              'Mulai Di Sini! 👆',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFFEA580C),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),


                          // Card Selebrasi di Bagian Bawah Jalur
                          Positioned(
                            bottom: 24,
                            left: 20,
                            right: 20,
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.95),
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: const Column(
                                children: [
                                  Text('🎉', style: TextStyle(fontSize: 40)),
                                  SizedBox(height: 6),
                                  Text(
                                    'Terus Lanjut!',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF9333EA),
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Selesaikan setiap checkpoint untuk menaklukkan tahap ini!',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingDecorations() {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: 24,
            left: 24,
            child: Text('☁️', style: TextStyle(fontSize: 34, color: Colors.white.withValues(alpha: 0.7))),
          ),
          Positioned(
            top: 100,
            right: 20,
            child: Text('⭐', style: TextStyle(fontSize: 24, color: Colors.amber.withValues(alpha: 0.7))),
          ),
          Positioned(
            top: 240,
            left: 18,
            child: Text('✨', style: TextStyle(fontSize: 26, color: Colors.orange.withValues(alpha: 0.7))),
          ),
          Positioned(
            bottom: 120,
            right: 18,
            child: Text('☁️', style: TextStyle(fontSize: 36, color: Colors.white.withValues(alpha: 0.7))),
          ),
        ],
      ),
    );
  }
}