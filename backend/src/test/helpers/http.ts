import { Server } from 'http';
import { Express } from 'express';
import jwt from 'jsonwebtoken';
import { TEST_JWT_SECRET } from './test_env.js';
import { signAccessToken, signDeviceToken } from '../../services/token_service.js';
import { UserRole } from '../../types/user.js';
import { createRateLimiters, RateLimiters } from '../../middlewares/rate_limit.js';
import { config } from '../../config/env.js';
import { DeviceState, PrincipalStore, UserState } from '../../services/principal_store.js';

export interface TestServer {
  baseUrl: string;
  close: () => Promise<void>;
}

export async function startServer(app: Express): Promise<TestServer> {
  const server: Server = await new Promise((resolve) => {
    const s = app.listen(0, '127.0.0.1', () => resolve(s));
  });
  const address = server.address();
  if (!address || typeof address !== 'object') throw new Error('Server has no address');
  return {
    baseUrl: `http://127.0.0.1:${address.port}`,
    close: () =>
      new Promise<void>((resolve, reject) => {
        server.closeAllConnections();
        server.close((err) => (err ? reject(err) : resolve()));
      }),
  };
}

/** userId deterministik per role (dipakai stub PrincipalStore di unit test). */
export const TEST_USER_IDS: Record<UserRole, string> = {
  admin: '00000000-0000-4000-8000-0000000000a1',
  researcher: '00000000-0000-4000-8000-0000000000a2',
  teacher: '00000000-0000-4000-8000-0000000000a3',
  child: '00000000-0000-4000-8000-0000000000a4',
  student: '00000000-0000-4000-8000-0000000000a5',
};

export function userToken(role: UserRole, userId = TEST_USER_IDS[role], username = `${role}_user`): string {
  return signAccessToken({ userId, username, role });
}

export function deviceToken(deviceId = '00000000-0000-4000-8000-0000000000d1'): string {
  return signDeviceToken(deviceId).token;
}

/**
 * PrincipalStore in-memory untuk unit test tanpa database: semua TEST_USER_IDS
 * aktif dengan role-nya, dan setiap perangkat dianggap disetujui kecuali diatur.
 */
export function testPrincipals(
  overrides: { users?: Record<string, UserState | null>; devices?: Record<string, DeviceState | null> } = {}
): PrincipalStore {
  const users = new Map<string, UserState | null>(
    Object.entries(TEST_USER_IDS).map(([role, id]) => [id, { role: role as UserRole, isActive: true }])
  );
  for (const [id, state] of Object.entries(overrides.users ?? {})) users.set(id, state);
  const devices = new Map<string, DeviceState | null>(Object.entries(overrides.devices ?? {}));
  return {
    async getUser(userId) {
      return users.has(userId) ? (users.get(userId) ?? null) : null;
    },
    async getDevice(deviceId) {
      return devices.has(deviceId) ? (devices.get(deviceId) ?? null) : { approved: true, revoked: false };
    },
  };
}

/** Token dengan payload/opsi bebas (untuk menguji penolakan token). */
export function rawToken(payload: object, options: jwt.SignOptions = { algorithm: 'HS256', expiresIn: 600 }): string {
  return jwt.sign(payload, TEST_JWT_SECRET, options);
}

export function bearer(token: string): Record<string, string> {
  return { Authorization: `Bearer ${token}` };
}

export async function postJson(
  baseUrl: string,
  path: string,
  body: unknown,
  headers: Record<string, string> = {}
): Promise<{ status: number; body: any; headers: Headers }> {
  const res = await fetch(`${baseUrl}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(body),
  });
  const text = await res.text();
  let parsed: unknown = text;
  try {
    parsed = text ? JSON.parse(text) : null;
  } catch {
    // respons non-JSON (mis. audio/CSV)
  }
  return { status: res.status, body: parsed, headers: res.headers };
}

export async function getJson(
  baseUrl: string,
  path: string,
  headers: Record<string, string> = {}
): Promise<{ status: number; body: any; headers: Headers; text: string }> {
  const res = await fetch(`${baseUrl}${path}`, { headers });
  const text = await res.text();
  let parsed: unknown = text;
  try {
    parsed = text ? JSON.parse(text) : null;
  } catch {
    // respons non-JSON
  }
  return { status: res.status, body: parsed, headers: res.headers, text };
}

/** Rate limiter nonaktif untuk integration test yang melakukan banyak request. */
export function noRateLimits(): RateLimiters {
  return createRateLimiters({ ...config.rateLimit, enabled: false });
}
