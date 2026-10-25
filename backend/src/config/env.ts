import dotenv from 'dotenv';

dotenv.config();

export interface ServerConfig {
  port: number;
  nodeEnv: string;
  apiPrefix: string;
  corsOrigin: string | string[];
}

export interface DatabaseConfig {
  host: string;
  port: number;
  database: string;
  user: string;
  password?: string;
  ssl: boolean;
  maxConnections: number;
  idleTimeoutMillis: number;
  connectionTimeoutMillis: number;
}

export interface AuthConfig {
  jwtSecret: string;
  jwtExpiresIn: string;
  jwtRefreshExpiresIn: string;
  bcryptSaltRounds: number;
}

export interface ElevenLabsConfig {
  baseUrl: string;
  apiKey?: string;
  defaultVoiceId: string;
  defaultModelId: string;
}

export interface AppConfig {
  server: ServerConfig;
  database: DatabaseConfig;
  auth: AuthConfig;
  elevenlabs: ElevenLabsConfig;
}

function parseCorsOrigin(val?: string): string | string[] {
  if (!val || val === '*') return '*';
  const origins = val.split(',').map((o) => o.trim()).filter(Boolean);
  return origins.length === 1 ? origins[0] : origins;
}

export const config: AppConfig = {
  server: {
    port: parseInt(process.env.PORT || '4000', 10),
    nodeEnv: process.env.NODE_ENV || 'development',
    apiPrefix: process.env.API_PREFIX || '/api',
    corsOrigin: parseCorsOrigin(process.env.CORS_ORIGIN),
  },
  database: {
    host: process.env.DB_HOST || 'localhost',
    port: parseInt(process.env.DB_PORT || '5432', 10),
    database: process.env.DB_NAME || 'kogo_research',
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD,
    ssl: process.env.DB_SSL === 'true',
    maxConnections: parseInt(process.env.DB_MAX_CONNECTIONS || '20', 10),
    idleTimeoutMillis: parseInt(process.env.DB_IDLE_TIMEOUT_MILLIS || '30000', 10),
    connectionTimeoutMillis: parseInt(process.env.DB_CONNECTION_TIMEOUT_MILLIS || '5000', 10),
  },
  auth: {
    jwtSecret: process.env.JWT_SECRET || 'kogo_dev_jwt_secret_change_in_production_min32chars',
    jwtExpiresIn: process.env.JWT_EXPIRES_IN || '15m',
    jwtRefreshExpiresIn: process.env.JWT_REFRESH_EXPIRES_IN || '7d',
    bcryptSaltRounds: parseInt(process.env.BCRYPT_SALT_ROUNDS || '10', 10),
  },
  elevenlabs: {
    baseUrl: process.env.ELEVENLABS_BASE_URL || 'https://api.elevenlabs.io/v1',
    apiKey: process.env.ELEVENLABS_API_KEY || '',
    defaultVoiceId: process.env.ELEVENLABS_DEFAULT_VOICE_ID || 'cgSgspJ2msm6clMCkdW9',
    defaultModelId: process.env.ELEVENLABS_DEFAULT_MODEL_ID || 'eleven_flash_v2_5',
  },
};
