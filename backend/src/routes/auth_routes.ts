import { Router } from 'express';
import { AuthController } from '../controllers/auth_controller.js';
import { requireAuth } from '../middlewares/auth.js';

export const authRouter = Router();
const controller = new AuthController();

authRouter.post('/auth/register', controller.register);
authRouter.post('/auth/register/child', controller.registerChild);
authRouter.post('/auth/login', controller.login);
authRouter.post('/auth/logout', requireAuth, controller.logout);
authRouter.get('/auth/me', requireAuth, controller.me);