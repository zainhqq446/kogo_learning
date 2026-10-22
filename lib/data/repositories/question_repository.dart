import '../database/app_database.dart';
import '../models/question_model.dart';

class QuestionRepository {
  final AppDatabase _database;

  QuestionRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  Future<List<QuestionModel>> getByLessonId(int lessonId) async {
    final db = await _database.database;

    final result = await db.query(
      'questions',
      where: 'lesson_id = ? AND is_active = ?',
      whereArgs: [lessonId, 1],
      orderBy: 'order_index ASC',
    );

    return result.map(QuestionModel.fromMap).toList();
  }

  Future<QuestionModel?> getById(int id) async {
    final db = await _database.database;

    final result = await db.query(
      'questions',
      where: 'id = ? AND is_active = ?',
      whereArgs: [id, 1],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return QuestionModel.fromMap(result.first);
  }
}