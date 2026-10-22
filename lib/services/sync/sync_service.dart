import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../../core/constants/backend_config.dart';
import '../../data/database/app_database.dart';

class SyncResult {
  final bool success;
  final int syncedSessions;
  final int syncedAttempts;
  final int failedItems;
  final String? message;
  final List<String> errors;

  const SyncResult({
    required this.success,
    this.syncedSessions = 0,
    this.syncedAttempts = 0,
    this.failedItems = 0,
    this.message,
    this.errors = const [],
  });

  bool get isPartialSuccess => (syncedSessions + syncedAttempts > 0) && failedItems > 0;
  bool get isAllFailed => (syncedSessions + syncedAttempts == 0) && failedItems > 0;
}

enum SyncStatus {
  idle,
  syncing,
  success,
  offline,
}

class SyncService {
  static final SyncService instance = SyncService();

  final AppDatabase _database;
  final HttpClient _httpClient;
  bool _isAutoSyncRunning = false;
  Timer? _periodicSyncTimer;
  String _cachedAuthToken = '';

  SyncStatus _currentStatus = SyncStatus.idle;
  final StreamController<SyncStatus> _statusController = StreamController<SyncStatus>.broadcast();

  SyncStatus get currentStatus => _currentStatus;
  Stream<SyncStatus> get statusStream => _statusController.stream;

  void _setStatus(SyncStatus status) {
    _currentStatus = status;
    _statusController.add(status);
  }

  SyncService({
    AppDatabase? database,
    HttpClient? httpClient,
  })  : _database = database ?? AppDatabase.instance,
        _httpClient = httpClient ?? HttpClient();

  /// Menyimpan token autentikasi peneliti untuk proses auto-sync latar belakang
  void setAuthToken(String token) {
    _cachedAuthToken = token.trim();
  }

  /// Memulai auto-sync berkala (setiap 30 detik) saat aplikasi online
  void startPeriodicSync({Duration interval = const Duration(seconds: 30)}) {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(interval, (_) {
      autoSyncInBackground();
    });
  }

  /// Menghentikan auto-sync berkala
  void stopPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
  }

  /// Menjalankan sinkronisasi otomatis di latar belakang secara aman tanpa memblokir UI thread.
  Future<SyncResult?> autoSyncInBackground({String? baseUrl, String? authToken}) async {
    if (_isAutoSyncRunning) return null;
    _isAutoSyncRunning = true;
    _setStatus(SyncStatus.syncing);

    try {
      var token = (authToken != null && authToken.isNotEmpty) ? authToken : _cachedAuthToken;
      final serverUrl = (baseUrl != null && baseUrl.isNotEmpty) ? baseUrl : BackendConfig.serverRootUrl;

      // Cek apakah ada data yang belum tersinkronkan
      final counts = await getUnsyncedCount();
      if ((counts['total'] ?? 0) == 0) {
        _setStatus(SyncStatus.idle);
        return const SyncResult(success: true, message: 'All items already synced');
      }

      // Jika token belum ada di cache, minta token otomatis dari backend
      if (token.isEmpty) {
        try {
          token = await _fetchSystemAuthToken(serverUrl);
          if (token.isNotEmpty) {
            _cachedAuthToken = token;
          }
        } catch (e) {
          debugPrint('[SyncService] Gagal mendapatkan system auth token: $e');
        }
      }

      final result = await syncPendingData(
        baseUrl: serverUrl,
        authToken: token,
      );

      if (result.success) {
        _setStatus(SyncStatus.success);
        Future.delayed(const Duration(seconds: 3), () {
          if (_currentStatus == SyncStatus.success) {
            _setStatus(SyncStatus.idle);
          }
        });
        if (kDebugMode && (result.syncedSessions > 0 || result.syncedAttempts > 0)) {
          debugPrint(
            '[AutoSync] Berhasil sinkronisasi latar belakang: '
            '${result.syncedSessions} sesi, ${result.syncedAttempts} percobaan.',
          );
        }
      } else {
        _setStatus(SyncStatus.offline);
      }
      return result;
    } catch (e) {
      _setStatus(SyncStatus.offline);
      if (kDebugMode) {
        debugPrint('[AutoSync] Background sync skipped/failed: $e');
      }
      return null;
    } finally {
      _isAutoSyncRunning = false;
    }
  }


  /// Menghitung jumlah item yang belum disinkronkan ke server.
  Future<Map<String, int>> getUnsyncedCount() async {
    final db = await _database.database;
    final unsyncedSessions = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM research_sessions WHERE is_synced = 0',
        )) ??
        0;

    final unsyncedAttempts = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM answer_logs WHERE is_synced = 0',
        )) ??
        0;

    return {
      'sessions': unsyncedSessions,
      'attempts': unsyncedAttempts,
      'total': unsyncedSessions + unsyncedAttempts,
    };
  }

  /// Melakukan sinkronisasi data tertunda ke backend Kogo Voice Learning.
  Future<SyncResult> syncPendingData({
    required String baseUrl,
    required String authToken,
    int batchSize = 100,
  }) async {
    final db = await _database.database;

    // 1. Ambil sesi yang belum disinkronkan
    final sessionRows = await db.rawQuery('''
      SELECT 
        s.id,
        s.client_session_uuid,
        c.child_code,
        d.device_id,
        s.session_number,
        s.started_at,
        s.ended_at,
        s.notes
      FROM research_sessions s
      JOIN children c ON s.child_id = c.id
      JOIN devices d ON s.device_id = d.id
      WHERE s.is_synced = 0
      LIMIT ?
    ''', [batchSize]);

    // 2. Ambil attempt yang belum disinkronkan
    final attemptRows = await db.rawQuery('''
      SELECT 
        a.id,
        a.client_attempt_uuid,
        s.client_session_uuid,
        c.child_code,
        d.device_id,
        a.question_id,
        a.attempt_number,
        a.target_text,
        a.recognized_text,
        a.normalized_target,
        a.normalized_recognized,
        a.edit_distance,
        a.similarity_score,
        a.similarity_percent,
        a.is_correct,
        a.recognition_duration_ms,
        a.timestamp,
        sp.provider,
        sp.locale,
        sp.confidence
      FROM answer_logs a
      JOIN research_sessions s ON a.session_id = s.id
      JOIN children c ON a.child_id = c.id
      JOIN devices d ON a.device_id = d.id
      LEFT JOIN speech_logs sp ON sp.session_id = a.session_id 
        AND sp.question_id = a.question_id 
        AND sp.started_at = a.timestamp
      WHERE a.is_synced = 0
      LIMIT ?
    ''', [batchSize]);

    if (sessionRows.isEmpty && attemptRows.isEmpty) {
      return const SyncResult(
        success: true,
        syncedSessions: 0,
        syncedAttempts: 0,
        failedItems: 0,
        message: 'No pending data to sync',
      );
    }

    // 3. Format payload sesuai skema POST /api/research/sync/batch
    final sessionsPayload = sessionRows.map((r) {
      final startedIso = _ensureIso8601(r['started_at'] as String);
      final endedIso = r['ended_at'] != null ? _ensureIso8601(r['ended_at'] as String) : null;

      return {
        'clientSessionUuid': r['client_session_uuid'],
        'participantCode': r['child_code'],
        'deviceIdentifier': r['device_id'],
        'sessionSequenceNumber': r['session_number'],
        'startedAt': startedIso,
        'endedAt': endedIso,
        'notes': r['notes'],
      };
    }).toList();

    final attemptsPayload = attemptRows.map((r) {
      final attemptedIso = _ensureIso8601(r['timestamp'] as String);
      final isCorrect = (r['is_correct'] as int) == 1;
      final editDistance = r['edit_distance'] as int;

      String evalStatus = 'INCORRECT';
      if (editDistance == 0) {
        evalStatus = 'EXACT_MATCH';
      } else if (isCorrect) {
        evalStatus = 'ACCEPTED_SIMILAR';
      }

      return {
        'clientAttemptUuid': r['client_attempt_uuid'],
        'clientSessionUuid': r['client_session_uuid'],
        'participantCode': r['child_code'],
        'deviceIdentifier': r['device_id'],
        'questionId': r['question_id'],
        'attemptNumber': r['attempt_number'],
        'targetText': r['target_text'],
        'recognizedText': r['recognized_text'],
        'asrProvider': (r['provider'] as String?) ?? 'whisper_onnx',
        'locale': (r['locale'] as String?) ?? 'id_ID',
        'asrConfidence': (r['confidence'] as num?)?.toDouble() ?? 1.0,
        'durationMs': r['recognition_duration_ms'] as int?,
        'attemptedAt': attemptedIso,
        'evaluation': {
          'normalizedTarget': r['normalized_target'],
          'normalizedRecognized': r['normalized_recognized'],
          'editDistance': editDistance,
          'similarityScore': (r['similarity_score'] as num).toDouble(),
          'similarityPercent': (r['similarity_percent'] as num).toDouble(),
          'isCorrect': isCorrect,
          'evaluationStatus': evalStatus,
          'thresholdUsed': 1.0,
          'evaluationMethod': 'levenshtein_normalized_v1',
          'feedbackText': isCorrect ? 'Hebat!' : 'Ayo coba lagi!',
        },
      };
    }).toList();

    final body = {
      'sessions': sessionsPayload,
      'attempts': attemptsPayload,
    };

    // 4. Kirim request HTTP ke backend
    try {
      final cleanBaseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
      final uri = Uri.parse('$cleanBaseUrl/api/research/sync/batch');

      final request = await _httpClient.postUrl(uri);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $authToken');
      request.write(jsonEncode(body));

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode != HttpStatus.ok) {
        return SyncResult(
          success: false,
          message: 'Server returned HTTP ${response.statusCode}: $responseBody',
        );
      }

      final json = jsonDecode(responseBody) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>;
      final sessionsResult = (data['sessions'] as List<dynamic>?) ?? [];
      final attemptsResult = (data['attempts'] as List<dynamic>?) ?? [];

      // 5. Tandai data yang berhasil sebagai ter-sinkronisasi (is_synced = 1)
      final successfulSessionUuids = sessionsResult
          .where((s) => s['status'] == 'created' || s['status'] == 'already_synced')
          .map((s) => s['clientSessionUuid'] as String)
          .toList();

      final successfulAttemptUuids = attemptsResult
          .where((a) => a['status'] == 'created' || a['status'] == 'already_synced')
          .map((a) => a['clientAttemptUuid'] as String)
          .toList();

      if (successfulSessionUuids.isNotEmpty) {
        final placeholders = List.filled(successfulSessionUuids.length, '?').join(',');
        await db.rawUpdate(
          'UPDATE research_sessions SET is_synced = 1 WHERE client_session_uuid IN ($placeholders)',
          successfulSessionUuids,
        );
      }

      if (successfulAttemptUuids.isNotEmpty) {
        final placeholders = List.filled(successfulAttemptUuids.length, '?').join(',');
        await db.rawUpdate(
          'UPDATE answer_logs SET is_synced = 1 WHERE client_attempt_uuid IN ($placeholders)',
          successfulAttemptUuids,
        );
      }

      final summary = data['summary'] as Map<String, dynamic>?;
      final failedCount = summary?['failedItems'] as int? ??
          (sessionsResult.where((s) => s['status'] == 'failed').length +
              attemptsResult.where((a) => a['status'] == 'failed').length);

      final errors = <String>[];
      for (final s in sessionsResult) {
        if (s['status'] == 'failed' && s['error'] != null) {
          final errStr = s['error'].toString();
          if (!errors.contains(errStr)) {
            errors.add(errStr);
          }
        }
      }
      for (final a in attemptsResult) {
        if (a['status'] == 'failed' && a['error'] != null) {
          final errStr = a['error'].toString();
          if (!errors.contains(errStr)) {
            errors.add(errStr);
          }
        }
      }

      final syncedSessions = summary?['syncedSessions'] as int? ?? successfulSessionUuids.length;
      final syncedAttempts = summary?['syncedAttempts'] as int? ?? successfulAttemptUuids.length;

      final isAllSuccess = failedCount == 0;
      String message;
      if (isAllSuccess) {
        message = 'Sync completed successfully';
      } else if (syncedSessions == 0 && syncedAttempts == 0) {
        message = 'All $failedCount items failed to sync';
      } else {
        message = 'Partially synced: $syncedSessions sessions, $syncedAttempts attempts synced, $failedCount failed';
      }

      return SyncResult(
        success: isAllSuccess,
        syncedSessions: syncedSessions,
        syncedAttempts: syncedAttempts,
        failedItems: failedCount,
        message: message,
        errors: errors,
      );
    } catch (e) {
      return SyncResult(
        success: false,
        message: 'Network or database error during sync: $e',
      );
    }
  }

  String _ensureIso8601(String raw) {
    try {
      final parsed = DateTime.parse(raw);
      return parsed.toUtc().toIso8601String();
    } catch (_) {
      return raw;
    }
  }

  /// Meminta token JWT untuk sinkronisasi otomatis menggunakan kredensial default peneliti
  Future<String> _fetchSystemAuthToken(String serverUrl) async {
    final cleanBaseUrl = serverUrl.endsWith('/') ? serverUrl.substring(0, serverUrl.length - 1) : serverUrl;
    final uri = Uri.parse('$cleanBaseUrl/api/auth/login');

    final request = await _httpClient.postUrl(uri);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.write(jsonEncode({
      'username': 'researcher',
      'password': 'kogo2026',
    }));

    final response = await request.close();
    if (response.statusCode == HttpStatus.ok) {
      final responseBody = await response.transform(utf8.decoder).join();
      final data = jsonDecode(responseBody) as Map<String, dynamic>;
      final tokens = data['data']?['tokens'] as Map<String, dynamic>?;
      return (tokens?['accessToken'] as String?) ?? '';
    }
    return '';
  }

  void dispose() {
    _httpClient.close(force: true);
  }
}
