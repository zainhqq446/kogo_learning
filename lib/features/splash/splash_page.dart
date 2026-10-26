import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_session.dart';
import '../../core/motion/motion.dart';
import '../../core/theme/kogo_colors.dart';
import '../../services/audio/voice_service.dart';
import '../biodata/biodata_page.dart';
import '../shell/home_shell.dart';

/// Splash screen (proposal Gambar 3.21; desain Figma): beruang Kogo berputar
/// masuk, nama aplikasi, dan tiga titik pemuatan. Selama splash, database,
/// profil terakhir, dan mesin suara disiapkan.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key, this.minDuration = const Duration(milliseconds: 2500)});

  final Duration minDuration;

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    bool hasProfile = false;
    await Future.wait([
      Future<void>.delayed(widget.minDuration),
      () async {
        try {
          hasProfile = await AppSession.instance.restore();
        } catch (e) {
          debugPrint('[Splash] gagal memuat profil: $e');
        }
      }(),
      VoiceService.instance.init().catchError((_) => false),
    ]);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        settings: RouteSettings(name: hasProfile ? HomeShell.routeName : 'biodata'),
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (_, _, _) => hasProfile ? const HomeShell() : const BiodataPage(),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(gradient: KogoColors.b(const [KogoColors.amber100, KogoColors.orange50])),
        child: Center(
          child: Entrance(
            duration: const Duration(milliseconds: 1000),
            fromScale: 0,
            fromTurns: -0.5,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Loop(
                  duration: const Duration(seconds: 2),
                  dy: const [0, -20, 0],
                  rotateDeg: const [0, 5, -5, 0],
                  child: const Text('🐻', style: TextStyle(fontSize: 120)),
                ),
                const SizedBox(height: 12),
                const Entrance.slide(
                  delay: Duration(milliseconds: 500),
                  child: Column(
                    children: [
                      Text(
                        'Kogo',
                        style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: KogoColors.red600),
                      ),
                      SizedBox(height: 4),
                      Text('Petualangan Belajar', style: TextStyle(fontSize: 18, color: KogoColors.gray600)),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Loop(
                          duration: const Duration(seconds: 1),
                          delay: Duration(milliseconds: 200 * i),
                          scale: const [1, 1.5, 1],
                          opacity: const [0.5, 1, 0.5],
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(color: KogoColors.red500, shape: BoxShape.circle),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
