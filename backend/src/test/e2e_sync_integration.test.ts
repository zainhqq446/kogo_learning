import test from 'node:test';
import assert from 'node:assert/strict';
import { Pool } from 'pg';
import { Server } from 'http';
import { config } from '../config/env.js';
import { createApp } from '../app.js';
import { setDbPool } from '../config/database.js';
import { AuthService } from '../services/auth_service.js';
import { randomUUID } from 'node:crypto';

/**
 * End-to-End Integration Test: Batch Sync Protocol (/api/research/sync/batch)
 *
 * Persyaratan Keamanan Database:
 * 1. Tidak boleh menyentuh database utama kogo_research.
 * 2. Hanya boleh berjalan pada database khusus E2E yang disetujui (default: kogo_curriculum_e2e_test).
 * 3. Menolak database kogo_research dan kogo_research_test.
 * 4. Menjalankan pemeriksaan ketat SELECT current_database() sebelum operasi apa pun.
 * 5. Menggunakan kurikulum resmi: Question ID 1 dengan target A.
 * 6. Menggunakan fixture TEST001 dan KOGO-TEST-WIN-001.
 */
test('E2E Sync Integration Test: Batch Sync Protocol', async (t) => {
  const ALLOWED_E2E_DATABASES = ['kogo_curriculum_e2e_test'];
  const TEST_DB_NAME = process.env.TEST_DB_NAME || 'kogo_curriculum_e2e_test';

  // 1. Strict Allowlist & Guard Validation
  assert.ok(
    ALLOWED_E2E_DATABASES.includes(TEST_DB_NAME),
    'FATAL GUARD: Target database   + TEST_DB_NAME +  is not permitted! Must be in allowlist: ' + ALLOWED_E2E_DATABASES.join(', ')
  );
  assert.notStrictEqual(
    TEST_DB_NAME,
    'kogo_research',
    'FATAL GUARD: Attempted to run E2E test on production database kogo_research!'
  );
  assert.notStrictEqual(
    TEST_DB_NAME,
    'kogo_research_test',
    'FATAL GUARD: Attempted to run E2E test on fixture-divergent database kogo_research_test!'
  );

  const testPool = new Pool({
    host: config.database.host,
    port: config.database.port,
    database: TEST_DB_NAME,
    user: config.database.user,
    password: config.database.password,
    ssl: config.database.ssl ? { rejectUnauthorized: false } : false,
  });

  const authService = new AuthService(testPool);
  let server: Server | undefined;
  let baseUrl = '';

  // UUID unik terisolasi untuk tes ini
  const testSessionUuid = randomUUID();
  const testAttemptUuid = randomUUID();

  try {
    // 2. Runtime Guard Assertion: Verifikasi koneksi fisik benar-benar mengarah ke TEST_DB_NAME
    const dbCheck = await testPool.query('SELECT current_database() as db_name');
    const activeDb = dbCheck.rows[0].db_name;
    assert.strictEqual(
      activeDb,
      TEST_DB_NAME,
      'FATAL GUARD: Connected database mismatch! Expected: ' + TEST_DB_NAME + ', Actual: ' + activeDb
    );

    // 3. Setup server Express pada port dinamis (port 0) dengan pool terisolasi
    await t.test('Setup isolated Express server on dynamic ephemeral port', async () => {
      setDbPool(testPool);
      const app = createApp();
      return new Promise<void>((resolve, reject) => {
        server = app.listen(0, () => {
          const address = server?.address();
          if (address && typeof address === 'object') {
            baseUrl = 'http://127.0.0.1:' + address.port;
          }
          resolve();
        });
        server.on('error', reject);
      });
    });

    // 4. Pre-kondisi: Validasi kurikulum resmi (Question 1 = A) dan fixture relasional (TEST001, KOGO-TEST-WIN-001)
    await t.test('Pre-condition: Validate official curriculum and test fixtures in E2E database', async () => {
      const qRes = await testPool.query(
        'SELECT id, target_text, normalized_target FROM questions WHERE id = $1',
        [1]
      );
      assert.strictEqual(qRes.rowCount, 1, 'Question ID 1 must exist in E2E database');
      assert.strictEqual(qRes.rows[0].target_text, 'A', 'Official curriculum Question 1 target must be A');

      const pRes = await testPool.query(
        'SELECT id, participant_code FROM participants WHERE participant_code = $1',
        ['TEST001']
      );
      assert.strictEqual(pRes.rowCount, 1, 'Participant TEST001 must exist in E2E database');

      const dRes = await testPool.query(
        'SELECT id, device_identifier FROM devices WHERE device_identifier = $1',
        ['KOGO-TEST-WIN-001']
      );
      assert.strictEqual(dRes.rowCount, 1, 'Device KOGO-TEST-WIN-001 must exist in E2E database');
    });

    // 5. Pengujian POST /api/research/sync/batch (First Submission)
    await t.test('POST /api/research/sync/batch - Successfully process session, attempt, and evaluations', async () => {
      const researcherTokens = authService.generateTokens({
        userId: '111e4567-e89b-12d3-a456-426614174111',
        username: 'dr_researcher',
        role: 'researcher',
      });

      const payload = {
        sessions: [
          {
            clientSessionUuid: testSessionUuid,
            participantCode: 'TEST001',
            deviceIdentifier: 'KOGO-TEST-WIN-001',
            sessionSequenceNumber: 1,
            startedAt: new Date().toISOString(),
            endedAt: new Date().toISOString(),
            notes: 'E2E isolated sync test session',
          },
        ],
        attempts: [
          {
            clientAttemptUuid: testAttemptUuid,
            clientSessionUuid: testSessionUuid,
            participantCode: 'TEST001',
            deviceIdentifier: 'KOGO-TEST-WIN-001',
            questionId: 1,
            attemptNumber: 1,
            targetText: 'A',
            recognizedText: 'a',
            asrProvider: 'whisper_onnx',
            locale: 'id_ID',
            asrConfidence: 0.99,
            durationMs: 400,
            attemptedAt: new Date().toISOString(),
            evaluation: {
              normalizedTarget: 'a',
              normalizedRecognized: 'a',
              editDistance: 0,
              similarityScore: 1.0,
              similarityPercent: 100.0,
              isCorrect: true,
              evaluationStatus: 'EXACT_MATCH' as const,
              thresholdUsed: 1.0,
              evaluationMethod: 'levenshtein_normalized_v1',
              feedbackText: 'Hebat! Tepat Sekali',
            },
          },
        ],
      };

      const res = await fetch(baseUrl + '/api/research/sync/batch', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: 'Bearer ' + researcherTokens.accessToken,
        },
        body: JSON.stringify(payload),
      });

      assert.strictEqual(res.status, 200, 'Endpoint should return HTTP 200');
      const data = (await res.json()) as any;
      assert.strictEqual(data.status, 'success');
      assert.strictEqual(data.data.summary.totalSessions, 1);
      assert.strictEqual(data.data.summary.syncedSessions, 1);
      assert.strictEqual(data.data.summary.totalAttempts, 1);
      assert.strictEqual(data.data.summary.syncedAttempts, 1);
      assert.strictEqual(data.data.summary.failedItems, 0);

      assert.strictEqual(data.data.sessions[0].status, 'created');
      assert.strictEqual(data.data.attempts[0].status, 'created');

      // Verifikasi Foreign Key di database secara langsung dengan parameter 
      const attemptRow = await testPool.query(
        'SELECT session_id, participant_id, device_id, question_id, target_text FROM speech_attempts WHERE client_attempt_uuid = $1',
        [testAttemptUuid]
      );
      assert.strictEqual(attemptRow.rowCount, 1);
      assert.strictEqual(attemptRow.rows[0].question_id, 1, 'Question ID FK must match 1');
      assert.strictEqual(attemptRow.rows[0].target_text, 'A');

      const evalRow = await testPool.query(
        'SELECT is_correct, similarity_percent FROM similarity_evaluations WHERE attempt_id = (SELECT id FROM speech_attempts WHERE client_attempt_uuid = $1)',
        [testAttemptUuid]
      );
      assert.strictEqual(evalRow.rowCount, 1);
      assert.strictEqual(evalRow.rows[0].is_correct, true);
      assert.strictEqual(Number(evalRow.rows[0].similarity_percent), 100.0);
    });

    // 6. Pengujian Idempotensi (Repeated Submission with Same UUIDs)
    await t.test('POST /api/research/sync/batch - Idempotency returns already_synced without duplicate records', async () => {
      const researcherTokens = authService.generateTokens({
        userId: '111e4567-e89b-12d3-a456-426614174111',
        username: 'dr_researcher',
        role: 'researcher',
      });

      const repeatedPayload = {
        sessions: [
          {
            clientSessionUuid: testSessionUuid,
            participantCode: 'TEST001',
            deviceIdentifier: 'KOGO-TEST-WIN-001',
            sessionSequenceNumber: 1,
            startedAt: new Date().toISOString(),
            notes: 'E2E isolated sync repeated payload',
          },
        ],
        attempts: [
          {
            clientAttemptUuid: testAttemptUuid,
            clientSessionUuid: testSessionUuid,
            participantCode: 'TEST001',
            deviceIdentifier: 'KOGO-TEST-WIN-001',
            questionId: 1,
            attemptNumber: 1,
            targetText: 'A',
            recognizedText: 'a',
            attemptedAt: new Date().toISOString(),
            evaluation: {
              normalizedTarget: 'a',
              normalizedRecognized: 'a',
              editDistance: 0,
              similarityScore: 1.0,
              similarityPercent: 100.0,
              isCorrect: true,
              evaluationStatus: 'EXACT_MATCH' as const,
            },
          },
        ],
      };

      const res = await fetch(baseUrl + '/api/research/sync/batch', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: 'Bearer ' + researcherTokens.accessToken,
        },
        body: JSON.stringify(repeatedPayload),
      });

      assert.strictEqual(res.status, 200);
      const data = (await res.json()) as any;
      assert.strictEqual(data.data.summary.failedItems, 0);
      assert.strictEqual(data.data.sessions[0].status, 'already_synced');
      assert.strictEqual(data.data.attempts[0].status, 'already_synced');

      // Pastikan baris di database tidak terduplikasi dengan parameter 
      const countRes = await testPool.query(
        'SELECT COUNT(*) as count FROM speech_attempts WHERE client_attempt_uuid = $1',
        [testAttemptUuid]
      );
      assert.strictEqual(parseInt(countRes.rows[0].count, 10), 1, 'Record count must remain strictly 1');
    });
  } finally {
    // 7. Graceful Teardown: server, HTTP listeners, dan pool selalu ditutup
    if (server) {
      await new Promise<void>((resolve) => {
        (server as Server).close(() => resolve());
      });
    }
    await testPool.end();
  }
});
