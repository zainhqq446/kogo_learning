import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/constants/image_dataset_catalog.dart';
import '../../services/auth/hash_service.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String _databaseName = 'kogo_voice_learning.db';
  static const int _databaseVersion = 9;

  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _openDatabase();
    return _database!;
  }

  Future<Database> _openDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);

    return openDatabase(
      path,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createTables(db);
        await _createIndexes(db);
        await _seedInitialData(db);
        await _seedLearningData(db);
        await _seedChildren(db, count: 40);
        await _createLearningWordsTable(db);
        await _populateAllDatasetImages(db);
        await _createActivityProgressTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _seedLearningData(db);
        }
        if (oldVersion < 3) {
          await _createIndexes(db);
          await _seedChildren(db, count: 40);
        }
        if (oldVersion < 4) {
          await _seedLearningData(db);
        }
        if (oldVersion < 5) {
          await _seedLearningData(db);
        }
        if (oldVersion < 6) {
          await _migrateToV6(db);
        }
        if (oldVersion < 7) {
          await _createLearningWordsTable(db);
        }
        if (oldVersion < 8) {
          await _populateAllDatasetImages(db);
        }
        if (oldVersion < 9) {
          await _createActivityProgressTable(db);
        }
      },
    );
  }

  Future<void> _migrateToV6(Database db) async {
    // Tambahkan kolom sinkronisasi ke research_sessions
    try {
      await db.execute('ALTER TABLE research_sessions ADD COLUMN client_session_uuid TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE research_sessions ADD COLUMN is_synced INTEGER NOT NULL DEFAULT 0');
    } catch (_) {}

    // Tambahkan kolom sinkronisasi ke answer_logs
    try {
      await db.execute('ALTER TABLE answer_logs ADD COLUMN client_attempt_uuid TEXT');
    } catch (_) {}
    try {
      await db.execute('ALTER TABLE answer_logs ADD COLUMN is_synced INTEGER NOT NULL DEFAULT 0');
    } catch (_) {}

    // Backfill UUID untuk data sesi atau log yang sudah ada
    final sessions = await db.query('research_sessions', columns: ['id'], where: 'client_session_uuid IS NULL');
    for (final s in sessions) {
      final id = s['id'] as int;
      final generatedUuid = '00000000-0000-4000-8000-${id.toString().padLeft(12, '0')}';
      await db.update(
        'research_sessions',
        {'client_session_uuid': generatedUuid},
        where: 'id = ?',
        whereArgs: [id],
      );
    }

    final answers = await db.query('answer_logs', columns: ['id'], where: 'client_attempt_uuid IS NULL');
    for (final a in answers) {
      final id = a['id'] as int;
      final generatedUuid = '00000000-0000-4000-9000-${id.toString().padLeft(12, '0')}';
      await db.update(
        'answer_logs',
        {'client_attempt_uuid': generatedUuid},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> _seedLearningData(Database db) async {
  // Ambil ID Stage berdasarkan order_index agar tidak bergantung
  // pada ID yang kebetulan diberikan SQLite.
  final stages = await db.query(
    'stages',
    columns: ['id', 'order_index'],
    orderBy: 'order_index ASC',
  );

  if (stages.length < 4) {
    return;
  }

  for (final stage in stages) {
    final stageId = stage['id'] as int;
    final stageOrder = stage['order_index'] as int;

    final lessonDefinitions = [
      {
        'title': 'Listen & Repeat',
        'description': 'Dengarkan contoh lalu ulangi.',
        'lesson_type': 'listen_repeat',
        'order_index': 1,
      },
      {
        'title': 'Find Object',
        'description': 'Temukan objek yang sesuai.',
        'lesson_type': 'find_object',
        'order_index': 2,
      },
      {
        'title': 'Matching Object',
        'description': 'Pasangkan objek yang sesuai.',
        'lesson_type': 'matching',
        'order_index': 3,
      },
      {
        'title': 'Listen Carefully',
        'description': 'Dengarkan dan pilih jawaban yang benar.',
        'lesson_type': 'listen_carefully',
        'order_index': 4,
      },
      {
        'title': 'Missing Letter',
        'description': 'Lengkapi huruf yang hilang.',
        'lesson_type': 'missing_letter',
        'order_index': 5,
      },
    ];

    for (final lesson in lessonDefinitions) {
      final existingLesson = await db.query(
        'lessons',
        where: 'stage_id = ? AND title = ?',
        whereArgs: [stageId, lesson['title']],
        limit: 1,
      );

      if (existingLesson.isEmpty) {
        await db.insert('lessons', {
          'stage_id': stageId,
          'title': lesson['title'],
          'description': lesson['description'],
          'lesson_type': lesson['lesson_type'],
          'order_index': lesson['order_index'],
          'is_active': 1,
        });
      }
    }

    // Pertanyaan seed untuk setiap stage agar mendukung pengujian komprehensif
    final questionsMap = <int, Map<String, List<Map<String, dynamic>>>>{
      // Stage 1: Huruf
      1: {
        'listen_repeat': [
          {'target_text': 'A', 'hint_text': 'Ucapkan huruf A'},
          {'target_text': 'B', 'hint_text': 'Ucapkan huruf B'},
          {'target_text': 'C', 'hint_text': 'Ucapkan huruf C'},
          {'target_text': 'D', 'hint_text': 'Ucapkan huruf D'},
          {'target_text': 'E', 'hint_text': 'Ucapkan huruf E'},
        ],
        'find_object': [
          {'target_text': 'Apel', 'hint_text': 'Cari benda berawalan huruf A'},
          {'target_text': 'Bola', 'hint_text': 'Cari benda berawalan huruf B'},
        ],
        'matching': [
          {'target_text': 'A - Apel', 'hint_text': 'Pasangkan huruf A dengan Apel'},
          {'target_text': 'B - Bola', 'hint_text': 'Pasangkan huruf B dengan Bola'},
        ],
        'listen_carefully': [
          {'target_text': 'A', 'hint_text': 'Dengarkan baik-baik lalu pilih huruf A'},
          {'target_text': 'B', 'hint_text': 'Dengarkan baik-baik lalu pilih huruf B'},
        ],
        'missing_letter': [
          {'target_text': 'Apel', 'hint_text': 'Lengkapi huruf pada kata Apel'},
          {'target_text': 'Bola', 'hint_text': 'Lengkapi huruf pada kata Bola'},
        ],
      },
      // Stage 2: Dua Suku Kata
      2: {
        'listen_repeat': [
          {'target_text': 'Buku', 'hint_text': 'Ucapkan kata Bu-ku'},
          {'target_text': 'Bola', 'hint_text': 'Ucapkan kata Bo-la'},
          {'target_text': 'Meja', 'hint_text': 'Ucapkan kata Me-ja'},
          {'target_text': 'Sapi', 'hint_text': 'Ucapkan kata Sa-pi'},
          {'target_text': 'Kaki', 'hint_text': 'Ucapkan kata Ka-ki'},
        ],
        'find_object': [
          {'target_text': 'Buku', 'hint_text': 'Temukan gambar Buku'},
          {'target_text': 'Meja', 'hint_text': 'Temukan gambar Meja'},
        ],
        'matching': [
          {'target_text': 'Bu - ku', 'hint_text': 'Pasangkan suku kata Bu dan ku'},
          {'target_text': 'Me - ja', 'hint_text': 'Pasangkan suku kata Me dan ja'},
        ],
        'listen_carefully': [
          {'target_text': 'Buku', 'hint_text': 'Dengarkan lalu pilih kata Buku'},
          {'target_text': 'Bola', 'hint_text': 'Dengarkan lalu pilih kata Bola'},
        ],
        'missing_letter': [
          {'target_text': 'Buku', 'hint_text': 'Lengkapi huruf yang hilang pada Buku'},
          {'target_text': 'Meja', 'hint_text': 'Lengkapi huruf yang hilang pada Meja'},
        ],
      },
      // Stage 3: Tiga Suku Kata
      3: {
        'listen_repeat': [
          {'target_text': 'Sepatu', 'hint_text': 'Ucapkan kata Se-pa-tu'},
          {'target_text': 'Kereta', 'hint_text': 'Ucapkan kata Ke-re-ta'},
          {'target_text': 'Kelinci', 'hint_text': 'Ucapkan kata Ke-lin-ci'},
          {'target_text': 'Kamera', 'hint_text': 'Ucapkan kata Ka-me-ra'},
        ],
        'find_object': [
          {'target_text': 'Sepatu', 'hint_text': 'Temukan objek Sepatu'},
          {'target_text': 'Kelinci', 'hint_text': 'Temukan hewan Kelinci'},
        ],
        'matching': [
          {'target_text': 'Se - pa - tu', 'hint_text': 'Susun tiga suku kata Sepatu'},
          {'target_text': 'Ke - re - ta', 'hint_text': 'Susun tiga suku kata Kereta'},
        ],
        'listen_carefully': [
          {'target_text': 'Sepatu', 'hint_text': 'Dengarkan suara dan pilih Sepatu'},
          {'target_text': 'Kereta', 'hint_text': 'Dengarkan suara dan pilih Kereta'},
        ],
        'missing_letter': [
          {'target_text': 'Sepatu', 'hint_text': 'Lengkapi huruf pada Sepatu'},
          {'target_text': 'Kereta', 'hint_text': 'Lengkapi huruf pada Kereta'},
        ],
      },
      // Stage 4: Banyak Suku Kata
      4: {
        'listen_repeat': [
          {'target_text': 'Helikopter', 'hint_text': 'Ucapkan kata He-li-kop-ter'},
          {'target_text': 'Matahari', 'hint_text': 'Ucapkan kata Ma-ta-ha-ri'},
          {'target_text': 'Laboratorium', 'hint_text': 'Ucapkan kata La-bo-ra-to-ri-um'},
        ],
        'find_object': [
          {'target_text': 'Helikopter', 'hint_text': 'Temukan gambar Helikopter'},
          {'target_text': 'Matahari', 'hint_text': 'Temukan gambar Matahari'},
        ],
        'matching': [
          {'target_text': 'He - li - kop - ter', 'hint_text': 'Cocokkan suku kata Helikopter'},
          {'target_text': 'Ma - ta - ha - ri', 'hint_text': 'Cocokkan suku kata Matahari'},
        ],
        'listen_carefully': [
          {'target_text': 'Helikopter', 'hint_text': 'Dengarkan lalu pilih Helikopter'},
          {'target_text': 'Matahari', 'hint_text': 'Dengarkan lalu pilih Matahari'},
        ],
        'missing_letter': [
          {'target_text': 'Helikopter', 'hint_text': 'Lengkapi huruf pada Helikopter'},
          {'target_text': 'Matahari', 'hint_text': 'Lengkapi huruf pada Matahari'},
        ],
      },
    };

    final stageQuestions = questionsMap[stageOrder];
    if (stageQuestions != null) {
      for (final entry in stageQuestions.entries) {
        final lessonType = entry.key;
        final questionsList = entry.value;

        final targetLessons = await db.query(
          'lessons',
          where: 'stage_id = ? AND lesson_type = ?',
          whereArgs: [stageId, lessonType],
          limit: 1,
        );

        if (targetLessons.isEmpty) continue;
        final lessonId = targetLessons.first['id'] as int;

        for (int i = 0; i < questionsList.length; i++) {
          final q = questionsList[i];
          final target = q['target_text'] as String;
          final order = i + 1;

          final existingQuestion = await db.query(
            'questions',
            where: 'lesson_id = ? AND order_index = ?',
            whereArgs: [lessonId, order],
            limit: 1,
          );

          if (existingQuestion.isEmpty) {
            final imagePath = ImageDatasetCatalog.findAssetPath(target);
            await db.insert('questions', {
              'lesson_id': lessonId,
              'target_text': target,
              'normalized_target': target.toLowerCase().trim(),
              'image_path': imagePath,
              'audio_path': 'assets/audio/words/${target.toLowerCase()}.mp3',
              'hint_text': q['hint_text'],
              'order_index': order,
              'is_active': 1,
            });
          }
        }
      }
    }
  }
}

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE children (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        child_code TEXT NOT NULL UNIQUE,
        display_name TEXT NOT NULL,
        age INTEGER,
        pin_hash TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE devices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id TEXT NOT NULL UNIQUE,
        device_label TEXT,
        platform TEXT NOT NULL,
        app_version TEXT,
        registered_at TEXT NOT NULL,
        last_used_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE stages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        description TEXT,
        order_index INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE lessons (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        stage_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        lesson_type TEXT NOT NULL,
        order_index INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (stage_id)
          REFERENCES stages(id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE questions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        lesson_id INTEGER NOT NULL,
        target_text TEXT NOT NULL,
        normalized_target TEXT NOT NULL,
        image_path TEXT,
        audio_path TEXT,
        hint_text TEXT,
        order_index INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        FOREIGN KEY (lesson_id)
          REFERENCES lessons(id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE research_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_session_uuid TEXT UNIQUE,
        child_id INTEGER NOT NULL,
        device_id INTEGER NOT NULL,
        session_number INTEGER NOT NULL,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        notes TEXT,
        is_synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (child_id)
          REFERENCES children(id)
          ON DELETE CASCADE,
        FOREIGN KEY (device_id)
          REFERENCES devices(id)
          ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE answer_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_attempt_uuid TEXT UNIQUE,
        child_id INTEGER NOT NULL,
        device_id INTEGER NOT NULL,
        session_id INTEGER NOT NULL,
        question_id INTEGER NOT NULL,
        attempt_number INTEGER NOT NULL,

        target_text TEXT NOT NULL,
        recognized_text TEXT NOT NULL,
        normalized_target TEXT NOT NULL,
        normalized_recognized TEXT NOT NULL,

        edit_distance INTEGER NOT NULL,
        similarity_score REAL NOT NULL,
        similarity_percent REAL NOT NULL,

        is_correct INTEGER NOT NULL,

        recognition_duration_ms INTEGER,
        timestamp TEXT NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,

        FOREIGN KEY (child_id)
          REFERENCES children(id)
          ON DELETE CASCADE,

        FOREIGN KEY (device_id)
          REFERENCES devices(id)
          ON DELETE RESTRICT,

        FOREIGN KEY (session_id)
          REFERENCES research_sessions(id)
          ON DELETE CASCADE,

        FOREIGN KEY (question_id)
          REFERENCES questions(id)
          ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE speech_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        child_id INTEGER NOT NULL,
        device_id INTEGER NOT NULL,
        session_id INTEGER NOT NULL,
        question_id INTEGER NOT NULL,

        raw_recognized_text TEXT NOT NULL,
        normalized_recognized_text TEXT NOT NULL,

        provider TEXT,
        locale TEXT,
        confidence REAL,

        started_at TEXT,
        ended_at TEXT,
        duration_ms INTEGER,

        FOREIGN KEY (child_id)
          REFERENCES children(id)
          ON DELETE CASCADE,

        FOREIGN KEY (device_id)
          REFERENCES devices(id)
          ON DELETE RESTRICT,

        FOREIGN KEY (session_id)
          REFERENCES research_sessions(id)
          ON DELETE CASCADE,

        FOREIGN KEY (question_id)
          REFERENCES questions(id)
          ON DELETE RESTRICT
      )
    ''');

    await db.execute('''
      CREATE TABLE achievements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL,
        description TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE child_achievements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        child_id INTEGER NOT NULL,
        achievement_id INTEGER NOT NULL,
        earned_at TEXT NOT NULL,

        FOREIGN KEY (child_id)
          REFERENCES children(id)
          ON DELETE CASCADE,

        FOREIGN KEY (achievement_id)
          REFERENCES achievements(id)
          ON DELETE CASCADE,

        UNIQUE (child_id, achievement_id)
      )
    ''');
  }

  Future<void> _createIndexes(Database db) async {
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_children_code
      ON children(child_code)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_devices_id
      ON devices(device_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_lessons_stage
      ON lessons(stage_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_questions_lesson
      ON questions(lesson_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_research_sessions_child
      ON research_sessions(child_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_research_sessions_device
      ON research_sessions(device_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_answer_logs_child
      ON answer_logs(child_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_answer_logs_device
      ON answer_logs(device_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_answer_logs_question
      ON answer_logs(question_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_answer_logs_session
      ON answer_logs(session_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_speech_logs_child
      ON speech_logs(child_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_speech_logs_device
      ON speech_logs(device_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_speech_logs_session
      ON speech_logs(session_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_speech_logs_question
      ON speech_logs(question_id)
    ''');
  }

  Future<void> _createLearningWordsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS learning_words (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id TEXT NOT NULL UNIQUE,
        stage_id INTEGER NOT NULL,
        stage_name TEXT NOT NULL,
        target_text TEXT NOT NULL,
        normalized_target TEXT NOT NULL,
        syllables TEXT NOT NULL,
        category TEXT NOT NULL,
        difficulty_level TEXT NOT NULL,
        question_order INTEGER NOT NULL,
        image_asset_path TEXT NOT NULL,
        audio_asset_path TEXT NOT NULL,
        asset_status TEXT NOT NULL DEFAULT 'PENDING_ASSET',
        is_active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_learning_words_stage
      ON learning_words(stage_id)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_learning_words_category
      ON learning_words(category)
    ''');
  }

  Future<void> _createActivityProgressTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS activity_progress (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        child_id INTEGER NOT NULL,
        lesson_id INTEGER NOT NULL,
        active_question_index INTEGER NOT NULL DEFAULT 0,
        is_completed INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        UNIQUE(child_id, lesson_id),
        FOREIGN KEY (child_id)
          REFERENCES children(id)
          ON DELETE CASCADE,
        FOREIGN KEY (lesson_id)
          REFERENCES lessons(id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_activity_progress_child_lesson
      ON activity_progress(child_id, lesson_id)
    ''');
  }

  Future<void> _seedChildren(Database db, {int count = 40}) async {
    final now = DateTime.now().toIso8601String();

    final defaultPinHash = HashService.hashPassword('1234');

    for (int i = 1; i <= count; i++) {
      final code = 'P${i.toString().padLeft(3, '0')}';
      final existing = await db.query(
        'children',
        columns: ['id'],
        where: 'child_code = ?',
        whereArgs: [code],
        limit: 1,
      );

      if (existing.isEmpty) {
        await db.insert('children', {
          'child_code': code,
          'display_name': 'Anak $i',
          'age': 5 + (i % 3), // Variasi usia 5-7 tahun
          'pin_hash': defaultPinHash,
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
        });
      }
    }
  }

  Future<void> _seedInitialData(Database db) async {
    final now = DateTime.now().toIso8601String();

    // Stage
    await db.insert('stages', {
      'title': 'Huruf',
      'description': 'Belajar mengenal dan mengucapkan huruf.',
      'order_index': 1,
      'is_active': 1,
    });

    await db.insert('stages', {
      'title': 'Dua Suku Kata',
      'description': 'Belajar membaca dan mengucapkan dua suku kata.',
      'order_index': 2,
      'is_active': 1,
    });

    await db.insert('stages', {
      'title': 'Tiga Suku Kata',
      'description': 'Belajar membaca dan mengucapkan tiga suku kata.',
      'order_index': 3,
      'is_active': 1,
    });

    await db.insert('stages', {
      'title': 'Banyak Suku Kata',
      'description': 'Belajar mengucapkan kata yang lebih panjang.',
      'order_index': 4,
      'is_active': 1,
    });

    // Achievement
    await db.insert('achievements', {
      'code': 'FIRST_PRACTICE',
      'title': 'Latihan Pertama',
      'description': 'Menyelesaikan latihan pertama.',
    });

    await db.insert('achievements', {
      'code': 'TEN_CORRECT',
      'title': '10 Jawaban Benar',
      'description': 'Mendapatkan 10 jawaban benar.',
    });

    await db.insert('achievements', {
      'code': 'STAGE_ONE_COMPLETE',
      'title': 'Stage 1 Selesai',
      'description': 'Menyelesaikan Stage 1.',
    });

    // Akun peneliti / guru dengan password ter-hash
    final researcherPasswordHash = HashService.hashPassword('kogo2026');
    await db.insert('users', {
      'username': 'researcher',
      'password_hash': researcherPasswordHash,
      'role': 'researcher',
      'created_at': now,
      'updated_at': now,
    });
  }

  /// Sinkronisasi aset gambar:
  /// 1. Update image_path di tabel questions yang sudah ada jika gambar tersedia di katalog.
  /// 2. Masukkan seluruh 450 kata dataset gambar ke tabel learning_words jika belum ada.
  Future<void> _populateAllDatasetImages(Database db) async {
    // 1. Update kolom image_path pada tabel questions
    final questions = await db.query('questions');
    for (final q in questions) {
      final id = q['id'] as int;
      final target = q['target_text'] as String?;
      final existingPath = q['image_path'] as String?;

      if (existingPath == null || existingPath.isEmpty) {
        final resolved = ImageDatasetCatalog.findAssetPath(target);
        if (resolved != null) {
          await db.update(
            'questions',
            {'image_path': resolved},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    }

    // 2. Populasi seluruh 450 entri dataset ke tabel learning_words
    final allEntries = ImageDatasetCatalog.allEntries;
    int order = 1;
    for (final entry in allEntries) {
      final wordId = 'word_${entry.word}';
      final existing = await db.query(
        'learning_words',
        columns: ['id'],
        where: 'word_id = ?',
        whereArgs: [wordId],
        limit: 1,
      );

      final stageName = entry.stageFolder.startsWith('1_')
          ? 'Dua Suku Kata'
          : (entry.stageFolder.startsWith('2_') ? 'Tiga Suku Kata' : 'Banyak Suku Kata');

      if (existing.isEmpty) {
        await db.insert('learning_words', {
          'word_id': wordId,
          'stage_id': entry.stageNumber,
          'stage_name': stageName,
          'target_text': entry.word,
          'normalized_target': entry.word.toLowerCase().trim(),
          'syllables': entry.word,
          'category': entry.category,
          'difficulty_level': entry.stageFolder.startsWith('1_')
              ? 'BEGINNER'
              : (entry.stageFolder.startsWith('2_') ? 'INTERMEDIATE' : 'ADVANCED'),
          'question_order': order++,
          'image_asset_path': entry.assetPath,
          'audio_asset_path': 'assets/audio/words/${entry.word}.mp3',
          'asset_status': 'LOCAL_ASSET_READY',
          'is_active': 1,
        });
      } else {
        await db.update(
          'learning_words',
          {
            'image_asset_path': entry.assetPath,
            'asset_status': 'LOCAL_ASSET_READY',
          },
          where: 'word_id = ?',
          whereArgs: [wordId],
        );
      }
    }
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<void> deleteDatabase() async {
    await close();

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);

    await databaseFactory.deleteDatabase(path);
  }
}