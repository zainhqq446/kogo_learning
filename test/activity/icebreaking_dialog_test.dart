import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/core/theme/kogo_theme.dart';
import 'package:kogo_voice_learning/features/activity/presentation/pages/icebreaking_dialog.dart';

import 'package:kogo_voice_learning/services/audio/voice_interaction_controller.dart';
import '../mocks/mock_speech_output_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    VoiceInteractionController.instance.setProviderForTesting(MockSpeechOutputProvider());
  });


  testWidgets('IcebreakingDialog renders correctly for Color Balloons mini-game', (
    WidgetTester tester,
  ) async {
    bool continued = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: KogoTheme.lightTheme,
        home: Scaffold(
          body: IcebreakingDialog(
            type: IcebreakingType.colorBalloons,
            onContinue: () {
              continued = true;
            },
          ),
        ),
      ),
    );

    await tester.pump();

    // Verifikasi teks header mini-game
    expect(find.text('Letuskan Balon! 🎈'), findsOneWidget);
    expect(find.text('Ketuk semua balon warna-warni sampai meletus!'), findsOneWidget);

    // Verifikasi tombol lanjut
    expect(find.text('Lewati / Lanjut ⏩'), findsOneWidget);

    // Tekan tombol Lewati / Lanjut
    await tester.tap(find.text('Lewati / Lanjut ⏩'));
    await tester.pump();

    expect(continued, isTrue);
  });
}


