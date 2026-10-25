import { config } from '../config/env.js';
import { AppError } from '../types/errors.js';
import { logger } from '../utils/logger.js';

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
}


export interface TranscribeParams {
  audioBuffer: Buffer;
  mimeType?: string;
  languageCode?: string;
  modelId?: string;
}

export interface TranscribeResult {
  text: string;
  languageCode?: string;
  durationSecs?: number;
  words?: Array<{ text: string; start: number; end: number; logprob?: number }>;
}

export class VoiceService {
  isConfigured(): boolean {
    return Boolean(config.elevenlabs.apiKey && config.elevenlabs.apiKey.trim().length > 0);
  }

  
  async transcribe(params: TranscribeParams): Promise<TranscribeResult> {
    if (!this.isConfigured()) {
      throw new AppError('Speech-to-text service is not configured on this server', 503);
    }

    if (!params.audioBuffer || params.audioBuffer.length === 0) {
      throw new AppError('Audio buffer cannot be empty', 400);
    }

    if (params.audioBuffer.length > 10 * 1024 * 1024) {
      throw new AppError('Audio file exceeds maximum allowed size of 10MB', 400);
    }

    const mimeType = params.mimeType || 'audio/wav';
    const ext = mimeType.includes('mpeg') || mimeType.includes('mp3') ? 'mp3' : mimeType.includes('m4a') ? 'm4a' : 'wav';
    const blob = new Blob([params.audioBuffer], { type: mimeType });
    const formData = new FormData();
    formData.append('file', blob, `speech_attempt.${ext}`);
    formData.append('model_id', params.modelId || 'scribe_v1');
    if (params.languageCode) {
      formData.append('language_code', params.languageCode);
    }

    const url = `${config.elevenlabs.baseUrl}/speech-to-text`;
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 15000);

    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'xi-api-key': config.elevenlabs.apiKey!,
        },
        body: formData,
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      if (!response.ok) {
        const errorText = await response.text();
        logger.error(`ElevenLabs STT upstream error HTTP ${response.status}: ${errorText}`);
        throw new AppError('Voice transcription upstream provider error', 502);
      }

      const data = (await response.json()) as any;
      return {
        text: (data.text || '').trim(),
        languageCode: data.language_code,
        durationSecs: data.audio_duration_secs,
        words: data.words,
      };
    } catch (err: unknown) {
      clearTimeout(timeoutId);
      if (err instanceof AppError) throw err;
      const isAbort = err instanceof Error && err.name === 'AbortError';
      if (isAbort) {
        logger.error('ElevenLabs STT upstream request timed out');
        throw new AppError('Voice transcription request timed out', 504);
      }
      logger.error('ElevenLabs transcription unexpected error:', err instanceof Error ? err.message : String(err));
      throw new AppError('Failed to communicate with voice transcription provider', 502);
    }
  }

  async synthesize(params: SynthesizeParams): Promise<Buffer> {
    if (!this.isConfigured()) {
      throw new AppError('Speech synthesis service is not configured on this server', 503);
    }

    const cleanText = params.text.trim();
    if (!cleanText) {
      throw new AppError('Text cannot be empty', 400);
    }
    if (cleanText.length > 500) {
      throw new AppError('Text exceeds maximum allowed length of 500 characters', 400);
    }

    const voiceId = params.voiceId || config.elevenlabs.defaultVoiceId;
    const modelId = params.modelId || config.elevenlabs.defaultModelId;
    const url = `${config.elevenlabs.baseUrl}/text-to-speech/${encodeURIComponent(voiceId)}?output_format=mp3_44100_128`;

    const voiceSettings = params.settings
      ? {
          stability: params.settings.stability ?? 0.4,
          similarity_boost: params.settings.similarityBoost ?? 0.8,
          style: params.settings.style ?? 0.45,
          speed: params.settings.speed ?? 0.98,
          use_speaker_boost: params.settings.useSpeakerBoost ?? true,
        }
      : {
          stability: 0.4,
          similarity_boost: 0.8,
          style: 0.45,
          speed: 0.98,
          use_speaker_boost: true,
        };

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 8000);

    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Accept: 'audio/mpeg',
          'xi-api-key': config.elevenlabs.apiKey!,
        },
        body: JSON.stringify({
          text: cleanText,
          model_id: modelId,
          voice_settings: voiceSettings,
        }),
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      if (!response.ok) {
        logger.error(`ElevenLabs upstream responded with HTTP ${response.status}`);
        throw new AppError('Voice synthesis upstream provider error', 502);
      }

      const arrayBuffer = await response.arrayBuffer();
      return Buffer.from(arrayBuffer);
    } catch (err: unknown) {
      clearTimeout(timeoutId);
      if (err instanceof AppError) throw err;
      const isAbort = err instanceof Error && err.name === 'AbortError';
      if (isAbort) {
        logger.error('ElevenLabs upstream request timed out');
        throw new AppError('Voice synthesis request timed out', 504);
      }
      logger.error('ElevenLabs synthesis unexpected error:', err instanceof Error ? err.message : String(err));
      throw new AppError('Failed to communicate with voice synthesis provider', 502);
    }
  }
}
