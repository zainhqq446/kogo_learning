import { z } from 'zod';
import { config } from '../config/env.js';
import { resolveDateBounds } from '../utils/date_range.js';
import {
  GAME_TYPES,
  LEARNER_MAX_AGE,
  LEARNER_MIN_AGE,
  MATERI_CODES,
  MAX_ITEMS_PER_SESSION,
  MAX_STARS_PER_NODE,
  SESSION_STATUSES,
} from './curriculum.js';

/**
 * PostgreSQL menolak karakter NUL (U+0000) pada kolom teks (SQLSTATE 22021).
 * Semua string dari klien divalidasi bebas NUL agar item rusak ditolak per
 * item (400 / INVALID) dan tidak pernah menggagalkan seluruh transaksi.
 */
const NO_NUL = /^[^\u0000]*$/;
const text = () => z.string().regex(NO_NUL, 'must not contain NUL (U+0000) characters');

/**
 * UUID 8-4-4-4-12 heksadesimal (sesuai tipe `uuid` PostgreSQL). Sengaja tidak
 * memaksa versi/varian RFC agar UUID dari klien lama tetap diterima.
 */
const uuidField = (label: string) => z.guid({ error: `${label} must be a valid UUID` });
const isoDateTime = (label: string) =>
  z.iso.datetime({ offset: true, error: `${label} must be an ISO 8601 datetime with timezone (e.g. 2026-10-25T08:00:00.000Z)` });

/**
 * Offset UTC yang dapat disimpan PostgreSQL: `Z` atau +/-HH:MM dengan HH <= 15
 * (offset lebih besar ditolak PostgreSQL dengan SQLSTATE 22009).
 */
const PG_SAFE_OFFSET = /(?:Z|[+-](?:0\d|1[0-5]):[0-5]\d)$/;
/**
 * Batas bawah timestamp perangkat yang masuk akal. Tablet yang jamnya ter-reset
 * (mis. ke 1970 setelah baterai habis) mengirim nilai di bawahnya; tahun 0000
 * bahkan ditolak PostgreSQL (22008).
 */
const MIN_CLIENT_TIMESTAMP_MS = Date.UTC(2000, 0, 1);

/**
 * Timestamp dari jam perangkat (API v2).
 *
 * - Offset di luar +/-15:59 (tidak dapat disimpan PostgreSQL, 22009) ditolak
 *   per item (INVALID), tidak pernah menggagalkan seluruh batch. Aplikasi
 *   selalu mengirim UTC (`Z`), jadi ini hanya mengenai klien lain.
 * - Nilai yang jelas berasal dari jam tablet yang salah, yaitu sebelum
 *   2000-01-01 atau lebih dari SYNC_MAX_CLOCK_SKEW_HOURS (default 24 jam) di
 *   masa depan, DIPANGKAS ke waktu server saat ini, bukan ditolak: jam yang
 *   salah tidak boleh membuat aplikasi membuang data anak (dan seluruh sesinya)
 *   secara permanen, dan filter tanggal metrik tetap masuk akal.
 */
const clientTimestamp = (label: string) =>
  isoDateTime(label)
    .refine((value) => PG_SAFE_OFFSET.test(value), {
      message: `${label} must use a UTC offset between -15:59 and +15:59 (e.g. Z or +07:00)`,
    })
    .transform((value) => {
      const ms = Date.parse(value);
      return ms < MIN_CLIENT_TIMESTAMP_MS || ms > Date.now() + config.devices.maxClockSkewMs ? new Date().toISOString() : value;
    });

// ============================================================================
// AUTH
// ============================================================================

const usernameField = text()
  .min(3, 'Username minimal 3 karakter')
  .max(50, 'Username maksimal 50 karakter')
  .regex(/^[a-zA-Z0-9_]+$/, 'Username hanya boleh berupa huruf, angka, dan garis bawah (_)');

const passwordField = text()
  .min(6, 'Password minimal 6 karakter')
  .max(72, 'Password maksimal 72 karakter');

export const registerSchema = z.object({
  username: usernameField,
  password: passwordField,
  fullName: text()
    .trim()
    .min(2, 'Nama lengkap / nama anak minimal 2 karakter')
    .max(100, 'Nama lengkap maksimal 100 karakter'),
  role: z.enum(['admin', 'researcher', 'teacher', 'child', 'student']).optional(),
  ageYears: z
    .number()
    .int('Umur harus bilangan bulat')
    .min(2, 'Umur minimal 2 tahun')
    .max(18, 'Umur maksimal 18 tahun')
    .optional(),
  schoolName: text()
    .trim()
    .min(2, 'Nama sekolah minimal 2 karakter')
    .max(150, 'Nama sekolah maksimal 150 karakter')
    .optional(),
});

export const childRegisterSchema = z.object({
  fullName: text().trim().min(2, 'Nama anak minimal 2 karakter').max(100, 'Nama anak maksimal 100 karakter'),
  username: usernameField,
  password: passwordField,
  ageYears: z
    .number({ error: 'Umur harus berupa angka' })
    .int('Umur harus berupa bilangan bulat')
    .min(2, 'Umur minimal 2 tahun')
    .max(18, 'Umur maksimal 18 tahun'),
  schoolName: text().trim().min(2, 'Nama sekolah minimal 2 karakter').max(150, 'Nama sekolah maksimal 150 karakter'),
});

export const loginSchema = z.object({
  username: text().min(1, 'Username is required').max(50),
  password: text().min(1, 'Password is required').max(200),
});

// ============================================================================
// LEGACY RESEARCH API (/api/research/*)
// ============================================================================

export const createParticipantSchema = z.object({
  participantCode: text()
    .min(2, 'Participant code must be at least 2 characters long')
    .max(50, 'Participant code cannot exceed 50 characters')
    .regex(/^[A-Z0-9_\-]+$/i, 'Participant code should be alphanumeric'),
  displayAlias: text().min(1, 'Display alias is required').max(50, 'Display alias cannot exceed 50 characters'),
  ageYears: z.number().int('Age must be an integer').min(2, 'Minimum age is 2 years').max(12, 'Maximum age is 12 years').optional(),
  gender: z.enum(['M', 'F', 'unspecified']).optional(),
  pin: text().regex(/^\d{4}$/, 'PIN must be exactly 4 digits'),
});

export const registerDeviceSchema = z.object({
  deviceIdentifier: text()
    .min(3, 'Device identifier must be at least 3 characters long')
    .max(100, 'Device identifier cannot exceed 100 characters'),
  deviceLabel: text().max(100).optional(),
  platform: z.enum(['android', 'ios', 'windows', 'macos', 'linux']),
  appVersion: text().max(20).optional(),
});

export const createSessionSchema = z.object({
  clientSessionUuid: uuidField('clientSessionUuid'),
  participantCode: text().min(1, 'Participant code is required').max(50),
  deviceIdentifier: text().min(1, 'Device identifier is required').max(100),
  sessionSequenceNumber: z.number().int().min(1, 'Session sequence number must be >= 1').max(1_000_000),
  startedAt: isoDateTime('startedAt'),
  endedAt: isoDateTime('endedAt').optional(),
  notes: text().max(1000).optional(),
});

const evaluationSchema = z.object({
  normalizedTarget: text().min(1).max(100),
  normalizedRecognized: text().max(255),
  editDistance: z.number().int().min(0).max(10_000),
  similarityScore: z.number().min(0).max(1),
  similarityPercent: z.number().min(0).max(100),
  isCorrect: z.boolean(),
  evaluationStatus: z.enum(['EXACT_MATCH', 'ACCEPTED_SIMILAR', 'INCORRECT', 'UNRECOGNIZED']),
  thresholdUsed: z.number().min(0).max(1).default(1.0),
  evaluationMethod: text().max(50).default('levenshtein_normalized_v1'),
  feedbackText: text().max(500).nullable().optional(),
});

export const createAttemptSchema = z.object({
  clientAttemptUuid: uuidField('clientAttemptUuid'),
  clientSessionUuid: uuidField('clientSessionUuid'),
  participantCode: text().min(1, 'Participant code is required').max(50),
  deviceIdentifier: text().min(1, 'Device identifier is required').max(100),
  questionId: z.number().int().min(1, 'questionId must be a positive integer').max(1_000_000),
  attemptNumber: z.number().int().min(1, 'attemptNumber must be >= 1').max(1000),
  targetText: text().min(1).max(100),
  recognizedText: text().max(255),
  asrProvider: text().max(50).default('whisper_onnx'),
  locale: text().max(20).default('id_ID'),
  asrConfidence: z.number().min(0).max(1).optional(),
  durationMs: z.number().int().min(0).max(86_400_000).optional(),
  attemptedAt: isoDateTime('attemptedAt'),
  evaluation: evaluationSchema,
});

export const syncSessionItemSchema = createSessionSchema.extend({
  endedAt: isoDateTime('endedAt').nullable().optional(),
  notes: text().max(1000).nullable().optional(),
});

export const syncAttemptItemSchema = createAttemptSchema.extend({
  asrConfidence: z.number().min(0).max(1).nullable().optional(),
  durationMs: z.number().int().min(0).max(86_400_000).nullable().optional(),
});

export const LEGACY_SYNC_MAX_SESSIONS = 200;
export const LEGACY_SYNC_MAX_ATTEMPTS = 1000;
export const LEGACY_BATCH_MAX_PARTICIPANTS = 200;

export const syncBatchSchema = z.object({
  sessions: z.array(syncSessionItemSchema).max(LEGACY_SYNC_MAX_SESSIONS).default([]),
  attempts: z.array(syncAttemptItemSchema).max(LEGACY_SYNC_MAX_ATTEMPTS).default([]),
});

export type SyncSessionItem = z.infer<typeof syncSessionItemSchema>;
export type SyncAttemptItem = z.infer<typeof syncAttemptItemSchema>;
export type SyncBatchPayload = z.infer<typeof syncBatchSchema>;

export const batchParticipantSchema = z.object({
  participants: z
    .array(createParticipantSchema)
    .min(1, 'At least one participant required')
    .max(LEGACY_BATCH_MAX_PARTICIPANTS, `At most ${LEGACY_BATCH_MAX_PARTICIPANTS} participants per batch`),
});

export const paginationQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(500).default(50),
  offset: z.coerce.number().int().min(0).max(1_000_000).default(0),
});

export const listAttemptsQuerySchema = paginationQuerySchema.extend({
  sessionId: uuidField('sessionId').optional(),
});

// ============================================================================
// VOICE PROXY (/api/voice/*)
// ============================================================================

export const TTS_MOODS = ['excited', 'celebratory', 'playful', 'curious', 'warm', 'encouraging', 'gentle', 'patient'] as const;
export type TtsMood = (typeof TTS_MOODS)[number];

const providerIdField = text()
  .min(1)
  .max(100)
  .regex(/^[A-Za-z0-9_\-]+$/, 'Identifier contains invalid characters');

export const ttsSynthesizeSchema = z.object({
  text: text()
    .trim()
    .min(1, 'Text is required')
    .max(config.elevenlabs.ttsMaxTextLength, `Text exceeds ${config.elevenlabs.ttsMaxTextLength} characters limit`),
  voiceId: providerIdField.optional(),
  modelId: providerIdField.optional(),
  mood: z.enum(TTS_MOODS).optional(),
  settings: z
    .object({
      stability: z.number().min(0).max(1).optional(),
      similarityBoost: z.number().min(0).max(1).optional(),
      style: z.number().min(0).max(1).optional(),
      speed: z.number().min(0.7).max(1.2).optional(),
      useSpeakerBoost: z.boolean().optional(),
    })
    .optional(),
});

export type TtsSynthesizeRequest = z.infer<typeof ttsSynthesizeSchema>;

export const sttJsonBodySchema = z.object({
  audioBase64: text().min(1, 'audioBase64 is required'),
  mimeType: text().max(100).optional(),
  languageCode: text()
    .regex(/^[a-z]{2,3}$/, 'languageCode must be an ISO 639 code')
    .optional(),
});

// ============================================================================
// API v2: DEVICE REGISTRATION & SYNC (/api/v2/*)
// ============================================================================

export const deviceRegisterSchema = z.object({
  deviceUuid: uuidField('deviceUuid'),
  platform: z.literal('android', { error: "platform must be 'android'" }),
  appVersion: text().trim().min(1, 'appVersion is required').max(32, 'appVersion must be at most 32 characters'),
  model: text().trim().max(64, 'model must be at most 64 characters').nullish(),
  /** Rahasia perangkat dari respons registrasi pertama (bukti kepemilikan saat registrasi ulang). */
  deviceSecret: text()
    .regex(/^[A-Za-z0-9_-]{20,128}$/, 'deviceSecret must be the value returned by the first registration')
    .optional(),
});

export type DeviceRegisterRequest = z.infer<typeof deviceRegisterSchema>;

export const SYNC_MAX_LEARNERS = 50;
export const SYNC_MAX_SESSIONS = 200;
export const SYNC_MAX_ATTEMPTS = 1000;

export const syncLearnerSchema = z.object({
  clientUuid: uuidField('clientUuid'),
  name: text().trim().min(2, 'name must be 2-40 characters').max(40, 'name must be 2-40 characters'),
  school: text().trim().min(2, 'school must be 2-60 characters').max(60, 'school must be 2-60 characters'),
  age: z
    .number()
    .int()
    .min(LEARNER_MIN_AGE, `age must be ${LEARNER_MIN_AGE} or ${LEARNER_MAX_AGE}`)
    .max(LEARNER_MAX_AGE, `age must be ${LEARNER_MIN_AGE} or ${LEARNER_MAX_AGE}`),
  createdAt: clientTimestamp('createdAt'),
  updatedAt: clientTimestamp('updatedAt'),
});

export const syncGameSessionSchema = z
  .object({
    clientUuid: uuidField('clientUuid'),
    learnerUuid: uuidField('learnerUuid'),
    materi: z.enum(MATERI_CODES),
    nodeIndex: z.number().int().min(0).max(9999),
    gameType: z.enum(GAME_TYPES),
    status: z.enum(SESSION_STATUSES),
    totalItems: z.number().int().min(0).max(MAX_ITEMS_PER_SESSION),
    firstTryCorrect: z.number().int().min(0).max(MAX_ITEMS_PER_SESSION),
    stars: z.number().int().min(0).max(MAX_STARS_PER_NODE),
    startedAt: clientTimestamp('startedAt'),
    endedAt: clientTimestamp('endedAt').nullish(),
  })
  .refine((s) => s.firstTryCorrect <= s.totalItems, {
    message: 'firstTryCorrect must not exceed totalItems',
    path: ['firstTryCorrect'],
  })
  // Setiap timestamp dipangkas terpisah; sesi tidak boleh berakhir sebelum dimulai.
  .transform((s) => (s.endedAt && Date.parse(s.endedAt) < Date.parse(s.startedAt) ? { ...s, endedAt: s.startedAt } : s));

export const syncAnswerAttemptSchema = z.object({
  clientUuid: uuidField('clientUuid'),
  sessionUuid: uuidField('sessionUuid'),
  learnerUuid: uuidField('learnerUuid'),
  gameType: z.enum(GAME_TYPES),
  targetText: text().min(1, 'targetText is required').max(60),
  answerText: text().max(200),
  isCorrect: z.boolean(),
  attemptNumber: z.number().int().min(1).max(1000),
  similarity: z.number().min(0).max(1).nullish(),
  responseMs: z.number().int().min(0).max(86_400_000).nullish(),
  sttError: text().max(40).nullish(),
  createdAt: clientTimestamp('createdAt'),
});

export type SyncLearner = z.infer<typeof syncLearnerSchema>;
export type SyncGameSession = z.infer<typeof syncGameSessionSchema>;
export type SyncAnswerAttempt = z.infer<typeof syncAnswerAttemptSchema>;

/**
 * Validasi tingkat request: hanya struktur dan batas jumlah item. Setiap item
 * divalidasi terpisah sehingga satu item rusak tidak menggagalkan seluruh
 * batch (item tersebut dikembalikan sebagai `rejected` dengan kode INVALID).
 */
export const syncRequestSchema = z.object({
  learners: z.array(z.unknown()).max(SYNC_MAX_LEARNERS, `At most ${SYNC_MAX_LEARNERS} learners per request`).default([]),
  sessions: z.array(z.unknown()).max(SYNC_MAX_SESSIONS, `At most ${SYNC_MAX_SESSIONS} sessions per request`).default([]),
  attempts: z.array(z.unknown()).max(SYNC_MAX_ATTEMPTS, `At most ${SYNC_MAX_ATTEMPTS} attempts per request`).default([]),
});

export type SyncRequest = z.infer<typeof syncRequestSchema>;

// ============================================================================
// API v2: RESEARCH METRICS & EXPORT
// ============================================================================

const dateOrDateTime = z.union([z.iso.date(), z.iso.datetime({ offset: true })], {
  error: 'Must be an ISO date (YYYY-MM-DD) or ISO datetime with timezone',
});

/** Parameter query kosong (`?from=`) diperlakukan sama dengan tidak dikirim. */
const blankAsUndefined = (value: unknown) => (typeof value === 'string' && value.trim() === '' ? undefined : value);

export const RESEARCH_DEVICE_FILTERS = ['approved', 'all'] as const;

export const researchQuerySchema = z
  .object({
    learnerUuid: z.preprocess(blankAsUndefined, uuidField('learnerUuid').optional()),
    from: z.preprocess(blankAsUndefined, dateOrDateTime.optional()),
    to: z.preprocess(blankAsUndefined, dateOrDateTime.optional()),
    /**
     * `approved` (default): hanya perangkat yang disetujui peneliti.
     * `all`: juga perangkat `pending` (perangkat yang dicabut selalu dikecualikan).
     */
    devices: z.preprocess(blankAsUndefined, z.enum(RESEARCH_DEVICE_FILTERS).default('approved')),
  })
  .refine(
    (q) => {
      // Batas yang sama persis dengan resolveRange() (tanggal saja pada `to` = seluruh hari, inklusif).
      const { from, toExclusive } = resolveDateBounds(q.from, q.to);
      return !from || !toExclusive || from.getTime() < toExclusive.getTime();
    },
    {
      message: '`from` must be before or equal to `to`',
      path: ['from'],
    }
  );

export type ResearchQuery = z.infer<typeof researchQuerySchema>;

// ============================================================================
// API v2: RESEARCHER DEVICE MANAGEMENT
// ============================================================================

export const deviceIdParamSchema = z.object({
  deviceId: uuidField('deviceId'),
});

export const deviceApproveSchema = z.object({
  label: text().trim().min(1, 'label must be 1-60 characters').max(60, 'label must be 1-60 characters').optional(),
});
