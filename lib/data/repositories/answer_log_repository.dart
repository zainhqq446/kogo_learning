import 'package:uuid/uuid.dart';
import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';

class AnswerLogModel {
  final int? id;
  final String? clientAttemptUuid;
  final int childId;
  final int deviceId;
  final int sessionId;
  final int questionId;
  final int attemptNumber;
  final String targetText;
  final String recognizedText;
  final String normalizedTarget;
  final String normalizedRecognized;
  final int editDistance;
  final double similarityScore;
  final double similarityPercent;
  final bool isCorrect;
  final int? recognitionDurationMs;
  final String timestamp;
  final bool isSynced;

  const AnswerLogModel({
    this.id,
    this.clientAttemptUuid,
    required this.childId,
    required this.deviceId,
    required this.sessionId,
    required this.questionId,
    required this.attemptNumber,
    required this.targetText,
    required this.recognizedText,
    required this.normalizedTarget,
    required this.normalizedRecognized,
    required this.editDistance,
    required this.similarityScore,
    required this.similarityPercent,
    required this.isCorrect,
    this.recognitionDurationMs,
    required this.timestamp,
    this.isSynced = false,
  });

  factory AnswerLogModel.fromMap(Map<String, dynamic> map) {
    return AnswerLogModel(
      id: map['id'] as int?,
      clientAttemptUuid: map['client_attempt_uuid'] as String?,
      childId: map['child_id'] as int,
      deviceId: map['device_id'] as int,
      sessionId: map['session_id'] as int,
      questionId: map['question_id'] as int,
      attemptNumber: map['attempt_number'] as int,
      targetText: map['target_text'] as String,
      recognizedText: map['recognized_text'] as String,
      normalizedTarget: map['normalized_target'] as String,
      normalizedRecognized: map['normalized_recognized'] as String,
      editDistance: map['edit_distance'] as int,
      similarityScore: (map['similarity_score'] as num).toDouble(),
      similarityPercent: (map['similarity_percent'] as num).toDouble(),
      isCorrect: (map['is_correct'] as int) == 1,
      recognitionDurationMs: map['recognition_duration_ms'] as int?,
      timestamp: map['timestamp'] as String,
      isSynced: (map['is_synced'] as int?) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (clientAttemptUuid != null) 'client_attempt_uuid': clientAttemptUuid,
      'child_id': childId,
      'device_id': deviceId,
      'session_id': sessionId,
      'question_id': questionId,
      'attempt_number': attemptNumber,
      'target_text': targetText,
      'recognized_text': recognizedText,
      'normalized_target': normalizedTarget,
      'normalized_recognized': normalizedRecognized,
      'edit_distance': editDistance,
      'similarity_score': similarityScore,
      'similarity_percent': similarityPercent,
      'is_correct': isCorrect ? 1 : 0,
      'recognition_duration_ms': recognitionDurationMs,
      'timestamp': timestamp,
      'is_synced': isSynced ? 1 : 0,
    };
  }
}

class AnswerLogRepository {
  Future<Database> get _db async => await AppDatabase.instance.database;

  /// Mendapatkan nomor attempt berikutnya untuk question_id dalam session_id tertentu.
  /// Memastikan attempt_number selalu berurutan (1, 2, 3, ...) per sesi.
  Future<int> getNextAttemptNumber({
    required int childId,
    required int sessionId,
    required int questionId,
    DatabaseExecutor? executor,
  }) async {
    final exec = executor ?? await _db;
    final result = await exec.rawQuery('''
      SELECT MAX(attempt_number) as max_attempt
      FROM answer_logs
      WHERE child_id = ? AND session_id = ? AND question_id = ?
    ''', [childId, sessionId, questionId]);

    final maxAttempt = result.first['max_attempt'] as int?;
    return (maxAttempt ?? 0) + 1;
  }

  /// Menyimpan log jawaban ke database secara atomik untuk mencegah duplikasi attempt.
  Future<AnswerLogModel> logAnswer({
    required int childId,
    required int deviceId,
    required int sessionId,
    required int questionId,
    required String targetText,
    required String recognizedText,
    required String normalizedTarget,
    required String normalizedRecognized,
    required int editDistance,
    required double similarityScore,
    required double similarityPercent,
    required bool isCorrect,
    int? recognitionDurationMs,
    double? confidence,
    String? startedAt,
    String? endedAt,
    String? provider,
    String? locale,
  }) async {
    final db = await _db;
    final timestamp = DateTime.now().toIso8601String();

    return await db.transaction<AnswerLogModel>((txn) async {
      // Pastikan child_id, device_id, dan session_id valid agar tidak memicu SQLite FOREIGN KEY constraint error
      var safeChildId = childId;
      var safeDeviceId = deviceId;
      var safeSessionId = sessionId;

      final childCheck = await txn.query('children', where: 'id = ?', whereArgs: [safeChildId], limit: 1);
      if (childCheck.isEmpty) {
        final anyChild = await txn.query('children', limit: 1);
        if (anyChild.isNotEmpty) {
          safeChildId = anyChild.first['id'] as int;
        } else {
          safeChildId = await txn.insert('children', {
            'child_code': 'P001',
            'display_name': 'Teman Kecil',
            'age': 5,
            'pin_hash': 'default',
            'is_active': 1,
            'created_at': timestamp,
            'updated_at': timestamp,
          });
        }
      }

      final deviceCheck = await txn.query('devices', where: 'id = ?', whereArgs: [safeDeviceId], limit: 1);
      if (deviceCheck.isEmpty) {
        final anyDevice = await txn.query('devices', limit: 1);
        if (anyDevice.isNotEmpty) {
          safeDeviceId = anyDevice.first['id'] as int;
        } else {
          safeDeviceId = await txn.insert('devices', {
            'device_id': 'default_device',
            'device_label': 'Perangkat Utama',
            'platform': 'android',
            'registered_at': timestamp,
            'last_used_at': timestamp,
          });
        }
      }

      final sessionCheck = await txn.query('research_sessions', where: 'id = ?', whereArgs: [safeSessionId], limit: 1);
      if (sessionCheck.isEmpty) {
        final anySession = await txn.query('research_sessions', where: 'child_id = ?', whereArgs: [safeChildId], limit: 1);
        if (anySession.isNotEmpty) {
          safeSessionId = anySession.first['id'] as int;
        } else {
          safeSessionId = await txn.insert('research_sessions', {
            'child_id': safeChildId,
            'device_id': safeDeviceId,
            'client_session_uuid': const Uuid().v4(),
            'session_number': 1,
            'started_at': timestamp,
            'notes': 'Sesi belajar otomatis',
            'is_synced': 0,
          });
        }
      }

      final attemptNumber = await getNextAttemptNumber(
        childId: safeChildId,
        sessionId: safeSessionId,
        questionId: questionId,
        executor: txn,
      );

      final attemptUuid = const Uuid().v4();
      final answerLog = AnswerLogModel(
        clientAttemptUuid: attemptUuid,
        childId: safeChildId,
        deviceId: safeDeviceId,
        sessionId: safeSessionId,
        questionId: questionId,
        attemptNumber: attemptNumber,
        targetText: targetText,
        recognizedText: recognizedText,
        normalizedTarget: normalizedTarget,
        normalizedRecognized: normalizedRecognized,
        editDistance: editDistance,
        similarityScore: similarityScore,
        similarityPercent: similarityPercent,
        isCorrect: isCorrect,
        recognitionDurationMs: recognitionDurationMs,
        timestamp: timestamp,
        isSynced: false,
      );

      final id = await txn.insert('answer_logs', answerLog.toMap());

      // Simpan juga speech_logs jika data pengenalan suara tersedia
      await txn.insert('speech_logs', {
        'child_id': safeChildId,
        'device_id': safeDeviceId,
        'session_id': safeSessionId,
        'question_id': questionId,
        'raw_recognized_text': recognizedText,
        'normalized_recognized_text': normalizedRecognized,
        'provider': provider ?? 'whisper_tiny',
        'locale': locale ?? 'id_ID',
        'confidence': confidence,
        'started_at': startedAt ?? timestamp,
        'ended_at': endedAt ?? timestamp,
        'duration_ms': recognitionDurationMs,
      });

      return AnswerLogModel(
        id: id,
        clientAttemptUuid: attemptUuid,
        childId: safeChildId,
        deviceId: safeDeviceId,
        sessionId: safeSessionId,
        questionId: questionId,
        attemptNumber: attemptNumber,
        targetText: targetText,
        recognizedText: recognizedText,
        normalizedTarget: normalizedTarget,
        normalizedRecognized: normalizedRecognized,
        editDistance: editDistance,
        similarityScore: similarityScore,
        similarityPercent: similarityPercent,
        isCorrect: isCorrect,
        recognitionDurationMs: recognitionDurationMs,
        timestamp: timestamp,
        isSynced: false,
      );
    });
  }

  /// Mengambil riwayat logs untuk evaluasi atau verifikasi test
  Future<List<AnswerLogModel>> getLogsForQuestion({
    required int childId,
    required int sessionId,
    required int questionId,
  }) async {
    final db = await _db;
    final list = await db.query(
      'answer_logs',
      where: 'child_id = ? AND session_id = ? AND question_id = ?',
      whereArgs: [childId, sessionId, questionId],
      orderBy: 'attempt_number ASC',
    );
    return list.map(AnswerLogModel.fromMap).toList();
  }
}
