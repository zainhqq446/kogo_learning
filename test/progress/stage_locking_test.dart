import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kogo_voice_learning/data/database/app_database.dart';
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

  setUp(() async {
    await AppDatabase.instance.deleteDatabase();
    await AppDatabase.instance.database;

    final sessionManager = SessionManager.instance;
    final device = await sessionManager.initDevice(deviceId: 'dev_stage_locking_test');
    deviceId = device.id!;

    await sessionManager.loginChild(childCode: 'P001', pin: '1234');
    final s1 = await sessionManager.startResearchSession(notes: 'Stage Locking Child 1');
    sessionChild1Id = s1.id!;

    await sessionManager.loginChild(childCode: 'P002', pin: '1234');
    await sessionManager.startResearchSession(notes: 'Stage Locking Child 2');
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  group('Stage Locking Specification Tests', () {
    test('Stage 1 is unlocked by default; Stage 2 is locked when Stage 1 is unstarted', () async {
      final progressRepo = ProgressRepository();

      // Child 1: Stage 1 belum dimulai
      final isStage1Unlocked = await progressRepo.isStageUnlocked(childId: 1, stageOrderIndex: 1);
      final isStage2Unlocked = await progressRepo.isStageUnlocked(childId: 1, stageOrderIndex: 2);
      final isStage3Unlocked = await progressRepo.isStageUnlocked(childId: 1, stageOrderIndex: 3);

      expect(isStage1Unlocked, isTrue, reason: 'Stage pertama harus selalu terbuka');
      expect(isStage2Unlocked, isFalse, reason: 'Stage kedua harus terkunci sebelum stage 1 selesai');
      expect(isStage3Unlocked, isFalse, reason: 'Stage ketiga harus terkunci');
    });

    test('Stage 2 remains locked while Stage 1 is partially in-progress', () async {
      final answerLogRepo = AnswerLogRepository();
      final progressRepo = ProgressRepository();
      final db = await AppDatabase.instance.database;

      // Ambil pertanyaan dari lesson pertama saja di Stage 1
      final qList = await db.rawQuery('''
        SELECT q.* FROM questions q
        INNER JOIN lessons l ON q.lesson_id = l.id
        WHERE l.stage_id = 1 AND l.order_index = 1
      ''');
      expect(qList, isNotEmpty);

      // Jawab benar semua soal di lesson pertama saja (masih ada lesson lain di stage 1)
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

      // Pastikan status Stage 1 sedang berjalan tapi belum selesai sepenuhnya
      final summary = await progressRepo.getProgressSummary(1);
      final stage1 = summary.stageProgressList.firstWhere((s) => s.orderIndex == 1);
      expect(stage1.isCompleted, isFalse);
      expect(stage1.completedQuestions, greaterThan(0));
      expect(stage1.completedQuestions, lessThan(stage1.totalQuestions));

      // Stage 2 harus TETAP terkunci
      final isStage2Unlocked = await progressRepo.isStageUnlocked(childId: 1, stageOrderIndex: 2);
      expect(isStage2Unlocked, isFalse, reason: 'Stage 2 harus tetap terkunci jika Stage 1 masih in-progress');
    });

    test('Stage 2 unlocks only after Stage 1 is genuinely complete; Child 2 remains locked', () async {
      final answerLogRepo = AnswerLogRepository();
      final progressRepo = ProgressRepository();
      final db = await AppDatabase.instance.database;

      // Ambil SEMUA pertanyaan di Stage 1
      final stage1Questions = await db.rawQuery('''
        SELECT q.* FROM questions q
        INNER JOIN lessons l ON q.lesson_id = l.id
        WHERE l.stage_id = 1
      ''');
      expect(stage1Questions, isNotEmpty);

      // Child 1 menjawab BENAR semua pertanyaan di Stage 1
      for (final q in stage1Questions) {
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

      // Verifikasi status penyelesaian Stage 1 untuk Child 1
      final summaryChild1 = await progressRepo.getProgressSummary(1);
      final stage1Child1 = summaryChild1.stageProgressList.firstWhere((s) => s.orderIndex == 1);
      expect(stage1Child1.isCompleted, isTrue);

      // Stage 2 terbuka untuk Child 1
      final isStage2UnlockedChild1 = await progressRepo.isStageUnlocked(childId: 1, stageOrderIndex: 2);
      expect(isStage2UnlockedChild1, isTrue, reason: 'Stage 2 harus terbuka setelah seluruh aktivitas Stage 1 selesai');

      // Stage 3 masih tetap terkunci untuk Child 1 karena Stage 2 belum selesai
      final isStage3UnlockedChild1 = await progressRepo.isStageUnlocked(childId: 1, stageOrderIndex: 3);
      expect(isStage3UnlockedChild1, isFalse, reason: 'Stage 3 harus tetap terkunci sebelum Stage 2 selesai');

      // Isolasi akun: Child 2 yang belum menyelesaikan Stage 1 TIDAK boleh terbuka Stage 2
      final isStage2UnlockedChild2 = await progressRepo.isStageUnlocked(childId: 2, stageOrderIndex: 2);
      expect(isStage2UnlockedChild2, isFalse, reason: 'Child 2 tidak boleh mendapatkan unlock dari progres Child 1');
    });
  });
}
