import '../database/app_database.dart';
import '../models/stage_model.dart';

class StageRepository {
  final AppDatabase _database;

  StageRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  Future<List<StageModel>> getAll() async {
    final db = await _database.database;

    final result = await db.query(
      'stages',
      where: 'is_active = ?',
      whereArgs: [1],
      orderBy: 'order_index ASC',
    );

    return result.map(StageModel.fromMap).toList();
  }

  Future<StageModel?> getById(int id) async {
    final db = await _database.database;

    final result = await db.query(
      'stages',
      where: 'id = ? AND is_active = ?',
      whereArgs: [id, 1],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return StageModel.fromMap(result.first);
  }
}