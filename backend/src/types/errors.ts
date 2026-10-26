/**
 * Kode error stabil yang dikirim ke klien di field `code`. Klien (aplikasi
 * Flutter / dashboard peneliti) sebaiknya bercabang berdasarkan kode ini,
 * bukan berdasarkan teks `message`.
 */
export type ErrorCode =
  | 'BAD_REQUEST'
  | 'VALIDATION_ERROR'
  | 'INVALID_JSON'
  | 'INVALID_INPUT'
  | 'CONSTRAINT_VIOLATION'
  | 'UNAUTHORIZED'
  | 'INVALID_TOKEN'
  | 'TOKEN_EXPIRED'
  | 'INVALID_CREDENTIALS'
  | 'DEVICE_NOT_REGISTERED'
  | 'DEVICE_NOT_APPROVED'
  | 'DEVICE_REVOKED'
  | 'DEVICE_PROOF_REQUIRED'
  | 'ENROLLMENT_REQUIRED'
  | 'ACCOUNT_DISABLED'
  | 'FORBIDDEN'
  | 'NOT_FOUND'
  | 'CONFLICT'
  | 'DUPLICATE_RESOURCE'
  | 'INVALID_REFERENCE'
  | 'USERNAME_TAKEN'
  | 'PARTICIPANT_EXISTS'
  | 'PAYLOAD_TOO_LARGE'
  | 'UNSUPPORTED_MEDIA_TYPE'
  | 'VOICE_NOT_ALLOWED'
  | 'MODEL_NOT_ALLOWED'
  | 'RATE_LIMITED'
  | 'INTERNAL_ERROR'
  | 'NOT_CONFIGURED'
  | 'SERVICE_UNAVAILABLE'
  | 'UPSTREAM_ERROR'
  | 'UPSTREAM_TIMEOUT'
  | 'UPSTREAM_RATE_LIMITED'
  | 'VOICE_BUDGET_EXHAUSTED';

function defaultCodeForStatus(statusCode: number): ErrorCode {
  switch (statusCode) {
    case 400:
      return 'BAD_REQUEST';
    case 401:
      return 'UNAUTHORIZED';
    case 403:
      return 'FORBIDDEN';
    case 404:
      return 'NOT_FOUND';
    case 409:
      return 'CONFLICT';
    case 413:
      return 'PAYLOAD_TOO_LARGE';
    case 415:
      return 'UNSUPPORTED_MEDIA_TYPE';
    case 429:
      return 'RATE_LIMITED';
    case 502:
      return 'UPSTREAM_ERROR';
    case 503:
      return 'SERVICE_UNAVAILABLE';
    case 504:
      return 'UPSTREAM_TIMEOUT';
    default:
      return statusCode >= 500 ? 'INTERNAL_ERROR' : 'BAD_REQUEST';
  }
}

export class AppError extends Error {
  public readonly statusCode: number;
  public readonly isOperational: boolean;
  public readonly errors?: unknown;
  public readonly code: ErrorCode;

  constructor(message: string, statusCode = 500, isOperational = true, errors?: unknown, code?: ErrorCode) {
    super(message);
    this.statusCode = statusCode;
    this.isOperational = isOperational;
    this.errors = errors;
    this.code = code ?? defaultCodeForStatus(statusCode);
    Object.setPrototypeOf(this, new.target.prototype);
    Error.captureStackTrace(this, this.constructor);
  }
}

export class NotFoundError extends AppError {
  constructor(message = 'Resource not found') {
    super(message, 404, true, undefined, 'NOT_FOUND');
  }
}

export class ValidationError extends AppError {
  constructor(message = 'Invalid request payload', errors?: unknown) {
    super(message, 400, true, errors, 'VALIDATION_ERROR');
  }
}

export class UnauthorizedError extends AppError {
  constructor(message = 'Authentication required', code: ErrorCode = 'UNAUTHORIZED') {
    super(message, 401, true, undefined, code);
  }
}

export class ForbiddenError extends AppError {
  constructor(message = 'Permission denied', code: ErrorCode = 'FORBIDDEN') {
    super(message, 403, true, undefined, code);
  }
}

export class ConflictError extends AppError {
  constructor(message = 'Resource already exists', code: ErrorCode = 'CONFLICT') {
    super(message, 409, true, undefined, code);
  }
}

export class ServiceUnavailableError extends AppError {
  constructor(message = 'Service unavailable', code: ErrorCode = 'SERVICE_UNAVAILABLE') {
    super(message, 503, true, undefined, code);
  }
}
