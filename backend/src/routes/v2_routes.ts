import { Router } from 'express';
import { V2Controller } from '../controllers/v2_controller.js';
import { AuthMiddlewares, requireRole } from '../middlewares/auth.js';
import { RateLimiters } from '../middlewares/rate_limit.js';
import { validateQuery } from '../middlewares/validate.js';
import { researchQuerySchema } from '../types/schemas.js';

/**
 * API v2 (dipakai aplikasi Flutter "Kogo Belajar"):
 * - POST /devices/register        : publik (rate limit per IP); perangkat lama wajib bukti kepemilikan
 * - POST /sync                    : device token
 * - GET  /research/*              : access token role admin/researcher
 * - /research/devices[/...]       : persetujuan / pencabutan perangkat oleh peneliti
 */
export function createV2Router(limiters: RateLimiters, auth: AuthMiddlewares): Router {
  const router = Router();
  const controller = new V2Controller();

  router.post('/devices/register', limiters.deviceRegister, controller.registerDevice);
  router.post('/sync', auth.requireDevice, limiters.sync, controller.sync);

  const researcher = [auth.requireAuth, requireRole('admin', 'researcher')];
  const researcherQuery = [...researcher, validateQuery(researchQuerySchema)];
  router.get('/research/metrics', ...researcherQuery, controller.metrics);
  router.get('/research/export/attempts.csv', ...researcherQuery, controller.exportAttempts);
  router.get('/research/export/sessions.csv', ...researcherQuery, controller.exportSessions);

  router.get('/research/devices', ...researcher, controller.listDevices);
  router.post('/research/devices/:deviceId/approve', ...researcher, controller.approveDevice);
  router.post('/research/devices/:deviceId/revoke', ...researcher, controller.revokeDevice);
  router.post('/research/devices/:deviceId/reset-credential', ...researcher, controller.resetDeviceCredential);

  return router;
}
