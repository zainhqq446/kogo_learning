import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/curriculum/curriculum.dart';
import '../../core/motion/motion.dart';
import '../../core/theme/kogo_colors.dart';
import '../../core/widgets/kogo_widgets.dart';
import '../../data/progress_repository.dart';
import '../../services/audio/audio_service.dart';
import '../../services/audio/voice_lines.dart';
import '../../services/audio/voice_service.dart';

enum RewardAction { next, replay, home }

/// Halaman hadiah setelah permainan selesai (proposal: "sistem memberikan
/// bintang dan pengguna dapat memilih untuk melanjutkan ke tahap berikutnya
/// atau kembali ke halaman utama").
class RewardDialog extends StatefulWidget {
  const RewardDialog({super.key, required this.stars, required this.newTiers, required this.hasNext});

  final int stars;
  final List<RewardTier> newTiers;
  final bool hasNext;

  static Future<RewardAction> show(BuildContext context, {required GameResult? result, required int fallbackStars, required bool hasNext}) async {
    final action = await showGeneralDialog<RewardAction>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, _, _) => RewardDialog(stars: result?.stars ?? fallbackStars, newTiers: result?.newTiers ?? const [], hasNext: hasNext),
      transitionBuilder: (_, animation, _, child) => ScaleTransition(
        scale: CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
        child: child,
      ),
    );
    return action ?? RewardAction.home;
  }

  @override
  State<RewardDialog> createState() => _RewardDialogState();
}

class _RewardDialogState extends State<RewardDialog> {
  int _shown = 0;
  final List<Timer> _timers = [];

  @override
  void initState() {
    super.initState();
    AudioService.instance.play(Sfx.complete);
    for (var i = 0; i < widget.stars; i++) {
      _timers.add(
        Timer(Duration(milliseconds: 450 + i * 380), () {
          if (!mounted) return;
          setState(() => _shown = i + 1);
          AudioService.instance.play(Sfx.star);
        }),
      );
    }
    final line = widget.newTiers.isNotEmpty ? VoiceLines.newReward(widget.newTiers.last) : VoiceLines.completion(widget.stars);
    unawaited(VoiceService.instance.say(line.text, mood: line.mood));
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  void _close(RewardAction action) {
    unawaited(VoiceService.instance.stop());
    Navigator.of(context).pop(action);
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.stars) {
      3 => 'Sempurna!',
      2 => 'Hebat!',
      _ => 'Bagus!',
    };
    return PopScope(
      canPop: false,
      child: Stack(
        children: [
          const Positioned.fill(child: ConfettiRain(count: 24)),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Material(
                color: Colors.transparent,
                child: KogoCard(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Loop(
                        duration: const Duration(seconds: 2),
                        dy: const [0, -12, 0],
                        rotateDeg: const [0, 10, -10, 0],
                        child: const Text('🎉', style: TextStyle(fontSize: 72)),
                      ),
                      Text(
                        title,
                        style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: KogoColors.purple600),
                      ),
                      const SizedBox(height: 12),
                      Semantics(
                        label: 'Kamu mendapat ${widget.stars} bintang',
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < 3; i++)
                              Padding(
                                padding: EdgeInsets.only(left: 6, right: 6, bottom: i == 1 ? 18 : 0),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 400),
                                  transitionBuilder: (child, a) => ScaleTransition(
                                    scale: CurvedAnimation(parent: a, curve: Curves.elasticOut),
                                    child: child,
                                  ),
                                  child: Icon(
                                    i < _shown ? Icons.star_rounded : Icons.star_outline_rounded,
                                    key: ValueKey(i < _shown),
                                    size: i == 1 ? 72 : 58,
                                    color: i < _shown ? KogoColors.yellow400 : KogoColors.gray300,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '+${widget.stars} bintang',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: KogoColors.gray600),
                      ),
                      for (final tier in widget.newTiers) ...[
                        const SizedBox(height: 14),
                        Entrance.pop(
                          delay: const Duration(milliseconds: 1500),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              gradient: KogoColors.r(KogoColors.purple400, KogoColors.pink500),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '🏆 Hadiah ${tier.title} terbuka!',
                              style: const TextStyle(color: KogoColors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
                      if (widget.hasNext) GradientButton(label: 'Lanjut', icon: Icons.play_arrow_rounded, expand: true, onTap: () => _close(RewardAction.next)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: GradientButton(
                              label: 'Ulangi',
                              icon: Icons.replay_rounded,
                              colors: const [KogoColors.blue500, KogoColors.purple500],
                              fontSize: 16,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              onTap: () => _close(RewardAction.replay),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GradientButton(
                              label: 'Beranda',
                              icon: Icons.home_rounded,
                              colors: const [KogoColors.orange400, KogoColors.red500],
                              fontSize: 16,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                              onTap: () => _close(RewardAction.home),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
