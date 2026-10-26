import 'dart:async';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// Database lokal Kogo Belajar (offline-first).
///
/// Skema v11 mengikuti ERD pada proposal (Gambar 3.20):
/// - `learners`        = Users (nama, sekolah, umur)
/// - `game_sessions`   = GameSessions (sesi bermain per node/permainan)
/// - `stars`           = Stars (bintang terbaik per node peta)
/// - `rewards`         = Rewards (tingkatan Perunggu–Berlian yang diraih)
/// - `answer_attempts` = AnswerLogs (setiap jawaban/ucapan anak)
/// - `app_state`       = pengaturan & profil aktif
///
/// Materi, Stages, WordType, dan Words disimpan sebagai data statis di
/// `lib/core/curriculum` agar aplikasi sepenuhnya berjalan offline.
///
/// Tabel lama (v1–v10) tidak dihapus saat upgrade agar data uji coba
/// sebelumnya tidak hilang; aplikasi baru tidak lagi memakainya.
class KogoDatabase {
  KogoDatabase._();

  static final KogoDatabase instance = KogoDatabase._();

  static const String fileName = 'kogo_voice_learning.db';
  static const int version = 11;

  /// Path khusus untuk pengujian (contoh `inMemoryDatabasePath`).
  static String? overridePath;

  Database? _db;
  Future<Database>? _opening;

  Future<Database> get database {
    final db = _db;
    if (db != null && db.isOpen) return Future.value(db);
    return _opening ??= _open()
        .then((value) {
          _db = value;
          return value;
        })
        .whenComplete(() => _opening = null);
  }

  Future<Database> _open() async {
    final path = overridePath ?? join(await getDatabasesPath(), fileName);
    return openDatabase(
      path,
      version: version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) => createSchema(db),
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 11) await createSchema(db);
      },
    );
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    _opening = null;
    if (db != null && db.isOpen) await db.close();
  }

  static Future<void> createSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS learners (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_uuid TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        school TEXT NOT NULL,
        age INTEGER NOT NULL CHECK (age BETWEEN 5 AND 6),
        avatar TEXT NOT NULL DEFAULT '🐻',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS game_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_uuid TEXT NOT NULL UNIQUE,
        learner_id INTEGER NOT NULL REFERENCES learners(id) ON DELETE CASCADE,
        materi TEXT NOT NULL,
        node_index INTEGER NOT NULL,
        game_type TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'started' CHECK (status IN ('started', 'completed', 'abandoned')),
        total_items INTEGER NOT NULL DEFAULT 0,
        first_try_correct INTEGER NOT NULL DEFAULT 0,
        stars INTEGER NOT NULL DEFAULT 0,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        local_date TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS stars (
        learner_id INTEGER NOT NULL REFERENCES learners(id) ON DELETE CASCADE,
        materi TEXT NOT NULL,
        node_index INTEGER NOT NULL,
        stars INTEGER NOT NULL CHECK (stars BETWEEN 0 AND 3),
        play_count INTEGER NOT NULL DEFAULT 1,
        first_completed_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (learner_id, materi, node_index)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS rewards (
        learner_id INTEGER NOT NULL REFERENCES learners(id) ON DELETE CASCADE,
        tier TEXT NOT NULL,
        min_stars INTEGER NOT NULL,
        earned_at TEXT NOT NULL,
        seen INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (learner_id, tier)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS answer_attempts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_uuid TEXT NOT NULL UNIQUE,
        session_id INTEGER NOT NULL REFERENCES game_sessions(id) ON DELETE CASCADE,
        learner_id INTEGER NOT NULL REFERENCES learners(id) ON DELETE CASCADE,
        game_type TEXT NOT NULL,
        target_text TEXT NOT NULL,
        answer_text TEXT NOT NULL,
        is_correct INTEGER NOT NULL,
        attempt_number INTEGER NOT NULL,
        similarity REAL,
        response_ms INTEGER,
        stt_error TEXT,
        created_at TEXT NOT NULL,
        local_date TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_state (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX IF NOT EXISTS idx_sessions_learner ON game_sessions(learner_id, local_date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_attempts_session ON answer_attempts(session_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_attempts_learner ON answer_attempts(learner_id, game_type)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sessions_sync ON game_sessions(is_synced)');
  }
}
