import { Router } from 'express';
import { getHealthStatus, getReadinessStatus } from '../controllers/health_controller.js';

export const healthRouter = Router();

// Liveness (tanpa database, tanpa detail internal)
healthRouter.get('/health', getHealthStatus);
// Readiness (503 bila PostgreSQL tidak dapat dijangkau)
healthRouter.get('/health/ready', getReadinessStatus);
