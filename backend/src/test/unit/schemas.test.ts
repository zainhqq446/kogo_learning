import '../helpers/test_env.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import {
  batchParticipantSchema,
  createParticipantSchema,
  deviceApproveSchema,
  deviceRegisterSchema,
  loginSchema,
  registerSchema,
  listAttemptsQuerySchema,
  paginationQuerySchema,
  researchQuerySchema,
  syncAnswerAttemptSchema,
  syncBatchSchema,
  syncGameSessionSchema,
  syncLearnerSchema,
  syncRequestSchema,
  ttsSynthesizeSchema,
} from '../../types/schemas.js';
import { GAME_TYPES, MATERI_CODES, REWARD_TIERS, SESSION_STATUSES } from '../../types/curriculum.js';
import { vocabulary } from '../../services/reference_data_service.js';

const UUID_A = '3f1c9a2e-5b7d-4c8e-9f0a-1b2c3d4e5f60';
const UUID_B = '7a8b9c0d-1e2f-4a3b-8c4d-5e6f7a8b9c0d';
const NOW = '2026-10-25T08:00:00.123456Z';

const learner = { clientUuid: UUID_A, name: 'Ani', school: 'TK Pelita', age: 5, createdAt: NOW, updatedAt: NOW };
const session = {
  clientUuid: UUID_B,
  learnerUuid: UUID_A,
  materi: 'two-syllable',
  nodeIndex: 3,
  gameType: 'speaking',
  status: 'completed',
  totalItems: 4,
  firstTryCorrect: 3,
  stars: 2,
  startedAt: NOW,
  endedAt: NOW,
};
const attempt = {
  clientUuid: '0b1c2d3e-4f50-4617-8899-aabbccddeeff',
  sessionUuid: UUID_B,
  learnerUuid: UUID_A,
  gameType: 'speaking',
  targetText: 'bola',
  answerText: 'bola',
  isCorrect: true,
  attemptNumber: 1,
  similarity: 1,
  responseMs: 1200,
  sttError: null,
  createdAt: NOW,
};

test('schemas: curriculum constants match vocabulary.json (single source of truth)', () => {
  assert.deepEqual([...MATERI_CODES], vocabulary.materi.map((m) => m.code));
  assert.deepEqual([...GAME_TYPES], vocabulary.gameTypes.map((g) => g.code));
  assert.deepEqual(
    REWARD_TIERS.map((t) => [t.code, t.minStars]),
    vocabulary.rewardTiers.map((t) => [t.code, t.minStars])
  );
  assert.deepEqual([...SESSION_STATUSES], ['started', 'completed', 'abandoned']);
});

test('schemas: learner age must be 5 or 6 and names are bounded', () => {
  assert.equal(syncLearnerSchema.safeParse(learner).success, true);
  assert.equal(syncLearnerSchema.safeParse({ ...learner, age: 6 }).success, true);
  for (const age of [4, 7, 5.5, '5']) {
    assert.equal(syncLearnerSchema.safeParse({ ...learner, age }).success, false, `age ${age} must be rejected`);
  }
  assert.equal(syncLearnerSchema.safeParse({ ...learner, name: 'A' }).success, false);
  assert.equal(syncLearnerSchema.safeParse({ ...learner, name: 'x'.repeat(41) }).success, false);
  assert.equal(syncLearnerSchema.safeParse({ ...learner, school: 'x'.repeat(61) }).success, false);
  assert.equal(syncLearnerSchema.safeParse({ ...learner, clientUuid: 'not-a-uuid' }).success, false);
  // Datetime tanpa zona waktu ditolak (ambigu).
  assert.equal(syncLearnerSchema.safeParse({ ...learner, createdAt: '2026-10-25T08:00:00' }).success, false);
  assert.equal(syncLearnerSchema.safeParse({ ...learner, createdAt: '2026-10-25T15:00:00+07:00' }).success, true);
});

test('schemas: session enums, limits and firstTryCorrect <= totalItems', () => {
  assert.equal(syncGameSessionSchema.safeParse(session).success, true);
  assert.equal(syncGameSessionSchema.safeParse({ ...session, endedAt: null }).success, true);
  assert.equal(syncGameSessionSchema.safeParse({ ...session, materi: 'science' }).success, false);
  assert.equal(syncGameSessionSchema.safeParse({ ...session, gameType: 'quiz' }).success, false);
  assert.equal(syncGameSessionSchema.safeParse({ ...session, status: 'paused' }).success, false);
  assert.equal(syncGameSessionSchema.safeParse({ ...session, stars: 4 }).success, false);
  assert.equal(syncGameSessionSchema.safeParse({ ...session, stars: -1 }).success, false);
  assert.equal(syncGameSessionSchema.safeParse({ ...session, totalItems: 21, firstTryCorrect: 0 }).success, false);
  assert.equal(syncGameSessionSchema.safeParse({ ...session, nodeIndex: -1 }).success, false);
  const tooMany = syncGameSessionSchema.safeParse({ ...session, totalItems: 2, firstTryCorrect: 3 });
  assert.equal(tooMany.success, false);
  assert.ok(!tooMany.success && tooMany.error.issues.some((i) => i.path.join('.') === 'firstTryCorrect'));
});

test('schemas: attempt limits and nullable fields', () => {
  assert.equal(syncAnswerAttemptSchema.safeParse(attempt).success, true);
  assert.equal(
    syncAnswerAttemptSchema.safeParse({ ...attempt, similarity: null, responseMs: null, sttError: 'no_match' }).success,
    true
  );
  assert.equal(syncAnswerAttemptSchema.safeParse({ ...attempt, similarity: 1.2 }).success, false);
  assert.equal(syncAnswerAttemptSchema.safeParse({ ...attempt, responseMs: -1 }).success, false);
  assert.equal(syncAnswerAttemptSchema.safeParse({ ...attempt, attemptNumber: 0 }).success, false);
  assert.equal(syncAnswerAttemptSchema.safeParse({ ...attempt, targetText: 'x'.repeat(61) }).success, false);
  assert.equal(syncAnswerAttemptSchema.safeParse({ ...attempt, answerText: 'x'.repeat(201) }).success, false);
  assert.equal(syncAnswerAttemptSchema.safeParse({ ...attempt, sttError: 'x'.repeat(41) }).success, false);
});

test('schemas: sync request caps array sizes (50 learners / 200 sessions / 1000 attempts)', () => {
  assert.equal(syncRequestSchema.safeParse({}).success, true);
  assert.equal(syncRequestSchema.safeParse({ learners: Array(50).fill(learner) }).success, true);
  assert.equal(syncRequestSchema.safeParse({ learners: Array(51).fill(learner) }).success, false);
  assert.equal(syncRequestSchema.safeParse({ sessions: Array(201).fill(session) }).success, false);
  assert.equal(syncRequestSchema.safeParse({ attempts: Array(1000).fill(attempt) }).success, true);
  assert.equal(syncRequestSchema.safeParse({ attempts: Array(1001).fill(attempt) }).success, false);
  assert.equal(syncRequestSchema.safeParse({ learners: 'nope' }).success, false);
});

test('schemas: device registration accepts android only with bounded strings', () => {
  const ok = { deviceUuid: UUID_A, platform: 'android', appVersion: '1.0.0+1', model: 'Pixel 7' };
  assert.equal(deviceRegisterSchema.safeParse(ok).success, true);
  assert.equal(deviceRegisterSchema.safeParse({ ...ok, model: undefined }).success, true);
  assert.equal(deviceRegisterSchema.safeParse({ ...ok, platform: 'ios' }).success, false);
  assert.equal(deviceRegisterSchema.safeParse({ ...ok, appVersion: 'x'.repeat(33) }).success, false);
  assert.equal(deviceRegisterSchema.safeParse({ ...ok, model: 'x'.repeat(65) }).success, false);
  assert.equal(deviceRegisterSchema.safeParse({ ...ok, deviceUuid: '123' }).success, false);
});

test('schemas: TTS text <= 300 chars and mood enum', () => {
  assert.equal(ttsSynthesizeSchema.safeParse({ text: 'Halo, ayo belajar!' }).success, true);
  assert.equal(ttsSynthesizeSchema.safeParse({ text: 'a'.repeat(300) }).success, true);
  assert.equal(ttsSynthesizeSchema.safeParse({ text: 'a'.repeat(301) }).success, false);
  assert.equal(ttsSynthesizeSchema.safeParse({ text: '   ' }).success, false);
  assert.equal(ttsSynthesizeSchema.safeParse({ text: 'Hebat!', mood: 'celebratory' }).success, true);
  assert.equal(ttsSynthesizeSchema.safeParse({ text: 'Hebat!', mood: 'angry' }).success, false);
  assert.equal(ttsSynthesizeSchema.safeParse({ text: 'x', voiceId: '../../etc' }).success, false);
  assert.equal(ttsSynthesizeSchema.safeParse({ text: 'x', settings: { speed: 2 } }).success, false);
});

test('schemas: NUL characters are rejected before they can reach PostgreSQL (22021)', () => {
  const nul = 'Bad\u0000Kid';
  assert.equal(syncLearnerSchema.safeParse({ ...learner, name: nul }).success, false);
  assert.equal(syncLearnerSchema.safeParse({ ...learner, school: nul }).success, false);
  assert.equal(syncAnswerAttemptSchema.safeParse({ ...attempt, answerText: nul }).success, false);
  assert.equal(syncAnswerAttemptSchema.safeParse({ ...attempt, targetText: nul }).success, false);
  assert.equal(syncAnswerAttemptSchema.safeParse({ ...attempt, sttError: nul }).success, false);
  assert.equal(loginSchema.safeParse({ username: 'a\u0000b', password: 'secret' }).success, false);
  assert.equal(loginSchema.safeParse({ username: 'ab', password: 'se\u0000cret' }).success, false);
  assert.equal(
    deviceRegisterSchema.safeParse({ deviceUuid: UUID_A, platform: 'android', appVersion: 'a\u0000b' }).success,
    false
  );
  assert.equal(
    registerSchema.safeParse({ username: 'ani', password: 'secret1', fullName: 'Ani\u0000' }).success,
    false
  );
  assert.equal(createParticipantSchema.safeParse({ participantCode: 'P1', displayAlias: 'x\u0000', pin: '1234' }).success, false);
  assert.equal(deviceApproveSchema.safeParse({ label: 'Tab\u0000let' }).success, false);
  // Karakter Unicode lain tetap boleh (nama anak Indonesia, emoji, dsb.).
  assert.equal(syncLearnerSchema.safeParse({ ...learner, name: 'Añi 😊' }).success, true);
});

test('schemas: device timestamps far in the future are rejected (default skew 24h)', () => {
  const inAnHour = new Date(Date.now() + 60 * 60 * 1000).toISOString();
  const inTwoDays = new Date(Date.now() + 48 * 60 * 60 * 1000).toISOString();
  assert.equal(syncLearnerSchema.safeParse({ ...learner, updatedAt: inAnHour }).success, true, 'small clock skew tolerated');
  assert.equal(syncLearnerSchema.safeParse({ ...learner, updatedAt: '2099-01-01T00:00:00.000Z' }).success, false);
  assert.equal(syncLearnerSchema.safeParse({ ...learner, createdAt: inTwoDays }).success, false);
  assert.equal(syncGameSessionSchema.safeParse({ ...session, startedAt: inTwoDays }).success, false);
  assert.equal(syncGameSessionSchema.safeParse({ ...session, endedAt: inTwoDays }).success, false);
  assert.equal(syncAnswerAttemptSchema.safeParse({ ...attempt, createdAt: inTwoDays }).success, false);
  const res = syncLearnerSchema.safeParse({ ...learner, updatedAt: '2099-01-01T00:00:00.000Z' });
  assert.ok(!res.success && res.error.issues[0].message.includes('future'));
  // Jam perangkat yang tertinggal (masa lalu) tetap diterima.
  assert.equal(syncLearnerSchema.safeParse({ ...learner, createdAt: '2000-01-01T00:00:00.000Z' }).success, true);
});

test('schemas: device registration accepts an optional deviceSecret of the issued shape', () => {
  const base = { deviceUuid: UUID_A, platform: 'android', appVersion: '2.0.0' };
  assert.equal(deviceRegisterSchema.safeParse({ ...base, deviceSecret: 'A'.repeat(43) }).success, true);
  assert.equal(deviceRegisterSchema.safeParse({ ...base, deviceSecret: 'short' }).success, false);
  assert.equal(deviceRegisterSchema.safeParse({ ...base, deviceSecret: 'x'.repeat(30) + '!' }).success, false);
});

test('schemas: research query validates uuid and date range', () => {
  assert.equal(researchQuerySchema.safeParse({}).success, true);
  // Nilai kosong (form HTML / dasbor) = tidak difilter.
  const blank = researchQuerySchema.parse({ learnerUuid: '', from: '', to: '', devices: '' });
  assert.deepEqual(blank, { learnerUuid: undefined, from: undefined, to: undefined, devices: 'approved' });
  assert.equal(researchQuerySchema.parse({}).devices, 'approved');
  assert.equal(researchQuerySchema.parse({ devices: 'all' }).devices, 'all');
  assert.equal(researchQuerySchema.safeParse({ devices: 'revoked' }).success, false);
  assert.equal(researchQuerySchema.safeParse({ from: '2026-10-01', to: '2026-10-31' }).success, true);
  assert.equal(researchQuerySchema.safeParse({ from: '2026-10-01T00:00:00+07:00' }).success, true);
  assert.equal(researchQuerySchema.safeParse({ from: '2026-11-01', to: '2026-10-01' }).success, false);
  assert.equal(researchQuerySchema.safeParse({ from: 'yesterday' }).success, false);
  assert.equal(researchQuerySchema.safeParse({ learnerUuid: 'abc' }).success, false);
});

test('schemas: legacy batch arrays and pagination are bounded', () => {
  const participant = { participantCode: 'P001', displayAlias: 'Anak', pin: '1234' };
  assert.equal(batchParticipantSchema.safeParse({ participants: Array(200).fill(participant) }).success, true);
  assert.equal(batchParticipantSchema.safeParse({ participants: Array(201).fill(participant) }).success, false);
  assert.equal(syncBatchSchema.safeParse({ sessions: [], attempts: [] }).success, true);
  assert.equal(syncBatchSchema.safeParse({ sessions: Array(201).fill({}) }).success, false);

  assert.deepEqual(paginationQuerySchema.parse({}), { limit: 50, offset: 0 });
  assert.deepEqual(paginationQuerySchema.parse({ limit: '10', offset: '20' }), { limit: 10, offset: 20 });
  assert.equal(paginationQuerySchema.safeParse({ limit: 'abc' }).success, false);
  assert.equal(paginationQuerySchema.safeParse({ limit: '1000' }).success, false);
  assert.equal(paginationQuerySchema.safeParse({ offset: '-1' }).success, false);
  assert.equal(listAttemptsQuerySchema.safeParse({ sessionId: 'x' }).success, false);
});
