import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/core/theme/kogo_theme.dart';

/// Memajukan waktu palsu secara bertahap (jeda suara Kogo memakai timer).
Future<void> settle(WidgetTester tester, {Duration total = const Duration(seconds: 6)}) async {
  const step = Duration(milliseconds: 100);
  for (var t = Duration.zero; t < total; t += step) {
    await tester.pump(step);
  }
}

Widget testApp(Widget home) => MaterialApp(theme: KogoTheme.light, home: home);

/// Ukuran layar ponsel umum (360 x 740 dp) agar tata letak teruji realistis.
void usePhoneSize(WidgetTester tester, {Size size = const Size(360, 740)}) {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}
