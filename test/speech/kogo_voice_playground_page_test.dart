import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/features/speech/presentation/pages/kogo_voice_playground_page.dart';
import 'package:kogo_voice_learning/services/audio/kogo_voice_manager.dart';
import 'package:kogo_voice_learning/services/audio/voice_cache.dart';
import 'package:kogo_voice_learning/services/audio/voice_message_planner.dart';
import '../mocks/mock_speech_output_provider.dart';

void main() {
  group('Kogo Voice Playground Widget & Integration Tests', () {
    late MockSpeechOutputProvider mockProvider;

    setUp(() {
      mockProvider = MockSpeechOutputProvider();
      KogoVoiceManager.instance.setProviderForTesting(mockProvider);
      VoiceMessagePlanner.instance.resetHistory();
      VoiceCache.instance.clear();
    });

    testWidgets('1. Renders all key components and controls', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: KogoVoicePlaygroundPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Title
      expect(find.text('Kogo Voice Playground'), findsOneWidget);

      // Category chips
      expect(find.widgetWithText(ChoiceChip, 'INTRO'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'INSTRUCTION'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'CORRECT'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'ALMOST CORRECT'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'INCORRECT'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'RETRY'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'STREAK'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'TRANSITION'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'COMPLETION'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'NO RECOGNITION'), findsOneWidget);

      // Action buttons
      expect(find.byKey(const Key('kogo_voice_playground_play_btn')), findsOneWidget);
      expect(find.byKey(const Key('kogo_voice_playground_stop_btn')), findsOneWidget);
      expect(find.byKey(const Key('kogo_voice_playground_seq_btn')), findsOneWidget);
      expect(find.byKey(const Key('kogo_voice_playground_err_seq_btn')), findsOneWidget);

      // Context controls
      expect(find.text('Uji Parameter Konteks (Context Test)'), findsOneWidget);
      expect(find.text('Stage:'), findsOneWidget);
      expect(find.text('Activity:'), findsOneWidget);
    });

    testWidgets('2. Play triggers voice synthesis and updates status', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: KogoVoicePlaygroundPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Play
      await tester.tap(find.byKey(const Key('kogo_voice_playground_play_btn')));
      await tester.pumpAndSettle();

      expect(mockProvider.spokenTexts.isNotEmpty, isTrue);
      expect(find.textContaining('Completed'), findsOneWidget);
    });

    testWidgets('3. Category switching loads appropriate variations', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: KogoVoicePlaygroundPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Select INTRO
      await tester.tap(find.widgetWithText(ChoiceChip, 'INTRO'));
      await tester.pumpAndSettle();

      expect(find.text('Category:'), findsOneWidget);
      expect(find.text('INTRO'), findsNWidgets(2)); // chip and telemetry
    });

    testWidgets('4. Sequence playback plays multiple phrases sequentially', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        const MaterialApp(
          home: KogoVoicePlaygroundPage(),
        ),
      );
      await tester.pumpAndSettle();

      final seqBtn = find.byKey(const Key('kogo_voice_playground_seq_btn'));
      await tester.ensureVisible(seqBtn);
      await tester.tap(seqBtn);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(mockProvider.spokenTexts.length, greaterThanOrEqualTo(3));
    });

    testWidgets('5. Stop button halts playback immediately', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: KogoVoicePlaygroundPage(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('kogo_voice_playground_play_btn')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('kogo_voice_playground_stop_btn')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Idle (Stopped)'), findsOneWidget);
    });
  });
}
