import express, { Express, RequestHandler } from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { config } from './config/env.js';
import { healthRouter } from './routes/health_routes.js';
import { createAuthRouter } from './routes/auth_routes.js';
import { createResearchRouter } from './routes/research_routes.js';
import { createVoiceRouter, STT_PATHS } from './routes/voice_routes.js';
import { createV2Router } from './routes/v2_routes.js';
import { createRateLimiters, RateLimiters } from './middlewares/rate_limit.js';
import { createAuthMiddlewares } from './middlewares/auth.js';
import { PrincipalStore } from './services/principal_store.js';
import { VoiceController } from './controllers/voice_controller.js';
import { errorHandler, notFoundHandler } from './middlewares/error_handler.js';

export interface CreateAppOptions {
  /** Override rate limiter (misalnya untuk test); default dibuat per instance app. */
  rateLimiters?: RateLimiters;
  /** Sumber status akun/perangkat hidup (default: PostgreSQL). */
  principals?: PrincipalStore;
  /** Override controller suara (misalnya VoiceService dengan stub di test). */
  voiceController?: VoiceController;
}

export function createApp(options: CreateAppOptions = {}): Express {
  const app = express();
  const prefix = config.server.apiPrefix;
  const limiters = options.rateLimiters ?? createRateLimiters();
  const auth = createAuthMiddlewares(options.principals);

  // 0. Di belakang reverse proxy (Traefik/Coolify): X-Forwarded-For hanya
  //    dipercaya dari peer di jaringan privat (default TRUST_PROXY) agar req.ip &
  //    rate limit memakai IP klien yang benar dan tidak dapat dipalsukan.
  app.set('trust proxy', config.server.trustProxy);
  app.disable('x-powered-by');

  // 1. Keamanan header via Helmet
  app.use(helmet());

  // 2. CORS: nonaktif kecuali CORS_ORIGIN diset (aplikasi Android tidak butuh CORS).
  if (config.server.corsOrigin) {
    app.use(
      cors({
        origin: config.server.corsOrigin,
        credentials: false,
        methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
        allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With'],
        maxAge: 600,
      })
    );
  }

  // 3. Body parser JSON global (1 MB). Route STT memakai parser sendiri dengan
  //    batas MAX_AUDIO_UPLOAD_BYTES yang dipasang setelah autentikasi.
  const jsonParser = express.json({ limit: config.server.jsonBodyLimit });
  const sttPaths = new Set<string>(STT_PATHS.map((p) => `${prefix}${p}`));
  const globalJson: RequestHandler = (req, res, next) => (sttPaths.has(req.path) ? next() : jsonParser(req, res, next));
  app.use(globalJson);

  // 4. API Routes
  app.use(prefix, healthRouter);
  app.use(prefix, createAuthRouter(limiters, auth));
  app.use(`${prefix}/research`, createResearchRouter(limiters, auth));
  app.use(prefix, createVoiceRouter(limiters, auth, options.voiceController));
  app.use(`${prefix}/v2`, createV2Router(limiters, auth));

  // 5. 404 & Centralized Error Handler
  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
