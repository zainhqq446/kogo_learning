import '../database/app_database.dart';
import '../models/child_model.dart';
import '../../services/auth/hash_service.dart';

class ChildRepository {
  final AppDatabase _database;

  ChildRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  Future<int> insertChild(ChildModel child) async {
    final db = await _database.database;

    final data = child.toMap();
    data.remove('id');

    return db.insert('children', data);
  }

  Future<ChildModel?> getChildByCode(String childCode) async {
    final db = await _database.database;

    final result = await db.query(
      'children',
      where: 'child_code = ? AND is_active = 1',
      whereArgs: [childCode],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return ChildModel.fromMap(result.first);
  }

  /// Menambahkan anak baru atau mengupdate jika childCode sudah ada.
  Future<ChildModel> upsertChild(ChildModel child) async {
    final db = await _database.database;
    final existing = await getChildByCode(child.childCode);

    final data = child.toMap();
    data.remove('id');

    if (existing != null) {
      await db.update(
        'children',
        data,
        where: 'child_code = ?',
        whereArgs: [child.childCode],
      );
      final updated = await getChildByCode(child.childCode);
      return updated ?? child;
    } else {
      final id = await db.insert('children', data);
      return child.copyWith(id: id);
    }
  }


  /// Autentikasi login anak berdasarkan childCode dan PIN.
  Future<ChildModel?> authenticate(String childCode, String pin) async {
    final child = await getChildByCode(childCode);
    if (child == null) {
      return null;
    }

    if (HashService.verify(pin, child.pinHash)) {
      return child;
    }

    return null;
  }

  Future<List<ChildModel>> getAllChildren() async {
    final db = await _database.database;

    final result = await db.query(
      'children',
      where: 'is_active = 1',
      orderBy: 'child_code ASC',
    );

    return result.map(ChildModel.fromMap).toList();
  }

  Future<int> updateChild(ChildModel child) async {
    if (child.id == null) {
      throw ArgumentError('Child ID tidak boleh null saat update.');
    }

    final db = await _database.database;

    final data = child.toMap();
    data.remove('id');

    return db.update(
      'children',
      data,
      where: 'id = ?',
      whereArgs: [child.id],
    );
  }

  Future<int> deactivateChild(int childId) async {
    final db = await _database.database;

    return db.update(
      'children',
      {
        'is_active': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [childId],
    );
  }
}