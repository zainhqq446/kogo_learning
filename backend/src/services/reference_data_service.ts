import { PoolClient } from 'pg';
import vocabularyJson from '../data/vocabulary.json' with { type: 'json' };
import { logger } from '../utils/logger.js';

export interface VocabularyWord {
  order: number;
  text: string;
  syllables: string[];
  category: string;
  example?: string | null;
  image?: string | null;
}

export interface VocabularyMateri {
  code: string;
  title: string;
  order: number;
  nodeCount: number;
  words: VocabularyWord[];
}

export interface VocabularyFile {
  materi: VocabularyMateri[];
  gameTypes: Array<{ code: string; title: string }>;
  rewardTiers: Array<{ code: string; title: string; minStars: number }>;
}

/**
 * Kurikulum terkurasi (sumber kebenaran, dihasilkan dari aplikasi Flutter).
 * Di-import sebagai JSON module sehingga ikut ter-build ke `dist/data/`.
 */
export const vocabulary: VocabularyFile = vocabularyJson as VocabularyFile;

/** Judul kategori kata (WordType) dalam Bahasa Indonesia. */
const WORD_TYPE_TITLES: Record<string, string> = {
  buah: 'Buah',
  hewan: 'Hewan',
  makanan: 'Makanan',
  benda: 'Benda',
  kendaraan: 'Kendaraan',
  tubuh: 'Anggota Tubuh',
  alam: 'Alam',
};

function wordTypeTitle(code: string): string {
  return WORD_TYPE_TITLES[code] ?? code.charAt(0).toUpperCase() + code.slice(1);
}

export interface ReferenceSeedResult {
  materi: number;
  wordTypes: number;
  words: number;
  rewardTiers: number;
  removedWords: number;
}

/**
 * Seed idempoten tabel referensi (materi, word_types, words, reward_tiers)
 * dari vocabulary.json. Kata yang tidak lagi ada di JSON dihapus agar
 * database selalu sama dengan kurikulum aplikasi.
 */
export async function seedReferenceData(client: PoolClient, data: VocabularyFile = vocabulary): Promise<ReferenceSeedResult> {
  const result: ReferenceSeedResult = { materi: 0, wordTypes: 0, words: 0, rewardTiers: 0, removedWords: 0 };

  await client.query('BEGIN');
  try {
    for (const m of data.materi) {
      await client.query(
        `INSERT INTO materi (code, title, order_index, node_count) VALUES ($1, $2, $3, $4)
         ON CONFLICT (code) DO UPDATE SET title = EXCLUDED.title, order_index = EXCLUDED.order_index, node_count = EXCLUDED.node_count`,
        [m.code, m.title, m.order, m.nodeCount]
      );
      result.materi += 1;
    }

    const categories = Array.from(new Set(data.materi.flatMap((m) => m.words.map((w) => w.category)))).sort();
    for (const code of categories) {
      await client.query(
        `INSERT INTO word_types (code, title) VALUES ($1, $2)
         ON CONFLICT (code) DO UPDATE SET title = EXCLUDED.title`,
        [code, wordTypeTitle(code)]
      );
      result.wordTypes += 1;
    }

    for (const m of data.materi) {
      for (const w of m.words) {
        await client.query(
          `INSERT INTO words (materi_code, order_index, text, syllables, word_type, example_text, image_path)
           VALUES ($1, $2, $3, $4, $5, $6, $7)
           ON CONFLICT (materi_code, text) DO UPDATE
           SET order_index = EXCLUDED.order_index, syllables = EXCLUDED.syllables, word_type = EXCLUDED.word_type,
               example_text = EXCLUDED.example_text, image_path = EXCLUDED.image_path`,
          [m.code, w.order, w.text, w.syllables, w.category, w.example ?? null, w.image ?? null]
        );
        result.words += 1;
      }
      const removed = await client.query('DELETE FROM words WHERE materi_code = $1 AND NOT (text = ANY($2::text[]))', [
        m.code,
        m.words.map((w) => w.text),
      ]);
      result.removedWords += removed.rowCount ?? 0;
    }

    for (const tier of data.rewardTiers) {
      await client.query(
        `INSERT INTO reward_tiers (code, title, min_stars) VALUES ($1, $2, $3)
         ON CONFLICT (code) DO UPDATE SET title = EXCLUDED.title, min_stars = EXCLUDED.min_stars`,
        [tier.code, tier.title, tier.minStars]
      );
      result.rewardTiers += 1;
    }

    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  }

  logger.info(
    `Reference data seeded: ${result.materi} materi, ${result.wordTypes} word types, ${result.words} words, ${result.rewardTiers} reward tiers.`
  );
  return result;
}
