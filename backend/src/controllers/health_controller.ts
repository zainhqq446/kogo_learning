import { Request, Response } from 'express';
import { checkDatabaseHealth } from '../config/database.js';
import { config } from '../config/env.js';

const SERVICE_NAME = 'kogo-voice-learning-backend';

/**
 * Liveness: proses hidup dan melayani HTTP. Tidak menyentuh database dan tidak
 * mengungkap environment / detail internal.
 */
export function getHealthStatus(_req: Request, res: Response): void {
  res.status(200).json({
    status: 'ok',
    service: SERVICE_NAME,
    version: config.server.appVersion,
    timestamp: new Date().toISOString(),
    uptimeSeconds: Math.floor(process.uptime()),
  });
}

/**
 * Readiness: 200 bila PostgreSQL dapat dijangkau, 503 bila tidak.
 * Pesan error database hanya dicatat di log server.
 */
export async function getReadinessStatus(_req: Request, res: Response): Promise<void> {
  const db = await checkDatabaseHealth();
  res.status(db.connected ? 200 : 503).json({
    status: db.connected ? 'ready' : 'not_ready',
    service: SERVICE_NAME,
    timestamp: new Date().toISOString(),
    checks: {
      database: db.connected ? 'up' : 'down',
    },
    ...(db.connected ? { latencyMs: db.latencyMs } : {}),
  });
}
