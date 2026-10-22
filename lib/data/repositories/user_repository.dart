import '../database/app_database.dart';
import '../models/user_model.dart';
import '../../services/auth/hash_service.dart';

class UserRepository {
  final AppDatabase _database;

  UserRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  Future<int> insertUser(UserModel user) async {
    final db = await _database.database;
    final data = user.toMap();
    data.remove('id');
    return db.insert('users', data);
  }

  Future<UserModel?> getByUsername(String username) async {
    final db = await _database.database;
    final result = await db.query(
      'users',
      where: 'username = ?',
      whereArgs: [username],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return UserModel.fromMap(result.first);
  }

  /// Verifikasi login researcher/teacher berdasarkan username dan password.
  Future<UserModel?> authenticate(String username, String password) async {
    final user = await getByUsername(username);
    if (user == null) {
      return null;
    }

    if (HashService.verify(password, user.passwordHash)) {
      return user;
    }

    return null;
  }
}
