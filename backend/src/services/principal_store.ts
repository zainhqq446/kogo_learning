import { Pool } from 'pg';
import { getDbPool } from '../config/database.js';
import { UserRole } from '../types/user.js';

/** Status akun pengguna saat ini (bukan nilai yang tertanam di JWT). */
export interface UserState {
  role: UserRole;
  isActive: boolean;
}

/** Status kepercayaan perangkat saat ini. */
export interface DeviceState {
  approved: boolean;
  revoked: boolean;
}

/**
 * Sumber status principal yang hidup. JWT hanya membuktikan identitas; role,
 * status aktif, persetujuan dan pencabutan perangkat selalu dibaca ulang dari
 * database agar penonaktifan/penurunan peran/pencabutan berlaku seketika.
 */
export interface PrincipalStore {
  getUser(userId: string): Promise<UserState | null>;
  getDevice(deviceId: string): Promise<DeviceState | null>;
}

const UUID_SHAPE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function createDbPrincipalStore(getPool: () => Pool = getDbPool): PrincipalStore {
  return {
    async getUser(userId: string): Promise<UserState | null> {
      if (!UUID_SHAPE.test(userId)) return null;
      const res = await getPool().query<{ role: UserRole; is_active: boolean }>(
        'SELECT role, is_active FROM users WHERE id = $1',
        [userId]
      );
      const row = res.rows[0];
      return row ? { role: row.role, isActive: row.is_active } : null;
    },

    async getDevice(deviceId: string): Promise<DeviceState | null> {
      if (!UUID_SHAPE.test(deviceId)) return null;
      const res = await getPool().query<{ approved: boolean; revoked: boolean }>(
        `SELECT approved_at IS NOT NULL AS approved, revoked_at IS NOT NULL AS revoked
         FROM app_devices WHERE id = $1`,
        [deviceId]
      );
      return res.rows[0] ?? null;
    },
  };
}
