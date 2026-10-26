import { Request, Response, NextFunction } from 'express';
import { AppError, ValidationError } from '../types/errors.js';
import { VoiceService } from '../services/voice_service.js';
import { sttJsonBodySchema, ttsSynthesizeSchema } from '../types/schemas.js';
import { config } from '../config/env.js';

const BASE64_PATTERN = /^[A-Za-z0-9+/]*={0,2}$/;

export class VoiceController {
  constructor(private readonly service: VoiceService = new VoiceService()) {}

  getStatus = (_req: Request, res: Response): void => {
    res.status(200).json({
      status: 'success',
      ...this.service.status(),
    });
  };

  transcribe = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      let audioBuffer: Buffer;
      let mimeType = (req.headers['content-type'] || 'audio/wav').toString();
      let languageCode: string | undefined;

      if (Buffer.isBuffer(req.body)) {
        audioBuffer = req.body;
      } else if (req.body && typeof req.body === 'object' && 'audioBase64' in req.body) {
        const data = sttJsonBodySchema.parse(req.body);
        const base64 = data.audioBase64.replace(/\s+/g, '');
        if (!BASE64_PATTERN.test(base64)) {
          throw new ValidationError('audioBase64 is not valid base64');
        }
        // Tolak sebelum decode bila jelas melebihi batas ukuran.
        if (Math.floor((base64.length * 3) / 4) > config.elevenlabs.maxAudioUploadBytes + 2) {
          throw new AppError('Audio exceeds maximum allowed size', 413, true, undefined, 'PAYLOAD_TOO_LARGE');
        }
        audioBuffer = Buffer.from(base64, 'base64');
        mimeType = data.mimeType ?? 'audio/wav';
        languageCode = data.languageCode;
      } else {
        throw new ValidationError(
          'Missing audio payload. Send raw audio (Content-Type: audio/*) or JSON { audioBase64, mimeType }'
        );
      }

      const queryLanguage = typeof req.query.language_code === 'string' ? req.query.language_code : undefined;
      if (queryLanguage && /^[a-z]{2,3}$/.test(queryLanguage)) {
        languageCode = queryLanguage;
      }

      const result = await this.service.transcribe({ audioBuffer, mimeType, languageCode });

      res.status(200).json({
        status: 'success',
        data: result,
      });
    } catch (err) {
      next(err);
    }
  };

  synthesize = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const data = ttsSynthesizeSchema.parse(req.body ?? {});
      const { audio, cacheHit } = await this.service.synthesize(data);

      res.setHeader('Content-Type', 'audio/mpeg');
      res.setHeader('Content-Length', audio.length);
      res.setHeader('Cache-Control', 'private, max-age=86400');
      res.setHeader('X-Cache', cacheHit ? 'HIT' : 'MISS');
      res.status(200).send(audio);
    } catch (err) {
      next(err);
    }
  };
}
