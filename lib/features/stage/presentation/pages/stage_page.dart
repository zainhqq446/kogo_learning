import 'package:flutter/material.dart';

import '../../../../data/models/stage_model.dart';
import '../../../../data/repositories/progress_repository.dart';
import '../../../../data/repositories/stage_repository.dart';
import '../../../../services/auth/session_manager.dart';
import '../../../lesson/presentation/pages/lesson_page.dart';
import '../../../progress/presentation/pages/child_progress_page.dart';

class StagePage extends StatefulWidget {
  const StagePage({super.key});

  @override
  State<StagePage> createState() => _StagePageState();
}

class _StagePageState extends State<StagePage> {
  final StageRepository _repository = StageRepository();
  final ProgressRepository _progressRepository = ProgressRepository();
  final SessionManager _sessionManager = SessionManager.instance;

  late Future<List<StageModel>> _stagesFuture;
  Map<int, bool> _stageUnlockStatus = {};

  @override
  void initState() {
    super.initState();
    _loadStagesAndUnlockStatus();
  }

  void _loadStagesAndUnlockStatus() {
    _stagesFuture = _repository.getAll().then((stages) async {
      final childId = _sessionManager.currentChild?.id ?? 1;
      final unlockMap = <int, bool>{};

      for (final stage in stages) {
        final isUnlocked = await _progressRepository.isStageUnlocked(
          childId: childId,
          stageOrderIndex: stage.orderIndex,
        );
        unlockMap[stage.id ?? stage.orderIndex] = isUnlocked;
      }

      if (mounted) {
        setState(() {
          _stageUnlockStatus = unlockMap;
        });
      }

      return stages;
    });
  }

  void _openStage(StageModel stage, bool isUnlocked) {
    if (!isUnlocked) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.lock_rounded, color: Colors.orange, size: 28),
              SizedBox(width: 8),
              Text('Tahap Terkunci 🔒'),
            ],
          ),
          content: Text(
            'Selesaikan semua materi pada Tahap ${stage.orderIndex - 1} terlebih dahulu untuk membuka ${stage.title} ya!',
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
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LessonPage(stage: stage),
      ),
    ).then((_) {
      // Refresh status kunci stage saat kembali dari pelajaran
      _loadStagesAndUnlockStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih Tahap'),
        actions: [
          IconButton(
            icon: const Icon(Icons.military_tech_rounded),
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
      body: FutureBuilder<List<StageModel>>(
        future: _stagesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(),
            );
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

          final stages = snapshot.data ?? [];

          if (stages.isEmpty) {
            return const Center(
              child: Text('Belum ada tahap belajar.'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            itemCount: stages.length,
            itemBuilder: (context, index) {
              final stage = stages[index];
              final stageKey = stage.id ?? stage.orderIndex;
              final isUnlocked = _stageUnlockStatus[stageKey] ?? (stage.orderIndex == 1);

              // Warna variatif yang lembut untuk setiap tahap
              final stageColors = [
                const Color(0xFFFF6B4A), // Coral
                const Color(0xFF4A90E2), // Sky Blue
                const Color(0xFF48BB78), // Green
                const Color(0xFF9B51E0), // Purple
                const Color(0xFFFFB703), // Yellow
              ];
              final stageColor = isUnlocked
                  ? stageColors[index % stageColors.length]
                  : Colors.grey.shade400;

              return Card(
                elevation: isUnlocked ? 3 : 1,
                margin: const EdgeInsets.only(bottom: 16),
                color: isUnlocked ? null : Colors.grey.shade100,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => _openStage(stage, isUnlocked),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: isUnlocked
                                ? stageColor.withValues(alpha: 0.15)
                                : Colors.grey.shade200,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: isUnlocked
                              ? Text(
                                  '${stage.orderIndex}',
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                    color: stageColor,
                                  ),
                                )
                              : const Icon(
                                  Icons.lock_rounded,
                                  color: Colors.grey,
                                  size: 26,
                                ),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      stage.title,
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: isUnlocked ? const Color(0xFF2D3748) : Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                  if (!isUnlocked)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.orange.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.orange.shade200),
                                      ),
                                      child: const Text(
                                        'Terkunci',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.orange,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (stage.description != null && stage.description!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  stage.description!,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isUnlocked ? const Color(0xFF718096) : Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isUnlocked ? stageColor.withValues(alpha: 0.1) : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isUnlocked ? Icons.arrow_forward_ios_rounded : Icons.lock_outline_rounded,
                            color: stageColor,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}