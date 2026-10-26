import '../helpers/test_env.js';
import { TEST_ENROLLMENT_KEY } from '../helpers/enrollment_env.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createApp } from '../../app.js';
import { config } from '../../config/env.js';
import { setDbPool } from '../../config/database.js';
import { createTestPool, createUserWithToken, prepareTestDatabase } from '../helpers/db.js';
import { bearer, getJson, noRateLimits, postJson, startServer, TestServer } from '../helpers/http.js';

test('API v2 with DEVICE_ENROLLMENT_KEY: only enrolled devices can register (auto-approved)', async (t) => {
  assert.equal(config.devices.enrollmentKey, TEST_ENROLLMENT_KEY);
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
  const body = () => ({ deviceUuid: randomUUID(), platform: 'android', appVersion: '2.0.0' });

  await t.test('anonymous registration is refused (403 ENROLLMENT_REQUIRED), nothing is stored', async () => {
    const missing = await postJson(base, '/api/v2/devices/register', body());
    assert.equal(missing.status, 403);
    assert.equal(missing.body.code, 'ENROLLMENT_REQUIRED');
    const wrong = await postJson(base, '/api/v2/devices/register', body(), { 'X-Enrollment-Key': 'not-the-key-not-the-key' });
    assert.equal(wrong.status, 403);
    const n = await pool.query('SELECT COUNT(*)::int AS n FROM app_devices');
    assert.equal(n.rows[0].n, 0);
  });

  await t.test('enrolled devices are approved immediately and their data counts in metrics', async () => {
    const reg = await postJson(base, '/api/v2/devices/register', body(), { 'X-Enrollment-Key': TEST_ENROLLMENT_KEY });
    assert.equal(reg.status, 201);
    assert.equal(reg.body.data.approved, true);
    const device = bearer(reg.body.data.deviceToken);
    const learner = randomUUID();
    const sync = await postJson(
      base,
      '/api/v2/sync',
      {
        learners: [
          { clientUuid: learner, name: 'Ani', school: 'TK Pelita', age: 5, createdAt: '2026-10-20T01:00:00.000Z', updatedAt: '2026-10-20T01:00:00.000Z' },
        ],
      },
      device
    );
    assert.equal(sync.status, 200);
    const researcher = await createUserWithToken(pool, 'researcher');
    const metrics = await getJson(base, '/api/v2/research/metrics', bearer(researcher.token));
    assert.deepEqual(metrics.body.data.devices, { approved: 1, pending: 0, revoked: 0 });
    assert.equal(metrics.body.data.perLearner.length, 1);
  });
});
