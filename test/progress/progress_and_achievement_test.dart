import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kogo_voice_learning/data/database/app_database.dart';
import 'package:kogo_voice_learning/data/repositories/achievement_repository.dart';
import 'package:kogo_voice_learning/data/repositories/answer_log_repository.dart';
import 'package:kogo_voice_learning/data/repositories/progress_repository.dart';
import 'package:kogo_voice_learning/services/auth/session_manager.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late int deviceId;
  late int sessionChild1Id;
  late int sessionChild2Id;

  setUp(() async {
    await AppDatabase.instance.deleteDatabase();
    await AppDatabase.instance.database;

    final sessionManager = SessionManager.instance;
    final device = await sessionManager.initDevice(deviceId: 'dev_test_progress');
    deviceId = device.id!;

    // Buat sesi untuk Child 1
    await sessionManager.loginChild(childCode: 'P001', pin: '1234');
    final session1 = await sessionManager.startResearchSession(notes: 'Session child 1');
    sessionChild1Id = session1.id!;

    // Buat sesi untuk Child 2
    await sessionManager.loginChild(childCode: 'P002', pin: '1234');
    final session2 = await sessionManager.startResearchSession(notes: 'Session child 2');
    sessionChild2Id = session2.id!;
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  group('Progress and Achievement Tests (Child Isolation & Metrics)', () {
    test('Calculates accuracy as (correct_attempts / total_attempts) * 100 and isolates by child', () async {
      final answerLogRepo = AnswerLogRepository();
      final progressRepo = ProgressRepository();

      // Child 1 (P001, id: 1) dan Child 2 (P002, id: 2)
      // Child 1: 3 attempts, 2 benar, 1 salah -> Akurasi = (2 / 3) * 100 = 66.666%
      await answerLogRepo.logAnswer(
        childId: 1,
        deviceId: deviceId,
        sessionId: sessionChild1Id,
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
        childId: 1,
        deviceId: deviceId,
        sessionId: sessionChild1Id,
        questionId: 2,
        targetText: 'B',
        recognizedText: 'B',
        normalizedTarget: 'b',
        normalizedRecognized: 'b',
        editDistance: 0,
        similarityScore: 1.0,
        similarityPercent: 100.0,
        isCorrect: true,
      );

      await answerLogRepo.logAnswer(
        childId: 1,
        deviceId: deviceId,
        sessionId: sessionChild1Id,
        questionId: 3,
        targetText: 'C',
        recognizedText: 'D',
        normalizedTarget: 'c',
        normalizedRecognized: 'd',
        editDistance: 1,
        similarityScore: 0.0,
        similarityPercent: 0.0,
        isCorrect: false,
      );

      // Child 2: 1 attempt, 1 salah -> Akurasi = 0%
      await answerLogRepo.logAnswer(
        childId: 2,
        deviceId: deviceId,
        sessionId: sessionChild2Id,
        questionId: 1,
        targetText: 'A',
        recognizedText: 'Z',
        normalizedTarget: 'a',
        normalizedRecognized: 'z',
        editDistance: 1,
        similarityScore: 0.0,
        similarityPercent: 0.0,
        isCorrect: false,
      );

      // 1. Cek progress Child 1
      final summaryChild1 = await progressRepo.getProgressSummary(1);
      expect(summaryChild1.childId, equals(1));
      expect(summaryChild1.totalAttempts, equals(3));
      expect(summaryChild1.correctAttempts, equals(2));
      expect(summaryChild1.accuracyPercent, closeTo(66.66, 0.1));
      expect(summaryChild1.completedQuestions, equals(2)); // question 1 dan 2 dijawab benar

      // 2. Cek progress Child 2 (Child isolation terbukti)
      final summaryChild2 = await progressRepo.getProgressSummary(2);
      expect(summaryChild2.childId, equals(2));
      expect(summaryChild2.totalAttempts, equals(1));
      expect(summaryChild2.correctAttempts, equals(0));
      expect(summaryChild2.accuracyPercent, equals(0.0));
      expect(summaryChild2.completedQuestions, equals(0));
    });

    test('Achievement unlocking: FIRST_PRACTICE, TEN_CORRECT, STAGE_ONE_COMPLETE', () async {
      final answerLogRepo = AnswerLogRepository();
      final achievementRepo = AchievementRepository();
      final progressRepo = ProgressRepository();

      // Mulanya Child 1 belum punya achievement apapun
      final initialAch = await achievementRepo.getChildAchievements(1);
      expect(initialAch, isEmpty);

      // 1. Simpan attempt pertama
      await answerLogRepo.logAnswer(
        childId: 1,
        deviceId: deviceId,
        sessionId: sessionChild1Id,
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

      // Dapatkan summary -> mengevaluasi & memberikan FIRST_PRACTICE
      var summary = await progressRepo.getProgressSummary(1);
      expect(summary.earnedAchievements.any((a) => a.achievementCode == 'FIRST_PRACTICE'), isTrue);
      expect(summary.earnedAchievements.any((a) => a.achievementCode == 'TEN_CORRECT'), isFalse);

      // 2. Tambah hingga 10 jawaban benar
      for (int i = 2; i <= 10; i++) {
        await answerLogRepo.logAnswer(
          childId: 1,
          deviceId: deviceId,
          sessionId: sessionChild1Id,
          questionId: i,
          targetText: 'T$i',
          recognizedText: 'T$i',
          normalizedTarget: 't$i',
          normalizedRecognized: 't$i',
          editDistance: 0,
          similarityScore: 1.0,
          similarityPercent: 100.0,
          isCorrect: true,
        );
      }

      summary = await progressRepo.getProgressSummary(1);
      expect(summary.correctAttempts, equals(10));
      expect(summary.earnedAchievements.any((a) => a.achievementCode == 'TEN_CORRECT'), isTrue);

      // Pastikan Child 2 tidak mendapatkan achievement Child 1 (Isolation)
      final achChild2 = await achievementRepo.getChildAchievements(2);
      expect(achChild2, isEmpty);
    });

    test('Stage and Lesson progress reflects questions completed in SQLite', () async {
      final answerLogRepo = AnswerLogRepository();
      final progressRepo = ProgressRepository();
      final db = await AppDatabase.instance.database;

      // Ambil seluruh question_id di lesson 1 (stage 1, listen_repeat)
      final qList = await db.query('questions', where: 'lesson_id = ?', whereArgs: [1]);
      final totalLesson1Q = qList.length;

      // Child 1 menyelesaikan semua soal di lesson 1
      for (final q in qList) {
        await answerLogRepo.logAnswer(
          childId: 1,
          deviceId: deviceId,
          sessionId: sessionChild1Id,
          questionId: q['id'] as int,
          targetText: q['target_text'] as String,
          recognizedText: q['target_text'] as String,
          normalizedTarget: q['normalized_target'] as String,
          normalizedRecognized: q['normalized_target'] as String,
          editDistance: 0,
          similarityScore: 1.0,
          similarityPercent: 100.0,
          isCorrect: true,
        );
      }

      final summary = await progressRepo.getProgressSummary(1);
      final stage1 = summary.stageProgressList.firstWhere((s) => s.stageId == 1);
      final lesson1 = stage1.lessonProgressList.firstWhere((l) => l.lessonId == 1);

      expect(lesson1.completedQuestions, equals(totalLesson1Q));
      expect(lesson1.isCompleted, isTrue);
      expect(lesson1.progressPercent, equals(100.0));
      expect(stage1.completedLessons, greaterThanOrEqualTo(1));
    });
  });
}
