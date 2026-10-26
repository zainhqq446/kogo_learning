import { Pool } from 'pg';
import { config } from '../config/env.js';
import { waitForDatabase } from '../config/database.js';
import { MIGRATIONS_DIR } from '../utils/paths.js';
import { logger } from '../utils/logger.js';
import { applyPendingMigrations, withMigrationLock } from './migrator.js';
import { ReferenceSeedResult, seedReferenceData } from './reference_data_service.js';
import { AdminBootstrapResult, ensureAdminUser } from './auth_service.js';

export interface StartupTasksResult {
  appliedMigrations: string[];
  referenceData: ReferenceSeedResult;
  admin: AdminBootstrapResult;
}

export interface StartupTasksOptions {
  migrationsDir?: string;
  waitForDbSeconds?: number;
  admin?: { username?: string; password?: string };
}

/**
 * Tugas startup idempoten: migrasi skema, seed data referensi kurikulum, dan
 * bootstrap akun admin. Seluruhnya berjalan di bawah satu advisory lock agar
 * aman bila beberapa container start bersamaan.
 */
export async function runStartupTasks(pool: Pool, options: StartupTasksOptions = {}): Promise<StartupTasksResult> {
  const waitSeconds = options.waitForDbSeconds ?? config.startup.dbWaitSeconds;
  if (waitSeconds > 0) {
    const ready = await waitForDatabase(pool, waitSeconds);
    if (!ready) {
      throw new Error(`PostgreSQL is not reachable after ${waitSeconds}s`);
    }
  }

  return withMigrationLock(pool, async (client) => {
    const appliedMigrations = await applyPendingMigrations(client, options.migrationsDir ?? MIGRATIONS_DIR);
    if (appliedMigrations.length > 0) {
      logger.info(`Applied ${appliedMigrations.length} migration(s): ${appliedMigrations.join(', ')}`);
    } else {
      logger.info('Database schema is up to date.');
    }

    const referenceData = await seedReferenceData(client);
    const admin = await ensureAdminUser(
      client,
      options.admin ?? { username: config.auth.adminUsername, password: config.auth.adminPassword }
    );
    if (admin === 'skipped') {
      logger.warn('ADMIN_USERNAME/ADMIN_PASSWORD not set: no admin account was bootstrapped.');
    }

    return { appliedMigrations, referenceData, admin };
  });
}
