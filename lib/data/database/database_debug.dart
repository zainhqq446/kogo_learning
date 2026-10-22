import '../models/child_model.dart';
import '../repositories/child_repository.dart';
import 'package:flutter/foundation.dart';
import 'app_database.dart';

class DatabaseDebug {
  static Future<void> run() async {
    final repository = ChildRepository();

    final now = DateTime.now().toIso8601String();

    final existing = await repository.getChildByCode('P001');

    if (existing == null) {
      await repository.insertChild(
        ChildModel(
          childCode: 'P001',
          displayName: 'Anak 1',
          age: 5,
          pinHash: '1234',
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    final child = await repository.getChildByCode('P001');

    debugPrint('===== DATABASE DEBUG =====');
    debugPrint('ID         : ${child?.id}');
    debugPrint('Child Code : ${child?.childCode}');
    debugPrint('Name       : ${child?.displayName}');
    debugPrint('Age        : ${child?.age}');
    debugPrint('==========================');
  }

  static Future<void> checkLearningData() async {
    final db = await AppDatabase.instance.database;

    final stages = await db.query(
      'stages',
      orderBy: 'order_index ASC',
    );

    debugPrint('===== STAGES =====');

    for (final stage in stages) {
      debugPrint(
        'Stage ${stage['id']}: ${stage['title']}',
      );

      final lessons = await db.query(
        'lessons',
        where: 'stage_id = ?',
        whereArgs: [stage['id']],
        orderBy: 'order_index ASC',
      );

      for (final lesson in lessons) {
        debugPrint(
          '  Lesson ${lesson['id']}: ${lesson['title']}',
        );

        final questions = await db.query(
          'questions',
          where: 'lesson_id = ?',
          whereArgs: [lesson['id']],
          orderBy: 'order_index ASC',
        );

        for (final question in questions) {
          debugPrint(
            '    Question ${question['id']}: '
            '${question['target_text']}',
          );
        }
      }
    }
  }
}