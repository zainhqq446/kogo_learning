import { Request, Response, NextFunction } from 'express';
import { getDbPool } from '../config/database.js';
import { DeviceService } from '../services/device_service.js';
import { SyncService } from '../services/sync_service.js';
import { CsvChunk, MetricsService } from '../services/metrics_service.js';
import { verifyDeviceToken } from '../services/token_service.js';
import {
  deviceApproveSchema,
  deviceIdParamSchema,
  deviceRegisterSchema,
  ResearchQuery,
  syncRequestSchema,
} from '../types/schemas.js';

function csvFilename(kind: string): string {
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+$/, '').replace('T', '-');
  return `kogo-${kind}-${stamp}.csv`;
}

/** deviceId dari device token valid di header Authorization (opsional, bukti kepemilikan). */
function optionalDeviceTokenId(req: Request): string | undefined {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) return undefined;
  try {
    return verifyDeviceToken(header.substring(7).trim()).deviceId;
  } catch {
    return undefined;
  }
}

/** Menulis potongan ke respons dengan menghormati backpressure; gagal bila klien terputus. */
function writeChunk(res: Response, chunk: string): Promise<void> {
  if (res.destroyed) return Promise.reject(new Error('Client disconnected'));
  if (res.write(chunk)) return Promise.resolve();
  return new Promise((resolve, reject) => {
    const cleanup = () => {
      res.off('drain', onDrain);
      res.off('close', onClose);
    };
    const onDrain = () => {
      cleanup();
      resolve();
    };
    const onClose = () => {
      cleanup();
      reject(new Error('Client disconnected'));
    };
    res.on('drain', onDrain);
    res.on('close', onClose);
  });
}

/**
 * API v2 untuk aplikasi Android offline-first dan dasbor peneliti.
 */
export class V2Controller {
  registerDevice = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const data = deviceRegisterSchema.parse(req.body ?? {});
      const enrollmentHeader = req.headers['x-enrollment-key'];
      const result = await new DeviceService(getDbPool()).register(data, {
        enrollmentKey: typeof enrollmentHeader === 'string' ? enrollmentHeader : undefined,
        tokenDeviceId: optionalDeviceTokenId(req),
      });

      res.status(result.created ? 201 : 200).json({
        status: 'success',
        data: {
          deviceToken: result.deviceToken,
          expiresIn: result.expiresIn,
          ...(result.deviceSecret ? { deviceSecret: result.deviceSecret } : {}),
          approved: result.approved,
        },
      });
    } catch (err) {
      next(err);
    }
  };

  sync = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const payload = syncRequestSchema.parse(req.body ?? {});
      const result = await new SyncService(getDbPool()).sync(req.device!.deviceId, payload);

      res.status(200).json({
        status: 'success',
        data: result,
      });
    } catch (err) {
      next(err);
    }
  };

  metrics = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const query = res.locals.query as ResearchQuery;
      const service = new MetricsService(getDbPool());
      const report = await service.getMetrics(query);
      await service.logAudit(req.user?.userId, 'VIEW_RESEARCH_METRICS', 'v2/research/metrics', req.ip, query);

      res.status(200).json({
        status: 'success',
        data: report,
      });
    } catch (err) {
      next(err);
    }
  };

  exportAttempts = (req: Request, res: Response, next: NextFunction): Promise<void> =>
    this.streamCsv(req, res, next, 'attempts', 'EXPORT_ATTEMPTS_CSV', (service, query) => service.exportAttemptsCsv(query));

  exportSessions = (req: Request, res: Response, next: NextFunction): Promise<void> =>
    this.streamCsv(req, res, next, 'sessions', 'EXPORT_SESSIONS_CSV', (service, query) => service.exportSessionsCsv(query));

  // --------------------------------------------------------------------------
  // Manajemen perangkat (peneliti)
  // --------------------------------------------------------------------------

  listDevices = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const devices = await new DeviceService(getDbPool()).list();
      await new MetricsService(getDbPool()).logAudit(req.user?.userId, 'LIST_DEVICES', 'v2/research/devices', req.ip);
      res.status(200).json({ status: 'success', count: devices.length, data: devices });
    } catch (err) {
      next(err);
    }
  };

  approveDevice = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const { deviceId } = deviceIdParamSchema.parse(req.params);
      const { label } = deviceApproveSchema.parse(req.body ?? {});
      const status = await new DeviceService(getDbPool()).approve(deviceId, req.user?.userId, label);
      await new MetricsService(getDbPool()).logAudit(req.user?.userId, 'APPROVE_DEVICE', `device:${deviceId}`, req.ip, { label });
      res.status(200).json({ status: 'success', data: { deviceId, status } });
    } catch (err) {
      next(err);
    }
  };

  revokeDevice = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const { deviceId } = deviceIdParamSchema.parse(req.params);
      const status = await new DeviceService(getDbPool()).revoke(deviceId);
      await new MetricsService(getDbPool()).logAudit(req.user?.userId, 'REVOKE_DEVICE', `device:${deviceId}`, req.ip);
      res.status(200).json({ status: 'success', data: { deviceId, status } });
    } catch (err) {
      next(err);
    }
  };

  resetDeviceCredential = async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    try {
      const { deviceId } = deviceIdParamSchema.parse(req.params);
      await new DeviceService(getDbPool()).resetCredential(deviceId);
      await new MetricsService(getDbPool()).logAudit(req.user?.userId, 'RESET_DEVICE_CREDENTIAL', `device:${deviceId}`, req.ip);
      res.status(200).json({
        status: 'success',
        data: { deviceId, message: 'The next registration with this deviceUuid receives a new deviceSecret.' },
      });
    } catch (err) {
      next(err);
    }
  };

  /**
   * Mengalirkan CSV per batch. Error sebelum data pertama terkirim menjadi
   * respons JSON biasa; error setelahnya memutus koneksi (CSV tidak lengkap
   * tidak boleh terlihat seperti file utuh). Setiap akses dicatat di audit_logs.
   */
  private async streamCsv(
    req: Request,
    res: Response,
    next: NextFunction,
    kind: 'attempts' | 'sessions',
    action: string,
    produce: (service: MetricsService, query: ResearchQuery) => AsyncGenerator<CsvChunk>
  ): Promise<void> {
    const query = res.locals.query as ResearchQuery;
    const service = new MetricsService(getDbPool());
    const chunks = produce(service, query);
    let rows = 0;
    let completed = false;
    try {
      const first = await chunks.next();
      res.setHeader('Content-Type', 'text/csv; charset=utf-8');
      res.setHeader('Content-Disposition', `attachment; filename="${csvFilename(kind)}"`);
      res.setHeader('Cache-Control', 'no-store');
      res.status(200);
      if (!first.done) {
        rows += first.value.rows;
        await writeChunk(res, first.value.chunk);
        for await (const { chunk, rows: n } of chunks) {
          rows += n;
          await writeChunk(res, chunk);
        }
      }
      res.end();
      completed = true;
    } catch (err) {
      await chunks.return(undefined).catch(() => undefined);
      if (!res.headersSent) next(err);
      else res.destroy(err instanceof Error ? err : undefined);
    } finally {
      await service.logAudit(req.user?.userId, action, `v2/research/export/${kind}.csv`, req.ip, { ...query, rows, completed });
    }
  }
}
