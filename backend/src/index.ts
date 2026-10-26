import { Server } from 'http';
import { createApp } from './app.js';
import { config } from './config/env.js';
import { logger } from './utils/logger.js';
import { closeDbPool, getDbPool } from './config/database.js';
import { runStartupTasks } from './services/startup_service.js';

let server: Server | undefined;
let shuttingDown = false;

async function main(): Promise<void> {
  for (const warning of config.warnings) {
    logger.warn(warning);
  }

  if (config.startup.runMigrationsOnStart) {
    logger.info('Running startup tasks (migrations, reference data, admin bootstrap)...');
    await runStartupTasks(getDbPool());
  } else {
    logger.info('RUN_MIGRATIONS_ON_START=false: skipping migrations/seed/admin bootstrap.');
  }

  const app = createApp();
  server = app.listen(config.server.port, config.server.host, () => {
    logger.info('====================================================');
    logger.info('Kogo Voice Learning Backend running');
    logger.info(`Environment : ${config.server.nodeEnv}`);
    logger.info(`Listening   : ${config.server.host}:${config.server.port}`);
    logger.info(`Health API  : http://localhost:${config.server.port}${config.server.apiPrefix}/health`);
    logger.info('====================================================');
  });

  // Lebih panjang dari idle timeout reverse proxy (Traefik) untuk mencegah 502
  // akibat koneksi keep-alive yang ditutup server lebih dulu.
  server.keepAliveTimeout = 65_000;
  server.headersTimeout = 66_000;
}

// Penanganan graceful shutdown
async function gracefulShutdown(signal: string): Promise<void> {
  if (shuttingDown) return;
  shuttingDown = true;
  logger.info(`Received ${signal}. Shutting down gracefully...`);

  // Force close jika melebihi 10 detik
  setTimeout(() => {
    logger.error('Could not close connections in time, forcefully shutting down');
    process.exit(1);
  }, 10000).unref();

  if (server) {
    await new Promise<void>((resolve) => server!.close(() => resolve()));
    logger.info('HTTP server closed.');
  }
  await closeDbPool();
  process.exit(0);
}

process.on('SIGTERM', () => void gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => void gracefulShutdown('SIGINT'));
process.on('unhandledRejection', (reason) => {
  logger.error('Unhandled promise rejection:', reason instanceof Error ? reason.message : String(reason));
});

main().catch(async (err: unknown) => {
  logger.error(`Startup failed: ${err instanceof Error ? err.message : String(err)}`);
  await closeDbPool().catch(() => undefined);
  process.exit(1);
});
