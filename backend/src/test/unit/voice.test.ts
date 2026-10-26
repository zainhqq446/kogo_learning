import '../helpers/test_env.js';
import fs from 'fs/promises';
import os from 'os';
import path from 'path';
import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../../app.js';
import { config, ElevenLabsConfig } from '../../config/env.js';
import { TtsDiskCache, ttsCacheKey } from '../../services/tts_cache.js';
import {
  DEFAULT_VOICE_PROFILE,
  MOOD_PROFILES,
  VoiceService,
  estimateAudioSeconds,
  languageCodeForModel,
  resolveVoiceSettings,
} from '../../services/voice_service.js';
import { MemoryVoiceUsageBudget } from '../../services/voice_budget.js';
import { AppError } from '../../types/errors.js';
import { generateUserTokens } from '../../services/token_service.js';
import { bearer, deviceToken, getJson, postJson, startServer, TEST_USER_IDS, testPrincipals, TestServer, userToken } from '../helpers/http.js';

const baseKey = {
  text: 'Ayo ucapkan bola',
  voiceId: 'voiceA',
  modelId: 'eleven_multilingual_v2',
  settings: { stability: 0.45, similarity_boost: 0.8, style: 0.4, speed: 0.95, use_speaker_boost: true },
  languageCode: null,
  outputFormat: 'mp3_22050_32',
  textNormalization: 'auto',
};

async function tempDir(): Promise<string> {
  return fs.mkdtemp(path.join(os.tmpdir(), 'kogo-tts-unit-'));
}

function voiceConfig(overrides: Partial<ElevenLabsConfig> = {}): ElevenLabsConfig {
  return {
    ...config.elevenlabs,
    baseUrl: 'https://elevenlabs.test/v1',
    apiKey: 'test-key',
    defaultVoiceId: 'voiceA',
    allowedVoiceIds: ['voiceA', 'voiceB'],
    defaultModelId: 'eleven_multilingual_v2',
    allowedModelIds: ['eleven_multilingual_v2', 'eleven_flash_v2_5'],
    ttsTimeoutMs: 200,
    sttTimeoutMs: 200,
    dailyTtsCharBudget: 100_000,
    dailySttSecondsBudget: 100_000,
    ...overrides,
  };
}

function service(cfg: ElevenLabsConfig, cache: TtsDiskCache, budget = new MemoryVoiceUsageBudget()): VoiceService {
  return new VoiceService(cfg, cache, budget);
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

interface CapturedRequest {
  url: string;
  init: RequestInit;
}

function stubFetch(responder: (req: CapturedRequest) => Promise<Response> | Response): { calls: CapturedRequest[]; restore: () => void } {
  const original = globalThis.fetch;
  const calls: CapturedRequest[] = [];
  globalThis.fetch = (async (input: string | URL | Request, init: RequestInit = {}) => {
    const req = { url: String(input), init };
    calls.push(req);
    return responder(req);
  }) as typeof fetch;
  return { calls, restore: () => (globalThis.fetch = original) };
}

test('tts cache key is deterministic and sensitive to every input', () => {
  const key = ttsCacheKey(baseKey);
  assert.match(key, /^[a-f0-9]{64}$/);
  assert.equal(ttsCacheKey({ ...baseKey, settings: { ...baseKey.settings } }), key);
  // Urutan properti settings tidak berpengaruh.
  const reordered = { use_speaker_boost: true, speed: 0.95, style: 0.4, similarity_boost: 0.8, stability: 0.45 };
  assert.equal(ttsCacheKey({ ...baseKey, settings: reordered }), key);
  assert.notEqual(ttsCacheKey({ ...baseKey, text: 'Ayo ucapkan buku' }), key);
  assert.notEqual(ttsCacheKey({ ...baseKey, voiceId: 'voiceB' }), key);
  assert.notEqual(ttsCacheKey({ ...baseKey, modelId: 'eleven_flash_v2_5' }), key);
  assert.notEqual(ttsCacheKey({ ...baseKey, settings: { ...baseKey.settings, style: 0.6 } }), key);
  assert.notEqual(ttsCacheKey({ ...baseKey, languageCode: 'id' }), key);
  assert.notEqual(ttsCacheKey({ ...baseKey, outputFormat: 'mp3_44100_128' }), key);
});

test('mood mapping gives intonation variety; explicit settings override the mood', () => {
  assert.deepEqual(resolveVoiceSettings(), {
    stability: DEFAULT_VOICE_PROFILE.stability,
    similarity_boost: 0.8,
    style: DEFAULT_VOICE_PROFILE.style,
    speed: DEFAULT_VOICE_PROFILE.speed,
    use_speaker_boost: true,
  });
  assert.equal(DEFAULT_VOICE_PROFILE.stability, 0.45);
  assert.equal(DEFAULT_VOICE_PROFILE.style, 0.4);
  for (const mood of ['excited', 'celebratory'] as const) {
    assert.equal(resolveVoiceSettings(mood).stability, 0.3);
    assert.equal(resolveVoiceSettings(mood).style, 0.6);
  }
  for (const mood of ['gentle', 'patient'] as const) {
    assert.equal(resolveVoiceSettings(mood).stability, 0.6);
    assert.equal(resolveVoiceSettings(mood).style, 0.2);
  }
  assert.deepEqual(Object.keys(MOOD_PROFILES).sort(), [
    'celebratory',
    'curious',
    'encouraging',
    'excited',
    'gentle',
    'patient',
    'playful',
    'warm',
  ]);
  const overridden = resolveVoiceSettings('excited', { stability: 0.9, speed: 1.1 });
  assert.equal(overridden.stability, 0.9);
  assert.equal(overridden.style, 0.6);
  assert.equal(overridden.speed, 1.1);
});

test('language_code is sent only for models that support it', () => {
  assert.equal(languageCodeForModel('eleven_multilingual_v2', 'id'), null);
  assert.equal(languageCodeForModel('eleven_flash_v2_5', 'id'), 'id');
  assert.equal(languageCodeForModel('eleven_turbo_v2_5', 'id'), 'id');
});

test('disk cache round-trips audio and rejects unsafe keys', async () => {
  const dir = await tempDir();
  const cache = new TtsDiskCache(dir);
  const key = ttsCacheKey(baseKey);
  assert.equal(await cache.get(key), null);
  await cache.set(key, Buffer.from('ID3-audio'));
  assert.equal((await cache.get(key))?.toString(), 'ID3-audio');
  assert.equal(await cache.get('../../etc/passwd'), null);
  await assert.rejects(() => cache.set('../../etc/passwd', Buffer.from('x')), /Invalid cache key/);
  const disabled = new TtsDiskCache(dir, false);
  assert.equal(await disabled.get(key), null);
  await fs.rm(dir, { recursive: true, force: true });
});

test('VoiceService.synthesize sends Indonesian-friendly request and caches the result', async () => {
  const dir = await tempDir();
  const stub = stubFetch(() => new Response(Buffer.from('mp3-bytes'), { status: 200, headers: { 'Content-Type': 'audio/mpeg' } }));
  try {
    const svc = service(voiceConfig(), new TtsDiskCache(dir));
    const first = await svc.synthesize({ text: '  Hebat   sekali! ', mood: 'celebratory' });
    assert.equal(first.cacheHit, false);
    assert.equal(first.audio.toString(), 'mp3-bytes');
    assert.equal(stub.calls.length, 1);

    const { url, init } = stub.calls[0];
    assert.equal(url, 'https://elevenlabs.test/v1/text-to-speech/voiceA?output_format=mp3_22050_32');
    assert.equal((init.headers as Record<string, string>)['xi-api-key'], 'test-key');
    const body = JSON.parse(String(init.body));
    assert.equal(body.text, 'Hebat sekali!');
    assert.equal(body.model_id, 'eleven_multilingual_v2');
    assert.equal(body.apply_text_normalization, 'auto');
    assert.equal(body.language_code, undefined, 'multilingual_v2 does not accept language_code');
    assert.equal(body.voice_settings.stability, 0.3);
    assert.equal(body.voice_settings.style, 0.6);

    const second = await svc.synthesize({ text: 'Hebat sekali!', mood: 'celebratory' });
    assert.equal(second.cacheHit, true);
    assert.equal(stub.calls.length, 1, 'second request is served from disk cache');

    await svc.synthesize({ text: 'Hebat sekali!', modelId: 'eleven_flash_v2_5' });
    assert.equal(JSON.parse(String(stub.calls[1].init.body)).language_code, 'id');
  } finally {
    stub.restore();
    await fs.rm(dir, { recursive: true, force: true });
  }
});

test('VoiceService enforces allowlists, configuration and limits', async () => {
  const dir = await tempDir();
  const stub = stubFetch(() => new Response('nope', { status: 500 }));
  try {
    const svc = service(voiceConfig(), new TtsDiskCache(dir));
    await assert.rejects(
      () => svc.synthesize({ text: 'Halo', voiceId: 'attackerVoice' }),
      (err: unknown) => err instanceof AppError && err.code === 'VOICE_NOT_ALLOWED' && err.statusCode === 400
    );
    await assert.rejects(
      () => svc.synthesize({ text: 'Halo', modelId: 'eleven_v3' }),
      (err: unknown) => err instanceof AppError && err.code === 'MODEL_NOT_ALLOWED'
    );
    await assert.rejects(
      () => svc.synthesize({ text: 'Halo' }),
      (err: unknown) => err instanceof AppError && err.statusCode === 502 && err.code === 'UPSTREAM_ERROR'
    );
    assert.equal(stub.calls.length, 1, 'disallowed voices/models never reach the provider');

    const noVoice = service(voiceConfig({ defaultVoiceId: '', allowedVoiceIds: [] }), new TtsDiskCache(dir));
    await assert.rejects(
      () => noVoice.synthesize({ text: 'Halo' }),
      (err: unknown) => err instanceof AppError && err.statusCode === 503 && err.code === 'NOT_CONFIGURED'
    );

    await assert.rejects(
      () => svc.transcribe({ audioBuffer: Buffer.alloc(config.elevenlabs.maxAudioUploadBytes + 1), mimeType: 'audio/wav' }),
      (err: unknown) => err instanceof AppError && err.statusCode === 413
    );
    await assert.rejects(
      () => svc.transcribe({ audioBuffer: Buffer.from('abc'), mimeType: 'text/html' }),
      (err: unknown) => err instanceof AppError && err.statusCode === 415
    );
  } finally {
    stub.restore();
    await fs.rm(dir, { recursive: true, force: true });
  }
});

test('VoiceService keeps the timeout active until the body is read', async () => {
  const dir = await tempDir();
  const stub = stubFetch(
    ({ init }) =>
      new Response(
        new ReadableStream({
          start(controller) {
            controller.enqueue(new TextEncoder().encode('partial'));
            init.signal?.addEventListener('abort', () => controller.error(new DOMException('aborted', 'AbortError')));
          },
        }),
        { status: 200 }
      )
  );
  try {
    const svc = service(voiceConfig({ ttsTimeoutMs: 50 }), new TtsDiskCache(dir));
    await assert.rejects(
      () => svc.synthesize({ text: 'Halo' }),
      (err: unknown) => err instanceof AppError && err.statusCode === 504 && err.code === 'UPSTREAM_TIMEOUT'
    );
  } finally {
    stub.restore();
    await fs.rm(dir, { recursive: true, force: true });
  }
});

test('VoiceService.transcribe sends scribe model and Indonesian language code', async () => {
  const stub = stubFetch(() => Response.json({ text: ' bola ', language_code: 'ind', audio_duration_secs: 1.2 }));
  try {
    const svc = service(voiceConfig(), new TtsDiskCache('/nonexistent', false));
    const result = await svc.transcribe({ audioBuffer: Buffer.from('RIFF....WAVE'), mimeType: 'audio/wav' });
    assert.equal(result.text, 'bola');
    const form = stub.calls[0].init.body as FormData;
    assert.equal(form.get('model_id'), 'scribe_v2');
    assert.equal(form.get('language_code'), 'id');
    assert.equal(stub.calls[0].url, 'https://elevenlabs.test/v1/speech-to-text');
  } finally {
    stub.restore();
  }
});

test('client voice settings are snapped to a coarse grid (bounded cache key space)', () => {
  const a = resolveVoiceSettings(undefined, { stability: 0.1, similarityBoost: 0.83, style: 0.47, speed: 1.07 });
  const b = resolveVoiceSettings(undefined, { stability: 0.11, similarityBoost: 0.8, style: 0.53, speed: 1.06 });
  const c = resolveVoiceSettings(undefined, { stability: 0.12, similarityBoost: 0.84, style: 0.5, speed: 1.04 });
  assert.deepEqual(a, b);
  assert.deepEqual(b, c);
  assert.deepEqual(a, { stability: 0.1, similarity_boost: 0.8, style: 0.5, speed: 1.05, use_speaker_boost: true });
  // Profil mood (nilai server) tidak dibulatkan.
  assert.equal(resolveVoiceSettings('patient').speed, 0.9);
  assert.equal(resolveVoiceSettings('curious').speed, 0.97);
});

test('VoiceService enforces the daily TTS character budget and refunds failed calls', async () => {
  const dir = await tempDir();
  let fail = false;
  const stub = stubFetch(() => (fail ? new Response('boom', { status: 500 }) : new Response(Buffer.from('mp3'), { status: 200 })));
  try {
    const budget = new MemoryVoiceUsageBudget();
    const svc = service(voiceConfig({ dailyTtsCharBudget: 10 }), new TtsDiskCache(dir), budget);
    await svc.synthesize({ text: 'Halo' });
    assert.equal(budget.usage('tts_chars'), 4);
    await assert.rejects(
      () => svc.synthesize({ text: 'Halo dunia' }),
      (err: unknown) => err instanceof AppError && err.statusCode === 503 && err.code === 'VOICE_BUDGET_EXHAUSTED'
    );
    assert.equal(stub.calls.length, 1, 'exhausted budget never reaches the provider');
    // Cache hit tidak memakai anggaran.
    assert.equal((await svc.synthesize({ text: 'Halo' })).cacheHit, true);
    assert.equal(budget.usage('tts_chars'), 4);

    fail = true;
    await assert.rejects(() => svc.synthesize({ text: 'Bola' }), (err: unknown) => err instanceof AppError && err.statusCode === 502);
    assert.equal(budget.usage('tts_chars'), 4, 'failed upstream calls are refunded');

    const zero = service(voiceConfig({ dailyTtsCharBudget: 0 }), new TtsDiskCache(dir, false), new MemoryVoiceUsageBudget());
    await assert.rejects(() => zero.synthesize({ text: 'Halo' }), (err: unknown) => err instanceof AppError && err.code === 'VOICE_BUDGET_EXHAUSTED');
  } finally {
    stub.restore();
    await fs.rm(dir, { recursive: true, force: true });
  }
});

test('VoiceService reserves STT seconds conservatively and settles to the billed duration', async () => {
  const stub = stubFetch(() => Response.json({ text: 'bola', audio_duration_secs: 3.4 }));
  try {
    assert.equal(estimateAudioSeconds(1000), 1);
    assert.equal(estimateAudioSeconds(2 * 1024 * 1024), 1049);
    const budget = new MemoryVoiceUsageBudget();
    const svc = service(voiceConfig({ dailySttSecondsBudget: 10 }), new TtsDiskCache('/nonexistent', false), budget);
    await svc.transcribe({ audioBuffer: Buffer.alloc(1000), mimeType: 'audio/wav' });
    assert.equal(budget.usage('stt_seconds'), 4, 'reservation corrected to ceil(audio_duration_secs)');
    await assert.rejects(
      () => svc.transcribe({ audioBuffer: Buffer.alloc(14_000), mimeType: 'audio/ogg' }),
      (err: unknown) => err instanceof AppError && err.statusCode === 503 && err.code === 'VOICE_BUDGET_EXHAUSTED'
    );
    assert.equal(stub.calls.length, 1);
  } finally {
    stub.restore();
  }
});

test('TTS disk cache is size-capped and evicts the least recently used files', async () => {
  const dir = await tempDir();
  try {
    const cache = new TtsDiskCache(dir, true, 25);
    const k = (text: string) => ttsCacheKey({ ...baseKey, text });
    await cache.set(k('satu'), Buffer.alloc(10, 1));
    await sleep(20);
    await cache.set(k('dua'), Buffer.alloc(10, 2));
    await sleep(20);
    assert.ok(await cache.get(k('satu')), 'touching marks the file as recently used');
    await sleep(20);
    await cache.set(k('tiga'), Buffer.alloc(10, 3));
    assert.equal(await cache.get(k('dua')), null, 'least recently used file evicted');
    assert.ok(await cache.get(k('satu')));
    assert.ok(await cache.get(k('tiga')));
    assert.ok((await cache.sizeBytes()) <= 25);
  } finally {
    await fs.rm(dir, { recursive: true, force: true });
  }
});

test('voice routes over HTTP: auth required, 503 NOT_CONFIGURED, size caps', async (t) => {
  let server: TestServer | undefined;
  t.after(() => server?.close());
  const pendingDevice = '00000000-0000-4000-8000-0000000000e1';
  const revokedDevice = '00000000-0000-4000-8000-0000000000e2';
  const deletedDevice = '00000000-0000-4000-8000-0000000000e3';
  server = await startServer(
    createApp({
      principals: testPrincipals({
        users: { [TEST_USER_IDS.teacher]: { role: 'teacher', isActive: false } },
        devices: {
          [pendingDevice]: { approved: false, revoked: false },
          [revokedDevice]: { approved: true, revoked: true },
          [deletedDevice]: null,
        },
      }),
    })
  );
  const base = server.baseUrl;
  const device = bearer(deviceToken());
  const researcher = bearer(userToken('researcher'));

  await t.test('only staff accounts and approved, non-revoked devices may use the paid proxy', async () => {
    const cases: Array<[Record<string, string>, number, string]> = [
      [bearer(deviceToken(pendingDevice)), 403, 'DEVICE_NOT_APPROVED'],
      [bearer(deviceToken(revokedDevice)), 403, 'DEVICE_REVOKED'],
      [bearer(deviceToken(deletedDevice)), 401, 'DEVICE_NOT_REGISTERED'],
      [bearer(userToken('child')), 403, 'FORBIDDEN'],
      [bearer(userToken('student')), 403, 'FORBIDDEN'],
      [bearer(userToken('teacher')), 401, 'ACCOUNT_DISABLED'],
    ];
    for (const [headers, status, code] of cases) {
      const res = await postJson(base, '/api/voice/tts', { text: 'Halo' }, headers);
      assert.equal(res.status, status, code);
      assert.equal(res.body.code, code);
    }
    assert.equal((await postJson(base, '/api/voice/tts', { text: 'Halo' }, bearer(userToken('admin')))).status, 503);
  });

  await t.test('401 without token or with refresh token', async () => {
    for (const path of ['/api/voice/tts', '/api/voice/synthesize', '/api/voice/stt', '/api/voice/transcribe']) {
      assert.equal((await postJson(base, path, { text: 'Halo' })).status, 401, path);
    }
    assert.equal((await getJson(base, '/api/voice/status')).status, 401);
    const refresh = generateUserTokens({ userId: 'u', username: 'u', role: 'admin' }).refreshToken;
    assert.equal((await postJson(base, '/api/voice/tts', { text: 'Halo' }, bearer(refresh))).status, 401);
  });

  await t.test('503 NOT_CONFIGURED for device and user tokens when ElevenLabs is not configured', async () => {
    for (const headers of [device, researcher]) {
      const tts = await postJson(base, '/api/voice/tts', { text: 'Halo', mood: 'warm' }, headers);
      assert.equal(tts.status, 503);
      assert.equal(tts.body.code, 'NOT_CONFIGURED');
    }
    const stt = await fetch(`${base}/api/voice/stt`, {
      method: 'POST',
      headers: { ...device, 'Content-Type': 'audio/wav' },
      body: Buffer.from('RIFF....WAVE'),
    });
    assert.equal(stt.status, 503);
  });

  await t.test('status endpoint reports configuration without secrets', async () => {
    const res = await getJson(base, '/api/voice/status', device);
    assert.equal(res.status, 200);
    assert.equal(res.body.configured, false);
    assert.equal(res.body.defaultVoiceId, null);
    assert.equal(res.body.defaultModelId, 'eleven_multilingual_v2');
    assert.ok(!JSON.stringify(res.body).includes('apiKey'));
  });

  await t.test('400 for invalid TTS input (text > 300 chars, unknown mood)', async () => {
    assert.equal((await postJson(base, '/api/voice/tts', { text: 'a'.repeat(301) }, device)).status, 400);
    assert.equal((await postJson(base, '/api/voice/tts', { text: '' }, device)).status, 400);
    assert.equal((await postJson(base, '/api/voice/tts', { text: 'Halo', mood: 'angry' }, device)).status, 400);
  });

  await t.test('413 when STT audio exceeds MAX_AUDIO_UPLOAD_BYTES (raw and base64)', async () => {
    const raw = await fetch(`${base}/api/voice/stt`, {
      method: 'POST',
      headers: { ...device, 'Content-Type': 'audio/wav' },
      body: Buffer.alloc(config.elevenlabs.maxAudioUploadBytes + 1024),
    });
    assert.equal(raw.status, 413);
    const b64 = await postJson(
      base,
      '/api/voice/transcribe',
      { audioBase64: Buffer.alloc(config.elevenlabs.maxAudioUploadBytes + 1024).toString('base64') },
      device
    );
    assert.equal(b64.status, 413);
    // Body STT besar tanpa token ditolak 401 sebelum dibaca.
    const anonymous = await fetch(`${base}/api/voice/stt`, {
      method: 'POST',
      headers: { 'Content-Type': 'audio/wav' },
      body: Buffer.alloc(1024),
    });
    assert.equal(anonymous.status, 401);
  });
});
