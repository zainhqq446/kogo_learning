import '../helpers/test_env.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import { z } from 'zod';
import { createApp } from '../../app.js';
import { normalizeError } from '../../middlewares/error_handler.js';
import { AppError, ConflictError } from '../../types/errors.js';
import { startServer } from '../helpers/http.js';

function pgError(code: string, message = 'duplicate key value violates unique constraint "users_username_key"') {
  return Object.assign(new Error(message), { code, severity: 'ERROR', detail: 'Key (username)=(ani) already exists.' });
}

test('error mapping: zod errors become 400 VALIDATION_ERROR with field paths', () => {
  const result = z.object({ age: z.number() }).safeParse({ age: 'x' });
  assert.equal(result.success, false);
  const n = normalizeError(!result.success ? result.error : null);
  assert.equal(n.statusCode, 400);
  assert.equal(n.code, 'VALIDATION_ERROR');
  assert.deepEqual((n.errors as Array<{ path: string }>).map((e) => e.path), ['age']);
});

test('error mapping: PostgreSQL errors map to stable codes without leaking raw messages', () => {
  const cases: Array<[string, number, string]> = [
    ['23505', 409, 'DUPLICATE_RESOURCE'],
    ['23503', 409, 'INVALID_REFERENCE'],
    ['22P02', 400, 'INVALID_INPUT'],
    ['22021', 400, 'INVALID_INPUT'],
    ['22P05', 400, 'INVALID_INPUT'],
    ['22007', 400, 'INVALID_INPUT'],
    ['22008', 400, 'INVALID_INPUT'], // datetime_field_overflow (tahun 0000)
    ['22009', 400, 'INVALID_INPUT'], // invalid_time_zone_displacement_value (+16:00)
    ['23514', 400, 'CONSTRAINT_VIOLATION'],
    ['23502', 400, 'CONSTRAINT_VIOLATION'],
    ['42P01', 500, 'INTERNAL_ERROR'],
  ];
  for (const [code, status, stable] of cases) {
    const n = normalizeError(pgError(code));
    assert.equal(n.statusCode, status, code);
    assert.equal(n.code, stable, code);
    assert.ok(!n.message.includes('users_username_key'), `raw pg message leaked for ${code}`);
  }
});

test('error mapping: body-parser 4xx errors keep their status instead of 500', () => {
  const parse = Object.assign(new SyntaxError('Unexpected token'), { status: 400, statusCode: 400, type: 'entity.parse.failed', expose: true });
  assert.deepEqual([normalizeError(parse).statusCode, normalizeError(parse).code], [400, 'INVALID_JSON']);
  const large = Object.assign(new Error('request entity too large'), { status: 413, type: 'entity.too.large', expose: true });
  assert.deepEqual([normalizeError(large).statusCode, normalizeError(large).code], [413, 'PAYLOAD_TOO_LARGE']);
  const charset = Object.assign(new Error('unsupported charset'), { status: 415, type: 'charset.unsupported' });
  assert.equal(normalizeError(charset).statusCode, 415);
});

test('error mapping: AppError keeps status/code; unknown errors are generic 500', () => {
  const conflict = normalizeError(new ConflictError('Username sudah terdaftar', 'USERNAME_TAKEN'));
  assert.deepEqual([conflict.statusCode, conflict.code, conflict.message], [409, 'USERNAME_TAKEN', 'Username sudah terdaftar']);
  const upstream = normalizeError(new AppError('Voice synthesis upstream provider error', 502, true, undefined, 'UPSTREAM_ERROR'));
  assert.deepEqual([upstream.statusCode, upstream.code], [502, 'UPSTREAM_ERROR']);
  const unknown = normalizeError(new Error('connect ECONNREFUSED 10.0.0.5:5432 password=hunter2'));
  assert.deepEqual([unknown.statusCode, unknown.code, unknown.message], [500, 'INTERNAL_ERROR', 'Internal server error']);
});

test('error handler over HTTP: malformed JSON -> 400, oversized JSON -> 413, no stack traces', async () => {
  const server = await startServer(createApp());
  try {
    const malformed = await fetch(`${server.baseUrl}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: '{"username": "ani", ',
    });
    assert.equal(malformed.status, 400);
    const malformedBody = (await malformed.json()) as Record<string, unknown>;
    assert.equal(malformedBody.code, 'INVALID_JSON');
    assert.equal(malformedBody.stack, undefined);

    const huge = await fetch(`${server.baseUrl}/api/v2/devices/register`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ padding: 'x'.repeat(1024 * 1024 + 10) }),
    });
    assert.equal(huge.status, 413);
    const hugeBody = (await huge.json()) as Record<string, unknown>;
    assert.equal(hugeBody.code, 'PAYLOAD_TOO_LARGE');

    const notFound = await fetch(`${server.baseUrl}/api/does-not-exist?token=secret`);
    assert.equal(notFound.status, 404);
    const notFoundBody = (await notFound.json()) as Record<string, string>;
    assert.equal(notFoundBody.code, 'NOT_FOUND');
    assert.ok(!notFoundBody.message.includes('secret'), 'query string must not be echoed');
  } finally {
    await server.close();
  }
});
