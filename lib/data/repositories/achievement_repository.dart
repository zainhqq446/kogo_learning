import 'package:sqflite/sqflite.dart';

import '../database/app_database.dart';
import '../models/achievement_model.dart';
import '../models/child_achievement_model.dart';

class AchievementRepository {
  final AppDatabase _appDatabase;

  AchievementRepository({AppDatabase? appDatabase})
      : _appDatabase = appDatabase ?? AppDatabase.instance;

  Future<Database> get _db => _appDatabase.database;

  /// Mengambil semua achievement yang terdaftar
  Future<List<AchievementModel>> getAllAchievements() async {
    final db = await _db;
    final results = await db.query('achievements', orderBy: 'id ASC');
    return results.map(AchievementModel.fromMap).toList();
  }

  /// Mengambil achievement berdasarkan kode unik (misal: 'FIRST_PRACTICE')
  Future<AchievementModel?> getByCode(String code) async {
    final db = await _db;
    final results = await db.query(
      'achievements',
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return AchievementModel.fromMap(results.first);
  }

  /// Mengambil semua achievement yang telah diraih oleh seorang anak (dengan child isolation)
  Future<List<ChildAchievementModel>> getChildAchievements(int childId) async {
    final db = await _db;
    final results = await db.rawQuery('''
      SELECT 
        ca.id,
        ca.child_id,
        ca.achievement_id,
        ca.earned_at,
        a.code AS achievement_code,
        a.title AS achievement_title,
        a.description AS achievement_description
      FROM child_achievements ca
      INNER JOIN achievements a ON a.id = ca.achievement_id
      WHERE ca.child_id = ?
      ORDER BY ca.id ASC
    ''', [childId]);

    return results.map(ChildAchievementModel.fromMap).toList();
  }

  /// Memeriksa apakah anak sudah memiliki achievement tertentu
  Future<bool> hasAchievement(int childId, String achievementCode) async {
    final db = await _db;
    final results = await db.rawQuery('''
      SELECT 1 FROM child_achievements ca
      INNER JOIN achievements a ON a.id = ca.achievement_id
      WHERE ca.child_id = ? AND a.code = ?
      LIMIT 1
    ''', [childId, achievementCode]);
    return results.isNotEmpty;
  }

  /// Memberikan achievement ke child jika belum pernah didapatkan sebelumnya
  Future<ChildAchievementModel?> awardAchievement({
    required int childId,
    required String achievementCode,
  }) async {
    final achievement = await getByCode(achievementCode);
    if (achievement == null) return null;

    final db = await _db;
    final now = DateTime.now().toIso8601String();

    try {
      final id = await db.insert(
        'child_achievements',
        {
          'child_id': childId,
          'achievement_id': achievement.id,
          'earned_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      if (id <= 0) {
        // Sudah ada (conflict ignore)
        return null;
      }

      return ChildAchievementModel(
        id: id,
        childId: childId,
        achievementId: achievement.id!,
        earnedAt: now,
        achievementCode: achievement.code,
        achievementTitle: achievement.title,
        achievementDescription: achievement.description,
      );
    } catch (_) {
      return null;
    }
  }

  /// Memeriksa dan memberikan seluruh achievement yang memenuhi kriteria secara otomatis
  /// Aturan:
  /// - FIRST_PRACTICE: Setidaknya 1 attempt telah dilakukan oleh child
  /// - TEN_CORRECT: Setidaknya 10 attempt benar dicapai oleh child
  /// - STAGE_ONE_COMPLETE: Seluruh soal di Stage 1 telah dijawab dengan benar setidaknya 1 kali
  Future<List<ChildAchievementModel>> checkAndAwardAchievements(int childId) async {
    final awardedList = <ChildAchievementModel>[];
    final db = await _db;

    // 1. Cek FIRST_PRACTICE
    final totalAttemptsCountResult = await db.rawQuery('''
      SELECT COUNT(*) as count FROM answer_logs WHERE child_id = ?
    ''', [childId]);
    final totalAttempts = Sqflite.firstIntValue(totalAttemptsCountResult) ?? 0;

    if (totalAttempts >= 1) {
      final awarded = await awardAchievement(
        childId: childId,
        achievementCode: 'FIRST_PRACTICE',
      );
      if (awarded != null) awardedList.add(awarded);
    }

    // 2. Cek TEN_CORRECT
    final correctAttemptsCountResult = await db.rawQuery('''
      SELECT COUNT(*) as count FROM answer_logs WHERE child_id = ? AND is_correct = 1
    ''', [childId]);
    final correctAttempts = Sqflite.firstIntValue(correctAttemptsCountResult) ?? 0;

    if (correctAttempts >= 10) {
      final awarded = await awardAchievement(
        childId: childId,
        achievementCode: 'TEN_CORRECT',
      );
      if (awarded != null) awardedList.add(awarded);
    }

    // 3. Cek STAGE_ONE_COMPLETE
    // Menghitung total pertanyaan di stage 1
    final stageOneQuestionsResult = await db.rawQuery('''
      SELECT COUNT(q.id) as count 
      FROM questions q
      INNER JOIN lessons l ON l.id = q.lesson_id
      WHERE l.stage_id = 1
    ''');
    final stageOneTotalQuestions = Sqflite.firstIntValue(stageOneQuestionsResult) ?? 0;

    // Menghitung pertanyaan unik di stage 1 yang sudah dijawab benar oleh child ini
    final stageOneCompletedResult = await db.rawQuery('''
      SELECT COUNT(DISTINCT q.id) as count
      FROM questions q
      INNER JOIN lessons l ON l.id = q.lesson_id
      INNER JOIN answer_logs al ON al.question_id = q.id
      WHERE l.stage_id = 1 AND al.child_id = ? AND al.is_correct = 1
    ''', [childId]);
    final stageOneCompletedQuestions = Sqflite.firstIntValue(stageOneCompletedResult) ?? 0;

    if (stageOneTotalQuestions > 0 && stageOneCompletedQuestions >= stageOneTotalQuestions) {
      final awarded = await awardAchievement(
        childId: childId,
        achievementCode: 'STAGE_ONE_COMPLETE',
      );
      if (awarded != null) awardedList.add(awarded);
    }

    return awardedList;
  }
}
