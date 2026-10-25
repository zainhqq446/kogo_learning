import { Pool } from 'pg';
import bcrypt from 'bcrypt';
import { Participant, Device, ResearchSession, SpeechAttempt, SimilarityEvaluation } from '../types/research.js';
import { NotFoundError, ValidationError } from '../types/errors.js';
import { config } from '../config/env.js';

export class ResearchService {
  constructor(private pool: Pool) {}

  /**
   * Catat audit log untuk setiap aksi riset/ekspor.
   */
  async logAudit(userId: string | undefined, action: string, resource: string, ip?: string, metadata?: unknown): Promise<void> {
    try {
      await this.pool.query(
        `INSERT INTO audit_logs (user_id, action, resource_affected, ip_address, metadata, created_at)
         VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP)`,
        [userId || null, action, resource, ip || null, metadata ? JSON.stringify(metadata) : null]
      );
    } catch {
      // Non-blocking error for audit log
    }
  }

  // --- PARTICIPANTS ---

  async listParticipants(): Promise<Omit<Participant, 'pin_hash'>[]> {
    const res = await this.pool.query<Participant>(
      `SELECT id, participant_code, display_alias, age_years, gender, created_by_user_id, is_active, created_at, updated_at
       FROM participants
       ORDER BY participant_code ASC`
    );
    return res.rows;
  }

  async getParticipantByCode(code: string): Promise<Omit<Participant, 'pin_hash'>> {
    const res = await this.pool.query<Participant>(
      `SELECT id, participant_code, display_alias, age_years, gender, created_by_user_id, is_active, created_at, updated_at
       FROM participants
       WHERE participant_code = $1`,
      [code.trim().toUpperCase()]
    );
    if (res.rowCount === 0) {
      throw new NotFoundError(`Participant with code '${code}' not found`);
    }
    return res.rows[0];
  }

  async createParticipant(params: {
    participantCode: string;
    displayAlias: string;
    ageYears?: number;
    gender?: string;
    pin: string;
    createdByUserId?: string;
  }): Promise<Omit<Participant, 'pin_hash'>> {
    const code = params.participantCode.trim().toUpperCase();
    const alias = params.displayAlias.trim();

    // Cek apakah code sudah ada
    const existing = await this.pool.query('SELECT id FROM participants WHERE participant_code = $1', [code]);
    if (existing.rowCount && existing.rowCount > 0) {
      throw new ValidationError(`Participant code '${code}' is already registered`);
    }

    const pinHash = await bcrypt.hash(params.pin, config.auth.bcryptSaltRounds);

    const res = await this.pool.query<Participant>(
      `INSERT INTO participants (participant_code, display_alias, age_years, gender, pin_hash, created_by_user_id, is_active, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
       RETURNING id, participant_code, display_alias, age_years, gender, created_by_user_id, is_active, created_at, updated_at`,
      [code, alias, params.ageYears ?? null, params.gender ?? 'unspecified', pinHash, params.createdByUserId || null]
    );

    return res.rows[0];
  }


  async batchImportParticipants(
    participants: Array<{
      participantCode: string;
      displayAlias: string;
      ageYears?: number;
      gender?: string;
      pin: string;
    }>,
    createdByUserId?: string
  ): Promise<{
    total: number;
    created: number;
    skipped: number;
    results: Array<{ code: string; status: 'created' | 'skipped' | 'failed'; error?: string }>;
  }> {
    const results: Array<{ code: string; status: 'created' | 'skipped' | 'failed'; error?: string }> = [];
    let createdCount = 0;
    let skippedCount = 0;

    for (const p of participants) {
      const code = p.participantCode.trim().toUpperCase();
      try {
        const existing = await this.pool.query('SELECT id FROM participants WHERE participant_code = $1', [code]);
        if (existing.rowCount && existing.rowCount > 0) {
          skippedCount++;
          results.push({ code, status: 'skipped', error: 'Participant code already exists' });
          continue;
        }

        const pinHash = await bcrypt.hash(p.pin, config.auth.bcryptSaltRounds);
        await this.pool.query(
          `INSERT INTO participants (participant_code, display_alias, age_years, gender, pin_hash, created_by_user_id, is_active, created_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, true, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)`,
          [code, p.displayAlias.trim(), p.ageYears ?? null, p.gender ?? 'unspecified', pinHash, createdByUserId || null]
        );
        createdCount++;
        results.push({ code, status: 'created' });
      } catch (err: unknown) {
        results.push({ code, status: 'failed', error: err instanceof Error ? err.message : String(err) });
      }
    }

    return {
      total: participants.length,
      created: createdCount,
      skipped: skippedCount,
      results,
    };
  }

  // --- DEVICES ---

  async listDevices(): Promise<Device[]> {
    const res = await this.pool.query<Device>('SELECT * FROM devices ORDER BY last_seen_at DESC');
    return res.rows;
  }

  async registerDevice(params: {
    deviceIdentifier: string;
    deviceLabel?: string;
    platform: 'android' | 'ios' | 'windows' | 'macos' | 'linux';
    appVersion?: string;
  }): Promise<Device> {
    const identifier = params.deviceIdentifier.trim();

    const res = await this.pool.query<Device>(
      `INSERT INTO devices (device_identifier, device_label, platform, app_version, registered_at, last_seen_at)
       VALUES ($1, $2, $3, $4, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
       ON CONFLICT (device_identifier) DO UPDATE
       SET device_label = COALESCE(EXCLUDED.device_label, devices.device_label),
           platform = EXCLUDED.platform,
           app_version = COALESCE(EXCLUDED.app_version, devices.app_version),
           last_seen_at = CURRENT_TIMESTAMP
       RETURNING *`,
      [identifier, params.deviceLabel || null, params.platform, params.appVersion || null]
    );

    return res.rows[0];
  }

  // --- SESSIONS ---

  async listSessions(limit = 50, offset = 0): Promise<ResearchSession[]> {
    const res = await this.pool.query<ResearchSession>(
      `SELECT * FROM research_sessions ORDER BY started_at DESC LIMIT $1 OFFSET $2`,
      [limit, offset]
    );
    return res.rows;
  }

  async createSession(params: {
    clientSessionUuid: string;
    participantCode: string;
    deviceIdentifier: string;
    sessionSequenceNumber: number;
    startedAt: string;
    endedAt?: string;
    notes?: string;
  }): Promise<ResearchSession> {
    // 1. Resolve participant_id
    const pRes = await this.pool.query('SELECT id FROM participants WHERE participant_code = $1', [
      params.participantCode.trim().toUpperCase(),
    ]);
    if (pRes.rowCount === 0) {
      throw new NotFoundError(`Participant '${params.participantCode}' not found`);
    }
    const participantId = pRes.rows[0].id;

    // 2. Resolve or create device
    const dRes = await this.pool.query('SELECT id FROM devices WHERE device_identifier = $1', [
      params.deviceIdentifier.trim(),
    ]);
    let deviceId: string;
    if (dRes.rowCount === 0) {
      const newDev = await this.registerDevice({
        deviceIdentifier: params.deviceIdentifier,
        platform: 'android',
      });
      deviceId = newDev.id;
    } else {
      deviceId = dRes.rows[0].id;
    }

    // 3. Upsert session idempoten
    const res = await this.pool.query<ResearchSession>(
      `INSERT INTO research_sessions (client_session_uuid, participant_id, device_id, session_sequence_number, started_at, ended_at, notes, synced_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, CURRENT_TIMESTAMP)
       ON CONFLICT (client_session_uuid) DO UPDATE
       SET ended_at = COALESCE(EXCLUDED.ended_at, research_sessions.ended_at),
           notes = COALESCE(EXCLUDED.notes, research_sessions.notes),
           synced_at = CURRENT_TIMESTAMP
       RETURNING *`,
      [
        params.clientSessionUuid,
        participantId,
        deviceId,
        params.sessionSequenceNumber,
        new Date(params.startedAt),
        params.endedAt ? new Date(params.endedAt) : null,
        params.notes || null,
      ]
    );

    return res.rows[0];
  }

  // --- SPEECH ATTEMPTS & EVALUATIONS ---

  async listAttempts(sessionId?: string, limit = 50, offset = 0): Promise<any[]> {
    let query = `
      SELECT a.*, e.normalized_target, e.normalized_recognized, e.edit_distance,
             e.similarity_score, e.similarity_percent, e.is_correct,
             e.evaluation_status, e.threshold_used, e.evaluation_method, e.feedback_text
      FROM speech_attempts a
      LEFT JOIN similarity_evaluations e ON a.id = e.attempt_id
    `;
    const values: any[] = [];

    if (sessionId) {
      query += ` WHERE a.session_id = $1`;
      values.push(sessionId);
    }

    query += ` ORDER BY a.attempted_at DESC LIMIT $${values.length + 1} OFFSET $${values.length + 2}`;
    values.push(limit, offset);

    const res = await this.pool.query(query, values);
    return res.rows;
  }

  async recordAttemptWithEvaluation(params: {
    clientAttemptUuid: string;
    clientSessionUuid: string;
    participantCode: string;
    deviceIdentifier: string;
    questionId: number;
    attemptNumber: number;
    targetText: string;
    recognizedText: string;
    asrProvider?: string;
    locale?: string;
    asrConfidence?: number;
    durationMs?: number;
    attemptedAt: string;
    evaluation: {
      normalizedTarget: string;
      normalizedRecognized: string;
      editDistance: number;
      similarityScore: number;
      similarityPercent: number;
      isCorrect: boolean;
      evaluationStatus: 'EXACT_MATCH' | 'ACCEPTED_SIMILAR' | 'INCORRECT' | 'UNRECOGNIZED';
      thresholdUsed?: number;
      evaluationMethod?: string;
      feedbackText?: string;
    };
  }): Promise<{ attempt: SpeechAttempt; evaluation: SimilarityEvaluation }> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');

      // 1. Resolve session
      const sRes = await client.query('SELECT id, participant_id, device_id FROM research_sessions WHERE client_session_uuid = $1', [
        params.clientSessionUuid,
      ]);
      if (sRes.rowCount === 0) {
        throw new NotFoundError(`Session with UUID '${params.clientSessionUuid}' must be created first`);
      }
      const session = sRes.rows[0];

      // 2. Insert speech_attempts (Idempoten)
      const attemptRes = await client.query<SpeechAttempt>(
        `INSERT INTO speech_attempts (client_attempt_uuid, session_id, participant_id, device_id, question_id, attempt_number, target_text, recognized_text, asr_provider, locale, asr_confidence, duration_ms, attempted_at, synced_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, CURRENT_TIMESTAMP)
         ON CONFLICT (client_attempt_uuid) DO NOTHING
         RETURNING *`,
        [
          params.clientAttemptUuid,
          session.id,
          session.participant_id,
          session.device_id,
          params.questionId,
          params.attemptNumber,
          params.targetText,
          params.recognizedText,
          params.asrProvider || 'whisper_onnx',
          params.locale || 'id_ID',
          params.asrConfidence ?? null,
          params.durationMs ?? null,
          new Date(params.attemptedAt),
        ]
      );

      let attempt: SpeechAttempt;
      if (attemptRes.rowCount === 0) {
        // Data sudah ada sebelumnya, ambil data yang ada
        const existing = await client.query<SpeechAttempt>(
          'SELECT * FROM speech_attempts WHERE client_attempt_uuid = $1',
          [params.clientAttemptUuid]
        );
        attempt = existing.rows[0];
      } else {
        attempt = attemptRes.rows[0];
      }

      // 3. Insert similarity_evaluations
      const evalRes = await client.query<SimilarityEvaluation>(
        `INSERT INTO similarity_evaluations (attempt_id, normalized_target, normalized_recognized, edit_distance, similarity_score, similarity_percent, is_correct, evaluation_status, threshold_used, evaluation_method, feedback_text, created_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, CURRENT_TIMESTAMP)
         ON CONFLICT (attempt_id) DO NOTHING
         RETURNING *`,
        [
          attempt.id,
          params.evaluation.normalizedTarget,
          params.evaluation.normalizedRecognized,
          params.evaluation.editDistance,
          params.evaluation.similarityScore,
          params.evaluation.similarityPercent,
          params.evaluation.isCorrect,
          params.evaluation.evaluationStatus,
          params.evaluation.thresholdUsed ?? 1.0,
          params.evaluation.evaluationMethod || 'levenshtein_normalized_v1',
          params.evaluation.feedbackText || null,
        ]
      );

      let evaluation: SimilarityEvaluation;
      if (evalRes.rowCount === 0) {
        const existing = await client.query<SimilarityEvaluation>(
          'SELECT * FROM similarity_evaluations WHERE attempt_id = $1',
          [attempt.id]
        );
        evaluation = existing.rows[0];
      } else {
        evaluation = evalRes.rows[0];
      }

      await client.query('COMMIT');
      return { attempt, evaluation };
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  // --- STATS & SUMMARY ---

  async getResearchSummary(): Promise<any> {
    const res = await this.pool.query(`
      SELECT 
        COUNT(DISTINCT p.id) as total_participants,
        COUNT(DISTINCT s.id) as total_sessions,
        COUNT(a.id) as total_attempts,
        ROUND(AVG(e.similarity_score)::numeric, 4) as avg_similarity_score,
        ROUND(AVG(e.similarity_percent)::numeric, 2) as avg_similarity_percent,
        ROUND((COUNT(CASE WHEN e.is_correct THEN 1 END)::numeric / NULLIF(COUNT(e.id), 0) * 100)::numeric, 2) as accuracy_rate_percent,
        COUNT(CASE WHEN e.evaluation_status = 'EXACT_MATCH' THEN 1 END) as exact_matches,
        COUNT(CASE WHEN e.evaluation_status = 'ACCEPTED_SIMILAR' THEN 1 END) as accepted_similar,
        COUNT(CASE WHEN e.evaluation_status = 'INCORRECT' THEN 1 END) as incorrect_attempts,
        COUNT(CASE WHEN e.evaluation_status = 'UNRECOGNIZED' THEN 1 END) as unrecognized_attempts
      FROM participants p
      LEFT JOIN research_sessions s ON p.id = s.participant_id
      LEFT JOIN speech_attempts a ON s.id = a.session_id
      LEFT JOIN similarity_evaluations e ON a.id = e.attempt_id
    `);
    return res.rows[0];
  }


  // --- BATCH SYNC PROTOCOL ---

  async syncBatch(
    payload: {
      sessions: Array<{
        clientSessionUuid: string;
        participantCode: string;
        deviceIdentifier: string;
        sessionSequenceNumber: number;
        startedAt: string;
        endedAt?: string | null;
        notes?: string | null;
      }>;
      attempts: Array<{
        clientAttemptUuid: string;
        clientSessionUuid: string;
        participantCode: string;
        deviceIdentifier: string;
        questionId: number;
        attemptNumber: number;
        targetText: string;
        recognizedText: string;
        asrProvider?: string;
        locale?: string;
        asrConfidence?: number | null;
        durationMs?: number | null;
        attemptedAt: string;
        evaluation: {
          normalizedTarget: string;
          normalizedRecognized: string;
          editDistance: number;
          similarityScore: number;
          similarityPercent: number;
          isCorrect: boolean;
          evaluationStatus: 'EXACT_MATCH' | 'ACCEPTED_SIMILAR' | 'INCORRECT' | 'UNRECOGNIZED';
          thresholdUsed?: number;
          evaluationMethod?: string;
          feedbackText?: string | null;
        };
      }>;
    },
    userId?: string,
    ip?: string
  ): Promise<{
    summary: {
      totalSessions: number;
      syncedSessions: number;
      totalAttempts: number;
      syncedAttempts: number;
      failedItems: number;
    };
    sessions: Array<{
      clientSessionUuid: string;
      status: 'created' | 'already_synced' | 'failed';
      error?: string;
    }>;
    attempts: Array<{
      clientAttemptUuid: string;
      status: 'created' | 'already_synced' | 'failed';
      error?: string;
    }>;
  }> {
    const sessionResults: Array<{ clientSessionUuid: string; status: 'created' | 'already_synced' | 'failed'; error?: string }> = [];
    const attemptResults: Array<{ clientAttemptUuid: string; status: 'created' | 'already_synced' | 'failed'; error?: string }> = [];

    // 1. Proses Sesi secara terisolasi per record agar kegagalan 1 sesi tidak membatalkan yang lain
    for (const s of payload.sessions) {
      try {
        // Cek apakah sesi sudah ada sebelumnya
        const existing = await this.pool.query('SELECT id FROM research_sessions WHERE client_session_uuid = $1', [
          s.clientSessionUuid,
        ]);

        if (existing.rowCount && existing.rowCount > 0) {
          // Idempoten: perbarui data penutupan jika ada
          if (s.endedAt || s.notes) {
            await this.pool.query(
              `UPDATE research_sessions 
               SET ended_at = COALESCE($1, ended_at),
                   notes = COALESCE($2, notes),
                   synced_at = CURRENT_TIMESTAMP
               WHERE client_session_uuid = $3`,
              [s.endedAt ? new Date(s.endedAt) : null, s.notes || null, s.clientSessionUuid]
            );
          }
          sessionResults.push({ clientSessionUuid: s.clientSessionUuid, status: 'already_synced' });
        } else {
          await this.createSession({
            clientSessionUuid: s.clientSessionUuid,
            participantCode: s.participantCode,
            deviceIdentifier: s.deviceIdentifier,
            sessionSequenceNumber: s.sessionSequenceNumber,
            startedAt: s.startedAt,
            endedAt: s.endedAt || undefined,
            notes: s.notes || undefined,
          });
          sessionResults.push({ clientSessionUuid: s.clientSessionUuid, status: 'created' });
        }
      } catch (err: any) {
        sessionResults.push({
          clientSessionUuid: s.clientSessionUuid,
          status: 'failed',
          error: err.message || 'Unknown database error',
        });
      }
    }

    // 2. Proses Percobaan (Attempts + Evaluations)
    for (const a of payload.attempts) {
      try {
        const existing = await this.pool.query('SELECT id FROM speech_attempts WHERE client_attempt_uuid = $1', [
          a.clientAttemptUuid,
        ]);

        if (existing.rowCount && existing.rowCount > 0) {
          attemptResults.push({ clientAttemptUuid: a.clientAttemptUuid, status: 'already_synced' });
        } else {
          await this.recordAttemptWithEvaluation({
            clientAttemptUuid: a.clientAttemptUuid,
            clientSessionUuid: a.clientSessionUuid,
            participantCode: a.participantCode,
            deviceIdentifier: a.deviceIdentifier,
            questionId: a.questionId,
            attemptNumber: a.attemptNumber,
            targetText: a.targetText,
            recognizedText: a.recognizedText,
            asrProvider: a.asrProvider,
            locale: a.locale,
            asrConfidence: a.asrConfidence ?? undefined,
            durationMs: a.durationMs ?? undefined,
            attemptedAt: a.attemptedAt,
            evaluation: {
              normalizedTarget: a.evaluation.normalizedTarget,
              normalizedRecognized: a.evaluation.normalizedRecognized,
              editDistance: a.evaluation.editDistance,
              similarityScore: a.evaluation.similarityScore,
              similarityPercent: a.evaluation.similarityPercent,
              isCorrect: a.evaluation.isCorrect,
              evaluationStatus: a.evaluation.evaluationStatus,
              thresholdUsed: a.evaluation.thresholdUsed,
              evaluationMethod: a.evaluation.evaluationMethod,
              feedbackText: a.evaluation.feedbackText || undefined,
            },
          });
          attemptResults.push({ clientAttemptUuid: a.clientAttemptUuid, status: 'created' });
        }
      } catch (err: any) {
        attemptResults.push({
          clientAttemptUuid: a.clientAttemptUuid,
          status: 'failed',
          error: err.message || 'Unknown database error',
        });
      }
    }

    const createdSessions = sessionResults.filter((r) => r.status === 'created' || r.status === 'already_synced').length;
    const createdAttempts = attemptResults.filter((r) => r.status === 'created' || r.status === 'already_synced').length;
    const failedCount =
      sessionResults.filter((r) => r.status === 'failed').length +
      attemptResults.filter((r) => r.status === 'failed').length;

    await this.logAudit(userId, 'BATCH_SYNC', 'research_sync', ip, {
      sessionsCount: payload.sessions.length,
      attemptsCount: payload.attempts.length,
      createdSessions,
      createdAttempts,
      failedCount,
    });

    return {
      summary: {
        totalSessions: payload.sessions.length,
        syncedSessions: createdSessions,
        totalAttempts: payload.attempts.length,
        syncedAttempts: createdAttempts,
        failedItems: failedCount,
      },
      sessions: sessionResults,
      attempts: attemptResults,
    };
  }
}