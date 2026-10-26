import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_session.dart';
import '../../services/audio/audio_service.dart';
import '../home/beranda_tab.dart';
import '../profile/profil_tab.dart';
import '../rewards/hadiah_tab.dart';
import 'bottom_nav.dart';

/// Halaman utama dengan tiga tab (proposal Gambar 3.23: Beranda, Pencapaian,
/// Profil). Tombol kembali Android di tab lain kembali ke Beranda.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  static const routeName = 'home';

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    unawaited(AudioService.instance.stopMusic());
  }

  void _select(int index) {
    if (index == _index) return;
    AudioService.instance.play(Sfx.tap);
    setState(() => _index = index);
    if (index == 1) unawaited(AppSession.instance.markRewardsSeen());
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: ListenableBuilder(
        listenable: AppSession.instance,
        builder: (context, _) {
          return Scaffold(
            body: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: KeyedSubtree(
                key: ValueKey(_index),
                child: switch (_index) {
                  0 => const BerandaTab(),
                  1 => const HadiahTab(),
                  _ => const ProfilTab(),
                },
              ),
            ),
            bottomNavigationBar: KogoBottomNav(index: _index, onTap: _select, rewardBadge: AppSession.instance.stats.unseenRewards),
          );
        },
      ),
    );
  }
}
