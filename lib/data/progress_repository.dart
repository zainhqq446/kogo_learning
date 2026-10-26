import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../core/curriculum/curriculum.dart';
import 'db/kogo_database.dart';

/// Hasil akhir satu permainan (ditampilkan pada dialog hadiah).
class GameResult {
  const GameResult({required this.stars, required this.previousBest, required this.totalStars, required this.newTiers});

  final int stars;
  final int previousBest;
  final int totalStars;
  final List<RewardTier> newTiers;

  bool get isFirstCompletion => previousBest == 0;
  bool get improved => stars > previousBest;
}

/// Ringkasan untuk halaman Profil & Hadiah (proposal Gambar 3.29 & 3.30).
class LearnerStats {
  const LearnerStats({
    required this.totalStars,
    required this.completedNodes,
    required this.streakDays,
    required this.completedPerMateri,
    required this.unseenRewards,
  });

  static const empty = LearnerStats(totalStars: 0, completedNodes: 0, streakDays: 0, completedPerMateri: {}, unseenRewards: 0);

  final int totalStars;
  final int completedNodes;
  final int streakDays;
  final Map<Materi, int> completedPerMateri;
  final int unseenRewards;

  List<RewardTier> get earnedTiers => RewardTier.values.where((t) => t.isEarned(totalStars)).toList();
}

/// Metrik pengujian lapangan (proposal Tabel 3.1).
class ResearchMetrics {
  const ResearchMetrics({
    required this.sttAttempts,
    required this.sttCorrect,
    required this.sttErrors,
    required this.avgResponseMs,
    required this.sessionsStarted,
    required this.sessionsCompleted,
    required this.sessionsWithErrors,
  });

  final int sttAttempts;
  final int sttCorrect;
  final int sttErrors;
  final int? avgResponseMs;
  final int sessionsStarted;
  final int sessionsCompleted;

  /// Sesi yang mengalami minimal satu galat pengenalan suara.
  final int sessionsWithErrors;

  /// STT Accuracy Rate = benar / total × 100% (target ≥ 70%).
  double? get sttAccuracy => sttAttempts == 0 ? null : sttCorrect / sttAttempts * 100;

  /// Task Completion Rate = selesai / total × 100% (target ≥ 75%).
  double? get taskCompletion => sessionsStarted == 0 ? null : sessionsCompleted / sessionsStarted * 100;

  /// System Error Rate = sesi dengan error / total sesi × 100% (target ≤ 10%),
  /// sesuai rumus Tabel 3.1 dan perhitungan di backend.
  double? get errorRate => sessionsStarted == 0 ? null : sessionsWithErrors / sessionsStarted * 100;
}

class ProgressRepository {
  ProgressRepository({KogoDatabase? database}) : _database = database ?? KogoDatabase.instance;

  final KogoDatabase _database;
  static const _uuid = Uuid();

  static String localDate(DateTime time) {
    final t = time.toLocal();
    return '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  Future<int> startSession({required int learnerId, required LearningNode node, DateTime? now}) async {
    final db = await _database.database;
    final time = now ?? DateTime.now();
    return db.insert('game_sessions', {
      'client_uuid': _uuid.v4(),
      'learner_id': learnerId,
      'materi': node.materi.code,
      'node_index': node.index,
      'game_type': node.game.code,
      'status': 'started',
      'started_at': time.toUtc().toIso8601String(),
      'local_date': localDate(time),
    });
  }

  Future<void> logAttempt({
    required int sessionId,
    required int learnerId,
    required GameType game,
    required String target,
    required String answer,
    required bool isCorrect,
    required int attemptNumber,
    double? similarity,
    int? responseMs,
    String? sttError,
    DateTime? now,
  }) async {
    final db = await _database.database;
    final time = now ?? DateTime.now();
    await db.insert('answer_attempts', {
      'client_uuid': _uuid.v4(),
      'session_id': sessionId,
      'learner_id': learnerId,
      'game_type': game.code,
      'target_text': target,
      'answer_text': answer,
      'is_correct': isCorrect ? 1 : 0,
      'attempt_number': attemptNumber,
      'similarity': similarity,
      'response_ms': responseMs,
      'stt_error': sttError,
      'created_at': time.toUtc().toIso8601String(),
      'local_date': localDate(time),
    });
  }

  /// Menyelesaikan sesi, menyimpan bintang terbaik, dan membuka hadiah baru
  /// dalam satu transaksi.
  Future<GameResult> completeSession({
    required int sessionId,
    required int learnerId,
    required LearningNode node,
    required int totalItems,
    required int firstTryCorrect,
    DateTime? now,
  }) async {
    final db = await _database.database;
    final time = (now ?? DateTime.now()).toUtc().toIso8601String();
    final stars = Curriculum.starsFor(firstTryCorrect: firstTryCorrect, total: totalItems);

    return db.transaction((txn) async {
      await txn.update(
        'game_sessions',
        {'status': 'completed', 'total_items': totalItems, 'first_try_correct': firstTryCorrect, 'stars': stars, 'ended_at': time, 'is_synced': 0},
        where: 'id = ? AND learner_id = ?',
        whereArgs: [sessionId, learnerId],
      );

      final existing = await txn.query(
        'stars',
        columns: ['stars'],
        where: 'learner_id = ? AND materi = ? AND node_index = ?',
        whereArgs: [learnerId, node.materi.code, node.index],
        limit: 1,
      );
      final previous = existing.isEmpty ? 0 : existing.first['stars'] as int;
      if (existing.isEmpty) {
        await txn.insert('stars', {
          'learner_id': learnerId,
          'materi': node.materi.code,
          'node_index': node.index,
          'stars': stars,
          'play_count': 1,
          'first_completed_at': time,
          'updated_at': time,
        });
      } else {
        await txn.rawUpdate(
          'UPDATE stars SET stars = MAX(stars, ?), play_count = play_count + 1, updated_at = ? '
          'WHERE learner_id = ? AND materi = ? AND node_index = ?',
          [stars, time, learnerId, node.materi.code, node.index],
        );
      }

      final total = await _totalStars(txn, learnerId);
      final owned = (await txn.query('rewards', columns: ['tier'], where: 'learner_id = ?', whereArgs: [learnerId])).map((r) => r['tier'] as String).toSet();
      final newTiers = <RewardTier>[];
      for (final tier in RewardTier.values) {
        if (!tier.isEarned(total) || owned.contains(tier.name)) continue;
        await txn.insert('rewards', {'learner_id': learnerId, 'tier': tier.name, 'min_stars': tier.minStars, 'earned_at': time, 'seen': 0});
        newTiers.add(tier);
      }
      return GameResult(stars: stars, previousBest: previous, totalStars: total, newTiers: newTiers);
    });
  }

  Future<void> abandonSession(int sessionId) async {
    final db = await _database.database;
    await db.update(
      'game_sessions',
      {'status': 'abandoned', 'ended_at': DateTime.now().toUtc().toIso8601String(), 'is_synced': 0},
      where: "id = ? AND status = 'started'",
      whereArgs: [sessionId],
    );
  }

  /// Bintang terbaik per node (indeks node → 1..3) untuk satu materi.
  Future<Map<int, int>> starsFor(int learnerId, Materi materi) async {
    final db = await _database.database;
    final rows = await db.query('stars', columns: ['node_index', 'stars'], where: 'learner_id = ? AND materi = ?', whereArgs: [learnerId, materi.code]);
    return {for (final r in rows) r['node_index'] as int: r['stars'] as int};
  }

  /// Node terbuka bila node sebelumnya sudah selesai (peta dikerjakan bertahap
  /// sesuai proposal: "learning path yang harus diselesaikan secara bertahap").
  static int currentNodeIndex(Map<int, int> stars, int nodeCount) {
    for (var i = 0; i < nodeCount; i++) {
      if ((stars[i] ?? 0) == 0) return i;
    }
    return nodeCount;
  }

  static bool isUnlocked(Map<int, int> stars, int index) => index == 0 || (stars[index - 1] ?? 0) > 0;

  Future<LearnerStats> stats(int learnerId, {DateTime? now}) async {
    final db = await _database.database;
    final total = await _totalStars(db, learnerId);
    final perMateri = await db.rawQuery('SELECT materi, COUNT(*) AS c FROM stars WHERE learner_id = ? AND stars > 0 GROUP BY materi', [learnerId]);
    final days = await db.rawQuery("SELECT DISTINCT local_date FROM game_sessions WHERE learner_id = ? AND status = 'completed' ORDER BY local_date DESC", [
      learnerId,
    ]);
    final unseen = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM rewards WHERE learner_id = ? AND seen = 0', [learnerId])) ?? 0;
    final completed = <Materi, int>{for (final r in perMateri) Materi.fromCode(r['materi'] as String): r['c'] as int};
    return LearnerStats(
      totalStars: total,
      completedNodes: completed.values.fold(0, (a, b) => a + b),
      streakDays: streakFrom(days.map((r) => r['local_date'] as String).toList(), now ?? DateTime.now()),
      completedPerMateri: completed,
      unseenRewards: unseen,
    );
  }

  /// Hari belajar berturut-turut yang berakhir hari ini atau kemarin.
  static int streakFrom(List<String> distinctDatesDesc, DateTime now) {
    final dates = distinctDatesDesc.toSet();
    var day = DateTime(now.year, now.month, now.day);
    if (!dates.contains(localDate(day))) {
      day = day.subtract(const Duration(days: 1));
      if (!dates.contains(localDate(day))) return 0;
    }
    var streak = 0;
    while (dates.contains(localDate(day))) {
      streak++;
      day = DateTime(day.year, day.month, day.day - 1);
    }
    return streak;
  }

  Future<void> markRewardsSeen(int learnerId) async {
    final db = await _database.database;
    await db.update('rewards', {'seen': 1}, where: 'learner_id = ? AND seen = 0', whereArgs: [learnerId]);
  }

  /// Metrik Tabel 3.1. [learnerId] null = seluruh anak pada perangkat ini.
  Future<ResearchMetrics> metrics({int? learnerId}) async {
    final db = await _database.database;
    final filter = learnerId == null ? '' : ' AND learner_id = ?';
    final args = [?learnerId];
    final stt = (await db.rawQuery(
      'SELECT COUNT(*) AS total, '
      'SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) AS correct, '
      'SUM(CASE WHEN stt_error IS NOT NULL THEN 1 ELSE 0 END) AS errors, '
      'AVG(response_ms) AS avg_ms '
      'FROM answer_attempts WHERE game_type = ?$filter',
      [GameType.listenRepeat.code, ...args],
    )).first;
    final sessions = (await db.rawQuery(
      "SELECT COUNT(*) AS started, SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) AS completed, "
      'SUM(CASE WHEN EXISTS (SELECT 1 FROM answer_attempts a WHERE a.session_id = s.id AND a.game_type = ? '
      'AND a.stt_error IS NOT NULL) THEN 1 ELSE 0 END) AS with_errors '
      'FROM game_sessions s WHERE 1 = 1$filter',
      [GameType.listenRepeat.code, ...args],
    )).first;
    return ResearchMetrics(
      sttAttempts: (stt['total'] as int?) ?? 0,
      sttCorrect: (stt['correct'] as int?) ?? 0,
      sttErrors: (stt['errors'] as int?) ?? 0,
      avgResponseMs: (stt['avg_ms'] as num?)?.round(),
      sessionsStarted: (sessions['started'] as int?) ?? 0,
      sessionsCompleted: (sessions['completed'] as int?) ?? 0,
      sessionsWithErrors: (sessions['with_errors'] as int?) ?? 0,
    );
  }

  static Future<int> _totalStars(DatabaseExecutor db, int learnerId) async {
    return Sqflite.firstIntValue(await db.rawQuery('SELECT COALESCE(SUM(stars), 0) FROM stars WHERE learner_id = ?', [learnerId])) ?? 0;
  }
}
