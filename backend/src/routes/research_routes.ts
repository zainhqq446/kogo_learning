import { Router } from 'express';
import { ResearchController } from '../controllers/research_controller.js';
import { AuthMiddlewares, requireRole } from '../middlewares/auth.js';
import { RateLimiters } from '../middlewares/rate_limit.js';

/**
 * API riset lama (v1). Tetap dipertahankan untuk kompatibilitas; seluruh route
 * mewajibkan access token pengguna dan role yang sesuai.
 */
export function createResearchRouter(limiters: RateLimiters, auth: AuthMiddlewares): Router {
  const router = Router();
  const controller = new ResearchController();

  // Seluruh route research mewajibkan autentikasi (requireAuth)
  router.use(auth.requireAuth);

  // 1. Peserta Penelitian (Pseudonim)
  router.get('/participants', requireRole('admin', 'researcher', 'teacher'), controller.listParticipants);
  router.post('/participants', requireRole('admin', 'researcher'), controller.createParticipant);
  router.post('/participants/batch', requireRole('admin', 'researcher'), controller.batchImportParticipants);
  router.get('/participants/:code', requireRole('admin', 'researcher', 'teacher'), controller.getParticipant);

  // 2. Perangkat Penelitian (Devices)
  router.get('/devices', requireRole('admin', 'researcher'), controller.listDevices);
  router.post('/devices', requireRole('admin', 'researcher', 'teacher'), controller.registerDevice);

  // 3. Sesi Penelitian (Sessions)
  router.get('/sessions', requireRole('admin', 'researcher', 'teacher'), controller.listSessions);
  router.post('/sessions', requireRole('admin', 'researcher', 'teacher'), controller.createSession);

  // 4. Percobaan Suara & Evaluasi Kemiripan (Attempts & Evaluations)
  router.get('/attempts', requireRole('admin', 'researcher'), controller.listAttempts);
  router.post('/attempts', requireRole('admin', 'researcher', 'teacher'), controller.recordAttempt);

  // 5. Agregasi & Summary Penelitian
  router.get('/summary', requireRole('admin', 'researcher'), controller.getSummary);

  // 6. Offline-to-Online Batch Sync (lama)
  router.post('/sync/batch', requireRole('admin', 'researcher', 'teacher'), limiters.sync, controller.syncBatch);

  return router;
}
