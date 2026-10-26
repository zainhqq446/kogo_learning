import { Request, Response, NextFunction, RequestHandler } from 'express';
import { AuthTokenPayload, DevicePrincipal, UserRole } from '../types/user.js';
import { UnauthorizedError, ForbiddenError } from '../types/errors.js';
import { verifyAccessToken, verifyDeviceToken, verifyUserOrDeviceToken } from '../services/token_service.js';
import { createDbPrincipalStore, PrincipalStore } from '../services/principal_store.js';

// Perluas tipe Request Express agar menyimpan info principal terautentikasi
declare global {
  namespace Express {
    interface Request {
      /** Diisi untuk access token pengguna (admin/researcher/teacher/child). */
      user?: AuthTokenPayload;
      /** Diisi untuk device token aplikasi Android. */
      device?: DevicePrincipal;
    }
  }
}

/** Akun pengguna yang boleh memakai proxy suara berbayar (bukan akun anak). */
export const VOICE_USER_ROLES: readonly UserRole[] = ['admin', 'researcher', 'teacher'];

export interface AuthMiddlewares {
  /** Access token pengguna + status akun hidup (aktif, role terkini). */
  requireAuth: RequestHandler;
  /** Device token aplikasi (status perangkat diperiksa di transaksi sinkronisasi). */
  requireDevice: RequestHandler;
  /** Proxy suara: akun staf aktif, atau perangkat yang disetujui dan tidak dicabut. */
  requireVoiceAccess: RequestHandler;
}

function extractBearerToken(req: Request): string {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new UnauthorizedError('Missing or malformed Authorization header. Expected Bearer token.');
  }
  const token = authHeader.substring(7).trim();
  if (!token) {
    throw new UnauthorizedError('Bearer token is empty');
  }
  return token;
}

async function loadActiveUser(store: PrincipalStore, payload: AuthTokenPayload): Promise<AuthTokenPayload> {
  const state = await store.getUser(payload.userId);
  if (!state || !state.isActive) {
    throw new UnauthorizedError('Account is disabled or no longer exists. Please log in again.', 'ACCOUNT_DISABLED');
  }
  // Role dari database (bukan dari token) agar penurunan peran berlaku seketika.
  return { ...payload, role: state.role };
}

async function loadTrustedDevice(store: PrincipalStore, principal: DevicePrincipal): Promise<DevicePrincipal> {
  const state = await store.getDevice(principal.deviceId);
  if (!state) {
    throw new UnauthorizedError('Device is not registered. Register the device again.', 'DEVICE_NOT_REGISTERED');
  }
  if (state.revoked) {
    throw new ForbiddenError('This device has been revoked by a researcher.', 'DEVICE_REVOKED');
  }
  if (!state.approved) {
    throw new ForbiddenError('This device is waiting for researcher approval.', 'DEVICE_NOT_APPROVED');
  }
  return principal;
}

/**
 * Membuat middleware autentikasi yang memeriksa status principal secara hidup
 * melalui `store` (default: PostgreSQL).
 */
export function createAuthMiddlewares(store: PrincipalStore = createDbPrincipalStore()): AuthMiddlewares {
  const requireAuth: RequestHandler = async (req, _res, next) => {
    try {
      req.user = await loadActiveUser(store, verifyAccessToken(extractBearerToken(req)));
      next();
    } catch (err) {
      next(err);
    }
  };

  const requireDevice: RequestHandler = (req, _res, next) => {
    try {
      req.device = verifyDeviceToken(extractBearerToken(req));
      next();
    } catch (err) {
      next(err);
    }
  };

  const requireVoiceAccess: RequestHandler = async (req, _res, next) => {
    try {
      const verified = verifyUserOrDeviceToken(extractBearerToken(req));
      if (verified.kind === 'user') {
        const user = await loadActiveUser(store, verified.payload);
        if (!VOICE_USER_ROLES.includes(user.role)) {
          throw new ForbiddenError('The voice proxy is available to staff accounts and approved devices only.');
        }
        req.user = user;
      } else {
        req.device = await loadTrustedDevice(store, verified.payload);
      }
      next();
    } catch (err) {
      next(err);
    }
  };

  return { requireAuth, requireDevice, requireVoiceAccess };
}

/**
 * Middleware Role-Based Access Control (RBAC) untuk token pengguna.
 */
export function requireRole(...allowedRoles: UserRole[]) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    if (!req.user) {
      return next(new UnauthorizedError('Authentication required'));
    }

    if (!allowedRoles.includes(req.user.role)) {
      return next(new ForbiddenError(`Access denied. Requires one of the following roles: ${allowedRoles.join(', ')}`));
    }

    next();
  };
}
