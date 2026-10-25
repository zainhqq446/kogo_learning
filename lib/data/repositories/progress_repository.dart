import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/child_progress_summary_model.dart';
import 'achievement_repository.dart';

class ProgressRepository {
  final AppDatabase _appDatabase;
  final AchievementRepository _achievementRepository;

  ProgressRepository({
    AppDatabase? appDatabase,
    AchievementRepository? achievementRepository,
  })  : _appDatabase = appDatabase ?? AppDatabase.instance,
        _achievementRepository = achievementRepository ?? AchievementRepository();

  Future<Database> get _db => _appDatabase.database;

  /// Mengambil metrik progress komprehensif untuk child tertentu (Child Isolation terjamin).
  /// Menghitung:
  /// - progress stage
  /// - progress lesson
  /// - completed questions
  /// - correct attempts
  /// - total attempts
  /// - accuracy = (correct_attempts / total_attempts) * 100
  /// - achievements
  Future<ChildProgressSummaryModel> getProgressSummary(int childId) async {
    final db = await _db;

    // Evaluasi otomatis peraihan achievement terbaru
    await _achievementRepository.checkAndAwardAchievements(childId);

    // 1. Total Attempts dan Correct Attempts untuk child ini
    final attemptsResult = await db.rawQuery('''
      SELECT 
        COUNT(*) as total_attempts,
        SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) as correct_attempts
      FROM answer_logs
      WHERE child_id = ?
    ''', [childId]);

    final totalAttempts = Sqflite.firstIntValue([{'count': attemptsResult.first['total_attempts']}]) ?? 0;
    final correctAttempts = Sqflite.firstIntValue([{'count': attemptsResult.first['correct_attempts']}]) ?? 0;

    // Accuracy: correct_attempts / total_attempts * 100
    // Tidak menggunakan confidence Whisper.
    final accuracyPercent = totalAttempts > 0
        ? (correctAttempts / totalAttempts) * 100.0
        : 0.0;

    // 2. Ambil semua stage
    final stagesData = await db.query('stages', orderBy: 'order_index ASC');

    final stageProgressList = <StageProgressModel>[];
    var totalGlobalQuestions = 0;
    var completedGlobalQuestions = 0;
    var totalGlobalLessons = 0;
    var completedGlobalLessons = 0;
    var completedStagesCount = 0;

    for (final stageRow in stagesData) {
      final stageId = stageRow['id'] as int;
      final stageTitle = stageRow['title'] as String;
      final stageOrderIndex = stageRow['order_index'] as int;

      // Ambil lessons di stage ini
      final lessonsData = await db.query(
        'lessons',
        where: 'stage_id = ?',
        whereArgs: [stageId],
        orderBy: 'order_index ASC',
      );

      final lessonProgressList = <LessonProgressModel>[];
      var stageTotalQuestions = 0;
      var stageCompletedQuestions = 0;
      var stageCompletedLessons = 0;

      for (final lessonRow in lessonsData) {
        final lessonId = lessonRow['id'] as int;
        final lessonTitle = lessonRow['title'] as String;
        final lessonType = lessonRow['lesson_type'] as String;

        // Total questions untuk lesson ini
        final qCountResult = await db.rawQuery('''
          SELECT COUNT(*) as count FROM questions WHERE lesson_id = ?
        ''', [lessonId]);
        final lessonTotalQuestions = Sqflite.firstIntValue(qCountResult) ?? 0;

        // Completed questions: pertanyaan unik yang telah dijawab dengan benar oleh child ini
        final qCompletedResult = await db.rawQuery('''
          SELECT COUNT(DISTINCT q.id) as count
          FROM questions q
          INNER JOIN answer_logs al ON al.question_id = q.id
          WHERE q.lesson_id = ? AND al.child_id = ? AND al.is_correct = 1
        ''', [lessonId, childId]);
        final lessonCompletedQuestions = Sqflite.firstIntValue(qCompletedResult) ?? 0;

        final isLessonCompleted = lessonTotalQuestions > 0 &&
            lessonCompletedQuestions >= lessonTotalQuestions;

        if (isLessonCompleted) {
          stageCompletedLessons++;
        }

        final lessonPercent = lessonTotalQuestions > 0
            ? (lessonCompletedQuestions / lessonTotalQuestions) * 100.0
            : 0.0;

        lessonProgressList.add(LessonProgressModel(
          lessonId: lessonId,
          title: lessonTitle,
          lessonType: lessonType,
          totalQuestions: lessonTotalQuestions,
          completedQuestions: lessonCompletedQuestions,
          isCompleted: isLessonCompleted,
          progressPercent: lessonPercent,
        ));

        stageTotalQuestions += lessonTotalQuestions;
        stageCompletedQuestions += lessonCompletedQuestions;
      }

      final isStageCompleted = stageTotalQuestions > 0 &&
          stageCompletedQuestions >= stageTotalQuestions;

      if (isStageCompleted) {
        completedStagesCount++;
      }

      final stagePercent = stageTotalQuestions > 0
          ? (stageCompletedQuestions / stageTotalQuestions) * 100.0
          : 0.0;

      stageProgressList.add(StageProgressModel(
        stageId: stageId,
        title: stageTitle,
        orderIndex: stageOrderIndex,
        totalQuestions: stageTotalQuestions,
        completedQuestions: stageCompletedQuestions,
        totalLessons: lessonsData.length,
        completedLessons: stageCompletedLessons,
        isCompleted: isStageCompleted,
        progressPercent: stagePercent,
        lessonProgressList: lessonProgressList,
      ));

      totalGlobalQuestions += stageTotalQuestions;
      totalGlobalLessons += lessonsData.length;
      completedGlobalLessons += stageCompletedLessons;
      completedGlobalQuestions += stageCompletedQuestions;
    }

    // Ambil achievement yang diraih child dan daftar seluruh achievement
    final earnedAchievements = await _achievementRepository.getChildAchievements(childId);
    final allAchievements = await _achievementRepository.getAllAchievements();

    return ChildProgressSummaryModel(
      childId: childId,
      totalStages: stagesData.length,
      completedStages: completedStagesCount,
      totalLessons: totalGlobalLessons,
      completedLessons: completedGlobalLessons,
      totalQuestions: totalGlobalQuestions,
      completedQuestions: completedGlobalQuestions,
      totalAttempts: totalAttempts,
      correctAttempts: correctAttempts,
      accuracyPercent: accuracyPercent,
      stageProgressList: stageProgressList,
      earnedAchievements: earnedAchievements,
      allAchievements: allAchievements,
    );
  }

  /// Mengambil indeks soal aktif terakhir untuk (childId, lessonId).
  /// Mengembalikan 0 jika belum ada progres yang tersimpan.
  Future<int> getActiveQuestionIndex({required int childId, required int lessonId}) async {
    final db = await _db;
    final result = await db.query(
      'activity_progress',
      columns: ['active_question_index'],
      where: 'child_id = ? AND lesson_id = ?',
      whereArgs: [childId, lessonId],
      limit: 1,
    );

    if (result.isEmpty) return 0;
    return (result.first['active_question_index'] as int?) ?? 0;
  }

  /// Menyimpan indeks soal aktif saat ini untuk (childId, lessonId).
  Future<void> saveActiveQuestionIndex({
    required int childId,
    required int lessonId,
    required int activeIndex,
    bool isCompleted = false,
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();

    await db.insert(
      'activity_progress',
      {
        'child_id': childId,
        'lesson_id': lessonId,
        'active_question_index': activeIndex,
        'is_completed': isCompleted ? 1 : 0,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Memeriksa apakah suatu stage terbuka untuk anak tertentu.
  /// Stage pertama (order_index = 1) selalu terbuka.
  /// Stage ke-N hanya terbuka jika stage ke-(N-1) sudah completed.
  Future<bool> isStageUnlocked({required int childId, required int stageOrderIndex}) async {
    if (stageOrderIndex <= 1) return true;

    final summary = await getProgressSummary(childId);
    final prevStage = summary.stageProgressList.firstWhere(
      (s) => s.orderIndex == stageOrderIndex - 1,
      orElse: () => StageProgressModel(
        stageId: 0,
        title: '',
        orderIndex: stageOrderIndex - 1,
        totalQuestions: 0,
        completedQuestions: 0,
        totalLessons: 0,
        completedLessons: 0,
        isCompleted: false,
        progressPercent: 0,
        lessonProgressList: const [],
      ),
    );

    return prevStage.isCompleted;
  }

  /// Menandai suatu checkpoint selesai untuk anak tertentu
  Future<void> completeCheckpoint({
    required int childId,
    required int stageId,
    required int checkpointNumber,
  }) async {
    final db = await _db;
    final now = DateTime.now().toIso8601String();
    final checkpointLessonKey = (stageId * 100) + checkpointNumber;

    await db.insert(
      'activity_progress',
      {
        'child_id': childId,
        'lesson_id': checkpointLessonKey,
        'active_question_index': 0,
        'is_completed': 1,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Kompatibilitas dengan index lama
    await db.insert(
      'activity_progress',
      {
        'child_id': childId,
        'lesson_id': checkpointNumber,
        'active_question_index': 0,
        'is_completed': 1,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Memeriksa apakah suatu checkpoint terbuka untuk anak tertentu di dalam stage.
  /// Checkpoint pertama (orderIndex = 1) selalu terbuka.
  /// Checkpoint ke-N hanya terbuka jika checkpoint ke-(N-1) sudah selesai.
  Future<bool> isCheckpointUnlocked({
    required int childId,
    required int stageId,
    required int checkpointOrderIndex,
  }) async {
    if (checkpointOrderIndex <= 1) return true;

    final db = await _db;
    final prevKey = (stageId * 100) + (checkpointOrderIndex - 1);
    // Cek apakah ada record penyelesaian untuk checkpoint sebelumnya di activity_progress
    final prevCompleted = await db.query(
      'activity_progress',
      where: 'child_id = ? AND (lesson_id = ? OR lesson_id = ?) AND is_completed = 1',
      whereArgs: [childId, prevKey, checkpointOrderIndex - 1],
    );

    if (prevCompleted.isNotEmpty) return true;

    // Verifikasi juga dari total jawaban benar di answer_logs untuk stage ini
    final countAnswers = Sqflite.firstIntValue(await db.rawQuery('''
      SELECT COUNT(DISTINCT a.question_id)
      FROM answer_logs a
      INNER JOIN questions q ON a.question_id = q.id
      INNER JOIN lessons l ON q.lesson_id = l.id
      WHERE a.child_id = ? AND l.stage_id = ? AND a.is_correct = 1
    ''', [childId, stageId])) ?? 0;

    return countAnswers >= ((checkpointOrderIndex - 1) * 2);
  }
}


