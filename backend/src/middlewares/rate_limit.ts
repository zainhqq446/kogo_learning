import { Request, RequestHandler, Response } from 'express';
import { rateLimit, ipKeyGenerator } from 'express-rate-limit';
import { config, RateLimitConfig } from '../config/env.js';

export interface RateLimiters {
  /** Login & registrasi: default 10 request / 15 menit / IP. */
  auth: RequestHandler;
  /** Proxy suara: default 60 request / menit / principal (device atau user). */
  voice: RequestHandler;
  /**
   * Proxy suara per IP klien (default 120 / menit), dipasang sebelum
   * autentikasi sehingga banyak token dari satu sumber tetap dibatasi.
   */
  voiceIp: RequestHandler;
  /** Sinkronisasi data riset: default 60 request / menit / device. */
  sync: RequestHandler;
  /** Registrasi perangkat: default 20 request / jam / IP. */
  deviceRegister: RequestHandler;
}

const passThrough: RequestHandler = (_req, _res, next) => next();

function clientIpKey(req: Request): string {
  return ipKeyGenerator(req.ip ?? 'unknown');
}

/**
 * Kunci rate limit berbasis principal terautentikasi. Banyak perangkat di satu
 * sekolah bisa berbagi IP publik yang sama (NAT), sehingga limit per perangkat
 * lebih adil daripada per IP. Fallback ke IP bila belum terautentikasi.
 */
function principalKey(req: Request): string {
  if (req.device) return `device:${req.device.deviceId}`;
  if (req.user) return `user:${req.user.userId}`;
  return `ip:${clientIpKey(req)}`;
}

function limitExceededHandler(message: string) {
  return (_req: Request, res: Response): void => {
    res.status(429).json({
      status: 'error',
      statusCode: 429,
      code: 'RATE_LIMITED',
      message,
    });
  };
}

/**
 * Rate limiter dibuat per instance aplikasi (store in-memory) sehingga setiap
 * `createApp()` (termasuk di test) memiliki counter sendiri.
 */
export function createRateLimiters(rateConfig: RateLimitConfig = config.rateLimit): RateLimiters {
  if (!rateConfig.enabled) {
    return { auth: passThrough, voice: passThrough, voiceIp: passThrough, sync: passThrough, deviceRegister: passThrough };
  }

  const common = {
    standardHeaders: 'draft-7' as const,
    legacyHeaders: false,
  };

  return {
    auth: rateLimit({
      ...common,
      windowMs: rateConfig.authWindowMs,
      limit: rateConfig.authMax,
      keyGenerator: clientIpKey,
      handler: limitExceededHandler('Too many authentication attempts. Please try again later.'),
    }),
    voice: rateLimit({
      ...common,
      windowMs: 60 * 1000,
      limit: rateConfig.voicePerMinute,
      keyGenerator: principalKey,
      handler: limitExceededHandler('Too many voice requests. Please slow down.'),
    }),
    voiceIp: rateLimit({
      ...common,
      windowMs: 60 * 1000,
      limit: rateConfig.voicePerIpPerMinute,
      keyGenerator: clientIpKey,
      handler: limitExceededHandler('Too many voice requests from this network. Please slow down.'),
    }),
    sync: rateLimit({
      ...common,
      windowMs: 60 * 1000,
      limit: rateConfig.syncPerMinute,
      keyGenerator: principalKey,
      handler: limitExceededHandler('Too many sync requests. Please retry later.'),
    }),
    deviceRegister: rateLimit({
      ...common,
      windowMs: 60 * 60 * 1000,
      limit: rateConfig.deviceRegisterPerHour,
      keyGenerator: clientIpKey,
      handler: limitExceededHandler('Too many device registrations from this network. Please retry later.'),
    }),
  };
}
