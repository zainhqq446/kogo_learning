import fs from 'fs';
import path from 'path';
import { Pool, PoolClient } from 'pg';
import { logger } from '../utils/logger.js';

export interface MigrationRecord {
  id: number;
  name: string;
  applied_at: Date;
}

/**
 * Kunci advisory PostgreSQL untuk migrasi/startup. Mencegah dua instance
 * (misalnya rolling deploy atau beberapa replika) menjalankan migrasi bersamaan.
 */
export const MIGRATION_LOCK_KEY = 7_202_604_001;

/**
 * Memastikan tabel pelacak migrasi `schema_migrations` telah tersedia.
 */
export async function ensureMigrationTable(client: PoolClient): Promise<void> {
  await client.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      id SERIAL PRIMARY KEY,
      name VARCHAR(255) NOT NULL UNIQUE,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
    );
  `);
}

/**
 * Mengambil daftar nama file migrasi yang sudah pernah diaplikasikan.
 */
export async function getAppliedMigrations(client: PoolClient): Promise<string[]> {
  await ensureMigrationTable(client);
  const result = await client.query<MigrationRecord>('SELECT name FROM schema_migrations ORDER BY id ASC;');
  return result.rows.map((row) => row.name);
}

export function listMigrationFiles(migrationsDir: string): string[] {
  if (!fs.existsSync(migrationsDir)) {
    throw new Error(`Migrations directory not found: ${migrationsDir}`);
  }
  return fs
    .readdirSync(migrationsDir)
    .filter((file) => file.endsWith('.sql'))
    .sort();
}

/**
 * Menjalankan migrasi pending memakai client yang sudah memegang advisory lock.
 * Setiap file dijalankan dalam transaksi atomik tersendiri.
 */
export async function applyPendingMigrations(client: PoolClient, migrationsDir: string): Promise<string[]> {
  const files = listMigrationFiles(migrationsDir);
  const applied = new Set(await getAppliedMigrations(client));
  const appliedNow: string[] = [];

  for (const file of files) {
    if (applied.has(file)) {
      logger.debug(`Migration ${file} already applied. Skipping.`);
      continue;
    }

    const sqlContent = fs.readFileSync(path.join(migrationsDir, file), 'utf8');
    logger.info(`Applying migration: ${file}...`);
    await client.query('BEGIN');
    try {
      await client.query(sqlContent);
      await client.query('INSERT INTO schema_migrations (name) VALUES ($1);', [file]);
      await client.query('COMMIT');
      logger.info(`Migration ${file} successfully applied.`);
      appliedNow.push(file);
    } catch (err) {
      await client.query('ROLLBACK');
      logger.error(`Failed to apply migration ${file}. Transaction rolled back.`);
      throw err;
    }
  }

  return appliedNow;
}

/**
 * Menjalankan `task` sambil memegang advisory lock sesi (diblokir sampai instance
 * lain selesai). Lock selalu dilepas, juga saat terjadi error.
 */
export async function withMigrationLock<T>(pool: Pool, task: (client: PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('SELECT pg_advisory_lock($1)', [MIGRATION_LOCK_KEY]);
    try {
      return await task(client);
    } finally {
      await client.query('SELECT pg_advisory_unlock($1)', [MIGRATION_LOCK_KEY]);
    }
  } finally {
    client.release();
  }
}

/**
 * Menjalankan seluruh file migrasi pending secara berurutan di bawah advisory lock.
 */
export async function runMigrations(pool: Pool, migrationsDir: string): Promise<string[]> {
  return withMigrationLock(pool, (client) => applyPendingMigrations(client, migrationsDir));
}
