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
  const result = await client.query<MigrationRecord>(
    'SELECT name FROM schema_migrations ORDER BY id ASC;'
  );
  return result.rows.map((row) => row.name);
}

/**
 * Menjalankan seluruh file migrasi pending secara berurutan dalam transaksi atomik.
 */
export async function runMigrations(pool: Pool, migrationsDir: string): Promise<string[]> {
  if (!fs.existsSync(migrationsDir)) {
    throw new Error(`Migrations directory not found: ${migrationsDir}`);
  }

  const files = fs
    .readdirSync(migrationsDir)
    .filter((file) => file.endsWith('.sql'))
    .sort();

  const client = await pool.connect();
  const appliedNow: string[] = [];

  try {
    const applied = await getAppliedMigrations(client);

    for (const file of files) {
      if (applied.includes(file)) {
        logger.debug(`Migration ${file} already applied. Skipping.`);
        continue;
      }

      const filePath = path.join(migrationsDir, file);
      const sqlContent = fs.readFileSync(filePath, 'utf8');

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
  } finally {
    client.release();
  }
}