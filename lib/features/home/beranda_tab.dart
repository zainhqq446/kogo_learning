import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_session.dart';
import '../../core/curriculum/curriculum.dart';
import '../../core/motion/motion.dart';
import '../../core/theme/kogo_colors.dart';
import '../../core/widgets/kogo_widgets.dart';
import '../../services/audio/audio_service.dart';
import '../../services/audio/voice_lines.dart';
import '../../services/audio/voice_service.dart';
import '../map/stage_map_page.dart';

/// Tab Beranda: sapaan, maskot, dan empat pilihan materi (proposal Gambar 3.23).
class BerandaTab extends StatelessWidget {
  const BerandaTab({super.key});

  static const _cards = [
    _MateriStyle(Materi.huruf, Icons.menu_book_rounded, KogoColors.red400, KogoColors.red600),
    _MateriStyle(Materi.duaSuku, Icons.chat_bubble_rounded, KogoColors.orange400, KogoColors.orange600),
    _MateriStyle(Materi.tigaSuku, Icons.volume_up_rounded, KogoColors.teal400, KogoColors.teal600),
    _MateriStyle(Materi.beberapaKata, Icons.forum_rounded, KogoColors.purple500, KogoColors.purple700),
  ];

  void _greet() {
    final line = VoiceLines.greeting();
    unawaited(VoiceService.instance.say(line.text, mood: line.mood));
  }

  Future<void> _open(BuildContext context, Materi materi) async {
    AudioService.instance.play(Sfx.tap);
    await VoiceService.instance.stop();
    if (!context.mounted) return;
    await Navigator.of(context).push(StageMapPage.route(materi));
    await AppSession.instance.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: AppSession.instance, builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final session = AppSession.instance;
    final name = session.learner?.firstName;
    final stats = session.stats;
    return KogoBackground(
      colors: const [KogoColors.yellow100, KogoColors.orange50, KogoColors.pink50],
      decorations: const [
        FloatingDecoration('⭐', left: 28, top: 150, size: 36, tilt: 10),
        FloatingDecoration('✨', right: 36, top: 190, size: 30, lift: 15, tilt: -10, duration: Duration(milliseconds: 2500), delay: Duration(milliseconds: 500)),
        FloatingDecoration(
          '☁️',
          left: 40,
          bottom: 120,
          size: 46,
          opacity: 0.5,
          lift: 25,
          tilt: 0,
          duration: Duration(milliseconds: 3500),
          delay: Duration(seconds: 1),
        ),
        FloatingDecoration(
          '☁️',
          right: 24,
          bottom: 40,
          size: 38,
          opacity: 0.5,
          drift: 10,
          tilt: 0,
          duration: Duration(seconds: 4),
          delay: Duration(milliseconds: 1500),
        ),
      ],
      child: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            children: [
              Entrance.slide(
                fromOffset: const Offset(0, -50),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  decoration: const BoxDecoration(
                    color: KogoColors.white,
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(28), top: Radius.circular(12)),
                    boxShadow: [BoxShadow(color: Color(0x1F000000), blurRadius: 24, offset: Offset(0, 10))],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Kogo Belajar',
                        style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: KogoColors.gray800),
                      ),
                      const Text('Kogo Learning', style: TextStyle(fontSize: 14, color: KogoColors.gray500)),
                      const SizedBox(height: 12),
                      Loop(
                        duration: const Duration(seconds: 3),
                        rotateDeg: const [0, 10, -10, 10, 0],
                        dy: const [0, -10, 0],
                        child: Pressable(
                          onTap: _greet,
                          semanticLabel: 'Kogo menyapa',
                          child: const GradientCircle(
                            colors: [KogoColors.yellow300, KogoColors.orange400],
                            size: 128,
                            border: 4,
                            child: Text('🐻', style: TextStyle(fontSize: 64)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Entrance(
                        delay: const Duration(milliseconds: 500),
                        child: Text(
                          name == null ? 'Selamat datang di perjalanan belajarmu! 🎉' : 'Halo, $name! Selamat datang di perjalanan belajarmu! 🎉',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: KogoColors.teal600),
                        ),
                      ),
                      const SizedBox(height: 20),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 1.2,
                        children: [
                          for (var i = 0; i < _cards.length; i++)
                            Entrance(
                              delay: Duration(milliseconds: 600 + i * 100),
                              fromScale: 0,
                              fromTurns: -0.5,
                              child: _MateriCard(
                                style: _cards[i],
                                stars: stats.completedPerMateri[_cards[i].materi] ?? 0,
                                onTap: () => unawaited(_open(context, _cards[i].materi)),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Entrance.slide(
                delay: const Duration(milliseconds: 1000),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    _Chip(icon: '⭐', label: '${stats.totalStars} bintang'),
                    _Chip(icon: '🔥', label: '${stats.streakDays} hari beruntun'),
                    _Chip(icon: '🏆', label: '${stats.earnedTiers.length} hadiah'),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MateriStyle {
  const _MateriStyle(this.materi, this.icon, this.from, this.to);
  final Materi materi;
  final IconData icon;
  final Color from;
  final Color to;
}

class _MateriCard extends StatelessWidget {
  const _MateriCard({required this.style, required this.stars, required this.onTap});

  final _MateriStyle style;
  final int stars;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = Curriculum.nodesOf(style.materi).length;
    return Pressable(
      onTap: onTap,
      semanticLabel: '${style.materi.title}, $stars dari $total pelajaran selesai',
      pressedScale: 0.95,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
        decoration: BoxDecoration(
          gradient: KogoColors.br(style.from, style.to),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: style.from.withValues(alpha: 0.5), blurRadius: 16, offset: const Offset(0, 8))],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(style.icon, size: 40, color: KogoColors.white),
            const SizedBox(height: 6),
            Flexible(
              child: Text(
                style.materi.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: KogoColors.white, height: 1.15),
              ),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: total == 0 ? 0 : stars / total,
                minHeight: 6,
                backgroundColor: KogoColors.white.withValues(alpha: 0.35),
                valueColor: const AlwaysStoppedAnimation(KogoColors.white),
                semanticsLabel: 'Kemajuan ${style.materi.title}',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});
  final String icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: KogoColors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(99),
        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Text(
        '$icon $label',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: KogoColors.gray700),
      ),
    );
  }
}
