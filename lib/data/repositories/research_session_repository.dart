import 'package:uuid/uuid.dart';
import '../database/app_database.dart';
import '../models/research_session_model.dart';

class ResearchSessionRepository {
  final AppDatabase _database;

  ResearchSessionRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  /// Memulai sesi penelitian baru untuk child_id pada device_id tertentu.
  /// Menghitung nomor sesi secara otomatis berdasarkan riwayat sesi child tersebut.
  Future<ResearchSessionModel> startSession({
    required int childId,
    required int deviceId,
    String? notes,
  }) async {
    final db = await _database.database;

    // Hitung session number terakhir untuk anak ini
    final lastSession = await db.query(
      'research_sessions',
      columns: ['session_number'],
      where: 'child_id = ?',
      whereArgs: [childId],
      orderBy: 'session_number DESC',
      limit: 1,
    );

    final nextSessionNumber = lastSession.isEmpty
        ? 1
        : ((lastSession.first['session_number'] as int) + 1);

    final now = DateTime.now().toIso8601String();
    final sessionUuid = const Uuid().v4();
    final session = ResearchSessionModel(
      clientSessionUuid: sessionUuid,
      childId: childId,
      deviceId: deviceId,
      sessionNumber: nextSessionNumber,
      startedAt: now,
      notes: notes,
      isSynced: false,
    );

    final data = session.toMap();
    data.remove('id');
    final insertedId = await db.insert('research_sessions', data);

    return session.copyWith(id: insertedId);
  }

  /// Mengakhiri sesi penelitian yang sedang berlangsung.
  Future<ResearchSessionModel?> endSession({
    required int sessionId,
    String? notes,
  }) async {
    final db = await _database.database;
    final now = DateTime.now().toIso8601String();

    final updateData = <String, dynamic>{
      'ended_at': now,
    };
    if (notes != null) {
      updateData['notes'] = notes;
    }

    await db.update(
      'research_sessions',
      updateData,
      where: 'id = ?',
      whereArgs: [sessionId],
    );

    return getById(sessionId);
  }

  Future<ResearchSessionModel?> getById(int id) async {
    final db = await _database.database;
    final result = await db.query(
      'research_sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return ResearchSessionModel.fromMap(result.first);
  }

  /// Mengambil riwayat sesi khusus milik child tertentu (isolasi data child).
  Future<List<ResearchSessionModel>> getSessionsByChildId(int childId) async {
    final db = await _database.database;
    final result = await db.query(
      'research_sessions',
      where: 'child_id = ?',
      whereArgs: [childId],
      orderBy: 'session_number DESC',
    );

    return result.map(ResearchSessionModel.fromMap).toList();
  }

  /// Mengambil sesi aktif terakhir milik child (jika ada yang belum di-end).
  Future<ResearchSessionModel?> getActiveSession(int childId) async {
    final db = await _database.database;
    final result = await db.query(
      'research_sessions',
      where: 'child_id = ? AND ended_at IS NULL',
      whereArgs: [childId],
      orderBy: 'id DESC',
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return ResearchSessionModel.fromMap(result.first);
  }
}
