import path from 'path';
import { fileURLToPath } from 'url';
import { Pool } from 'pg';
import { config } from '../config/env.js';
import { runMigrations } from '../services/migrator.js';
import { CurriculumService } from '../services/curriculum_service.js';
import { ResearchService } from '../services/research_service.js';
import { logger } from '../utils/logger.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const ALLOWED_E2E_DATABASES = ['kogo_curriculum_e2e_test'];
const TARGET_DB = process.env.TEST_DB_NAME || 'kogo_curriculum_e2e_test';

async function main() {
  logger.info('====================================================');
  logger.info('?? Setup Isolated E2E Database: ' + TARGET_DB);
  logger.info('====================================================');

  // Tahap 1: Validasi Allowlist Database
  logger.info('[Tahap 1/7] Memvalidasi nama database target...');
  if (!ALLOWED_E2E_DATABASES.includes(TARGET_DB)) {
    logger.error('CRITICAL ERROR: Target database   + TARGET_DB +  is not in the approved E2E allowlist!');
    logger.error('Approved databases: ' + ALLOWED_E2E_DATABASES.join(', '));
    process.exit(1);
  }

  if (TARGET_DB === 'kogo_research' || TARGET_DB === 'kogo_research_test') {
    logger.error('CRITICAL GUARD: Target database cannot be kogo_research or kogo_research_test!');
    process.exit(1);
  }

  // Tahap 2: Koneksi Administratif & Pengecekan/Pembuatan Database
  logger.info('[Tahap 2/7] Memeriksa keberadaan database ' + TARGET_DB + ' via admin connection (postgres)...');
  const adminPool = new Pool({
    host: config.database.host,
    port: config.database.port,
    database: 'postgres',
    user: config.database.user,
    password: config.database.password,
    ssl: config.database.ssl ? { rejectUnauthorized: false } : false,
  });

  try {
    const dbExistsRes = await adminPool.query(
      'SELECT 1 FROM pg_database WHERE datname = $1',
      [TARGET_DB]
    );

    if (dbExistsRes.rowCount === 0) {
      logger.info('Database ' + TARGET_DB + ' belum ada. Membuat database baru...');
      if (!/^[a-zA-Z0-9_]+$/.test(TARGET_DB)) {
        throw new Error('Invalid database name format: ' + TARGET_DB);
      }
      await adminPool.query('CREATE DATABASE ' + TARGET_DB);
      logger.info('? Database ' + TARGET_DB + ' berhasil dibuat.');
    } else {
      logger.info('??  Database ' + TARGET_DB + ' sudah ada. Mempertahankan database eksisting.');
    }
  } finally {
    await adminPool.end();
  }

  // Tahap 3: Menghubungkan Langsung ke Database E2E
  logger.info('[Tahap 3/7] Menghubungkan pool khusus ke ' + TARGET_DB + '...');
  const e2ePool = new Pool({
    host: config.database.host,
    port: config.database.port,
    database: TARGET_DB,
    user: config.database.user,
    password: config.database.password,
    ssl: config.database.ssl ? { rejectUnauthorized: false } : false,
  });

  try {
    const dbCheck = await e2ePool.query('SELECT current_database() as db_name');
    const activeDb = dbCheck.rows[0].db_name;
    if (activeDb !== TARGET_DB) {
      throw new Error('Connection mismatch! Expected: ' + TARGET_DB + ', Active: ' + activeDb);
    }
    logger.info('? Terhubung secara valid ke database: ' + activeDb);

    // Tahap 4: Menjalankan Migrasi Skema
    const migrationsDir = path.resolve(__dirname, '../../migrations');
    logger.info('[Tahap 4/7] Menjalankan migrasi skema pada ' + TARGET_DB + '...');
    const applied = await runMigrations(e2ePool, migrationsDir);
    logger.info('? Migrasi skema selesai. File baru diaplikasikan: ' + applied.length);

    // Tahap 5: Seeding Kurikulum Lengkap
    logger.info('[Tahap 5/7] Menjalankan seeder kurikulum resmi (4 stages, 20 lessons, 49 questions)...');
    const curriculumService = new CurriculumService(e2ePool);
    const seedResult = await curriculumService.seedCurriculum();
    if (seedResult.alreadySeeded) {
      logger.info('??  Kurikulum sudah ter-seed. Stages: ' + seedResult.stagesTotal + ', Lessons: ' + seedResult.lessonsTotal + ', Questions: ' + seedResult.questionsTotal);
    } else {
      logger.info('? Kurikulum berhasil di-seed! Stages: +' + seedResult.insertedStages + ', Lessons: +' + seedResult.insertedLessons + ', Questions: +' + seedResult.insertedQuestions);
    }

    // Tahap 6: Memastikan Fixture Participant TEST001
    logger.info('[Tahap 6/7] Memeriksa fixture participant TEST001...');
    const researchService = new ResearchService(e2ePool);
    const existingP = await e2ePool.query(
      'SELECT id, participant_code, display_alias FROM participants WHERE participant_code = $1',
      ['TEST001']
    );

    if (existingP.rowCount === 0) {
      logger.info('Mendaftarkan participant uji TEST001...');
      await researchService.createParticipant({
        participantCode: 'TEST001',
        displayAlias: 'Peserta Uji',
        ageYears: 5,
        gender: 'M',
        pin: '1234',
      });
      logger.info('? Participant TEST001 berhasil didaftarkan.');
    } else {
      const p = existingP.rows[0];
      if (p.participant_code !== 'TEST001') {
        throw new Error('Conflicting participant data detected for TEST001');
      }
      logger.info('??  Participant TEST001 sudah terdaftar.');
    }

    // Tahap 7: Memastikan Fixture Device KOGO-TEST-WIN-001
    logger.info('[Tahap 7/7] Memeriksa fixture device KOGO-TEST-WIN-001...');
    const existingD = await e2ePool.query(
      'SELECT id, device_identifier, device_label FROM devices WHERE device_identifier = $1',
      ['KOGO-TEST-WIN-001']
    );

    if (existingD.rowCount === 0) {
      logger.info('Mendaftarkan device uji KOGO-TEST-WIN-001...');
      await researchService.registerDevice({
        deviceIdentifier: 'KOGO-TEST-WIN-001',
        deviceLabel: 'Perangkat Uji Lokal',
        platform: 'windows',
        appVersion: '1.0.0',
      });
      logger.info('? Device KOGO-TEST-WIN-001 berhasil didaftarkan.');
    } else {
      const d = existingD.rows[0];
      if (d.device_identifier !== 'KOGO-TEST-WIN-001') {
        throw new Error('Conflicting device data detected for KOGO-TEST-WIN-001');
      }
      logger.info('??  Device KOGO-TEST-WIN-001 sudah terdaftar.');
    }

    logger.info('====================================================');
    logger.info('?? Database E2E ' + TARGET_DB + ' selesai disiapkan dan siap digunakan!');
    logger.info('====================================================');
  } finally {
    await e2ePool.end();
  }
}

main().catch((err) => {
  logger.error('Setup E2E database failed:', err instanceof Error ? err.message : String(err));
  process.exit(1);
});
