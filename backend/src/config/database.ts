import { Pool, PoolConfig } from 'pg';
import { config } from './env.js';
import { logger } from '../utils/logger.js';

let pool: Pool | null = null;

export function getPoolConfig(): PoolConfig {
  return {
    host: config.database.host,
    port: config.database.port,
    database: config.database.database,
    user: config.database.user,
    password: config.database.password,
    ssl: config.database.ssl ? { rejectUnauthorized: false } : false,
    max: config.database.maxConnections,
    idleTimeoutMillis: config.database.idleTimeoutMillis,
    connectionTimeoutMillis: config.database.connectionTimeoutMillis,
  };
}

/**
 * Inisialisasi pool PostgreSQL secara lazy.
 * Tidak melempar error saat aplikasi startup jika DB belum siap.
 */
export function getDbPool(): Pool {
  if (!pool) {
    pool = new Pool(getPoolConfig());

    pool.on('error', (err) => {
      logger.error('Unexpected error on idle PostgreSQL client:', err.message);
    });
  }
  return pool;
}

export interface DbHealthResult {
  connected: boolean;
  latencyMs?: number;
  error?: string;
}

/**
 * Uji koneksi aktif ke PostgreSQL tanpa menghentikan server bila gagal.
 */
export async function checkDatabaseHealth(): Promise<DbHealthResult> {
  const currentPool = getDbPool();
  const startTime = Date.now();

  try {
    const client = await currentPool.connect();
    try {
      await client.query('SELECT 1');
      const latencyMs = Date.now() - startTime;
      return { connected: true, latencyMs };
    } finally {
      client.release();
    }
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    logger.warn(`PostgreSQL health check failed (lazy check): ${errorMsg}`);
    return { connected: false, error: errorMsg };
  }
}

/**
 * Menutup pool saat server shutdown.
 */
export async function closeDbPool(): Promise<void> {
  if (pool) {
    await pool.end();
    pool = null;
    logger.info('PostgreSQL connection pool closed.');
  }
}

export function setDbPool(customPool: Pool): void {
  pool = customPool;
}