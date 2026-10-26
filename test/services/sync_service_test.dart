import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/core/curriculum/curriculum.dart';
import 'package:kogo_voice_learning/data/db/kogo_database.dart';
import 'package:kogo_voice_learning/data/learner_repository.dart';
import 'package:kogo_voice_learning/data/progress_repository.dart';
import 'package:kogo_voice_learning/services/sync/sync_service.dart';

import '../helpers/test_database.dart';

class _Request {
  _Request(this.url, this.body, this.bearer, this.headers);
  final Uri url;
  final Map<String, dynamic> body;
  final String? bearer;
  final Map<String, String> headers;
  String get path => url.path;
}

/// Server v2 palsu: mencatat permintaan dan meniru aturan registrasi perangkat.
class _FakeServer {
  final requests = <_Request>[];
  final knownSecrets = <String, String>{};

  /// Respons paksa berikutnya: (status, kode galat).
  final responses = <(int, String)>[];
  final rejectUuids = <String>{};

  /// Data yang dimiliki server per host (untuk meniru UNKNOWN_LEARNER/SESSION).
  final learners = <String>{};
  final sessions = <String>{};
  bool approved = false;
  bool dropNextRegisterResponse = false;
  int _tokens = 0;

  /// Meniru server yang dipulihkan dari cadangan lama.
  void forgetData() {
    learners.clear();
    sessions.clear();
  }

  static String jwt(String deviceId, int n) {
    String part(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
    return '${part({'alg': 'HS256'})}.${part({'deviceId': deviceId, 'n': n})}.sig';
  }

  Future<HttpResult> post(Uri url, Map<String, dynamic> body, {String? bearer, Map<String, String>? headers}) async {
    requests.add(_Request(url, jsonDecode(jsonEncode(body)) as Map<String, dynamic>, bearer, headers ?? const {}));
    if (responses.isNotEmpty) {
      final (status, code) = responses.removeAt(0);
      return HttpResult(status, {'status': 'error', 'statusCode': status, 'code': code});
    }
    if (url.path.endsWith('/v2/devices/register')) {
      final uuid = '${url.host}|${body['deviceUuid']}';
      final known = knownSecrets[uuid];
      if (known != null && body['deviceSecret'] != known) {
        return const HttpResult(409, {'code': 'DEVICE_PROOF_REQUIRED'});
      }
      final secret = known ?? 'secret-${knownSecrets.length + 1}-abcdefghijklmnopqrstu';
      knownSecrets[uuid] = secret;
      if (dropNextRegisterResponse) {
        dropNextRegisterResponse = false;
        throw const SocketException('connection reset after the server stored the device');
      }
      return HttpResult(known == null ? 201 : 200, {
        'status': 'success',
        'data': {
          'deviceToken': jwt('dev-1234567890', ++_tokens),
          'expiresIn': 15552000,
          'deviceSecret': ?(known == null ? secret : null),
          'approved': approved,
        },
      });
    }
    final rejected = <Map<String, String>>[];
    void reject(String type, String uuid, String code) => rejected.add({'type': type, 'clientUuid': uuid, 'code': code});
    for (final l in (body['learners'] as List).cast<Map>()) {
      final uuid = l['clientUuid'] as String;
      rejectUuids.contains(uuid) ? reject('learners', uuid, 'INVALID') : learners.add(uuid);
    }
    for (final ses in (body['sessions'] as List).cast<Map>()) {
      final uuid = ses['clientUuid'] as String;
      if (rejectUuids.contains(uuid)) {
        reject('sessions', uuid, 'INVALID');
      } else if (!learners.contains(ses['learnerUuid'])) {
        reject('sessions', uuid, 'UNKNOWN_LEARNER');
      } else {
        sessions.add(uuid);
      }
    }
    for (final a in (body['attempts'] as List).cast<Map>()) {
      final uuid = a['clientUuid'] as String;
      if (rejectUuids.contains(uuid)) {
        reject('attempts', uuid, 'INVALID');
      } else if (!sessions.contains(a['sessionUuid'])) {
        reject('attempts', uuid, 'UNKNOWN_SESSION');
      }
    }
    return HttpResult(200, {
      'status': 'success',
      'data': {'accepted': {}, 'rejected': rejected},
    });
  }

  List<_Request> get syncs => requests.where((r) => r.path.endsWith('/v2/sync')).toList();
  List<_Request> get registrations => requests.where((r) => r.path.endsWith('/v2/devices/register')).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized(); // channel model perangkat
  late _FakeServer server;
  late SyncService sync;
  late LearnerRepository learners;
  late ProgressRepository progress;

  setUp(() async {
    await useFreshTestDatabase();
    server = _FakeServer();
    sync = SyncService(post: server.post);
    learners = LearnerRepository();
    progress = ProgressRepository();
  });

  Future<void> playOneGame() async {
    final kid = await learners.create(name: 'Sarah', school: 'TK Pertiwi', age: 6);
    final node = Curriculum.nodesOf(Materi.duaSuku).first;
    final session = await progress.startSession(learnerId: kid.id, node: node);
    await progress.logAttempt(
      sessionId: session,
      learnerId: kid.id,
      game: GameType.listenRepeat,
      target: 'bola',
      answer: '',
      isCorrect: false,
      attemptNumber: 1,
      sttError: 'noSpeech',
    );
    await progress.logAttempt(
      sessionId: session,
      learnerId: kid.id,
      game: GameType.listenRepeat,
      target: 'bola',
      answer: 'bola',
      isCorrect: true,
      attemptNumber: 1,
      responseMs: 900,
    );
    await progress.completeSession(sessionId: session, learnerId: kid.id, node: node, totalItems: 4, firstTryCorrect: 4);
  }

  Future<Map<String, int>> syncedStates() async {
    final db = await KogoDatabase.instance.database;
    final out = <String, int>{};
    for (final t in const ['learners', 'game_sessions', 'answer_attempts']) {
      final rows = await db.rawQuery('SELECT is_synced, COUNT(*) AS c FROM $t GROUP BY is_synced');
      for (final r in rows) {
        out['$t:${r['is_synced']}'] = r['c'] as int;
      }
    }
    return out;
  }

  test('first sync registers the device, stores its secret and sends parents with children', () async {
    await playOneGame();
    final report = await sync.syncNow();
    expect(report.ok, isTrue, reason: report.message);
    expect((report.learners, report.sessions, report.attempts), (1, 1, 2));

    final reg = server.registrations.single;
    expect(reg.body['platform'], 'android');
    expect(reg.body.containsKey('deviceSecret'), isFalse);
    expect(reg.headers, isEmpty, reason: 'no enrollment key configured');

    final payload = server.syncs.single.body;
    expect(payload['learners'], hasLength(1));
    expect(payload['sessions'].single['status'], 'completed');
    expect(payload['attempts'], hasLength(2));
    expect(payload['attempts'].first['sttError'], 'noSpeech');
    expect(server.syncs.single.bearer, isNotNull);
    expect(await syncedStates(), {'learners:1': 1, 'game_sessions:1': 1, 'answer_attempts:1': 2});

    final status = await sync.deviceStatus();
    expect(status.registered, isTrue);
    expect(status.approved, isFalse);
    expect(status.deviceId, 'dev-1234567890');

    expect((await sync.syncNow()).nothingToSend, isTrue);
    expect(server.registrations, hasLength(1), reason: 'token is reused');
  });

  test('manual refresh re-registers with the stored secret and current token', () async {
    await sync.syncNow();
    server.approved = true;
    await sync.syncNow(refreshDevice: true);
    final second = server.registrations.last;
    expect(second.body['deviceSecret'], startsWith('secret-1'));
    expect(second.bearer, isNotNull);
    expect((await sync.deviceStatus()).approved, isTrue);
  });

  test('401 on sync re-registers once and retries the same batch', () async {
    await playOneGame();
    await sync.syncNow();
    await playOneGame();
    server.responses.add((401, 'TOKEN_EXPIRED'));
    final report = await sync.syncNow();
    expect(report.ok, isTrue, reason: report.message);
    expect(server.registrations, hasLength(2));
    expect(server.registrations.last.body['deviceSecret'], isNotNull);
    expect(await syncedStates(), {'learners:1': 2, 'game_sessions:1': 2, 'answer_attempts:1': 4});
  });

  test('revoked device stops with a clear message and keeps data queued', () async {
    await sync.syncNow();
    await playOneGame();
    server.responses.add((403, 'DEVICE_REVOKED'));
    final report = await sync.syncNow();
    expect(report.ok, isFalse);
    expect(report.message, contains('dicabut'));
    expect(await syncedStates(), {'learners:0': 1, 'game_sessions:0': 1, 'answer_attempts:0': 2});
  });

  test('lost secret gives DEVICE_PROOF_REQUIRED guidance instead of a new identity', () async {
    await sync.syncNow();
    final db = await KogoDatabase.instance.database;
    await db.delete('app_state', where: "key LIKE 'device_secret@%' OR key LIKE 'device_token@%'");
    await playOneGame();
    final report = await sync.syncNow();
    expect(report.ok, isFalse);
    expect(report.message, contains('reset'));
    expect(server.registrations.map((r) => r.body['deviceUuid']).toSet(), hasLength(1));
  });

  test('items rejected by the server are not resent', () async {
    await playOneGame();
    final db = await KogoDatabase.instance.database;
    final attempt = (await db.query('answer_attempts', orderBy: 'id', limit: 1)).single;
    server.rejectUuids.add(attempt['client_uuid'] as String);
    final report = await sync.syncNow();
    expect(report.rejected, 1);
    expect(await syncedStates(), {'learners:1': 1, 'game_sessions:1': 1, 'answer_attempts:1': 1, 'answer_attempts:2': 1});
  });

  test('switching server resends everything with that server\'s own credentials', () async {
    await playOneGame();
    await sync.syncNow();
    expect(server.syncs.single.url.host, 'be-kogo.taro.web.id');

    await sync.switchServer('https://test.example.org/api');
    expect(await sync.pendingCount(), 4);
    expect((await sync.deviceStatus()).registered, isFalse);
    final report = await sync.syncNow();
    expect((report.learners, report.sessions, report.attempts), (1, 1, 2));
    expect(server.registrations.last.url.host, 'test.example.org');
    expect(server.registrations.last.body.containsKey('deviceSecret'), isFalse, reason: 'secrets are per server');

    // Kembali ke server awal: rahasia lama masih dipakai, bukan identitas baru.
    await sync.switchServer(null);
    final back = await sync.syncNow(refreshDevice: true);
    expect(back.ok, isTrue, reason: back.message);
    expect(server.registrations.last.body['deviceSecret'], startsWith('secret-1'));

    // Menyimpan alamat yang sama tidak mengirim ulang apa pun.
    await sync.switchServer(null);
    expect(await sync.pendingCount(), 0);
  });

  test('server that lost synced data (backup restore) gets everything resent once', () async {
    await playOneGame();
    await sync.syncNow();
    server.forgetData();
    final db = await KogoDatabase.instance.database;
    final kid = (await learners.all()).single;
    final node = Curriculum.nodesOf(Materi.duaSuku)[1];
    final session = await progress.startSession(learnerId: kid.id, node: node);
    await progress.completeSession(sessionId: session, learnerId: kid.id, node: node, totalItems: 4, firstTryCorrect: 4);

    final report = await sync.syncNow();
    expect(report.ok, isTrue, reason: report.message);
    expect(report.rejected, 0);
    expect(await sync.pendingCount(), 0);
    expect(await sync.rejectedCount(), 0);
    expect(server.learners, hasLength(1));
    expect(server.sessions, hasLength(2), reason: 'old and new sessions are back on the server');
    expect((await db.query('game_sessions', where: 'is_synced = 1')).length, 2);
  });

  test('a permanently rejected learner takes its unsent children with it, and an edit resends them', () async {
    final kid = await learners.create(name: 'Sarah', school: 'TK Pertiwi', age: 6);
    server.rejectUuids.add(kid.clientUuid);
    await sync.syncNow();
    final node = Curriculum.nodesOf(Materi.duaSuku).first;
    final session = await progress.startSession(learnerId: kid.id, node: node);
    await progress.completeSession(sessionId: session, learnerId: kid.id, node: node, totalItems: 4, firstTryCorrect: 4);

    final second = await sync.syncNow();
    expect(second.nothingToSend, isTrue);
    expect(await sync.pendingCount(), 0, reason: 'nothing is silently stranded at is_synced = 0');
    expect(await sync.rejectedCount(), 2);
    expect(await syncedStates(), {'learners:2': 1, 'game_sessions:2': 1});

    server.rejectUuids.clear();
    await learners.update(kid, name: 'Sarah', school: 'TK Pertiwi', age: 6);
    final fixed = await sync.syncNow();
    expect((fixed.learners, fixed.sessions), (1, 1));
    expect(await syncedStates(), {'learners:1': 1, 'game_sessions:1': 1});
  });

  test('lost response of the very first registration recovers with a fresh identity', () async {
    await playOneGame();
    server.dropNextRegisterResponse = true;
    final failed = await sync.syncNow();
    expect(failed.ok, isFalse);
    final ok = await sync.syncNow();
    expect(ok.ok, isTrue, reason: ok.message);
    expect(server.registrations.map((r) => r.body['deviceUuid']).toSet(), hasLength(2));
  });

  test('manual refresh hitting the rate limit keeps syncing with the valid token', () async {
    await sync.syncNow();
    await playOneGame();
    server.responses.add((429, 'TOO_MANY_REQUESTS'));
    final report = await sync.syncNow(refreshDevice: true);
    expect(report.ok, isTrue, reason: report.message);
    expect(report.learners, 1);
  });

  test('pending device over its quota keeps data queued with a clear message', () async {
    await sync.syncNow();
    await playOneGame();
    server.responses.add((403, 'DEVICE_PENDING_QUOTA'));
    final report = await sync.syncNow();
    expect(report.ok, isFalse);
    expect(report.message, contains('belum disetujui'));
    expect(await sync.pendingCount(), 4);
  });

  test('network failure releases claimed rows for the next attempt', () async {
    await playOneGame();
    final failing = SyncService(
      post: (url, body, {bearer, headers}) async =>
          url.path.endsWith('/v2/sync') ? throw const SocketException('offline') : server.post(url, body, bearer: bearer, headers: headers),
    );
    final report = await failing.syncNow();
    expect(report.ok, isFalse);
    expect(report.message, 'Tidak ada koneksi ke server.');
    expect(await syncedStates(), {'learners:0': 1, 'game_sessions:0': 1, 'answer_attempts:0': 2});
  });

  test('research metrics use the Table 3.1 session-based error rate', () async {
    await playOneGame();
    await playOneGame();
    final kid = (await learners.all()).first;
    final node = Curriculum.nodesOf(Materi.duaSuku).first;
    await progress.startSession(learnerId: kid.id, node: node);
    final m = await progress.metrics();
    expect(m.sessionsStarted, 3);
    expect(m.sessionsCompleted, 2);
    expect(m.sessionsWithErrors, 2);
    expect(m.errorRate, closeTo(66.67, 0.01));
    expect(m.sttAttempts, 4);
    expect(m.sttAccuracy, 50);
    expect(m.avgResponseMs, 900);
  });
}
