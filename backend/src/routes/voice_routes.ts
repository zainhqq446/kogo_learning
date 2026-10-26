import express, { Router } from 'express';
import { VoiceController } from '../controllers/voice_controller.js';
import { AuthMiddlewares } from '../middlewares/auth.js';
import { RateLimiters } from '../middlewares/rate_limit.js';
import { config } from '../config/env.js';

export const STT_PATHS = ['/voice/stt', '/voice/transcribe'] as const;
export const TTS_PATHS = ['/voice/tts', '/voice/synthesize'] as const;

/**
 * Proxy ElevenLabs (TTS/STT). Semua route wajib akun staf aktif atau perangkat
 * yang disetujui peneliti, dibatasi rate limit per IP dan per principal,
 * voice/model divalidasi terhadap allowlist, dan biaya dibatasi anggaran harian.
 */
export function createVoiceRouter(limiters: RateLimiters, auth: AuthMiddlewares, controller = new VoiceController()): Router {
  const router = Router();
  const maxAudio = config.elevenlabs.maxAudioUploadBytes;

  // Parser khusus STT: audio mentah hingga MAX_AUDIO_UPLOAD_BYTES, atau JSON
  // base64 (ukuran base64 = 4/3 audio) — hanya setelah autentikasi berhasil.
  const sttRawParser = express.raw({ type: ['audio/*', 'application/octet-stream'], limit: maxAudio });
  const sttJsonParser = express.json({ limit: Math.ceil((maxAudio * 4) / 3) + 16 * 1024 });

  router.get('/voice/status', limiters.voiceIp, auth.requireVoiceAccess, controller.getStatus);
  router.post([...TTS_PATHS], limiters.voiceIp, auth.requireVoiceAccess, limiters.voice, controller.synthesize);
  router.post(
    [...STT_PATHS],
    limiters.voiceIp,
    auth.requireVoiceAccess,
    limiters.voice,
    sttRawParser,
    sttJsonParser,
    controller.transcribe
  );

  return router;
}
