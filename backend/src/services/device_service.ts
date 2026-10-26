import crypto from 'crypto';
import { Pool, PoolClient } from 'pg';
import { config } from '../config/env.js';
import { ConflictError, ForbiddenError, NotFoundError } from '../types/errors.js';
import { DeviceRegisterRequest } from '../types/schemas.js';
import { signDeviceToken } from './token_service.js';

export interface DeviceRegistrationResult {
  deviceId: string;
  created: boolean;
  deviceToken: string;
  expiresIn: number;
  /** Hanya ada saat rahasia baru diterbitkan (registrasi pertama / klaim ulang). */
  deviceSecret?: string;
  approved: boolean;
}

export interface DeviceRegistrationProof {
  /** Nilai header `X-Enrollment-Key` (hanya relevan untuk perangkat baru). */
  enrollmentKey?: string;
  /** deviceId dari device token valid yang dikirim di header Authorization. */
  tokenDeviceId?: string;
}

export type DeviceStatus = 'approved' | 'pending' | 'revoked';

export interface DeviceSummary {
  deviceId: string;
  label: string | null;
  platform: string;
  appVersion: string;
  model: string | null;
  status: DeviceStatus;
  createdAt: string;
  lastSeenAt: string;
  approvedAt: string | null;
  revokedAt: string | null;
  learners: number;
  sessions: number;
  attempts: number;
}

interface DeviceRow {
  id: string;
  secret_hash: string | null;
  approved_at: Date | null;
  revoked_at: Date | null;
}

/** Rahasia perangkat acak 256-bit (base64url, 43 karakter). */
export function generateDeviceSecret(): string {
  return crypto.randomBytes(32).toString('base64url');
}

export function hashDeviceSecret(secret: string): string {
  return crypto.createHash('sha256').update(secret, 'utf8').digest('hex');
}

/** Perbandingan waktu-konstan untuk string rahasia (via hash agar panjang sama). */
export function secretsEqual(a: string, b: string): boolean {
  const ha = crypto.createHash('sha256').update(a, 'utf8').digest();
  const hb = crypto.createHash('sha256').update(b, 'utf8').digest();
  return crypto.timingSafeEqual(ha, hb);
}

function iso(value: Date | null): string | null {
  return value ? value.toISOString() : null;
}

export class DeviceService {
  constructor(
    private pool: Pool,
    private readonly enrollmentKey: string | undefined = config.devices.enrollmentKey
  ) {}

  /**
   * Registrasi perangkat Android.
   *
   * - Perangkat baru: 201 + deviceToken + deviceSecret (sekali saja). Bila
   *   DEVICE_ENROLLMENT_KEY diset, header `X-Enrollment-Key` wajib cocok dan
   *   perangkat langsung disetujui; bila tidak, perangkat berstatus pending.
   * - Perangkat yang sudah ada: 200 hanya dengan bukti kepemilikan (deviceSecret
   *   yang benar atau device token valid milik perangkat ini). deviceUuid saja
   *   tidak cukup. Perangkat lama tanpa rahasia (sebelum migrasi 005, atau
   *   setelah peneliti mereset kredensialnya) dapat mengklaim rahasia baru sekali.
   */
  async register(params: DeviceRegisterRequest, proof: DeviceRegistrationProof = {}): Promise<DeviceRegistrationResult> {
    const deviceUuid = params.deviceUuid.toLowerCase();
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      let existing = await this.lockDevice(client, deviceUuid);
      let result: DeviceRegistrationResult | null = null;

      if (!existing) {
        result = await this.createDevice(client, deviceUuid, params, proof);
        if (!result) {
          // Registrasi paralel dengan deviceUuid yang sama: perlakukan sebagai perangkat lama.
          existing = await this.lockDevice(client, deviceUuid);
        }
      }
      if (!result) {
        result = await this.refreshDevice(client, existing as DeviceRow, params, proof);
      }

      await client.query('COMMIT');
      return result;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  private async lockDevice(client: PoolClient, deviceUuid: string): Promise<DeviceRow | null> {
    const res = await client.query<DeviceRow>(
      'SELECT id, secret_hash, approved_at, revoked_at FROM app_devices WHERE device_uuid = $1 FOR UPDATE',
      [deviceUuid]
    );
    return res.rows[0] ?? null;
  }

  private async createDevice(
    client: PoolClient,
    deviceUuid: string,
    params: DeviceRegisterRequest,
    proof: DeviceRegistrationProof
  ): Promise<DeviceRegistrationResult | null> {
    let approved = false;
    if (this.enrollmentKey) {
      if (!proof.enrollmentKey || !secretsEqual(proof.enrollmentKey, this.enrollmentKey)) {
        throw new ForbiddenError('A valid X-Enrollment-Key header is required to register a new device.', 'ENROLLMENT_REQUIRED');
      }
      approved = true;
    }

    const secret = generateDeviceSecret();
    const res = await client.query<{ id: string }>(
      `INSERT INTO app_devices (device_uuid, platform, app_version, model, secret_hash, approved_at, created_at, last_seen_at)
       VALUES ($1, $2, $3, $4, $5, CASE WHEN $6::boolean THEN CURRENT_TIMESTAMP END, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
       ON CONFLICT (device_uuid) DO NOTHING
       RETURNING id`,
      [deviceUuid, params.platform, params.appVersion, params.model ?? null, hashDeviceSecret(secret), approved]
    );
    const row = res.rows[0];
    if (!row) return null;

    const { token, expiresIn } = signDeviceToken(row.id);
    return { deviceId: row.id, created: true, deviceToken: token, expiresIn, deviceSecret: secret, approved };
  }

  private async refreshDevice(
    client: PoolClient,
    row: DeviceRow,
    params: DeviceRegisterRequest,
    proof: DeviceRegistrationProof
  ): Promise<DeviceRegistrationResult> {
    if (row.revoked_at) {
      throw new ForbiddenError('This device has been revoked by a researcher.', 'DEVICE_REVOKED');
    }

    const secretMatches =
      row.secret_hash !== null && params.deviceSecret !== undefined && secretsEqual(hashDeviceSecret(params.deviceSecret), row.secret_hash);
    const tokenMatches = proof.tokenDeviceId !== undefined && proof.tokenDeviceId === row.id;
    const unclaimed = row.secret_hash === null;

    if (!secretMatches && !tokenMatches && !unclaimed) {
      throw new ConflictError(
        'This deviceUuid is already registered. Send the deviceSecret from the first registration (or a valid device token) to refresh the token.',
        'DEVICE_PROOF_REQUIRED'
      );
    }

    const newSecret = unclaimed ? generateDeviceSecret() : undefined;
    await client.query(
      `UPDATE app_devices
       SET platform = $2, app_version = $3, model = COALESCE($4, model),
           secret_hash = COALESCE($5, secret_hash), last_seen_at = CURRENT_TIMESTAMP
       WHERE id = $1`,
      [row.id, params.platform, params.appVersion, params.model ?? null, newSecret ? hashDeviceSecret(newSecret) : null]
    );

    const { token, expiresIn } = signDeviceToken(row.id);
    return {
      deviceId: row.id,
      created: false,
      deviceToken: token,
      expiresIn,
      ...(newSecret ? { deviceSecret: newSecret } : {}),
      approved: row.approved_at !== null,
    };
  }

  // --------------------------------------------------------------------------
  // Manajemen perangkat oleh peneliti
  // --------------------------------------------------------------------------

  async list(): Promise<DeviceSummary[]> {
    const res = await this.pool.query<{
      id: string;
      label: string | null;
      platform: string;
      app_version: string;
      model: string | null;
      created_at: Date;
      last_seen_at: Date;
      approved_at: Date | null;
      revoked_at: Date | null;
      learners: number;
      sessions: number;
      attempts: number;
    }>(
      `SELECT d.id, d.label, d.platform, d.app_version, d.model, d.created_at, d.last_seen_at, d.approved_at, d.revoked_at,
              (SELECT COUNT(*) FROM learners l WHERE l.device_id = d.id)::int AS learners,
              (SELECT COUNT(*) FROM game_sessions gs WHERE gs.device_id = d.id)::int AS sessions,
              (SELECT COUNT(*) FROM answer_attempts aa JOIN game_sessions gs ON gs.id = aa.session_id
                WHERE gs.device_id = d.id)::int AS attempts
       FROM app_devices d
       ORDER BY d.created_at DESC, d.id`
    );
    return res.rows.map((r) => ({
      deviceId: r.id,
      label: r.label,
      platform: r.platform,
      appVersion: r.app_version,
      model: r.model,
      status: r.revoked_at ? 'revoked' : r.approved_at ? 'approved' : 'pending',
      createdAt: r.created_at.toISOString(),
      lastSeenAt: r.last_seen_at.toISOString(),
      approvedAt: iso(r.approved_at),
      revokedAt: iso(r.revoked_at),
      learners: Number(r.learners),
      sessions: Number(r.sessions),
      attempts: Number(r.attempts),
    }));
  }

  /** Menyetujui perangkat (juga membatalkan pencabutan). */
  async approve(deviceId: string, approvedBy: string | undefined, label?: string): Promise<DeviceStatus> {
    const res = await this.pool.query(
      `UPDATE app_devices
       SET approved_at = CURRENT_TIMESTAMP, approved_by = $2, revoked_at = NULL, label = COALESCE($3, label)
       WHERE id = $1`,
      [deviceId, approvedBy ?? null, label ?? null]
    );
    if (res.rowCount === 0) throw new NotFoundError('Device not found');
    return 'approved';
  }

  /** Mencabut perangkat: token ditolak, registrasi ulang ditolak, data dikecualikan dari metrik. */
  async revoke(deviceId: string): Promise<DeviceStatus> {
    const res = await this.pool.query(
      'UPDATE app_devices SET revoked_at = COALESCE(revoked_at, CURRENT_TIMESTAMP) WHERE id = $1',
      [deviceId]
    );
    if (res.rowCount === 0) throw new NotFoundError('Device not found');
    return 'revoked';
  }

  /**
   * Menghapus rahasia perangkat sehingga registrasi berikutnya dengan deviceUuid
   * yang sama boleh mengklaim rahasia baru tanpa bukti (pemulihan bila aplikasi
   * kehilangan deviceSecret/token, mis. setelah JWT_SECRET dirotasi).
   */
  async resetCredential(deviceId: string): Promise<void> {
    const res = await this.pool.query('UPDATE app_devices SET secret_hash = NULL WHERE id = $1', [deviceId]);
    if (res.rowCount === 0) throw new NotFoundError('Device not found');
  }
}
