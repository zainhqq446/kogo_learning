import '../helpers/test_env.js';
import path from 'path';
import test from 'node:test';
import assert from 'node:assert/strict';
import { ConfigError, DEFAULT_TRUST_PROXY, loadConfig, parseCorsOrigin, parseTrustProxy } from '../../config/env.js';
import { getPoolConfig } from '../../config/database.js';
import { parseDurationSeconds } from '../../utils/duration.js';

const STRONG_SECRET = 'a3f9c2e8b7d6a5f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0c9b8';

function issuesOf(fn: () => unknown): string[] {
  try {
    fn();
  } catch (err) {
    if (err instanceof ConfigError) return err.issues;
    throw err;
  }
  return [];
}

test('config: production fails fast without JWT_SECRET', () => {
  const issues = issuesOf(() => loadConfig({ NODE_ENV: 'production' }));
  assert.ok(issues.some((i) => i.includes('JWT_SECRET is required')), issues.join('; '));
});

test('config: NODE_ENV defaults to production (secure by default)', () => {
  assert.throws(() => loadConfig({}), ConfigError);
  const cfg = loadConfig({ JWT_SECRET: STRONG_SECRET });
  assert.equal(cfg.server.nodeEnv, 'production');
  assert.equal(cfg.server.isProduction, true);
});

test('config: production rejects short, default and placeholder secrets', () => {
  assert.ok(issuesOf(() => loadConfig({ NODE_ENV: 'production', JWT_SECRET: 'short-secret' })).some((i) => i.includes('32')));
  assert.ok(
    issuesOf(() =>
      loadConfig({ NODE_ENV: 'production', JWT_SECRET: 'kogo_dev_jwt_secret_change_in_production_min32chars' })
    ).some((i) => i.includes('publicly known'))
  );
  assert.ok(
    issuesOf(() =>
      loadConfig({ NODE_ENV: 'production', JWT_SECRET: 'change_me_to_a_long_random_value_of_64_hex_chars_please' })
    ).some((i) => i.includes('placeholder'))
  );
  const ok = loadConfig({ NODE_ENV: 'production', JWT_SECRET: STRONG_SECRET });
  assert.equal(ok.auth.jwtSecret, STRONG_SECRET);
  assert.equal(ok.auth.jwtSecretIsEphemeral, false);
});

test('config: publicly known secrets are never used, in any environment', () => {
  for (const nodeEnv of ['development', 'test']) {
    for (const secret of [
      'kogo_dev_jwt_secret_change_in_production_min32chars',
      'replace_with_output_of_openssl_rand_hex_48',
      'change_me_to_a_long_random_value_of_64_hex_chars_please',
    ]) {
      const cfg = loadConfig({ NODE_ENV: nodeEnv, JWT_SECRET: secret });
      assert.notEqual(cfg.auth.jwtSecret, secret, `${nodeEnv}: ${secret} must be ignored`);
      assert.equal(cfg.auth.jwtSecretIsEphemeral, true);
      assert.ok(cfg.auth.jwtSecret.length >= 64);
      assert.ok(cfg.warnings.some((w) => w.includes('ephemeral')), cfg.warnings.join('; '));
    }
  }
});

test('config: HOST binds all interfaces only in production', () => {
  assert.equal(loadConfig({ NODE_ENV: 'production', JWT_SECRET: STRONG_SECRET }).server.host, '0.0.0.0');
  assert.equal(loadConfig({ NODE_ENV: 'development' }).server.host, '127.0.0.1');
  assert.equal(loadConfig({ NODE_ENV: 'development', HOST: '0.0.0.0' }).server.host, '0.0.0.0');
});

test('config: device enrollment key, sync clock skew and voice budgets', () => {
  const cfg = loadConfig({ NODE_ENV: 'production', JWT_SECRET: STRONG_SECRET });
  assert.equal(cfg.devices.enrollmentKey, undefined);
  assert.equal(cfg.devices.maxClockSkewMs, 24 * 60 * 60 * 1000);
  assert.ok(cfg.warnings.some((w) => w.includes('DEVICE_ENROLLMENT_KEY')), 'pending-approval mode is announced');
  assert.equal(cfg.elevenlabs.dailyTtsCharBudget, 20000);
  assert.equal(cfg.elevenlabs.dailySttSecondsBudget, 1800);
  assert.equal(cfg.elevenlabs.ttsCacheMaxBytes, 256 * 1024 * 1024);
  assert.equal(cfg.rateLimit.voicePerIpPerMinute, 120);

  const enrolled = loadConfig({ NODE_ENV: 'test', DEVICE_ENROLLMENT_KEY: 'field-test-2026-key', SYNC_MAX_CLOCK_SKEW_HOURS: '2' });
  assert.equal(enrolled.devices.enrollmentKey, 'field-test-2026-key');
  assert.equal(enrolled.devices.maxClockSkewMs, 2 * 60 * 60 * 1000);
  assert.ok(issuesOf(() => loadConfig({ NODE_ENV: 'test', DEVICE_ENROLLMENT_KEY: 'short' })).some((i) => i.includes('16')));
  assert.equal(loadConfig({ NODE_ENV: 'test', ELEVENLABS_DAILY_CHAR_BUDGET: '0' }).elevenlabs.dailyTtsCharBudget, 0);
  assert.throws(() => loadConfig({ NODE_ENV: 'test', ELEVENLABS_DAILY_STT_SECONDS_BUDGET: '-1' }), ConfigError);
});

test('config: non-production without JWT_SECRET uses an ephemeral random secret, never a public default', () => {
  const a = loadConfig({ NODE_ENV: 'development' });
  const b = loadConfig({ NODE_ENV: 'development' });
  assert.equal(a.auth.jwtSecretIsEphemeral, true);
  assert.ok(a.auth.jwtSecret.length >= 64);
  assert.notEqual(a.auth.jwtSecret, b.auth.jwtSecret);
  assert.notEqual(a.auth.jwtSecret, 'kogo_dev_jwt_secret_change_in_production_min32chars');
  assert.ok(a.warnings.some((w) => w.includes('ephemeral')));
});

test('config: secure defaults for proxy, CORS, limits and voice', () => {
  const cfg = loadConfig({ NODE_ENV: 'production', JWT_SECRET: STRONG_SECRET });
  assert.equal(cfg.server.trustProxy, 'loopback, linklocal, uniquelocal');
  assert.equal(cfg.server.corsOrigin, null, 'CORS must be disabled unless CORS_ORIGIN is set');
  assert.equal(cfg.server.jsonBodyLimit, '1mb');
  assert.equal(cfg.server.port, 4000);
  assert.equal(cfg.elevenlabs.defaultVoiceId, '', 'no hardcoded English default voice');
  assert.deepEqual(cfg.elevenlabs.allowedVoiceIds, []);
  assert.equal(cfg.elevenlabs.defaultModelId, 'eleven_multilingual_v2');
  assert.deepEqual(cfg.elevenlabs.allowedModelIds, ['eleven_multilingual_v2']);
  assert.equal(cfg.elevenlabs.sttModelId, 'scribe_v2');
  assert.equal(cfg.elevenlabs.outputFormat, 'mp3_22050_32');
  assert.equal(cfg.elevenlabs.languageCode, 'id');
  assert.equal(cfg.elevenlabs.ttsMaxTextLength, 300);
  assert.equal(cfg.elevenlabs.maxAudioUploadBytes, 2 * 1024 * 1024);
  assert.ok(cfg.elevenlabs.ttsCacheDir.endsWith(path.join('data', 'tts-cache')));
  assert.equal(cfg.auth.deviceTokenTtlSeconds, 180 * 86400);
  assert.equal(cfg.rateLimit.authMax, 10);
  assert.equal(cfg.rateLimit.authWindowMs, 15 * 60 * 1000);
  assert.equal(cfg.rateLimit.voicePerMinute, 60);
  assert.equal(cfg.rateLimit.syncPerMinute, 60);
  assert.equal(cfg.rateLimit.deviceRegisterPerHour, 20);
  assert.equal(cfg.startup.runMigrationsOnStart, true);
});

test('config: voice/model allowlists always include the configured defaults', () => {
  const cfg = loadConfig({
    NODE_ENV: 'test',
    ELEVENLABS_DEFAULT_VOICE_ID: 'voiceA',
    ELEVENLABS_ALLOWED_VOICE_IDS: 'voiceB, voiceC,voiceA',
    ELEVENLABS_DEFAULT_MODEL_ID: 'eleven_flash_v2_5',
    ELEVENLABS_ALLOWED_MODEL_IDS: 'eleven_multilingual_v2',
  });
  assert.deepEqual(cfg.elevenlabs.allowedVoiceIds, ['voiceA', 'voiceB', 'voiceC']);
  assert.deepEqual(cfg.elevenlabs.allowedModelIds, ['eleven_flash_v2_5', 'eleven_multilingual_v2']);
});

test('config: DATABASE_URL is supported and TLS verification defaults to on', () => {
  const withUrl = loadConfig({ NODE_ENV: 'test', DATABASE_URL: 'postgres://kogo:secret@db:5432/kogo', DB_SSL: 'true' });
  const poolCfg = getPoolConfig(withUrl.database);
  assert.equal(poolCfg.connectionString, 'postgres://kogo:secret@db:5432/kogo');
  assert.deepEqual(poolCfg.ssl, { rejectUnauthorized: true });

  const insecure = loadConfig({ NODE_ENV: 'test', DB_SSL: 'true', DB_SSL_REJECT_UNAUTHORIZED: 'false' });
  assert.deepEqual(getPoolConfig(insecure.database).ssl, { rejectUnauthorized: false });
  assert.ok(insecure.warnings.some((w) => w.includes('DB_SSL_REJECT_UNAUTHORIZED')));

  const plain = loadConfig({ NODE_ENV: 'test', DB_HOST: 'pg', DB_NAME: 'kogo' });
  const plainPool = getPoolConfig(plain.database);
  assert.equal(plainPool.ssl, false);
  assert.equal(plainPool.host, 'pg');
  assert.equal(plainPool.database, 'kogo');

  assert.throws(() => loadConfig({ NODE_ENV: 'test', DATABASE_URL: 'mysql://x' }), ConfigError);
});

test('config: admin bootstrap credentials are validated', () => {
  assert.ok(issuesOf(() => loadConfig({ NODE_ENV: 'test', ADMIN_USERNAME: 'admin' })).some((i) => i.includes('together')));
  assert.ok(
    issuesOf(() =>
      loadConfig({ NODE_ENV: 'production', JWT_SECRET: STRONG_SECRET, ADMIN_USERNAME: 'admin', ADMIN_PASSWORD: 'short' })
    ).some((i) => i.includes('ADMIN_PASSWORD'))
  );
  assert.ok(issuesOf(() => loadConfig({ NODE_ENV: 'test', ADMIN_USERNAME: 'bad name!', ADMIN_PASSWORD: 'x'.repeat(16) })).length > 0);
  const cfg = loadConfig({
    NODE_ENV: 'production',
    JWT_SECRET: STRONG_SECRET,
    ADMIN_USERNAME: 'Peneliti_Admin',
    ADMIN_PASSWORD: 'a-very-long-password',
  });
  assert.equal(cfg.auth.adminUsername, 'peneliti_admin');
});

test('config: invalid numbers, booleans and durations fail fast', () => {
  assert.throws(() => loadConfig({ NODE_ENV: 'test', PORT: 'abc' }), ConfigError);
  assert.throws(() => loadConfig({ NODE_ENV: 'test', JWT_EXPIRES_IN: 'soon' }), ConfigError);
  assert.throws(() => loadConfig({ NODE_ENV: 'test', RATE_LIMIT_ENABLED: 'maybe' }), ConfigError);
  assert.throws(() => loadConfig({ NODE_ENV: 'test', ELEVENLABS_TEXT_NORMALIZATION: 'always' }), ConfigError);
});

test('config helpers: TRUST_PROXY, CORS_ORIGIN and durations', () => {
  assert.equal(parseTrustProxy(undefined), DEFAULT_TRUST_PROXY);
  assert.equal(parseTrustProxy('1'), 1);
  assert.equal(parseTrustProxy('2'), 2);
  assert.equal(parseTrustProxy('0'), false);
  assert.equal(parseTrustProxy('false'), false);
  assert.equal(parseTrustProxy('loopback, 10.0.0.0/8'), 'loopback, 10.0.0.0/8');

  assert.equal(parseCorsOrigin(undefined), null);
  assert.equal(parseCorsOrigin(''), null);
  assert.equal(parseCorsOrigin('*'), '*');
  assert.equal(parseCorsOrigin('https://a.example'), 'https://a.example');
  assert.deepEqual(parseCorsOrigin('https://a.example, https://b.example'), ['https://a.example', 'https://b.example']);

  assert.equal(parseDurationSeconds('900'), 900);
  assert.equal(parseDurationSeconds('15m'), 900);
  assert.equal(parseDurationSeconds('12h'), 43200);
  assert.equal(parseDurationSeconds('180d'), 15552000);
  assert.throws(() => parseDurationSeconds('0s'));
  assert.throws(() => parseDurationSeconds('1w'));
});
