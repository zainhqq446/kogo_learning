import { Pool, PoolClient } from 'pg';
import { logger } from '../utils/logger.js';

export interface CurriculumStageDefinition {
  id: number;
  title: string;
  description: string;
  order_index: number;
}

export interface CurriculumLessonDefinition {
  stage_order: number;
  title: string;
  description: string;
  lesson_type: string;
  order_index: number;
}

export interface CurriculumQuestionDefinition {
  stage_order: number;
  lesson_type: string;
  target_text: string;
  normalized_target: string;
  hint_text: string;
  order_index: number;
  expected_id: number;
}

export const SEED_STAGES: CurriculumStageDefinition[] = [
  { id: 1, title: 'Huruf', description: 'Belajar mengenal dan mengucapkan huruf.', order_index: 1 },
  { id: 2, title: 'Dua Suku Kata', description: 'Belajar membaca dan mengucapkan dua suku kata.', order_index: 2 },
  { id: 3, title: 'Tiga Suku Kata', description: 'Belajar membaca dan mengucapkan tiga suku kata.', order_index: 3 },
  { id: 4, title: 'Banyak Suku Kata', description: 'Belajar mengucapkan kata yang lebih panjang.', order_index: 4 },
];

export const SEED_LESSONS: CurriculumLessonDefinition[] = [
  // Stage 1
  { stage_order: 1, title: 'Listen & Repeat', description: 'Dengarkan contoh lalu ulangi.', lesson_type: 'listen_repeat', order_index: 1 },
  { stage_order: 1, title: 'Find Object', description: 'Temukan objek yang sesuai.', lesson_type: 'find_object', order_index: 2 },
  { stage_order: 1, title: 'Matching Object', description: 'Pasangkan objek yang sesuai.', lesson_type: 'matching', order_index: 3 },
  { stage_order: 1, title: 'Listen Carefully', description: 'Dengarkan dan pilih jawaban yang benar.', lesson_type: 'listen_carefully', order_index: 4 },
  { stage_order: 1, title: 'Missing Letter', description: 'Lengkapi huruf yang hilang.', lesson_type: 'missing_letter', order_index: 5 },
  // Stage 2
  { stage_order: 2, title: 'Listen & Repeat', description: 'Dengarkan contoh lalu ulangi.', lesson_type: 'listen_repeat', order_index: 1 },
  { stage_order: 2, title: 'Find Object', description: 'Temukan objek yang sesuai.', lesson_type: 'find_object', order_index: 2 },
  { stage_order: 2, title: 'Matching Object', description: 'Pasangkan objek yang sesuai.', lesson_type: 'matching', order_index: 3 },
  { stage_order: 2, title: 'Listen Carefully', description: 'Dengarkan dan pilih jawaban yang benar.', lesson_type: 'listen_carefully', order_index: 4 },
  { stage_order: 2, title: 'Missing Letter', description: 'Lengkapi huruf yang hilang.', lesson_type: 'missing_letter', order_index: 5 },
  // Stage 3
  { stage_order: 3, title: 'Listen & Repeat', description: 'Dengarkan contoh lalu ulangi.', lesson_type: 'listen_repeat', order_index: 1 },
  { stage_order: 3, title: 'Find Object', description: 'Temukan objek yang sesuai.', lesson_type: 'find_object', order_index: 2 },
  { stage_order: 3, title: 'Matching Object', description: 'Pasangkan objek yang sesuai.', lesson_type: 'matching', order_index: 3 },
  { stage_order: 3, title: 'Listen Carefully', description: 'Dengarkan dan pilih jawaban yang benar.', lesson_type: 'listen_carefully', order_index: 4 },
  { stage_order: 3, title: 'Missing Letter', description: 'Lengkapi huruf yang hilang.', lesson_type: 'missing_letter', order_index: 5 },
  // Stage 4
  { stage_order: 4, title: 'Listen & Repeat', description: 'Dengarkan contoh lalu ulangi.', lesson_type: 'listen_repeat', order_index: 1 },
  { stage_order: 4, title: 'Find Object', description: 'Temukan objek yang sesuai.', lesson_type: 'find_object', order_index: 2 },
  { stage_order: 4, title: 'Matching Object', description: 'Pasangkan objek yang sesuai.', lesson_type: 'matching', order_index: 3 },
  { stage_order: 4, title: 'Listen Carefully', description: 'Dengarkan dan pilih jawaban yang benar.', lesson_type: 'listen_carefully', order_index: 4 },
  { stage_order: 4, title: 'Missing Letter', description: 'Lengkapi huruf yang hilang.', lesson_type: 'missing_letter', order_index: 5 },
];

export const RAW_STAGE_QUESTIONS_MAP: Record<number, Record<string, { target_text: string; hint_text: string }[]>> = {
  1: {
    listen_repeat: [
      { target_text: 'A', hint_text: 'Ucapkan huruf A' },
      { target_text: 'B', hint_text: 'Ucapkan huruf B' },
      { target_text: 'C', hint_text: 'Ucapkan huruf C' },
      { target_text: 'D', hint_text: 'Ucapkan huruf D' },
      { target_text: 'E', hint_text: 'Ucapkan huruf E' },
    ],
    find_object: [
      { target_text: 'Apel', hint_text: 'Cari benda berawalan huruf A' },
      { target_text: 'Bola', hint_text: 'Cari benda berawalan huruf B' },
    ],
    matching: [
      { target_text: 'A - Apel', hint_text: 'Pasangkan huruf A dengan Apel' },
      { target_text: 'B - Bola', hint_text: 'Pasangkan huruf B dengan Bola' },
    ],
    listen_carefully: [
      { target_text: 'A', hint_text: 'Dengarkan baik-baik lalu pilih huruf A' },
      { target_text: 'B', hint_text: 'Dengarkan baik-baik lalu pilih huruf B' },
    ],
    missing_letter: [
      { target_text: 'Apel', hint_text: 'Lengkapi huruf pada kata Apel' },
      { target_text: 'Bola', hint_text: 'Lengkapi huruf pada kata Bola' },
    ],
  },
  2: {
    listen_repeat: [
      { target_text: 'Buku', hint_text: 'Ucapkan kata Bu-ku' },
      { target_text: 'Bola', hint_text: 'Ucapkan kata Bo-la' },
      { target_text: 'Meja', hint_text: 'Ucapkan kata Me-ja' },
      { target_text: 'Sapi', hint_text: 'Ucapkan kata Sa-pi' },
      { target_text: 'Kaki', hint_text: 'Ucapkan kata Ka-ki' },
    ],
    find_object: [
      { target_text: 'Buku', hint_text: 'Temukan gambar Buku' },
      { target_text: 'Meja', hint_text: 'Temukan gambar Meja' },
    ],
    matching: [
      { target_text: 'Bu - ku', hint_text: 'Pasangkan suku kata Bu dan ku' },
      { target_text: 'Me - ja', hint_text: 'Pasangkan suku kata Me dan ja' },
    ],
    listen_carefully: [
      { target_text: 'Buku', hint_text: 'Dengarkan lalu pilih kata Buku' },
      { target_text: 'Bola', hint_text: 'Dengarkan lalu pilih kata Bola' },
    ],
    missing_letter: [
      { target_text: 'Buku', hint_text: 'Lengkapi huruf yang hilang pada Buku' },
      { target_text: 'Meja', hint_text: 'Lengkapi huruf yang hilang pada Meja' },
    ],
  },
  3: {
    listen_repeat: [
      { target_text: 'Sepatu', hint_text: 'Ucapkan kata Se-pa-tu' },
      { target_text: 'Kereta', hint_text: 'Ucapkan kata Ke-re-ta' },
      { target_text: 'Kelinci', hint_text: 'Ucapkan kata Ke-lin-ci' },
      { target_text: 'Kamera', hint_text: 'Ucapkan kata Ka-me-ra' },
    ],
    find_object: [
      { target_text: 'Sepatu', hint_text: 'Temukan objek Sepatu' },
      { target_text: 'Kelinci', hint_text: 'Temukan hewan Kelinci' },
    ],
    matching: [
      { target_text: 'Se - pa - tu', hint_text: 'Susun tiga suku kata Sepatu' },
      { target_text: 'Ke - re - ta', hint_text: 'Susun tiga suku kata Kereta' },
    ],
    listen_carefully: [
      { target_text: 'Sepatu', hint_text: 'Dengarkan suara dan pilih Sepatu' },
      { target_text: 'Kereta', hint_text: 'Dengarkan suara dan pilih Kereta' },
    ],
    missing_letter: [
      { target_text: 'Sepatu', hint_text: 'Lengkapi huruf pada Sepatu' },
      { target_text: 'Kereta', hint_text: 'Lengkapi huruf pada Kereta' },
    ],
  },
  4: {
    listen_repeat: [
      { target_text: 'Helikopter', hint_text: 'Ucapkan kata He-li-kop-ter' },
      { target_text: 'Matahari', hint_text: 'Ucapkan kata Ma-ta-ha-ri' },
      { target_text: 'Laboratorium', hint_text: 'Ucapkan kata La-bo-ra-to-ri-um' },
    ],
    find_object: [
      { target_text: 'Helikopter', hint_text: 'Temukan gambar Helikopter' },
      { target_text: 'Matahari', hint_text: 'Temukan gambar Matahari' },
    ],
    matching: [
      { target_text: 'He - li - kop - ter', hint_text: 'Cocokkan suku kata Helikopter' },
      { target_text: 'Ma - ta - ha - ri', hint_text: 'Cocokkan suku kata Matahari' },
    ],
    listen_carefully: [
      { target_text: 'Helikopter', hint_text: 'Dengarkan lalu pilih Helikopter' },
      { target_text: 'Matahari', hint_text: 'Dengarkan lalu pilih Matahari' },
    ],
    missing_letter: [
      { target_text: 'Helikopter', hint_text: 'Lengkapi huruf pada Helikopter' },
      { target_text: 'Matahari', hint_text: 'Lengkapi huruf pada Matahari' },
    ],
  },
};

export function buildExpectedSeedQuestions(): CurriculumQuestionDefinition[] {
  const result: CurriculumQuestionDefinition[] = [];
  let questionCounter = 1;

  for (let stageOrder = 1; stageOrder <= 4; stageOrder++) {
    const stageQuestions = RAW_STAGE_QUESTIONS_MAP[stageOrder];
    if (!stageQuestions) continue;

    for (const [lessonType, qList] of Object.entries(stageQuestions)) {
      for (let i = 0; i < qList.length; i++) {
        const item = qList[i];
        result.push({
          stage_order: stageOrder,
          lesson_type: lessonType,
          target_text: item.target_text,
          normalized_target: item.target_text.toLowerCase().trim(),
          hint_text: item.hint_text,
          order_index: i + 1,
          expected_id: questionCounter++,
        });
      }
    }
  }

  return result;
}

export interface SeedCurriculumResult {
  insertedStages: number;
  insertedLessons: number;
  insertedQuestions: number;
  stagesTotal: number;
  lessonsTotal: number;
  questionsTotal: number;
  alreadySeeded: boolean;
}

export class CurriculumService {
  constructor(private pool: Pool) {}

  async seedCurriculum(): Promise<SeedCurriculumResult> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await this.seedWithClient(client);
      await client.query('COMMIT');
      return result;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  async seedWithClient(client: PoolClient): Promise<SeedCurriculumResult> {
    let insertedStages = 0;
    let insertedLessons = 0;
    let insertedQuestions = 0;

    // 1. STAGES
    for (const stage of SEED_STAGES) {
      const existing = await client.query<{ id: number; title: string; order_index: number }>(
        'SELECT id, title, order_index FROM stages WHERE id = $1',
        [stage.id]
      );

      if (existing.rows.length === 0) {
        const conflictOrder = await client.query(
          'SELECT id, title FROM stages WHERE order_index = $1',
          [stage.order_index]
        );
        if (conflictOrder.rows.length > 0) {
          throw new Error(
            'Conflict in stages: order_index ' + stage.order_index + ' already used by stage id ' + conflictOrder.rows[0].id
          );
        }

        await client.query(
          'INSERT INTO stages (id, title, description, order_index, is_active) VALUES ($1, $2, $3, $4, true)',
          [stage.id, stage.title, stage.description, stage.order_index]
        );
        insertedStages++;
      } else {
        const row = existing.rows[0];
        if (row.title !== stage.title || row.order_index !== stage.order_index) {
          throw new Error(
            'Data mismatch for stage ID ' + stage.id + ': DB has (' + row.title + ', order ' + row.order_index + '), seed expects (' + stage.title + ', order ' + stage.order_index + ')'
          );
        }
      }
    }

    // 2. LESSONS
    const lessonIdMap = new Map<string, number>();

    for (const lesson of SEED_LESSONS) {
      const stageId = lesson.stage_order;
      const existing = await client.query<{ id: number; title: string; lesson_type: string; order_index: number }>(
        'SELECT id, title, lesson_type, order_index FROM lessons WHERE stage_id = $1 AND lesson_type = $2',
        [stageId, lesson.lesson_type]
      );

      let actualLessonId: number;

      if (existing.rows.length === 0) {
        const conflictOrder = await client.query(
          'SELECT id, title FROM lessons WHERE stage_id = $1 AND order_index = $2',
          [stageId, lesson.order_index]
        );
        if (conflictOrder.rows.length > 0) {
          throw new Error(
            'Conflict in lessons: stage_id ' + stageId + ' already has order_index ' + lesson.order_index
          );
        }

        const insertRes = await client.query<{ id: number }>(
          'INSERT INTO lessons (stage_id, title, description, lesson_type, order_index, is_active) VALUES ($1, $2, $3, $4, $5, true) RETURNING id',
          [stageId, lesson.title, lesson.description, lesson.lesson_type, lesson.order_index]
        );
        actualLessonId = insertRes.rows[0].id;
        insertedLessons++;
      } else {
        const row = existing.rows[0];
        if (row.title !== lesson.title || row.order_index !== lesson.order_index) {
          throw new Error(
            'Data mismatch for lesson in stage ' + stageId + ' (' + lesson.lesson_type + ')'
          );
        }
        actualLessonId = row.id;
      }

      lessonIdMap.set(stageId + ':' + lesson.lesson_type, actualLessonId);
    }

    // 3. QUESTIONS
    const expectedQuestions = buildExpectedSeedQuestions();

    for (const q of expectedQuestions) {
      const lessonId = lessonIdMap.get(q.stage_order + ':' + q.lesson_type);
      if (!lessonId) {
        throw new Error('Referenced lesson not found for stage ' + q.stage_order + ', type ' + q.lesson_type);
      }

      const existingById = await client.query<{ id: number; lesson_id: number; target_text: string; order_index: number }>(
        'SELECT id, lesson_id, target_text, order_index FROM questions WHERE id = $1',
        [q.expected_id]
      );

      if (existingById.rows.length === 0) {
        const conflictOrder = await client.query<{ id: number; target_text: string }>(
          'SELECT id, target_text FROM questions WHERE lesson_id = $1 AND order_index = $2',
          [lessonId, q.order_index]
        );
        if (conflictOrder.rows.length > 0) {
          throw new Error(
            'Conflict in questions: lesson_id ' + lessonId + ' already has order_index ' + q.order_index
          );
        }

        await client.query(
          'INSERT INTO questions (id, lesson_id, target_text, normalized_target, hint_text, order_index, is_active) VALUES ($1, $2, $3, $4, $5, $6, true)',
          [q.expected_id, lessonId, q.target_text, q.normalized_target, q.hint_text, q.order_index]
        );
        insertedQuestions++;
      } else {
        const row = existingById.rows[0];
        if (row.lesson_id !== lessonId || row.target_text !== q.target_text || row.order_index !== q.order_index) {
          throw new Error(
            'Data mismatch for question ID ' + q.expected_id
          );
        }
      }
    }

    // 4. Synchronize sequence PostgreSQL
    await this.synchronizeSequences(client);

    // 5. Total count verification
    const stagesCountRes = await client.query<{ count: string }>('SELECT COUNT(*) as count FROM stages');
    const lessonsCountRes = await client.query<{ count: string }>('SELECT COUNT(*) as count FROM lessons');
    const questionsCountRes = await client.query<{ count: string }>('SELECT COUNT(*) as count FROM questions');

    const stagesTotal = parseInt(stagesCountRes.rows[0].count, 10);
    const lessonsTotal = parseInt(lessonsCountRes.rows[0].count, 10);
    const questionsTotal = parseInt(questionsCountRes.rows[0].count, 10);

    const alreadySeeded = insertedStages === 0 && insertedLessons === 0 && insertedQuestions === 0;

    return {
      insertedStages,
      insertedLessons,
      insertedQuestions,
      stagesTotal,
      lessonsTotal,
      questionsTotal,
      alreadySeeded,
    };
  }

  async synchronizeSequences(client: PoolClient): Promise<void> {
    const tables = [
      { table: 'stages', col: 'id' },
      { table: 'lessons', col: 'id' },
      { table: 'questions', col: 'id' },
    ];

    for (const { table, col } of tables) {
      await client.query(
        'SELECT setval(pg_get_serial_sequence($1, $2), COALESCE((SELECT MAX(' + col + ') FROM ' + table + '), 0) + 1, false);',
        [table, col]
      );
    }
  }
}
