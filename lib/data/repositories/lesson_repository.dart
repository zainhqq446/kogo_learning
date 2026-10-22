import '../database/app_database.dart';
import '../models/lesson_model.dart';

class LessonRepository {
  final AppDatabase _database;

  LessonRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  Future<List<LessonModel>> getByStageId(int stageId) async {
    final db = await _database.database;

    final result = await db.query(
      'lessons',
      where: 'stage_id = ? AND is_active = ?',
      whereArgs: [stageId, 1],
      orderBy: 'order_index ASC',
    );

    return result.map(LessonModel.fromMap).toList();
  }

  Future<LessonModel?> getByStageIdAndType(int stageId, String lessonType) async {
    final db = await _database.database;

    final result = await db.query(
      'lessons',
      where: 'stage_id = ? AND lesson_type = ? AND is_active = ?',
      whereArgs: [stageId, lessonType, 1],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return LessonModel.fromMap(result.first);
  }

  Future<LessonModel?> getById(int id) async {
    final db = await _database.database;

    final result = await db.query(
      'lessons',
      where: 'id = ? AND is_active = ?',
      whereArgs: [id, 1],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return LessonModel.fromMap(result.first);
  }
}