import { Router } from 'express';
import { VoiceController } from '../controllers/voice_controller.js';
import { requireAuth } from '../middlewares/auth.js';

export const voiceRouter = Router();
const controller = new VoiceController();

// Voice proxy endpoints protected by JWT Bearer token
voiceRouter.get('/voice/status', requireAuth, controller.getStatus);
voiceRouter.post('/voice/tts', controller.synthesize);
voiceRouter.post('/voice/synthesize', controller.synthesize);
voiceRouter.post('/voice/stt', controller.transcribe);
voiceRouter.post('/voice/transcribe', controller.transcribe);
