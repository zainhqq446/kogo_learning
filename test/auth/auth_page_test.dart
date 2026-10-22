import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/core/theme/kogo_theme.dart';
import 'package:kogo_voice_learning/features/auth/presentation/pages/auth_page.dart';

void main() {
  testWidgets('AuthPage renders tabs for Child and Researcher and inputs', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        theme: KogoTheme.lightTheme,
        home: const AuthPage(),
      ),
    );


    // Verifikasi teks header dan tab
    expect(find.text('Kogo Voice Learning'), findsOneWidget);
    expect(find.text('Anak / Peserta'), findsOneWidget);
    expect(find.text('Guru / Peneliti'), findsOneWidget);

    // Verifikasi input pada tab Anak
    expect(find.text('Masuk Akun Anak'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Mulai Belajar Sekarang!'), findsOneWidget);

    // Beralih ke tab Guru / Peneliti
    await tester.tap(find.text('Guru / Peneliti'));
    await tester.pumpAndSettle();

    // Verifikasi komponen tab Peneliti
    expect(find.text('Login Guru / Peneliti'), findsOneWidget);
    expect(find.text('Daftar Baru'), findsOneWidget);
    expect(find.text('Masuk Dashboard Peneliti'), findsOneWidget);

    // Uji klik Daftar Baru
    await tester.tap(find.text('Daftar Baru'));
    await tester.pumpAndSettle();
    expect(find.text('Daftar Peneliti Baru'), findsOneWidget);
    expect(find.text('Daftar & Masuk'), findsOneWidget);
  });
}
