import '../helpers/test_env.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import { Pool } from 'pg';
import { createApp } from '../../app.js';
import { setDbPool } from '../../config/database.js';
import { getJson, startServer, TestServer } from '../helpers/http.js';

test('health, readiness and security headers (no database needed)', async (t) => {
  // Pool ke port tertutup: readiness harus 503 tanpa membocorkan pesan error.
  const unreachable = new Pool({ host: '127.0.0.1', port: 1, connectionTimeoutMillis: 1000, max: 1 });
  setDbPool(unreachable);
  let server: TestServer | undefined;
  t.after(async () => {
    await server?.close();
    await unreachable.end();
  });
  server = await startServer(createApp());
  const base = server.baseUrl;

  await t.test('GET /api/health is a liveness probe without environment or DB details', async () => {
    const res = await getJson(base, '/api/health');
    assert.equal(res.status, 200);
    assert.equal(res.body.status, 'ok');
    assert.equal(res.body.service, 'kogo-voice-learning-backend');
    assert.equal(typeof res.body.uptimeSeconds, 'number');
    assert.equal(res.body.environment, undefined);
    assert.equal(res.body.database, undefined);
  });

  await t.test('GET /api/health/ready returns 503 when PostgreSQL is down, without error details', async () => {
    const res = await getJson(base, '/api/health/ready');
    assert.equal(res.status, 503);
    assert.equal(res.body.status, 'not_ready');
    assert.equal(res.body.checks.database, 'down');
    assert.ok(!res.text.includes('ECONNREFUSED'));
  });

  await t.test('CORS is disabled by default and helmet headers are present', async () => {
    const res = await getJson(base, '/api/health', { Origin: 'https://evil.example' });
    assert.equal(res.headers.get('access-control-allow-origin'), null);
    assert.equal(res.headers.get('access-control-allow-credentials'), null);
    assert.equal(res.headers.get('x-content-type-options'), 'nosniff');
    assert.equal(res.headers.get('x-powered-by'), null);
  });

  await t.test('unknown routes return structured 404', async () => {
    const res = await getJson(base, '/api/unknown');
    assert.equal(res.status, 404);
    assert.equal(res.body.code, 'NOT_FOUND');
  });
});
