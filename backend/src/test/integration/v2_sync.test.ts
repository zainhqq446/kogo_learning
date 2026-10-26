import '../helpers/test_env.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import jwt from 'jsonwebtoken';
import { createApp } from '../../app.js';
import { setDbPool } from '../../config/database.js';
import { createTestPool, prepareTestDatabase } from '../helpers/db.js';
import { bearer, deviceToken, noRateLimits, postJson, startServer, TestServer, userToken } from '../helpers/http.js';

const T0 = '2026-10-20T01:00:00.000Z';
const T1 = '2026-10-20T01:05:00.000Z';
const T2 = '2026-10-20T02:00:00.000Z';

function learner(clientUuid: string, overrides: Record<string, unknown> = {}) {
  return { clientUuid, name: 'Ani', school: 'TK Pelita', age: 5, createdAt: T0, updatedAt: T0, ...overrides };
}

function session(clientUuid: string, learnerUuid: string, overrides: Record<string, unknown> = {}) {
  return {
    clientUuid,
    learnerUuid,
    materi: 'two-syllable',
    nodeIndex: 0,
    gameType: 'speaking',
    status: 'completed',
    totalItems: 4,
    firstTryCorrect: 4,
    stars: 3,
    startedAt: T0,
    endedAt: T1,
    ...overrides,
  };
}

function attempt(clientUuid: string, sessionUuid: string, learnerUuid: string, overrides: Record<string, unknown> = {}) {
  return {
    clientUuid,
    sessionUuid,
    learnerUuid,
    gameType: 'speaking',
    targetText: 'bola',
    answerText: 'bola',
    isCorrect: true,
    attemptNumber: 1,
    similarity: 1,
    responseMs: 1500,
    sttError: null,
    createdAt: T1,
    ...overrides,
  };
}

async function count(pool: import('pg').Pool, table: string): Promise<number> {
  const res = await pool.query<{ n: number }>(`SELECT COUNT(*)::int AS n FROM ${table}`);
  return res.rows[0].n;
}

test('API v2 device registration and sync (real PostgreSQL)', async (t) => {
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

  const deviceUuidA = randomUUID();
  const deviceUuidB = randomUUID();
  let tokenA = '';
  let tokenB = '';
  let deviceIdA = '';
  let secretA = '';

  const L1 = randomUUID();
  const S1 = randomUUID();
  const S2 = randomUUID();
  const A1 = randomUUID();
  const A2 = randomUUID();
  const A3 = randomUUID();
  const A4 = randomUUID();

  const syncA = (body: unknown) => postJson(base, '/api/v2/sync', body, bearer(tokenA));
  const syncB = (body: unknown) => postJson(base, '/api/v2/sync', body, bearer(tokenB));

  await t.test('register new device -> 201 with token + one-time deviceSecret; device starts pending', async () => {
    const first = await postJson(base, '/api/v2/devices/register', {
      deviceUuid: deviceUuidA,
      platform: 'android',
      appVersion: '2.0.0+1',
      model: 'Samsung Tab A',
    });
    assert.equal(first.status, 201);
    assert.equal(first.body.status, 'success');
    assert.equal(first.body.data.expiresIn, 180 * 86400);
    assert.equal(first.body.data.approved, false, 'without DEVICE_ENROLLMENT_KEY new devices are pending');
    assert.match(first.body.data.deviceSecret, /^[A-Za-z0-9_-]{43}$/);
    secretA = first.body.data.deviceSecret;
    tokenA = first.body.data.deviceToken;
    const decoded = jwt.decode(tokenA) as jwt.JwtPayload;
    assert.equal(decoded.role, 'device');
    assert.equal(decoded.tokenType, 'device');
    deviceIdA = decoded.deviceId;
    assert.equal(decoded.sub, deviceIdA, 'sub is the internal id, never the deviceUuid');
    assert.ok(!tokenA.includes(deviceUuidA) && !JSON.stringify(decoded).includes(deviceUuidA));

    const row = await pool.query('SELECT secret_hash, approved_at FROM app_devices WHERE id = $1', [deviceIdA]);
    assert.equal(row.rows[0].approved_at, null);
    assert.equal(row.rows[0].secret_hash.length, 64);
    assert.notEqual(row.rows[0].secret_hash, secretA, 'only a hash of the secret is stored');
  });

  await t.test('re-registering a known deviceUuid needs proof of possession', async () => {
    // deviceUuid saja (mis. bocor) tidak cukup: 409 dan data perangkat tidak berubah.
    const hijack = await postJson(base, '/api/v2/devices/register', { deviceUuid: deviceUuidA, platform: 'android', appVersion: 'evil' });
    assert.equal(hijack.status, 409);
    assert.equal(hijack.body.code, 'DEVICE_PROOF_REQUIRED');
    let row = await pool.query('SELECT app_version, model FROM app_devices WHERE device_uuid = $1', [deviceUuidA]);
    assert.deepEqual(row.rows[0], { app_version: '2.0.0+1', model: 'Samsung Tab A' });

    const wrongSecret = await postJson(base, '/api/v2/devices/register', {
      deviceUuid: deviceUuidA,
      platform: 'android',
      appVersion: 'evil',
      deviceSecret: 'A'.repeat(43),
    });
    assert.equal(wrongSecret.status, 409);

    // Rahasia yang benar -> 200, deviceId sama, tidak ada rahasia baru.
    const withSecret = await postJson(base, '/api/v2/devices/register', {
      deviceUuid: deviceUuidA.toUpperCase(),
      platform: 'android',
      appVersion: '2.0.1',
      deviceSecret: secretA,
    });
    assert.equal(withSecret.status, 200);
    assert.equal(withSecret.body.data.deviceSecret, undefined);
    assert.equal((jwt.decode(withSecret.body.data.deviceToken) as jwt.JwtPayload).deviceId, deviceIdA);
    row = await pool.query('SELECT app_version, model FROM app_devices WHERE device_uuid = $1', [deviceUuidA]);
    assert.deepEqual(row.rows[0], { app_version: '2.0.1', model: 'Samsung Tab A' });

    // Device token yang masih berlaku juga merupakan bukti (refresh sebelum kedaluwarsa).
    const withToken = await postJson(
      base,
      '/api/v2/devices/register',
      { deviceUuid: deviceUuidA, platform: 'android', appVersion: '2.0.2' },
      bearer(tokenA)
    );
    assert.equal(withToken.status, 200);
    tokenA = withToken.body.data.deviceToken;
    assert.equal(await count(pool, 'app_devices'), 1);

    const b = await postJson(base, '/api/v2/devices/register', { deviceUuid: deviceUuidB, platform: 'android', appVersion: '2.0.0' });
    assert.equal(b.status, 201);
    tokenB = b.body.data.deviceToken;
    // Token perangkat B bukan bukti untuk perangkat A.
    const crossToken = await postJson(
      base,
      '/api/v2/devices/register',
      { deviceUuid: deviceUuidA, platform: 'android', appVersion: 'evil' },
      bearer(tokenB)
    );
    assert.equal(crossToken.status, 409);

    const invalid = await postJson(base, '/api/v2/devices/register', { deviceUuid: 'abc', platform: 'android', appVersion: '1' });
    assert.equal(invalid.status, 400);
    const nul = await postJson(base, '/api/v2/devices/register', { deviceUuid: randomUUID(), platform: 'android', appVersion: 'a\u0000b' });
    assert.equal(nul.status, 400, 'NUL bytes are a client error, not a 500');
  });

  const happyPayload = () => ({
    learners: [learner(L1)],
    sessions: [
      session(S1, L1),
      session(S2, L1, { nodeIndex: 1, gameType: 'find-object', status: 'started', firstTryCorrect: 0, stars: 0, endedAt: null }),
    ],
    attempts: [
      attempt(A1, S1, L1),
      attempt(A2, S1, L1, { targetText: 'buku', answerText: 'bukan', isCorrect: false, similarity: 0.6, sttError: null }),
      attempt(A3, S1, L1, { attemptNumber: 2, sttError: 'no_match', isCorrect: false, answerText: '', similarity: null }),
      attempt(A4, S2, L1, { gameType: 'find-object', responseMs: null, similarity: null }),
    ],
  });

  await t.test('sync happy path stores learners, sessions, attempts and stars', async () => {
    const res = await syncA(happyPayload());
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.data, { accepted: { learners: 1, sessions: 2, attempts: 4 }, rejected: [] });

    assert.equal(await count(pool, 'learners'), 1);
    assert.equal(await count(pool, 'game_sessions'), 2);
    assert.equal(await count(pool, 'answer_attempts'), 4);
    const stars = await pool.query('SELECT materi_code, node_index, stars FROM stars');
    assert.deepEqual(stars.rows, [{ materi_code: 'two-syllable', node_index: 0, stars: 3 }]);
    const a3 = await pool.query('SELECT stt_error, similarity FROM answer_attempts WHERE client_uuid = $1', [A3]);
    assert.deepEqual(a3.rows[0], { stt_error: 'no_match', similarity: null });
    const lastSeen = await pool.query('SELECT last_seen_at > created_at AS touched FROM app_devices WHERE id = $1', [deviceIdA]);
    assert.equal(lastSeen.rows[0].touched, true);
  });

  await t.test('resending the same payload is idempotent (no duplicates)', async () => {
    const res = await syncA(happyPayload());
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.data, { accepted: { learners: 1, sessions: 2, attempts: 4 }, rejected: [] });
    assert.equal(await count(pool, 'learners'), 1);
    assert.equal(await count(pool, 'game_sessions'), 2);
    assert.equal(await count(pool, 'answer_attempts'), 4);
    assert.equal(await count(pool, 'stars'), 1);
  });

  await t.test('completed sessions are never downgraded; started sessions can complete', async () => {
    const res = await syncA({
      sessions: [
        session(S1, L1, { status: 'started', totalItems: 0, firstTryCorrect: 0, stars: 0, endedAt: null }),
        session(S2, L1, { nodeIndex: 1, gameType: 'find-object', status: 'completed', firstTryCorrect: 2, stars: 2, endedAt: T2 }),
      ],
    });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.data.accepted, { learners: 0, sessions: 2, attempts: 0 });

    const s1 = await pool.query('SELECT status, total_items, stars, ended_at FROM game_sessions WHERE client_uuid = $1', [S1]);
    assert.equal(s1.rows[0].status, 'completed');
    assert.equal(s1.rows[0].total_items, 4);
    assert.equal(s1.rows[0].stars, 3);
    assert.equal(new Date(s1.rows[0].ended_at).toISOString(), T1);

    const s2 = await pool.query('SELECT status, stars FROM game_sessions WHERE client_uuid = $1', [S2]);
    assert.deepEqual(s2.rows[0], { status: 'completed', stars: 2 });

    const abandonAfterComplete = await syncA({
      sessions: [session(S2, L1, { nodeIndex: 1, gameType: 'find-object', status: 'abandoned', firstTryCorrect: 0, stars: 0 })],
    });
    assert.equal(abandonAfterComplete.status, 200);
    const still = await pool.query('SELECT status, stars FROM game_sessions WHERE client_uuid = $1', [S2]);
    assert.deepEqual(still.rows[0], { status: 'completed', stars: 2 });

    // Hasil sesi completed bersifat final: kirim ulang completed dengan nilai lebih rendah tidak menimpa.
    const lowerResend = await syncA({
      sessions: [session(S1, L1, { totalItems: 2, firstTryCorrect: 1, stars: 1, endedAt: T2 })],
    });
    assert.equal(lowerResend.body.data.accepted.sessions, 1);
    const frozen = await pool.query('SELECT total_items, first_try_correct, stars, ended_at FROM game_sessions WHERE client_uuid = $1', [S1]);
    assert.deepEqual(
      { ...frozen.rows[0], ended_at: new Date(frozen.rows[0].ended_at).toISOString() },
      { total_items: 4, first_try_correct: 4, stars: 3, ended_at: T1 }
    );
    const best = await pool.query(
      "SELECT s.stars FROM stars s JOIN learners l ON l.id = s.learner_id WHERE l.client_uuid = $1 AND s.materi_code = 'two-syllable' AND s.node_index = 0",
      [L1]
    );
    assert.equal(best.rows[0].stars, 3, 'stars table and game_sessions agree');
  });

  await t.test('learner updates from the owning device are always applied (device clock independent)', async () => {
    const newer = await syncA({ learners: [learner(L1, { name: 'Ani Putri', age: 6, updatedAt: T2 })] });
    assert.equal(newer.status, 200);
    let row = await pool.query('SELECT name, age FROM learners WHERE client_uuid = $1', [L1]);
    assert.deepEqual(row.rows[0], { name: 'Ani Putri', age: 6 });

    // Jam perangkat mundur (timestamp lebih lama): koreksi tetap diterapkan, tidak "accepted" diam-diam.
    const olderClock = await syncA({ learners: [learner(L1, { name: 'Ani Putri', school: 'TK B', age: 6, updatedAt: '2026-10-19T00:00:00.000Z' })] });
    assert.deepEqual(olderClock.body.data.accepted.learners, 1);
    row = await pool.query('SELECT name, school, age FROM learners WHERE client_uuid = $1', [L1]);
    assert.deepEqual(row.rows[0], { name: 'Ani Putri', school: 'TK B', age: 6 });

    // Timestamp jauh di masa depan ditolak per item (tidak bisa "mengunci" data).
    const future = await syncA({ learners: [learner(L1, { name: 'Masa Depan', updatedAt: '2099-01-01T00:00:00.000Z' })] });
    assert.equal(future.status, 200);
    assert.deepEqual(future.body.data.accepted.learners, 0);
    assert.equal(future.body.data.rejected[0].code, 'INVALID');
    assert.match(future.body.data.rejected[0].detail, /future/);
    row = await pool.query('SELECT name FROM learners WHERE client_uuid = $1', [L1]);
    assert.equal(row.rows[0].name, 'Ani Putri');
  });

  await t.test("another device can never overwrite or attach to device A's data (FOREIGN_DEVICE)", async () => {
    const res = await syncB({
      learners: [learner(L1, { name: 'Penyusup', updatedAt: T2 })],
      sessions: [session(S1, L1, { stars: 0 })],
      attempts: [attempt(A1, S1, L1, { answerText: 'hack' }), attempt(randomUUID(), S1, L1)],
    });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.data.accepted, { learners: 0, sessions: 0, attempts: 0 });
    assert.equal(res.body.data.rejected.length, 4);
    for (const r of res.body.data.rejected) assert.equal(r.code, 'FOREIGN_DEVICE', JSON.stringify(r));
    assert.deepEqual(
      res.body.data.rejected.map((r: { type: string }) => r.type),
      ['learner', 'session', 'attempt', 'attempt']
    );

    const row = await pool.query('SELECT name FROM learners WHERE client_uuid = $1', [L1]);
    assert.equal(row.rows[0].name, 'Ani Putri');
    const s1 = await pool.query('SELECT stars FROM game_sessions WHERE client_uuid = $1', [S1]);
    assert.equal(s1.rows[0].stars, 3);
    const a1 = await pool.query('SELECT answer_text FROM answer_attempts WHERE client_uuid = $1', [A1]);
    assert.equal(a1.rows[0].answer_text, 'bola');
    assert.equal(await count(pool, 'answer_attempts'), 4);
  });

  await t.test('unknown references and invalid items are rejected per item; the rest is accepted', async () => {
    const L2 = randomUUID();
    const S3 = randomUUID();
    const badLearner = randomUUID();
    const res = await syncA({
      learners: [learner(L2, { name: 'Budi', age: 6 }), learner(badLearner, { age: 7 }), 'not-an-object'],
      sessions: [
        session(S3, L2, { materi: 'letters', nodeIndex: 2 }),
        session(randomUUID(), randomUUID()),
        session(randomUUID(), L2, { totalItems: 2, firstTryCorrect: 3 }),
      ],
      attempts: [
        attempt(randomUUID(), S3, L2),
        attempt(randomUUID(), randomUUID(), L2),
        attempt(randomUUID(), S3, L1),
        attempt(randomUUID(), S3, L2, { similarity: 5 }),
      ],
    });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.data.accepted, { learners: 1, sessions: 1, attempts: 1 });

    const codes = res.body.data.rejected.map((r: { type: string; code: string; clientUuid: string | null }) => `${r.type}:${r.code}`).sort();
    assert.deepEqual(codes, [
      'attempt:INVALID',
      'attempt:INVALID',
      'attempt:UNKNOWN_SESSION',
      'learner:INVALID',
      'learner:INVALID',
      'session:INVALID',
      'session:UNKNOWN_LEARNER',
    ]);
    const invalidLearner = res.body.data.rejected.find((r: { clientUuid: string }) => r.clientUuid === badLearner);
    assert.equal(invalidLearner.code, 'INVALID');
    assert.match(invalidLearner.detail, /age/);
    assert.ok(res.body.data.rejected.some((r: { clientUuid: string | null }) => r.clientUuid === null));
  });

  await t.test('uppercase UUIDs are accepted and normalised', async () => {
    const L3 = randomUUID();
    const res = await syncA({ learners: [learner(L3.toUpperCase(), { name: 'Citra' })] });
    assert.deepEqual(res.body.data.accepted.learners, 1);
    const again = await syncA({ learners: [learner(L3, { name: 'Citra', updatedAt: T1 })] });
    assert.deepEqual(again.body.data.accepted.learners, 1);
    const n = await pool.query('SELECT COUNT(*)::int AS n FROM learners WHERE client_uuid = $1', [L3]);
    assert.equal(n.rows[0].n, 1);
  });

  await t.test('stars keep the best score per node and rewards unlock at 10 / 50 stars', async () => {
    const L4 = randomUUID();
    const nodes = (from: number, to: number, stars: number) =>
      Array.from({ length: to - from }, (_, i) =>
        session(randomUUID(), L4, { materi: 'three-syllable', nodeIndex: from + i, stars, firstTryCorrect: 4 })
      );

    // 4 node x 3 bintang = 12 -> Perunggu (10)
    let res = await syncA({ learners: [learner(L4, { name: 'Dodi' })], sessions: nodes(0, 4, 3) });
    assert.deepEqual(res.body.data.accepted, { learners: 1, sessions: 4, attempts: 0 });
    let rewards = await pool.query(
      'SELECT r.tier_code, r.earned_at FROM rewards r JOIN learners l ON l.id = r.learner_id WHERE l.client_uuid = $1 ORDER BY r.tier_code',
      [L4]
    );
    assert.deepEqual(rewards.rows.map((r) => r.tier_code), ['perunggu']);
    const bronzeEarnedAt = new Date(rewards.rows[0].earned_at).toISOString();

    // Skor lebih rendah pada node yang sama tidak menurunkan bintang terbaik.
    res = await syncA({ sessions: [session(randomUUID(), L4, { materi: 'three-syllable', nodeIndex: 0, stars: 1, firstTryCorrect: 1 })] });
    assert.equal(res.body.data.accepted.sessions, 1);
    const best = await pool.query(
      `SELECT s.stars FROM stars s JOIN learners l ON l.id = s.learner_id
       WHERE l.client_uuid = $1 AND s.materi_code = 'three-syllable' AND s.node_index = 0`,
      [L4]
    );
    assert.equal(best.rows[0].stars, 3);

    // Sesi started/abandoned tidak menambah bintang.
    await syncA({ sessions: [session(randomUUID(), L4, { materi: 'multiple', nodeIndex: 0, status: 'abandoned', stars: 3 })] });

    // +13 node x 3 = 39 -> total 51 -> Perak (50)
    res = await syncA({ sessions: nodes(4, 17, 3) });
    assert.equal(res.body.data.accepted.sessions, 13);
    const total = await pool.query(
      'SELECT SUM(s.stars)::int AS total FROM stars s JOIN learners l ON l.id = s.learner_id WHERE l.client_uuid = $1',
      [L4]
    );
    assert.equal(total.rows[0].total, 51);
    rewards = await pool.query(
      'SELECT r.tier_code, r.earned_at FROM rewards r JOIN learners l ON l.id = r.learner_id WHERE l.client_uuid = $1 ORDER BY r.tier_code',
      [L4]
    );
    assert.deepEqual(rewards.rows.map((r) => r.tier_code), ['perak', 'perunggu']);
    const bronzeAfter = rewards.rows.find((r) => r.tier_code === 'perunggu');
    assert.equal(new Date(bronzeAfter.earned_at).toISOString(), bronzeEarnedAt, 'earned_at keeps the first time');
  });

  await t.test('duplicate clientUuids in one payload are counted once; bad duplicates are not hidden', async () => {
    const L5 = randomUUID();
    const S5 = randomUUID();
    const X = randomUUID();
    const res = await syncA({
      learners: [learner(L5, { name: 'Eka' }), learner(L5, { name: 'Eka' })],
      sessions: [session(S5, L5), session(S5, L5)],
      attempts: [attempt(X, S5, L5), attempt(X, randomUUID(), L5), attempt(X, S5, L5)],
    });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.data.accepted, { learners: 1, sessions: 1, attempts: 1 });
    assert.deepEqual(
      res.body.data.rejected.map((r: { type: string; code: string }) => `${r.type}:${r.code}`),
      ['attempt:UNKNOWN_SESSION'],
      'a duplicate pointing at an unknown session is rejected, not counted as accepted'
    );
    const n = await pool.query('SELECT COUNT(*)::int AS n FROM answer_attempts WHERE client_uuid = $1', [X]);
    assert.equal(n.rows[0].n, 1);
  });

  await t.test('NUL characters are rejected per item instead of rolling back the whole batch', async () => {
    const good = randomUUID();
    const bad = randomUUID();
    const res = await syncA({ learners: [learner(good, { name: 'Good Kid' }), learner(bad, { name: 'Bad\u0000Kid' })] });
    assert.equal(res.status, 200);
    assert.deepEqual(res.body.data.accepted.learners, 1);
    assert.deepEqual(res.body.data.rejected, [
      { type: 'learner', clientUuid: bad, code: 'INVALID', detail: 'name: must not contain NUL (U+0000) characters' },
    ]);
    const stored = await pool.query('SELECT client_uuid FROM learners WHERE client_uuid = ANY($1::uuid[])', [[good, bad]]);
    assert.deepEqual(stored.rows.map((r) => r.client_uuid), [good]);
  });

  await t.test('request-level limits and auth', async () => {
    const tooMany = await syncA({ learners: Array.from({ length: 51 }, () => learner(randomUUID())) });
    assert.equal(tooMany.status, 400);
    assert.equal(tooMany.body.code, 'VALIDATION_ERROR');

    assert.equal((await postJson(base, '/api/v2/sync', {})).status, 401);
    assert.equal((await postJson(base, '/api/v2/sync', {}, bearer(userToken('admin')))).status, 401);

    const ghost = await postJson(base, '/api/v2/sync', {}, bearer(deviceToken(randomUUID())));
    assert.equal(ghost.status, 401);
    assert.equal(ghost.body.code, 'DEVICE_NOT_REGISTERED');
  });

  await t.test('pending devices can sync (data is quarantined until approval)', async () => {
    const row = await pool.query('SELECT approved_at FROM app_devices WHERE id = $1', [deviceIdA]);
    assert.equal(row.rows[0].approved_at, null);
    assert.ok((await count(pool, 'learners')) > 0);
  });
});
