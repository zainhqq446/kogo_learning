/**
 * Environment deterministik untuk test. HARUS menjadi import pertama di setiap
 * file test agar dievaluasi sebelum `config/env.ts` membaca process.env
 * (ESM mengevaluasi import sesuai urutan deklarasi).
 *
 * - ElevenLabs selalu dikosongkan agar test tidak pernah memanggil API berbayar.
 * - Admin bootstrap dari .env developer diabaikan.
 */
import os from 'os';
import path from 'path';

export const TEST_JWT_SECRET = 'kogo-test-only-jwt-secret-0123456789abcdef-0123456789';

process.env.NODE_ENV = 'test';
process.env.JWT_SECRET = TEST_JWT_SECRET;
process.env.JWT_EXPIRES_IN = '15m';
process.env.DEVICE_TOKEN_TTL = '180d';
process.env.BCRYPT_SALT_ROUNDS = '4';
process.env.ELEVENLABS_API_KEY = '';
process.env.ELEVENLABS_DEFAULT_VOICE_ID = '';
process.env.ELEVENLABS_ALLOWED_VOICE_IDS = '';
process.env.ELEVENLABS_ALLOWED_MODEL_IDS = '';
process.env.ADMIN_USERNAME = '';
process.env.ADMIN_PASSWORD = '';
process.env.CORS_ORIGIN = '';
delete process.env.TRUST_PROXY; // default: loopback, linklocal, uniquelocal
process.env.DEVICE_ENROLLMENT_KEY = '';
process.env.RATE_LIMIT_ENABLED = 'true';
process.env.RUN_MIGRATIONS_ON_START = 'false';
process.env.MAX_AUDIO_UPLOAD_BYTES = String(2 * 1024 * 1024);
process.env.TTS_CACHE_DIR = path.join(os.tmpdir(), `kogo-tts-cache-test-${process.pid}`);
process.env.HOST = '127.0.0.1';
