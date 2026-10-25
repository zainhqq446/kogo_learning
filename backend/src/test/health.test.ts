import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../app.js';
import { Server } from 'http';

test('Kogo Backend Foundation Test Suite', async (t) => {
  const app = createApp();
  let server: Server;
  let baseUrl: string;

  await t.test('Setup test server', async () => {
    return new Promise<void>((resolve) => {
      server = app.listen(0, () => {
        const address = server.address();
        if (address && typeof address === 'object') {
          baseUrl = `http://localhost:${address.port}`;
        }
        resolve();
      });
    });
  });

  await t.test('GET /api/health returns 200 and valid payload', async () => {
    const res = await fetch(`${baseUrl}/api/health`);
    assert.strictEqual(res.status, 200, 'Status code should be 200');

    const data = await res.json() as any;
    assert.strictEqual(data.status, 'ok', 'Status should be ok');
    assert.strictEqual(data.service, 'kogo-voice-learning-backend');
    assert.ok(data.timestamp, 'Timestamp should exist');
    assert.ok(typeof data.uptimeSeconds === 'number', 'Uptime should be a number');
    assert.ok(data.database, 'Database health section should exist');
    assert.strictEqual(data.database.provider, 'postgresql');
    assert.ok(typeof data.database.connected === 'boolean', 'Database connected should be boolean');
  });

  await t.test('GET /unknown-route returns 404 with structured JSON error', async () => {
    const res = await fetch(`${baseUrl}/unknown-nonexistent-route`);
    assert.strictEqual(res.status, 404, 'Status code should be 404');

    const data = await res.json() as any;
    assert.strictEqual(data.status, 'error');
    assert.strictEqual(data.statusCode, 404);
    assert.ok(data.message.includes('not found'));
  });

  await t.test('CORS headers are set properly', async () => {
    const res = await fetch(`${baseUrl}/api/health`, {
      method: 'GET',
      headers: {
        Origin: 'http://localhost:3000',
      },
    });
    assert.strictEqual(res.status, 200);
    const allowOrigin = res.headers.get('access-control-allow-origin');
    assert.ok(allowOrigin, 'Access-Control-Allow-Origin header should exist');
  });

  await t.test('Teardown test server', async () => {
    return new Promise<void>((resolve, reject) => {
      server.close((err) => {
        if (err) reject(err);
        else resolve();
      });
    });
  });
});
