import { Request, Response } from 'express';
import { checkDatabaseHealth } from '../config/database.js';
import { config } from '../config/env.js';

export async function getHealthStatus(req: Request, res: Response): Promise<void> {
  const dbHealth = await checkDatabaseHealth();

  const isHealthy = true; // Service API aktif dan melayani request
  const responseData = {
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptimeSeconds: Math.floor(process.uptime()),
    environment: config.server.nodeEnv,
    service: 'kogo-voice-learning-backend',
    version: '1.0.0',
    database: {
      provider: 'postgresql',
      connected: dbHealth.connected,
      latencyMs: dbHealth.latencyMs ?? null,
      status: dbHealth.connected ? 'ready' : 'disconnected (lazy check - not blocking)',
      ...(dbHealth.error ? { message: dbHealth.error } : {}),
    },
  };

  res.status(200).json(responseData);
}
