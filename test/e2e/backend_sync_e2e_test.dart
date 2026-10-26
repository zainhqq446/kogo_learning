// End-to-end check of the app's SyncService against a real Kogo backend.
// Skipped unless a backend is running:
//   KOGO_E2E_API=http://127.0.0.1:4000/api KOGO_E2E_ADMIN_USER=kogo_admin \
//   KOGO_E2E_ADMIN_PASSWORD=... flutter test test/e2e/backend_sync_e2e_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kogo_voice_learning/core/curriculum/curriculum.dart';
import 'package:kogo_voice_learning/data/db/kogo_database.dart';
import 'package:kogo_voice_learning/data/learner_repository.dart';
import 'package:kogo_voice_learning/data/progress_repository.dart';
import 'package:kogo_voice_learning/services/sync/sync_service.dart';

import '../helpers/test_database.dart';

final _api = Platform.environment['KOGO_E2E_API'];

Future<(int, Map<String, dynamic>)> _call(String method, String path, {String? token, Object? body}) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, Uri.parse('$_api$path'));
    req.headers.contentType = ContentType.json;
    if (token != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    if (body != null) req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return (res.statusCode, text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>);
  } finally {
    client.close(force: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('app data reaches the backend and metrics agree with Table 3.1', () async {
    HttpOverrides.global = null; // flutter_test memblokir HTTP secara bawaan
    await useFreshTestDatabase();
    final sync = SyncService();
    final learners = LearnerRepository();
    final progress = ProgressRepository();
    await sync.switchServer(_api);

    // Satu anak memainkan Dengar & Ulangi: 1 galat suara, 3 benar, 1 salah.
    final kid = await learners.create(name: 'Sarah Putri', school: 'TK Pertiwi', age: 6);
    final node = Curriculum.nodesOf(Materi.duaSuku).first;
    final s1 = await progress.startSession(learnerId: kid.id, node: node);
    Future<void> attempt(String target, String answer, bool ok, {String? error, int? ms}) => progress.logAttempt(
      sessionId: s1,
      learnerId: kid.id,
      game: GameType.listenRepeat,
      target: target,
      answer: answer,
      isCorrect: ok,
      attemptNumber: 1,
      responseMs: ms,
      sttError: error,
    );
    await attempt('bola', '', false, error: 'noSpeech');
    await attempt('bola', 'bola', true, ms: 800);
    await attempt('buku', 'buka', true, ms: 1200);
    await attempt('kuda', 'gajah', false, ms: 1000);
    await attempt('susu', 'susu', true, ms: 1000);
    await progress.completeSession(sessionId: s1, learnerId: kid.id, node: node, totalItems: 4, firstTryCorrect: 3);
    final s2 = await progress.startSession(learnerId: kid.id, node: Curriculum.nodesOf(Materi.duaSuku)[1]);
    await progress.abandonSession(s2);

    final first = await sync.syncNow();
    expect(first.ok, isTrue, reason: first.message);
    expect((first.learners, first.sessions, first.attempts, first.rejected), (1, 2, 5, 0));
    final device = await sync.deviceStatus();
    expect(device.registered, isTrue);
    expect(device.approved, isFalse, reason: 'new devices wait for researcher approval');

    final (loginStatus, login) = await _call(
      'POST',
      '/auth/login',
      body: {'username': Platform.environment['KOGO_E2E_ADMIN_USER'] ?? 'kogo_admin', 'password': Platform.environment['KOGO_E2E_ADMIN_PASSWORD']},
    );
    expect(loginStatus, 200);
    final admin = login['data']['tokens']['accessToken'] as String;

    // Data perangkat yang belum disetujui dikarantina dari metrik bawaan.
    final (_, quarantined) = await _call('GET', '/v2/research/metrics', token: admin);
    expect(quarantined['data']['overall']['sttAttempts'], 0);
    expect(quarantined['data']['devices']['pending'], greaterThanOrEqualTo(1));

    final (approveStatus, _) = await _call('POST', '/v2/research/devices/${device.deviceId}/approve', token: admin, body: {'label': 'E2E tablet'});
    expect(approveStatus, 200);
    final refreshed = await sync.syncNow(refreshDevice: true);
    expect(refreshed.ok, isTrue, reason: refreshed.message);
    expect((await sync.deviceStatus()).approved, isTrue);

    final (_, metricsBody) = await _call('GET', '/v2/research/metrics', token: admin);
    final server = metricsBody['data']['perLearner'].firstWhere((l) => l['name'] == 'Sarah Putri') as Map<String, dynamic>;
    final local = await progress.metrics(learnerId: kid.id);
    expect(server['sttAttempts'], local.sttAttempts);
    expect(server['sttCorrect'], local.sttCorrect);
    expect((server['sttAccuracy'] as num).toDouble(), closeTo(local.sttAccuracy!, 0.01));
    expect((server['taskCompletion'] as num).toDouble(), closeTo(local.taskCompletion!, 0.01));
    expect((server['errorRate'] as num).toDouble(), closeTo(local.errorRate!, 0.01));
    expect(server['avgResponseMs'], local.avgResponseMs);
    expect(server['age'], 6);

    // Pengiriman ulang penuh (mis. setelah ganti server) bersifat idempoten.
    await sync.switchServer('http://127.0.0.2:9/api');
    await sync.switchServer(_api);
    final resent = await sync.syncNow();
    expect(resent.ok, isTrue, reason: resent.message);
    expect(resent.rejected, 0);
    final (_, again) = await _call('GET', '/v2/research/metrics', token: admin);
    expect(again['data']['perLearner'].where((l) => l['name'] == 'Sarah Putri').single['sttAttempts'], local.sttAttempts);

    // Token rusak → 401 → daftar ulang otomatis dengan deviceSecret.
    final db = await KogoDatabase.instance.database;
    await db.update('app_state', {'value': 'broken.token.value'}, where: "key LIKE 'device_token@%'");
    await learners.update(kid, name: kid.name, school: 'TK Pertiwi 2', age: 6);
    final recovered = await sync.syncNow();
    expect(recovered.ok, isTrue, reason: recovered.message);
    expect(recovered.learners, 1);

    // Perangkat dicabut → sinkron berhenti dengan pesan jelas.
    final (revokeStatus, _) = await _call('POST', '/v2/research/devices/${device.deviceId}/revoke', token: admin);
    expect(revokeStatus, 200);
    await learners.update(kid, name: kid.name, school: 'TK Pertiwi 3', age: 6);
    final revoked = await sync.syncNow();
    expect(revoked.ok, isFalse);
    expect(revoked.message, contains('dicabut'));
  }, skip: _api == null ? 'set KOGO_E2E_API to run against a live backend' : false);
}
