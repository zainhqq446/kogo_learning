import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme/kogo_theme.dart';
import 'data/app_settings.dart';
import 'features/splash/splash_page.dart';
import 'services/audio/audio_service.dart';
import 'services/audio/voice_service.dart';
import 'services/sync/sync_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const KogoApp());
}

class KogoApp extends StatefulWidget {
  const KogoApp({super.key, this.home});

  /// Halaman awal (dapat diganti pada pengujian).
  final Widget? home;

  @override
  State<KogoApp> createState() => _KogoAppState();
}

class _KogoAppState extends State<KogoApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () {
        unawaited(VoiceService.instance.stop());
        unawaited(AudioService.instance.setAppPaused(true));
      },
      onShow: () => unawaited(AudioService.instance.setAppPaused(false)),
      onResume: () => SyncService.instance.syncInBackground(),
    );
    unawaited(_loadAudioSettings());
  }

  Future<void> _loadAudioSettings() async {
    if (AudioService.disabled) return;
    try {
      final settings = AppSettings();
      AudioService.instance.soundOn = await settings.getBool(AppSettings.soundOnKey);
      await AudioService.instance.setMusicOn(await settings.getBool(AppSettings.musicOnKey));
    } catch (e) {
      debugPrint('[KogoApp] gagal memuat pengaturan suara: $e');
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kogo Belajar',
      debugShowCheckedModeBanner: false,
      theme: KogoTheme.light,
      locale: const Locale('id'),
      supportedLocales: const [Locale('id'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: widget.home ?? const SplashPage(),
    );
  }
}
