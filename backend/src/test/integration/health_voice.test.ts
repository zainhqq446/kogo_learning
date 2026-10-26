import '../helpers/test_env.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { createApp } from '../../app.js';
import { setDbPool } from '../../config/database.js';
import { ensureAdminUser } from '../../services/auth_service.js';
import { DbVoiceUsageBudget } from '../../services/voice_budget.js';
import { createTestPool, createUserWithToken, prepareTestDatabase } from '../helpers/db.js';
import { bearer, getJson, noRateLimits, postJson, startServer, TestServer } from '../helpers/http.js';

test('health readiness and voice proxy with real database and real tokens', async (t) => {
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

  await t.test('GET /api/health/ready returns 200 when PostgreSQL is reachable', async () => {
    const res = await getJson(base, '/api/health/ready');
    assert.equal(res.status, 200);
    assert.equal(res.body.status, 'ready');
    assert.equal(res.body.checks.database, 'up');
    assert.equal(typeof res.body.latencyMs, 'number');
  });

  await t.test('voice routes: staff or approved devices only; 503 NOT_CONFIGURED without ElevenLabs', async () => {
    assert.equal((await postJson(base, '/api/voice/tts', { text: 'Halo' })).status, 401);
    assert.equal((await postJson(base, '/api/voice/stt', { audioBase64: 'AAAA' })).status, 401);

    const reg = await postJson(base, '/api/v2/devices/register', { deviceUuid: randomUUID(), platform: 'android', appVersion: '2.0.0' });
    const device = bearer(reg.body.data.deviceToken);
    const deviceId = (JSON.parse(Buffer.from(reg.body.data.deviceToken.split('.')[1], 'base64url').toString()) as { deviceId: string })
      .deviceId;

    // Perangkat baru (pending) belum boleh memakai proxy berbayar.
    const pending = await postJson(base, '/api/voice/tts', { text: 'Halo' }, device);
    assert.equal(pending.status, 403);
    assert.equal(pending.body.code, 'DEVICE_NOT_APPROVED');
    await pool.query('UPDATE app_devices SET approved_at = CURRENT_TIMESTAMP WHERE id = $1', [deviceId]);

    await ensureAdminUser(pool, { username: 'voice_admin', password: 'voice-admin-pass' });
    const login = await postJson(base, '/api/auth/login', { username: 'voice_admin', password: 'voice-admin-pass' });
    const user = bearer(login.body.data.tokens.accessToken);

    for (const headers of [device, user]) {
      const tts = await postJson(base, '/api/voice/tts', { text: 'Ayo ucapkan bola!', mood: 'encouraging' }, headers);
      assert.equal(tts.status, 503);
      assert.equal(tts.body.code, 'NOT_CONFIGURED');
      const stt = await postJson(base, '/api/voice/stt', { audioBase64: Buffer.from('RIFFxxxxWAVE').toString('base64') }, headers);
      assert.equal(stt.status, 503);
      assert.equal(stt.body.code, 'NOT_CONFIGURED');
    }

    const refresh = bearer(login.body.data.tokens.refreshToken);
    assert.equal((await postJson(base, '/api/voice/tts', { text: 'Halo' }, refresh)).status, 401);

    // Akun anak tidak boleh memakai proxy berbayar.
    const child = await createUserWithToken(pool, 'child');
    assert.equal((await postJson(base, '/api/voice/tts', { text: 'Halo' }, bearer(child.token))).status, 403);

    // Perangkat yang dihapus kehilangan akses suara seketika (bukan setelah token kedaluwarsa).
    await pool.query('DELETE FROM app_devices WHERE id = $1', [deviceId]);
    const deleted = await postJson(base, '/api/voice/tts', { text: 'Halo' }, device);
    assert.equal(deleted.status, 401);
    assert.equal(deleted.body.code, 'DEVICE_NOT_REGISTERED');
  });

  await t.test('daily voice budget is enforced atomically in PostgreSQL', async () => {
    const budget = new DbVoiceUsageBudget(() => pool);
    assert.equal(await budget.tryReserve('tts_chars', 60, 100), true);
    assert.equal(await budget.tryReserve('tts_chars', 50, 100), false, 'would exceed the daily limit');
    assert.equal(await budget.tryReserve('tts_chars', 40, 100), true);
    assert.equal(await budget.tryReserve('tts_chars', 1, 100), false);
    await budget.adjust('tts_chars', -40);
    assert.equal(await budget.tryReserve('tts_chars', 40, 100), true, 'refunds free the budget again');
    await budget.adjust('stt_seconds', -10);
    const rows = await pool.query<{ metric: string; amount: string }>('SELECT metric, amount FROM voice_usage_daily ORDER BY metric');
    assert.deepEqual(
      rows.rows.map((r) => [r.metric, Number(r.amount)]),
      [
        ['stt_seconds', 0],
        ['tts_chars', 100],
      ]
    );
    // Reservasi paralel tidak pernah melampaui batas.
    await pool.query('DELETE FROM voice_usage_daily');
    const results = await Promise.all(Array.from({ length: 20 }, () => budget.tryReserve('stt_seconds', 10, 55)));
    assert.equal(results.filter(Boolean).length, 5);
  });
});
