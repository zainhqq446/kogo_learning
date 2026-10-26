import '../helpers/test_env.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import jwt from 'jsonwebtoken';
import { createApp } from '../../app.js';
import {
  generateUserTokens,
  signAccessToken,
  signDeviceToken,
  verifyAccessToken,
  verifyDeviceToken,
  verifyUserOrDeviceToken,
} from '../../services/token_service.js';
import { UnauthorizedError } from '../../types/errors.js';
import { TEST_JWT_SECRET } from '../helpers/test_env.js';
import {
  bearer,
  deviceToken,
  getJson,
  postJson,
  rawToken,
  startServer,
  TEST_USER_IDS,
  testPrincipals,
  TestServer,
  userToken,
} from '../helpers/http.js';

const USER = { userId: '11111111-2222-4333-8444-555555555555', username: 'peneliti', role: 'researcher' as const };

test('tokens: access tokens are HS256 and carry tokenType=access', () => {
  const { accessToken, refreshToken } = generateUserTokens(USER);
  const header = JSON.parse(Buffer.from(accessToken.split('.')[0], 'base64url').toString());
  assert.equal(header.alg, 'HS256');
  const payload = verifyAccessToken(accessToken);
  assert.deepEqual(payload, { ...USER, tokenType: 'access' });
  assert.ok(refreshToken);
});

test('tokens: refresh tokens are never accepted as access tokens', () => {
  const { refreshToken } = generateUserTokens(USER);
  assert.throws(() => verifyAccessToken(refreshToken), (err: unknown) => err instanceof UnauthorizedError && err.code === 'INVALID_TOKEN');
  assert.throws(() => verifyUserOrDeviceToken(refreshToken), UnauthorizedError);
  assert.throws(() => verifyDeviceToken(refreshToken), UnauthorizedError);
});

test('tokens: device tokens and user tokens are not interchangeable', () => {
  const { token, expiresIn } = signDeviceToken('aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee');
  assert.equal(expiresIn, 180 * 86400);
  const decoded = jwt.decode(token) as jwt.JwtPayload;
  // `sub` adalah id internal, bukan deviceUuid (kredensial perangkat tidak boleh ada di payload JWT).
  assert.equal(decoded.sub, 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee');
  assert.equal(decoded.deviceId, 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee');
  assert.equal(decoded.role, 'device');
  assert.equal(decoded.tokenType, 'device');
  assert.equal(decoded.exp! - decoded.iat!, 180 * 86400);
  assert.deepEqual(Object.keys(decoded).sort(), ['deviceId', 'exp', 'iat', 'role', 'sub', 'tokenType']);

  assert.deepEqual(verifyDeviceToken(token), { deviceId: 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee' });
  assert.throws(() => verifyAccessToken(token), UnauthorizedError);
  assert.throws(() => verifyDeviceToken(generateUserTokens(USER).accessToken), UnauthorizedError);
  assert.equal(verifyUserOrDeviceToken(token).kind, 'device');
  assert.equal(verifyUserOrDeviceToken(generateUserTokens(USER).accessToken).kind, 'user');
});

test('tokens: algorithm is pinned (HS512, alg=none and wrong secret are rejected)', () => {
  const hs512 = jwt.sign({ ...USER, tokenType: 'access' }, TEST_JWT_SECRET, { algorithm: 'HS512' });
  assert.throws(() => verifyAccessToken(hs512), UnauthorizedError);

  const unsigned = `${Buffer.from(JSON.stringify({ alg: 'none', typ: 'JWT' })).toString('base64url')}.${Buffer.from(
    JSON.stringify({ ...USER, tokenType: 'access' })
  ).toString('base64url')}.`;
  assert.throws(() => verifyAccessToken(unsigned), UnauthorizedError);

  const wrongSecret = jwt.sign({ ...USER, tokenType: 'access' }, 'another-secret-that-is-long-enough-123456', { algorithm: 'HS256' });
  assert.throws(() => verifyAccessToken(wrongSecret), UnauthorizedError);

  const legacyNoType = rawToken({ userId: USER.userId, username: USER.username, role: 'researcher' });
  assert.throws(() => verifyAccessToken(legacyNoType), UnauthorizedError);

  const expired = rawToken({ ...USER, tokenType: 'access' }, { algorithm: 'HS256', expiresIn: -10 });
  assert.throws(() => verifyAccessToken(expired), (err: unknown) => err instanceof UnauthorizedError && err.code === 'TOKEN_EXPIRED');
});

test('auth middleware over HTTP enforces token types and roles', async (t) => {
  let server: TestServer | undefined;
  t.after(() => server?.close());
  const disabledResearcher = '00000000-0000-4000-8000-0000000000b1';
  const demotedResearcher = '00000000-0000-4000-8000-0000000000b2';
  server = await startServer(
    createApp({
      principals: testPrincipals({
        users: {
          [disabledResearcher]: { role: 'researcher', isActive: false },
          [demotedResearcher]: { role: 'child', isActive: true },
        },
      }),
    })
  );
  const base = server.baseUrl;
  const { refreshToken } = generateUserTokens(USER);

  await t.test('GET /api/auth/me rejects refresh and device tokens with 401', async () => {
    const noToken = await getJson(base, '/api/auth/me');
    assert.equal(noToken.status, 401);
    const refresh = await getJson(base, '/api/auth/me', bearer(refreshToken));
    assert.equal(refresh.status, 401);
    assert.equal(refresh.body.code, 'INVALID_TOKEN');
    const device = await getJson(base, '/api/auth/me', bearer(deviceToken()));
    assert.equal(device.status, 401);
  });

  await t.test('POST /api/v2/sync requires a device token', async () => {
    assert.equal((await postJson(base, '/api/v2/sync', {})).status, 401);
    assert.equal((await postJson(base, '/api/v2/sync', {}, bearer(userToken('admin')))).status, 401);
    assert.equal((await postJson(base, '/api/v2/sync', {}, bearer(refreshToken))).status, 401);
  });

  await t.test('research endpoints require admin/researcher (401 without, 403 for other roles)', async () => {
    for (const path of ['/api/v2/research/metrics', '/api/v2/research/export/attempts.csv', '/api/v2/research/export/sessions.csv']) {
      assert.equal((await getJson(base, path)).status, 401, path);
      assert.equal((await getJson(base, path, bearer(deviceToken()))).status, 401, `${path} device`);
      assert.equal((await getJson(base, path, bearer(refreshToken))).status, 401, `${path} refresh`);
      assert.equal((await getJson(base, path, bearer(userToken('teacher')))).status, 403, `${path} teacher`);
      assert.equal((await getJson(base, path, bearer(userToken('child')))).status, 403, `${path} child`);
    }
  });

  await t.test('legacy /api/research routes keep their auth', async () => {
    assert.equal((await getJson(base, '/api/research/participants')).status, 401);
    assert.equal((await getJson(base, '/api/research/devices', bearer(userToken('teacher')))).status, 403);
    assert.equal((await getJson(base, '/api/research/summary', bearer(deviceToken()))).status, 401);
    assert.equal((await postJson(base, '/api/research/sync/batch', {}, bearer(userToken('child')))).status, 403);
  });

  await t.test('there is no public registration (no account or participant enumeration)', async () => {
    for (const role of [undefined, 'child', 'teacher', 'researcher', 'admin']) {
      const res = await postJson(base, '/api/auth/register', {
        username: `user_${role ?? 'none'}`,
        password: 'password123',
        fullName: 'Some Person',
        ...(role ? { role } : {}),
      });
      assert.equal(res.status, 401, String(role));
    }
    const child = await postJson(base, '/api/auth/register/child', {
      username: 'anak_baru',
      password: 'password123',
      fullName: 'Anak Baru',
      ageYears: 5,
      schoolName: 'TK Pelita',
    });
    assert.equal(child.status, 401);
    // Akun anak tidak boleh membuat akun apa pun.
    const byChild = await postJson(
      base,
      '/api/auth/register/child',
      { username: 'anak_lain', password: 'password123', fullName: 'Anak Lain', ageYears: 5, schoolName: 'TK Pelita' },
      bearer(userToken('child'))
    );
    assert.equal(byChild.status, 403);
    // Researcher tidak boleh membuat akun staf.
    const nonAdmin = await postJson(
      base,
      '/api/auth/register',
      { username: 'staff_x', password: 'password123', fullName: 'Staff Person', role: 'teacher' },
      bearer(userToken('researcher'))
    );
    assert.equal(nonAdmin.status, 403);
    assert.equal(nonAdmin.body.code, 'FORBIDDEN');
  });

  await t.test('account status is checked live: disabled -> 401, demoted -> 403', async () => {
    const disabled = signAccessToken({ userId: disabledResearcher, username: 'peneliti_x', role: 'researcher' });
    const res = await getJson(base, '/api/v2/research/metrics', bearer(disabled));
    assert.equal(res.status, 401);
    assert.equal(res.body.code, 'ACCOUNT_DISABLED');

    const demoted = signAccessToken({ userId: demotedResearcher, username: 'peneliti_y', role: 'researcher' });
    assert.equal((await getJson(base, '/api/v2/research/export/attempts.csv', bearer(demoted))).status, 403);
    assert.equal((await getJson(base, '/api/research/summary', bearer(demoted))).status, 403);

    const unknownUser = signAccessToken({ userId: '00000000-0000-4000-8000-0000000000ff', username: 'ghost', role: 'admin' });
    assert.equal((await getJson(base, '/api/auth/me', bearer(unknownUser))).status, 401);
    assert.equal(TEST_USER_IDS.admin.length, 36);
  });
});
