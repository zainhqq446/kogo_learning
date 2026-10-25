import fs from 'fs';
import path from 'path';
import { Pool } from 'pg';
import { getDbPool, closeDbPool } from '../config/database.js';
import { logger } from '../utils/logger.js';
import { runMigrations } from '../services/migrator.js';

interface LearningWordItem {
  id: number;
  word_id: string;
  stage_id: number;
  stage_name: string;
  target_text: string;
  normalized_target: string;
  syllables: string;
  category: string;
  difficulty_level: 'easy' | 'medium' | 'hard';
  question_order: number;
  image_asset_path: string;
  audio_asset_path: string;
  asset_status: string;
  is_active: boolean;
}

export async function seed300Words(pool: Pool): Promise<{ total: number; inserted: number }> {
  const filePath = path.join(process.cwd(), 'src', 'data', 'learning_words_300.json');
  if (!fs.existsSync(filePath)) {
    throw new Error(`Data file not found: ${filePath}`);
  }

  const raw = fs.readFileSync(filePath, 'utf8');
  const items: LearningWordItem[] = JSON.parse(raw);

  const client = await pool.connect();
  let inserted = 0;

  try {
    await client.query('BEGIN');

    for (const item of items) {
      const existing = await client.query('SELECT id FROM learning_words WHERE word_id = $1', [
        item.word_id,
      ]);

      if (existing.rows.length === 0) {
        await client.query(
          `INSERT INTO learning_words (
            word_id, stage_id, stage_name, target_text, normalized_target,
            syllables, category, difficulty_level, question_order,
            image_asset_path, audio_asset_path, asset_status, is_active
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)`,
          [
            item.word_id,
            item.stage_id,
            item.stage_name,
            item.target_text,
            item.normalized_target,
            item.syllables,
            item.category,
            item.difficulty_level,
            item.question_order,
            item.image_asset_path,
            item.audio_asset_path,
            item.asset_status,
            item.is_active,
          ]
        );
        inserted++;
      }
    }

    await client.query('COMMIT');
    logger.info(`Seeded learning_words: ${inserted} new items, total items: ${items.length}`);
    return { total: items.length, inserted };
  } catch (err) {
    await client.query('ROLLBACK');
    logger.error('Failed to seed learning_words:', err);
    throw err;
  } finally {
    client.release();
  }
}

async function main() {
  const pool = getDbPool();

  try {
    logger.info('Running pending migrations...');
    await runMigrations(pool, path.join(process.cwd(), 'migrations'));
    logger.info('Seeding 300 learning words...');
    const res = await seed300Words(pool);
    logger.info(`Completed! Total in catalog: ${res.total}, Newly inserted: ${res.inserted}`);
  } catch (err) {
    console.error('Migration/Seeder error:', err);
    process.exit(1);
  } finally {
    await closeDbPool();
  }
}

if (process.argv[1] && process.argv[1].includes('seed_300_words')) {
  main();
}
