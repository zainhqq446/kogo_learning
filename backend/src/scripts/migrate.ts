import path from 'path';
import { fileURLToPath } from 'url';
import { getDbPool, checkDatabaseHealth, closeDbPool } from '../config/database.js';
import { runMigrations, getAppliedMigrations } from '../services/migrator.js';
import { logger } from '../utils/logger.js';
import { config } from '../config/env.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {
  logger.info('====================================================');
  logger.info('🚀 Kogo Voice Learning Database Migrations CLI');
  logger.info(`Target Database : ${config.database.database} @ ${config.database.host}:${config.database.port}`);
  logger.info('====================================================');

  // 1. Cek kesehatan koneksi terlebih dahulu
  const health = await checkDatabaseHealth();
  if (!health.connected) {
    logger.error(`Cannot connect to database: ${health.error}`);
    logger.info('Please verify your .env configuration and database service status.');
    await closeDbPool();
    process.exit(1);
  }

  // 2. Jalankan migrasi
  const migrationsDir = path.resolve(__dirname, '../../migrations');
  const pool = getDbPool();

  try {
    const applied = await runMigrations(pool, migrationsDir);
    if (applied.length === 0) {
      logger.info('✨ No new migrations to apply. Database schema is already up to date.');
    } else {
      logger.info(`🎉 Successfully applied ${applied.length} migration(s): ${applied.join(', ')}`);
    }
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    logger.error(`Migration process aborted: ${errorMsg}`);
    await closeDbPool();
    process.exit(1);
  }

  await closeDbPool();
  process.exit(0);
}

main().catch(async (err) => {
  logger.error('Unexpected migration failure:', err);
  await closeDbPool();
  process.exit(1);
});