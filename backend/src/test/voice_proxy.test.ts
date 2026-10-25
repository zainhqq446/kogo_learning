import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../app.js';
import { Server } from 'http';
import { Pool } from 'pg';
import { setDbPool } from '../config/database.js';
import jwt from 'jsonwebtoken';
import { config } from '../config/env.js';

test('Voice Proxy & Batch Participants Test Suite', async (t) => {
  const testPool = new Pool({
    host: config.database.host,
    port: config.database.port,
    database: 'kogo_research_test',
    user: config.database.user,
    password: config.database.password,
    ssl: config.database.ssl ? { rejectUnauthorized: false } : false,
  });

  setDbPool(testPool);
  const app = createApp();
  let server: Server;
  let baseUrl: string;
  let authToken: string;

  await t.test('Setup test server and mock pool', async () => {
    // Pastikan user dummy ada di database test untuk referensi audit
    await testPool.query(`
      INSERT INTO users (id, username, password_hash, full_name, role, is_active, created_at, updated_at)
      VALUES ('111e4567-e89b-12d3-a456-426614174000', 'voice_tester', 'hash', 'Voice Tester', 'researcher', true, NOW(), NOW())
      ON CONFLICT (id) DO NOTHING;
    `);

    authToken = jwt.sign(
      { userId: '111e4567-e89b-12d3-a456-426614174000', username: 'voice_tester', role: 'researcher' },
      config.auth.jwtSecret,
      { expiresIn: '1h' }
    );

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

  await t.test('GET /api/voice/status requires authentication', async () => {
    const res = await fetch(`${baseUrl}/api/voice/status`);
    assert.strictEqual(res.status, 401, 'Should return 401 without token');
  });

  await t.test('GET /api/voice/status returns 200 with Bearer token', async () => {
    const res = await fetch(`${baseUrl}/api/voice/status`, {
      headers: { Authorization: `Bearer ${authToken}` },
    });
    assert.strictEqual(res.status, 200);
    const data = await res.json() as any;
    assert.strictEqual(data.status, 'success');
    assert.ok(typeof data.configured === 'boolean');
    assert.ok(data.defaultVoiceId);
    assert.ok(data.defaultModelId);
  });

  await t.test('POST /api/voice/tts validates text input', async () => {
    // Empty text
    const emptyRes = await fetch(`${baseUrl}/api/voice/tts`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${authToken}`,
      },
      body: JSON.stringify({ text: '' }),
    });
    assert.strictEqual(emptyRes.status, 400);

    // Text > 500 chars
    const longRes = await fetch(`${baseUrl}/api/voice/tts`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${authToken}`,
      },
      body: JSON.stringify({ text: 'a'.repeat(501) }),
    });
    assert.strictEqual(longRes.status, 400);
  });

  await t.test('POST /api/research/participants/batch validates payload schema', async () => {
    const res = await fetch(`${baseUrl}/api/research/participants/batch`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${authToken}`,
      },
      body: JSON.stringify({ participants: [] }),
    });
    assert.strictEqual(res.status, 400, 'Empty participants array should be rejected');
  });

  await t.test('POST /api/research/participants/batch processes batch gracefully', async () => {
    const batchPayload = {
      participants: [
        {
          participantCode: 'TEST_BATCH_01',
          displayAlias: 'Peserta Batch 1',
          ageYears: 5,
          gender: 'M',
          pin: '1234',
        },
      ],
    };

    const res = await fetch(`${baseUrl}/api/research/participants/batch`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${authToken}`,
      },
      body: JSON.stringify(batchPayload),
    });

    assert.strictEqual(res.status, 200);
    const data = await res.json() as any;
    assert.strictEqual(data.status, 'success');
    assert.strictEqual(data.data.total, 1);
    assert.strictEqual(data.data.created, 1);

    // Teardown created participant from database
    await testPool.query('DELETE FROM participants WHERE participant_code = $1', ['TEST_BATCH_01']);
  });

  await t.test('Teardown test server and pool', async () => {
    await testPool.end();
    return new Promise<void>((resolve, reject) => {
      server.close((err) => {
        if (err) reject(err);
        else resolve();
      });
    });
  });
});
