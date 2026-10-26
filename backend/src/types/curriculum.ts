/**
 * Kode kurikulum yang stabil dan dipakai bersama oleh aplikasi Flutter,
 * validasi API, dan constraint database. Nilai ini harus sama dengan
 * `src/data/vocabulary.json` (diverifikasi oleh unit test).
 */
export const MATERI_CODES = ['letters', 'two-syllable', 'three-syllable', 'multiple'] as const;
export type MateriCode = (typeof MATERI_CODES)[number];

export const GAME_TYPES = ['speaking', 'find-object', 'missing-letter', 'matching', 'listening', 'fill-blank'] as const;
export type GameType = (typeof GAME_TYPES)[number];

/** Permainan berbasis voice recognition (dipakai untuk metrik STT). */
export const STT_GAME_TYPE: GameType = 'speaking';

export const SESSION_STATUSES = ['started', 'completed', 'abandoned'] as const;
export type SessionStatus = (typeof SESSION_STATUSES)[number];

/**
 * Urutan status sesi: status tidak boleh turun peringkat saat sinkronisasi ulang
 * (misalnya sesi `completed` tidak boleh kembali menjadi `started`).
 */
export const SESSION_STATUS_RANK: Record<SessionStatus, number> = {
  started: 0,
  abandoned: 1,
  completed: 2,
};

export const REWARD_TIERS = [
  { code: 'perunggu', title: 'Perunggu', minStars: 10 },
  { code: 'perak', title: 'Perak', minStars: 50 },
  { code: 'emas', title: 'Emas', minStars: 150 },
  { code: 'berlian', title: 'Berlian', minStars: 300 },
] as const;

export const LEARNER_MIN_AGE = 5;
export const LEARNER_MAX_AGE = 6;
export const MAX_ITEMS_PER_SESSION = 20;
export const MAX_STARS_PER_NODE = 3;

/** Target metrik pengujian lapangan (Tabel 3.1 proposal). */
export const THESIS_TARGETS = {
  sttAccuracyMinPercent: 70,
  taskCompletionMinPercent: 75,
  responseTimeMaxMs: 3000,
  errorRateMaxPercent: 10,
} as const;
