import { getDbPool, closeDbPool } from '../config/database.js';
import { runStartupTasks } from '../services/startup_service.js';
import { logger } from '../utils/logger.js';
import { config } from '../config/env.js';

/**
 * CLI migrasi: menjalankan migrasi skema, seed data referensi kurikulum
 * (vocabulary.json), dan bootstrap akun admin. Dipakai juga oleh
 * docker-entrypoint.sh sebelum server dijalankan.
 */
async function main(): Promise<void> {
  const target = config.database.connectionString
    ? 'DATABASE_URL'
    : `${config.database.database} @ ${config.database.host}:${config.database.port}`;
  logger.info('====================================================');
  logger.info('Kogo Voice Learning - Database migrations');
  logger.info(`Target database : ${target}`);
  logger.info('====================================================');

  const result = await runStartupTasks(getDbPool());
  logger.info(
    `Done. Migrations applied now: ${result.appliedMigrations.length}, admin bootstrap: ${result.admin}, words seeded: ${result.referenceData.words}.`
  );
}

main()
  .then(async () => {
    await closeDbPool();
    process.exit(0);
  })
  .catch(async (err: unknown) => {
    logger.error(`Migration process aborted: ${err instanceof Error ? err.message : String(err)}`);
    await closeDbPool().catch(() => undefined);
    process.exit(1);
  });
