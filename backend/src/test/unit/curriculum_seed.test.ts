import '../helpers/test_env.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  SEED_STAGES,
  SEED_LESSONS,
  buildExpectedSeedQuestions,
  CurriculumService,
} from '../../services/curriculum_service.js';

test('Curriculum Seeding Specification & Logic Suite', async (t) => {
  await t.test('Seed definitions match exact target requirements', () => {
    assert.strictEqual(SEED_STAGES.length, 4);
    const stageTitles = SEED_STAGES.map((s) => s.title);
    assert.deepStrictEqual(stageTitles, ['Huruf', 'Dua Suku Kata', 'Tiga Suku Kata', 'Banyak Suku Kata']);

    assert.strictEqual(SEED_LESSONS.length, 20);
    for (let stageOrder = 1; stageOrder <= 4; stageOrder++) {
      const lessonsInStage = SEED_LESSONS.filter((l) => l.stage_order === stageOrder);
      assert.strictEqual(lessonsInStage.length, 5);
      const types = lessonsInStage.map((l) => l.lesson_type);
      assert.deepStrictEqual(types, ['listen_repeat', 'find_object', 'matching', 'listen_carefully', 'missing_letter']);
    }

    const allQuestions = buildExpectedSeedQuestions();
    assert.strictEqual(allQuestions.length, 49);
  });

  await t.test('Question IDs are continuous (1..49) and strictly consistent with SQLite seed execution', () => {
    const allQuestions = buildExpectedSeedQuestions();
    for (let i = 0; i < allQuestions.length; i++) {
      assert.strictEqual(allQuestions[i].expected_id, i + 1);
    }

    assert.strictEqual(allQuestions[0].expected_id, 1);
    assert.strictEqual(allQuestions[0].stage_order, 1);
    assert.strictEqual(allQuestions[0].lesson_type, 'listen_repeat');
    assert.strictEqual(allQuestions[0].target_text, 'A');
    assert.strictEqual(allQuestions[0].normalized_target, 'a');

    const lastQ = allQuestions[48];
    assert.strictEqual(lastQ.expected_id, 49);
    assert.strictEqual(lastQ.stage_order, 4);
    assert.strictEqual(lastQ.lesson_type, 'missing_letter');
    assert.strictEqual(lastQ.target_text, 'Matahari');
    assert.strictEqual(lastQ.normalized_target, 'matahari');
  });

  await t.test('CurriculumService mock transaction: Seeds all records and validates relations', async () => {
    const dbStages: any[] = [];
    const dbLessons: any[] = [];
    const dbQuestions: any[] = [];
    let lessonIdSequence = 1;

    const mockClient = {
      query: async (queryText: string, params: any[] = []) => {
        const sql = queryText.trim().replace(/\s+/g, ' ');

        if (sql.startsWith('SELECT id, title, order_index FROM stages WHERE id = $1')) {
          return { rows: dbStages.filter((s) => s.id === params[0]) };
        }
        if (sql.startsWith('SELECT id, title FROM stages WHERE order_index = $1')) {
          return { rows: dbStages.filter((s) => s.order_index === params[0]) };
        }
        if (sql.startsWith('INSERT INTO stages')) {
          dbStages.push({ id: params[0], title: params[1], description: params[2], order_index: params[3], is_active: true });
          return { rows: [] };
        }
        if (sql.startsWith('SELECT id, title, lesson_type, order_index FROM lessons WHERE stage_id = $1 AND lesson_type = $2')) {
          return { rows: dbLessons.filter((l) => l.stage_id === params[0] && l.lesson_type === params[1]) };
        }
        if (sql.startsWith('SELECT id, title FROM lessons WHERE stage_id = $1 AND order_index = $2')) {
          return { rows: dbLessons.filter((l) => l.stage_id === params[0] && l.order_index === params[1]) };
        }
        if (sql.startsWith('INSERT INTO lessons')) {
          const newId = lessonIdSequence++;
          dbLessons.push({ id: newId, stage_id: params[0], title: params[1], description: params[2], lesson_type: params[3], order_index: params[4], is_active: true });
          return { rows: [{ id: newId }] };
        }
        if (sql.startsWith('SELECT id, lesson_id, target_text, order_index FROM questions WHERE id = $1')) {
          return { rows: dbQuestions.filter((q) => q.id === params[0]) };
        }
        if (sql.startsWith('SELECT id, target_text FROM questions WHERE lesson_id = $1 AND order_index = $2')) {
          return { rows: dbQuestions.filter((q) => q.lesson_id === params[0] && q.order_index === params[1]) };
        }
        if (sql.startsWith('INSERT INTO questions')) {
          dbQuestions.push({ id: params[0], lesson_id: params[1], target_text: params[2], normalized_target: params[3], hint_text: params[4], order_index: params[5], is_active: true });
          return { rows: [] };
        }
        if (sql.includes('SELECT setval(')) {
          return { rows: [] };
        }
        if (sql.includes('COUNT(*) as count FROM stages')) {
          return { rows: [{ count: String(dbStages.length) }] };
        }
        if (sql.includes('COUNT(*) as count FROM lessons')) {
          return { rows: [{ count: String(dbLessons.length) }] };
        }
        if (sql.includes('COUNT(*) as count FROM questions')) {
          return { rows: [{ count: String(dbQuestions.length) }] };
        }
        throw new Error('Unhandled query in mockClient: ' + sql);
      },
    };

    const service = new CurriculumService({} as any);

    const res1 = await service.seedWithClient(mockClient as any);
    assert.strictEqual(res1.insertedStages, 4);
    assert.strictEqual(res1.insertedLessons, 20);
    assert.strictEqual(res1.insertedQuestions, 49);
    assert.strictEqual(res1.stagesTotal, 4);
    assert.strictEqual(res1.lessonsTotal, 20);
    assert.strictEqual(res1.questionsTotal, 49);
    assert.strictEqual(res1.alreadySeeded, false);

    const res2 = await service.seedWithClient(mockClient as any);
    assert.strictEqual(res2.insertedStages, 0);
    assert.strictEqual(res2.insertedLessons, 0);
    assert.strictEqual(res2.insertedQuestions, 0);
    assert.strictEqual(res2.stagesTotal, 4);
    assert.strictEqual(res2.lessonsTotal, 20);
    assert.strictEqual(res2.questionsTotal, 49);
    assert.strictEqual(res2.alreadySeeded, true);
  });

  await t.test('CurriculumService aborts and throws on conflicting existing data', async () => {
    const mockClientConflict = {
      query: async (queryText: string) => {
        const sql = queryText.trim().replace(/\s+/g, ' ');
        if (sql.startsWith('SELECT id, title, order_index FROM stages WHERE id = $1')) {
          return { rows: [{ id: 1, title: 'Nama Berbeda', order_index: 99 }] };
        }
        return { rows: [] };
      },
    };

    const service = new CurriculumService({} as any);
    await assert.rejects(
      async () => {
        await service.seedWithClient(mockClientConflict as any);
      },
      /Data mismatch for stage ID 1/
    );
  });
});
