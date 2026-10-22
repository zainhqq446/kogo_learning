import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kogo_voice_learning/data/database/app_database.dart';
import 'package:kogo_voice_learning/data/models/lesson_model.dart';
import 'package:kogo_voice_learning/data/repositories/answer_log_repository.dart';
import 'package:kogo_voice_learning/data/repositories/lesson_repository.dart';
import 'package:kogo_voice_learning/features/activity/presentation/pages/question_page.dart';
import 'package:kogo_voice_learning/services/auth/session_manager.dart';
import 'package:kogo_voice_learning/services/speech/mock_speech_recognition_provider.dart';
import 'package:kogo_voice_learning/services/speech/speech_recognition_result_model.dart';

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

    // Siapkan sesi aktif untuk pengetesan log jawaban
    final sessionManager = SessionManager.instance;
    await sessionManager.initDevice(deviceId: 'dev_test_listen_repeat');
    await sessionManager.loginChild(childCode: 'P001', pin: '1234');
    await sessionManager.startResearchSession(notes: 'Sesi integrasi Listen & Repeat');
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  testWidgets('Integration: Listen & Repeat voice recognition, evaluation, and attempt numbering in answer_logs', (
    WidgetTester tester,
  ) async {
    final mockProvider = MockSpeechRecognitionProvider();
    final answerLogRepo = AnswerLogRepository();
    final session = SessionManager.instance.currentSession!;
    final child = SessionManager.instance.currentChild!;

    final lessonRepo = LessonRepository();
    late LessonModel lesson;
    await tester.runAsync(() async {
      final lessons = await lessonRepo.getByStageId(1);
      lesson = lessons.firstWhere((l) => l.lessonType == 'listen_repeat');
    });

    await tester.pumpWidget(
      MaterialApp(
        home: QuestionPage(
          lesson: lesson,
          speechProvider: mockProvider,
        ),
      ),
    );

    // Biarkan FutureBuilder membaca questions dari SQLite
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    // 1. Verifikasi UI awal: target word 'A', tombol mikrofon besar tersedia
    expect(find.text('Ucapkan:'), findsOneWidget);
    expect(find.text('A'), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(find.text('Tekan Mikrofon untuk Berbicara'), findsOneWidget);

    // 2. ATTEMPT 1: Anak menekan mikrofon -> mulai recording
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump();

    expect(mockProvider.isListening, isTrue);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.text('Sedang Mendengarkan... (Tekan untuk berhenti)'), findsOneWidget);

    // Simulasi anak mengucapkan "B" (salah untuk target "A")
    await tester.runAsync(() async {
      mockProvider.emitResult(const SpeechRecognitionResultModel(
        recognizedText: 'B',
        confidence: 0.92,
        duration: Duration(milliseconds: 300),
        provider: 'mock_whisper',
        locale: 'id_ID',
        isFinal: true,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();

    // Evaluator berjalan: jawaban salah dievaluasi
    expect(find.text('Coba Sekali Lagi'), findsOneWidget);
    expect(find.text('Terdengar: "B"'), findsOneWidget);

    // Verifikasi database: attempt 1 tersimpan dengan nomor 1
    late List<AnswerLogModel> logs;
    await tester.runAsync(() async {
      logs = await answerLogRepo.getLogsForQuestion(
        childId: child.id!,
        sessionId: session.id!,
        questionId: 1,
      );
    });
    expect(logs.length, equals(1));
    expect(logs[0].attemptNumber, equals(1));
    expect(logs[0].targetText, equals('A'));
    expect(logs[0].recognizedText, equals('B')); // recognizedText TIDAK diubah paksa menjadi A
    expect(logs[0].isCorrect, isFalse);
    expect(logs[0].editDistance, equals(1));

    // 3. ATTEMPT 2: Anak menekan mikrofon lagi untuk mencoba ulang pertanyaan yang sama
    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump();

    expect(mockProvider.isListening, isTrue);

    // Simulasi anak mengucapkan "A" (benar untuk target "A")
    await tester.runAsync(() async {
      mockProvider.emitResult(const SpeechRecognitionResultModel(
        recognizedText: 'A',
        confidence: 0.98,
        duration: Duration(milliseconds: 350),
        provider: 'mock_whisper',
        locale: 'id_ID',
        isFinal: true,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();

    // Evaluator berjalan: jawaban benar
    expect(find.text('Hebat! Tepat Sekali'), findsOneWidget);
    expect(find.text('Terdengar: "A"'), findsOneWidget);

    // Verifikasi database: attempt 2 tersimpan dengan nomor 2 secara berurutan
    await tester.runAsync(() async {
      logs = await answerLogRepo.getLogsForQuestion(
        childId: child.id!,
        sessionId: session.id!,
        questionId: 1,
      );
    });
    expect(logs.length, equals(2));
    expect(logs[1].attemptNumber, equals(2));
    expect(logs[1].targetText, equals('A'));
    expect(logs[1].recognizedText, equals('A'));
    expect(logs[1].isCorrect, isTrue);
    expect(logs[1].editDistance, equals(0));
    expect(logs[1].similarityPercent, equals(100.0));
  });
}
