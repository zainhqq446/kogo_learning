import '../helpers/test_env.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createApp } from '../../app.js';
import { setDbPool } from '../../config/database.js';
import { CurriculumService } from '../../services/curriculum_service.js';
import { signAccessToken } from '../../services/token_service.js';
import { createTestPool, createUserWithToken, prepareTestDatabase } from '../helpers/db.js';
import { bearer, getJson, noRateLimits, postJson, startServer, TestServer, userToken } from '../helpers/http.js';

/**
 * Regression suite untuk API riset lama (/api/research/*): tetap berfungsi dan
 * tetap terlindungi setelah perbaikan keamanan.
 */
test('legacy /api/research routes keep working behind auth', async (t) => {
  const pool = await createTestPool();
  await prepareTestDatabase(pool);
  await new CurriculumService(pool).seedCurriculum();
  setDbPool(pool);
  let server: TestServer | undefined;
  t.after(async () => {
    await server?.close();
    await pool.end();
  });
  server = await startServer(createApp({ rateLimiters: noRateLimits() }));
  const base = server.baseUrl;

  const user = await pool.query<{ id: string }>(
    `INSERT INTO users (username, password_hash, full_name, role) VALUES ('legacy_researcher', 'x', 'Peneliti', 'researcher') RETURNING id`
  );
  const auth = bearer(signAccessToken({ userId: user.rows[0].id, username: 'legacy_researcher', role: 'researcher' }));
  const sessionUuid = randomUUID();
  const attemptUuid = randomUUID();
  const now = new Date().toISOString();

  await t.test('participants: create, duplicate (409), list and batch limits', async () => {
    const created = await postJson(base, '/api/research/participants', { participantCode: 'P001', displayAlias: 'Anak A', ageYears: 5, gender: 'M', pin: '1234' }, auth);
    assert.equal(created.status, 201);
    assert.equal(created.body.data.pin_hash, undefined, 'PIN hash is never returned');

    const dup = await postJson(base, '/api/research/participants', { participantCode: 'p001', displayAlias: 'Lagi', pin: '1234' }, auth);
    assert.equal(dup.status, 409);
    assert.equal(dup.body.code, 'PARTICIPANT_EXISTS');

    const list = await getJson(base, '/api/research/participants', auth);
    assert.equal(list.status, 200);
    assert.equal(list.body.count, 1);

    const tooMany = await postJson(
      base,
      '/api/research/participants/batch',
      { participants: Array.from({ length: 201 }, (_, i) => ({ participantCode: `B${i}`, displayAlias: 'x', pin: '1234' })) },
      auth
    );
    assert.equal(tooMany.status, 400);
  });

  await t.test('devices, sessions, attempts and summary', async () => {
    const device = await postJson(base, '/api/research/devices', { deviceIdentifier: 'tablet-kelas-a', platform: 'android', appVersion: '1.0.0' }, auth);
    assert.equal(device.status, 200);

    const sessionBody = {
      clientSessionUuid: sessionUuid,
      participantCode: 'P001',
      deviceIdentifier: 'tablet-kelas-a',
      sessionSequenceNumber: 1,
      startedAt: now,
    };
    const s1 = await postJson(base, '/api/research/sessions', sessionBody, auth);
    const s2 = await postJson(base, '/api/research/sessions', { ...sessionBody, endedAt: now }, auth);
    assert.equal(s1.status, 201);
    assert.equal(s2.body.data.id, s1.body.data.id, 'idempotent by clientSessionUuid');

    const attempt = await postJson(
      base,
      '/api/research/attempts',
      {
        clientAttemptUuid: attemptUuid,
        clientSessionUuid: sessionUuid,
        participantCode: 'P001',
        deviceIdentifier: 'tablet-kelas-a',
        questionId: 1,
        attemptNumber: 1,
        targetText: 'A',
        recognizedText: 'a',
        attemptedAt: now,
        evaluation: {
          normalizedTarget: 'a',
          normalizedRecognized: 'a',
          editDistance: 0,
          similarityScore: 1,
          similarityPercent: 100,
          isCorrect: true,
          evaluationStatus: 'EXACT_MATCH',
        },
      },
      auth
    );
    assert.equal(attempt.status, 201);
    assert.equal(attempt.body.data.evaluation.evaluation_status, 'EXACT_MATCH');

    const summary = await getJson(base, '/api/research/summary', auth);
    assert.equal(summary.status, 200);
    assert.equal(Number(summary.body.data.total_attempts), 1);
    assert.equal(Number(summary.body.data.exact_matches), 1);
  });

  await t.test('pagination query params are validated', async () => {
    assert.equal((await getJson(base, '/api/research/sessions?limit=abc', auth)).status, 400);
    assert.equal((await getJson(base, '/api/research/sessions?limit=100000', auth)).status, 400);
    assert.equal((await getJson(base, '/api/research/attempts?sessionId=not-a-uuid', auth)).status, 400);
    const ok = await getJson(base, '/api/research/sessions?limit=1&offset=0', auth);
    assert.equal(ok.status, 200);
    assert.equal(ok.body.count, 1);
  });

  await t.test('legacy batch sync: created, already_synced, and safe per-item errors', async () => {
    const payload = {
      sessions: [
        {
          clientSessionUuid: sessionUuid,
          participantCode: 'P001',
          deviceIdentifier: 'tablet-kelas-a',
          sessionSequenceNumber: 1,
          startedAt: now,
        },
        {
          clientSessionUuid: randomUUID(),
          participantCode: 'TIDAK_ADA',
          deviceIdentifier: 'tablet-kelas-a',
          sessionSequenceNumber: 2,
          startedAt: now,
        },
      ],
      attempts: [],
    };
    const res = await postJson(base, '/api/research/sync/batch', payload, auth);
    assert.equal(res.status, 200);
    assert.equal(res.body.data.sessions[0].status, 'already_synced');
    assert.equal(res.body.data.sessions[1].status, 'failed');
    assert.match(res.body.data.sessions[1].error, /not found/);
    assert.equal(res.body.data.summary.failedItems, 1);
  });

  await t.test('RBAC is unchanged', async () => {
    const teacher = bearer((await createUserWithToken(pool, 'teacher')).token);
    assert.equal((await getJson(base, '/api/research/devices', teacher)).status, 403);
    assert.equal((await getJson(base, '/api/research/participants', teacher)).status, 200);
    assert.equal((await getJson(base, '/api/research/summary')).status, 401);
    // Token bertanda tangan sah untuk pengguna yang tidak ada di database ditolak.
    assert.equal((await getJson(base, '/api/research/participants', bearer(userToken('researcher')))).status, 401);
  });
});
