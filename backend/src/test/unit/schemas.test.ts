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
import { resolveRange } from '../../services/metrics_service.js';

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

/** Nilai yang dipangkas harus sama dengan waktu server saat parse. */
function nearNow(value: string | null | undefined, before: number): void {
  assert.ok(typeof value === 'string', `expected a timestamp, got ${value}`);
  const ms = Date.parse(value);
  assert.ok(ms >= before && ms <= Date.now(), `${value} should be clamped to the server's current time`);
}

test('schemas: device timestamps far in the future are clamped to server time, not rejected (default skew 24h)', () => {
  const inAnHour = new Date(Date.now() + 60 * 60 * 1000).toISOString();
  const inTwoDays = new Date(Date.now() + 48 * 60 * 60 * 1000).toISOString();

  // Skew kecil ditoleransi apa adanya.
  const small = syncLearnerSchema.parse({ ...learner, updatedAt: inAnHour });
  assert.equal(small.updatedAt, inAnHour, 'small clock skew is kept unchanged');

  const before = Date.now();
  const far = syncLearnerSchema.safeParse({ ...learner, updatedAt: '2099-01-01T00:00:00.000Z', createdAt: inTwoDays });
  assert.equal(far.success, true, 'far-future timestamps must not drop the learner');
  if (far.success) {
    nearNow(far.data.updatedAt, before);
    nearNow(far.data.createdAt, before);
  }
  const s = syncGameSessionSchema.safeParse({ ...session, startedAt: inTwoDays, endedAt: '2099-12-31T23:59:59+15:00' });
  assert.equal(s.success, true);
  if (s.success) {
    nearNow(s.data.startedAt, before);
    nearNow(s.data.endedAt, before);
  }
  const a = syncAnswerAttemptSchema.safeParse({ ...attempt, createdAt: inTwoDays });
  assert.equal(a.success, true);
  if (a.success) nearNow(a.data.createdAt, before);
  // endedAt null tetap null (tidak dipangkas menjadi waktu sekarang).
  assert.equal(syncGameSessionSchema.parse({ ...session, endedAt: null }).endedAt, null);

  // Jam perangkat yang tertinggal (masa lalu) tetap diterima apa adanya.
  assert.equal(syncLearnerSchema.parse({ ...learner, createdAt: '2000-01-01T00:00:00.000Z' }).createdAt, '2000-01-01T00:00:00.000Z');
  assert.equal(syncLearnerSchema.parse(learner).createdAt, NOW);
});

test('schemas: unstorable offsets are INVALID per item; reset device clocks are clamped', () => {
  // Offset di dalam batas PostgreSQL (+/-15:59) diterima.
  for (const ts of ['2026-10-25T08:00:00Z', '2026-10-25T08:00:00+07:00', '2026-10-25T08:00:00+15:59', '2026-10-25T08:00:00-15:00', '2026-10-25T08:00:00.123+05:30']) {
    assert.equal(syncLearnerSchema.safeParse({ ...learner, createdAt: ts }).success, true, ts);
  }
  // Offset yang ditolak PostgreSQL dengan SQLSTATE 22009 tidak boleh lolos ke database.
  for (const ts of ['2026-10-25T08:00:00+16:00', '2026-10-25T08:00:00-23:00', '2026-10-25T08:00:00+23:59']) {
    const res = syncLearnerSchema.safeParse({ ...learner, createdAt: ts });
    assert.equal(res.success, false, ts);
    assert.ok(!res.success && /offset/.test(res.error.issues[0].message), ts);
  }
  assert.equal(syncGameSessionSchema.safeParse({ ...session, startedAt: '2026-10-25T08:00:00+18:00' }).success, false);
  assert.equal(syncGameSessionSchema.safeParse({ ...session, endedAt: '2026-10-25T08:00:00-16:30' }).success, false);
  assert.equal(syncAnswerAttemptSchema.safeParse({ ...attempt, createdAt: '2026-10-25T08:00:00+20:00' }).success, false);

  // Jam tablet yang ter-reset (tahun 0000, 1970, sebelum 2000) dipangkas ke waktu server, bukan ditolak.
  for (const ts of ['0000-01-01T00:00:00Z', '1970-01-01T00:00:00Z', '1999-12-31T23:59:59.999Z']) {
    const before = Date.now();
    const res = syncLearnerSchema.safeParse({ ...learner, updatedAt: ts });
    assert.equal(res.success, true, ts);
    if (res.success) nearNow(res.data.updatedAt, before);
  }
  const reset = syncGameSessionSchema.parse({ ...session, startedAt: '1970-01-01T00:00:00Z', endedAt: '1970-01-01T00:05:00Z' });
  assert.ok(Date.parse(reset.startedAt) > Date.UTC(2020, 0, 1));
  // endedAt tidak pernah mendahului startedAt setelah pemangkasan terpisah.
  assert.ok(Date.parse(reset.endedAt as string) >= Date.parse(reset.startedAt));
  const inThreeDays = new Date(Date.now() + 3 * 24 * 3600 * 1000).toISOString();
  const skewed = syncGameSessionSchema.parse({ ...session, startedAt: '2026-10-25T08:00:00.000Z', endedAt: inThreeDays });
  assert.ok(Date.parse(skewed.endedAt as string) >= Date.parse(skewed.startedAt));
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

test('schemas: research range uses the same bounds as resolveRange (date-only `to` = whole day)', () => {
  const ok = (from: string, to: string) => {
    const res = researchQuerySchema.safeParse({ from, to });
    assert.equal(res.success, true, `${from} .. ${to} must be accepted`);
    // Rentang yang diterima validasi juga tidak kosong menurut resolveRange().
    const range = resolveRange(researchQuerySchema.parse({ from, to }));
    assert.ok(range.from && range.toExclusive && range.from.getTime() < range.toExclusive.getTime(), `${from} .. ${to}`);
  };
  const bad = (from: string, to: string) => {
    const res = researchQuerySchema.safeParse({ from, to });
    assert.equal(res.success, false, `${from} .. ${to} must be rejected`);
    assert.ok(!res.success && res.error.issues[0].path.join('.') === 'from');
  };

  // Datetime `from` + tanggal saja `to` pada hari yang sama (dulu ditolak keliru).
  ok('2026-10-25T10:00:00Z', '2026-10-25');
  ok('2026-10-25T23:59:59.999Z', '2026-10-25');
  ok('2026-10-25T10:00:00+07:00', '2026-10-25');
  ok('2026-10-25', '2026-10-25');
  ok('2026-10-25', '2026-10-25T00:00:00Z');
  ok('2026-10-25T08:00:00Z', '2026-10-25T08:00:00Z');
  ok('2026-10-25T08:00:00+07:00', '2026-10-25T01:00:00Z');

  // Tanggal saja = hari UTC: 2026-10-26T05:00+07:00 = 2026-10-25T22:00Z, masih hari 25.
  ok('2026-10-26T05:00:00+07:00', '2026-10-25');

  bad('2026-10-26T00:00:00Z', '2026-10-25');
  bad('2026-10-26T08:00:00+07:00', '2026-10-25');
  bad('2026-10-25T08:00:00.001Z', '2026-10-25T08:00:00Z');
  bad('2026-10-26', '2026-10-25T23:59:59.999Z');
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
