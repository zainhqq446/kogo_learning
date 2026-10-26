import { Router } from 'express';
import { AuthController } from '../controllers/auth_controller.js';
import { AuthMiddlewares, requireRole } from '../middlewares/auth.js';
import { RateLimiters } from '../middlewares/rate_limit.js';

export function createAuthRouter(limiters: RateLimiters, auth: AuthMiddlewares): Router {
  const router = Router();
  const controller = new AuthController();

  // Tidak ada registrasi publik: akun dibuat oleh staf yang login (admin untuk
  // akun staf; admin/researcher/teacher untuk akun anak). Akun admin pertama
  // berasal dari ADMIN_USERNAME/ADMIN_PASSWORD. Aplikasi v2 memakai perangkat
  // + learners, bukan akun pengguna.
  const staff = [auth.requireAuth, requireRole('admin', 'researcher', 'teacher')];
  router.post('/auth/register', limiters.auth, ...staff, controller.register);
  router.post('/auth/register/child', limiters.auth, ...staff, controller.registerChild);
  router.post('/auth/login', limiters.auth, controller.login);
  router.post('/auth/logout', auth.requireAuth, controller.logout);
  router.get('/auth/me', auth.requireAuth, controller.me);

  return router;
}
