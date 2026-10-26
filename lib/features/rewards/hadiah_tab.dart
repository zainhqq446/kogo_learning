import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_session.dart';
import '../../core/curriculum/curriculum.dart';
import '../../core/motion/motion.dart';
import '../../core/theme/kogo_colors.dart';
import '../../core/widgets/kogo_widgets.dart';
import '../../services/audio/voice_lines.dart';
import '../../services/audio/voice_service.dart';

/// Tab Hadiah / Pencapaian (proposal Gambar 3.10, 3.18, 3.29): tingkatan
/// Perunggu, Perak, Emas, Berlian berdasarkan total bintang.
class HadiahTab extends StatefulWidget {
  const HadiahTab({super.key});

  @override
  State<HadiahTab> createState() => _HadiahTabState();
}

class _HadiahTabState extends State<HadiahTab> {
  @override
  void initState() {
    super.initState();
    final line = VoiceLines.rewardsPage(AppSession.instance.stats.totalStars);
    unawaited(VoiceService.instance.say(line.text, mood: line.mood));
  }

  static ({List<Color> colors, IconData icon}) _styleOf(RewardTier tier) => switch (tier) {
    RewardTier.perunggu => (colors: const [KogoColors.orange400, KogoColors.amber600], icon: Icons.emoji_events_rounded),
    RewardTier.perak => (colors: const [KogoColors.gray300, KogoColors.gray500], icon: Icons.star_rounded),
    RewardTier.emas => (colors: const [KogoColors.yellow400, KogoColors.yellow600], icon: Icons.workspace_premium_rounded),
    RewardTier.berlian => (colors: const [KogoColors.cyan400, KogoColors.blue600], icon: Icons.diamond_rounded),
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: AppSession.instance, builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final stars = AppSession.instance.stats.totalStars;
    final next = RewardTier.values.where((t) => !t.isEarned(stars)).firstOrNull;
    return KogoBackground(
      colors: const [KogoColors.amber100, KogoColors.yellow50, KogoColors.orange50],
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
                      Icon(Icons.emoji_events_rounded, size: 28, color: KogoColors.yellow600),
                      SizedBox(width: 10),
                      Text(
                        'Hadiah',
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
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              children: [
                Center(
                  child: Entrance(
                    fromScale: 0,
                    fromTurns: -0.5,
                    child: Loop(
                      duration: const Duration(seconds: 2),
                      dy: const [0, -15, 0],
                      rotateDeg: const [0, 10, -10, 0],
                      child: const Text('🎉', style: TextStyle(fontSize: 88)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Entrance.pop(
                    delay: const Duration(milliseconds: 300),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                      decoration: BoxDecoration(
                        color: KogoColors.white,
                        borderRadius: BorderRadius.circular(99),
                        boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 4))],
                      ),
                      child: Text(
                        '⭐ $stars bintang terkumpul',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: KogoColors.gray800),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                for (final (i, tier) in RewardTier.values.indexed) ...[
                  Entrance(
                    delay: Duration(milliseconds: 150 * i),
                    fromOffset: Offset(i.isEven ? -50 : 50, 0),
                    fromOpacity: 0,
                    child: _TierCard(tier: tier, stars: stars, style: _styleOf(tier), delay: 500 + 150 * i),
                  ),
                  const SizedBox(height: 18),
                ],
                Entrance.slide(
                  delay: const Duration(milliseconds: 1000),
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: KogoColors.r(KogoColors.purple400, KogoColors.pink500),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [BoxShadow(color: Color(0x33EC4899), blurRadius: 20, offset: Offset(0, 8))],
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Terus Belajar! 🌟',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: KogoColors.white),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          next == null
                              ? 'Semua hadiah sudah kamu dapatkan. Luar biasa!'
                              : 'Kumpulkan ${next.minStars - stars} bintang lagi untuk membuka hadiah ${next.title}!',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 15, color: KogoColors.white.withValues(alpha: 0.95)),
                        ),
                      ],
                    ),
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

class _TierCard extends StatelessWidget {
  const _TierCard({required this.tier, required this.stars, required this.style, required this.delay});

  final RewardTier tier;
  final int stars;
  final ({List<Color> colors, IconData icon}) style;
  final int delay;

  Widget _badge() => GradientCircle(
    colors: style.colors,
    size: 76,
    border: 4,
    child: Icon(style.icon, size: 38, color: KogoColors.white),
  );

  @override
  Widget build(BuildContext context) {
    final earned = tier.isEarned(stars);
    final percent = tier.progressPercent(stars);
    return KogoCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              earned
                  ? _badge()
                  : Opacity(
                      opacity: 0.55,
                      child: ColorFiltered(
                        colorFilter: const ColorFilter.matrix([
                          0.33, 0.33, 0.33, 0, 0, //
                          0.33, 0.33, 0.33, 0, 0, //
                          0.33, 0.33, 0.33, 0, 0, //
                          0, 0, 0, 1, 0,
                        ]),
                        child: _badge(),
                      ),
                    ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            tier.title,
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: KogoColors.gray800),
                          ),
                        ),
                        if (earned) ...[
                          const SizedBox(width: 6),
                          Entrance.pop(
                            delay: Duration(milliseconds: delay),
                            child: const Icon(Icons.star_rounded, color: KogoColors.yellow500, size: 24),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: Container(
                        height: 12,
                        color: KogoColors.gray200,
                        alignment: Alignment.centerLeft,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: percent / 100),
                          duration: Duration(milliseconds: Motion.of(context) ? 1000 : 0),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, _) => FractionallySizedBox(
                            widthFactor: value,
                            child: Container(decoration: BoxDecoration(gradient: KogoColors.r(style.colors.first, style.colors.last))),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      earned ? 'Selesai! 🎊' : '$percent% Selesai · butuh ${tier.minStars} ⭐',
                      style: const TextStyle(fontSize: 13, color: KogoColors.gray500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (earned) ...[
            const SizedBox(height: 14),
            Entrance.pop(
              delay: Duration(milliseconds: delay + 200),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(gradient: KogoColors.r(KogoColors.green400, KogoColors.emerald500), borderRadius: BorderRadius.circular(99)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_rounded, color: KogoColors.white, size: 18),
                    SizedBox(width: 4),
                    Text(
                      'Diraih!',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: KogoColors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
