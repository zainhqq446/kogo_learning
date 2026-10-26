import { Request, Response, NextFunction } from 'express';
import { ZodType, ZodError } from 'zod';
import { ValidationError } from '../types/errors.js';
import { formatZodIssues } from './error_handler.js';

export function validateBody<T>(schema: ZodType<T>) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    try {
      req.body = schema.parse(req.body ?? {});
      next();
    } catch (error) {
      if (error instanceof ZodError) {
        next(new ValidationError('Validation failed for request body', formatZodIssues(error)));
      } else {
        next(error);
      }
    }
  };
}

/**
 * Validasi query string. Hasil parse disimpan di `res.locals.query` (bukan
 * menimpa `req.query`) agar tipe tetap jelas di controller.
 */
export function validateQuery<T>(schema: ZodType<T>) {
  return (req: Request, res: Response, next: NextFunction): void => {
    try {
      res.locals.query = schema.parse(req.query);
      next();
    } catch (error) {
      if (error instanceof ZodError) {
        next(new ValidationError('Validation failed for query parameters', formatZodIssues(error)));
      } else {
        next(error);
      }
    }
  };
}
