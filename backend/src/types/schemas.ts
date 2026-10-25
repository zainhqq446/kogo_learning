import { z } from 'zod';

export const registerSchema = z.object({
  username: z
    .string()
    .min(3, 'Username minimal 3 karakter')
    .max(50, 'Username maksimal 50 karakter')
    .regex(/^[a-zA-Z0-9_]+$/, 'Username hanya boleh berupa huruf, angka, dan garis bawah (_)'),
  password: z
    .string()
    .min(6, 'Password minimal 6 karakter')
    .max(100, 'Password tidak boleh melebihi 100 karakter'),
  fullName: z
    .string()
    .min(2, 'Nama lengkap / nama anak minimal 2 karakter')
    .max(100, 'Nama lengkap maksimal 100 karakter'),
  role: z.enum(['admin', 'researcher', 'teacher', 'child', 'student']).optional(),
  ageYears: z
    .number()
    .int('Umur harus bilangan bulat')
    .min(2, 'Umur minimal 2 tahun')
    .max(18, 'Umur maksimal 18 tahun')
    .optional(),
  schoolName: z
    .string()
    .min(2, 'Nama sekolah minimal 2 karakter')
    .max(150, 'Nama sekolah maksimal 150 karakter')
    .optional(),
});

export const childRegisterSchema = z.object({
  fullName: z
    .string()
    .min(2, 'Nama anak minimal 2 karakter')
    .max(100, 'Nama anak maksimal 100 karakter'),
  username: z
    .string()
    .min(3, 'Username minimal 3 karakter')
    .max(50, 'Username maksimal 50 karakter')
    .regex(/^[a-zA-Z0-9_]+$/, 'Username hanya boleh berupa huruf, angka, dan underscore (_)'),
  password: z
    .string()
    .min(6, 'Password minimal 6 karakter')
    .max(100, 'Password maksimal 100 karakter'),
  ageYears: z
    .number({ invalid_type_error: 'Umur harus berupa angka' })
    .int('Umur harus berupa bilangan bulat')
    .min(2, 'Umur minimal 2 tahun')
    .max(18, 'Umur maksimal 18 tahun'),
  schoolName: z
    .string()
    .min(2, 'Nama sekolah minimal 2 karakter')
    .max(150, 'Nama sekolah maksimal 150 karakter'),
});

export const loginSchema = z.object({
  username: z.string().min(1, 'Username is required'),
  password: z.string().min(1, 'Password is required'),
});

export const createParticipantSchema = z.object({
  participantCode: z
    .string()
    .min(2, 'Participant code must be at least 2 characters long')
    .max(50, 'Participant code cannot exceed 50 characters')
    .regex(/^[A-Z0-9_\-]+$/i, 'Participant code should be alphanumeric'),
  displayAlias: z
    .string()
    .min(1, 'Display alias is required')
    .max(50, 'Display alias cannot exceed 50 characters'),
  ageYears: z
    .number()
    .int('Age must be an integer')
    .min(2, 'Minimum age is 2 years')
    .max(12, 'Maximum age is 12 years')
    .optional(),
  gender: z.enum(['M', 'F', 'unspecified']).optional(),
  pin: z
    .string()
    .regex(/^\d{4}$/, 'PIN must be exactly 4 digits'),
});

export const registerDeviceSchema = z.object({
  deviceIdentifier: z
    .string()
    .min(3, 'Device identifier must be at least 3 characters long')
    .max(100, 'Device identifier cannot exceed 100 characters'),
  deviceLabel: z.string().max(100).optional(),
  platform: z.enum(['android', 'ios', 'windows', 'macos', 'linux']),
  appVersion: z.string().max(20).optional(),
});

export const createSessionSchema = z.object({
  clientSessionUuid: z.string().uuid('clientSessionUuid must be a valid UUID v4'),
  participantCode: z.string().min(1, 'Participant code is required'),
  deviceIdentifier: z.string().min(1, 'Device identifier is required'),
  sessionSequenceNumber: z.number().int().min(1, 'Session sequence number must be >= 1'),
  startedAt: z.string().datetime({ message: 'startedAt must be ISO 8601 datetime' }),
  endedAt: z.string().datetime({ message: 'endedAt must be ISO 8601 datetime' }).optional(),
  notes: z.string().max(1000).optional(),
});

export const createAttemptSchema = z.object({
  clientAttemptUuid: z.string().uuid('clientAttemptUuid must be a valid UUID v4'),
  clientSessionUuid: z.string().uuid('clientSessionUuid must be a valid UUID v4'),
  participantCode: z.string().min(1, 'Participant code is required'),
  deviceIdentifier: z.string().min(1, 'Device identifier is required'),
  questionId: z.number().int().min(1, 'questionId must be a positive integer'),
  attemptNumber: z.number().int().min(1, 'attemptNumber must be >= 1'),
  targetText: z.string().min(1).max(100),
  recognizedText: z.string().max(255),
  asrProvider: z.string().max(50).default('whisper_onnx'),
  locale: z.string().max(20).default('id_ID'),
  asrConfidence: z.number().min(0).max(1).optional(),
  durationMs: z.number().int().min(0).optional(),
  attemptedAt: z.string().datetime({ message: 'attemptedAt must be ISO 8601 datetime' }),
  evaluation: z.object({
    normalizedTarget: z.string().min(1).max(100),
    normalizedRecognized: z.string().max(255),
    editDistance: z.number().int().min(0),
    similarityScore: z.number().min(0).max(1),
    similarityPercent: z.number().min(0).max(100),
    isCorrect: z.boolean(),
    evaluationStatus: z.enum(['EXACT_MATCH', 'ACCEPTED_SIMILAR', 'INCORRECT', 'UNRECOGNIZED']),
    thresholdUsed: z.number().min(0).max(1).default(1.0),
    evaluationMethod: z.string().max(50).default('levenshtein_normalized_v1'),
    feedbackText: z.string().optional(),
  }),
});

export const syncSessionItemSchema = z.object({
  clientSessionUuid: z.string().uuid('clientSessionUuid must be a valid UUID v4'),
  participantCode: z.string().min(1, 'Participant code is required'),
  deviceIdentifier: z.string().min(1, 'Device identifier is required'),
  sessionSequenceNumber: z.number().int().min(1, 'sessionSequenceNumber must be >= 1'),
  startedAt: z.string().datetime({ message: 'startedAt must be ISO 8601 datetime' }),
  endedAt: z.string().datetime({ message: 'endedAt must be ISO 8601 datetime' }).nullable().optional(),
  notes: z.string().max(1000).nullable().optional(),
});

export const syncAttemptItemSchema = z.object({
  clientAttemptUuid: z.string().uuid('clientAttemptUuid must be a valid UUID v4'),
  clientSessionUuid: z.string().uuid('clientSessionUuid must be a valid UUID v4'),
  participantCode: z.string().min(1, 'Participant code is required'),
  deviceIdentifier: z.string().min(1, 'Device identifier is required'),
  questionId: z.number().int().min(1, 'questionId must be a positive integer'),
  attemptNumber: z.number().int().min(1, 'attemptNumber must be >= 1'),
  targetText: z.string().min(1).max(100),
  recognizedText: z.string().max(255),
  asrProvider: z.string().max(50).default('whisper_onnx'),
  locale: z.string().max(20).default('id_ID'),
  asrConfidence: z.number().min(0).max(1).nullable().optional(),
  durationMs: z.number().int().min(0).nullable().optional(),
  attemptedAt: z.string().datetime({ message: 'attemptedAt must be ISO 8601 datetime' }),
  evaluation: z.object({
    normalizedTarget: z.string().min(1).max(100),
    normalizedRecognized: z.string().max(255),
    editDistance: z.number().int().min(0),
    similarityScore: z.number().min(0).max(1),
    similarityPercent: z.number().min(0).max(100),
    isCorrect: z.boolean(),
    evaluationStatus: z.enum(['EXACT_MATCH', 'ACCEPTED_SIMILAR', 'INCORRECT', 'UNRECOGNIZED']),
    thresholdUsed: z.number().min(0).max(1).default(1.0),
    evaluationMethod: z.string().max(50).default('levenshtein_normalized_v1'),
    feedbackText: z.string().nullable().optional(),
  }),
});

export const syncBatchSchema = z.object({
  sessions: z.array(syncSessionItemSchema).default([]),
  attempts: z.array(syncAttemptItemSchema).default([]),
});

export type SyncSessionItem = z.infer<typeof syncSessionItemSchema>;
export type SyncAttemptItem = z.infer<typeof syncAttemptItemSchema>;
export type SyncBatchPayload = z.infer<typeof syncBatchSchema>;

export const batchParticipantSchema = z.object({
  participants: z.array(createParticipantSchema).min(1, 'At least one participant required'),
});

export const ttsSynthesizeSchema = z.object({
  text: z.string().min(1, 'Text is required').max(500, 'Text exceeds 500 characters limit'),
  voiceId: z.string().max(100).optional(),
  modelId: z.string().max(100).optional(),
  settings: z.object({
    stability: z.number().min(0).max(1).optional(),
    similarityBoost: z.number().min(0).max(1).optional(),
    style: z.number().min(0).max(1).optional(),
    speed: z.number().min(0.5).max(2.0).optional(),
    useSpeakerBoost: z.boolean().optional(),
  }).optional(),
});
