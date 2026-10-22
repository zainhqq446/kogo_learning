import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kogo_voice_learning/features/home/presentation/pages/home_page.dart';
import 'package:kogo_voice_learning/features/stage/presentation/pages/stage_page.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('HomePage renders child-friendly welcome, cards, and navigates', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomePage(),
      ),
    );

    await tester.pump();

    // 1. Cek elemen selamat datang
    expect(find.textContaining('Halo,'), findsOneWidget);
    expect(find.text('Ayo belajar bicara & bersuara hari ini!'), findsOneWidget);

    // 2. Cek banner hero
    expect(find.text('Kogo Voice Learning'), findsOneWidget);
    expect(find.text('Mulai Belajar Sekarang'), findsOneWidget);

    // 3. Cek kartu menu cepat
    expect(find.text('Tahap Belajar'), findsOneWidget);
    expect(find.text('Pencapaian'), findsOneWidget);

    // 4. Navigasi ke StagePage via banner tombol
    await tester.tap(find.text('Mulai Belajar Sekarang'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(StagePage), findsOneWidget);
  });
}
