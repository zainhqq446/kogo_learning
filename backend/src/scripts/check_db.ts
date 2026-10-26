import { checkDatabaseHealth, closeDbPool } from '../config/database.js';
import { config } from '../config/env.js';
import { logger } from '../utils/logger.js';

async function main() {
  logger.info('====================================================');
  logger.info('Checking PostgreSQL database connection');
  if (config.database.connectionString) {
    logger.info('Source   : DATABASE_URL');
  } else {
    logger.info(`Host     : ${config.database.host}`);
    logger.info(`Port     : ${config.database.port}`);
    logger.info(`Database : ${config.database.database}`);
    logger.info(`User     : ${config.database.user}`);
  }
  logger.info(`SSL      : ${config.database.ssl}`);
  logger.info('====================================================');

  const health = await checkDatabaseHealth();

  if (health.connected) {
    logger.info(`PostgreSQL connection SUCCESSFUL (latency: ${health.latencyMs}ms)`);
    await closeDbPool();
    process.exit(0);
  } else {
    logger.warn('PostgreSQL connection FAILED (see the warning above for details).');
    logger.info('Tip: verify DATABASE_URL or DB_* variables in backend/.env and that PostgreSQL is running.');
    await closeDbPool();
    process.exit(1);
  }
}

main().catch(async (err) => {
  logger.error('Unexpected error during check:', err instanceof Error ? err.message : String(err));
  await closeDbPool();
  process.exit(1);
});
