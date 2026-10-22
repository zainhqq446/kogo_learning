import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kogo_voice_learning/data/database/app_database.dart';
import 'package:kogo_voice_learning/data/repositories/stage_repository.dart';
import 'package:kogo_voice_learning/data/repositories/lesson_repository.dart';
import 'package:kogo_voice_learning/data/repositories/question_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.deleteDatabase();
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  test('Database schema, migrations, tables, and constraints work correctly', () async {
    final db = await AppDatabase.instance.database;

    // 1. Verify 11 required tables exist
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
    );
    final tableNames = tables.map((t) => t['name'] as String).toSet();

    final expectedTables = {
      'users',
      'children',
      'devices',
      'stages',
      'lessons',
      'questions',
      'research_sessions',
      'answer_logs',
      'speech_logs',
      'achievements',
      'child_achievements',
      'learning_words',
    };

    expect(expectedTables.difference(tableNames), isEmpty);

    // 1b. Verify learning_words contains all 450 images
    final learningWordsCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM learning_words'),
    );
    expect(learningWordsCount, equals(450));

    // 2. Verify support for 40 children
    final childrenCount = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM children'),
    );
    expect(childrenCount, greaterThanOrEqualTo(40));

    // Verify child_code formatting P001 to P040
    final p001 = await db.query('children', where: 'child_code = ?', whereArgs: ['P001']);
    expect(p001, isNotEmpty);
    final p040 = await db.query('children', where: 'child_code = ?', whereArgs: ['P040']);
    expect(p040, isNotEmpty);

    // 3. Verify devices & multi-child device usage
    // Register 1 device
    final now = DateTime.now().toIso8601String();
    final devicePk = await db.insert('devices', {
      'device_id': 'tablet-001',
      'device_label': 'Tablet Laboratorium 1',
      'platform': 'android',
      'app_version': '1.0.0',
      'registered_at': now,
      'last_used_at': now,
    });

    final child1 = p001.first['id'] as int;
    final child2 = p040.first['id'] as int;

    // Both children use the same device
    final session1Id = await db.insert('research_sessions', {
      'child_id': child1,
      'device_id': devicePk,
      'session_number': 1,
      'started_at': now,
      'notes': 'Sesi anak 1 pada tablet 1',
    });

    final session2Id = await db.insert('research_sessions', {
      'child_id': child2,
      'device_id': devicePk,
      'session_number': 1,
      'started_at': now,
      'notes': 'Sesi anak 40 pada tablet yang sama',
    });

    expect(session1Id, greaterThan(0));
    expect(session2Id, greaterThan(0));

    // 4. Verify question exists
    final questions = await db.query('questions', limit: 1);
    expect(questions, isNotEmpty);
    final questionId = questions.first['id'] as int;

    // 5. Verify answer_logs insertion with all required columns
    final answerLogId = await db.insert('answer_logs', {
      'child_id': child1,
      'device_id': devicePk,
      'session_id': session1Id,
      'question_id': questionId,
      'attempt_number': 1,
      'target_text': 'A',
      'recognized_text': 'a',
      'normalized_target': 'a',
      'normalized_recognized': 'a',
      'edit_distance': 0,
      'similarity_score': 1.0,
      'similarity_percent': 100.0,
      'is_correct': 1,
      'recognition_duration_ms': 1200,
      'timestamp': now,
    });
    expect(answerLogId, greaterThan(0));

    // Second attempt for same question (attempt history preserved)
    final answerLog2Id = await db.insert('answer_logs', {
      'child_id': child1,
      'device_id': devicePk,
      'session_id': session1Id,
      'question_id': questionId,
      'attempt_number': 2,
      'target_text': 'A',
      'recognized_text': 'ha',
      'normalized_target': 'a',
      'normalized_recognized': 'ha',
      'edit_distance': 1,
      'similarity_score': 0.5,
      'similarity_percent': 50.0,
      'is_correct': 0,
      'recognition_duration_ms': 1500,
      'timestamp': now,
    });
    expect(answerLog2Id, greaterThan(answerLogId));

    // 6. Verify speech_logs insertion with all required columns
    final speechLogId = await db.insert('speech_logs', {
      'child_id': child1,
      'device_id': devicePk,
      'session_id': session1Id,
      'question_id': questionId,
      'raw_recognized_text': 'A',
      'normalized_recognized_text': 'a',
      'provider': 'sherpa_onnx',
      'locale': 'id_ID',
      'confidence': 0.95,
      'started_at': now,
      'ended_at': now,
      'duration_ms': 1200,
    });
    expect(speechLogId, greaterThan(0));

    // 7. Verify indices exist
    final indexRows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'",
    );
    final indexNames = indexRows.map((i) => i['name'] as String).toList();
    expect(indexNames, contains('idx_children_code'));
    expect(indexNames, contains('idx_answer_logs_child'));
    expect(indexNames, contains('idx_speech_logs_child'));
  });

  test('StageRepository, LessonRepository, and QuestionRepository can read seeded data correctly', () async {
    // 1. StageRepository reads all 4 stages
    final stageRepo = StageRepository();
    final stages = await stageRepo.getAll();
    expect(stages.length, equals(4));

    final stageTitles = stages.map((s) => s.title).toList();
    expect(stageTitles, containsAll([
      'Huruf',
      'Dua Suku Kata',
      'Tiga Suku Kata',
      'Banyak Suku Kata',
    ]));

    final lessonRepo = LessonRepository();
    final questionRepo = QuestionRepository();

    const expectedLessonTypes = [
      'listen_repeat',
      'find_object',
      'matching',
      'listen_carefully',
      'missing_letter',
    ];

    // 2. Each stage has all 5 lesson types and questions
    for (final stage in stages) {
      final lessons = await lessonRepo.getByStageId(stage.id!);
      expect(lessons.length, equals(5));

      final lessonTypes = lessons.map((l) => l.lessonType).toList();
      expect(lessonTypes, containsAll(expectedLessonTypes));

      for (final lesson in lessons) {
        final questions = await questionRepo.getByLessonId(lesson.id!);
        expect(questions, isNotEmpty, reason: 'Lesson ${lesson.title} in stage ${stage.title} must have questions');
        
        final firstQ = questions.first;
        expect(firstQ.targetText, isNotEmpty);
        expect(firstQ.normalizedTarget, isNotEmpty);

        final singleQ = await questionRepo.getById(firstQ.id!);
        expect(singleQ, isNotNull);
        expect(singleQ!.id, equals(firstQ.id));
      }
    }
  });
}
