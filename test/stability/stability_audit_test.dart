import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/data/database/app_database.dart';
import 'package:kogo_voice_learning/data/models/lesson_model.dart';
import 'package:kogo_voice_learning/data/repositories/answer_log_repository.dart';
import 'package:kogo_voice_learning/features/activity/presentation/pages/question_page.dart';
import 'package:kogo_voice_learning/services/auth/session_manager.dart';
import 'package:kogo_voice_learning/services/speech/mock_speech_recognition_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:kogo_voice_learning/services/audio/voice_interaction_controller.dart';
import '../mocks/mock_speech_output_provider.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    VoiceInteractionController.instance.setProviderForTesting(MockSpeechOutputProvider());
    await AppDatabase.instance.deleteDatabase();
    await AppDatabase.instance.database;

    final sessionManager = SessionManager.instance;
    await sessionManager.initDevice(deviceId: 'dev_stability_test');
    await sessionManager.loginChild(childCode: 'P001', pin: '1234');
    await sessionManager.startResearchSession(notes: 'Sesi audit stability');
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  group('Stability and Reliability Audit Tests', () {
    testWidgets('Microphone releases and state reverts to idle on app pause/inactive lifecycle', (tester) async {
      final mockProvider = MockSpeechRecognitionProvider(
        name: 'lifecycle_test_provider',
      );

      final lesson = LessonModel(
        id: 1,
        stageId: 1,
        title: 'Huruf A-E',
        lessonType: 'listen_repeat',
        orderIndex: 1,
        isActive: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: QuestionPage(
            lesson: lesson,
            speechProvider: mockProvider,
          ),
        ),
      );

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      // Start recording
      final micButton = find.byIcon(Icons.mic_rounded);
      expect(micButton, findsOneWidget);
      await tester.tap(micButton);
      await tester.pump();

      expect(mockProvider.isListening, isTrue);

      // Trigger app inactive / paused
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      // Microphone MUST be released and provider should not be listening
      expect(mockProvider.isListening, isFalse);
    });

    test('Concurrent logAnswer calls preserve atomic attempt numbering without duplicate attempts', () async {
      final repo = AnswerLogRepository();
      final child = SessionManager.instance.currentChild!;
      final session = SessionManager.instance.currentSession!;
      final device = SessionManager.instance.currentDevice!;

      // Run 5 simultaneous logAnswer attempts
      final futures = List.generate(5, (index) {
        return repo.logAnswer(
          childId: child.id!,
          deviceId: device.id!,
          sessionId: session.id!,
          questionId: 1,
          targetText: 'A',
          recognizedText: 'A',
          normalizedTarget: 'a',
          normalizedRecognized: 'a',
          editDistance: 0,
          similarityScore: 1.0,
          similarityPercent: 100.0,
          isCorrect: true,
        );
      });

      final results = await Future.wait(futures);
      final attemptNumbers = results.map((r) => r.attemptNumber).toList();

      // Verify that all attempt numbers are strictly unique
      final uniqueAttempts = attemptNumbers.toSet();
      expect(uniqueAttempts.length, equals(5));
      expect(attemptNumbers, containsAll([1, 2, 3, 4, 5]));
    });
  });
}
