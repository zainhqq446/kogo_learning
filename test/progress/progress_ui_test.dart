import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kogo_voice_learning/data/database/app_database.dart';
import 'package:kogo_voice_learning/data/repositories/answer_log_repository.dart';
import 'package:kogo_voice_learning/features/progress/presentation/pages/child_progress_page.dart';
import 'package:kogo_voice_learning/services/auth/session_manager.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.deleteDatabase();
    await AppDatabase.instance.database;

    final sessionManager = SessionManager.instance;
    final device = await sessionManager.initDevice(deviceId: 'dev_test_progress_ui');
    final child = await sessionManager.loginChild(childCode: 'P001', pin: '1234');
    final session = await sessionManager.startResearchSession(notes: 'UI Progress Test');

    final answerLogRepo = AnswerLogRepository();
    // 2 attempts, 1 benar (Akurasi 50%)
    await answerLogRepo.logAnswer(
      childId: child!.id!,
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

    await answerLogRepo.logAnswer(
      childId: child.id!,
      deviceId: device.id!,
      sessionId: session.id!,
      questionId: 2,
      targetText: 'B',
      recognizedText: 'C',
      normalizedTarget: 'b',
      normalizedRecognized: 'c',
      editDistance: 1,
      similarityScore: 0.0,
      similarityPercent: 0.0,
      isCorrect: false,
    );
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  Future<void> pumpAsync(WidgetTester tester) async {
    for (int i = 0; i < 5; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pump();
    }
  }

  testWidgets('Navigation to ChildProgressPage displays accuracy, completed questions, stages, and achievements', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ChildProgressPage(),
      ),
    );
    await pumpAsync(tester);

    // 1. Berada di ChildProgressPage
    expect(find.byType(ChildProgressPage), findsOneWidget);
    expect(find.text('Ringkasan Belajar'), findsOneWidget);

    // 2. Verifikasi Akurasi = 50.0%
    expect(find.text('50.0%'), findsOneWidget);
    expect(find.text('Akurasi'), findsOneWidget);

    // 3. Verifikasi Soal Selesai & Attempts
    expect(find.text('1 / 2'), findsWidgets); // 1 / 2 attempts benar

    // 4. Verifikasi Achievement (Latihan Pertama didapat)
    expect(find.text('Pencapaian & Medali (Achievements)'), findsOneWidget);
    expect(find.text('Latihan Pertama'), findsOneWidget);
    expect(find.text('Didapat'), findsOneWidget);
    expect(find.text('Terkunci'), findsWidgets);

    // 5. Verifikasi Progress Tiap Tahap
    expect(find.text('Progress Tiap Tahap (Stages)'), findsOneWidget);
    expect(find.text('Huruf'), findsWidgets);
  });
}
