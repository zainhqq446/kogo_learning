import { Pool } from 'pg';
import { getDbPool } from '../config/database.js';

export type VoiceUsageMetric = 'tts_chars' | 'stt_seconds';

/**
 * Anggaran harian (UTC) untuk biaya ElevenLabs. Reservasi dilakukan secara
 * atomik sebelum memanggil provider; kegagalan upstream dikembalikan (refund).
 */
export interface VoiceUsageBudget {
  /** Menambah pemakaian bila `terpakai + amount <= limit`; false bila anggaran habis. */
  tryReserve(metric: VoiceUsageMetric, amount: number, limit: number): Promise<boolean>;
  /** Koreksi pemakaian (positif = tambah, negatif = refund), tidak pernah di bawah 0. */
  adjust(metric: VoiceUsageMetric, delta: number): Promise<void>;
}

const TODAY_UTC = `(CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date`;

/** Anggaran di PostgreSQL (tabel voice_usage_daily): bertahan saat restart dan berlaku lintas replika. */
export class DbVoiceUsageBudget implements VoiceUsageBudget {
  constructor(private readonly getPool: () => Pool = getDbPool) {}

  async tryReserve(metric: VoiceUsageMetric, amount: number, limit: number): Promise<boolean> {
    if (amount > limit) return false;
    const res = await this.getPool().query(
      `INSERT INTO voice_usage_daily (day, metric, amount, updated_at)
       VALUES (${TODAY_UTC}, $1, $2, CURRENT_TIMESTAMP)
       ON CONFLICT (day, metric) DO UPDATE
       SET amount = voice_usage_daily.amount + EXCLUDED.amount, updated_at = CURRENT_TIMESTAMP
       WHERE voice_usage_daily.amount + EXCLUDED.amount <= $3
       RETURNING amount`,
      [metric, amount, limit]
    );
    return (res.rowCount ?? 0) > 0;
  }

  async adjust(metric: VoiceUsageMetric, delta: number): Promise<void> {
    if (delta === 0) return;
    await this.getPool().query(
      `INSERT INTO voice_usage_daily (day, metric, amount, updated_at)
       VALUES (${TODAY_UTC}, $1, GREATEST($2::numeric, 0), CURRENT_TIMESTAMP)
       ON CONFLICT (day, metric) DO UPDATE
       SET amount = GREATEST(voice_usage_daily.amount + $2::numeric, 0), updated_at = CURRENT_TIMESTAMP`,
      [metric, delta]
    );
  }
}

/** Anggaran in-memory (test / tanpa database). */
export class MemoryVoiceUsageBudget implements VoiceUsageBudget {
  private readonly used = new Map<string, number>();

  private key(metric: VoiceUsageMetric): string {
    return `${new Date().toISOString().slice(0, 10)}:${metric}`;
  }

  usage(metric: VoiceUsageMetric): number {
    return this.used.get(this.key(metric)) ?? 0;
  }

  async tryReserve(metric: VoiceUsageMetric, amount: number, limit: number): Promise<boolean> {
    const current = this.usage(metric);
    if (current + amount > limit) return false;
    this.used.set(this.key(metric), current + amount);
    return true;
  }

  async adjust(metric: VoiceUsageMetric, delta: number): Promise<void> {
    this.used.set(this.key(metric), Math.max(0, this.usage(metric) + delta));
  }
}
