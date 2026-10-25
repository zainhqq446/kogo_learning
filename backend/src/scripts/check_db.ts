import { checkDatabaseHealth, closeDbPool } from '../config/database.js';
import { config } from '../config/env.js';
import { logger } from '../utils/logger.js';

async function main() {
  logger.info('====================================================');
  logger.info('🔍 Checking PostgreSQL Database Connection');
  logger.info(`Host     : ${config.database.host}`);
  logger.info(`Port     : ${config.database.port}`);
  logger.info(`Database : ${config.database.database}`);
  logger.info(`User     : ${config.database.user}`);
  logger.info(`SSL      : ${config.database.ssl}`);
  logger.info('====================================================');

  const health = await checkDatabaseHealth();

  if (health.connected) {
    logger.info(`✅ PostgreSQL connection SUCCESSFUL! (Latency: ${health.latencyMs}ms)`);
    await closeDbPool();
    process.exit(0);
  } else {
    logger.warn(`❌ PostgreSQL connection FAILED: ${health.error}`);
    logger.info('ℹ️  Tips: Pastikan PostgreSQL service berjalan dan password pada D:\\KogoBackend\\.env sudah sesuai.');
    await closeDbPool();
    process.exit(1);
  }
}

main().catch(async (err) => {
  logger.error('Unexpected error during check:', err);
  await closeDbPool();
  process.exit(1);
});