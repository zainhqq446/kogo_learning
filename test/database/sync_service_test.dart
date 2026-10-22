import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import 'package:kogo_voice_learning/data/database/app_database.dart';
import 'package:kogo_voice_learning/services/sync/sync_service.dart';

class MockSyncHttpClient implements HttpClient {
  int responseCode = 200;
  Map<String, dynamic> responseData = {};
  String? lastRequestBody;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    return _MockSyncRequest(this);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockSyncRequest implements HttpClientRequest {
  final MockSyncHttpClient client;
  final List<int> _bytes = [];
  @override
  final HttpHeaders headers = _MockHeaders();

  _MockSyncRequest(this.client);

  @override
  void write(Object? obj) {
    if (obj != null) {
      _bytes.addAll(utf8.encode(obj.toString()));
    }
  }

  @override
  Future<HttpClientResponse> close() async {
    client.lastRequestBody = utf8.decode(_bytes);
    return _MockSyncResponse(client.responseCode, client.responseData);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHeaders implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockSyncResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  final int statusCode;
  final List<int> _body;

  @override
  final HttpHeaders headers = _MockHeaders();

  _MockSyncResponse(this.statusCode, Map<String, dynamic> data)
      : _body = utf8.encode(jsonEncode(data));

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream.value(_body).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await AppDatabase.instance.deleteDatabase();
  });

  tearDown(() async {
    await AppDatabase.instance.close();
  });

  test('SyncService counts unsynced items, formats payload, and marks as synced', () async {
    final db = await AppDatabase.instance.database;
    final now = DateTime.now().toIso8601String();

    // 1. Masukkan / perbarui data anak dan device
    await db.insert(
      'children',
      {
        'id': 1,
        'child_code': 'P001',
        'display_name': 'Budi',
        'age': 6,
        'pin_hash': '1234',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await db.insert(
      'devices',
      {
        'id': 1,
        'device_id': 'DEV_001',
        'device_label': 'Tablet Lab',
        'platform': 'windows',
        'registered_at': now,
        'last_used_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );


    final sessionUuid = const Uuid().v4();
    await db.insert('research_sessions', {
      'id': 1,
      'child_id': 1,
      'device_id': 1,
      'client_session_uuid': sessionUuid,
      'session_number': 1,
      'started_at': now,
      'notes': 'Test Sync Session',
      'is_synced': 0,
    });

    final attemptUuid = const Uuid().v4();
    await db.insert('answer_logs', {
      'id': 1,
      'client_attempt_uuid': attemptUuid,
      'child_id': 1,
      'device_id': 1,
      'session_id': 1,
      'question_id': 1,
      'attempt_number': 1,
      'target_text': 'MATA',
      'recognized_text': 'MATA',
      'normalized_target': 'mata',
      'normalized_recognized': 'mata',
      'edit_distance': 0,
      'similarity_score': 1.0,
      'similarity_percent': 100.0,
      'is_correct': 1,
      'recognition_duration_ms': 450,
      'timestamp': now,
      'is_synced': 0,
    });

    final mockClient = MockSyncHttpClient();
    mockClient.responseCode = 200;
    mockClient.responseData = {
      'status': 'success',
      'data': {
        'sessions': [
          {'clientSessionUuid': sessionUuid, 'status': 'created'}
        ],
        'attempts': [
          {'clientAttemptUuid': attemptUuid, 'status': 'created'}
        ],
        'summary': {
          'syncedSessions': 1,
          'syncedAttempts': 1,
          'failedItems': 0,
        }
      }
    };

    final syncService = SyncService(
      database: AppDatabase.instance,
      httpClient: mockClient,
    );

    // Verifikasi count unsynced sebelum sync
    final beforeCount = await syncService.getUnsyncedCount();
    expect(beforeCount['sessions'], equals(1));
    expect(beforeCount['attempts'], equals(1));
    expect(beforeCount['total'], equals(2));

    // Jalankan sync
    final result = await syncService.syncPendingData(
      baseUrl: 'http://127.0.0.1:4000',
      authToken: 'mock_jwt_token',
    );

    expect(result.success, isTrue);

    expect(result.syncedSessions, equals(1));
    expect(result.syncedAttempts, equals(1));
    expect(result.failedItems, equals(0));

    // Verifikasi data di SQLite berubah menjadi is_synced = 1
    final afterCount = await syncService.getUnsyncedCount();
    expect(afterCount['total'], equals(0));

    // Verifikasi payload yang dikirim
    expect(mockClient.lastRequestBody, isNotNull);
    final payload = jsonDecode(mockClient.lastRequestBody!) as Map<String, dynamic>;
    final sentSessions = payload['sessions'] as List;
    final sentAttempts = payload['attempts'] as List;

    expect(sentSessions.length, equals(1));
    expect(sentSessions.first['clientSessionUuid'], equals(sessionUuid));
    expect(sentAttempts.length, equals(1));
    expect(sentAttempts.first['clientAttemptUuid'], equals(attemptUuid));
    expect(sentAttempts.first['targetText'], equals('MATA'));
  });
}
