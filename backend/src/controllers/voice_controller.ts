import { AppError } from "../types/errors.js";
import { Request, Response, NextFunction } from 'express';
import { VoiceService } from '../services/voice_service.js';
import { ttsSynthesizeSchema } from '../types/schemas.js';
import { config } from '../config/env.js';

export class VoiceController {
  private service = new VoiceService();

  getStatus = (_req: Request, res: Response): void => {
    res.status(200).json({
      status: 'success',
      configured: this.service.isConfigured(),
      defaultVoiceId: config.elevenlabs.defaultVoiceId,
      defaultModelId: config.elevenlabs.defaultModelId,
    });
  };

  
  transcribe = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      let audioBuffer: Buffer;
      let mimeType = req.headers['content-type'] || 'audio/wav';

      if (Buffer.isBuffer(req.body)) {
        audioBuffer = req.body;
      } else if (req.body && typeof req.body === 'object' && req.body.audioBase64) {
        audioBuffer = Buffer.from(req.body.audioBase64, 'base64');
        if (req.body.mimeType) mimeType = req.body.mimeType;
      } else {
        throw new AppError('Missing audio payload. Send raw binary audio or JSON with audioBase64', 400);
      }

      const languageCode = (req.query.language_code as string) || (req.body?.languageCode as string) || 'id';

      const result = await this.service.transcribe({
        audioBuffer,
        mimeType,
        languageCode,
      });

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
      const data = ttsSynthesizeSchema.parse(req.body);
      const audioBuffer = await this.service.synthesize(data);

      res.setHeader('Content-Type', 'audio/mpeg');
      res.setHeader('Content-Length', audioBuffer.length);
      res.setHeader('Cache-Control', 'public, max-age=86400');
      res.status(200).send(audioBuffer);
    } catch (err) {
      next(err);
    }
  };
}
