import { Request, Response, NextFunction } from 'express';
import { ZodError } from 'zod';
import { AppError, ErrorCode } from '../types/errors.js';
import { logger } from '../utils/logger.js';
import { config } from '../config/env.js';

export interface ErrorResponseBody {
  status: 'error';
  statusCode: number;
  code: ErrorCode;
  message: string;
  errors?: unknown;
  stack?: string;
}

interface NormalizedError {
  statusCode: number;
  code: ErrorCode;
  message: string;
  errors?: unknown;
  /** true = error tak terduga (500) yang perlu dicatat lengkap. */
  unexpected: boolean;
}

/** Format issue Zod menjadi daftar { path, message } yang ringkas. */
export function formatZodIssues(error: ZodError): Array<{ path: string; message: string }> {
  return error.issues.map((issue) => ({
    path: issue.path.map(String).join('.'),
    message: issue.message,
  }));
}

/** Error dari body-parser / raw-body membawa `type` dan `status`/`statusCode` 4xx. */
function asHttpClientError(err: unknown): { status: number; type?: string } | null {
  if (typeof err !== 'object' || err === null) return null;
  const candidate = err as { status?: unknown; statusCode?: unknown; type?: unknown; expose?: unknown };
  const status = typeof candidate.status === 'number' ? candidate.status : candidate.statusCode;
  if (typeof status !== 'number' || status < 400 || status >= 500) return null;
  return { status, type: typeof candidate.type === 'string' ? candidate.type : undefined };
}

/** Error PostgreSQL membawa SQLSTATE 5 karakter pada field `code`. */
function asPgError(err: unknown): { code: string } | null {
  if (typeof err !== 'object' || err === null) return null;
  const candidate = err as { code?: unknown; severity?: unknown; routine?: unknown };
  if (typeof candidate.code === 'string' && /^[0-9A-Z]{5}$/.test(candidate.code) && 'severity' in candidate) {
    return { code: candidate.code };
  }
  return null;
}

/**
 * Memetakan error apa pun ke respons yang aman. Pesan mentah PostgreSQL,
 * stack trace, dan detail internal tidak pernah dikirim ke klien.
 */
export function normalizeError(err: unknown): NormalizedError {
  if (err instanceof ZodError) {
    return {
      statusCode: 400,
      code: 'VALIDATION_ERROR',
      message: 'Validation failed',
      errors: formatZodIssues(err),
      unexpected: false,
    };
  }

  if (err instanceof AppError) {
    return {
      statusCode: err.statusCode,
      code: err.code,
      message: err.statusCode >= 500 && !err.isOperational ? 'Internal server error' : err.message,
      errors: err.errors,
      unexpected: !err.isOperational,
    };
  }

  const pgError = asPgError(err);
  if (pgError) {
    switch (pgError.code) {
      case '23505':
        return { statusCode: 409, code: 'DUPLICATE_RESOURCE', message: 'Resource already exists', unexpected: false };
      case '23503':
        return {
          statusCode: 409,
          code: 'INVALID_REFERENCE',
          message: 'Referenced resource does not exist or is still in use',
          unexpected: false,
        };
      case '22P02':
      case '22021': // character_not_in_repertoire (mis. NUL / UTF-8 tidak valid)
      case '22P05': // untranslatable_character
      case '22007': // invalid_datetime_format
      case '22008': // datetime_field_overflow (mis. tahun 0000)
      case '22009': // invalid_time_zone_displacement_value (offset di luar +/-15:59)
      case '22003':
      case '22001':
        return { statusCode: 400, code: 'INVALID_INPUT', message: 'Invalid input value', unexpected: false };
      case '23514':
      case '23502':
        return {
          statusCode: 400,
          code: 'CONSTRAINT_VIOLATION',
          message: 'Data violates a validation constraint',
          unexpected: false,
        };
      default:
        return { statusCode: 500, code: 'INTERNAL_ERROR', message: 'Internal server error', unexpected: true };
    }
  }

  const httpError = asHttpClientError(err);
  if (httpError) {
    switch (httpError.type) {
      case 'entity.parse.failed':
        return { statusCode: 400, code: 'INVALID_JSON', message: 'Malformed JSON request body', unexpected: false };
      case 'entity.too.large':
        return { statusCode: 413, code: 'PAYLOAD_TOO_LARGE', message: 'Request body is too large', unexpected: false };
      case 'encoding.unsupported':
      case 'charset.unsupported':
        return {
          statusCode: 415,
          code: 'UNSUPPORTED_MEDIA_TYPE',
          message: 'Unsupported request body encoding',
          unexpected: false,
        };
      default:
        return {
          statusCode: httpError.status,
          code: httpError.status === 413 ? 'PAYLOAD_TOO_LARGE' : 'BAD_REQUEST',
          message: httpError.status === 413 ? 'Request body is too large' : 'Bad request',
          unexpected: false,
        };
    }
  }

  return { statusCode: 500, code: 'INTERNAL_ERROR', message: 'Internal server error', unexpected: true };
}

export function errorHandler(err: unknown, req: Request, res: Response, _next: NextFunction): void {
  const normalized = normalizeError(err);
  const rawMessage = err instanceof Error ? err.message : String(err);

  if (normalized.unexpected) {
    logger.error(`[${req.method}] ${req.path} - Status: ${normalized.statusCode} - ${rawMessage}`);
    if (err instanceof Error && err.stack) logger.debug(err.stack);
  } else {
    const detail = err instanceof ZodError ? `${err.issues.length} validation issue(s)` : rawMessage;
    logger.warn(`[${req.method}] ${req.path} - Status: ${normalized.statusCode} - ${normalized.code} - ${detail}`);
  }

  if (res.headersSent) {
    res.end();
    return;
  }

  const body: ErrorResponseBody = {
    status: 'error',
    statusCode: normalized.statusCode,
    code: normalized.code,
    message: normalized.message,
  };
  if (normalized.errors !== undefined) body.errors = normalized.errors;

  // Stack trace hanya pada NODE_ENV=development yang diset eksplisit.
  if (config.server.nodeEnv === 'development' && normalized.unexpected && err instanceof Error) {
    body.stack = err.stack;
  }

  res.status(normalized.statusCode).json(body);
}

export function notFoundHandler(req: Request, res: Response): void {
  res.status(404).json({
    status: 'error',
    statusCode: 404,
    code: 'NOT_FOUND',
    message: `Endpoint ${req.method} ${req.path} not found`,
  });
}
