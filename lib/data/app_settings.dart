import 'package:sqflite/sqflite.dart';

import 'db/kogo_database.dart';

/// Pengaturan sederhana (key-value) yang disimpan di tabel `app_state`.
class AppSettings {
  AppSettings({KogoDatabase? database}) : _database = database ?? KogoDatabase.instance;

  final KogoDatabase _database;

  static const soundOnKey = 'sound_on';
  static const musicOnKey = 'music_on';
  static const backendUrlKey = 'backend_url';
  static const deviceUuidKey = 'device_uuid';
  static const deviceTokenKey = 'device_token';
  static const deviceTokenExpiryKey = 'device_token_expiry';
  static const lastSyncKey = 'last_sync_at';

  Future<String?> get(String key) async {
    final db = await _database.database;
    final rows = await db.query('app_state', columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> set(String key, String? value) async {
    final db = await _database.database;
    if (value == null) {
      await db.delete('app_state', where: 'key = ?', whereArgs: [key]);
    } else {
      await db.insert('app_state', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<bool> getBool(String key, {bool fallback = true}) async {
    final v = await get(key);
    return v == null ? fallback : v == '1';
  }

  Future<void> setBool(String key, bool value) => set(key, value ? '1' : '0');
}
