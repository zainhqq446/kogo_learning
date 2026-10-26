import { Pool, PoolClient } from 'pg';
import { ZodType } from 'zod';
import { config } from '../config/env.js';
import { ForbiddenError, UnauthorizedError } from '../types/errors.js';
import {
  SyncAnswerAttempt,
  SyncGameSession,
  SyncLearner,
  SyncRequest,
  syncAnswerAttemptSchema,
  syncGameSessionSchema,
  syncLearnerSchema,
} from '../types/schemas.js';
import { SESSION_STATUS_RANK, SessionStatus } from '../types/curriculum.js';
import { logger } from '../utils/logger.js';

export type SyncItemType = 'learner' | 'session' | 'attempt';
export type SyncRejectCode = 'UNKNOWN_LEARNER' | 'UNKNOWN_SESSION' | 'FOREIGN_DEVICE' | 'INVALID';

export interface SyncRejection {
  type: SyncItemType;
  clientUuid: string | null;
  code: SyncRejectCode;
  /** Penjelasan singkat (hanya untuk INVALID) untuk membantu debugging klien. */
  detail?: string;
}

export interface SyncResult {
  accepted: { learners: number; sessions: number; attempts: number };
  rejected: SyncRejection[];
}

interface LearnerRef {
  id: string;
  deviceId: string;
}

interface SessionRef {
  id: string;
  deviceId: string;
  learnerId: string;
}

interface ParsedItem<T> {
  value: T;
  /** clientUuid seperti yang dikirim klien (untuk dikembalikan apa adanya). */
  rawUuid: string;
  key: string;
}

const RANK_SQL = (column: string) =>
  `(CASE ${column} WHEN 'completed' THEN ${SESSION_STATUS_RANK.completed} WHEN 'abandoned' THEN ${SESSION_STATUS_RANK.abandoned} ELSE ${SESSION_STATUS_RANK.started} END)`;

function rawClientUuid(item: unknown): string | null {
  if (typeof item === 'object' && item !== null && 'clientUuid' in item) {
    const value = (item as { clientUuid: unknown }).clientUuid;
    if (typeof value === 'string' && value.length <= 64) return value;
  }
  return null;
}

function parseItems<T extends { clientUuid: string }>(
  type: SyncItemType,
  items: unknown[],
  schema: ZodType<T>,
  rejected: SyncRejection[]
): Array<ParsedItem<T>> {
  const parsed: Array<ParsedItem<T>> = [];
  for (const item of items) {
    const result = schema.safeParse(item);
    if (result.success) {
      parsed.push({ value: result.data, rawUuid: result.data.clientUuid, key: result.data.clientUuid.toLowerCase() });
    } else {
      const issue = result.error.issues[0];
      const detail = issue ? `${issue.path.map(String).join('.') || type}: ${issue.message}` : 'Invalid item';
      rejected.push({ type, clientUuid: rawClientUuid(item), code: 'INVALID', detail });
    }
  }
  return parsed;
}

const key = (uuid: string) => uuid.toLowerCase();

/**
 * Sinkronisasi data riset dari aplikasi Android (API v2).
 *
 * Semantik:
 * - Satu transaksi per request; upsert idempoten berdasarkan clientUuid.
 * - Data milik perangkat lain tidak pernah ditimpa (ditolak FOREIGN_DEVICE).
 * - Learner: insert / update nama, sekolah, umur, updated_at. Perangkat pemilik
 *   adalah sumber kebenaran, sehingga setiap kiriman dari perangkat yang sama
 *   diterapkan (tidak bergantung pada jam perangkat yang bisa salah).
 * - Session: insert / update status, total, bintang, ended_at; status tidak
 *   pernah turun peringkat (completed tidak kembali menjadi started) dan hasil
 *   sesi yang sudah `completed` (total, bintang, ended_at) bersifat final.
 * - Attempt: insert-only (ON CONFLICT DO NOTHING).
 * - Jumlah `accepted` menghitung clientUuid yang berbeda (duplikat dalam satu
 *   payload tidak dihitung dua kali).
 * - Tabel stars (bintang terbaik per node) dan rewards (tier pertama tercapai)
 *   diperbarui setelah sesi diproses.
 * - Perangkat `pending` dibatasi PENDING_DEVICE_MAX_ITEMS sesi + percobaan;
 *   request yang melampauinya ditolak utuh (403 DEVICE_PENDING_QUOTA).
 */
export class SyncService {
  constructor(private pool: Pool) {}

  async sync(deviceId: string, request: SyncRequest): Promise<SyncResult> {
    const rejected: SyncRejection[] = [];
    const learners = parseItems<SyncLearner>('learner', request.learners, syncLearnerSchema, rejected);
    const sessions = parseItems<SyncGameSession>('session', request.sessions, syncGameSessionSchema, rejected);
    const attempts = parseItems<SyncAnswerAttempt>('attempt', request.attempts, syncAnswerAttemptSchema, rejected);

    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      // Kunci baris perangkat: sinkronisasi paralel dari perangkat yang sama diserialkan.
      const device = await client.query<{ revoked: boolean; approved: boolean }>(
        `UPDATE app_devices SET last_seen_at = CURRENT_TIMESTAMP WHERE id = $1
         RETURNING revoked_at IS NOT NULL AS revoked, approved_at IS NOT NULL AS approved`,
        [deviceId]
      );
      if (device.rowCount === 0) {
        throw new UnauthorizedError('Device is not registered. Register the device again.', 'DEVICE_NOT_REGISTERED');
      }
      if (device.rows[0].revoked) {
        throw new ForbiddenError('This device has been revoked by a researcher.', 'DEVICE_REVOKED');
      }
      if (!device.rows[0].approved) {
        await this.assertPendingQuota(client, deviceId, sessions, attempts);
      }

      const learnerMap = await this.loadLearners(client, [
        ...learners.map((l) => l.key),
        ...sessions.map((s) => key(s.value.learnerUuid)),
        ...attempts.map((a) => key(a.value.learnerUuid)),
      ]);
      const acceptedLearners = await this.upsertLearners(client, deviceId, learners, learnerMap, rejected);

      const sessionMap = await this.loadSessions(client, [
        ...sessions.map((s) => s.key),
        ...attempts.map((a) => key(a.value.sessionUuid)),
      ]);
      const { accepted: acceptedSessions, affectedLearnerIds } = await this.upsertSessions(
        client,
        deviceId,
        sessions,
        learnerMap,
        sessionMap,
        rejected
      );

      if (affectedLearnerIds.size > 0) {
        await this.refreshStarsAndRewards(client, Array.from(affectedLearnerIds));
      }

      const acceptedAttempts = await this.insertAttempts(client, deviceId, attempts, learnerMap, sessionMap, rejected);

      await client.query('COMMIT');

      const result: SyncResult = {
        accepted: { learners: acceptedLearners, sessions: acceptedSessions, attempts: acceptedAttempts },
        rejected,
      };
      logger.info(
        `[SyncV2] device=${deviceId} accepted learners=${acceptedLearners} sessions=${acceptedSessions} attempts=${acceptedAttempts} rejected=${rejected.length}`
      );
      return result;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Perangkat `pending` (belum disetujui) hanya boleh menyimpan sampai
   * PENDING_DEVICE_MAX_ITEMS sesi + percobaan agar registrasi terbuka tidak
   * bisa dipakai untuk mengisi database tanpa batas. Bila request ini akan
   * melampaui batas, SELURUH request ditolak (tidak ada penulisan parsial;
   * data tetap aman di tablet dan terkirim setelah perangkat disetujui).
   * Dipanggil setelah baris perangkat dikunci sehingga sinkronisasi paralel
   * dari perangkat yang sama tidak dapat melewati batas.
   */
  private async assertPendingQuota(
    client: PoolClient,
    deviceId: string,
    sessions: Array<ParsedItem<SyncGameSession>>,
    attempts: Array<ParsedItem<SyncAnswerAttempt>>
  ): Promise<void> {
    const limit = config.devices.pendingMaxItems;
    const sessionKeys = Array.from(new Set(sessions.map((s) => s.key)));
    const attemptKeys = Array.from(new Set(attempts.map((a) => a.key)));
    // `known` = item kiriman ulang yang sudah tersimpan (tidak menambah data),
    // sehingga kiriman ulang setelah respons hilang tidak ikut dihitung.
    const counts = await client.query<{ stored: number; known: number }>(
      `SELECT (SELECT COUNT(*) FROM game_sessions WHERE device_id = $1)::int
            + (SELECT COUNT(*) FROM answer_attempts aa JOIN game_sessions gs ON gs.id = aa.session_id
               WHERE gs.device_id = $1)::int AS stored,
              (SELECT COUNT(*) FROM game_sessions WHERE client_uuid = ANY($2::uuid[]))::int
            + (SELECT COUNT(*) FROM answer_attempts WHERE client_uuid = ANY($3::uuid[]))::int AS known`,
      [deviceId, sessionKeys, attemptKeys]
    );
    const existing = counts.rows[0].stored;
    const incoming = sessionKeys.length + attemptKeys.length - counts.rows[0].known;
    if (existing + incoming > limit) {
      logger.warn(
        `[SyncV2] device=${deviceId} pending quota exceeded: stored=${existing} incoming=${incoming} limit=${limit}`
      );
      throw new ForbiddenError(
        `This device is not approved yet and has reached the storage limit for unapproved devices (${limit} sessions + attempts). ` +
          'Ask a researcher to approve the device; the data stays on the tablet and is sent after approval.',
        'DEVICE_PENDING_QUOTA'
      );
    }
  }

  private async loadLearners(client: PoolClient, uuids: string[]): Promise<Map<string, LearnerRef>> {
    const map = new Map<string, LearnerRef>();
    const unique = Array.from(new Set(uuids));
    if (unique.length === 0) return map;
    const res = await client.query<{ id: string; client_uuid: string; device_id: string }>(
      'SELECT id, client_uuid, device_id FROM learners WHERE client_uuid = ANY($1::uuid[])',
      [unique]
    );
    for (const row of res.rows) map.set(row.client_uuid, { id: row.id, deviceId: row.device_id });
    return map;
  }

  private async loadSessions(client: PoolClient, uuids: string[]): Promise<Map<string, SessionRef>> {
    const map = new Map<string, SessionRef>();
    const unique = Array.from(new Set(uuids));
    if (unique.length === 0) return map;
    const res = await client.query<{ id: string; client_uuid: string; device_id: string; learner_id: string }>(
      'SELECT id, client_uuid, device_id, learner_id FROM game_sessions WHERE client_uuid = ANY($1::uuid[])',
      [unique]
    );
    for (const row of res.rows) {
      map.set(row.client_uuid, { id: row.id, deviceId: row.device_id, learnerId: row.learner_id });
    }
    return map;
  }

  private async upsertLearners(
    client: PoolClient,
    deviceId: string,
    learners: Array<ParsedItem<SyncLearner>>,
    learnerMap: Map<string, LearnerRef>,
    rejected: SyncRejection[]
  ): Promise<number> {
    const accepted = new Set<string>();
    for (const item of learners) {
      const existing = learnerMap.get(item.key);
      if (existing && existing.deviceId !== deviceId) {
        rejected.push({ type: 'learner', clientUuid: item.rawUuid, code: 'FOREIGN_DEVICE' });
        continue;
      }

      const l = item.value;
      const res = await client.query<{ id: string }>(
        `INSERT INTO learners (client_uuid, device_id, name, school, age, created_at, updated_at, synced_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, CURRENT_TIMESTAMP)
         ON CONFLICT (client_uuid) DO UPDATE
         SET name = EXCLUDED.name, school = EXCLUDED.school, age = EXCLUDED.age,
             updated_at = EXCLUDED.updated_at, synced_at = CURRENT_TIMESTAMP
         WHERE learners.device_id = EXCLUDED.device_id
         RETURNING id`,
        [item.key, deviceId, l.name, l.school, l.age, l.createdAt, l.updatedAt]
      );

      if (res.rowCount === 1) {
        learnerMap.set(item.key, { id: res.rows[0].id, deviceId });
        accepted.add(item.key);
      } else {
        // Tidak ada baris yang berubah: baris dibuat perangkat lain (race).
        rejected.push({ type: 'learner', clientUuid: item.rawUuid, code: 'FOREIGN_DEVICE' });
      }
    }
    return accepted.size;
  }

  private async upsertSessions(
    client: PoolClient,
    deviceId: string,
    sessions: Array<ParsedItem<SyncGameSession>>,
    learnerMap: Map<string, LearnerRef>,
    sessionMap: Map<string, SessionRef>,
    rejected: SyncRejection[]
  ): Promise<{ accepted: number; affectedLearnerIds: Set<string> }> {
    const accepted = new Set<string>();
    const affectedLearnerIds = new Set<string>();

    for (const item of sessions) {
      const s = item.value;
      const existing = sessionMap.get(item.key);
      if (existing && existing.deviceId !== deviceId) {
        rejected.push({ type: 'session', clientUuid: item.rawUuid, code: 'FOREIGN_DEVICE' });
        continue;
      }

      const learner = learnerMap.get(key(s.learnerUuid));
      if (!learner) {
        rejected.push({ type: 'session', clientUuid: item.rawUuid, code: 'UNKNOWN_LEARNER' });
        continue;
      }
      if (learner.deviceId !== deviceId) {
        rejected.push({ type: 'session', clientUuid: item.rawUuid, code: 'FOREIGN_DEVICE' });
        continue;
      }
      if (existing && existing.learnerId !== learner.id) {
        rejected.push({
          type: 'session',
          clientUuid: item.rawUuid,
          code: 'INVALID',
          detail: 'learnerUuid does not match the already synced session',
        });
        continue;
      }

      const res = await client.query<{ id: string }>(
        `INSERT INTO game_sessions (client_uuid, learner_id, device_id, materi_code, node_index, game_type, status,
                                    total_items, first_try_correct, stars, started_at, ended_at, synced_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, CURRENT_TIMESTAMP)
         ON CONFLICT (client_uuid) DO UPDATE
         SET status = EXCLUDED.status,
             total_items = CASE WHEN game_sessions.status = 'completed' THEN game_sessions.total_items ELSE EXCLUDED.total_items END,
             first_try_correct = CASE WHEN game_sessions.status = 'completed' THEN game_sessions.first_try_correct
                                      ELSE EXCLUDED.first_try_correct END,
             stars = CASE WHEN game_sessions.status = 'completed' THEN game_sessions.stars ELSE EXCLUDED.stars END,
             ended_at = CASE WHEN game_sessions.status = 'completed' THEN game_sessions.ended_at
                             ELSE COALESCE(EXCLUDED.ended_at, game_sessions.ended_at) END,
             synced_at = CURRENT_TIMESTAMP
         WHERE game_sessions.device_id = EXCLUDED.device_id
           AND game_sessions.learner_id = EXCLUDED.learner_id
           AND ${RANK_SQL('EXCLUDED.status')} >= ${RANK_SQL('game_sessions.status')}
         RETURNING id`,
        [
          item.key,
          learner.id,
          deviceId,
          s.materi,
          s.nodeIndex,
          s.gameType,
          s.status satisfies SessionStatus,
          s.totalItems,
          s.firstTryCorrect,
          s.stars,
          s.startedAt,
          s.endedAt ?? null,
        ]
      );

      let sessionId: string | undefined = res.rows[0]?.id;
      if (!sessionId) {
        // Tidak diperbarui: status masuk lebih rendah (mis. completed -> started)
        // sehingga dipertahankan, atau baris dibuat perangkat lain (race).
        const owner = await client.query<{ id: string; device_id: string; learner_id: string }>(
          'SELECT id, device_id, learner_id FROM game_sessions WHERE client_uuid = $1',
          [item.key]
        );
        const row = owner.rows[0];
        if (!row || row.device_id !== deviceId) {
          rejected.push({ type: 'session', clientUuid: item.rawUuid, code: 'FOREIGN_DEVICE' });
          continue;
        }
        if (row.learner_id !== learner.id) {
          rejected.push({
            type: 'session',
            clientUuid: item.rawUuid,
            code: 'INVALID',
            detail: 'learnerUuid does not match the already synced session',
          });
          continue;
        }
        sessionId = row.id;
      }

      sessionMap.set(item.key, { id: sessionId, deviceId, learnerId: learner.id });
      affectedLearnerIds.add(learner.id);
      accepted.add(item.key);
    }

    return { accepted: accepted.size, affectedLearnerIds };
  }

  /**
   * Bintang terbaik per (learner, materi, node) dari sesi `completed` dan tier
   * hadiah yang tercapai berdasarkan total bintang. Bintang tidak pernah turun
   * dan earned_at hadiah tidak pernah ditimpa.
   */
  private async refreshStarsAndRewards(client: PoolClient, learnerIds: string[]): Promise<void> {
    await client.query(
      `INSERT INTO stars (learner_id, materi_code, node_index, stars, updated_at)
       SELECT learner_id, materi_code, node_index, MAX(stars), CURRENT_TIMESTAMP
       FROM game_sessions
       WHERE status = 'completed' AND learner_id = ANY($1::uuid[])
       GROUP BY learner_id, materi_code, node_index
       ON CONFLICT (learner_id, materi_code, node_index) DO UPDATE
       SET stars = EXCLUDED.stars, updated_at = CURRENT_TIMESTAMP
       WHERE EXCLUDED.stars > stars.stars`,
      [learnerIds]
    );

    await client.query(
      `INSERT INTO rewards (learner_id, tier_code, earned_at)
       SELECT totals.learner_id, rt.code, CURRENT_TIMESTAMP
       FROM (
         SELECT learner_id, SUM(stars) AS total_stars
         FROM stars
         WHERE learner_id = ANY($1::uuid[])
         GROUP BY learner_id
       ) totals
       JOIN reward_tiers rt ON rt.min_stars <= totals.total_stars
       ON CONFLICT (learner_id, tier_code) DO NOTHING`,
      [learnerIds]
    );
  }

  private async insertAttempts(
    client: PoolClient,
    deviceId: string,
    attempts: Array<ParsedItem<SyncAnswerAttempt>>,
    learnerMap: Map<string, LearnerRef>,
    sessionMap: Map<string, SessionRef>,
    rejected: SyncRejection[]
  ): Promise<number> {
    if (attempts.length === 0) return 0;

    const existingRes = await client.query<{ client_uuid: string; device_id: string }>(
      `SELECT aa.client_uuid, gs.device_id
       FROM answer_attempts aa
       JOIN game_sessions gs ON gs.id = aa.session_id
       WHERE aa.client_uuid = ANY($1::uuid[])`,
      [Array.from(new Set(attempts.map((a) => a.key)))]
    );
    const existingOwner = new Map(existingRes.rows.map((row) => [row.client_uuid, row.device_id]));

    /** clientUuid yang sudah tersimpan/terkonfirmasi milik perangkat ini. */
    const accepted = new Set<string>();
    /** clientUuid yang sudah dijadwalkan untuk disisipkan dari payload ini. */
    const scheduled = new Set<string>();
    const toInsert: Array<{ item: ParsedItem<SyncAnswerAttempt>; session: SessionRef }> = [];

    for (const item of attempts) {
      const a = item.value;
      const owner = existingOwner.get(item.key);
      if (owner !== undefined) {
        if (owner === deviceId) accepted.add(item.key);
        else rejected.push({ type: 'attempt', clientUuid: item.rawUuid, code: 'FOREIGN_DEVICE' });
        continue;
      }

      const session = sessionMap.get(key(a.sessionUuid));
      if (!session) {
        rejected.push({ type: 'attempt', clientUuid: item.rawUuid, code: 'UNKNOWN_SESSION' });
        continue;
      }
      if (session.deviceId !== deviceId) {
        rejected.push({ type: 'attempt', clientUuid: item.rawUuid, code: 'FOREIGN_DEVICE' });
        continue;
      }
      const learner = learnerMap.get(key(a.learnerUuid));
      if (!learner) {
        rejected.push({ type: 'attempt', clientUuid: item.rawUuid, code: 'UNKNOWN_LEARNER' });
        continue;
      }
      if (learner.deviceId !== deviceId) {
        rejected.push({ type: 'attempt', clientUuid: item.rawUuid, code: 'FOREIGN_DEVICE' });
        continue;
      }
      if (session.learnerId !== learner.id) {
        rejected.push({
          type: 'attempt',
          clientUuid: item.rawUuid,
          code: 'INVALID',
          detail: 'learnerUuid does not match the session learner',
        });
        continue;
      }

      // Duplikat clientUuid di payload yang sama (setelah referensinya valid):
      // salinan pertama yang disimpan, salinan berikutnya tidak dihitung lagi.
      if (scheduled.has(item.key)) continue;
      scheduled.add(item.key);
      toInsert.push({ item, session });
    }

    if (toInsert.length === 0) return accepted.size;

    const insertRes = await client.query<{ client_uuid: string }>(
      `INSERT INTO answer_attempts (client_uuid, session_id, learner_id, game_type, target_text, answer_text, is_correct,
                                    attempt_number, similarity, response_ms, stt_error, created_at, synced_at)
       SELECT u.client_uuid, u.session_id, u.learner_id, u.game_type, u.target_text, u.answer_text, u.is_correct,
              u.attempt_number, u.similarity, u.response_ms, u.stt_error, u.created_at, CURRENT_TIMESTAMP
       FROM unnest($1::uuid[], $2::uuid[], $3::uuid[], $4::text[], $5::text[], $6::text[], $7::boolean[],
                   $8::int[], $9::numeric[], $10::int[], $11::text[], $12::timestamptz[])
            AS u(client_uuid, session_id, learner_id, game_type, target_text, answer_text, is_correct,
                 attempt_number, similarity, response_ms, stt_error, created_at)
       ON CONFLICT (client_uuid) DO NOTHING
       RETURNING client_uuid`,
      [
        toInsert.map(({ item }) => item.key),
        toInsert.map(({ session }) => session.id),
        toInsert.map(({ session }) => session.learnerId),
        toInsert.map(({ item }) => item.value.gameType),
        toInsert.map(({ item }) => item.value.targetText),
        toInsert.map(({ item }) => item.value.answerText),
        toInsert.map(({ item }) => item.value.isCorrect),
        toInsert.map(({ item }) => item.value.attemptNumber),
        toInsert.map(({ item }) => item.value.similarity ?? null),
        toInsert.map(({ item }) => item.value.responseMs ?? null),
        toInsert.map(({ item }) => item.value.sttError ?? null),
        toInsert.map(({ item }) => item.value.createdAt),
      ]
    );

    const inserted = new Set(insertRes.rows.map((row) => row.client_uuid));
    const conflicted = toInsert.filter(({ item }) => !inserted.has(item.key));
    for (const uuid of inserted) accepted.add(uuid);

    if (conflicted.length > 0) {
      // Race: attempt dengan UUID sama disisipkan transaksi lain di antara pengecekan.
      const ownerRes = await client.query<{ client_uuid: string; device_id: string }>(
        `SELECT aa.client_uuid, gs.device_id FROM answer_attempts aa JOIN game_sessions gs ON gs.id = aa.session_id
         WHERE aa.client_uuid = ANY($1::uuid[])`,
        [conflicted.map(({ item }) => item.key)]
      );
      const owners = new Map(ownerRes.rows.map((row) => [row.client_uuid, row.device_id]));
      for (const { item } of conflicted) {
        if (owners.get(item.key) === deviceId) accepted.add(item.key);
        else rejected.push({ type: 'attempt', clientUuid: item.rawUuid, code: 'FOREIGN_DEVICE' });
      }
    }

    return accepted.size;
  }
}
