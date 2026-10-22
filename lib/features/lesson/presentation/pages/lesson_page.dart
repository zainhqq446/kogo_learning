import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../data/models/lesson_model.dart';
import '../../../../data/models/stage_model.dart';
import '../../../../data/repositories/lesson_repository.dart';
import '../../../activity/presentation/pages/find_object_page.dart';
import '../../../activity/presentation/pages/listen_carefully_page.dart';
import '../../../activity/presentation/pages/matching_page.dart';
import '../../../activity/presentation/pages/missing_letter_page.dart';
import '../../../activity/presentation/pages/question_page.dart';
import '../../../progress/presentation/pages/child_progress_page.dart';

/// Path Painter untuk menggambar jalur petualangan berkelok-kelok (seperti LessonMapScreen di Figma)
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

/// Halaman Lesson Map Petualangan Kogo (LessonPage) yang mengadopsi Figma LessonMapScreen.tsx
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

  late Future<List<LessonModel>> _lessonsFuture;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _lessonsFuture = _repository.getByStageId(widget.stage.id!);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  IconData _getLessonIcon(String lessonType) {
    switch (lessonType) {
      case 'listen_repeat':
        return Icons.mic_rounded;
      case 'find_object':
        return Icons.search_rounded;
      case 'matching':
        return Icons.extension_rounded;
      case 'missing_letter':
        return Icons.spellcheck_rounded;
      case 'listen_carefully':
        return Icons.hearing_rounded;
      default:
        return Icons.menu_book_rounded;
    }
  }

  List<Color> _getNodeGradient(int index) {
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

  void _navigateToLesson(LessonModel lesson) {
    Widget destination;
    switch (lesson.lessonType) {
      case 'find_object':
        destination = FindObjectPage(lesson: lesson);
        break;
      case 'matching':
        destination = MatchingPage(lesson: lesson);
        break;
      case 'missing_letter':
        destination = MissingLetterPage(lesson: lesson);
        break;
      case 'listen_carefully':
        destination = ListenCarefullyPage(lesson: lesson);
        break;
      case 'listen_repeat':
      default:
        destination = QuestionPage(lesson: lesson);
        break;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => destination,
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
                  const itemHeight = 170.0;
                  final totalHeight = (lessons.length * itemHeight) + 220.0;

                  // Hitung koordinat titik node untuk jalur berkelok-kelok
                  final points = <Offset>[];
                  final nodeAlignments = <double>[];

                  for (int i = 0; i < lessons.length; i++) {
                    // Pola zig-zag: tengah-kiri, tengah-kanan, tengah
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
                    final y = (i * itemHeight) + 60.0 + 45.0;
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
                          // Jalur melengkung
                          CustomPaint(
                            size: Size(screenWidth, totalHeight),
                            painter: _LearningPathPainter(points: points),
                          ),

                          // Node Pelajaran
                          ...List.generate(lessons.length, (index) {
                            final lesson = lessons[index];
                            final xCenter = screenWidth * nodeAlignments[index];
                            final yTop = (index * itemHeight) + 60.0;
                            final isFirst = index == 0;
                            final gradient = _getNodeGradient(index);

                            return Positioned(
                              top: yTop,
                              left: xCenter - 80,
                              width: 160,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Tombol Lingkaran Besar
                                  GestureDetector(
                                    onTap: () => _navigateToLesson(lesson),
                                    child: AnimatedBuilder(
                                      animation: _pulseController,
                                      builder: (context, child) {
                                        final scale = isFirst
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
                                          // Efek glow untuk node aktif pertama
                                          if (isFirst)
                                            Container(
                                              width: 96,
                                              height: 96,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.amber.withValues(alpha: 0.35),
                                              ),
                                            ),

                                          // Node Utama
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
                                              border: Border.all(color: Colors.white, width: 4),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: gradient.first.withValues(alpha: 0.4),
                                                  blurRadius: 16,
                                                  offset: const Offset(0, 8),
                                                ),
                                              ],
                                            ),
                                            child: Icon(
                                              _getLessonIcon(lesson.lessonType),
                                              size: 38,
                                              color: Colors.white,
                                            ),
                                          ),

                                          // Bintang selesai atau badge
                                          Positioned(
                                            top: -2,
                                            right: -2,
                                            child: Container(
                                              padding: const EdgeInsets.all(5),
                                              decoration: BoxDecoration(
                                                gradient: const LinearGradient(
                                                  colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
                                                ),
                                                shape: BoxShape.circle,
                                                border: Border.all(color: Colors.white, width: 2),
                                              ),
                                              child: const Icon(
                                                Icons.star_rounded,
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

                                  // Judul Aktivitas (Klik untuk navigasi, memenuhi ekspektasi test)
                                  GestureDetector(
                                    onTap: () => _navigateToLesson(lesson),
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
                                            lesson.title,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF1F2937),
                                            ),
                                          ),
                                          if (isFirst)
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
                                    'Lebih banyak petualangan seru menantimu!',
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