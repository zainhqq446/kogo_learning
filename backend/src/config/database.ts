import { Pool, PoolConfig } from 'pg';
import { config, DatabaseConfig } from './env.js';
import { logger } from '../utils/logger.js';

let pool: Pool | null = null;

/**
 * Membangun konfigurasi pool PostgreSQL dari DATABASE_URL (prioritas) atau DB_*.
 * Saat DB_SSL aktif, sertifikat server diverifikasi kecuali
 * DB_SSL_REJECT_UNAUTHORIZED=false secara eksplisit.
 */
export function getPoolConfig(dbConfig: DatabaseConfig = config.database): PoolConfig {
  const ssl = dbConfig.ssl ? { rejectUnauthorized: dbConfig.sslRejectUnauthorized } : false;
  const common: PoolConfig = {
    ssl,
    max: dbConfig.maxConnections,
    idleTimeoutMillis: dbConfig.idleTimeoutMillis,
    connectionTimeoutMillis: dbConfig.connectionTimeoutMillis,
    application_name: 'kogo-backend',
  };

  if (dbConfig.connectionString) {
    return { ...common, connectionString: dbConfig.connectionString };
  }

  return {
    ...common,
    host: dbConfig.host,
    port: dbConfig.port,
    database: dbConfig.database,
    user: dbConfig.user,
    password: dbConfig.password,
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
}

/**
 * Uji koneksi aktif ke PostgreSQL. Detail error hanya dicatat di log server,
 * tidak pernah dikembalikan ke klien.
 */
export async function checkDatabaseHealth(targetPool: Pool = getDbPool()): Promise<DbHealthResult> {
  const startTime = Date.now();

  try {
    const client = await targetPool.connect();
    try {
      await client.query('SELECT 1');
      return { connected: true, latencyMs: Date.now() - startTime };
    } finally {
      client.release();
    }
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    logger.warn(`PostgreSQL health check failed: ${errorMsg}`);
    return { connected: false };
  }
}

/**
 * Menunggu database siap (dipakai saat startup container agar tidak gagal
 * ketika PostgreSQL masih booting).
 */
export async function waitForDatabase(targetPool: Pool, maxWaitSeconds: number): Promise<boolean> {
  const deadline = Date.now() + maxWaitSeconds * 1000;
  let attempt = 0;
  for (;;) {
    attempt += 1;
    const health = await checkDatabaseHealth(targetPool);
    if (health.connected) return true;
    if (Date.now() >= deadline) return false;
    logger.info(`Waiting for PostgreSQL (attempt ${attempt})...`);
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }
}

/**
 * Menutup pool saat server shutdown.
 */
export async function closeDbPool(): Promise<void> {
  if (pool) {
    const current = pool;
    pool = null;
    await current.end();
    logger.info('PostgreSQL connection pool closed.');
  }
}

export function setDbPool(customPool: Pool): void {
  pool = customPool;
}
