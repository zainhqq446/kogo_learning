import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_session.dart';
import '../../core/motion/motion.dart';
import '../../core/theme/kogo_colors.dart';
import '../../core/widgets/kogo_widgets.dart';
import '../biodata/biodata_page.dart';
import '../research/research_page.dart';

/// Tab Profil (proposal Gambar 3.11, 3.19, 3.30): data diri dan statistik
/// belajar — pelajaran selesai, total bintang, dan hari belajar beruntun.
class ProfilTab extends StatelessWidget {
  const ProfilTab({super.key});

  Future<void> _parentAction(BuildContext context, Future<void> Function() action) async {
    if (await ParentalGate.ask(context)) await action();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: AppSession.instance, builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final session = AppSession.instance;
    final learner = session.learner;
    final stats = session.stats;
    final navigator = Navigator.of(context);
    return KogoBackground(
      colors: const [KogoColors.pink100, KogoColors.purple50, KogoColors.blue50],
      child: Column(
        children: [
          Entrance.slide(
            fromOffset: const Offset(0, -20),
            child: Container(
              color: KogoColors.white.withValues(alpha: 0.9),
              child: const SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_rounded, size: 28, color: KogoColors.purple600),
                      SizedBox(width: 10),
                      Text(
                        'Profil Saya',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: KogoColors.gray800),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
              children: [
                Center(
                  child: Entrance(
                    fromScale: 0,
                    fromTurns: -0.5,
                    child: Stack(
                      children: [
                        GradientCircle(
                          colors: const [KogoColors.purple400, KogoColors.pink500],
                          size: 128,
                          border: 4,
                          child: Text(learner?.avatar ?? '🐻', style: const TextStyle(fontSize: 64)),
                        ),
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Loop(
                            duration: const Duration(seconds: 2),
                            scale: const [1, 1.2, 1],
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: KogoColors.green500,
                                shape: BoxShape.circle,
                                border: Border.all(color: KogoColors.white, width: 4),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Entrance.slide(
                  delay: const Duration(milliseconds: 200),
                  child: KogoCard(
                    child: Column(
                      children: [
                        _InfoRow(
                          icon: Icons.person_rounded,
                          colors: const [KogoColors.purple400, KogoColors.pink400],
                          label: 'Nama',
                          value: learner?.name ?? '-',
                        ),
                        const Divider(height: 28, color: KogoColors.gray100),
                        _InfoRow(
                          icon: Icons.school_rounded,
                          colors: const [KogoColors.blue400, KogoColors.cyan400],
                          label: 'Sekolah',
                          value: learner?.school ?? '-',
                        ),
                        const Divider(height: 28, color: KogoColors.gray100),
                        _InfoRow(
                          icon: Icons.cake_rounded,
                          colors: const [KogoColors.orange400, KogoColors.red400],
                          label: 'Umur',
                          value: learner == null ? '-' : '${learner.age} tahun',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Entrance.slide(
                  delay: const Duration(milliseconds: 300),
                  child: KogoCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.bar_chart_rounded, color: KogoColors.purple600),
                            SizedBox(width: 8),
                            Text(
                              'Statistik Progress',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: KogoColors.gray800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _StatRow(
                          index: 0,
                          icon: Icons.workspace_premium_rounded,
                          colors: const [KogoColors.green400, KogoColors.emerald500],
                          label: 'Pelajaran Selesai',
                          value: '${stats.completedNodes}',
                        ),
                        _StatRow(
                          index: 1,
                          icon: Icons.star_rounded,
                          colors: const [KogoColors.yellow400, KogoColors.orange500],
                          label: 'Total Bintang',
                          value: '${stats.totalStars}',
                        ),
                        _StatRow(
                          index: 2,
                          icon: Icons.trending_up_rounded,
                          colors: const [KogoColors.purple400, KogoColors.pink500],
                          label: 'Beruntun Belajar',
                          value: '${stats.streakDays} hari',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Entrance.pop(
                    delay: const Duration(milliseconds: 800),
                    child: Loop(
                      duration: const Duration(seconds: 3),
                      rotateDeg: const [0, 10, -10, 0],
                      dy: const [0, -10, 0],
                      child: const Text('🐻', style: TextStyle(fontSize: 72)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Untuk Orang Tua / Guru',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: KogoColors.gray500),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _ParentButton(
                      icon: Icons.edit_rounded,
                      label: 'Ubah Biodata',
                      onTap: learner == null
                          ? null
                          : () => _parentAction(context, () async {
                              await navigator.push(BiodataPage.route(editing: learner));
                            }),
                    ),
                    _ParentButton(
                      icon: Icons.switch_account_rounded,
                      label: 'Ganti Anak',
                      onTap: () => _parentAction(context, () async {
                        await navigator.push(BiodataPage.route(choose: true));
                      }),
                    ),
                    _ParentButton(
                      icon: Icons.science_rounded,
                      label: 'Mode Peneliti',
                      onTap: () => _parentAction(context, () async {
                        await navigator.push(ResearchPage.route());
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.colors, required this.label, required this.value});

  final IconData icon;
  final List<Color> colors;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GradientCircle(
          colors: colors,
          child: Icon(icon, color: KogoColors.white),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: KogoColors.gray500),
              ),
              Text(
                value,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: KogoColors.gray800),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.index, required this.icon, required this.colors, required this.label, required this.value});

  final int index;
  final IconData icon;
  final List<Color> colors;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Entrance(
        delay: Duration(milliseconds: 400 + index * 100),
        fromOffset: const Offset(-20, 0),
        fromOpacity: 0,
        child: Row(
          children: [
            GradientCircle(
              colors: colors,
              child: Icon(icon, color: KogoColors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: KogoColors.gray700),
              ),
            ),
            Entrance.pop(
              delay: Duration(milliseconds: 600 + index * 100),
              child: Text(
                value,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: KogoColors.gray800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParentButton extends StatelessWidget {
  const _ParentButton({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap == null ? null : () => unawaited(Future.sync(onTap!)),
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: KogoColors.purple600,
        side: const BorderSide(color: KogoColors.purple200, width: 2),
        backgroundColor: KogoColors.white.withValues(alpha: 0.8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      ),
    );
  }
}
