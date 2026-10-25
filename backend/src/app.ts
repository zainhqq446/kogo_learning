import express, { Express } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { config } from './config/env.js';
import { healthRouter } from './routes/health_routes.js';
import { authRouter } from './routes/auth_routes.js';
import { researchRouter } from './routes/research_routes.js';
import { voiceRouter } from './routes/voice_routes.js';
import { errorHandler, notFoundHandler } from './middlewares/error_handler.js';

export function createApp(): Express {
  const app = express();

  // 1. Keamanan header via Helmet
  app.use(helmet());

  // 2. Cross-Origin Resource Sharing (CORS)
  app.use(
    cors({
      origin: config.server.corsOrigin,
      credentials: true,
      methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
      allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With'],
    })
  );

  // 3. Body parsers
  app.use(express.json({ limit: '10mb' }));
  app.use(express.urlencoded({ extended: true, limit: '10mb' }));
  app.use(express.raw({ type: ['audio/*', 'application/octet-stream'], limit: '10mb' }));

  // 4. API Routes
  app.use(config.server.apiPrefix, healthRouter);
  app.use(config.server.apiPrefix, authRouter);
  app.use(`${config.server.apiPrefix}/research`, researchRouter);
  app.use(config.server.apiPrefix, voiceRouter);

  // 5. 404 & Centralized Error Handler
  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}