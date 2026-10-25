import { Request, Response, NextFunction } from 'express';
import { AuthService } from '../services/auth_service.js';
import { getDbPool } from '../config/database.js';
import { AuthTokenPayload, UserRole } from '../types/user.js';
import { UnauthorizedError, ForbiddenError } from '../types/errors.js';

// Perluas tipe Request Express agar menyimpan info pengguna terautentikasi
declare global {
  namespace Express {
    interface Request {
      user?: AuthTokenPayload;
    }
  }
}

/**
 * Middleware untuk memvalidasi Bearer JWT Token pada header Authorization.
 */
export function requireAuth(req: Request, _res: Response, next: NextFunction): void {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return next(new UnauthorizedError('Missing or malformed Authorization header. Expected Bearer token.'));
  }

  const token = authHeader.substring(7).trim();
  if (!token) {
    return next(new UnauthorizedError('Bearer token is empty'));
  }

  try {
    const authService = new AuthService(getDbPool());
    const payload = authService.verifyToken(token);
    req.user = payload;
    next();
  } catch (err) {
    next(err);
  }
}

/**
 * Middleware Role-Based Access Control (RBAC).
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