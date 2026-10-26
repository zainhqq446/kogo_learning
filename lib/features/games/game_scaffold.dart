import 'package:flutter/material.dart';

import '../../core/curriculum/curriculum.dart';
import '../../core/motion/motion.dart';
import '../../core/theme/kogo_colors.dart';
import '../../core/widgets/kogo_widgets.dart';
import '../../services/audio/voice_service.dart';

/// Kerangka halaman permainan sesuai desain Figma: header putih "Kembali",
/// latar gradien khas tiap permainan, indikator kemajuan, dan maskot Kogo.
class GameScaffold extends StatelessWidget {
  const GameScaffold({super.key, required this.game, required this.progress, required this.total, required this.child, required this.onExit, this.overlay});

  final GameType game;
  final int progress;
  final int total;
  final Widget child;
  final Future<bool> Function() onExit;
  final Widget? overlay;

  static List<Color> backgroundOf(GameType game) => switch (game) {
    GameType.listenRepeat => const [KogoColors.blue100, KogoColors.purple100],
    GameType.findObject => const [KogoColors.yellow100, KogoColors.green100],
    GameType.missingLetter => const [KogoColors.pink100, KogoColors.orange100],
    GameType.matching => const [KogoColors.purple100, KogoColors.blue100],
    GameType.listening => const [KogoColors.cyan100, KogoColors.blue100],
    GameType.fillBlank => const [KogoColors.green100, KogoColors.teal100],
  };

  /// Posisi maskot mengikuti desain Figma (kiri/kanan bawah).
  static bool _mascotOnLeft(GameType game) => game == GameType.missingLetter || game == GameType.listening;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await onExit() && navigator.mounted) navigator.pop();
      },
      child: Scaffold(
        body: KogoBackground(
          colors: backgroundOf(game),
          child: Stack(
            children: [
              Column(
                children: [
                  KogoHeader(
                    title: game.title,
                    onBack: () async {
                      final navigator = Navigator.of(context);
                      if (await onExit() && navigator.mounted) navigator.pop();
                    },
                  ),
                  _ProgressPills(progress: progress, total: total),
                  Expanded(child: SafeArea(top: false, child: child)),
                ],
              ),
              Positioned(
                bottom: 12,
                left: _mascotOnLeft(game) ? 12 : null,
                right: _mascotOnLeft(game) ? null : 12,
                child: IgnorePointer(
                  child: ListenableBuilder(
                    listenable: VoiceService.instance,
                    builder: (context, _) => Mascot(size: 52, speaking: VoiceService.instance.speaking),
                  ),
                ),
              ),
              ?overlay,
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressPills extends StatelessWidget {
  const _ProgressPills({required this.progress, required this.total});

  final int progress;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Soal ${progress + 1 > total ? total : progress + 1} dari $total',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
        child: Row(
          children: [
            for (var i = 0; i < total; i++)
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    gradient: i < progress
                        ? KogoColors.r(KogoColors.green400, KogoColors.emerald500)
                        : i == progress
                        ? KogoColors.r(KogoColors.yellow400, KogoColors.orange500)
                        : null,
                    color: i <= progress ? null : KogoColors.white.withValues(alpha: 0.7),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Konfirmasi keluar di tengah permainan.
Future<bool> confirmExitGame(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Berhenti bermain?'),
      content: const Text('Bintang dari permainan ini belum tersimpan.'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Ya, keluar')),
        FilledButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Lanjut main')),
      ],
    ),
  );
  return ok ?? false;
}

/// Umpan balik besar di tengah layar ("🎉 Benar!" / "😊 Coba Lagi!").
class FeedbackBadge extends StatelessWidget {
  const FeedbackBadge({super.key, required this.correct, this.title, this.subtitle});

  final bool correct;
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    // FittedBox: badge dipasang di slot bertinggi tetap; teks besar tidak boleh meluap.
    return Entrance.pop(
      key: ValueKey('fb-$correct-$title'),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Loop(
              duration: const Duration(milliseconds: 900),
              rotateDeg: correct ? const [0, 10, -10, 0] : const [0, -8, 8, 0],
              scale: correct ? const [1, 1.15, 1] : const [1],
              child: Text(correct ? '🎉' : '😊', style: const TextStyle(fontSize: 56)),
            ),
            const SizedBox(height: 4),
            Text(
              title ?? (correct ? 'Benar!' : 'Coba Lagi!'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: correct ? KogoColors.green600 : KogoColors.orange600),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, color: KogoColors.gray600),
              ),
          ],
        ),
      ),
    );
  }
}
