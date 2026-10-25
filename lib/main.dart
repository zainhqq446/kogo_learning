import 'dart:io';
import 'package:flutter/material.dart';

import 'core/telemetry/startup_telemetry.dart';
import 'core/theme/kogo_theme.dart';
import 'services/auth/session_manager.dart';

import 'features/splash/presentation/pages/splash_page.dart';


void main() async {
  StartupTelemetry.onMainStart();
  WidgetsFlutterBinding.ensureInitialized();
  StartupTelemetry.onAppStart();

  // Inisialisasi identitas perangkat lokal secara otomatis
  try {
    final sessionManager = SessionManager.instance;
    final devicePlatform = Platform.isAndroid
        ? 'android'
        : Platform.isIOS
            ? 'ios'
            : Platform.isWindows
                ? 'windows'
                : 'desktop';
    await sessionManager.initDevice(
      deviceId: 'dev_${Platform.operatingSystem}_001',
      deviceLabel: 'Kogo Local Device',
      platform: devicePlatform,
      appVersion: '1.0.0',
    );
  } catch (e) {
    debugPrint('[main] Device initialization info: $e');
  }

  runApp(const KogoTestApp());
}

class KogoTestApp extends StatelessWidget {
  const KogoTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Kogo Voice Learning',
      theme: KogoTheme.lightTheme,
      home: const SplashPage(),
    );
  }
}

