import { getDbPool, checkDatabaseHealth, closeDbPool } from '../config/database.js';
import { CurriculumService } from '../services/curriculum_service.js';
import { logger } from '../utils/logger.js';
import { config } from '../config/env.js';

async function main() {
  logger.info('====================================================');
  logger.info('Kogo Voice Learning - Curriculum Seeder');
  logger.info(
    'Target Database : ' +
      (config.database.connectionString
        ? 'DATABASE_URL'
        : config.database.database + ' @ ' + config.database.host + ':' + config.database.port)
  );
  logger.info('====================================================');

  // 1. Cek koneksi database
  const health = await checkDatabaseHealth();
  if (!health.connected) {
    logger.error('Cannot connect to database (see the warning above for details).');
    logger.info('Please verify your .env configuration and database service status.');
    await closeDbPool();
    process.exit(1);
  }

  const pool = getDbPool();
  const service = new CurriculumService(pool);

  try {
    const result = await service.seedCurriculum();
    if (result.alreadySeeded) {
      logger.info('Curriculum is already up to date. No changes needed.');
      logger.info('Totals -> Stages: ' + result.stagesTotal + ', Lessons: ' + result.lessonsTotal + ', Questions: ' + result.questionsTotal);
    } else {
      logger.info('Successfully seeded curriculum!');
      logger.info('Inserted -> Stages: ' + result.insertedStages + ', Lessons: ' + result.insertedLessons + ', Questions: ' + result.insertedQuestions);
      logger.info('Totals   -> Stages: ' + result.stagesTotal + ', Lessons: ' + result.lessonsTotal + ', Questions: ' + result.questionsTotal);
    }
  } catch (err: unknown) {
    const errorMsg = err instanceof Error ? err.message : String(err);
    logger.error('Curriculum seeding failed: ' + errorMsg);
    await closeDbPool();
    process.exit(1);
  }

  await closeDbPool();
  process.exit(0);
}

main().catch(async (err) => {
  logger.error('Unexpected seeding error:', err);
  await closeDbPool();
  process.exit(1);
});
