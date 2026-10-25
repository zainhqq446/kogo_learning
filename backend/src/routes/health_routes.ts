import { Router } from 'express';
import { getHealthStatus } from '../controllers/health_controller.js';

export const healthRouter = Router();

healthRouter.get('/health', getHealthStatus);
