import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/backend_config.dart';
import '../../data/app_settings.dart';
import '../../data/db/kogo_database.dart';

/// Respons HTTP sederhana.
class HttpResult {
  const HttpResult(this.status, this.body);
  final int status;
  final Map<String, dynamic> body;
}

typedef JsonPost = Future<HttpResult> Function(Uri url, Map<String, dynamic> body, {String? bearer});

class SyncReport {
  const SyncReport({required this.ok, this.learners = 0, this.sessions = 0, this.attempts = 0, this.rejected = 0, this.message});

  final bool ok;
  final int learners;
  final int sessions;
  final int attempts;
  final int rejected;
  final String? message;

  bool get nothingToSend => ok && learners == 0 && sessions == 0 && attempts == 0;
}

/// Mengirim data penelitian (biodata, sesi permainan, jawaban) ke backend
/// secara bertahap. Aplikasi tetap berjalan penuh tanpa internet; data yang
/// belum terkirim ditandai `is_synced = 0` dan dikirim ulang nanti.
///
/// Status sinkron: 0 = belum, -1 = sedang dikirim, 1 = terkirim,
/// 2 = ditolak server (tidak dikirim ulang).
class SyncService {
  SyncService({KogoDatabase? database, AppSettings? settings, JsonPost? post})
    : _database = database ?? KogoDatabase.instance,
      _settings = settings ?? AppSettings(),
      _post = post ?? _defaultPost;

  static SyncService instance = SyncService();

  final KogoDatabase _database;
  final AppSettings _settings;
  final JsonPost _post;
  Future<SyncReport>? _running;
  Timer? _debounce;

  static const _learnerBatch = 50;
  static const _sessionBatch = 200;
  static const _attemptBatch = 500;

  Future<String> apiBaseUrl() async {
    final stored = await _settings.get(AppSettings.backendUrlKey);
    return BackendConfig.normalize(stored ?? BackendConfig.defaultApiBaseUrl);
  }

  Future<DateTime?> lastSyncAt() async {
    final v = await _settings.get(AppSettings.lastSyncKey);
    return v == null ? null : DateTime.tryParse(v)?.toLocal();
  }

  Future<int> pendingCount() async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      'SELECT (SELECT COUNT(*) FROM learners WHERE is_synced = 0) + '
      '(SELECT COUNT(*) FROM game_sessions WHERE is_synced = 0) + '
      '(SELECT COUNT(*) FROM answer_attempts WHERE is_synced = 0) AS c',
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Sinkronisasi diam-diam setelah permainan selesai (gagal = dicoba lagi nanti).
  void syncInBackground() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () => unawaited(syncNow()));
  }

  Future<SyncReport> syncNow() => _running ??= _sync().whenComplete(() => _running = null);

  Future<SyncReport> _sync() async {
    try {
      await _recoverInFlight();
      final base = await apiBaseUrl();
      final token = await _deviceToken(base);
      var learners = 0, sessions = 0, attempts = 0, rejected = 0;
      for (var round = 0; round < 50; round++) {
        final batch = await _claimBatch();
        if (batch.isEmpty) break;
        final HttpResult res;
        try {
          res = await _post(Uri.parse('$base/v2/sync'), batch.payload, bearer: token);
        } catch (e) {
          await _release(batch);
          rethrow;
        }
        if (res.status == 401) {
          await _release(batch);
          await _settings.set(AppSettings.deviceTokenKey, null);
          return const SyncReport(ok: false, message: 'Token perangkat kedaluwarsa. Coba sinkronkan lagi.');
        }
        if (res.status != 200) {
          await _release(batch);
          return SyncReport(ok: false, message: 'Server menolak (${res.status}).');
        }
        final rejectedItems = ((res.body['data'] as Map?)?['rejected'] as List?) ?? const [];
        await _commit(batch, rejectedItems.whereType<Map>().map((r) => '${r['clientUuid']}').toSet());
        learners += batch.learnerIds.length;
        sessions += batch.sessionIds.length;
        attempts += batch.attemptIds.length;
        rejected += rejectedItems.length;
      }
      await _settings.set(AppSettings.lastSyncKey, DateTime.now().toUtc().toIso8601String());
      return SyncReport(ok: true, learners: learners, sessions: sessions, attempts: attempts, rejected: rejected);
    } on SocketException {
      return const SyncReport(ok: false, message: 'Tidak ada koneksi ke server.');
    } on TimeoutException {
      return const SyncReport(ok: false, message: 'Server tidak merespons.');
    } on HandshakeException {
      return const SyncReport(ok: false, message: 'Koneksi aman (HTTPS) gagal.');
    } catch (e) {
      debugPrint('[SyncService] gagal: $e');
      return const SyncReport(ok: false, message: 'Sinkronisasi gagal.');
    }
  }

  Future<String> _deviceToken(String base) async {
    final token = await _settings.get(AppSettings.deviceTokenKey);
    final expiry = DateTime.tryParse(await _settings.get(AppSettings.deviceTokenExpiryKey) ?? '');
    if (token != null && expiry != null && expiry.isAfter(DateTime.now().add(const Duration(days: 1)))) return token;

    var deviceUuid = await _settings.get(AppSettings.deviceUuidKey);
    if (deviceUuid == null) {
      deviceUuid = const Uuid().v4();
      await _settings.set(AppSettings.deviceUuidKey, deviceUuid);
    }
    final res = await _post(Uri.parse('$base/v2/devices/register'), {'deviceUuid': deviceUuid, 'platform': 'android', 'appVersion': appVersion});
    final data = res.body['data'] as Map?;
    final newToken = data?['deviceToken'] as String?;
    if ((res.status != 200 && res.status != 201) || newToken == null) {
      throw HttpException('register device failed (${res.status})');
    }
    final seconds = (data?['expiresIn'] as num?)?.toInt() ?? 86400;
    await _settings.set(AppSettings.deviceTokenKey, newToken);
    await _settings.set(AppSettings.deviceTokenExpiryKey, DateTime.now().add(Duration(seconds: seconds)).toIso8601String());
    return newToken;
  }

  static const appVersion = '2.0.0';

  /// Mengembalikan baris yang tertinggal berstatus "sedang dikirim" (aplikasi
  /// tertutup di tengah sinkronisasi) menjadi "belum terkirim".
  Future<void> _recoverInFlight() async {
    final db = await _database.database;
    for (final table in const ['learners', 'game_sessions', 'answer_attempts']) {
      await db.update(table, {'is_synced': 0}, where: 'is_synced = -1');
    }
  }

  Future<_Batch> _claimBatch() async {
    final db = await _database.database;
    return db.transaction((txn) async {
      // Anak dikirim bersama induknya: sesi hanya bila datanya (learner) sudah
      // terkirim atau ikut batch ini; jawaban hanya bila sesinya demikian.
      final learners = await txn.query('learners', where: 'is_synced = 0', orderBy: 'id', limit: _learnerBatch);
      final learnerIds = [for (final r in learners) r['id'] as int];
      final sessions = await txn.rawQuery(
        'SELECT s.*, l.client_uuid AS learner_uuid FROM game_sessions s '
        'JOIN learners l ON l.id = s.learner_id WHERE s.is_synced = 0 '
        'AND (l.is_synced = 1 OR l.id IN (${_placeholders(learnerIds)})) ORDER BY s.id LIMIT $_sessionBatch',
        learnerIds,
      );
      final sessionIds = [for (final r in sessions) r['id'] as int];
      final attempts = await txn.rawQuery(
        'SELECT a.*, s.client_uuid AS session_uuid, l.client_uuid AS learner_uuid FROM answer_attempts a '
        'JOIN game_sessions s ON s.id = a.session_id JOIN learners l ON l.id = a.learner_id '
        'WHERE a.is_synced = 0 AND (s.is_synced = 1 OR s.id IN (${_placeholders(sessionIds)})) '
        'ORDER BY a.id LIMIT $_attemptBatch',
        sessionIds,
      );
      final batch = _Batch(
        learnerIds: [for (final r in learners) r['id'] as int],
        sessionIds: [for (final r in sessions) r['id'] as int],
        attemptIds: [for (final r in attempts) r['id'] as int],
        uuidToRow: {
          for (final r in learners) r['client_uuid'] as String: ('learners', r['id'] as int),
          for (final r in sessions) r['client_uuid'] as String: ('game_sessions', r['id'] as int),
          for (final r in attempts) r['client_uuid'] as String: ('answer_attempts', r['id'] as int),
        },
        payload: {
          'learners': [
            for (final r in learners)
              {
                'clientUuid': r['client_uuid'],
                'name': r['name'],
                'school': r['school'],
                'age': r['age'],
                'createdAt': r['created_at'],
                'updatedAt': r['updated_at'],
              },
          ],
          'sessions': [
            for (final r in sessions)
              {
                'clientUuid': r['client_uuid'],
                'learnerUuid': r['learner_uuid'],
                'materi': r['materi'],
                'nodeIndex': r['node_index'],
                'gameType': r['game_type'],
                'status': r['status'],
                'totalItems': r['total_items'],
                'firstTryCorrect': r['first_try_correct'],
                'stars': r['stars'],
                'startedAt': r['started_at'],
                'endedAt': r['ended_at'],
              },
          ],
          'attempts': [
            for (final r in attempts)
              {
                'clientUuid': r['client_uuid'],
                'sessionUuid': r['session_uuid'],
                'learnerUuid': r['learner_uuid'],
                'gameType': r['game_type'],
                'targetText': r['target_text'],
                'answerText': _clip(r['answer_text'] as String, 200),
                'isCorrect': r['is_correct'] == 1,
                'attemptNumber': r['attempt_number'],
                'similarity': r['similarity'],
                'responseMs': r['response_ms'],
                'sttError': r['stt_error'],
                'createdAt': r['created_at'],
              },
          ],
        },
      );
      await _mark(txn, batch, from: 0, to: -1);
      return batch;
    });
  }

  Future<void> _release(_Batch batch) async {
    final db = await _database.database;
    await db.transaction((txn) => _mark(txn, batch, from: -1, to: 0));
  }

  Future<void> _commit(_Batch batch, Set<String> rejectedUuids) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      await _mark(txn, batch, from: -1, to: 1);
      for (final uuid in rejectedUuids) {
        final row = batch.uuidToRow[uuid];
        if (row != null) await txn.update(row.$1, {'is_synced': 2}, where: 'id = ?', whereArgs: [row.$2]);
      }
    });
  }

  /// Hanya baris yang statusnya masih [from] yang diubah: bila sebuah sesi
  /// diperbarui saat sedang dikirim (status kembali 0), ia akan dikirim ulang.
  static Future<void> _mark(Transaction txn, _Batch batch, {required int from, required int to}) async {
    for (final entry in {'learners': batch.learnerIds, 'game_sessions': batch.sessionIds, 'answer_attempts': batch.attemptIds}.entries) {
      if (entry.value.isEmpty) continue;
      await txn.rawUpdate('UPDATE ${entry.key} SET is_synced = ? WHERE is_synced = ? AND id IN (${List.filled(entry.value.length, '?').join(',')})', [
        to,
        from,
        ...entry.value,
      ]);
    }
  }

  static String _clip(String s, int max) => s.length <= max ? s : s.substring(0, max);

  /// `NULL` bila kosong agar klausa `IN ()` tetap valid di SQLite.
  static String _placeholders(List<int> ids) => ids.isEmpty ? 'NULL' : List.filled(ids.length, '?').join(',');

  static Future<HttpResult> _defaultPost(Uri url, Map<String, dynamic> body, {String? bearer}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      return await () async {
        final req = await client.postUrl(url);
        req.headers.contentType = ContentType.json;
        if (bearer != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearer');
        req.add(utf8.encode(jsonEncode(body)));
        final res = await req.close();
        final text = await res.transform(utf8.decoder).join();
        Map<String, dynamic> json = const {};
        try {
          final decoded = jsonDecode(text);
          if (decoded is Map<String, dynamic>) json = decoded;
        } catch (_) {}
        return HttpResult(res.statusCode, json);
      }().timeout(const Duration(seconds: 20));
    } finally {
      client.close(force: true);
    }
  }
}

class _Batch {
  const _Batch({required this.learnerIds, required this.sessionIds, required this.attemptIds, required this.uuidToRow, required this.payload});

  final List<int> learnerIds;
  final List<int> sessionIds;
  final List<int> attemptIds;
  final Map<String, (String, int)> uuidToRow;
  final Map<String, dynamic> payload;

  bool get isEmpty => learnerIds.isEmpty && sessionIds.isEmpty && attemptIds.isEmpty;
}
