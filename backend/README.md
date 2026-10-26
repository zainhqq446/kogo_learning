# Kogo Belajar - Backend

Node.js 22 + Express 4 + TypeScript (ESM) + PostgreSQL 16 backend for the **Kogo Belajar** Android app (offline-first word pronunciation practice for children aged 5-6).

The app works fully offline; the backend provides:

- **Research data sync** for the thesis field test: `POST /api/v2/devices/register`, `POST /api/v2/sync`.
- **Researcher metrics and CSV exports**: `GET /api/v2/research/metrics`, `/api/v2/research/export/{attempts,sessions}.csv`.
- **Optional premium voice**: authenticated, rate-limited, allowlisted ElevenLabs TTS/STT proxy with a disk cache (`/api/voice/*`).
- Legacy v1 research API (`/api/research/*`) kept for backward compatibility.

Documentation:

- API: [`docs/API_DOCUMENTATION.md`](../docs/API_DOCUMENTATION.md)
- Deployment (Coolify / Docker, `https://be-kogo.taro.web.id`): [`docs/DEPLOYMENT_COOLIFY.md`](../docs/DEPLOYMENT_COOLIFY.md)
- Environment variables: [`.env.example`](./.env.example)

## Project layout

```text
backend/
├── src/
│   ├── config/        env.ts (validated config, fail-fast in production), database.ts (pool, DATABASE_URL / DB_*)
│   ├── controllers/   HTTP handlers (auth, health, research v1, v2, voice)
│   ├── data/          vocabulary.json - curated curriculum (source of truth, read-only)
│   ├── middlewares/   auth (user/device tokens, RBAC), rate limits, error handler, validation
│   ├── routes/        route factories (rate limiters are created per app instance)
│   ├── scripts/       migrate.ts, check_db.ts, seed_curriculum.ts (legacy), setup_e2e_db.ts (legacy)
│   ├── services/      sync, metrics/CSV, device, auth/token, voice + TTS cache, migrator, startup tasks
│   ├── test/          unit/ (no DB), integration/ (real PostgreSQL), helpers/
│   ├── types/         zod schemas, curriculum constants, errors, user types
│   └── utils/         logger (redacts secrets), csv, duration, paths
├── migrations/        001-005 SQL migrations (004 = thesis ERD, 005 = device trust + voice budget)
├── docker/postgres/   db image: postgres:16-alpine + non-superuser API role script
├── Dockerfile, docker-entrypoint.sh, docker-compose.yml, .dockerignore, .env.example
```

## Running locally

```bash
cp .env.example .env          # adjust DB_* (or DATABASE_URL) and uncomment NODE_ENV=development
npm ci
npm run db:migrate            # migrations + reference data + admin bootstrap (also runs on server start)
npm run dev                   # http://127.0.0.1:4000/api/health
```

Production build: `npm run build && npm start` (requires `JWT_SECRET`, see `.env.example`).

## Tests

```bash
npm test                      # builds, then runs unit tests (no database required)
TEST_DATABASE_URL=postgres://postgres:postgres@localhost:5432/kogo_research_test npm run test:integration
npm run typecheck
```

Integration tests run sequentially (`--test-concurrency=1`) against a disposable database whose name must contain `test`
(they truncate tables and recreate the `public` schema). Without `TEST_DATABASE_URL` they use `DATABASE_URL` or `DB_*`
with `DB_NAME` defaulting to `kogo_research_test`.

## Security notes

- `NODE_ENV` defaults to `production`; production refuses to start without a strong `JWT_SECRET`, and publicly known secrets (old default, `.env.example` placeholder) are ignored in every environment. Outside production the server binds to `127.0.0.1` by default.
- JWTs are HS256-only; refresh tokens and device tokens are never accepted where an access token is required. Account status and role are re-read from the database on every authenticated request.
- There is no public registration: staff accounts come from `ADMIN_USERNAME`/`ADMIN_PASSWORD` (bootstrapped at start) or an admin; staff create child accounts.
- Devices: a known `deviceUuid` can only be re-registered with the one-time `deviceSecret` or a valid device token. New devices are `pending` (data quarantined from metrics/exports, no voice access) until a researcher approves them, unless they register with `DEVICE_ENROLLMENT_KEY`. Device tokens carry only the internal device id; exports never contain the `deviceUuid`.
- Voice proxy: staff or approved devices only, per-IP and per-principal rate limits, daily character/second budgets in PostgreSQL, size-capped cache.
- Rate limits: auth 10/15 min/IP, device registration 20/h/IP, sync and voice 60/min per device/user, voice 120/min/IP. `TRUST_PROXY` defaults to `loopback, linklocal, uniquelocal`, so `X-Forwarded-For` is only honoured from Traefik on the Docker network.
- The compose stack runs the API as a non-superuser PostgreSQL role (`APP_DB_USER`), created by `docker/postgres/10-kogo-app-role.sh`.
- CORS is off unless `CORS_ORIGIN` is set. Errors carry stable `code`s and never include stack traces or raw PostgreSQL messages; strings with NUL characters are rejected as client errors.
- The logger redacts tokens, passwords and API keys.
