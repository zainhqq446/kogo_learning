import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'db/kogo_database.dart';

/// Profil anak (entitas Users pada ERD): nama, sekolah, dan umur.
class Learner {
  const Learner({required this.id, required this.clientUuid, required this.name, required this.school, required this.age, this.avatar = '🐻'});

  final int id;
  final String clientUuid;
  final String name;
  final String school;
  final int age;
  final String avatar;

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  factory Learner.fromMap(Map<String, Object?> m) => Learner(
    id: m['id'] as int,
    clientUuid: m['client_uuid'] as String,
    name: m['name'] as String,
    school: m['school'] as String,
    age: m['age'] as int,
    avatar: (m['avatar'] as String?) ?? '🐻',
  );
}

/// Hasil validasi biodata (proposal Gambar 3.4: data harus valid & lengkap).
class BiodataValidation {
  BiodataValidation._();

  static const minAge = 5;
  static const maxAge = 6;
  static const maxNameLength = 40;
  static const maxSchoolLength = 60;

  static final _allowed = RegExp(r"^[A-Za-zÀ-ÿ0-9 .,'\-]+$");

  static String? name(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Nama belum diisi';
    if (v.length < 2) return 'Nama terlalu pendek';
    if (v.length > maxNameLength) return 'Nama maksimal $maxNameLength huruf';
    if (!_allowed.hasMatch(v)) return 'Nama hanya boleh berisi huruf';
    return null;
  }

  static String? school(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Sekolah belum diisi';
    if (v.length < 2) return 'Nama sekolah terlalu pendek';
    if (v.length > maxSchoolLength) return 'Nama sekolah maksimal $maxSchoolLength huruf';
    if (!_allowed.hasMatch(v)) return 'Nama sekolah tidak valid';
    return null;
  }

  /// Sesuai batasan masalah: media ditujukan untuk anak usia 5–6 tahun.
  static String? age(int? value) {
    if (value == null) return 'Pilih umur';
    if (value < minAge || value > maxAge) return 'Umur harus 5 atau 6 tahun';
    return null;
  }
}

class LearnerRepository {
  LearnerRepository({KogoDatabase? database}) : _database = database ?? KogoDatabase.instance;

  final KogoDatabase _database;
  static const _activeKey = 'active_learner_id';

  Future<Learner> create({required String name, required String school, required int age, String avatar = '🐻'}) async {
    final error = BiodataValidation.name(name) ?? BiodataValidation.school(school) ?? BiodataValidation.age(age);
    if (error != null) throw ArgumentError(error);
    final db = await _database.database;
    final now = DateTime.now().toUtc().toIso8601String();
    final uuid = const Uuid().v4();
    final id = await db.insert('learners', {
      'client_uuid': uuid,
      'name': _clean(name),
      'school': _clean(school),
      'age': age,
      'avatar': avatar,
      'created_at': now,
      'updated_at': now,
    });
    return Learner(id: id, clientUuid: uuid, name: _clean(name), school: _clean(school), age: age, avatar: avatar);
  }

  Future<Learner> update(Learner learner, {required String name, required String school, required int age}) async {
    final error = BiodataValidation.name(name) ?? BiodataValidation.school(school) ?? BiodataValidation.age(age);
    if (error != null) throw ArgumentError(error);
    final db = await _database.database;
    await db.update(
      'learners',
      {'name': _clean(name), 'school': _clean(school), 'age': age, 'updated_at': DateTime.now().toUtc().toIso8601String(), 'is_synced': 0},
      where: 'id = ?',
      whereArgs: [learner.id],
    );
    return Learner(id: learner.id, clientUuid: learner.clientUuid, name: _clean(name), school: _clean(school), age: age, avatar: learner.avatar);
  }

  Future<List<Learner>> all() async {
    final db = await _database.database;
    final rows = await db.query('learners', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(Learner.fromMap).toList();
  }

  Future<Learner?> byId(int id) async {
    final db = await _database.database;
    final rows = await db.query('learners', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Learner.fromMap(rows.first);
  }

  Future<void> setActive(int learnerId) async {
    final db = await _database.database;
    await db.insert('app_state', {'key': _activeKey, 'value': '$learnerId'}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Learner?> active() async {
    final db = await _database.database;
    final rows = await db.query('app_state', where: 'key = ?', whereArgs: [_activeKey], limit: 1);
    if (rows.isEmpty) return null;
    final id = int.tryParse(rows.first['value'] as String);
    return id == null ? null : byId(id);
  }

  Future<void> clearActive() async {
    final db = await _database.database;
    await db.delete('app_state', where: 'key = ?', whereArgs: [_activeKey]);
  }

  static String _clean(String v) => v.trim().replaceAll(RegExp(r'\s+'), ' ');
}
