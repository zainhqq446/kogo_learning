import bcrypt from 'bcrypt';
import { Pool, PoolClient } from 'pg';
import { config } from '../config/env.js';
import { User, AuthTokenPayload, AuthTokens, UserProfileResponse, UserRole } from '../types/user.js';
import { UnauthorizedError, NotFoundError, ConflictError } from '../types/errors.js';
import { generateUserTokens, verifyAccessToken } from './token_service.js';
import { logger } from '../utils/logger.js';

const INVALID_CREDENTIALS_MESSAGE = 'Username atau kata sandi tidak cocok.';

let dummyHashPromise: Promise<string> | null = null;

/**
 * Hash bcrypt tiruan untuk menyamakan waktu respons login ketika username
 * tidak ada (mencegah timing side channel untuk enumerasi akun).
 */
function getDummyHash(): Promise<string> {
  if (!dummyHashPromise) {
    dummyHashPromise = bcrypt.hash('kogo-dummy-password-for-timing', config.auth.bcryptSaltRounds);
  }
  return dummyHashPromise;
}

function toProfile(user: User): UserProfileResponse {
  return {
    id: user.id,
    username: user.username,
    fullName: user.full_name,
    role: user.role,
    isActive: user.is_active,
    ageYears: user.age_years,
    schoolName: user.school_name,
    createdAt: user.created_at.toISOString(),
  };
}

export class AuthService {
  constructor(private pool: Pool) {}

  /**
   * Hash password menggunakan bcrypt dengan salt rounds terkonfigurasi.
   */
  async hashPassword(password: string): Promise<string> {
    return bcrypt.hash(password, config.auth.bcryptSaltRounds);
  }

  /**
   * Verifikasi kecocokan password plaintext dengan bcrypt hash.
   */
  async comparePassword(password: string, hash: string): Promise<boolean> {
    return bcrypt.compare(password, hash);
  }

  /**
   * Pembuatan access token dan refresh token bertanda tangan JWT (HS256).
   */
  generateTokens(payload: Omit<AuthTokenPayload, 'tokenType'>): AuthTokens {
    return generateUserTokens(payload);
  }

  /**
   * Verifikasi access token. Refresh token dan device token ditolak.
   */
  verifyToken(token: string): AuthTokenPayload {
    return verifyAccessToken(token);
  }

  /**
   * Registrasi akun baru. Peran staf hanya boleh dibuat oleh admin (dicek di
   * controller); registrasi publik hanya untuk anak (`child`/`student`).
   * Untuk anak, profil peserta (participants) dibuat tanpa pernah menimpa
   * peserta yang sudah ada.
   */
  async registerUser(params: {
    username: string;
    password: string;
    fullName: string;
    role?: UserRole;
    ageYears?: number;
    schoolName?: string;
  }): Promise<UserProfileResponse> {
    const cleanUsername = params.username.trim().toLowerCase();
    const cleanFullName = params.fullName.trim();
    const role: UserRole = params.role || 'child';
    const ageYears = params.ageYears ?? null;
    const schoolName = params.schoolName?.trim() ?? null;

    const passwordHash = await this.hashPassword(params.password);

    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      const insertResult = await client.query<User>(
        `INSERT INTO users (username, password_hash, full_name, role, is_active, age_years, school_name, created_at, updated_at)
         VALUES ($1, $2, $3, $4, true, $5, $6, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
         ON CONFLICT (username) DO NOTHING
         RETURNING id, username, password_hash, full_name, role, is_active, age_years, school_name, created_at, updated_at`,
        [cleanUsername, passwordHash, cleanFullName, role, ageYears, schoolName]
      );

      if (insertResult.rowCount === 0) {
        throw new ConflictError(
          `Username '${cleanUsername}' sudah terdaftar. Silakan pilih username lain.`,
          'USERNAME_TAKEN'
        );
      }

      const user = insertResult.rows[0];

      // Anak/siswa mendapat entri participants agar data riset lama tetap terhubung.
      // ON CONFLICT DO NOTHING: tidak pernah mengambil alih peserta yang sudah ada.
      if (role === 'child' || role === 'student') {
        const participantCode = cleanUsername.toUpperCase().replace(/[^A-Z0-9_]/g, '').slice(0, 50);
        const unusedPinHash = await bcrypt.hash(`${user.id}:${Date.now()}`, config.auth.bcryptSaltRounds);
        const participant = await client.query(
          `INSERT INTO participants (participant_code, display_alias, age_years, pin_hash, user_id, is_active, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
           ON CONFLICT (participant_code) DO NOTHING
           RETURNING id`,
          [participantCode, cleanFullName.slice(0, 50), ageYears, unusedPinHash, user.id]
        );
        if (participant.rowCount === 0) {
          throw new ConflictError(
            `Kode peserta '${participantCode}' sudah dipakai. Silakan pilih username lain.`,
            'PARTICIPANT_EXISTS'
          );
        }
      }

      await client.query('COMMIT');
      return toProfile(user);
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Login pengguna. Selalu menjalankan bcrypt (hash tiruan bila user tidak ada)
   * dan memakai pesan 401 yang sama untuk user tidak ada, password salah,
   * maupun akun nonaktif.
   */
  async login(username: string, password: string): Promise<{ user: UserProfileResponse; tokens: AuthTokens }> {
    const cleanUsername = username.trim().toLowerCase();

    const result = await this.pool.query<User>(
      'SELECT id, username, password_hash, full_name, role, is_active, age_years, school_name, created_at, updated_at FROM users WHERE username = $1',
      [cleanUsername]
    );

    const user = result.rows[0];
    const hash = user ? user.password_hash : await getDummyHash();
    const isMatch = await this.comparePassword(password, hash);

    if (!user || !isMatch || !user.is_active) {
      throw new UnauthorizedError(INVALID_CREDENTIALS_MESSAGE, 'INVALID_CREDENTIALS');
    }

    const tokens = this.generateTokens({
      userId: user.id,
      username: user.username,
      role: user.role,
    });

    return { user: toProfile(user), tokens };
  }

  /**
   * Dapatkan profil pengguna berdasarkan ID.
   */
  async getUserProfile(userId: string): Promise<UserProfileResponse> {
    const result = await this.pool.query<User>(
      'SELECT id, username, password_hash, full_name, role, is_active, age_years, school_name, created_at, updated_at FROM users WHERE id = $1',
      [userId]
    );

    if (result.rowCount === 0) {
      throw new NotFoundError('Pengguna tidak ditemukan');
    }

    return toProfile(result.rows[0]);
  }
}

export type AdminBootstrapResult = 'created' | 'updated' | 'unchanged' | 'skipped';

/**
 * Membuat / memperbarui akun admin dari ADMIN_USERNAME + ADMIN_PASSWORD.
 * Environment adalah sumber kebenaran: password diganti bila berbeda dan akun
 * diaktifkan kembali dengan peran admin.
 */
export async function ensureAdminUser(
  client: Pool | PoolClient,
  credentials: { username?: string; password?: string } = {
    username: config.auth.adminUsername,
    password: config.auth.adminPassword,
  }
): Promise<AdminBootstrapResult> {
  const { username, password } = credentials;
  if (!username || !password) return 'skipped';

  const cleanUsername = username.trim().toLowerCase();
  const existing = await client.query<Pick<User, 'id' | 'password_hash' | 'role' | 'is_active'>>(
    'SELECT id, password_hash, role, is_active FROM users WHERE username = $1',
    [cleanUsername]
  );

  if (existing.rowCount === 0) {
    const hash = await bcrypt.hash(password, config.auth.bcryptSaltRounds);
    await client.query(
      `INSERT INTO users (username, password_hash, full_name, role, is_active, created_at, updated_at)
       VALUES ($1, $2, 'Administrator', 'admin', true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
       ON CONFLICT (username) DO UPDATE
       SET password_hash = EXCLUDED.password_hash, role = 'admin', is_active = true, updated_at = CURRENT_TIMESTAMP`,
      [cleanUsername, hash]
    );
    logger.info(`Admin account '${cleanUsername}' created from ADMIN_USERNAME/ADMIN_PASSWORD.`);
    return 'created';
  }

  const row = existing.rows[0];
  const passwordMatches = await bcrypt.compare(password, row.password_hash);
  if (passwordMatches && row.role === 'admin' && row.is_active) {
    return 'unchanged';
  }

  const hash = passwordMatches ? row.password_hash : await bcrypt.hash(password, config.auth.bcryptSaltRounds);
  await client.query(
    `UPDATE users SET password_hash = $2, role = 'admin', is_active = true, updated_at = CURRENT_TIMESTAMP WHERE id = $1`,
    [row.id, hash]
  );
  logger.info(`Admin account '${cleanUsername}' updated from ADMIN_USERNAME/ADMIN_PASSWORD.`);
  return 'updated';
}
