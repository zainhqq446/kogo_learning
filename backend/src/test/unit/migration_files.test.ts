import '../helpers/test_env.js';
import fs from 'fs';
import path from 'path';
import test from 'node:test';
import assert from 'node:assert/strict';
import { MIGRATIONS_DIR } from '../../utils/paths.js';
import { listMigrationFiles } from '../../services/migrator.js';

const read = (file: string) => fs.readFileSync(path.join(MIGRATIONS_DIR, file), 'utf8');

test('migrations: files are ordered and resolved independent of cwd', () => {
  const files = listMigrationFiles(MIGRATIONS_DIR);
  assert.deepEqual(files, [
    '001_create_kogo_research_schema.sql',
    '002_create_learning_words_table.sql',
    '003_add_child_profile_fields.sql',
    '004_thesis_erd.sql',
    '005_device_trust_and_voice_budget.sql',
  ]);
});

test('migrations: no uuid-ossp dependency; gen_random_uuid() is used everywhere', () => {
  for (const file of listMigrationFiles(MIGRATIONS_DIR)) {
    const sql = read(file);
    assert.ok(!/CREATE EXTENSION/i.test(sql), `${file} must not require extensions`);
    assert.ok(!sql.includes('uuid_generate_v4'), `${file} must not use uuid-ossp`);
  }
  assert.ok(read('001_create_kogo_research_schema.sql').includes('gen_random_uuid()'));
});

test('migration 001 keeps the legacy research entities (pseudonymous, idempotent DDL)', () => {
  const sql = read('001_create_kogo_research_schema.sql').toLowerCase();
  for (const table of [
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
  ]) {
    assert.ok(sql.includes(`create table if not exists ${table}`), table);
  }
  for (const line of sql.split('\n').filter((l) => l.trim().startsWith('create table'))) {
    assert.ok(line.includes('if not exists'), line);
  }
  assert.ok(!sql.includes('parent_phone') && !sql.includes('home_address'));
});

test('migration 004 implements the thesis ERD with constraints and indexes', () => {
  const sql = read('004_thesis_erd.sql');
  for (const table of [
    'materi',
    'word_types',
    'words',
    'reward_tiers',
    'app_devices',
    'learners',
    'game_sessions',
    'answer_attempts',
    'stars',
    'rewards',
  ]) {
    assert.match(sql, new RegExp(`CREATE TABLE IF NOT EXISTS ${table} \\(`), table);
  }
  assert.match(sql, /age SMALLINT NOT NULL CHECK \(age BETWEEN 5 AND 6\)/);
  assert.match(sql, /stars SMALLINT NOT NULL CHECK \(stars BETWEEN 0 AND 3\)/);
  assert.match(sql, /status IN \('started', 'completed', 'abandoned'\)/);
  assert.match(sql, /PRIMARY KEY \(learner_id, materi_code, node_index\)/);
  assert.match(sql, /PRIMARY KEY \(learner_id, tier_code\)/);
  assert.match(sql, /UNIQUE \(materi_code, text\)/);
  assert.match(sql, /DROP TABLE IF EXISTS learning_words/);
  assert.ok((sql.match(/CREATE INDEX IF NOT EXISTS/g) ?? []).length >= 8);
});

test('migration 005 adds device trust columns and the voice budget table', () => {
  const sql = read('005_device_trust_and_voice_budget.sql');
  for (const column of ['secret_hash', 'approved_at', 'approved_by', 'revoked_at', 'label']) {
    assert.match(sql, new RegExp(`ALTER TABLE app_devices ADD COLUMN IF NOT EXISTS ${column} `), column);
  }
  assert.match(sql, /CREATE TABLE IF NOT EXISTS voice_usage_daily \(/);
  assert.match(sql, /PRIMARY KEY \(day, metric\)/);
});
