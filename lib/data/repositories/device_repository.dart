import 'dart:io';
import '../database/app_database.dart';
import '../models/device_model.dart';

class DeviceRepository {
  final AppDatabase _database;

  DeviceRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  Future<DeviceModel?> getByDeviceId(String deviceId) async {
    final db = await _database.database;
    final result = await db.query(
      'devices',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return DeviceModel.fromMap(result.first);
  }

  Future<DeviceModel?> getById(int id) async {
    final db = await _database.database;
    final result = await db.query(
      'devices',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (result.isEmpty) {
      return null;
    }

    return DeviceModel.fromMap(result.first);
  }

  /// Mendaftarkan atau mendapatkan identitas device saat ini secara otomatis
  Future<DeviceModel> getOrCreateDevice({
    required String deviceId,
    String? deviceLabel,
    String? platform,
    String? appVersion,
  }) async {
    final existing = await getByDeviceId(deviceId);
    final now = DateTime.now().toIso8601String();

    if (existing != null) {
      final db = await _database.database;
      await db.update(
        'devices',
        {'last_used_at': now},
        where: 'id = ?',
        whereArgs: [existing.id],
      );
      return existing.copyWith(lastUsedAt: now);
    }

    final effectivePlatform = platform ?? (Platform.isAndroid ? 'android' : Platform.isIOS ? 'ios' : 'unknown');
    final newDevice = DeviceModel(
      deviceId: deviceId,
      deviceLabel: deviceLabel ?? 'Kogo Device',
      platform: effectivePlatform,
      appVersion: appVersion ?? '1.0.0',
      registeredAt: now,
      lastUsedAt: now,
    );

    final db = await _database.database;
    final data = newDevice.toMap();
    data.remove('id');
    final insertedId = await db.insert('devices', data);

    return newDevice.copyWith(id: insertedId);
  }
}
