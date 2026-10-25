import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

test('Database Migrations Validation Suite', async (t) => {
  const migrationsDir = path.resolve(__dirname, '../../migrations');

  await t.test('Migrations directory exists and contains valid SQL files', () => {
    assert.ok(fs.existsSync(migrationsDir), 'Migrations directory should exist');
    const files = fs.readdirSync(migrationsDir).filter((f) => f.endsWith('.sql'));
    assert.ok(files.length > 0, 'Should have at least 1 migration SQL file');
    assert.ok(files.includes('001_create_kogo_research_schema.sql'), 'Initial migration 001 should exist');
  });

  await t.test('Migration 001 contains all mandatory research entities', () => {
    const file001 = path.join(migrationsDir, '001_create_kogo_research_schema.sql');
    const sql = fs.readFileSync(file001, 'utf8');

    // Cek ekstensi UUID
    assert.ok(sql.includes('uuid-ossp') || sql.includes('uuid_generate_v4'), 'UUID extension or generator should be defined');

    // Cek tabel-tabel utama
    const expectedTables = [
      'users',
      'participants',
      'devices',
      'stages',
      'lessons',
      'questions',
      'research_sessions',
      'speech_attempts',
      'similarity_evaluations',
      'audit_logs',
    ];

    for (const table of expectedTables) {
      assert.ok(
        sql.toLowerCase().includes(`create table if not exists ${table}`),
        `Table '${table}' definition should exist in migration SQL`
      );
    }

    // Cek integritas kolom kritis
    assert.ok(sql.includes('client_session_uuid'), 'research_sessions must have client_session_uuid');
    assert.ok(sql.includes('client_attempt_uuid'), 'speech_attempts must have client_attempt_uuid');
    assert.ok(sql.includes('similarity_score'), 'similarity_evaluations must have similarity_score');
    assert.ok(sql.includes('similarity_percent'), 'similarity_evaluations must have similarity_percent');
    assert.ok(sql.includes('is_correct'), 'similarity_evaluations must have is_correct');
    assert.ok(sql.includes('edit_distance'), 'similarity_evaluations must have edit_distance');
    assert.ok(sql.includes('evaluation_status'), 'similarity_evaluations must have evaluation_status');
  });

  await t.test('Idempotency: All DDL statements use IF NOT EXISTS', () => {
    const file001 = path.join(migrationsDir, '001_create_kogo_research_schema.sql');
    const sql = fs.readFileSync(file001, 'utf8');

    const lines = sql.split('\n');
    const createTableLines = lines.filter((l) => l.trim().toUpperCase().startsWith('CREATE TABLE'));
    for (const line of createTableLines) {
      assert.ok(
        line.toUpperCase().includes('IF NOT EXISTS'),
        `Create table statement should be idempotent: ${line}`
      );
    }
  });

  await t.test('Privacy compliance: No plain PII in participants table', () => {
    const file001 = path.join(migrationsDir, '001_create_kogo_research_schema.sql');
    const sql = fs.readFileSync(file001, 'utf8').toLowerCase();

    assert.ok(!sql.includes('nik'), 'Should not contain NIK');
    assert.ok(!sql.includes('student_national_id'), 'Should not contain national student ID');
    assert.ok(!sql.includes('parent_phone'), 'Should not contain parent phone');
    assert.ok(!sql.includes('home_address'), 'Should not contain home address');
    assert.ok(sql.includes('participant_code'), 'Should use pseudonymous participant_code');
  });
});