import '../helpers/test_env.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import { createApp } from '../../app.js';
import { setDbPool } from '../../config/database.js';
import { ensureAdminUser } from '../../services/auth_service.js';
import { createTestPool, prepareTestDatabase } from '../helpers/db.js';
import { bearer, getJson, noRateLimits, postJson, startServer, TestServer } from '../helpers/http.js';

const INVALID_CREDENTIALS = 'Username atau kata sandi tidak cocok.';

test('auth integration: admin bootstrap, login hardening, staff-only registration', async (t) => {
  const pool = await createTestPool();
  await prepareTestDatabase(pool);
  setDbPool(pool);
  let server: TestServer | undefined;
  t.after(async () => {
    await server?.close();
    await pool.end();
  });
  server = await startServer(createApp({ rateLimiters: noRateLimits() }));
  const base = server.baseUrl;
  let adminAccess = '';
  let adminRefresh = '';
  let researcherAccess = '';

  await t.test('admin bootstrap account can log in and reach researcher endpoints', async () => {
    assert.equal(await ensureAdminUser(pool, { username: 'Kogo_Admin', password: 'Sup3r-Secret-Pass' }), 'created');
    assert.equal(await ensureAdminUser(pool, { username: 'kogo_admin', password: 'Sup3r-Secret-Pass' }), 'unchanged');

    const login = await postJson(base, '/api/auth/login', { username: 'KOGO_ADMIN', password: 'Sup3r-Secret-Pass' });
    assert.equal(login.status, 200);
    assert.equal(login.body.data.user.role, 'admin');
    adminAccess = login.body.data.tokens.accessToken;
    adminRefresh = login.body.data.tokens.refreshToken;

    const me = await getJson(base, '/api/auth/me', bearer(adminAccess));
    assert.equal(me.status, 200);
    assert.equal(me.body.data.username, 'kogo_admin');

    const metrics = await getJson(base, '/api/v2/research/metrics', bearer(adminAccess));
    assert.equal(metrics.status, 200);
  });

  await t.test('refresh token is rejected as an access token', async () => {
    const res = await getJson(base, '/api/auth/me', bearer(adminRefresh));
    assert.equal(res.status, 401);
    assert.equal(res.body.code, 'INVALID_TOKEN');
  });

  await t.test('admin can create staff accounts; staff can log in', async () => {
    const created = await postJson(
      base,
      '/api/auth/register',
      { username: 'dr_peneliti', password: 'peneliti-pass-1', fullName: 'Dr. Peneliti', role: 'researcher' },
      bearer(adminAccess)
    );
    assert.equal(created.status, 201);
    assert.equal(created.body.data.role, 'researcher');

    const login = await postJson(base, '/api/auth/login', { username: 'dr_peneliti', password: 'peneliti-pass-1' });
    assert.equal(login.status, 200);
    assert.equal(login.body.data.user.role, 'researcher');
    researcherAccess = login.body.data.tokens.accessToken;
  });

  await t.test('NUL bytes in credentials are a 400, never a 500', async () => {
    const res = await postJson(base, '/api/auth/login', { username: 'a\u0000b', password: 'whatever' });
    assert.equal(res.status, 400);
    assert.equal(res.body.code, 'VALIDATION_ERROR');
  });

  await t.test('there is no public registration: no account, staff or participant enumeration', async () => {
    const attempts = [
      { username: 'kogo_admin', password: 'rahasia1', fullName: 'Penyusup' },
      { username: 'ani_publik', password: 'rahasia1', fullName: 'Ani', role: 'teacher' },
    ];
    for (const body of attempts) {
      const res = await postJson(base, '/api/auth/register', body);
      assert.equal(res.status, 401, JSON.stringify(body));
      assert.ok(!JSON.stringify(res.body).includes('kogo_admin'), 'existing usernames are never echoed to anonymous callers');
    }
    const child = await postJson(base, '/api/auth/register/child', {
      username: 'anak_publik',
      password: 'rahasia1',
      fullName: 'Anak Publik',
      ageYears: 5,
      schoolName: 'TK Pelita',
    });
    assert.equal(child.status, 401);
    const created = await pool.query("SELECT 1 FROM users WHERE username IN ('ani_publik', 'anak_publik')");
    assert.equal(created.rowCount, 0);
  });

  await t.test('staff create child accounts; only an admin creates staff', async () => {
    const child = await postJson(
      base,
      '/api/auth/register',
      { username: 'ani_kecil', password: 'rahasia1', fullName: 'Ani Kecil', ageYears: 5, schoolName: 'TK Pelita' },
      bearer(researcherAccess)
    );
    assert.equal(child.status, 201);
    assert.equal(child.body.data.role, 'child');
    const participant = await pool.query('SELECT user_id FROM participants WHERE participant_code = $1', ['ANI_KECIL']);
    assert.equal(participant.rows[0].user_id, child.body.data.id);

    const teacherByResearcher = await postJson(
      base,
      '/api/auth/register',
      { username: 'guru_palsu', password: 'rahasia1', fullName: 'Guru Palsu', role: 'teacher' },
      bearer(researcherAccess)
    );
    assert.equal(teacherByResearcher.status, 403);
    const exists = await pool.query('SELECT 1 FROM users WHERE username = $1', ['guru_palsu']);
    assert.equal(exists.rowCount, 0);

    const viaChildEndpoint = await postJson(
      base,
      '/api/auth/register/child',
      { username: 'budi_kecil', password: 'rahasia1', fullName: 'Budi Kecil', ageYears: 6, schoolName: 'TK Ceria' },
      bearer(researcherAccess)
    );
    assert.equal(viaChildEndpoint.status, 201);
    assert.equal(viaChildEndpoint.body.data.role, 'child');

    // Akun anak tidak dapat membuat akun.
    const childLogin = await postJson(base, '/api/auth/login', { username: 'budi_kecil', password: 'rahasia1' });
    const byChild = await postJson(
      base,
      '/api/auth/register/child',
      { username: 'citra_kecil', password: 'rahasia1', fullName: 'Citra', ageYears: 5, schoolName: 'TK Ceria' },
      bearer(childLogin.body.data.tokens.accessToken)
    );
    assert.equal(byChild.status, 403);
  });

  await t.test('duplicate username returns 409 USERNAME_TAKEN (staff only)', async () => {
    const dup = await postJson(base, '/api/auth/register', { username: 'ANI_KECIL', password: 'rahasia1', fullName: 'Ani Lain' }, bearer(adminAccess));
    assert.equal(dup.status, 409);
    assert.equal(dup.body.code, 'USERNAME_TAKEN');
  });

  await t.test('registration never hijacks an existing participant (409, rolled back)', async () => {
    await pool.query(
      `INSERT INTO participants (participant_code, display_alias, age_years, pin_hash) VALUES ('P_RISET', 'Peserta Riset', 5, 'x')`
    );
    const hijack = await postJson(base, '/api/auth/register', { username: 'p_riset', password: 'rahasia1', fullName: 'Penyusup' }, bearer(adminAccess));
    assert.equal(hijack.status, 409);
    assert.equal(hijack.body.code, 'PARTICIPANT_EXISTS');

    const participant = await pool.query('SELECT display_alias, user_id FROM participants WHERE participant_code = $1', ['P_RISET']);
    assert.equal(participant.rows[0].display_alias, 'Peserta Riset');
    assert.equal(participant.rows[0].user_id, null);
    const user = await pool.query('SELECT 1 FROM users WHERE username = $1', ['p_riset']);
    assert.equal(user.rowCount, 0, 'user insert is rolled back');
  });

  await t.test('wrong password, unknown user and inactive account all return the same 401', async () => {
    const wrong = await postJson(base, '/api/auth/login', { username: 'dr_peneliti', password: 'nope-nope' });
    const unknown = await postJson(base, '/api/auth/login', { username: 'nobody_here', password: 'nope-nope' });
    await pool.query('UPDATE users SET is_active = false WHERE username = $1', ['dr_peneliti']);
    const inactive = await postJson(base, '/api/auth/login', { username: 'dr_peneliti', password: 'peneliti-pass-1' });

    for (const res of [wrong, unknown, inactive]) {
      assert.equal(res.status, 401);
      assert.equal(res.body.code, 'INVALID_CREDENTIALS');
      assert.equal(res.body.message, INVALID_CREDENTIALS);
    }
    // Token yang sudah terbit untuk akun yang kini nonaktif langsung ditolak.
    const stale = await getJson(base, '/api/auth/me', bearer(researcherAccess));
    assert.equal(stale.status, 401);
    assert.equal(stale.body.code, 'ACCOUNT_DISABLED');
  });
});
