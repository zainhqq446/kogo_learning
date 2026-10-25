import { Request, Response, NextFunction } from 'express';
import { ZodError } from 'zod';
import { AppError } from '../types/errors.js';
import { logger } from '../utils/logger.js';
import { config } from '../config/env.js';

export function errorHandler(
  err: Error | AppError | ZodError,
  req: Request,
  res: Response,
  _next: NextFunction
): void {
  // 1. Tangani Zod Validation Error secara terpusat
  if (err instanceof ZodError) {
    const formatted = err.errors.map((e) => ({
      path: e.path.join('.'),
      message: e.message,
    }));
    logger.warn(`[${req.method}] ${req.originalUrl} - Status: 400 - Validation failed`);
    res.status(400).json({
      status: 'error',
      statusCode: 400,
      message: 'Validation failed',
      errors: formatted,
    });
    return;
  }

  // 2. Tangani custom AppError (ValidationError, UnauthorizedError, NotFoundError, dll.)
  const isAppError = err instanceof AppError;
  const statusCode = isAppError ? err.statusCode : 500;
  const message = isAppError ? err.message : 'Internal server error';

  // Log error dengan sanitasi
  logger.error(`[${req.method}] ${req.originalUrl} - Status: ${statusCode} - ${err.message}`);
  if (!isAppError && err.stack) {
    logger.debug(err.stack);
  }

  const responseBody: Record<string, unknown> = {
    status: 'error',
    statusCode,
    message,
  };

  if (isAppError && err.errors) {
    responseBody.errors = err.errors;
  }

  if (config.server.nodeEnv === 'development' && !isAppError) {
    responseBody.stack = err.stack;
  }

  res.status(statusCode).json(responseBody);
}

export function notFoundHandler(req: Request, res: Response): void {
  res.status(404).json({
    status: 'error',
    statusCode: 404,
    message: `Endpoint ${req.method} ${req.originalUrl} not found`,
  });
}