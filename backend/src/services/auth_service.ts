import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { Pool } from 'pg';
import { config } from '../config/env.js';
import { User, AuthTokenPayload, AuthTokens, UserProfileResponse, UserRole } from '../types/user.js';
import { UnauthorizedError, ValidationError, ForbiddenError, NotFoundError } from '../types/errors.js';

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
   * Pembuatan access token dan refresh token bertanda tangan JWT.
   */
  generateTokens(payload: AuthTokenPayload): AuthTokens {
    const accessToken = jwt.sign(payload, config.auth.jwtSecret, {
      expiresIn: config.auth.jwtExpiresIn,
    } as jwt.SignOptions);

    const refreshToken = jwt.sign(
      { userId: payload.userId, tokenType: 'refresh' },
      config.auth.jwtSecret,
      { expiresIn: config.auth.jwtRefreshExpiresIn } as jwt.SignOptions
    );

    return {
      accessToken,
      refreshToken,
      expiresIn: config.auth.jwtExpiresIn,
    };
  }

  /**
   * Verifikasi JWT token dan kembalikan payloadnya.
   */
  verifyToken(token: string): AuthTokenPayload {
    try {
      const decoded = jwt.verify(token, config.auth.jwtSecret) as AuthTokenPayload;
      return decoded;
    } catch (err: unknown) {
      if (err instanceof jwt.TokenExpiredError) {
        throw new UnauthorizedError('Token has expired');
      }
      throw new UnauthorizedError('Invalid or corrupted token');
    }
  }

  /**
   * Registrasi akun baru (mendukung role child, researcher, teacher, admin).
   * Untuk child, otomatis mengaitkan atau membuat profil peserta (participants).
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

    // Cek apakah username sudah ada
    const existing = await this.pool.query('SELECT id FROM users WHERE username = $1', [cleanUsername]);
    if (existing.rowCount && existing.rowCount > 0) {
      throw new ValidationError(`Username '${cleanUsername}' sudah terdaftar. Silakan pilih username lain.`);
    }

    const passwordHash = await this.hashPassword(params.password);

    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      const insertResult = await client.query<User>(
        `INSERT INTO users (username, password_hash, full_name, role, is_active, age_years, school_name, created_at, updated_at)
         VALUES ($1, $2, $3, $4, true, $5, $6, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
         RETURNING id, username, password_hash, full_name, role, is_active, age_years, school_name, created_at, updated_at`,
        [cleanUsername, passwordHash, cleanFullName, role, ageYears, schoolName]
      );

      const user = insertResult.rows[0];

      // Jika role adalah child atau student, buatkan entri di tabel participants agar sinkronisasi batch log terhubung
      if (role === 'child' || role === 'student') {
        const participantCode = cleanUsername.toUpperCase().replace(/[^A-Z0-9_]/g, '').slice(0, 50);
        const defaultPinHash = await bcrypt.hash('1234', config.auth.bcryptSaltRounds);

        await client.query(
          `INSERT INTO participants (participant_code, display_alias, age_years, pin_hash, user_id, is_active, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
           ON CONFLICT (participant_code) DO UPDATE
           SET user_id = EXCLUDED.user_id, display_alias = EXCLUDED.display_alias, age_years = EXCLUDED.age_years, updated_at = CURRENT_TIMESTAMP`,
          [participantCode, cleanFullName, ageYears, defaultPinHash, user.id]
        );
      }

      await client.query('COMMIT');

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
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Login pengguna menggunakan username dan password.
   */
  async login(username: string, password: string): Promise<{ user: UserProfileResponse; tokens: AuthTokens }> {
    const cleanUsername = username.trim().toLowerCase();

    const result = await this.pool.query<User>(
      'SELECT id, username, password_hash, full_name, role, is_active, age_years, school_name, created_at, updated_at FROM users WHERE username = $1',
      [cleanUsername]
    );

    if (result.rowCount === 0) {
      throw new UnauthorizedError('Username atau kata sandi tidak cocok.');
    }

    const user = result.rows[0];

    if (!user.is_active) {
      throw new ForbiddenError('Akun Anda dinonaktifkan.');
    }

    const isMatch = await this.comparePassword(password, user.password_hash);
    if (!isMatch) {
      throw new UnauthorizedError('Username atau kata sandi tidak cocok.');
    }

    const payload: AuthTokenPayload = {
      userId: user.id,
      username: user.username,
      role: user.role,
    };

    const tokens = this.generateTokens(payload);

    return {
      user: {
        id: user.id,
        username: user.username,
        fullName: user.full_name,
        role: user.role,
        isActive: user.is_active,
        ageYears: user.age_years,
        schoolName: user.school_name,
        createdAt: user.created_at.toISOString(),
      },
      tokens,
    };
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

    const user = result.rows[0];
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
}