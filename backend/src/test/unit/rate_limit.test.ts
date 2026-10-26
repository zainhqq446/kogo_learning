import '../helpers/test_env.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../../app.js';
import { createRateLimiters } from '../../middlewares/rate_limit.js';
import { config, DEFAULT_TRUST_PROXY } from '../../config/env.js';
import { bearer, deviceToken, postJson, startServer, testPrincipals, TestServer, userToken } from '../helpers/http.js';

test('rate limits are wired per route group', async (t) => {
  let server: TestServer | undefined;
  t.after(() => server?.close());
  server = await startServer(createApp({ principals: testPrincipals() }));
  const base = server.baseUrl;

  await t.test('auth: 10 requests / 15 min / IP, then 429 RATE_LIMITED', async () => {
    const headers = { 'X-Forwarded-For': '203.0.113.10' };
    for (let i = 0; i < 10; i++) {
      const res = await postJson(base, '/api/auth/login', {}, headers);
      assert.equal(res.status, 400, `request ${i + 1} should reach validation`);
      if (i === 0) assert.ok(res.headers.get('ratelimit-policy'), 'standard RateLimit-Policy header present');
    }
    const blocked = await postJson(base, '/api/auth/login', {}, headers);
    assert.equal(blocked.status, 429);
    assert.equal(blocked.body.code, 'RATE_LIMITED');

    // Registrasi berbagi limiter auth (dan dibatasi sebelum autentikasi).
    const register = await postJson(base, '/api/auth/register/child', {}, headers);
    assert.equal(register.status, 429);
  });

  await t.test('trust proxy: X-Forwarded-For from a private-network proxy identifies the client', async () => {
    // Test server berjalan di 127.0.0.1 (loopback = proxy tepercaya), seperti Traefik di jaringan Docker.
    const res = await postJson(base, '/api/auth/login', {}, { 'X-Forwarded-For': '198.51.100.7' });
    assert.equal(res.status, 400);
  });

  await t.test('device register: 20 requests / hour / IP', async () => {
    const headers = { 'X-Forwarded-For': '203.0.113.20' };
    for (let i = 0; i < 20; i++) {
      const res = await postJson(base, '/api/v2/devices/register', { platform: 'ios' }, headers);
      assert.equal(res.status, 400, `request ${i + 1}`);
    }
    const blocked = await postJson(base, '/api/v2/devices/register', { platform: 'ios' }, headers);
    assert.equal(blocked.status, 429);
  });

  await t.test('voice: 60 requests / minute / principal (device token), independent of IP', async () => {
    const token = deviceToken('00000000-0000-4000-8000-00000000f00d');
    for (let i = 0; i < 60; i++) {
      const res = await postJson(base, '/api/voice/tts', { text: 'Halo' }, { ...bearer(token), 'X-Forwarded-For': `192.0.2.${i}` });
      assert.equal(res.status, 503, `request ${i + 1} should reach the (unconfigured) service`);
    }
    const blocked = await postJson(base, '/api/voice/tts', { text: 'Halo' }, { ...bearer(token), 'X-Forwarded-For': '192.0.2.200' });
    assert.equal(blocked.status, 429);
    const otherDevice = await postJson(
      base,
      '/api/voice/tts',
      { text: 'Halo' },
      { ...bearer(deviceToken('00000000-0000-4000-8000-00000000beef')), 'X-Forwarded-For': '192.0.2.201' }
    );
    assert.equal(otherDevice.status, 503);
  });

  await t.test('sync: per-device limit (2/min here; default 60/min)', async () => {
    const limiters = createRateLimiters({ ...config.rateLimit, enabled: true, syncPerMinute: 2 });
    const small = await startServer(createApp({ rateLimiters: limiters, principals: testPrincipals() }));
    try {
      const token = bearer(deviceToken('00000000-0000-4000-8000-00000000cafe'));
      // Request ke-1 dan ke-2 lolos limiter lalu ditolak validasi (400), tanpa database.
      for (let i = 0; i < 2; i++) {
        const res = await postJson(small.baseUrl, '/api/v2/sync', { learners: 'invalid' }, token);
        assert.equal(res.status, 400);
      }
      const blocked = await postJson(small.baseUrl, '/api/v2/sync', { learners: 'invalid' }, token);
      assert.equal(blocked.status, 429);
    } finally {
      await small.close();
    }
  });
});

test('voice: per-IP limit caps many tokens minted from one source', async () => {
  const limiters = createRateLimiters({ ...config.rateLimit, enabled: true, voicePerIpPerMinute: 5, voicePerMinute: 60 });
  const server = await startServer(createApp({ rateLimiters: limiters, principals: testPrincipals() }));
  try {
    const headers = (i: number) => ({
      ...bearer(deviceToken(`00000000-0000-4000-8000-0000000010${String(i).padStart(2, '0')}`)),
      'X-Forwarded-For': '203.0.113.99',
    });
    for (let i = 0; i < 5; i++) {
      const res = await postJson(server.baseUrl, '/api/voice/tts', { text: 'Halo' }, headers(i));
      assert.equal(res.status, 503, `request ${i + 1}`);
    }
    const blocked = await postJson(server.baseUrl, '/api/voice/tts', { text: 'Halo' }, headers(6));
    assert.equal(blocked.status, 429, 'a fresh token does not get a fresh quota from the same IP');
    // Limiter per IP berjalan sebelum autentikasi: request anonim dari IP yang sama juga dibatasi.
    const anonymous = await postJson(server.baseUrl, '/api/voice/stt', { audioBase64: 'AAAA' }, { 'X-Forwarded-For': '203.0.113.99' });
    assert.equal(anonymous.status, 429);
    // Akun anak tidak boleh memakai proxy berbayar (IP lain agar tidak terkena limit).
    const child = await postJson(
      server.baseUrl,
      '/api/voice/tts',
      { text: 'Halo' },
      { ...bearer(userToken('child')), 'X-Forwarded-For': '203.0.113.100' }
    );
    assert.equal(child.status, 403);
  } finally {
    await server.close();
  }
});

test('trust proxy default only honours X-Forwarded-For from private-network peers', () => {
  assert.equal(config.server.trustProxy, DEFAULT_TRUST_PROXY);
  const app = createApp({ principals: testPrincipals() });
  const trust = app.get('trust proxy fn') as (addr: string, i: number) => boolean;
  for (const addr of ['127.0.0.1', '::1', '10.0.1.5', '172.18.0.2', '192.168.1.10', 'fd00::1', '169.254.1.1']) {
    assert.equal(trust(addr, 0), true, `${addr} (Docker/Traefik network) is trusted`);
  }
  for (const addr of ['203.0.113.7', '198.51.100.1', '8.8.8.8', '2001:db8::1']) {
    assert.equal(trust(addr, 0), false, `${addr} (public client) cannot spoof X-Forwarded-For`);
  }
});
