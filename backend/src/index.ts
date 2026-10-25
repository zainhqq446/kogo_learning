import { createApp } from './app.js';
import { config } from './config/env.js';
import { logger } from './utils/logger.js';
import { closeDbPool } from './config/database.js';

const app = createApp();

const server = app.listen(config.server.port, () => {
  logger.info(`====================================================`);
  logger.info(`🚀 Kogo Voice Learning Backend Running!`);
  logger.info(`🌐 Environment : ${config.server.nodeEnv}`);
  logger.info(`📡 Port        : ${config.server.port}`);
  logger.info(`🔗 Health API  : http://localhost:${config.server.port}${config.server.apiPrefix}/health`);
  logger.info(`====================================================`);
});

// Penanganan graceful shutdown
async function gracefulShutdown(signal: string) {
  logger.info(`Received ${signal}. Shutting down gracefully...`);
  server.close(async () => {
    logger.info('HTTP server closed.');
    await closeDbPool();
    process.exit(0);
  });

  // Force close jika melebihi 10 detik
  setTimeout(() => {
    logger.error('Could not close connections in time, forcefully shutting down');
    process.exit(1);
  }, 10000);
}

process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));
