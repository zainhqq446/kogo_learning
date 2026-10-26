import jwt from 'jsonwebtoken';
import { config } from '../config/env.js';
import { UnauthorizedError } from '../types/errors.js';
import {
  AuthTokenPayload,
  AuthTokens,
  DevicePrincipal,
  DeviceTokenPayload,
  RefreshTokenPayload,
  USER_ROLES,
  UserRole,
} from '../types/user.js';

/** Satu-satunya algoritma yang diterima (mencegah algorithm confusion / alg=none). */
export const JWT_ALGORITHM = 'HS256' as const;

export type VerifiedToken =
  | { kind: 'user'; payload: AuthTokenPayload }
  | { kind: 'device'; payload: DevicePrincipal };

function sign(payload: object, expiresInSeconds: number, subject?: string): string {
  const options: jwt.SignOptions = { algorithm: JWT_ALGORITHM, expiresIn: expiresInSeconds };
  if (subject) options.subject = subject;
  return jwt.sign(payload, config.auth.jwtSecret, options);
}

/** Verifikasi tanda tangan + kedaluwarsa dengan algoritma yang dipin ke HS256. */
function decode(token: string): jwt.JwtPayload {
  try {
    const decoded = jwt.verify(token, config.auth.jwtSecret, { algorithms: [JWT_ALGORITHM] });
    if (typeof decoded !== 'object' || decoded === null) {
      throw new UnauthorizedError('Invalid or corrupted token', 'INVALID_TOKEN');
    }
    return decoded;
  } catch (err: unknown) {
    if (err instanceof UnauthorizedError) throw err;
    if (err instanceof jwt.TokenExpiredError) {
      throw new UnauthorizedError('Token has expired', 'TOKEN_EXPIRED');
    }
    throw new UnauthorizedError('Invalid or corrupted token', 'INVALID_TOKEN');
  }
}

function asUserPayload(decoded: jwt.JwtPayload): AuthTokenPayload | null {
  if (
    decoded.tokenType === 'access' &&
    typeof decoded.userId === 'string' &&
    typeof decoded.username === 'string' &&
    USER_ROLES.includes(decoded.role as UserRole)
  ) {
    return {
      userId: decoded.userId,
      username: decoded.username,
      role: decoded.role as UserRole,
      tokenType: 'access',
    };
  }
  return null;
}

function asDevicePayload(decoded: jwt.JwtPayload): DevicePrincipal | null {
  if (decoded.tokenType === 'device' && decoded.role === 'device' && typeof decoded.deviceId === 'string') {
    return { deviceId: decoded.deviceId };
  }
  return null;
}

export function signAccessToken(payload: Omit<AuthTokenPayload, 'tokenType'>): string {
  const body: AuthTokenPayload = {
    userId: payload.userId,
    username: payload.username,
    role: payload.role,
    tokenType: 'access',
  };
  return sign(body, config.auth.jwtExpiresInSeconds);
}

export function signRefreshToken(userId: string): string {
  const body: RefreshTokenPayload = { userId, tokenType: 'refresh' };
  return sign(body, config.auth.jwtRefreshExpiresInSeconds);
}

export function generateUserTokens(payload: Omit<AuthTokenPayload, 'tokenType'>): AuthTokens {
  return {
    accessToken: signAccessToken(payload),
    refreshToken: signRefreshToken(payload.userId),
    expiresIn: config.auth.jwtExpiresIn,
  };
}

/**
 * Token perangkat: `sub` = id internal perangkat. deviceUuid (kredensial yang
 * dibuat aplikasi) tidak pernah dimasukkan ke token karena payload JWT dapat
 * dibaca siapa pun yang memegang token.
 */
export function signDeviceToken(deviceId: string): { token: string; expiresIn: number } {
  const body: Omit<DeviceTokenPayload, 'sub'> = { deviceId, role: 'device', tokenType: 'device' };
  return {
    token: sign(body, config.auth.deviceTokenTtlSeconds, deviceId),
    expiresIn: config.auth.deviceTokenTtlSeconds,
  };
}

/** Hanya menerima access token pengguna; refresh token & device token ditolak. */
export function verifyAccessToken(token: string): AuthTokenPayload {
  const payload = asUserPayload(decode(token));
  if (!payload) {
    throw new UnauthorizedError('Token type is not accepted for this endpoint', 'INVALID_TOKEN');
  }
  return payload;
}

/** Hanya menerima device token aplikasi Android. */
export function verifyDeviceToken(token: string): DevicePrincipal {
  const payload = asDevicePayload(decode(token));
  if (!payload) {
    throw new UnauthorizedError('Token type is not accepted for this endpoint', 'INVALID_TOKEN');
  }
  return payload;
}

/** Menerima access token pengguna ATAU device token (misalnya untuk proxy suara). */
export function verifyUserOrDeviceToken(token: string): VerifiedToken {
  const decoded = decode(token);
  const user = asUserPayload(decoded);
  if (user) return { kind: 'user', payload: user };
  const device = asDevicePayload(decoded);
  if (device) return { kind: 'device', payload: device };
  throw new UnauthorizedError('Token type is not accepted for this endpoint', 'INVALID_TOKEN');
}
