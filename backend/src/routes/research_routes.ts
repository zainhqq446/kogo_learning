import { Router } from 'express';
import { ResearchController } from '../controllers/research_controller.js';
import { requireAuth, requireRole } from '../middlewares/auth.js';

export const researchRouter = Router();
const controller = new ResearchController();

// Seluruh route research mewajibkan autentikasi (requireAuth)
researchRouter.use(requireAuth);

// 1. Peserta Penelitian (Pseudonim)
researchRouter.get('/participants', requireRole('admin', 'researcher', 'teacher'), controller.listParticipants);
researchRouter.post('/participants', requireRole('admin', 'researcher'), controller.createParticipant);
researchRouter.post('/participants/batch', requireRole('admin', 'researcher'), controller.batchImportParticipants);
researchRouter.get('/participants/:code', requireRole('admin', 'researcher', 'teacher'), controller.getParticipant);

// 2. Perangkat Penelitian (Devices)
researchRouter.get('/devices', requireRole('admin', 'researcher'), controller.listDevices);
researchRouter.post('/devices', requireRole('admin', 'researcher', 'teacher'), controller.registerDevice);

// 3. Sesi Penelitian (Sessions)
researchRouter.get('/sessions', requireRole('admin', 'researcher', 'teacher'), controller.listSessions);
researchRouter.post('/sessions', requireRole('admin', 'researcher', 'teacher'), controller.createSession);

// 4. Percobaan Suara & Evaluasi Kemiripan (Attempts & Evaluations)
researchRouter.get('/attempts', requireRole('admin', 'researcher'), controller.listAttempts);
researchRouter.post('/attempts', requireRole('admin', 'researcher', 'teacher'), controller.recordAttempt);

// 5. Agregasi & Summary Penelitian
researchRouter.get('/summary', requireRole('admin', 'researcher'), controller.getSummary);

// 6. Offline-to-Online Batch Sync
researchRouter.post('/sync/batch', requireRole('admin', 'researcher', 'teacher'), controller.syncBatch);