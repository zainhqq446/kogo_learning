import { Pool, PoolConfig } from 'pg';
import { runStartupTasks } from '../../services/startup_service.js';
import { signAccessToken } from '../../services/token_service.js';
import { UserRole } from '../../types/user.js';

/**
 * Konfigurasi database integration test. Urutan prioritas:
 * TEST_DATABASE_URL > DATABASE_URL > DB_* (DB_NAME default `kogo_research_test`).
 * Nama database WAJIB mengandung "test" karena test melakukan TRUNCATE.
 */
export function testPoolConfig(): PoolConfig {
  const url = process.env.TEST_DATABASE_URL || process.env.DATABASE_URL;
  const ssl =
    process.env.DB_SSL === 'true' ? { rejectUnauthorized: process.env.DB_SSL_REJECT_UNAUTHORIZED !== 'false' } : false;
  if (url) {
    return { connectionString: url, ssl, max: 10 };
  }
  return {
    host: process.env.DB_HOST || 'localhost',
    port: Number(process.env.DB_PORT || 5432),
    database: process.env.DB_NAME || 'kogo_research_test',
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD,
    ssl,
    max: 10,
  };
}

export async function createTestPool(): Promise<Pool> {
  const pool = new Pool(testPoolConfig());
  const res = await pool.query<{ db: string }>('SELECT current_database() AS db');
  const db = res.rows[0].db;
  if (!/test/i.test(db)) {
    await pool.end();
    throw new Error(
      `Refusing to run integration tests against database "${db}": its name must contain "test". ` +
        'Set TEST_DATABASE_URL to a disposable database.'
    );
  }
  return pool;
}

const ALL_TABLES = [
  'answer_attempts',
  'rewards',
  'stars',
  'game_sessions',
  'learners',
  'app_devices',
  'similarity_evaluations',
  'speech_attempts',
  'research_sessions',
  'participants',
  'devices',
  'audit_logs',
  'voice_usage_daily',
  'users',
];

export async function truncateAll(pool: Pool): Promise<void> {
  await pool.query(`TRUNCATE ${ALL_TABLES.join(', ')} RESTART IDENTITY CASCADE`);
}

/** Membuat pengguna nyata (status akun diperiksa hidup oleh requireAuth) dan access token-nya. */
export async function createUserWithToken(
  pool: Pool,
  role: UserRole,
  username = `${role}_${Math.random().toString(36).slice(2, 10)}`
): Promise<{ id: string; token: string }> {
  const res = await pool.query<{ id: string }>(
    `INSERT INTO users (username, password_hash, full_name, role) VALUES ($1, 'x', 'Test User', $2) RETURNING id`,
    [username, role]
  );
  const id = res.rows[0].id;
  return { id, token: signAccessToken({ userId: id, username, role }) };
}

/** Migrasi + seed referensi (idempoten), lalu kosongkan data uji. */
export async function prepareTestDatabase(pool: Pool): Promise<void> {
  await runStartupTasks(pool, { waitForDbSeconds: 0, admin: {} });
  await truncateAll(pool);
}
