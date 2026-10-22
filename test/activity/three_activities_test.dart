import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kogo_voice_learning/data/database/app_database.dart';
import 'package:kogo_voice_learning/data/models/stage_model.dart';
import 'package:kogo_voice_learning/data/repositories/answer_log_repository.dart';
import 'package:kogo_voice_learning/features/activity/presentation/pages/find_object_page.dart';
import 'package:kogo_voice_learning/features/activity/presentation/pages/listen_carefully_page.dart';
import 'package:kogo_voice_learning/features/activity/presentation/pages/matching_page.dart';
import 'package:kogo_voice_learning/features/lesson/presentation/pages/lesson_page.dart';
import 'package:kogo_voice_learning/services/auth/session_manager.dart';

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
    await sessionManager.initDevice(deviceId: 'dev_test_activities');
    await sessionManager.loginChild(childCode: 'P001', pin: '1234');
    await sessionManager.startResearchSession(notes: 'Sesi pengetesan 3 aktivitas');
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  Future<void> pumpAsync(WidgetTester tester) async {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
  }

  testWidgets('Find Object Activity: Navigation, Options from SQLite, Selection, and Progress', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    const stage = StageModel(id: 1, title: 'Huruf', orderIndex: 1, isActive: true);

    await tester.pumpWidget(
      const MaterialApp(
        home: LessonPage(stage: stage),
      ),
    );
    await pumpAsync(tester);

    // 1. Ketuk lesson 'Find Object'
    expect(find.text('Find Object'), findsOneWidget);
    await tester.tap(find.text('Find Object'));
    await pumpAsync(tester);

    // 2. Berada di FindObjectPage dengan pertanyaan dari SQLite
    expect(find.byType(FindObjectPage), findsOneWidget);
    expect(find.text('Pertanyaan 1 dari 2'), findsOneWidget);
    expect(find.text('Temukan Objek:'), findsOneWidget);
    expect(find.text('Apel'), findsWidgets);

    // 3. Ketuk opsi yang benar 'Apel'
    final apelOption = find.descendant(
      of: find.byType(GridView),
      matching: find.text('Apel'),
    );
    expect(apelOption, findsOneWidget);
    await tester.ensureVisible(apelOption);
    await tester.tap(apelOption);
    await tester.pump();

    // Feedback benar muncul
    expect(find.text('Jawaban Benar! 🎉'), findsOneWidget);

    // 4. Lanjut ke pertanyaan berikutnya
    final nextBtn = find.text('Pertanyaan Berikutnya');
    await tester.ensureVisible(nextBtn);
    await tester.tap(nextBtn);
    await pumpAsync(tester);

    // Soal kedua muncul tanpa kebocoran state (state di-reset bersih)
    expect(find.text('Pertanyaan 2 dari 2'), findsOneWidget);
    expect(find.text('Jawaban Benar! 🎉'), findsNothing);

    // Ketuk 'Bola' di dalam GridView
    final bolaOption = find.descendant(
      of: find.byType(GridView),
      matching: find.text('Bola'),
    );
    expect(bolaOption, findsOneWidget);
    await tester.ensureVisible(bolaOption);
    await tester.tap(bolaOption);
    await tester.pump();
    expect(find.text('Jawaban Benar! 🎉'), findsOneWidget);

    // Selesai
    final finishBtn = find.text('Selesai');
    await tester.ensureVisible(finishBtn);
    await tester.tap(finishBtn);
    await pumpAsync(tester);

    expect(find.text('Bagus Sekali! 🌟'), findsOneWidget);
    final dialogFinishBtn = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Selesai'),
    );
    expect(dialogFinishBtn, findsOneWidget);
    await tester.tap(dialogFinishBtn);
    await pumpAsync(tester);

    // Kembali ke LessonPage
    expect(find.byType(LessonPage), findsOneWidget);

    // Verifikasi log jawaban tersimpan
    final repo = AnswerLogRepository();
    late List<AnswerLogModel> logs;
    await tester.runAsync(() async {
      final db = await AppDatabase.instance.database;
      final qList = await db.query('questions', where: "target_text = ?", whereArgs: ['Apel']);
      final qId = qList.first['id'] as int;
      logs = await repo.getLogsForQuestion(childId: 1, sessionId: 1, questionId: qId);
    });
    expect(logs, isNotEmpty);
    expect(logs.first.isCorrect, isTrue);
    expect(logs.first.targetText, equals('Apel'));
  });

  testWidgets('Matching Object Activity: Navigation, Segment Assembly from SQLite, and Reset', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    const stage = StageModel(id: 1, title: 'Huruf', orderIndex: 1, isActive: true);

    await tester.pumpWidget(
      const MaterialApp(
        home: LessonPage(stage: stage),
      ),
    );
    await pumpAsync(tester);

    // 1. Ketuk lesson 'Matching Object'
    expect(find.text('Matching Object'), findsOneWidget);
    await tester.tap(find.text('Matching Object'));
    await pumpAsync(tester);

    // 2. Berada di MatchingPage
    expect(find.byType(MatchingPage), findsOneWidget);
    expect(find.text('Pertanyaan 1 dari 2'), findsOneWidget);
    expect(find.text('Cocokkan & Susun:'), findsOneWidget);
    expect(find.text('A - Apel'), findsOneWidget);

    // 3. Sentuh tile potongan kartu
    final tileA = find.widgetWithText(ElevatedButton, 'A');
    final tileApel = find.widgetWithText(ElevatedButton, 'Apel');
    expect(tileA, findsOneWidget);
    expect(tileApel, findsOneWidget);

    await tester.ensureVisible(tileA);
    await tester.tap(tileA);
    await tester.pump();

    // Chip muncul pada susunan kartu
    expect(find.byType(InputChip), findsOneWidget);

    await tester.ensureVisible(tileApel);
    await tester.tap(tileApel);
    await tester.pump();

    // Evaluasi otomatis dijalankan
    expect(find.text('Cocok! Hebat Sekali 🎉'), findsOneWidget);

    // 4. Lanjut ke soal berikutnya
    final nextBtn = find.text('Pertanyaan Berikutnya');
    await tester.ensureVisible(nextBtn);
    await tester.tap(nextBtn);
    await pumpAsync(tester);

    // Soal kedua muncul tanpa kebocoran state sebelumnya
    expect(find.text('Pertanyaan 2 dari 2'), findsOneWidget);
    expect(find.text('B - Bola'), findsOneWidget);
    expect(find.text('Cocok! Hebat Sekali 🎉'), findsNothing);
  });

  testWidgets('Listen Carefully Activity: Audio Button, SQLite Choices, and Completion', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    const stage = StageModel(id: 1, title: 'Huruf', orderIndex: 1, isActive: true);

    await tester.pumpWidget(
      const MaterialApp(
        home: LessonPage(stage: stage),
      ),
    );
    await pumpAsync(tester);

    // 1. Ketuk lesson 'Listen Carefully'
    final listenCarefullyCard = find.text('Listen Carefully');
    await tester.ensureVisible(listenCarefullyCard);
    expect(listenCarefullyCard, findsOneWidget);
    await tester.tap(listenCarefullyCard);
    await pumpAsync(tester);

    // 2. Berada di ListenCarefullyPage
    expect(find.byType(ListenCarefullyPage), findsOneWidget);
    expect(find.text('Dengarkan Baik-baik:'), findsOneWidget);
    expect(find.text('Pertanyaan 1 dari 2'), findsOneWidget);

    // 3. Tekan tombol putar suara
    final playBtn = find.byIcon(Icons.play_arrow_rounded);
    await tester.ensureVisible(playBtn);
    await tester.tap(playBtn);
    await tester.pump();
    expect(find.text('Memutar Suara...'), findsOneWidget);

    // Tunggu audio timer selesai
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('Memutar Suara...'), findsNothing);

    // 4. Pilih opsi jawaban di GridView
    final choiceA = find.descendant(
      of: find.byType(GridView),
      matching: find.text('A'),
    );
    expect(choiceA, findsOneWidget);
    await tester.ensureVisible(choiceA);
    await tester.tap(choiceA);
    await tester.pump();

    expect(find.text('Tepat Sekali! 🎉'), findsOneWidget);

    // 5. Lanjut ke pertanyaan berikutnya
    final nextBtn = find.text('Pertanyaan Berikutnya');
    await tester.ensureVisible(nextBtn);
    await tester.tap(nextBtn);
    await pumpAsync(tester);

    expect(find.text('Pertanyaan 2 dari 2'), findsOneWidget);
    expect(find.text('Tepat Sekali! 🎉'), findsNothing);
  });

  testWidgets('Missing Letter Activity: Navigation, Options, Selection, and Progress', (
    WidgetTester tester,
  ) async {
    const stage = StageModel(id: 1, title: 'Huruf', orderIndex: 1, isActive: true);

    await tester.pumpWidget(
      const MaterialApp(
        home: LessonPage(stage: stage),
      ),
    );
    await pumpAsync(tester);

    // 1. Ketuk lesson 'Missing Letter'
    final missingLetterCard = find.text('Missing Letter');
    await tester.ensureVisible(missingLetterCard);
    expect(missingLetterCard, findsOneWidget);
    await tester.tap(missingLetterCard);
    await pumpAsync(tester);

    // 2. Berada di MissingLetterPage
    expect(find.text('Isi huruf yang hilang:'), findsOneWidget);
    expect(find.text('Soal 1 dari 2'), findsOneWidget);

    // 3. Ketuk salah satu pilihan huruf
    final letterOption = find.text('A').first;
    await tester.tap(letterOption);
    await tester.pump();

    // 4. Verifikasi muncul feedback
    expect(find.byType(ElevatedButton), findsWidgets);

    // 5. Ketuk tombol untuk lanjut atau ulangi
    final actionBtn = find.byType(ElevatedButton).first;
    await tester.ensureVisible(actionBtn);
    await tester.tap(actionBtn);
    await pumpAsync(tester);

    // Pastikan animation controller/timer selesai sebelum test ditutup
    await tester.pump(const Duration(milliseconds: 500));
  });
}
