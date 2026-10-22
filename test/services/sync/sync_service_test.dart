import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kogo_voice_learning/data/database/app_database.dart';
import 'package:kogo_voice_learning/data/repositories/research_session_repository.dart';
import 'package:kogo_voice_learning/data/repositories/answer_log_repository.dart';
import 'package:kogo_voice_learning/data/repositories/device_repository.dart';
import 'package:kogo_voice_learning/services/sync/sync_service.dart';

class MockSyncHttpClient implements HttpClient {
  int postCallCount = 0;
  Map<String, dynamic>? lastRequestBody;
  int statusCode = 200;
  String Function(Map<String, dynamic> body)? responseBuilder;

  @override
  Future<HttpClientRequest> postUrl(Uri url) async {
    postCallCount++;
    return MockSyncHttpClientRequest(
      url: url,
      onWrite: (data) {
        lastRequestBody = jsonDecode(data) as Map<String, dynamic>;
      },
      onClose: () async {
        final bodyText = responseBuilder != null && lastRequestBody != null
            ? responseBuilder!(lastRequestBody!)
            : jsonEncode({
                'status': 'success',
                'data': {
                  'summary': {
                    'totalSessions': (lastRequestBody?['sessions'] as List?)?.length ?? 0,
                    'syncedSessions': (lastRequestBody?['sessions'] as List?)?.length ?? 0,
                    'totalAttempts': (lastRequestBody?['attempts'] as List?)?.length ?? 0,
                    'syncedAttempts': (lastRequestBody?['attempts'] as List?)?.length ?? 0,
                    'failedItems': 0,
                  },
                  'sessions': ((lastRequestBody?['sessions'] as List?) ?? [])
                      .map((s) => {'clientSessionUuid': s['clientSessionUuid'], 'status': 'created'})
                      .toList(),
                  'attempts': ((lastRequestBody?['attempts'] as List?) ?? [])
                      .map((a) => {'clientAttemptUuid': a['clientAttemptUuid'], 'status': 'created'})
                      .toList(),
                },
              });

        return MockSyncHttpClientResponse(
          statusCode: statusCode,
          body: bodyText,
        );
      },
    );
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSyncHttpClientRequest implements HttpClientRequest {
  @override
  final Uri uri;
  final void Function(String) onWrite;
  final Future<HttpClientResponse> Function() onClose;
  @override
  final HttpHeaders headers = MockHttpHeaders();
  final StringBuffer _buffer = StringBuffer();

  MockSyncHttpClientRequest({
    required Uri url,
    required this.onWrite,
    required this.onClose,
  }) : uri = url;

  @override
  void write(Object? obj) {
    _buffer.write(obj);
  }

  @override
  Future<HttpClientResponse> close() async {
    onWrite(_buffer.toString());
    return onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockHttpHeaders implements HttpHeaders {
  final Map<String, String> _headers = {};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    _headers[name.toLowerCase()] = value.toString();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockSyncHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
  @override
  final int statusCode;
  final String body;

  MockSyncHttpClientResponse({
    required this.statusCode,
    required this.body,
  });

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream.value(utf8.encode(body)).listen(
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

  test('SyncService successfully batches offline sessions and attempts to server', () async {
    // 1. Setup device and session
    final deviceRepo = DeviceRepository();
    final device = await deviceRepo.getOrCreateDevice(deviceId: 'flutter-tablet-test');

    final sessionRepo = ResearchSessionRepository();
    final session = await sessionRepo.startSession(
      childId: 1, // P001 from seed
      deviceId: device.id!,
      notes: 'Test offline sync session',
    );
    expect(session.clientSessionUuid, isNotNull);
    expect(session.clientSessionUuid, isNotEmpty);

    // 2. Log answers
    final answerRepo = AnswerLogRepository();
    final answer1 = await answerRepo.logAnswer(
      childId: 1,
      deviceId: device.id!,
      sessionId: session.id!,
      questionId: 1,
      targetText: 'A',
      recognizedText: 'a',
      normalizedTarget: 'a',
      normalizedRecognized: 'a',
      editDistance: 0,
      similarityScore: 1.0,
      similarityPercent: 100.0,
      isCorrect: true,
    );
    expect(answer1.clientAttemptUuid, isNotNull);

    // 3. Check unsynced count
    final mockHttp = MockSyncHttpClient();
    final syncService = SyncService(httpClient: mockHttp);

    final countsBefore = await syncService.getUnsyncedCount();
    expect(countsBefore['sessions'], equals(1));
    expect(countsBefore['attempts'], equals(1));
    expect(countsBefore['total'], equals(2));

    // 4. Perform sync
    final result = await syncService.syncPendingData(
      baseUrl: 'http://localhost:3000',
      authToken: 'mock-valid-jwt-token',
    );

    expect(result.success, isTrue);
    expect(result.syncedSessions, equals(1));
    expect(result.syncedAttempts, equals(1));
    expect(result.failedItems, equals(0));
    expect(mockHttp.postCallCount, equals(1));

    // 5. Verify payload structure
    final payload = mockHttp.lastRequestBody!;
    final sessions = payload['sessions'] as List;
    final attempts = payload['attempts'] as List;
    expect(sessions.length, equals(1));
    expect(attempts.length, equals(1));
    expect(sessions.first['participantCode'], equals('P001'));
    expect(sessions.first['deviceIdentifier'], equals('flutter-tablet-test'));
    expect(attempts.first['clientAttemptUuid'], equals(answer1.clientAttemptUuid));

    // 6. Verify local database records marked as is_synced = 1
    final countsAfter = await syncService.getUnsyncedCount();
    expect(countsAfter['sessions'], equals(0));
    expect(countsAfter['attempts'], equals(0));
    expect(countsAfter['total'], equals(0));

    // 7. Verify subsequent sync has nothing to push
    final emptyResult = await syncService.syncPendingData(
      baseUrl: 'http://localhost:3000',
      authToken: 'mock-valid-jwt-token',
    );
    expect(emptyResult.success, isTrue);
    expect(emptyResult.message, contains('No pending data'));
    expect(mockHttp.postCallCount, equals(1)); // HTTP request was NOT sent unnecessarily
  });

  test('SyncService handles network/server errors gracefully without losing local state', () async {
    final deviceRepo = DeviceRepository();
    final device = await deviceRepo.getOrCreateDevice(deviceId: 'flutter-tablet-test-2');

    final sessionRepo = ResearchSessionRepository();
    await sessionRepo.startSession(
      childId: 1,
      deviceId: device.id!,
    );

    final mockHttp = MockSyncHttpClient();
    mockHttp.statusCode = 500; // Simulate server 500 internal error

    final syncService = SyncService(httpClient: mockHttp);
    final result = await syncService.syncPendingData(
      baseUrl: 'http://localhost:3000',
      authToken: 'mock-valid-jwt-token',
    );

    expect(result.success, isFalse);
    expect(result.message, contains('HTTP 500'));

    // Verify records remain unsynced (is_synced = 0)
    final counts = await syncService.getUnsyncedCount();
    expect(counts['sessions'], equals(1));
  });

  test('SyncService handles partial batch failure correctly and preserves failed items', () async {
    final deviceRepo = DeviceRepository();
    final device = await deviceRepo.getOrCreateDevice(deviceId: 'flutter-tablet-test-partial');

    final sessionRepo = ResearchSessionRepository();
    final session1 = await sessionRepo.startSession(childId: 1, deviceId: device.id!);
    final session2 = await sessionRepo.startSession(childId: 2, deviceId: device.id!);

    final mockHttp = MockSyncHttpClient();
    mockHttp.responseBuilder = (body) {
      return jsonEncode({
        'status': 'success',
        'data': {
          'summary': {
            'totalSessions': 2,
            'syncedSessions': 1,
            'totalAttempts': 0,
            'syncedAttempts': 0,
            'failedItems': 1,
          },
          'sessions': [
            {'clientSessionUuid': session1.clientSessionUuid, 'status': 'created'},
            {
              'clientSessionUuid': session2.clientSessionUuid,
              'status': 'failed',
              'error': "Participant 'P002' not found",
            },
          ],
          'attempts': [],
        },
      });
    };

    final syncService = SyncService(httpClient: mockHttp);
    final result = await syncService.syncPendingData(
      baseUrl: 'http://localhost:3000',
      authToken: 'mock-valid-jwt-token',
    );

    // Harus melaporkan false untuk success penuh, tetapi isPartialSuccess bernilai true
    expect(result.success, isFalse);
    expect(result.isPartialSuccess, isTrue);
    expect(result.syncedSessions, equals(1));
    expect(result.failedItems, equals(1));
    expect(result.errors, contains("Participant 'P002' not found"));

    // Verifikasi database: session1 harus is_synced = 1, session2 tetap 0
    final db = await AppDatabase.instance.database;
    final s1Row = await db.query(
      'research_sessions',
      where: 'client_session_uuid = ?',
      whereArgs: [session1.clientSessionUuid],
    );
    expect(s1Row.first['is_synced'], equals(1));

    final s2Row = await db.query(
      'research_sessions',
      where: 'client_session_uuid = ?',
      whereArgs: [session2.clientSessionUuid],
    );
    expect(s2Row.first['is_synced'], equals(0));

    final counts = await syncService.getUnsyncedCount();
    expect(counts['sessions'], equals(1));
  });

  test('SyncService handles total failure (all items rejected) without false positive success', () async {
    final deviceRepo = DeviceRepository();
    final device = await deviceRepo.getOrCreateDevice(deviceId: 'flutter-tablet-test-all-failed');

    final sessionRepo = ResearchSessionRepository();
    final session = await sessionRepo.startSession(childId: 1, deviceId: device.id!);

    final answerRepo = AnswerLogRepository();
    final answer = await answerRepo.logAnswer(
      childId: 1,
      deviceId: device.id!,
      sessionId: session.id!,
      questionId: 1,
      targetText: 'A',
      recognizedText: 'a',
      normalizedTarget: 'a',
      normalizedRecognized: 'a',
      editDistance: 0,
      similarityScore: 1.0,
      similarityPercent: 100.0,
      isCorrect: true,
    );

    final mockHttp = MockSyncHttpClient();
    mockHttp.responseBuilder = (body) {
      return jsonEncode({
        'status': 'success',
        'data': {
          'summary': {
            'totalSessions': 1,
            'syncedSessions': 0,
            'totalAttempts': 1,
            'syncedAttempts': 0,
            'failedItems': 2,
          },
          'sessions': [
            {
              'clientSessionUuid': session.clientSessionUuid,
              'status': 'failed',
              'error': "Participant 'P001' not found",
            },
          ],
          'attempts': [
            {
              'clientAttemptUuid': answer.clientAttemptUuid,
              'status': 'failed',
              'error': "Session with UUID '${session.clientSessionUuid}' must be created first",
            },
          ],
        },
      });
    };

    final syncService = SyncService(httpClient: mockHttp);
    final result = await syncService.syncPendingData(
      baseUrl: 'http://localhost:3000',
      authToken: 'mock-valid-jwt-token',
    );

    expect(result.success, isFalse);
    expect(result.isAllFailed, isTrue);
    expect(result.syncedSessions, equals(0));
    expect(result.syncedAttempts, equals(0));
    expect(result.failedItems, equals(2));
    expect(result.errors.length, equals(2));

    // Data lokal harus tetap unsynced (is_synced = 0)
    final counts = await syncService.getUnsyncedCount();
    expect(counts['sessions'], equals(1));
    expect(counts['attempts'], equals(1));
  });
}
