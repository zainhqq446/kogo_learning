import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/app/app_session.dart';
import 'package:kogo_voice_learning/core/curriculum/curriculum.dart';
import 'package:kogo_voice_learning/features/biodata/biodata_page.dart';
import 'package:kogo_voice_learning/features/games/reward_dialog.dart';
import 'package:kogo_voice_learning/features/map/stage_map_page.dart';
import 'package:kogo_voice_learning/features/shell/home_shell.dart';
import 'package:kogo_voice_learning/features/splash/splash_page.dart';
import 'package:kogo_voice_learning/main.dart';

import '../helpers/fakes.dart';
import '../helpers/pump.dart';
import '../helpers/test_env.dart';

void main() {
  late FakeSpeechListener listener;

  setUp(() async {
    listener = (await resetTestEnv()).listener;
  });

  testWidgets('first launch: splash → biodata (validation) → home', (tester) async {
    usePhoneSize(tester);
    await tester.pumpWidget(const KogoApp(home: SplashPage(minDuration: Duration(milliseconds: 200))));
    await settle(tester, total: const Duration(seconds: 2));
    expect(find.byType(BiodataPage), findsOneWidget);
    expect(find.text('Nama'), findsOneWidget);
    expect(find.text('Sekolah'), findsOneWidget);
    expect(find.text('Umur'), findsOneWidget);

    // Data belum lengkap → pesan kesalahan (proposal Gambar 3.4).
    await tester.tap(find.text('Selesai'));
    await settle(tester, total: const Duration(seconds: 1));
    expect(find.text('Nama belum diisi'), findsOneWidget);
    expect(find.text('Sekolah belum diisi'), findsOneWidget);
    expect(find.text('Umur harus 5 atau 6 tahun'), findsNothing);
    expect(find.text('Pilih umur'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Nama'), 'Sarah Putri');
    await tester.enterText(find.widgetWithText(TextFormField, 'Sekolah'), 'TK Pertiwi');
    await tester.tap(find.text('🎂 6 tahun'));
    await tester.pump();
    await tester.ensureVisible(find.text('Selesai'));
    await tester.tap(find.text('Selesai'));
    await settle(tester, total: const Duration(seconds: 1));

    // Dialog izin mikrofon lalu masuk Beranda.
    expect(find.text('Lanjut'), findsOneWidget);
    await tester.tap(find.text('Lanjut'));
    await settle(tester, total: const Duration(seconds: 2));
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.textContaining('Halo, Sarah! Selamat datang'), findsOneWidget);
    for (final m in Materi.values) {
      expect(find.text(m.title), findsOneWidget);
    }
    expect(AppSession.instance.learner!.age, 6);
  });

  testWidgets('returning user goes straight to home', (tester) async {
    usePhoneSize(tester);
    await tester.runAsync(() async {
      final kid = await AppSession.instance.learners.create(name: 'Budi', school: 'TK Melati', age: 5);
      await AppSession.instance.learners.setActive(kid.id);
    });
    await tester.pumpWidget(const KogoApp(home: SplashPage(minDuration: Duration(milliseconds: 200))));
    await settle(tester, total: const Duration(seconds: 2));
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.textContaining('Halo, Budi! Selamat datang'), findsOneWidget);
  });

  testWidgets('map: only first node open; playing Listen & Repeat earns stars and unlocks next', (tester) async {
    usePhoneSize(tester);
    await tester.runAsync(() async {
      final kid = await AppSession.instance.learners.create(name: 'Sarah', school: 'TK Pertiwi', age: 6);
      await AppSession.instance.activate(kid);
    });
    await tester.pumpWidget(const KogoApp(home: HomeShell()));
    await settle(tester, total: const Duration(seconds: 1));

    await tester.tap(find.text('Kata Dua Suku Kata'));
    await settle(tester, total: const Duration(seconds: 2));
    expect(find.byType(StageMapPage), findsOneWidget);
    expect(find.text('Mulai Di Sini! 👆'), findsOneWidget);

    // Node terkunci tidak bisa dibuka.
    await tester.tap(find.text('Cari Objek').first, warnIfMissed: false);
    await settle(tester, total: const Duration(seconds: 1));
    expect(find.text('Tekan mikrofon dan ucapkan!'), findsNothing);

    // Mainkan Dengar & Ulangi: semua kata diucapkan benar pada percobaan pertama.
    final words = Curriculum.nodesOf(Materi.duaSuku).first.unit.items;
    for (final w in words) {
      listener.say(w.text);
    }
    await tester.tap(find.text('Dengar & Ulangi').first);
    await settle(tester, total: const Duration(seconds: 3));
    expect(find.text('BOLA'), findsOneWidget);

    for (var i = 0; i < words.length; i++) {
      await tester.tap(find.bySemanticsLabel('Tekan untuk berbicara'));
      await settle(tester, total: const Duration(seconds: 2));
      expect(find.text('Bagus sekali! 🎉'), findsOneWidget);
      await tester.tap(find.text('Lanjutkan'));
      await settle(tester, total: const Duration(seconds: 3));
    }

    expect(find.byType(RewardDialog), findsOneWidget);
    expect(find.text('Sempurna!'), findsOneWidget);
    expect(find.text('+3 bintang'), findsOneWidget);
    expect(listener.acceptResults, everyElement(isTrue));

    await tester.tap(find.text('Beranda'));
    await settle(tester, total: const Duration(seconds: 2));
    expect(find.byType(HomeShell), findsOneWidget);
    expect(AppSession.instance.stats.totalStars, 3);
    expect(find.text('⭐ 3 bintang'), findsOneWidget);

    await tester.tap(find.text('Kata Dua Suku Kata'));
    await settle(tester, total: const Duration(seconds: 2));
    // Node kedua (Cari Objek) sekarang terbuka sebagai "sekarang".
    final stars = await tester.runAsync(() => AppSession.instance.progress.starsFor(AppSession.instance.learner!.id, Materi.duaSuku));
    expect(stars, {0: 3});
    expect(find.text('Mulai Di Sini! 👆'), findsOneWidget);
  });
}
