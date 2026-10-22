import 'package:flutter/material.dart';

import '../../../../data/models/child_progress_summary_model.dart';
import '../../../../data/repositories/progress_repository.dart';
import '../../../../services/auth/session_manager.dart';

class ChildProgressPage extends StatefulWidget {
  const ChildProgressPage({super.key});

  @override
  State<ChildProgressPage> createState() => _ChildProgressPageState();
}

class _ChildProgressPageState extends State<ChildProgressPage> {
  final ProgressRepository _progressRepository = ProgressRepository();
  final SessionManager _sessionManager = SessionManager.instance;

  late Future<ChildProgressSummaryModel> _progressFuture;

  @override
  void initState() {
    super.initState();
    final childId = _sessionManager.currentChild?.id ?? 1;
    _progressFuture = _progressRepository.getProgressSummary(childId);
  }

  void _loadProgress() {
    final childId = _sessionManager.currentChild?.id ?? 1;
    setState(() {
      _progressFuture = _progressRepository.getProgressSummary(childId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final child = _sessionManager.currentChild;

    return Scaffold(
      appBar: AppBar(
        title: Text('Progress ${child?.displayName ?? "Anak"}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadProgress,
          ),
        ],
      ),
      body: FutureBuilder<ChildProgressSummaryModel>(
        future: _progressFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Terjadi kesalahan:\n${snapshot.error}'),
              ),
            );
          }

          final summary = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Kartu Ringkasan Akurasi & Soal Selesai
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Text(
                          'Ringkasan Belajar',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatItem(
                              context,
                              label: 'Akurasi',
                              value: '${summary.accuracyPercent.toStringAsFixed(1)}%',
                              icon: Icons.track_changes,
                              color: Colors.blue,
                            ),
                            _buildStatItem(
                              context,
                              label: 'Soal Selesai',
                              value: '${summary.completedQuestions} / ${summary.totalQuestions}',
                              icon: Icons.check_circle,
                              color: Colors.green,
                            ),
                            _buildStatItem(
                              context,
                              label: 'Attempts Benar',
                              value: '${summary.correctAttempts} / ${summary.totalAttempts}',
                              icon: Icons.thumb_up,
                              color: Colors.orange,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Bagian Achievement
                Text(
                  'Pencapaian & Medali (Achievements)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 10),
                _buildAchievementsSection(summary),
                const SizedBox(height: 20),

                // Bagian Progress Tahap Belajar (Stages)
                Text(
                  'Progress Tiap Tahap (Stages)',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 10),
                ...summary.stageProgressList.map((stage) => _buildStageProgressCard(context, stage)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context, {
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          radius: 24,
          child: Icon(icon, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _buildAchievementsSection(ChildProgressSummaryModel summary) {
    final earnedMap = {for (var e in summary.earnedAchievements) e.achievementCode: e};

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: summary.allAchievements.map((ach) {
            final isEarned = earnedMap.containsKey(ach.code);

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: isEarned ? Colors.amber.shade100 : Colors.grey.shade200,
                child: Icon(
                  isEarned ? Icons.emoji_events : Icons.lock,
                  color: isEarned ? Colors.amber.shade800 : Colors.grey,
                ),
              ),
              title: Text(
                ach.title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isEarned ? Colors.black87 : Colors.grey.shade600,
                ),
              ),
              subtitle: Text(ach.description ?? ''),
              trailing: isEarned
                  ? Chip(
                      label: const Text('Didapat', style: TextStyle(fontSize: 12)),
                      backgroundColor: Colors.amber.shade50,
                      side: BorderSide(color: Colors.amber.shade400),
                    )
                  : const Text('Terkunci', style: TextStyle(color: Colors.grey, fontSize: 12)),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildStageProgressCard(BuildContext context, StageProgressModel stage) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ExpansionTile(
        initiallyExpanded: stage.orderIndex == 1,
        title: Text(
          stage.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: stage.progressPercent / 100.0,
              backgroundColor: Colors.grey.shade200,
            ),
            const SizedBox(height: 4),
            Text(
              '${stage.progressPercent.toStringAsFixed(0)}% Selesai (${stage.completedQuestions}/${stage.totalQuestions} soal)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        children: stage.lessonProgressList.map((lesson) {
          return ListTile(
            dense: true,
            leading: Icon(
              lesson.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
              color: lesson.isCompleted ? Colors.green : Colors.grey,
            ),
            title: Text(lesson.title),
            subtitle: Text('Tipe: ${lesson.lessonType}'),
            trailing: Text(
              '${lesson.completedQuestions} / ${lesson.totalQuestions}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        }).toList(),
      ),
    );
  }
}
