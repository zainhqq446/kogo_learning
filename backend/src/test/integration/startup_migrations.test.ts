import '../helpers/test_env.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import bcrypt from 'bcrypt';
import { runStartupTasks } from '../../services/startup_service.js';
import { vocabulary } from '../../services/reference_data_service.js';
import { createTestPool } from '../helpers/db.js';

test('startup tasks: advisory-locked migrations, reference seed and admin bootstrap', async (t) => {
  const pool = await createTestPool();
  t.after(() => pool.end());

  // Mulai dari skema kosong agar seluruh migrasi diuji dari awal.
  await pool.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');

  await t.test('three concurrent starts apply each migration exactly once', async () => {
    const admin = { username: 'boot_admin', password: 'initial-password-1' };
    const results = await Promise.all([1, 2, 3].map(() => runStartupTasks(pool, { waitForDbSeconds: 0, admin })));

    assert.deepEqual(
      results.map((r) => r.appliedMigrations.length).sort(),
      [0, 0, 5],
      'only the first instance (holding the advisory lock) applies migrations'
    );
    assert.deepEqual(results.map((r) => r.admin).sort(), ['created', 'unchanged', 'unchanged']);

    const applied = await pool.query<{ name: string }>('SELECT name FROM schema_migrations ORDER BY id');
    assert.deepEqual(
      applied.rows.map((r) => r.name),
      [
        '001_create_kogo_research_schema.sql',
        '002_create_learning_words_table.sql',
        '003_add_child_profile_fields.sql',
        '004_thesis_erd.sql',
        '005_device_trust_and_voice_budget.sql',
      ]
    );
    const extensions = await pool.query("SELECT 1 FROM pg_extension WHERE extname = 'uuid-ossp'");
    assert.equal(extensions.rowCount, 0, 'uuid-ossp is not required');
  });

  await t.test('out-of-scope learning_words table is gone; reference data matches vocabulary.json', async () => {
    const legacy = await pool.query<{ reg: string | null }>("SELECT to_regclass('public.learning_words')::text AS reg");
    assert.equal(legacy.rows[0].reg, null);

    const counts = await pool.query<{ materi: number; words: number; tiers: number; types: number }>(
      `SELECT (SELECT COUNT(*) FROM materi)::int AS materi, (SELECT COUNT(*) FROM words)::int AS words,
              (SELECT COUNT(*) FROM reward_tiers)::int AS tiers, (SELECT COUNT(*) FROM word_types)::int AS types`
    );
    const expectedWords = vocabulary.materi.reduce((sum, m) => sum + m.words.length, 0);
    const expectedTypes = new Set(vocabulary.materi.flatMap((m) => m.words.map((w) => w.category))).size;
    assert.deepEqual(counts.rows[0], { materi: 4, words: expectedWords, tiers: 4, types: expectedTypes });

    const tiers = await pool.query('SELECT code, min_stars FROM reward_tiers ORDER BY min_stars');
    assert.deepEqual(
      tiers.rows.map((r) => [r.code, r.min_stars]),
      [
        ['perunggu', 10],
        ['perak', 50],
        ['emas', 150],
        ['berlian', 300],
      ]
    );
    const bola = await pool.query("SELECT syllables, word_type FROM words WHERE materi_code = 'two-syllable' AND text = 'bola'");
    assert.equal(bola.rowCount, 1);
    assert.deepEqual(bola.rows[0].syllables, ['bo', 'la']);
  });

  await t.test('re-running is idempotent, removes stale words and rotates the admin password', async () => {
    await pool.query(
      "INSERT INTO words (materi_code, order_index, text, syllables, word_type) VALUES ('multiple', 99, 'laboratorium', '{la,bo,ra,to,ri,um}', 'benda')"
    );
    const again = await runStartupTasks(pool, {
      waitForDbSeconds: 0,
      admin: { username: 'boot_admin', password: 'rotated-password-2' },
    });
    assert.deepEqual(again.appliedMigrations, []);
    assert.equal(again.admin, 'updated');
    assert.equal(again.referenceData.removedWords, 1);

    const stale = await pool.query("SELECT 1 FROM words WHERE text = 'laboratorium'");
    assert.equal(stale.rowCount, 0);

    const admin = await pool.query('SELECT password_hash, role, is_active FROM users WHERE username = $1', ['boot_admin']);
    assert.equal(admin.rows[0].role, 'admin');
    assert.equal(admin.rows[0].is_active, true);
    assert.equal(await bcrypt.compare('rotated-password-2', admin.rows[0].password_hash), true);
  });
});
