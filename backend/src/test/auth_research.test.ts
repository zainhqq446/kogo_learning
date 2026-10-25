import test from 'node:test';
import assert from 'node:assert/strict';
import { Pool } from 'pg';
import { config } from '../config/env.js';
import { AuthService } from '../services/auth_service.js';
import { ResearchService } from '../services/research_service.js';
import { createApp } from '../app.js';
import { setDbPool } from '../config/database.js';
import { Server } from 'http';

test('Authentication and Research API Integration Suite', async (t) => {
  const testPool = new Pool({
    host: config.database.host,
    port: config.database.port,
    database: 'kogo_research_test',
    user: config.database.user,
    password: config.database.password,
    ssl: config.database.ssl ? { rejectUnauthorized: false } : false,
  });

  const authService = new AuthService(testPool);
  const researchService = new ResearchService(testPool);

  // Bersihkan tabel data uji sebelum mulai
  await testPool.query(`
    TRUNCATE similarity_evaluations, speech_attempts, research_sessions, participants, devices, audit_logs, users CASCADE;
  `);

  let server: Server;
  let baseUrl: string;

  await t.test('Server setup for integration test', async () => {
    setDbPool(testPool);
    const app = createApp();
    return new Promise<void>((resolve) => {
      server = app.listen(0, () => {
        const address = server.address();
        if (address && typeof address === 'object') {
          baseUrl = `http://localhost:${address.port}`;
        }
        resolve();
      });
    });
  });

  // --- UNIT / SERVICE LEVEL TESTS ---

  await t.test('AuthService: Password hashing and comparison', async () => {
    const rawPass = 'SuperSecret123!';
    const hash = await authService.hashPassword(rawPass);
    assert.notStrictEqual(hash, rawPass, 'Hash should not be equal to plain password');
    assert.ok(hash.startsWith('$2b$') || hash.startsWith('$2a$'), 'Should be bcrypt hash');

    const isValid = await authService.comparePassword(rawPass, hash);
    assert.strictEqual(isValid, true, 'Correct password should match');

    const isInvalid = await authService.comparePassword('WrongPassword', hash);
    assert.strictEqual(isInvalid, false, 'Wrong password should fail');
  });

  await t.test('AuthService: Token generation and verification', () => {
    const payload = {
      userId: '123e4567-e89b-12d3-a456-426614174000',
      username: 'researcher_test',
      role: 'researcher' as const,
    };

    const tokens = authService.generateTokens(payload);
    assert.ok(tokens.accessToken, 'Access token should be created');
    assert.ok(tokens.refreshToken, 'Refresh token should be created');

    const decoded = authService.verifyToken(tokens.accessToken);
    assert.strictEqual(decoded.userId, payload.userId);
    assert.strictEqual(decoded.username, payload.username);
    assert.strictEqual(decoded.role, payload.role);
  });

  await t.test('AuthService: Reject tampered or invalid token', () => {
    assert.throws(
      () => authService.verifyToken('invalid.tampered.token'),
      /Invalid or corrupted token/
    );
  });

  await t.test('AuthService: User registration and duplicate prevention', async () => {
    const user = await authService.registerUser({
      username: 'dr_researcher',
      password: 'password123',
      fullName: 'Dr. Researcher',
      role: 'researcher',
    });

    assert.ok(user.id, 'User ID should be generated');
    assert.strictEqual(user.username, 'dr_researcher');
    assert.strictEqual(user.role, 'researcher');

    // Duplicate check
    await assert.rejects(
      async () => {
        await authService.registerUser({
          username: 'dr_researcher',
          password: 'anotherpassword',
          fullName: 'Duplicate Researcher',
        });
      },
      /is already taken/
    );
  });

  await t.test('AuthService: User login success and failure', async () => {
    const loginSuccess = await authService.login('dr_researcher', 'password123');
    assert.ok(loginSuccess.tokens.accessToken, 'Should return access token');
    assert.strictEqual(loginSuccess.user.username, 'dr_researcher');

    await assert.rejects(
      async () => {
        await authService.login('dr_researcher', 'wrongpass');
      },
      /Invalid username or password/
    );

    await assert.rejects(
      async () => {
        await authService.login('non_existent_user', 'somepass');
      },
      /Invalid username or password/
    );
  });

  // --- RESEARCH SERVICE LEVEL TESTS ---

  let participantId: string;
  await t.test('ResearchService: Create and retrieve participant (Zero PII)', async () => {
    const p = await researchService.createParticipant({
      participantCode: 'P001',
      displayAlias: 'Anak A',
      ageYears: 5,
      gender: 'M',
      pin: '1234',
    });

    assert.strictEqual(p.participant_code, 'P001');
    assert.strictEqual(p.display_alias, 'Anak A');
    assert.strictEqual(p.age_years, 5);
    participantId = p.id;

    const fetched = await researchService.getParticipantByCode('P001');
    assert.strictEqual(fetched.id, p.id);
  });

  let deviceId: string;
  await t.test('ResearchService: Register device', async () => {
    const dev = await researchService.registerDevice({
      deviceIdentifier: 'tablet-samsung-tab-a',
      deviceLabel: 'Tablet Kelas A',
      platform: 'android',
      appVersion: '1.0.0',
    });

    assert.ok(dev.id);
    assert.strictEqual(dev.device_identifier, 'tablet-samsung-tab-a');
    deviceId = dev.id;
  });

  const sessionUuid = 'a1b2c3d4-e5f6-4a5b-8c9d-0e1f2a3b4c5d';
  await t.test('ResearchService: Create research session idempotently', async () => {
    const s1 = await researchService.createSession({
      clientSessionUuid: sessionUuid,
      participantCode: 'P001',
      deviceIdentifier: 'tablet-samsung-tab-a',
      sessionSequenceNumber: 1,
      startedAt: new Date().toISOString(),
      notes: 'Initial evaluation session',
    });

    assert.strictEqual(s1.client_session_uuid, sessionUuid);

    // Re-upserting same session should succeed without error
    const s2 = await researchService.createSession({
      clientSessionUuid: sessionUuid,
      participantCode: 'P001',
      deviceIdentifier: 'tablet-samsung-tab-a',
      sessionSequenceNumber: 1,
      startedAt: new Date().toISOString(),
      endedAt: new Date().toISOString(),
      notes: 'Updated notes',
    });

    assert.strictEqual(s2.id, s1.id);
  });

  const attemptUuid = 'f1e2d3c4-b5a6-4978-8765-43210fedcba9';
  await t.test('ResearchService: Record attempt and similarity evaluation', async () => {
    const result = await researchService.recordAttemptWithEvaluation({
      clientAttemptUuid: attemptUuid,
      clientSessionUuid: sessionUuid,
      participantCode: 'P001',
      deviceIdentifier: 'tablet-samsung-tab-a',
      questionId: 1,
      attemptNumber: 1,
      targetText: 'buku',
      recognizedText: 'buku',
      asrConfidence: 0.95,
      durationMs: 1200,
      attemptedAt: new Date().toISOString(),
      evaluation: {
        normalizedTarget: 'buku',
        normalizedRecognized: 'buku',
        editDistance: 0,
        similarityScore: 1.0,
        similarityPercent: 100.0,
        isCorrect: true,
        evaluationStatus: 'EXACT_MATCH',
        thresholdUsed: 1.0,
      },
    });

    assert.strictEqual(result.attempt.client_attempt_uuid, attemptUuid);
    assert.strictEqual(result.evaluation.evaluation_status, 'EXACT_MATCH');
    assert.strictEqual(result.evaluation.is_correct, true);
    assert.strictEqual(Number(result.evaluation.similarity_score), 1.0);
  });

  await t.test('ResearchService: Aggregate summary calculation', async () => {
    const summary = await researchService.getResearchSummary();
    assert.strictEqual(parseInt(summary.total_participants, 10), 1);
    assert.strictEqual(parseInt(summary.total_sessions, 10), 1);
    assert.strictEqual(parseInt(summary.total_attempts, 10), 1);
    assert.strictEqual(parseInt(summary.exact_matches, 10), 1);
    assert.strictEqual(parseFloat(summary.avg_similarity_percent), 100.0);
  });

  // --- HTTP ENDPOINT & PROTECTED ROUTE TESTS ---

  await t.test('HTTP GET /api/research/participants without token returns 401', async () => {
    const res = await fetch(`${baseUrl}/api/research/participants`);
    assert.strictEqual(res.status, 401);
    const data = await res.json() as any;
    assert.strictEqual(data.status, 'error');
    assert.ok(data.message.includes('Authorization header'));
  });

  await t.test('HTTP GET /api/research/participants with invalid token returns 401', async () => {
    const res = await fetch(`${baseUrl}/api/research/participants`, {
      headers: { Authorization: 'Bearer totally_invalid_token' },
    });
    assert.strictEqual(res.status, 401);
  });

  await t.test('HTTP RBAC: Teacher role is forbidden from viewing devices list', async () => {
    const teacherTokens = authService.generateTokens({
      userId: '999e4567-e89b-12d3-a456-426614174999',
      username: 'teacher_user',
      role: 'teacher',
    });

    const res = await fetch(`${baseUrl}/api/research/devices`, {
      headers: { Authorization: `Bearer ${teacherTokens.accessToken}` },
    });
    assert.strictEqual(res.status, 403, 'Teacher role should receive 403 Forbidden for device list');
    const data = await res.json() as any;
    assert.ok(data.message.includes('Access denied'));
  });

  await t.test('HTTP RBAC: Researcher can access profile /api/auth/me', async () => {
    const userRow = await testPool.query('SELECT id, username FROM users WHERE username = $1', ['dr_researcher']);
    const actualUserId = userRow.rows[0].id;

    const researcherTokens = authService.generateTokens({
      userId: actualUserId,
      username: 'dr_researcher',
      role: 'researcher',
    });

    const res = await fetch(`${baseUrl}/api/auth/me`, {
      headers: { Authorization: `Bearer ${researcherTokens.accessToken}` },
    });
    assert.strictEqual(res.status, 200);
    const data = (await res.json()) as any;
    assert.strictEqual(data.status, 'success');
    assert.strictEqual(data.data.username, 'dr_researcher');
  });

  await t.test('HTTP POST /api/auth/login validation schema error on empty body', async () => {
    const res = await fetch(`${baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({}),
    });
    assert.strictEqual(res.status, 400);
    const data = await res.json() as any;
    assert.strictEqual(data.statusCode, 400);
    assert.ok(data.message.includes('Validation failed'));
  });

  
  // --- BATCH SYNC ENDPOINT & IDEMPOTENCY TESTS ---

  const testSessionUuid = '77777777-8888-4444-9999-aaaaaaaaaaaa';
  const testAttemptUuid = '99999999-8888-4444-7777-bbbbbbbbbbbb';

  await t.test('POST /api/research/sync/batch - Process new session and attempt', async () => {
    const researcherTokens = authService.generateTokens({
      userId: '111e4567-e89b-12d3-a456-426614174111',
      username: 'dr_researcher',
      role: 'researcher',
    });

    const payload = {
      sessions: [
        {
          clientSessionUuid: testSessionUuid,
          participantCode: 'P001',
          deviceIdentifier: 'tablet-samsung-tab-a',
          sessionSequenceNumber: 2,
          startedAt: new Date().toISOString(),
          endedAt: new Date().toISOString(),
          notes: 'Batch sync test session',
        },
      ],
      attempts: [
        {
          clientAttemptUuid: testAttemptUuid,
          clientSessionUuid: testSessionUuid,
          participantCode: 'P001',
          deviceIdentifier: 'tablet-samsung-tab-a',
          questionId: 1,
          attemptNumber: 1,
          targetText: 'buku',
          recognizedText: 'buku',
          asrProvider: 'whisper_onnx',
          locale: 'id_ID',
          asrConfidence: 0.98,
          durationMs: 950,
          attemptedAt: new Date().toISOString(),
          evaluation: {
            normalizedTarget: 'buku',
            normalizedRecognized: 'buku',
            editDistance: 0,
            similarityScore: 1.0,
            similarityPercent: 100.0,
            isCorrect: true,
            evaluationStatus: 'EXACT_MATCH',
            thresholdUsed: 1.0,
            evaluationMethod: 'levenshtein_normalized_v1',
          },
        },
      ],
    };

    const res = await fetch(`${baseUrl}/api/research/sync/batch`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${researcherTokens.accessToken}`,
      },
      body: JSON.stringify(payload),
    });

    assert.strictEqual(res.status, 200);
    const data = (await res.json()) as any;
    assert.strictEqual(data.status, 'success');
    assert.strictEqual(data.data.summary.totalSessions, 1);
    assert.strictEqual(data.data.summary.syncedSessions, 1);
    assert.strictEqual(data.data.summary.totalAttempts, 1);
    assert.strictEqual(data.data.summary.syncedAttempts, 1);
    assert.strictEqual(data.data.summary.failedItems, 0);
    assert.strictEqual(data.data.sessions[0].status, 'created');
    assert.strictEqual(data.data.attempts[0].status, 'created');
  });

  await t.test('POST /api/research/sync/batch - Idempotency on repeated submission without duplicate errors', async () => {
    const researcherTokens = authService.generateTokens({
      userId: '111e4567-e89b-12d3-a456-426614174111',
      username: 'dr_researcher',
      role: 'researcher',
    });

    const payload = {
      sessions: [
        {
          clientSessionUuid: testSessionUuid,
          participantCode: 'P001',
          deviceIdentifier: 'tablet-samsung-tab-a',
          sessionSequenceNumber: 2,
          startedAt: new Date().toISOString(),
          notes: 'Batch sync repeated',
        },
      ],
      attempts: [
        {
          clientAttemptUuid: testAttemptUuid,
          clientSessionUuid: testSessionUuid,
          participantCode: 'P001',
          deviceIdentifier: 'tablet-samsung-tab-a',
          questionId: 1,
          attemptNumber: 1,
          targetText: 'buku',
          recognizedText: 'buku',
          attemptedAt: new Date().toISOString(),
          evaluation: {
            normalizedTarget: 'buku',
            normalizedRecognized: 'buku',
            editDistance: 0,
            similarityScore: 1.0,
            similarityPercent: 100.0,
            isCorrect: true,
            evaluationStatus: 'EXACT_MATCH',
            thresholdUsed: 1.0,
          },
        },
      ],
    };

    const res = await fetch(`${baseUrl}/api/research/sync/batch`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${researcherTokens.accessToken}`,
      },
      body: JSON.stringify(payload),
    });

    assert.strictEqual(res.status, 200);
    const data = (await res.json()) as any;
    assert.strictEqual(data.data.summary.failedItems, 0);
    assert.strictEqual(data.data.sessions[0].status, 'already_synced');
    assert.strictEqual(data.data.attempts[0].status, 'already_synced');
  });

  await t.test('POST /api/research/sync/batch - Handle partial failure gracefully (invalid participant)', async () => {
    const researcherTokens = authService.generateTokens({
      userId: '111e4567-e89b-12d3-a456-426614174111',
      username: 'dr_researcher',
      role: 'researcher',
    });

    const invalidUuid = '00000000-0000-4000-8000-000000000000';
    const payload = {
      sessions: [
        {
          clientSessionUuid: invalidUuid,
          participantCode: 'NON_EXISTENT_P999',
          deviceIdentifier: 'tablet-samsung-tab-a',
          sessionSequenceNumber: 1,
          startedAt: new Date().toISOString(),
        },
      ],
      attempts: [],
    };

    const res = await fetch(`${baseUrl}/api/research/sync/batch`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${researcherTokens.accessToken}`,
      },
      body: JSON.stringify(payload),
    });

    assert.strictEqual(res.status, 200);
    const data = (await res.json()) as any;
    assert.strictEqual(data.data.summary.failedItems, 1);
    assert.strictEqual(data.data.sessions[0].status, 'failed');
    assert.ok(data.data.sessions[0].error.includes('not found'));
  });

  await t.test('Teardown test server and pool', async () => {
    await testPool.end();
    return new Promise<void>((resolve, reject) => {
      server.close((err) => {
        if (err) reject(err);
        else resolve();
      });
    });
  });
});