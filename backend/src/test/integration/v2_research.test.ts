import '../helpers/test_env.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createApp } from '../../app.js';
import { setDbPool } from '../../config/database.js';
import { signAccessToken } from '../../services/token_service.js';
import { MetricsService } from '../../services/metrics_service.js';
import { createTestPool, createUserWithToken, prepareTestDatabase } from '../helpers/db.js';
import { bearer, deviceToken, getJson, noRateLimits, postJson, startServer, TestServer } from '../helpers/http.js';

const DAY1 = '2026-10-10';
const DAY2 = '2026-10-20';
const at = (day: string, minute: number) => `${day}T0${Math.floor(minute / 60)}:${String(minute % 60).padStart(2, '0')}:00.000Z`;

/** Unduh CSV sebagai byte mentah (Response.text() membuang BOM UTF-8). */
async function getCsv(url: string, headers: Record<string, string>) {
  const res = await fetch(url, { headers });
  const bytes = new Uint8Array(await res.arrayBuffer());
  return { status: res.status, headers: res.headers, bytes, text: new TextDecoder('utf-8', { ignoreBOM: true }).decode(bytes) };
}

interface AttemptSpec {
  correct: boolean;
  responseMs: number | null;
  sttError?: string | null;
  gameType?: string;
}

test('API v2 research metrics and CSV exports (real PostgreSQL)', async (t) => {
  const pool = await createTestPool();
  await prepareTestDatabase(pool);
  setDbPool(pool);
  let server: TestServer | undefined;
  t.after(async () => {
    await server?.close();
    await pool.end();
  });
  server = await startServer(createApp({ rateLimiters: noRateLimits() }));
  const base = server.baseUrl;

  // Peneliti nyata (agar audit_logs dapat mereferensikan user_id).
  const researcher = await pool.query<{ id: string }>(
    `INSERT INTO users (username, password_hash, full_name, role) VALUES ('peneliti_metrik', 'x', 'Peneliti', 'researcher') RETURNING id`
  );
  const researcherAuth = bearer(signAccessToken({ userId: researcher.rows[0].id, username: 'peneliti_metrik', role: 'researcher' }));

  const deviceUuid = randomUUID();
  const reg = await postJson(base, '/api/v2/devices/register', { deviceUuid, platform: 'android', appVersion: '2.0.0' });
  const deviceAuth = bearer(reg.body.data.deviceToken);
  const deviceId = (JSON.parse(Buffer.from(reg.body.data.deviceToken.split('.')[1], 'base64url').toString()) as { deviceId: string })
    .deviceId;
  const teacher = await createUserWithToken(pool, 'teacher');
  const child = await createUserWithToken(pool, 'child');
  const admin = await createUserWithToken(pool, 'admin');

  const L1 = randomUUID();
  const L2 = randomUUID();
  const S = { s1: randomUUID(), s2: randomUUID(), s3: randomUUID(), s4: randomUUID(), s5: randomUUID() };

  const attempts: unknown[] = [];
  const addAttempts = (sessionUuid: string, learnerUuid: string, day: string, specs: AttemptSpec[]) => {
    specs.forEach((spec, i) =>
      attempts.push({
        clientUuid: randomUUID(),
        sessionUuid,
        learnerUuid,
        gameType: spec.gameType ?? 'speaking',
        targetText: 'bola',
        answerText: spec.correct ? 'bola' : 'bolu',
        isCorrect: spec.correct,
        attemptNumber: 1,
        similarity: spec.correct ? 1 : 0.5,
        responseMs: spec.responseMs,
        sttError: spec.sttError ?? null,
        createdAt: at(day, 10 + i),
      })
    );
  };

  // S1: L1 speaking two-syllable node 0, completed 3 bintang: 10 percobaan, 7 benar, 1 error STT.
  addAttempts(
    S.s1,
    L1,
    DAY1,
    [1000, 1200, 1400, 1600, 1800, 2000, 2200, 2400, 2600, 2800].map((ms, i) => ({
      correct: i < 7,
      responseMs: ms,
      sttError: i === 9 ? 'no_match' : null,
    }))
  );
  // S2: L1 find-object two-syllable node 1, completed 2 bintang (bukan STT).
  addAttempts(S.s2, L1, DAY1, [
    { correct: true, responseMs: 900, gameType: 'find-object' },
    { correct: false, responseMs: 800, gameType: 'find-object' },
  ]);
  // S3: L1 speaking letters node 0, abandoned, hari ke-2: 2 percobaan salah, 1 error STT.
  addAttempts(S.s3, L1, DAY2, [
    { correct: false, responseMs: 3000, sttError: 'network' },
    { correct: false, responseMs: null },
  ]);
  // S4: L2 speaking letters node 0, completed 1 bintang: 4 percobaan, 3 benar.
  addAttempts(S.s4, L2, DAY1, [
    { correct: true, responseMs: 500 },
    { correct: true, responseMs: 700 },
    { correct: true, responseMs: 900 },
    { correct: false, responseMs: 1100 },
  ]);

  const sessionRow = (clientUuid: string, learnerUuid: string, extra: Record<string, unknown>) => ({
    clientUuid,
    learnerUuid,
    materi: 'two-syllable',
    nodeIndex: 0,
    gameType: 'speaking',
    status: 'completed',
    totalItems: 4,
    firstTryCorrect: 3,
    stars: 3,
    startedAt: at(DAY1, 0),
    endedAt: at(DAY1, 30),
    ...extra,
  });

  await t.test('seed dataset through the public sync API', async () => {
    const res = await postJson(
      base,
      '/api/v2/sync',
      {
        learners: [
          { clientUuid: L1, name: 'Ani', school: 'TK Pelita', age: 5, createdAt: at(DAY1, 0), updatedAt: at(DAY1, 0) },
          { clientUuid: L2, name: 'Budi', school: '+TK, "Ceria"', age: 6, createdAt: at(DAY1, 0), updatedAt: at(DAY1, 0) },
        ],
        sessions: [
          sessionRow(S.s1, L1, {}),
          sessionRow(S.s2, L1, { nodeIndex: 1, gameType: 'find-object', stars: 2 }),
          sessionRow(S.s3, L1, { materi: 'letters', status: 'abandoned', stars: 0, firstTryCorrect: 0, startedAt: at(DAY2, 0), endedAt: at(DAY2, 5) }),
          sessionRow(S.s4, L2, { materi: 'letters', stars: 1 }),
          sessionRow(S.s5, L2, { materi: 'letters', nodeIndex: 3, gameType: 'matching', status: 'started', stars: 0, firstTryCorrect: 0, endedAt: null }),
        ],
        attempts,
      },
      deviceAuth
    );
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.data, { accepted: { learners: 2, sessions: 5, attempts: 18 }, rejected: [] });
  });

  await t.test('data from a pending (unapproved) device is quarantined from metrics and exports', async () => {
    const res = await getJson(base, '/api/v2/research/metrics', researcherAuth);
    assert.equal(res.status, 200);
    assert.equal(res.body.data.deviceFilter, 'approved');
    assert.deepEqual(res.body.data.devices, { approved: 0, pending: 1, revoked: 0 });
    assert.equal(res.body.data.overall.sttAttempts, 0);
    assert.equal(res.body.data.overall.sessionsStarted, 0);
    assert.deepEqual(res.body.data.perLearner, []);

    const csv = await getCsv(`${base}/api/v2/research/export/sessions.csv`, researcherAuth);
    assert.equal(csv.text.slice(1).trimEnd().split('\r\n').length, 1, 'header only');

    // `devices=all` menampilkan perangkat pending (untuk ditinjau sebelum disetujui).
    const all = await getJson(base, '/api/v2/research/metrics?devices=all', researcherAuth);
    assert.equal(all.body.data.deviceFilter, 'all');
    assert.equal(all.body.data.overall.sttAttempts, 16);
  });

  await t.test('researcher lists and approves the device (no deviceUuid exposed)', async () => {
    const list = await getJson(base, '/api/v2/research/devices', researcherAuth);
    assert.equal(list.status, 200);
    assert.equal(list.body.count, 1);
    const dev = list.body.data[0];
    assert.equal(dev.deviceId, deviceId);
    assert.equal(dev.status, 'pending');
    assert.deepEqual([dev.learners, dev.sessions, dev.attempts], [2, 5, 18]);
    assert.ok(!JSON.stringify(list.body).includes(deviceUuid), 'deviceUuid (device credential) is never listed');

    const byTeacher = await postJson(base, `/api/v2/research/devices/${deviceId}/approve`, {}, bearer(teacher.token));
    assert.equal(byTeacher.status, 403);
    assert.equal((await postJson(base, `/api/v2/research/devices/${randomUUID()}/approve`, {}, researcherAuth)).status, 404);
    assert.equal((await postJson(base, '/api/v2/research/devices/not-a-uuid/approve', {}, researcherAuth)).status, 400);
    const approve = await postJson(base, `/api/v2/research/devices/${deviceId}/approve`, { label: 'Tablet TK Pelita' }, researcherAuth);
    assert.equal(approve.status, 200);
    assert.deepEqual(approve.body.data, { deviceId, status: 'approved' });
  });

  await t.test('overall metrics follow the thesis formulas', async () => {
    const res = await getJson(base, '/api/v2/research/metrics', researcherAuth);
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.data.devices, { approved: 1, pending: 0, revoked: 0 });
    assert.deepEqual(res.body.data.overall, {
      sttAttempts: 16,
      sttCorrect: 10,
      sttAccuracy: 62.5,
      sttErrors: 2,
      errorRate: 40,
      errorRatePerAttempt: 12.5,
      avgResponseMs: 1680,
      sessionsStarted: 5,
      sessionsCompleted: 3,
      taskCompletion: 60,
      totalStars: 6,
    });
    assert.deepEqual(res.body.data.targets, {
      sttAccuracyMinPercent: 70,
      taskCompletionMinPercent: 75,
      responseTimeMaxMs: 3000,
      errorRateMaxPercent: 10,
    });
  });

  await t.test('per-learner, per-materi and per-game breakdowns', async () => {
    const { data } = (await getJson(base, '/api/v2/research/metrics', researcherAuth)).body;

    const ani = data.perLearner.find((l: { learnerUuid: string }) => l.learnerUuid === L1);
    assert.deepEqual(ani, {
      learnerUuid: L1,
      name: 'Ani',
      school: 'TK Pelita',
      age: 5,
      sttAttempts: 12,
      sttCorrect: 7,
      sttAccuracy: 58.33,
      sttErrors: 2,
      errorRate: 66.67,
      errorRatePerAttempt: 16.67,
      avgResponseMs: 2000,
      sessionsStarted: 3,
      sessionsCompleted: 2,
      taskCompletion: 66.67,
      totalStars: 5,
    });
    const budi = data.perLearner.find((l: { learnerUuid: string }) => l.learnerUuid === L2);
    assert.equal(budi.sttAccuracy, 75);
    assert.equal(budi.avgResponseMs, 800);
    assert.equal(budi.errorRate, 0);
    assert.equal(budi.taskCompletion, 50);
    assert.equal(budi.totalStars, 1);

    assert.deepEqual(
      data.perMateri.map((m: { materi: string }) => m.materi),
      ['letters', 'two-syllable', 'three-syllable', 'multiple']
    );
    const two = data.perMateri.find((m: { materi: string }) => m.materi === 'two-syllable');
    assert.deepEqual(
      [two.sttAttempts, two.sttCorrect, two.sttAccuracy, two.sttErrors, two.errorRate, two.avgResponseMs, two.taskCompletion, two.totalStars],
      [10, 7, 70, 1, 50, 1900, 100, 5]
    );
    const letters = data.perMateri.find((m: { materi: string }) => m.materi === 'letters');
    assert.deepEqual(
      [letters.sttAttempts, letters.sttAccuracy, letters.sessionsStarted, letters.taskCompletion, letters.errorRate, letters.avgResponseMs],
      [6, 50, 3, 33.33, 33.33, 1240]
    );
    const three = data.perMateri.find((m: { materi: string }) => m.materi === 'three-syllable');
    assert.deepEqual(three, {
      materi: 'three-syllable',
      sttAttempts: 0,
      sttCorrect: 0,
      sttAccuracy: null,
      sttErrors: 0,
      errorRate: null,
      errorRatePerAttempt: null,
      avgResponseMs: null,
      sessionsStarted: 0,
      sessionsCompleted: 0,
      taskCompletion: null,
      totalStars: 0,
    });

    assert.equal(data.perGame.length, 6);
    const speaking = data.perGame.find((g: { gameType: string }) => g.gameType === 'speaking');
    assert.deepEqual(
      [speaking.sttAttempts, speaking.sttCorrect, speaking.sessionsStarted, speaking.taskCompletion, speaking.errorRate, speaking.totalStars],
      [16, 10, 3, 66.67, 66.67, 4]
    );
    const find = data.perGame.find((g: { gameType: string }) => g.gameType === 'find-object');
    assert.deepEqual([find.sttAttempts, find.sttAccuracy, find.taskCompletion, find.totalStars], [0, null, 100, 2]);
    const matching = data.perGame.find((g: { gameType: string }) => g.gameType === 'matching');
    assert.deepEqual([matching.sessionsStarted, matching.taskCompletion], [1, 0]);

    // Semua angka adalah JSON number (bukan string bigint/numeric dari pg).
    for (const value of Object.values(data.overall)) {
      assert.ok(value === null || typeof value === 'number', `overall value ${String(value)} must be a number`);
    }
  });

  await t.test('filters: learnerUuid and date range', async () => {
    const onlyBudi = await getJson(base, `/api/v2/research/metrics?learnerUuid=${L2}`, researcherAuth);
    assert.equal(onlyBudi.body.data.overall.sttAttempts, 4);
    assert.equal(onlyBudi.body.data.perLearner.length, 1);

    const day1 = await getJson(base, `/api/v2/research/metrics?from=${DAY1}&to=${DAY1}`, researcherAuth);
    assert.deepEqual(
      [
        day1.body.data.overall.sttAttempts,
        day1.body.data.overall.sttAccuracy,
        day1.body.data.overall.sessionsStarted,
        day1.body.data.overall.taskCompletion,
        day1.body.data.overall.errorRate,
      ],
      [14, 71.43, 4, 75, 25]
    );

    const bad = await getJson(base, '/api/v2/research/metrics?from=kemarin', researcherAuth);
    assert.equal(bad.status, 400);

    // Parameter kosong dari form/dasbor = tanpa filter.
    const blank = await getJson(base, '/api/v2/research/metrics?learnerUuid=&from=&to=', researcherAuth);
    assert.equal(blank.status, 200);
    assert.equal(blank.body.data.overall.sttAttempts, 16);
    const blankCsv = await getCsv(`${base}/api/v2/research/export/attempts.csv?learnerUuid=&from=&to=`, researcherAuth);
    assert.equal(blankCsv.status, 200);
  });

  await t.test('attempts.csv: BOM, header, escaping and formula guard', async () => {
    const res = await getCsv(`${base}/api/v2/research/export/attempts.csv`, researcherAuth);
    assert.equal(res.status, 200);
    assert.deepEqual(Array.from(res.bytes.slice(0, 3)), [0xef, 0xbb, 0xbf], 'UTF-8 BOM bytes');
    assert.match(res.headers.get('content-type') ?? '', /^text\/csv/);
    assert.match(res.headers.get('content-disposition') ?? '', /^attachment; filename="kogo-attempts-.*\.csv"$/);
    assert.equal(res.text.charCodeAt(0), 0xfeff, 'UTF-8 BOM for Excel');
    const lines = res.text.slice(1).trimEnd().split('\r\n');
    assert.equal(
      lines[0],
      'attempt_uuid,session_uuid,learner_uuid,learner_name,school,age,device_id,device_label,materi,node_index,game_type,target_text,answer_text,is_correct,attempt_number,similarity,response_ms,stt_error,created_at,synced_at'
    );
    assert.equal(lines.length, 1 + 18);
    assert.ok(res.text.includes(`"'+TK, ""Ceria"""`), 'school is quoted and formula-guarded');
    assert.ok(!res.text.includes(deviceUuid), 'deviceUuid (device credential) is never exported');
    assert.ok(lines[1].includes(`,${deviceId},Tablet TK Pelita,`), lines[1]);
  });

  await t.test('exports stream in keyset batches with identical output', async () => {
    const full = await getCsv(`${base}/api/v2/research/export/attempts.csv`, researcherAuth);
    for (const batch of [1, 5, 18, 1000]) {
      let streamed = '';
      let rows = 0;
      for await (const chunk of new MetricsService(pool, batch).exportAttemptsCsv({ devices: 'approved' })) {
        streamed += chunk.chunk;
        rows += chunk.rows;
      }
      assert.equal(rows, 18, `batch ${batch}`);
      assert.equal(streamed, full.text, `batch ${batch} output matches`);
    }
    let sessions = '';
    for await (const chunk of new MetricsService(pool, 2).exportSessionsCsv({ devices: 'approved' })) sessions += chunk.chunk;
    const sessionsFull = await getCsv(`${base}/api/v2/research/export/sessions.csv`, researcherAuth);
    assert.equal(sessions, sessionsFull.text);
  });

  await t.test('sessions.csv with learner filter', async () => {
    const res = await getCsv(`${base}/api/v2/research/export/sessions.csv?learnerUuid=${L1}`, researcherAuth);
    assert.equal(res.status, 200);
    const lines = res.text.slice(1).trimEnd().split('\r\n');
    assert.equal(
      lines[0],
      'session_uuid,learner_uuid,learner_name,school,age,device_id,device_label,materi,node_index,game_type,status,total_items,first_try_correct,stars,started_at,ended_at,duration_seconds,synced_at'
    );
    assert.equal(lines.length, 1 + 3);
    const s1 = lines.find((l) => l.startsWith(S.s1));
    assert.ok(s1?.includes(',completed,4,3,3,'), s1);
    assert.ok(s1?.includes(',1800,'), 'duration_seconds = 30 minutes');
  });

  await t.test('exports and metrics are audited and protected (401/403)', async () => {
    const audit = await pool.query<{ action: string }>('SELECT DISTINCT action FROM audit_logs ORDER BY action');
    const actions = audit.rows.map((r) => r.action);
    for (const action of ['APPROVE_DEVICE', 'EXPORT_ATTEMPTS_CSV', 'EXPORT_SESSIONS_CSV', 'LIST_DEVICES', 'VIEW_RESEARCH_METRICS']) {
      assert.ok(actions.includes(action), action);
    }
    const exportAudit = await pool.query<{ metadata: { rows: number; completed: boolean } }>(
      "SELECT metadata FROM audit_logs WHERE action = 'EXPORT_ATTEMPTS_CSV' ORDER BY created_at DESC LIMIT 1"
    );
    assert.equal(exportAudit.rows[0].metadata.completed, true);
    for (const path of [
      '/api/v2/research/export/attempts.csv',
      '/api/v2/research/export/sessions.csv',
      '/api/v2/research/metrics',
      '/api/v2/research/devices',
    ]) {
      assert.equal((await getJson(base, path)).status, 401);
      assert.equal((await getJson(base, path, deviceAuth)).status, 401);
      assert.equal((await getJson(base, path, bearer(deviceToken()))).status, 401);
      assert.equal((await getJson(base, path, bearer(teacher.token))).status, 403);
      assert.equal((await getJson(base, path, bearer(child.token))).status, 403);
      assert.equal((await getJson(base, path, bearer(admin.token))).status, 200);
    }
  });

  await t.test('account changes take effect immediately (no token grace period)', async () => {
    const peneliti = await createUserWithToken(pool, 'researcher', 'peneliti_x');
    const auth = bearer(peneliti.token);
    assert.equal((await getJson(base, '/api/v2/research/export/attempts.csv', auth)).status, 200);
    await pool.query("UPDATE users SET role = 'child' WHERE id = $1", [peneliti.id]);
    assert.equal((await getJson(base, '/api/v2/research/export/attempts.csv', auth)).status, 403);
    await pool.query("UPDATE users SET role = 'researcher', is_active = false WHERE id = $1", [peneliti.id]);
    const disabled = await getJson(base, '/api/v2/research/export/attempts.csv', auth);
    assert.equal(disabled.status, 401);
    assert.equal(disabled.body.code, 'ACCOUNT_DISABLED');
  });

  await t.test('revoking a device blocks its tokens and removes its data from metrics', async () => {
    const revoke = await postJson(base, `/api/v2/research/devices/${deviceId}/revoke`, {}, researcherAuth);
    assert.deepEqual(revoke.body.data, { deviceId, status: 'revoked' });

    const metrics = await getJson(base, '/api/v2/research/metrics?devices=all', researcherAuth);
    assert.equal(metrics.body.data.overall.sttAttempts, 0, 'revoked devices are excluded even with devices=all');
    assert.deepEqual(metrics.body.data.devices, { approved: 0, pending: 0, revoked: 1 });

    const sync = await postJson(base, '/api/v2/sync', {}, deviceAuth);
    assert.equal(sync.status, 403);
    assert.equal(sync.body.code, 'DEVICE_REVOKED');
    const tts = await postJson(base, '/api/voice/tts', { text: 'Halo' }, deviceAuth);
    assert.equal(tts.status, 403);
    assert.equal(tts.body.code, 'DEVICE_REVOKED');
    const reRegister = await postJson(
      base,
      '/api/v2/devices/register',
      { deviceUuid, platform: 'android', appVersion: '2.0.0', deviceSecret: reg.body.data.deviceSecret },
      deviceAuth
    );
    assert.equal(reRegister.status, 403);
    assert.equal(reRegister.body.code, 'DEVICE_REVOKED');

    // Persetujuan ulang memulihkan perangkat.
    assert.equal((await postJson(base, `/api/v2/research/devices/${deviceId}/approve`, {}, researcherAuth)).status, 200);
    assert.equal((await postJson(base, '/api/v2/sync', {}, deviceAuth)).status, 200);
  });

  await t.test('reset-credential lets a device that lost its secret claim a new one exactly once', async () => {
    const lost = await postJson(base, '/api/v2/devices/register', { deviceUuid, platform: 'android', appVersion: '2.0.0' });
    assert.equal(lost.status, 409);
    assert.equal(lost.body.code, 'DEVICE_PROOF_REQUIRED');

    assert.equal((await postJson(base, `/api/v2/research/devices/${deviceId}/reset-credential`, {}, researcherAuth)).status, 200);
    const claim = await postJson(base, '/api/v2/devices/register', { deviceUuid, platform: 'android', appVersion: '2.0.0' });
    assert.equal(claim.status, 200);
    assert.match(claim.body.data.deviceSecret, /^[A-Za-z0-9_-]{43}$/);
    assert.equal(claim.body.data.approved, true);
    const again = await postJson(base, '/api/v2/devices/register', { deviceUuid, platform: 'android', appVersion: '2.0.0' });
    assert.equal(again.status, 409, 'the claim works only once');
    const withNewSecret = await postJson(base, '/api/v2/devices/register', {
      deviceUuid,
      platform: 'android',
      appVersion: '2.0.0',
      deviceSecret: claim.body.data.deviceSecret,
    });
    assert.equal(withNewSecret.status, 200);
  });
});
