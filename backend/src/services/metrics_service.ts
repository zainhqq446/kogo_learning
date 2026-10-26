import { Pool } from 'pg';
import { GAME_TYPES, MATERI_CODES, STT_GAME_TYPE, THESIS_TARGETS } from '../types/curriculum.js';
import { ResearchQuery } from '../types/schemas.js';
import { CsvColumn, csvHeader, csvRows, CsvValue } from '../utils/csv.js';
import { resolveDateBounds } from '../utils/date_range.js';

/**
 * Metrik pengujian lapangan (Tabel 3.1 proposal):
 * - sttAccuracy         = sttCorrect / sttAttempts x 100 (percobaan permainan `speaking`)
 * - taskCompletion      = sessionsCompleted / sessionsStarted x 100
 * - avgResponseMs       = rata-rata responseMs percobaan `speaking`
 * - errorRate           = sesi dengan >= 1 error STT / sessionsStarted x 100
 *                         (Tabel 3.1: "(Error/Total Sesi) x 100%", target <= 10%)
 * - errorRatePerAttempt = sttErrors / sttAttempts x 100 (diagnostik tambahan
 *                         per percobaan, BUKAN metrik Tabel 3.1; halaman riset di
 *                         aplikasi memakai errorRate per sesi di atas)
 */
export interface Metrics {
  sttAttempts: number;
  sttCorrect: number;
  sttAccuracy: number | null;
  sttErrors: number;
  errorRate: number | null;
  errorRatePerAttempt: number | null;
  avgResponseMs: number | null;
  sessionsStarted: number;
  sessionsCompleted: number;
  taskCompletion: number | null;
  totalStars: number;
}

export interface LearnerMetrics extends Metrics {
  learnerUuid: string;
  name: string;
  school: string;
  age: number;
}

export interface DeviceCounts {
  approved: number;
  pending: number;
  revoked: number;
}

export interface MetricsReport {
  overall: Metrics;
  perLearner: LearnerMetrics[];
  perMateri: Array<{ materi: string } & Metrics>;
  perGame: Array<{ gameType: string } & Metrics>;
  targets: typeof THESIS_TARGETS;
  /** Filter perangkat yang dipakai (`approved` default, atau `all`). */
  deviceFilter: ResearchQuery['devices'];
  /** Jumlah perangkat per status (membantu melihat perangkat yang belum disetujui). */
  devices: DeviceCounts;
}

export interface ResolvedRange {
  learnerUuid: string | null;
  from: Date | null;
  /** Batas atas eksklusif. */
  toExclusive: Date | null;
  devices: ResearchQuery['devices'];
}

type Dim = 'overall' | 'learner' | 'materi' | 'game';

interface Counters {
  sttAttempts: number;
  sttCorrect: number;
  sttErrors: number;
  avgResponseMs: number | null;
  sessionsStarted: number;
  sessionsCompleted: number;
  sessionsWithErrors: number;
  totalStars: number;
}

/**
 * `from` inklusif. `to` inklusif: tanggal saja (YYYY-MM-DD) mencakup seluruh
 * hari tersebut (UTC); datetime mencakup hingga milidetik tersebut. Batas
 * dihitung oleh resolveDateBounds(), helper yang sama dengan validasi
 * researchQuerySchema.
 */
export function resolveRange(query: ResearchQuery): ResolvedRange {
  const { from, toExclusive } = resolveDateBounds(query.from, query.to);
  return { learnerUuid: query.learnerUuid?.toLowerCase() ?? null, from, toExclusive, devices: query.devices ?? 'approved' };
}

function percent(numerator: number, denominator: number): number | null {
  if (denominator <= 0) return null;
  return Math.round((numerator / denominator) * 10000) / 100;
}

function emptyCounters(): Counters {
  return {
    sttAttempts: 0,
    sttCorrect: 0,
    sttErrors: 0,
    avgResponseMs: null,
    sessionsStarted: 0,
    sessionsCompleted: 0,
    sessionsWithErrors: 0,
    totalStars: 0,
  };
}

export function toMetrics(c: Counters): Metrics {
  return {
    sttAttempts: c.sttAttempts,
    sttCorrect: c.sttCorrect,
    sttAccuracy: percent(c.sttCorrect, c.sttAttempts),
    sttErrors: c.sttErrors,
    errorRate: percent(c.sessionsWithErrors, c.sessionsStarted),
    errorRatePerAttempt: percent(c.sttErrors, c.sttAttempts),
    avgResponseMs: c.avgResponseMs,
    sessionsStarted: c.sessionsStarted,
    sessionsCompleted: c.sessionsCompleted,
    taskCompletion: percent(c.sessionsCompleted, c.sessionsStarted),
    totalStars: c.totalStars,
  };
}

const DIM_SQL = `CASE WHEN GROUPING(learner_uuid) = 0 THEN 'learner'
                      WHEN GROUPING(materi_code) = 0 THEN 'materi'
                      WHEN GROUPING(game_type) = 0 THEN 'game'
                      ELSE 'overall' END`;

const FILTER_LEARNER = `($1::uuid IS NULL OR l.client_uuid = $1::uuid)`;
const filterTime = (column: string) =>
  `($2::timestamptz IS NULL OR ${column} >= $2::timestamptz) AND ($3::timestamptz IS NULL OR ${column} < $3::timestamptz)`;
/**
 * Kepercayaan perangkat: perangkat yang dicabut selalu dikecualikan; perangkat
 * `pending` hanya ikut bila filter `devices=all`.
 */
const filterDevice = (alias: string, param: string) =>
  `${alias}.revoked_at IS NULL AND (${param}::text = 'all' OR ${alias}.approved_at IS NOT NULL)`;
const FILTER_DEVICE = filterDevice('d', '$4');

const ATTEMPT_METRICS_SQL = `
  WITH a AS (
    SELECT l.client_uuid::text AS learner_uuid, gs.materi_code, aa.game_type, aa.is_correct, aa.stt_error, aa.response_ms
    FROM answer_attempts aa
    JOIN game_sessions gs ON gs.id = aa.session_id
    JOIN learners l ON l.id = aa.learner_id
    JOIN app_devices d ON d.id = l.device_id
    WHERE aa.game_type = '${STT_GAME_TYPE}' AND ${FILTER_LEARNER} AND ${filterTime('aa.created_at')} AND ${FILTER_DEVICE}
  )
  SELECT ${DIM_SQL} AS dim, learner_uuid, materi_code, game_type,
         COUNT(*)::int AS stt_attempts,
         COUNT(*) FILTER (WHERE is_correct)::int AS stt_correct,
         COUNT(*) FILTER (WHERE stt_error IS NOT NULL)::int AS stt_errors,
         ROUND(AVG(response_ms))::int AS avg_response_ms
  FROM a
  GROUP BY GROUPING SETS ((), (learner_uuid), (materi_code), (game_type))`;

const SESSION_METRICS_SQL = `
  WITH s AS (
    SELECT l.client_uuid::text AS learner_uuid, gs.materi_code, gs.game_type, gs.status,
           EXISTS (
             SELECT 1 FROM answer_attempts aa
             WHERE aa.session_id = gs.id AND aa.game_type = '${STT_GAME_TYPE}' AND aa.stt_error IS NOT NULL
           ) AS has_error
    FROM game_sessions gs
    JOIN learners l ON l.id = gs.learner_id
    JOIN app_devices d ON d.id = l.device_id
    WHERE ${FILTER_LEARNER} AND ${filterTime('gs.started_at')} AND ${FILTER_DEVICE}
  )
  SELECT ${DIM_SQL} AS dim, learner_uuid, materi_code, game_type,
         COUNT(*)::int AS sessions_started,
         COUNT(*) FILTER (WHERE status = 'completed')::int AS sessions_completed,
         COUNT(*) FILTER (WHERE has_error)::int AS sessions_with_errors
  FROM s
  GROUP BY GROUPING SETS ((), (learner_uuid), (materi_code), (game_type))`;

const STAR_METRICS_SQL = `
  WITH base AS (
    SELECT l.client_uuid::text AS learner_uuid, gs.materi_code, gs.node_index, gs.game_type, gs.stars
    FROM game_sessions gs
    JOIN learners l ON l.id = gs.learner_id
    JOIN app_devices d ON d.id = l.device_id
    WHERE gs.status = 'completed' AND ${FILTER_LEARNER} AND ${filterTime('gs.started_at')} AND ${FILTER_DEVICE}
  ),
  best_node AS (
    SELECT learner_uuid, materi_code, node_index, MAX(stars) AS best FROM base GROUP BY learner_uuid, materi_code, node_index
  ),
  best_game AS (
    SELECT game_type, MAX(stars) AS best FROM base GROUP BY learner_uuid, materi_code, node_index, game_type
  )
  SELECT CASE WHEN GROUPING(learner_uuid) = 0 THEN 'learner' WHEN GROUPING(materi_code) = 0 THEN 'materi' ELSE 'overall' END AS dim,
         learner_uuid, materi_code, NULL::text AS game_type, COALESCE(SUM(best), 0)::int AS total_stars
  FROM best_node
  GROUP BY GROUPING SETS ((), (learner_uuid), (materi_code))
  UNION ALL
  SELECT 'game' AS dim, NULL, NULL, game_type, COALESCE(SUM(best), 0)::int FROM best_game GROUP BY game_type`;

interface DimRow {
  dim: Dim;
  learner_uuid: string | null;
  materi_code: string | null;
  game_type: string | null;
}

function dimKey(row: DimRow): string {
  switch (row.dim) {
    case 'learner':
      return `learner:${row.learner_uuid}`;
    case 'materi':
      return `materi:${row.materi_code}`;
    case 'game':
      return `game:${row.game_type}`;
    default:
      return 'overall';
  }
}

export interface AttemptExportRow {
  attempt_uuid: string;
  session_uuid: string;
  learner_uuid: string;
  learner_name: string;
  school: string;
  age: number;
  device_id: string;
  device_label: string | null;
  materi: string;
  node_index: number;
  game_type: string;
  target_text: string;
  answer_text: string;
  is_correct: boolean;
  attempt_number: number;
  similarity: string | null;
  response_ms: number | null;
  stt_error: string | null;
  created_at: Date;
  synced_at: Date;
  cursor_ts: string;
}

export interface SessionExportRow {
  session_uuid: string;
  learner_uuid: string;
  learner_name: string;
  school: string;
  age: number;
  device_id: string;
  device_label: string | null;
  materi: string;
  node_index: number;
  game_type: string;
  status: string;
  total_items: number;
  first_try_correct: number;
  stars: number;
  started_at: Date;
  ended_at: Date | null;
  duration_seconds: number | null;
  synced_at: Date;
  cursor_ts: string;
}

/** Satu potongan CSV hasil ekspor bertahap. */
export interface CsvChunk {
  chunk: string;
  rows: number;
}

/**
 * Kolom ekspor. `device_id` adalah id internal perangkat (bukan deviceUuid,
 * yang merupakan kredensial perangkat dan tidak pernah diekspor).
 */
export const ATTEMPT_EXPORT_COLUMNS: Array<CsvColumn<AttemptExportRow>> = [
  { header: 'attempt_uuid', value: (r) => r.attempt_uuid },
  { header: 'session_uuid', value: (r) => r.session_uuid },
  { header: 'learner_uuid', value: (r) => r.learner_uuid },
  { header: 'learner_name', value: (r) => r.learner_name },
  { header: 'school', value: (r) => r.school },
  { header: 'age', value: (r) => Number(r.age) },
  { header: 'device_id', value: (r) => r.device_id },
  { header: 'device_label', value: (r) => r.device_label },
  { header: 'materi', value: (r) => r.materi },
  { header: 'node_index', value: (r) => r.node_index },
  { header: 'game_type', value: (r) => r.game_type },
  { header: 'target_text', value: (r) => r.target_text },
  { header: 'answer_text', value: (r) => r.answer_text },
  { header: 'is_correct', value: (r) => r.is_correct },
  { header: 'attempt_number', value: (r) => r.attempt_number },
  { header: 'similarity', value: (r) => (r.similarity === null ? null : Number(r.similarity)) },
  { header: 'response_ms', value: (r) => r.response_ms },
  { header: 'stt_error', value: (r) => r.stt_error },
  { header: 'created_at', value: (r) => r.created_at },
  { header: 'synced_at', value: (r) => r.synced_at },
];

export const SESSION_EXPORT_COLUMNS: Array<CsvColumn<SessionExportRow>> = [
  { header: 'session_uuid', value: (r) => r.session_uuid },
  { header: 'learner_uuid', value: (r) => r.learner_uuid },
  { header: 'learner_name', value: (r) => r.learner_name },
  { header: 'school', value: (r) => r.school },
  { header: 'age', value: (r) => Number(r.age) },
  { header: 'device_id', value: (r) => r.device_id },
  { header: 'device_label', value: (r) => r.device_label },
  { header: 'materi', value: (r) => r.materi },
  { header: 'node_index', value: (r) => r.node_index },
  { header: 'game_type', value: (r) => r.game_type },
  { header: 'status', value: (r) => r.status },
  { header: 'total_items', value: (r) => r.total_items },
  { header: 'first_try_correct', value: (r) => r.first_try_correct },
  { header: 'stars', value: (r) => r.stars },
  { header: 'started_at', value: (r) => r.started_at },
  { header: 'ended_at', value: (r) => r.ended_at },
  { header: 'duration_seconds', value: (r): CsvValue => r.duration_seconds },
  { header: 'synced_at', value: (r) => r.synced_at },
];

/** Kursor keyset presisi mikrodetik (Date JS hanya milidetik). */
const CURSOR_TS = (column: string) => `to_char(${column} AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')`;

const EXPORT_ATTEMPTS_SQL = `
  SELECT aa.client_uuid::text AS attempt_uuid, gs.client_uuid::text AS session_uuid, l.client_uuid::text AS learner_uuid,
         l.name AS learner_name, l.school, l.age, d.id::text AS device_id, d.label AS device_label, gs.materi_code AS materi,
         gs.node_index, aa.game_type, aa.target_text, aa.answer_text, aa.is_correct, aa.attempt_number,
         aa.similarity, aa.response_ms, aa.stt_error, aa.created_at, aa.synced_at, ${CURSOR_TS('aa.created_at')} AS cursor_ts
  FROM answer_attempts aa
  JOIN game_sessions gs ON gs.id = aa.session_id
  JOIN learners l ON l.id = aa.learner_id
  JOIN app_devices d ON d.id = l.device_id
  WHERE ${FILTER_LEARNER} AND ${filterTime('aa.created_at')} AND ${FILTER_DEVICE}
    AND ($5::timestamptz IS NULL OR (aa.created_at, aa.client_uuid) > ($5::timestamptz, $6::uuid))
  ORDER BY aa.created_at, aa.client_uuid
  LIMIT $7`;

const EXPORT_SESSIONS_SQL = `
  SELECT gs.client_uuid::text AS session_uuid, l.client_uuid::text AS learner_uuid, l.name AS learner_name, l.school, l.age,
         d.id::text AS device_id, d.label AS device_label, gs.materi_code AS materi, gs.node_index, gs.game_type, gs.status,
         gs.total_items, gs.first_try_correct, gs.stars, gs.started_at, gs.ended_at,
         CASE WHEN gs.ended_at IS NULL THEN NULL
              ELSE GREATEST(0, ROUND(EXTRACT(EPOCH FROM (gs.ended_at - gs.started_at))))::int END AS duration_seconds,
         gs.synced_at, ${CURSOR_TS('gs.started_at')} AS cursor_ts
  FROM game_sessions gs
  JOIN learners l ON l.id = gs.learner_id
  JOIN app_devices d ON d.id = l.device_id
  WHERE ${FILTER_LEARNER} AND ${filterTime('gs.started_at')} AND ${FILTER_DEVICE}
    AND ($5::timestamptz IS NULL OR (gs.started_at, gs.client_uuid) > ($5::timestamptz, $6::uuid))
  ORDER BY gs.started_at, gs.client_uuid
  LIMIT $7`;

export const DEFAULT_EXPORT_BATCH_SIZE = 2000;

export class MetricsService {
  constructor(
    private pool: Pool,
    private readonly exportBatchSize: number = DEFAULT_EXPORT_BATCH_SIZE
  ) {}

  async getMetrics(query: ResearchQuery): Promise<MetricsReport> {
    const range = resolveRange(query);
    const params = [range.learnerUuid, range.from, range.toExclusive, range.devices];

    const [attemptRes, sessionRes, starRes, learnerRes, deviceRes] = await Promise.all([
      this.pool.query<DimRow & { stt_attempts: number; stt_correct: number; stt_errors: number; avg_response_ms: number | null }>(
        ATTEMPT_METRICS_SQL,
        params
      ),
      this.pool.query<DimRow & { sessions_started: number; sessions_completed: number; sessions_with_errors: number }>(
        SESSION_METRICS_SQL,
        params
      ),
      this.pool.query<DimRow & { total_stars: number }>(STAR_METRICS_SQL, params),
      this.pool.query<{ learner_uuid: string; name: string; school: string; age: number }>(
        `SELECT l.client_uuid::text AS learner_uuid, l.name, l.school, l.age
         FROM learners l
         JOIN app_devices d ON d.id = l.device_id
         WHERE ${FILTER_LEARNER} AND ${filterDevice('d', '$2')}
         ORDER BY l.school, l.name, l.client_uuid`,
        [range.learnerUuid, range.devices]
      ),
      this.pool.query<{ approved: number; pending: number; revoked: number }>(
        `SELECT COUNT(*) FILTER (WHERE revoked_at IS NULL AND approved_at IS NOT NULL)::int AS approved,
                COUNT(*) FILTER (WHERE revoked_at IS NULL AND approved_at IS NULL)::int AS pending,
                COUNT(*) FILTER (WHERE revoked_at IS NOT NULL)::int AS revoked
         FROM app_devices`
      ),
    ]);

    const counters = new Map<string, Counters>();
    const get = (k: string): Counters => {
      let c = counters.get(k);
      if (!c) {
        c = emptyCounters();
        counters.set(k, c);
      }
      return c;
    };

    for (const row of attemptRes.rows) {
      const c = get(dimKey(row));
      c.sttAttempts = Number(row.stt_attempts);
      c.sttCorrect = Number(row.stt_correct);
      c.sttErrors = Number(row.stt_errors);
      c.avgResponseMs = row.avg_response_ms === null ? null : Number(row.avg_response_ms);
    }
    for (const row of sessionRes.rows) {
      const c = get(dimKey(row));
      c.sessionsStarted = Number(row.sessions_started);
      c.sessionsCompleted = Number(row.sessions_completed);
      c.sessionsWithErrors = Number(row.sessions_with_errors);
    }
    for (const row of starRes.rows) {
      get(dimKey(row)).totalStars = Number(row.total_stars);
    }

    return {
      overall: toMetrics(get('overall')),
      perLearner: learnerRes.rows.map((l) => ({
        learnerUuid: l.learner_uuid,
        name: l.name,
        school: l.school,
        age: Number(l.age),
        ...toMetrics(get(`learner:${l.learner_uuid}`)),
      })),
      perMateri: MATERI_CODES.map((materi) => ({ materi, ...toMetrics(get(`materi:${materi}`)) })),
      perGame: GAME_TYPES.map((gameType) => ({ gameType, ...toMetrics(get(`game:${gameType}`)) })),
      targets: THESIS_TARGETS,
      deviceFilter: range.devices,
      devices: {
        approved: Number(deviceRes.rows[0]?.approved ?? 0),
        pending: Number(deviceRes.rows[0]?.pending ?? 0),
        revoked: Number(deviceRes.rows[0]?.revoked ?? 0),
      },
    };
  }

  /**
   * Ekspor bertahap (keyset pagination per `exportBatchSize` baris) agar data
   * besar tidak pernah dimuat seluruhnya ke memori. Potongan pertama berisi BOM
   * + header + batch pertama dan baru dihasilkan setelah query pertama berhasil,
   * sehingga error database sebelum data terkirim tetap menjadi respons JSON.
   */
  exportAttemptsCsv(query: ResearchQuery): AsyncGenerator<CsvChunk> {
    return this.exportCsv(query, EXPORT_ATTEMPTS_SQL, ATTEMPT_EXPORT_COLUMNS, (r) => r.attempt_uuid);
  }

  exportSessionsCsv(query: ResearchQuery): AsyncGenerator<CsvChunk> {
    return this.exportCsv(query, EXPORT_SESSIONS_SQL, SESSION_EXPORT_COLUMNS, (r) => r.session_uuid);
  }

  private async *exportCsv<T extends { cursor_ts: string }>(
    query: ResearchQuery,
    sql: string,
    columns: Array<CsvColumn<T>>,
    rowUuid: (row: T) => string
  ): AsyncGenerator<CsvChunk> {
    const range = resolveRange(query);
    let cursor: { ts: string; uuid: string } | null = null;
    let first = true;
    for (;;) {
      const res: { rows: T[] } = await this.pool.query<T>(sql, [
        range.learnerUuid,
        range.from,
        range.toExclusive,
        range.devices,
        cursor?.ts ?? null,
        cursor?.uuid ?? null,
        this.exportBatchSize,
      ]);
      const body = csvRows(columns, res.rows);
      if (first) {
        yield { chunk: csvHeader(columns) + body, rows: res.rows.length };
        first = false;
      } else if (res.rows.length > 0) {
        yield { chunk: body, rows: res.rows.length };
      }
      if (res.rows.length < this.exportBatchSize) return;
      const last = res.rows[res.rows.length - 1];
      cursor = { ts: last.cursor_ts, uuid: rowUuid(last) };
    }
  }

  /** Jejak audit akses data riset (non-blocking). */
  async logAudit(userId: string | undefined, action: string, resource: string, ip?: string, metadata?: unknown): Promise<void> {
    try {
      await this.pool.query(
        `INSERT INTO audit_logs (user_id, action, resource_affected, ip_address, metadata, created_at)
         VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP)`,
        [userId ?? null, action, resource.slice(0, 100), ip?.slice(0, 45) ?? null, metadata ? JSON.stringify(metadata) : null]
      );
    } catch {
      // Audit log tidak boleh menggagalkan request.
    }
  }
}
