import { config, ElevenLabsConfig } from '../config/env.js';
import { AppError, ServiceUnavailableError, ValidationError } from '../types/errors.js';
import { TtsMood } from '../types/schemas.js';
import { logger } from '../utils/logger.js';
import { TtsDiskCache, ttsCacheKey } from './tts_cache.js';
import { DbVoiceUsageBudget, VoiceUsageBudget } from './voice_budget.js';

export interface TtsSettings {
  stability?: number;
  similarityBoost?: number;
  style?: number;
  speed?: number;
  useSpeakerBoost?: boolean;
}

export interface SynthesizeParams {
  text: string;
  voiceId?: string;
  modelId?: string;
  settings?: TtsSettings;
  mood?: TtsMood;
}

export interface SynthesizeResult {
  audio: Buffer;
  cacheHit: boolean;
}

export interface TranscribeParams {
  audioBuffer: Buffer;
  mimeType?: string;
  languageCode?: string;
}

export interface TranscribeResult {
  text: string;
  languageCode?: string;
  durationSecs?: number;
  words?: Array<{ text: string; start: number; end: number; logprob?: number }>;
}

/** voice_settings ElevenLabs (snake_case sesuai API). */
export interface ElevenLabsVoiceSettings {
  stability: number;
  similarity_boost: number;
  style: number;
  speed: number;
  use_speaker_boost: boolean;
}

interface MoodProfile {
  stability: number;
  style: number;
  speed: number;
}

/**
 * Variasi intonasi untuk suara pemandu anak. Stability rendah + style tinggi =
 * lebih ekspresif (merayakan jawaban benar); stability tinggi + style rendah =
 * lebih tenang dan jelas (menyemangati setelah jawaban salah).
 */
export const DEFAULT_VOICE_PROFILE: MoodProfile = { stability: 0.45, style: 0.4, speed: 0.95 };

export const MOOD_PROFILES: Record<TtsMood, MoodProfile> = {
  excited: { stability: 0.3, style: 0.6, speed: 1.0 },
  celebratory: { stability: 0.3, style: 0.6, speed: 1.0 },
  playful: { stability: 0.35, style: 0.55, speed: 1.0 },
  curious: { stability: 0.4, style: 0.5, speed: 0.97 },
  warm: { stability: 0.5, style: 0.35, speed: 0.95 },
  encouraging: { stability: 0.45, style: 0.45, speed: 0.97 },
  gentle: { stability: 0.6, style: 0.2, speed: 0.92 },
  patient: { stability: 0.6, style: 0.2, speed: 0.9 },
};

const round2 = (value: number) => Math.round(value * 100) / 100;

/**
 * Override `settings` dari klien dibulatkan ke grid kasar (0,1; speed 0,05)
 * sehingga ruang kunci cache tetap kecil: variasi angka kecil tidak bisa
 * dipakai untuk memaksa cache miss (panggilan berbayar) berulang-ulang.
 */
export const SETTINGS_STEP = 0.1;
export const SPEED_STEP = 0.05;
const snap = (value: number, step: number) => round2(Math.round(value / step) * step);

/**
 * Menggabungkan profil mood dengan override eksplisit dari klien (override menang).
 */
export function resolveVoiceSettings(mood?: TtsMood, overrides?: TtsSettings): ElevenLabsVoiceSettings {
  const profile = mood ? MOOD_PROFILES[mood] : DEFAULT_VOICE_PROFILE;
  return {
    stability: overrides?.stability !== undefined ? snap(overrides.stability, SETTINGS_STEP) : round2(profile.stability),
    similarity_boost: overrides?.similarityBoost !== undefined ? snap(overrides.similarityBoost, SETTINGS_STEP) : 0.8,
    style: overrides?.style !== undefined ? snap(overrides.style, SETTINGS_STEP) : round2(profile.style),
    speed: overrides?.speed !== undefined ? snap(overrides.speed, SPEED_STEP) : round2(profile.speed),
    use_speaker_boost: overrides?.useSpeakerBoost ?? true,
  };
}

/**
 * Perkiraan konservatif durasi audio untuk reservasi anggaran STT sebelum
 * upload (~16 kbit/s, bitrate terendah yang wajar untuk ucapan terkompresi).
 * Setelah respons, reservasi dikoreksi ke `audio_duration_secs` dari provider.
 */
export function estimateAudioSeconds(bytes: number): number {
  return Math.min(3600, Math.max(1, Math.ceil(bytes / 2000)));
}

/**
 * Model multilingual_v2 tidak mendukung `language_code` (bahasa dideteksi dari
 * teks). Model Flash/Turbo v2.5 dan v3 menerima `language_code: 'id'`.
 */
const MODELS_WITHOUT_LANGUAGE_CODE = new Set(['eleven_multilingual_v2', 'eleven_multilingual_v1', 'eleven_monolingual_v1']);

export function languageCodeForModel(modelId: string, languageCode: string): string | null {
  return MODELS_WITHOUT_LANGUAGE_CODE.has(modelId) ? null : languageCode;
}

const ALLOWED_AUDIO_MIME = /^(audio\/[a-z0-9.+-]+|application\/octet-stream)$/i;

function audioExtension(mimeType: string): string {
  const mime = mimeType.toLowerCase();
  if (mime.includes('mpeg') || mime.includes('mp3')) return 'mp3';
  if (mime.includes('mp4') || mime.includes('m4a') || mime.includes('aac')) return 'm4a';
  if (mime.includes('ogg') || mime.includes('opus')) return 'ogg';
  if (mime.includes('webm')) return 'webm';
  if (mime.includes('3gpp') || mime.includes('amr')) return '3gp';
  return 'wav';
}

/**
 * Menjalankan fetch dengan batas waktu yang tetap aktif sampai body selesai
 * dibaca (bukan hanya sampai header diterima).
 */
async function fetchWithTimeout<T>(
  url: string,
  init: RequestInit,
  timeoutMs: number,
  read: (response: Response) => Promise<T>
): Promise<{ response: Response; body: T }> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, { ...init, signal: controller.signal });
    const body = await read(response);
    return { response, body };
  } finally {
    clearTimeout(timer);
  }
}

function isAbortError(err: unknown): boolean {
  return err instanceof Error && (err.name === 'AbortError' || err.name === 'TimeoutError');
}

function budgetExhausted(kind: 'speech synthesis' | 'transcription'): AppError {
  return new AppError(
    `Daily voice ${kind} budget is exhausted. The app should fall back to on-device speech.`,
    503,
    true,
    undefined,
    'VOICE_BUDGET_EXHAUSTED'
  );
}

export class VoiceService {
  private readonly cache: TtsDiskCache;
  private readonly budget: VoiceUsageBudget;

  constructor(
    private readonly cfg: ElevenLabsConfig = config.elevenlabs,
    cache?: TtsDiskCache,
    budget?: VoiceUsageBudget
  ) {
    this.cache = cache ?? new TtsDiskCache(cfg.ttsCacheDir, cfg.ttsCacheEnabled, cfg.ttsCacheMaxBytes);
    this.budget = budget ?? new DbVoiceUsageBudget();
  }

  /** Refund reservasi anggaran (best effort; tidak pernah menutupi error asli). */
  private async refund(metric: 'tts_chars' | 'stt_seconds', amount: number): Promise<void> {
    try {
      await this.budget.adjust(metric, -amount);
    } catch (err) {
      logger.warn(`Voice budget refund failed: ${err instanceof Error ? err.message : String(err)}`);
    }
  }

  hasApiKey(): boolean {
    return this.cfg.apiKey.trim().length > 0;
  }

  isTtsConfigured(): boolean {
    return this.hasApiKey() && this.cfg.defaultVoiceId.length > 0;
  }

  isSttConfigured(): boolean {
    return this.hasApiKey();
  }

  status() {
    return {
      configured: this.isTtsConfigured() && this.isSttConfigured(),
      ttsConfigured: this.isTtsConfigured(),
      sttConfigured: this.isSttConfigured(),
      defaultVoiceId: this.cfg.defaultVoiceId || null,
      defaultModelId: this.cfg.defaultModelId,
      sttModelId: this.cfg.sttModelId,
      allowedVoiceIds: this.cfg.allowedVoiceIds,
      allowedModelIds: this.cfg.allowedModelIds,
      languageCode: this.cfg.languageCode,
      maxTextLength: this.cfg.ttsMaxTextLength,
      maxAudioUploadBytes: this.cfg.maxAudioUploadBytes,
      dailyTtsCharBudget: this.cfg.dailyTtsCharBudget,
      dailySttSecondsBudget: this.cfg.dailySttSecondsBudget,
      moods: Object.keys(MOOD_PROFILES),
    };
  }

  /** Memvalidasi voice/model terhadap allowlist server (default = nilai default saja). */
  resolveVoiceAndModel(voiceId?: string, modelId?: string): { voiceId: string; modelId: string } {
    const resolvedVoice = voiceId ?? this.cfg.defaultVoiceId;
    const resolvedModel = modelId ?? this.cfg.defaultModelId;
    if (!this.cfg.allowedVoiceIds.includes(resolvedVoice)) {
      throw new AppError('Requested voiceId is not allowed on this server', 400, true, undefined, 'VOICE_NOT_ALLOWED');
    }
    if (!this.cfg.allowedModelIds.includes(resolvedModel)) {
      throw new AppError('Requested modelId is not allowed on this server', 400, true, undefined, 'MODEL_NOT_ALLOWED');
    }
    return { voiceId: resolvedVoice, modelId: resolvedModel };
  }

  async synthesize(params: SynthesizeParams): Promise<SynthesizeResult> {
    if (!this.isTtsConfigured()) {
      throw new ServiceUnavailableError('Speech synthesis service is not configured on this server', 'NOT_CONFIGURED');
    }

    const cleanText = params.text.trim().replace(/\s+/g, ' ');
    if (!cleanText) {
      throw new ValidationError('Text cannot be empty');
    }
    if (cleanText.length > this.cfg.ttsMaxTextLength) {
      throw new ValidationError(`Text exceeds maximum allowed length of ${this.cfg.ttsMaxTextLength} characters`);
    }

    const { voiceId, modelId } = this.resolveVoiceAndModel(params.voiceId, params.modelId);
    const voiceSettings = resolveVoiceSettings(params.mood, params.settings);
    const languageCode = languageCodeForModel(modelId, this.cfg.languageCode);

    const cacheKey = ttsCacheKey({
      text: cleanText,
      voiceId,
      modelId,
      settings: { ...voiceSettings },
      languageCode,
      outputFormat: this.cfg.outputFormat,
      textNormalization: this.cfg.textNormalization,
    });

    const cached = await this.cache.get(cacheKey);
    if (cached) {
      return { audio: cached, cacheHit: true };
    }

    // Cache miss = panggilan berbayar: reservasi anggaran karakter harian dulu.
    const chargedChars = cleanText.length;
    if (!(await this.budget.tryReserve('tts_chars', chargedChars, this.cfg.dailyTtsCharBudget))) {
      logger.warn('ElevenLabs daily TTS character budget exhausted');
      throw budgetExhausted('speech synthesis');
    }

    const url = `${this.cfg.baseUrl}/text-to-speech/${encodeURIComponent(voiceId)}?output_format=${encodeURIComponent(
      this.cfg.outputFormat
    )}`;
    const requestBody: Record<string, unknown> = {
      text: cleanText,
      model_id: modelId,
      voice_settings: voiceSettings,
      apply_text_normalization: this.cfg.textNormalization,
    };
    if (languageCode) requestBody.language_code = languageCode;

    try {
      const { response, body } = await fetchWithTimeout(
        url,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Accept: 'audio/mpeg',
            'xi-api-key': this.cfg.apiKey,
          },
          body: JSON.stringify(requestBody),
        },
        this.cfg.ttsTimeoutMs,
        async (res) => (res.ok ? Buffer.from(await res.arrayBuffer()) : await res.text())
      );

      if (!response.ok || typeof body === 'string') {
        logger.error(`ElevenLabs TTS upstream responded with HTTP ${response.status}`);
        if (response.status === 429) {
          throw new AppError('Voice provider is busy, please retry shortly', 503, true, undefined, 'UPSTREAM_RATE_LIMITED');
        }
        throw new AppError('Voice synthesis upstream provider error', 502, true, undefined, 'UPSTREAM_ERROR');
      }
      if (body.length === 0) {
        throw new AppError('Voice synthesis returned empty audio', 502, true, undefined, 'UPSTREAM_ERROR');
      }

      await this.cache.set(cacheKey, body);
      return { audio: body, cacheHit: false };
    } catch (err: unknown) {
      await this.refund('tts_chars', chargedChars);
      if (err instanceof AppError) throw err;
      if (isAbortError(err)) {
        logger.error('ElevenLabs TTS upstream request timed out');
        throw new AppError('Voice synthesis request timed out', 504, true, undefined, 'UPSTREAM_TIMEOUT');
      }
      logger.error('ElevenLabs synthesis unexpected error:', err instanceof Error ? err.message : String(err));
      throw new AppError('Failed to communicate with voice synthesis provider', 502, true, undefined, 'UPSTREAM_ERROR');
    }
  }

  async transcribe(params: TranscribeParams): Promise<TranscribeResult> {
    if (!this.isSttConfigured()) {
      throw new ServiceUnavailableError('Speech-to-text service is not configured on this server', 'NOT_CONFIGURED');
    }

    if (!params.audioBuffer || params.audioBuffer.length === 0) {
      throw new ValidationError('Audio buffer cannot be empty');
    }
    if (params.audioBuffer.length > this.cfg.maxAudioUploadBytes) {
      throw new AppError(
        `Audio exceeds maximum allowed size of ${this.cfg.maxAudioUploadBytes} bytes`,
        413,
        true,
        undefined,
        'PAYLOAD_TOO_LARGE'
      );
    }

    const mimeType = (params.mimeType || 'audio/wav').split(';')[0].trim();
    if (!ALLOWED_AUDIO_MIME.test(mimeType)) {
      throw new AppError('Unsupported audio content type', 415, true, undefined, 'UNSUPPORTED_MEDIA_TYPE');
    }

    const reservedSeconds = estimateAudioSeconds(params.audioBuffer.length);
    if (!(await this.budget.tryReserve('stt_seconds', reservedSeconds, this.cfg.dailySttSecondsBudget))) {
      logger.warn('ElevenLabs daily STT seconds budget exhausted');
      throw budgetExhausted('transcription');
    }

    const formData = new FormData();
    formData.append('file', new Blob([new Uint8Array(params.audioBuffer)], { type: mimeType }), `speech_attempt.${audioExtension(mimeType)}`);
    formData.append('model_id', this.cfg.sttModelId);
    formData.append('language_code', params.languageCode || this.cfg.languageCode);
    formData.append('tag_audio_events', 'false');

    try {
      const { response, body } = await fetchWithTimeout(
        `${this.cfg.baseUrl}/speech-to-text`,
        {
          method: 'POST',
          headers: { 'xi-api-key': this.cfg.apiKey },
          body: formData,
        },
        this.cfg.sttTimeoutMs,
        async (res) => (res.ok ? ((await res.json()) as Record<string, unknown>) : await res.text())
      );

      if (!response.ok || typeof body === 'string') {
        logger.error(`ElevenLabs STT upstream error HTTP ${response.status}`);
        if (response.status === 429) {
          throw new AppError('Voice provider is busy, please retry shortly', 503, true, undefined, 'UPSTREAM_RATE_LIMITED');
        }
        throw new AppError('Voice transcription upstream provider error', 502, true, undefined, 'UPSTREAM_ERROR');
      }

      // Koreksi reservasi ke durasi sebenarnya yang ditagih provider.
      const actualSeconds = typeof body.audio_duration_secs === 'number' ? Math.ceil(body.audio_duration_secs) : reservedSeconds;
      if (actualSeconds !== reservedSeconds) {
        await this.budget.adjust('stt_seconds', actualSeconds - reservedSeconds).catch((err: unknown) => {
          logger.warn(`Voice budget adjustment failed: ${err instanceof Error ? err.message : String(err)}`);
        });
      }

      return {
        text: String(body.text ?? '').trim(),
        languageCode: typeof body.language_code === 'string' ? body.language_code : undefined,
        durationSecs: typeof body.audio_duration_secs === 'number' ? body.audio_duration_secs : undefined,
        words: Array.isArray(body.words) ? (body.words as TranscribeResult['words']) : undefined,
      };
    } catch (err: unknown) {
      await this.refund('stt_seconds', reservedSeconds);
      if (err instanceof AppError) throw err;
      if (isAbortError(err)) {
        logger.error('ElevenLabs STT upstream request timed out');
        throw new AppError('Voice transcription request timed out', 504, true, undefined, 'UPSTREAM_TIMEOUT');
      }
      logger.error('ElevenLabs transcription unexpected error:', err instanceof Error ? err.message : String(err));
      throw new AppError('Failed to communicate with voice transcription provider', 502, true, undefined, 'UPSTREAM_ERROR');
    }
  }
}
