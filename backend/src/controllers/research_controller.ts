import { Request, Response, NextFunction } from 'express';
import { ResearchService } from '../services/research_service.js';
import { logger } from '../utils/logger.js';
import { getDbPool } from '../config/database.js';
import {
  createParticipantSchema,
  registerDeviceSchema,
  createSessionSchema,
  createAttemptSchema,
  batchParticipantSchema,
  syncBatchSchema,
  paginationQuerySchema,
  listAttemptsQuerySchema,
} from '../types/schemas.js';

export class ResearchController {
  private getService(): ResearchService {
    return new ResearchService(getDbPool());
  }

  // --- PARTICIPANTS ---

  listParticipants = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const service = this.getService();
      const participants = await service.listParticipants();
      await service.logAudit(req.user?.userId, 'LIST_PARTICIPANTS', 'participants', req.ip);

      res.status(200).json({
        status: 'success',
        count: participants.length,
        data: participants,
      });
    } catch (err) {
      next(err);
    }
  };

  createParticipant = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const data = createParticipantSchema.parse(req.body);
      const service = this.getService();
      const participant = await service.createParticipant({
        participantCode: data.participantCode,
        displayAlias: data.displayAlias,
        ageYears: data.ageYears,
        gender: data.gender,
        pin: data.pin,
        createdByUserId: req.user?.userId,
      });

      await service.logAudit(
        req.user?.userId,
        'CREATE_PARTICIPANT',
        `participant:${participant.participant_code}`,
        req.ip
      );

      res.status(201).json({
        status: 'success',
        message: 'Participant created successfully',
        data: participant,
      });
    } catch (err) {
      next(err);
    }
  };

  getParticipant = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const code = req.params.code;
      const service = this.getService();
      const participant = await service.getParticipantByCode(code);

      res.status(200).json({
        status: 'success',
        data: participant,
      });
    } catch (err) {
      next(err);
    }
  };


  batchImportParticipants = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const data = batchParticipantSchema.parse(req.body);
      const service = this.getService();
      const result = await service.batchImportParticipants(data.participants, req.user?.userId);

      await service.logAudit(
        req.user?.userId,
        'BATCH_IMPORT_PARTICIPANTS',
        `total:${result.total},created:${result.created},skipped:${result.skipped}`,
        req.ip
      );

      res.status(200).json({
        status: 'success',
        message: 'Batch participant import processed',
        data: result,
      });
    } catch (err) {
      next(err);
    }
  };

  // --- DEVICES ---

  listDevices = async (_req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const service = this.getService();
      const devices = await service.listDevices();
      res.status(200).json({
        status: 'success',
        count: devices.length,
        data: devices,
      });
    } catch (err) {
      next(err);
    }
  };

  registerDevice = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const data = registerDeviceSchema.parse(req.body);
      const service = this.getService();
      const device = await service.registerDevice(data);

      res.status(200).json({
        status: 'success',
        message: 'Device registered or updated successfully',
        data: device,
      });
    } catch (err) {
      next(err);
    }
  };

  // --- SESSIONS ---

  listSessions = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const { limit, offset } = paginationQuerySchema.parse(req.query);
      const service = this.getService();
      const sessions = await service.listSessions(limit, offset);

      res.status(200).json({
        status: 'success',
        count: sessions.length,
        data: sessions,
      });
    } catch (err) {
      next(err);
    }
  };

  createSession = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const data = createSessionSchema.parse(req.body);
      const service = this.getService();
      const session = await service.createSession(data);

      res.status(201).json({
        status: 'success',
        message: 'Research session recorded successfully',
        data: session,
      });
    } catch (err) {
      next(err);
    }
  };

  // --- ATTEMPTS & EVALUATIONS ---

  listAttempts = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const { sessionId, limit, offset } = listAttemptsQuerySchema.parse(req.query);
      const service = this.getService();
      const attempts = await service.listAttempts(sessionId, limit, offset);

      res.status(200).json({
        status: 'success',
        count: attempts.length,
        data: attempts,
      });
    } catch (err) {
      next(err);
    }
  };

  recordAttempt = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const data = createAttemptSchema.parse(req.body);
      const service = this.getService();
      const result = await service.recordAttemptWithEvaluation(data);

      res.status(201).json({
        status: 'success',
        message: 'Speech attempt and similarity evaluation recorded successfully',
        data: result,
      });
    } catch (err) {
      next(err);
    }
  };

  // --- SUMMARY ---

  getSummary = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const service = this.getService();
      const summary = await service.getResearchSummary();
      await service.logAudit(req.user?.userId, 'VIEW_RESEARCH_SUMMARY', 'summary', req.ip);

      res.status(200).json({
        status: 'success',
        data: summary,
      });
    } catch (err) {
      next(err);
    }
  };


  syncBatch = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    const startTime = Date.now();
    try {
      const data = syncBatchSchema.parse(req.body);
      const service = this.getService();

      logger.info(
        `[ResearchSync] Inbound batch request from user ${req.user?.userId || 'anonymous'} (IP: ${req.ip}) - ${data.sessions.length} sessions, ${data.attempts.length} attempts`
      );

      const result = await service.syncBatch(data, req.user?.userId, req.ip);
      const durationMs = Date.now() - startTime;

      logger.info(
        `[ResearchSync] Batch processed in ${durationMs}ms - Synced Sessions: ${result.summary.syncedSessions}/${result.summary.totalSessions}, Synced Attempts: ${result.summary.syncedAttempts}/${result.summary.totalAttempts}, Failed: ${result.summary.failedItems}`
      );

      res.status(200).json({
        status: 'success',
        message: 'Batch synchronization completed',
        data: result,
      });
    } catch (err: unknown) {
      const durationMs = Date.now() - startTime;
      logger.error(`[ResearchSync] Batch sync failed in ${durationMs}ms: ${err instanceof Error ? err.message : String(err)}`);
      next(err);
    }
  };
}