import crypto from 'crypto';
import path from 'path';
import dotenv from 'dotenv';
import { parseDurationSeconds } from '../utils/duration.js';
import { DEFAULT_TTS_CACHE_DIR } from '../utils/paths.js';

dotenv.config();

/** Dilempar saat konfigurasi environment tidak valid (fail fast saat startup). */
export class ConfigError extends Error {
  constructor(public readonly issues: string[]) {
    super(`Invalid configuration:\n - ${issues.join('\n - ')}`);
    this.name = 'ConfigError';
  }
}

export type TrustProxySetting = boolean | number | string;
export type TextNormalization = 'auto' | 'on' | 'off';

export interface ServerConfig {
  /** Alamat bind HTTP. Default 0.0.0.0 di production (container), 127.0.0.1 selain itu. */
  host: string;
  port: number;
  nodeEnv: string;
  isProduction: boolean;
  apiPrefix: string;
  /** null = CORS dimatikan (tidak ada header Access-Control-*). */
  corsOrigin: string | string[] | null;
  trustProxy: TrustProxySetting;
  jsonBodyLimit: string;
  appVersion: string;
}

export interface DatabaseConfig {
  connectionString?: string;
  host: string;
  port: number;
  database: string;
  user: string;
  password?: string;
  ssl: boolean;
  sslRejectUnauthorized: boolean;
  maxConnections: number;
  idleTimeoutMillis: number;
  connectionTimeoutMillis: number;
}

export interface AuthConfig {
  jwtSecret: string;
  /** true jika JWT_SECRET tidak diset di non-production (secret acak per proses). */
  jwtSecretIsEphemeral: boolean;
  jwtExpiresIn: string;
  jwtExpiresInSeconds: number;
  jwtRefreshExpiresIn: string;
  jwtRefreshExpiresInSeconds: number;
  deviceTokenTtl: string;
  deviceTokenTtlSeconds: number;
  bcryptSaltRounds: number;
  adminUsername?: string;
  adminPassword?: string;
}

export interface ElevenLabsConfig {
  baseUrl: string;
  apiKey: string;
  /** Kosong = TTS belum dikonfigurasi (endpoint mengembalikan 503 NOT_CONFIGURED). */
  defaultVoiceId: string;
  defaultModelId: string;
  sttModelId: string;
  allowedVoiceIds: string[];
  allowedModelIds: string[];
  languageCode: string;
  textNormalization: TextNormalization;
  outputFormat: string;
  ttsMaxTextLength: number;
  maxAudioUploadBytes: number;
  ttsCacheEnabled: boolean;
  ttsCacheDir: string;
  /** Batas ukuran cache audio TTS di disk (byte); file terlama dihapus bila terlampaui. */
  ttsCacheMaxBytes: number;
  ttsTimeoutMs: number;
  sttTimeoutMs: number;
  /** Anggaran harian karakter TTS yang dikirim ke ElevenLabs (cache miss). 0 = tidak ada panggilan baru. */
  dailyTtsCharBudget: number;
  /** Anggaran harian detik audio STT yang dikirim ke ElevenLabs. 0 = STT nonaktif. */
  dailySttSecondsBudget: number;
}

export interface DeviceConfig {
  /**
   * Bila diset, registrasi perangkat BARU wajib menyertakan header
   * `X-Enrollment-Key` dengan nilai ini dan perangkat langsung disetujui.
   * Bila kosong, registrasi terbuka tetapi perangkat baru berstatus `pending`
   * sampai disetujui peneliti.
   */
  enrollmentKey?: string;
  /**
   * Toleransi timestamp klien di masa depan (ms) untuk data sinkronisasi.
   * Timestamp yang melewati batas ini dipangkas ke waktu server (tidak ditolak).
   */
  maxClockSkewMs: number;
  /**
   * Batas jumlah sesi + percobaan yang disimpan untuk satu perangkat yang belum
   * disetujui (`pending`). Sinkronisasi yang akan melampauinya ditolak utuh
   * (403 DEVICE_PENDING_QUOTA) sampai peneliti menyetujui perangkat.
   */
  pendingMaxItems: number;
}

export interface RateLimitConfig {
  enabled: boolean;
  authMax: number;
  authWindowMs: number;
  voicePerMinute: number;
  /** Batas tambahan proxy suara per IP klien (di atas batas per principal). */
  voicePerIpPerMinute: number;
  syncPerMinute: number;
  deviceRegisterPerHour: number;
}

export interface StartupConfig {
  runMigrationsOnStart: boolean;
  dbWaitSeconds: number;
}

export interface AppConfig {
  server: ServerConfig;
  database: DatabaseConfig;
  auth: AuthConfig;
  elevenlabs: ElevenLabsConfig;
  devices: DeviceConfig;
  rateLimit: RateLimitConfig;
  startup: StartupConfig;
  /** Peringatan non-fatal yang dicetak saat server start. */
  warnings: string[];
}

type Env = Record<string, string | undefined>;

const MIN_JWT_SECRET_LENGTH = 32;
const MIN_ENROLLMENT_KEY_LENGTH = 16;
const MIN_ADMIN_PASSWORD_LENGTH = 12;
const KNOWN_WEAK_SECRETS = ['kogo_dev_jwt_secret_change_in_production_min32chars'];
const PLACEHOLDER_PATTERN = /change[_-]?me|replace[_-]?with|your[_-]?secret/i;
const USERNAME_PATTERN = /^[a-z0-9_]{3,50}$/;

const DEFAULT_TTS_MODEL = 'eleven_multilingual_v2';
const DEFAULT_STT_MODEL = 'scribe_v2';
const TTS_OUTPUT_FORMAT = 'mp3_22050_32';

function str(env: Env, key: string): string | undefined {
  const raw = env[key];
  if (raw === undefined) return undefined;
  const trimmed = raw.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function list(env: Env, key: string): string[] {
  const raw = str(env, key);
  if (!raw) return [];
  return raw
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

function parseBool(raw: string | undefined, fallback: boolean, key: string, issues: string[]): boolean {
  if (raw === undefined) return fallback;
  const value = raw.toLowerCase();
  if (['true', '1', 'yes', 'on'].includes(value)) return true;
  if (['false', '0', 'no', 'off'].includes(value)) return false;
  issues.push(`${key} must be true or false (got "${raw}")`);
  return fallback;
}

function parseIntInRange(
  raw: string | undefined,
  fallback: number,
  key: string,
  min: number,
  max: number,
  issues: string[]
): number {
  if (raw === undefined) return fallback;
  if (!/^-?\d+$/.test(raw)) {
    issues.push(`${key} must be an integer (got "${raw}")`);
    return fallback;
  }
  const value = Number(raw);
  if (value < min || value > max) {
    issues.push(`${key} must be between ${min} and ${max} (got ${value})`);
    return fallback;
  }
  return value;
}

function parseDuration(raw: string | undefined, fallback: string, key: string, issues: string[]): [string, number] {
  const value = raw ?? fallback;
  try {
    return [value, parseDurationSeconds(value)];
  } catch (err) {
    issues.push(`${key}: ${(err as Error).message}`);
    return [fallback, parseDurationSeconds(fallback)];
  }
}

/**
 * Default TRUST_PROXY: hanya percayai X-Forwarded-For bila peer langsung berada
 * di jaringan privat (Traefik/Docker network, loopback). Klien publik yang
 * terhubung langsung ke container tidak dapat memalsukan IP-nya.
 */
export const DEFAULT_TRUST_PROXY = 'loopback, linklocal, uniquelocal';

/**
 * TRUST_PROXY: `false`/`0` = tidak percaya proxy, angka = jumlah hop proxy,
 * atau daftar subnet/nama Express (default `loopback, linklocal, uniquelocal`).
 */
export function parseTrustProxy(raw: string | undefined): TrustProxySetting {
  if (raw === undefined) return DEFAULT_TRUST_PROXY;
  const value = raw.trim().toLowerCase();
  if (value === 'false') return false;
  if (value === 'true') return true;
  if (/^\d+$/.test(value)) {
    const hops = Number(value);
    return hops === 0 ? false : hops;
  }
  return raw.trim();
}

/** CORS_ORIGIN kosong = CORS dimatikan. `*` = semua origin (tanpa credentials). */
export function parseCorsOrigin(raw: string | undefined): string | string[] | null {
  if (!raw) return null;
  const origins = raw
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean);
  if (origins.length === 0) return null;
  if (origins.includes('*')) return '*';
  return origins.length === 1 ? origins[0] : origins;
}

function readAppVersion(env: Env): string {
  return str(env, 'APP_VERSION') ?? '2.0.0';
}

/**
 * Membaca dan memvalidasi konfigurasi dari environment. Fungsi murni agar bisa
 * diuji tanpa mengubah `process.env`.
 *
 * Aturan keamanan:
 * - NODE_ENV default `production` (aman secara default di container).
 * - Production wajib JWT_SECRET >= 32 karakter dan bukan nilai contoh.
 * - Non-production tanpa JWT_SECRET memakai secret acak per proses (bukan default publik).
 */
export function loadConfig(env: Env = process.env): AppConfig {
  const issues: string[] = [];
  const warnings: string[] = [];

  const nodeEnv = str(env, 'NODE_ENV') ?? 'production';
  const isProduction = nodeEnv === 'production';

  // --- Server ---
  const port = parseIntInRange(str(env, 'PORT'), 4000, 'PORT', 1, 65535, issues);
  let apiPrefix = str(env, 'API_PREFIX') ?? '/api';
  if (!apiPrefix.startsWith('/')) apiPrefix = `/${apiPrefix}`;
  apiPrefix = apiPrefix.replace(/\/+$/, '') || '/api';

  const host = str(env, 'HOST') ?? (isProduction ? '0.0.0.0' : '127.0.0.1');

  const trustProxy = parseTrustProxy(str(env, 'TRUST_PROXY'));
  if (trustProxy === true) {
    warnings.push(
      'TRUST_PROXY=true trusts every X-Forwarded-For hop, so clients can spoof their IP; prefer the default private-network list.'
    );
  } else if (typeof trustProxy === 'number') {
    warnings.push(
      `TRUST_PROXY=${trustProxy} trusts X-Forwarded-For from any peer; clients that reach the container directly can spoof their IP.`
    );
  }

  // --- Database ---
  const connectionString = str(env, 'DATABASE_URL');
  if (connectionString && !/^postgres(ql)?:\/\//i.test(connectionString)) {
    issues.push('DATABASE_URL must start with postgres:// or postgresql://');
  }
  const dbSsl = parseBool(str(env, 'DB_SSL'), false, 'DB_SSL', issues);
  const dbSslRejectUnauthorized = parseBool(
    str(env, 'DB_SSL_REJECT_UNAUTHORIZED'),
    true,
    'DB_SSL_REJECT_UNAUTHORIZED',
    issues
  );
  if (dbSsl && !dbSslRejectUnauthorized) {
    warnings.push('DB_SSL_REJECT_UNAUTHORIZED=false disables TLS certificate verification for PostgreSQL.');
  }

  // --- Auth ---
  // Nilai publik (default lama / placeholder .env.example) diperlakukan seperti
  // tidak diset di SEMUA environment: siapa pun dapat memalsukan token dengannya.
  let jwtSecret = str(env, 'JWT_SECRET');
  let jwtSecretIsEphemeral = false;
  if (jwtSecret && (KNOWN_WEAK_SECRETS.includes(jwtSecret) || PLACEHOLDER_PATTERN.test(jwtSecret))) {
    const reason = KNOWN_WEAK_SECRETS.includes(jwtSecret)
      ? 'JWT_SECRET uses a publicly known default value'
      : 'JWT_SECRET still contains the placeholder from .env.example';
    if (isProduction) {
      issues.push(`${reason}; generate a new random secret (openssl rand -hex 48)`);
    } else {
      warnings.push(`${reason}; ignoring it and using an ephemeral random secret instead.`);
    }
    jwtSecret = undefined;
  }
  if (!jwtSecret) {
    if (isProduction) {
      if (!issues.some((i) => i.startsWith('JWT_SECRET'))) {
        issues.push('JWT_SECRET is required in production (at least 32 random characters, e.g. `openssl rand -hex 48`)');
      }
    } else {
      jwtSecret = crypto.randomBytes(48).toString('hex');
      jwtSecretIsEphemeral = true;
      if (!warnings.some((w) => w.startsWith('JWT_SECRET'))) {
        warnings.push('JWT_SECRET is not set; using an ephemeral random secret (tokens become invalid on restart).');
      }
    }
  } else if (jwtSecret.length < MIN_JWT_SECRET_LENGTH) {
    if (isProduction) issues.push(`JWT_SECRET must be at least ${MIN_JWT_SECRET_LENGTH} characters in production`);
    else warnings.push(`JWT_SECRET is shorter than ${MIN_JWT_SECRET_LENGTH} characters`);
  }

  const [jwtExpiresIn, jwtExpiresInSeconds] = parseDuration(str(env, 'JWT_EXPIRES_IN'), '15m', 'JWT_EXPIRES_IN', issues);
  const [jwtRefreshExpiresIn, jwtRefreshExpiresInSeconds] = parseDuration(
    str(env, 'JWT_REFRESH_EXPIRES_IN'),
    '7d',
    'JWT_REFRESH_EXPIRES_IN',
    issues
  );
  const [deviceTokenTtl, deviceTokenTtlSeconds] = parseDuration(
    str(env, 'DEVICE_TOKEN_TTL'),
    '180d',
    'DEVICE_TOKEN_TTL',
    issues
  );
  const bcryptSaltRounds = parseIntInRange(str(env, 'BCRYPT_SALT_ROUNDS'), 10, 'BCRYPT_SALT_ROUNDS', 4, 15, issues);

  const adminUsernameRaw = str(env, 'ADMIN_USERNAME');
  const adminPassword = env.ADMIN_PASSWORD && env.ADMIN_PASSWORD.length > 0 ? env.ADMIN_PASSWORD : undefined;
  const adminUsername = adminUsernameRaw?.toLowerCase();
  if (adminUsername && !USERNAME_PATTERN.test(adminUsername)) {
    issues.push('ADMIN_USERNAME must be 3-50 characters of letters, digits or underscore');
  }
  if (Boolean(adminUsername) !== Boolean(adminPassword)) {
    issues.push('ADMIN_USERNAME and ADMIN_PASSWORD must be set together');
  }
  if (adminPassword && adminPassword.length < MIN_ADMIN_PASSWORD_LENGTH) {
    if (isProduction) issues.push(`ADMIN_PASSWORD must be at least ${MIN_ADMIN_PASSWORD_LENGTH} characters in production`);
    else warnings.push(`ADMIN_PASSWORD is shorter than ${MIN_ADMIN_PASSWORD_LENGTH} characters`);
  }
  if (adminPassword && adminPassword.length > 72) {
    issues.push('ADMIN_PASSWORD must be at most 72 characters (bcrypt limit)');
  }

  // --- ElevenLabs ---
  const baseUrl = (str(env, 'ELEVENLABS_BASE_URL') ?? 'https://api.elevenlabs.io/v1').replace(/\/+$/, '');
  if (!/^https?:\/\//.test(baseUrl) || (isProduction && !baseUrl.startsWith('https://'))) {
    issues.push('ELEVENLABS_BASE_URL must be an https:// URL');
  }
  const defaultVoiceId = str(env, 'ELEVENLABS_DEFAULT_VOICE_ID') ?? '';
  const defaultModelId = str(env, 'ELEVENLABS_DEFAULT_MODEL_ID') ?? DEFAULT_TTS_MODEL;
  const sttModelId = str(env, 'ELEVENLABS_STT_MODEL_ID') ?? DEFAULT_STT_MODEL;
  const allowedVoiceIds = Array.from(
    new Set([...(defaultVoiceId ? [defaultVoiceId] : []), ...list(env, 'ELEVENLABS_ALLOWED_VOICE_IDS')])
  );
  const allowedModelIds = Array.from(new Set([defaultModelId, ...list(env, 'ELEVENLABS_ALLOWED_MODEL_IDS')]));
  const textNormalizationRaw = (str(env, 'ELEVENLABS_TEXT_NORMALIZATION') ?? 'auto').toLowerCase();
  let textNormalization: TextNormalization = 'auto';
  if (textNormalizationRaw === 'auto' || textNormalizationRaw === 'on' || textNormalizationRaw === 'off') {
    textNormalization = textNormalizationRaw;
  } else {
    issues.push('ELEVENLABS_TEXT_NORMALIZATION must be auto, on or off');
  }
  const languageCode = (str(env, 'ELEVENLABS_LANGUAGE_CODE') ?? 'id').toLowerCase();
  if (!/^[a-z]{2,3}$/.test(languageCode)) {
    issues.push('ELEVENLABS_LANGUAGE_CODE must be an ISO 639 code such as "id"');
  }

  const ttsMaxTextLength = parseIntInRange(str(env, 'TTS_MAX_TEXT_LENGTH'), 300, 'TTS_MAX_TEXT_LENGTH', 1, 1000, issues);
  const maxAudioUploadBytes = parseIntInRange(
    str(env, 'MAX_AUDIO_UPLOAD_BYTES'),
    2 * 1024 * 1024,
    'MAX_AUDIO_UPLOAD_BYTES',
    1024,
    25 * 1024 * 1024,
    issues
  );
  const ttsTimeoutMs = parseIntInRange(
    str(env, 'ELEVENLABS_TTS_TIMEOUT_MS'),
    15000,
    'ELEVENLABS_TTS_TIMEOUT_MS',
    1000,
    120000,
    issues
  );
  const sttTimeoutMs = parseIntInRange(
    str(env, 'ELEVENLABS_STT_TIMEOUT_MS'),
    20000,
    'ELEVENLABS_STT_TIMEOUT_MS',
    1000,
    120000,
    issues
  );
  const ttsCacheEnabled = parseBool(str(env, 'TTS_CACHE_ENABLED'), true, 'TTS_CACHE_ENABLED', issues);
  const ttsCacheDirRaw = str(env, 'TTS_CACHE_DIR');
  const ttsCacheDir = ttsCacheDirRaw ? path.resolve(ttsCacheDirRaw) : DEFAULT_TTS_CACHE_DIR;
  const ttsCacheMaxMb = parseIntInRange(str(env, 'TTS_CACHE_MAX_MB'), 256, 'TTS_CACHE_MAX_MB', 1, 100_000, issues);
  const dailyTtsCharBudget = parseIntInRange(
    str(env, 'ELEVENLABS_DAILY_CHAR_BUDGET'),
    20_000,
    'ELEVENLABS_DAILY_CHAR_BUDGET',
    0,
    100_000_000,
    issues
  );
  const dailySttSecondsBudget = parseIntInRange(
    str(env, 'ELEVENLABS_DAILY_STT_SECONDS_BUDGET'),
    1_800,
    'ELEVENLABS_DAILY_STT_SECONDS_BUDGET',
    0,
    10_000_000,
    issues
  );

  // --- Devices (API v2) ---
  const enrollmentKey = str(env, 'DEVICE_ENROLLMENT_KEY');
  if (enrollmentKey && enrollmentKey.length < MIN_ENROLLMENT_KEY_LENGTH) {
    issues.push(`DEVICE_ENROLLMENT_KEY must be at least ${MIN_ENROLLMENT_KEY_LENGTH} characters`);
  }
  if (isProduction && !enrollmentKey) {
    warnings.push(
      'DEVICE_ENROLLMENT_KEY is not set: new devices register as "pending" and their data is excluded from metrics/exports until a researcher approves them (POST /api/v2/research/devices/:deviceId/approve).'
    );
  }
  const maxClockSkewHours = parseIntInRange(
    str(env, 'SYNC_MAX_CLOCK_SKEW_HOURS'),
    24,
    'SYNC_MAX_CLOCK_SKEW_HOURS',
    0,
    24 * 30,
    issues
  );
  const pendingMaxItems = parseIntInRange(
    str(env, 'PENDING_DEVICE_MAX_ITEMS'),
    20_000,
    'PENDING_DEVICE_MAX_ITEMS',
    0,
    10_000_000,
    issues
  );

  // --- Rate limit ---
  const rateLimit: RateLimitConfig = {
    enabled: parseBool(str(env, 'RATE_LIMIT_ENABLED'), true, 'RATE_LIMIT_ENABLED', issues),
    authMax: parseIntInRange(str(env, 'RATE_LIMIT_AUTH_MAX'), 10, 'RATE_LIMIT_AUTH_MAX', 1, 10000, issues),
    authWindowMs: 15 * 60 * 1000,
    voicePerMinute: parseIntInRange(str(env, 'RATE_LIMIT_VOICE_PER_MIN'), 60, 'RATE_LIMIT_VOICE_PER_MIN', 1, 10000, issues),
    voicePerIpPerMinute: parseIntInRange(
      str(env, 'RATE_LIMIT_VOICE_PER_IP_PER_MIN'),
      120,
      'RATE_LIMIT_VOICE_PER_IP_PER_MIN',
      1,
      10000,
      issues
    ),
    syncPerMinute: parseIntInRange(str(env, 'RATE_LIMIT_SYNC_PER_MIN'), 60, 'RATE_LIMIT_SYNC_PER_MIN', 1, 10000, issues),
    deviceRegisterPerHour: parseIntInRange(
      str(env, 'RATE_LIMIT_DEVICE_REGISTER_PER_HOUR'),
      20,
      'RATE_LIMIT_DEVICE_REGISTER_PER_HOUR',
      1,
      10000,
      issues
    ),
  };
  if (!rateLimit.enabled) {
    if (isProduction) warnings.push('RATE_LIMIT_ENABLED=false: rate limiting is disabled in production.');
  }

  // --- Startup ---
  const startup: StartupConfig = {
    runMigrationsOnStart: parseBool(str(env, 'RUN_MIGRATIONS_ON_START'), true, 'RUN_MIGRATIONS_ON_START', issues),
    dbWaitSeconds: parseIntInRange(str(env, 'DB_WAIT_SECONDS'), 60, 'DB_WAIT_SECONDS', 0, 600, issues),
  };

  const database: DatabaseConfig = {
    connectionString,
    host: str(env, 'DB_HOST') ?? 'localhost',
    port: parseIntInRange(str(env, 'DB_PORT'), 5432, 'DB_PORT', 1, 65535, issues),
    database: str(env, 'DB_NAME') ?? 'kogo_research',
    user: str(env, 'DB_USER') ?? 'postgres',
    password: env.DB_PASSWORD && env.DB_PASSWORD.length > 0 ? env.DB_PASSWORD : undefined,
    ssl: dbSsl,
    sslRejectUnauthorized: dbSslRejectUnauthorized,
    maxConnections: parseIntInRange(str(env, 'DB_MAX_CONNECTIONS'), 10, 'DB_MAX_CONNECTIONS', 1, 200, issues),
    idleTimeoutMillis: parseIntInRange(str(env, 'DB_IDLE_TIMEOUT_MILLIS'), 30000, 'DB_IDLE_TIMEOUT_MILLIS', 0, 3600000, issues),
    connectionTimeoutMillis: parseIntInRange(
      str(env, 'DB_CONNECTION_TIMEOUT_MILLIS'),
      5000,
      'DB_CONNECTION_TIMEOUT_MILLIS',
      100,
      120000,
      issues
    ),
  };

  if (issues.length > 0) {
    throw new ConfigError(issues);
  }

  return {
    server: {
      host,
      port,
      nodeEnv,
      isProduction,
      apiPrefix,
      corsOrigin: parseCorsOrigin(str(env, 'CORS_ORIGIN')),
      trustProxy,
      jsonBodyLimit: '1mb',
      appVersion: readAppVersion(env),
    },
    database,
    auth: {
      jwtSecret: jwtSecret as string,
      jwtSecretIsEphemeral,
      jwtExpiresIn,
      jwtExpiresInSeconds,
      jwtRefreshExpiresIn,
      jwtRefreshExpiresInSeconds,
      deviceTokenTtl,
      deviceTokenTtlSeconds,
      bcryptSaltRounds,
      adminUsername,
      adminPassword,
    },
    elevenlabs: {
      baseUrl,
      apiKey: str(env, 'ELEVENLABS_API_KEY') ?? '',
      defaultVoiceId,
      defaultModelId,
      sttModelId,
      allowedVoiceIds,
      allowedModelIds,
      languageCode,
      textNormalization,
      outputFormat: TTS_OUTPUT_FORMAT,
      ttsMaxTextLength,
      maxAudioUploadBytes,
      ttsCacheEnabled,
      ttsCacheDir,
      ttsCacheMaxBytes: ttsCacheMaxMb * 1024 * 1024,
      ttsTimeoutMs,
      sttTimeoutMs,
      dailyTtsCharBudget,
      dailySttSecondsBudget,
    },
    devices: {
      enrollmentKey,
      maxClockSkewMs: maxClockSkewHours * 60 * 60 * 1000,
      pendingMaxItems,
    },
    rateLimit,
    startup,
    warnings,
  };
}

export const config: AppConfig = loadConfig(process.env);
