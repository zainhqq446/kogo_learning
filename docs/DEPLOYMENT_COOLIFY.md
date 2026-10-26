# Deploying the Kogo Belajar Backend on Coolify

Target: **https://be-kogo.taro.web.id** -> Coolify (Traefik terminates TLS) -> container port **4000** -> PostgreSQL 16.

```
Android app (offline-first, SQLite)
        |  HTTPS (sync, optional TTS/STT)
        v
Coolify Traefik  -- Let's Encrypt TLS for be-kogo.taro.web.id
        |  http://api:4000 (internal Docker network)
        v
api container (node:22-alpine, user "node")
  - entrypoint: migrations + reference seed + admin bootstrap, then `exec node dist/index.js`
  - volume /app/data (ElevenLabs TTS audio cache, size-capped)
        |  postgres://kogo_app@db:5432 (internal only, never published; NOT a superuser)
        v
db container (postgres:16-alpine + init script creating the "kogo_app" role, named volume)
```

Files involved (all in `backend/`): `Dockerfile`, `docker-entrypoint.sh`, `docker-compose.yml`, `docker/postgres/` (db image + role script), `.dockerignore`, `.env.example`.

---

## 1. Prerequisites

1. A server with Coolify v4 and the repository connected (GitHub App for private repos, or "Public Repository").
2. DNS: an `A` record `be-kogo.taro.web.id` -> public IP of the Coolify server (and `AAAA` if you use IPv6). Wait until `dig +short be-kogo.taro.web.id` returns the IP; Let's Encrypt needs it.
3. Secrets generated locally (keep them in a password manager):

```bash
openssl rand -hex 48          # JWT_SECRET (96 hex chars)
openssl rand -hex 24          # POSTGRES_PASSWORD (superuser, stays inside the db container)
openssl rand -hex 24          # APP_DB_PASSWORD (role the API connects with)
openssl rand -base64 18       # ADMIN_PASSWORD (>= 12 characters)
openssl rand -hex 24          # DEVICE_ENROLLMENT_KEY (optional, see section 6)
```

---

## 2. Option A (recommended): Docker Compose build pack (API + PostgreSQL)

1. In Coolify open your project/environment -> **+ New** -> **Resource** -> *Public Repository* (or *Private Repository (with GitHub App)*).
2. Select the repository and the branch to deploy.
3. **Build Pack**: `Docker Compose`.
4. **Base Directory**: `/backend`. **Docker Compose Location**: `/docker-compose.yml`. Click *Continue*.
5. Coolify lists the services `api` and `db`:
   - `api` -> **Domains**: `https://be-kogo.taro.web.id:4000`
     The `:4000` suffix only tells Traefik which *container* port to route to; the public URL is still `https://be-kogo.taro.web.id` (443).
   - `db` -> leave the domain **empty** (the database must never be public; the compose file does not publish any host port).
6. **Environment Variables** tab: set at least the required ones (see section 4):
   `POSTGRES_PASSWORD`, `APP_DB_PASSWORD`, `JWT_SECRET`, `ADMIN_USERNAME`, `ADMIN_PASSWORD`. Mark secrets as *secret/locked* in the UI.
7. Click **Deploy**. First deploy: Coolify builds both images, starts `db` (which creates the non-superuser role `kogo_app` and makes it owner of the database), waits until `pg_isready` over TCP is healthy, then starts `api`, which runs the migrations as `kogo_app` and creates the admin user.
8. The `api` service turns **healthy** after the Docker `HEALTHCHECK` (`GET /api/health`) succeeds; Traefik then routes traffic and Let's Encrypt issues the certificate (can take a minute on the first deploy).

Persistent storage is declared in the compose file and created by Coolify automatically:

| Volume | Mounted at | Contents |
| :--- | :--- | :--- |
| `kogo_pg_data` | `/var/lib/postgresql/data` (db) | All research data. **Back it up** (section 9). |
| `kogo_api_data` | `/app/data` (api) | TTS audio cache (safe to delete, capped by `TTS_CACHE_MAX_MB`). |

Coolify prefixes volume names with the resource UUID, e.g. `abc123_kogo-pg-data`. Find them with `docker volume ls | grep kogo`.

**Database roles.** `POSTGRES_USER` (default `kogo`) is the PostgreSQL superuser and is only given to the `db` container. The API connects as `APP_DB_USER` (default `kogo_app`), which owns the `kogo_research` database but has no superuser, `CREATEDB` or `CREATEROLE` rights, so a compromised API container or an SQL injection cannot run `COPY ... PROGRAM` or touch other databases. The role is created by `docker/postgres/10-kogo-app-role.sh` when the volume is **first** initialised. If your `kogo_pg_data` volume was created by an older version of this stack, run the script once by hand (it is idempotent: creates/updates the role and hands over the existing tables), then redeploy:

```bash
docker exec -it <db container> /docker-entrypoint-initdb.d/10-kogo-app-role.sh
```

## 3. Option B: Dockerfile build pack + separate Coolify PostgreSQL

Use this if you prefer Coolify's managed database features (scheduled backups to S3 from the UI).

1. **+ New** -> **Database** -> **PostgreSQL** -> version **16** (image `postgres:16-alpine`). Deploy it.
2. Create a non-superuser role for the API (Coolify database -> *Terminal*, or `docker exec -it <db> psql -U postgres`):

   ```sql
   CREATE ROLE kogo_app LOGIN PASSWORD '<APP_DB_PASSWORD>' NOSUPERUSER NOCREATEDB NOCREATEROLE;
   CREATE DATABASE kogo_research OWNER kogo_app;
   ```

   Use `postgres://kogo_app:<APP_DB_PASSWORD>@<internal host>:5432/kogo_research` as `DATABASE_URL` (URL-encode special characters of the password). Do not give the API the `postgres` superuser URL.
3. **+ New** -> **Resource** -> repository -> **Build Pack**: `Dockerfile`, **Base Directory** `/backend`, **Dockerfile Location** `/Dockerfile`.
4. **Ports Exposes**: `4000`. **Domains**: `https://be-kogo.taro.web.id`. Do not add a host port mapping.
5. **Health check** (Configuration -> Health Checks): enabled, path `/api/health`, port `4000`, scheme `http`.
6. **Persistent Storage**: add a volume mounted at `/app/data`.
7. Environment variables: `DATABASE_URL`, `JWT_SECRET`, `ADMIN_USERNAME`, `ADMIN_PASSWORD`, plus optional ones from section 4 (`NODE_ENV` already defaults to `production` in the image).
8. Deploy. Configure **Backups** on the PostgreSQL resource (schedule + S3 destination).

---

## 4. Environment variables

Full list with comments: [`backend/.env.example`](../backend/.env.example). With the compose build pack every variable below is passed through `docker-compose.yml` (`${VAR:-default}`); required ones use `${VAR:?}` so the deploy fails fast if they are missing. With the Dockerfile build pack set them directly on the resource.

| Variable | Required | Default | Description |
| :--- | :---: | :--- | :--- |
| `POSTGRES_PASSWORD` | yes (compose) | - | Superuser password of the bundled PostgreSQL (only the `db` container gets it) |
| `APP_DB_PASSWORD` | yes (compose) | - | Password of the non-superuser role the API uses |
| `APP_DB_USER` | no | `kogo_app` | Name of that role (must differ from `POSTGRES_USER`) |
| `POSTGRES_USER` / `POSTGRES_DB` | no | `kogo` / `kogo_research` | Bundled superuser / database name |
| `DATABASE_URL` | Option B | empty | Full connection URL; overrides `DB_*` |
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` | no | set by compose | Individual DB settings (Option B / local) |
| `DB_SSL` / `DB_SSL_REJECT_UNAUTHORIZED` | no | `false` / `true` | TLS to an external database (certificate verified by default) |
| `DB_MAX_CONNECTIONS`, `DB_IDLE_TIMEOUT_MILLIS`, `DB_CONNECTION_TIMEOUT_MILLIS` | no | `10`, `30000`, `5000` | Pool settings |
| `JWT_SECRET` | **yes** | - | >= 32 random chars; the server refuses to start in production without it. Known public values (old default, `.env.example` placeholder) are rejected/ignored in every environment |
| `JWT_EXPIRES_IN` / `JWT_REFRESH_EXPIRES_IN` | no | `15m` / `7d` | Researcher token lifetimes (account status is re-checked on every request anyway) |
| `DEVICE_TOKEN_TTL` | no | `180d` | Device token lifetime |
| `BCRYPT_SALT_ROUNDS` | no | `10` | bcrypt cost |
| `ADMIN_USERNAME` / `ADMIN_PASSWORD` | recommended | empty | Admin account created/updated on every start (password >= 12 chars) |
| `DEVICE_ENROLLMENT_KEY` | recommended | empty | If set, new devices must send `X-Enrollment-Key` and are approved automatically. If empty, new devices are `pending` until approved (section 6) |
| `SYNC_MAX_CLOCK_SKEW_HOURS` | no | `24` | Device timestamps further in the future are rejected per item |
| `NODE_ENV` | no | `production` | Keep `production` (stack traces only with `development`) |
| `HOST` / `PORT` | no | `0.0.0.0` / `4000` | Bind address / container port |
| `APP_VERSION` | no | `2.0.0` | Reported by `/api/health` |
| `TRUST_PROXY` | no | `loopback, linklocal, uniquelocal` | Peers allowed to set `X-Forwarded-For` (Traefik on the Docker network). See section 5 for Cloudflare |
| `CORS_ORIGIN` | no | empty (disabled) | Comma-separated browser origins, only needed for a web dashboard |
| `RUN_MIGRATIONS_ON_START` | no | `true` | Migrations + reference seed + admin bootstrap at start (advisory-locked) |
| `DB_WAIT_SECONDS` | no | `60` | Wait for the database on start |
| `RATE_LIMIT_ENABLED` | no | `true` | Rate limiting switch |
| `RATE_LIMIT_AUTH_MAX` | no | `10` | Login/register attempts per 15 min per IP |
| `RATE_LIMIT_VOICE_PER_MIN` / `RATE_LIMIT_SYNC_PER_MIN` | no | `60` / `60` | Per device/user per minute |
| `RATE_LIMIT_VOICE_PER_IP_PER_MIN` | no | `120` | Voice requests per client IP per minute (before authentication) |
| `RATE_LIMIT_DEVICE_REGISTER_PER_HOUR` | no | `20` | Per IP per hour |
| `ELEVENLABS_API_KEY` | no | empty | Enables the TTS/STT proxy (otherwise 503 `NOT_CONFIGURED`) |
| `ELEVENLABS_BASE_URL` | no | `https://api.elevenlabs.io/v1` | API base URL |
| `ELEVENLABS_DEFAULT_VOICE_ID` | for TTS | empty | Indonesian-capable voice from the ElevenLabs Voice Library |
| `ELEVENLABS_DEFAULT_MODEL_ID` | no | `eleven_multilingual_v2` | TTS model |
| `ELEVENLABS_ALLOWED_VOICE_IDS` / `ELEVENLABS_ALLOWED_MODEL_IDS` | no | defaults only | Extra voices/models clients may request |
| `ELEVENLABS_STT_MODEL_ID` | no | `scribe_v2` | STT model (`scribe_v1` was retired in July 2026) |
| `ELEVENLABS_LANGUAGE_CODE` | no | `id` | Language for STT and language-enforcing TTS models |
| `ELEVENLABS_TEXT_NORMALIZATION` | no | `auto` | `auto`, `on` or `off` |
| `ELEVENLABS_TTS_TIMEOUT_MS` / `ELEVENLABS_STT_TIMEOUT_MS` | no | `15000` / `20000` | Upstream timeouts |
| `ELEVENLABS_DAILY_CHAR_BUDGET` | no | `20000` | TTS characters per UTC day sent to ElevenLabs (cache misses). `0` = cached audio only |
| `ELEVENLABS_DAILY_STT_SECONDS_BUDGET` | no | `1800` | STT audio seconds per UTC day. `0` = STT disabled |
| `TTS_MAX_TEXT_LENGTH` | no | `300` | Max characters per TTS request |
| `MAX_AUDIO_UPLOAD_BYTES` | no | `2097152` | Max STT upload (bytes) |
| `TTS_CACHE_ENABLED` / `TTS_CACHE_MAX_MB` | no | `true` / `256` | Disk cache switch and size cap (LRU eviction) |
| `TTS_CACHE_DIR` | no | `/app/data/tts-cache` | Disk cache location |

---

## 5. Domain, HTTPS, client IPs and health checks

- Coolify requests a Let's Encrypt certificate automatically when the domain starts with `https://`. HTTP is redirected to HTTPS by Traefik.
- Client IPs (rate limits): by default the API trusts `X-Forwarded-For` only when the direct peer is a private address (Traefik on the Docker network). A client that reaches the container port directly cannot spoof its IP, so do not switch `TRUST_PROXY` to a hop count unless port 4000 is unreachable from outside.
- If the domain is proxied by **Cloudflare** (orange cloud): set SSL/TLS mode to *Full (strict)* and append Cloudflare's ranges (https://www.cloudflare.com/ips/) to `TRUST_PROXY`, e.g. `loopback, linklocal, uniquelocal, 173.245.48.0/20, 103.21.244.0/22, ...`. Otherwise every user is identified by a Cloudflare edge IP in the rate limiter.
- Liveness: `GET /api/health` (Docker `HEALTHCHECK` every 30 s, 60 s start period). It never touches the database, so a database outage does not restart the API in a loop.
- Readiness: `GET /api/health/ready` returns 503 while PostgreSQL is unreachable. Use it for uptime monitoring (e.g. Coolify notifications, UptimeRobot).
- The server sets keep-alive timeouts above Traefik's to avoid sporadic 502s, and handles `SIGTERM` gracefully (Node is PID 1 via `exec`).

---

## 6. First admin login, researcher accounts and device approval

1. Set `ADMIN_USERNAME` and `ADMIN_PASSWORD`, deploy. The log shows `Admin account '<name>' created from ADMIN_USERNAME/ADMIN_PASSWORD.`
2. Log in:

```bash
BASE=https://be-kogo.taro.web.id/api
ACCESS=$(curl -s -X POST $BASE/auth/login -H 'Content-Type: application/json' \
  -d '{"username":"kogo_admin","password":"<ADMIN_PASSWORD>"}' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["tokens"]["accessToken"])')
```

3. Create a researcher account (there is no public registration; only an admin can create staff):

```bash
curl -s -X POST $BASE/auth/register -H "Authorization: Bearer $ACCESS" -H 'Content-Type: application/json' \
  -d '{"username":"peneliti1","password":"<strong password>","fullName":"Peneliti 1","role":"researcher"}'
```

The environment is the source of truth for the admin: changing `ADMIN_PASSWORD` and redeploying rotates the password and re-activates the account. Deactivating a user (`UPDATE users SET is_active = false ...`) takes effect on the next request, not only after the token expires.

4. **Approve the field-test tablet(s).** Anyone on the internet can call `POST /api/v2/devices/register`, so data from new devices is quarantined: it is stored, but metrics and exports only include **approved** devices, and only approved devices may use the paid voice proxy. After the tablet's first sync:

```bash
curl -s $BASE/v2/research/devices -H "Authorization: Bearer $ACCESS"
# -> [{"deviceId":"<id>","status":"pending","model":"SM-T225","learners":1,"sessions":3,...}]
curl -s -X POST $BASE/v2/research/devices/<id>/approve -H "Authorization: Bearer $ACCESS" \
  -H 'Content-Type: application/json' -d '{"label":"Tablet TK Pelita"}'
```

   Use `?devices=all` on the metrics/exports to look at pending data before approving, and `POST .../revoke` to exclude a device and block its tokens. Alternatively set `DEVICE_ENROLLMENT_KEY` and ship field-test builds that send it as the `X-Enrollment-Key` header (e.g. `--dart-define`): such devices are approved automatically and unknown devices cannot register at all.

5. If a tablet loses its `deviceSecret` (for example after `JWT_SECRET` was rotated and the app did not store the secret), re-registration returns 409 `DEVICE_PROOF_REQUIRED`. Run `POST /api/v2/research/devices/<id>/reset-credential`; the next registration of that tablet then succeeds and receives a new secret.

---

## 7. Verify the deployment with curl

```bash
BASE=https://be-kogo.taro.web.id/api

# 1. Liveness and readiness
curl -s $BASE/health
curl -s -w '\n%{http_code}\n' $BASE/health/ready          # expect 200 and "database":"up"

# 2. Register a test device (fresh random UUID). Keep reg.json: it holds the one-time deviceSecret.
DEV=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen)
curl -s -X POST $BASE/v2/devices/register -H 'Content-Type: application/json' \
  -d "{\"deviceUuid\":\"$DEV\",\"platform\":\"android\",\"appVersion\":\"smoke-test\"}" > reg.json
DEVICE_TOKEN=$(python3 -c 'import json;print(json.load(open("reg.json"))["data"]["deviceToken"])')
DEVICE_ID=$(python3 -c 'import json,base64;t=json.load(open("reg.json"))["data"]["deviceToken"].split(".")[1];print(json.loads(base64.urlsafe_b64decode(t+"=="))["deviceId"])')

# 3. Sync one learner, one session, one attempt (run twice: same counts, no duplicates)
L=$(uuidgen); S=$(uuidgen); A=$(uuidgen); NOW=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
curl -s -X POST $BASE/v2/sync -H "Authorization: Bearer $DEVICE_TOKEN" -H 'Content-Type: application/json' -d "{
  \"learners\":[{\"clientUuid\":\"$L\",\"name\":\"Uji Coba\",\"school\":\"TK Uji\",\"age\":5,\"createdAt\":\"$NOW\",\"updatedAt\":\"$NOW\"}],
  \"sessions\":[{\"clientUuid\":\"$S\",\"learnerUuid\":\"$L\",\"materi\":\"two-syllable\",\"nodeIndex\":0,\"gameType\":\"speaking\",\"status\":\"completed\",\"totalItems\":4,\"firstTryCorrect\":3,\"stars\":2,\"startedAt\":\"$NOW\",\"endedAt\":\"$NOW\"}],
  \"attempts\":[{\"clientUuid\":\"$A\",\"sessionUuid\":\"$S\",\"learnerUuid\":\"$L\",\"gameType\":\"speaking\",\"targetText\":\"bola\",\"answerText\":\"bola\",\"isCorrect\":true,\"attemptNumber\":1,\"similarity\":1,\"responseMs\":1400,\"sttError\":null,\"createdAt\":\"$NOW\"}]}"
# expect {"status":"success","data":{"accepted":{"learners":1,"sessions":1,"attempts":1},"rejected":[]}}

# 4. Metrics: the device is still pending -> overall is empty and "devices":{"pending":1}
curl -s $BASE/v2/research/metrics -H "Authorization: Bearer $ACCESS"
curl -s -X POST $BASE/v2/research/devices/$DEVICE_ID/approve -H "Authorization: Bearer $ACCESS"
curl -s $BASE/v2/research/metrics -H "Authorization: Bearer $ACCESS"     # now includes the test data
curl -s -OJ $BASE/v2/research/export/attempts.csv -H "Authorization: Bearer $ACCESS"
curl -s -OJ $BASE/v2/research/export/sessions.csv -H "Authorization: Bearer $ACCESS"

# 5. Security checks
curl -s -o /dev/null -w '%{http_code}\n' $BASE/v2/research/metrics                       # 401
curl -s -o /dev/null -w '%{http_code}\n' -X POST $BASE/voice/tts -d '{}' -H 'Content-Type: application/json'  # 401
curl -s -o /dev/null -w '%{http_code}\n' -X POST $BASE/v2/devices/register -H 'Content-Type: application/json' \
  -d "{\"deviceUuid\":\"$DEV\",\"platform\":\"android\",\"appVersion\":\"x\"}"                # 409 (UUID alone is not enough)
curl -s -o /dev/null -w '%{http_code}\n' -X POST $BASE/auth/register -H 'Content-Type: application/json' \
  -d '{"username":"x_user","password":"secret12","fullName":"X"}'                              # 401 (no public sign-up)
curl -s -X POST $BASE/voice/tts -H "Authorization: Bearer $DEVICE_TOKEN" -H 'Content-Type: application/json' \
  -d '{"text":"Halo"}' -o /dev/null -w '%{http_code}\n'   # 200 with ElevenLabs configured, 503 otherwise
```

Remove smoke-test data afterwards if it should not appear in the thesis data: revoke the test device (`POST /v2/research/devices/$DEVICE_ID/revoke`, which excludes it from metrics/exports), or delete the learner by `client_uuid` in the database (sessions and attempts cascade).

---

## 8. Privacy

The `learners` table and both CSV exports contain children's names and schools. Obtain written parental consent (as required by the proposal), restrict researcher accounts, store downloaded CSVs encrypted, and delete them at the end of the retention period. The device credential (`deviceUuid`/`deviceSecret`) is never shown in exports or device listings.

---

## 9. Backups and restore

**Option A (database inside the compose stack)** - run on the Coolify host, e.g. from cron:

```bash
DB=$(docker ps --format '{{.Names}}' | grep -E 'db-' | grep -i kogo | head -1)   # or copy the name from Coolify
docker exec "$DB" pg_dump -U kogo -d kogo_research -Fc > /root/backups/kogo_$(date +%F).dump
```

Restore into an empty database (objects are recreated with `kogo_app` as owner):

```bash
docker exec -i "$DB" pg_restore -U kogo -d kogo_research --clean --if-exists --no-owner --role=kogo_app < /root/backups/kogo_2026-10-25.dump
```

Copy the dumps off the server (S3, another machine). A raw copy of the `kogo_pg_data` volume is only consistent when the `db` container is stopped.

**Option B (Coolify PostgreSQL resource)** - enable *Backups* on the database resource (cron schedule + S3 storage) and test a restore once before the field study.

Also export the CSVs after each field-test day as an extra, human-readable copy.

---

## 10. Updates and migrations

- Push to the deployed branch and click **Redeploy** (or enable auto-deploy via webhook).
- Migrations in `backend/migrations/*.sql` run automatically before the server starts, inside a PostgreSQL advisory lock (safe with overlapping old/new containers during a rolling deploy). Applied files are recorded in `schema_migrations`; never edit an applied migration, add a new numbered file instead.
- Reference data (`materi`, `word_types`, `words`, `reward_tiers`) is re-seeded idempotently from `src/data/vocabulary.json` on every start.
- To run migrations manually: `docker compose run --rm api node dist/scripts/migrate.js` (or set `RUN_MIGRATIONS_ON_START=false` and run it as a Coolify "pre-deployment command").

---

## 11. ElevenLabs (optional premium voice) and cost control

1. Create an API key in ElevenLabs (restrict it to Text to Speech and Speech to Text if possible) and set a monthly credit limit in the ElevenLabs dashboard as a last line of defence.
2. Pick an Indonesian-capable voice in the Voice Library and copy its Voice ID.
3. Set `ELEVENLABS_API_KEY` and `ELEVENLABS_DEFAULT_VOICE_ID` (and optionally `ELEVENLABS_ALLOWED_VOICE_IDS`), redeploy.
4. Check with a staff access token or an approved device token: `GET /api/voice/status` -> `"configured": true`.

How spend is bounded:

- Only active staff accounts and **approved** devices can call the proxy; child accounts, pending and revoked devices get 403. There is no public account registration, and newly registered devices are pending, so nobody can mint new voice credentials.
- Rate limits: 120 requests/min per client IP (before authentication) and 60/min per device or user.
- Daily budgets in PostgreSQL: `ELEVENLABS_DAILY_CHAR_BUDGET` (default 20 000 characters of TTS cache misses) and `ELEVENLABS_DAILY_STT_SECONDS_BUDGET` (default 1 800 s of STT audio). When used up the endpoints return 503 `VOICE_BUDGET_EXHAUSTED` until the next UTC day; usage is in the `voice_usage_daily` table.
- Text is capped at 300 characters; client `settings` are snapped to a coarse grid; audio is cached on disk (`X-Cache: HIT` costs nothing) with an LRU size cap (`TTS_CACHE_MAX_MB`).
- Only allowlisted voices/models can be requested.

---

## 12. Troubleshooting

| Symptom | Cause / fix |
| :--- | :--- |
| `api` restarts, log shows `ConfigError: ... JWT_SECRET is required` | Set `JWT_SECRET` (>= 32 random chars; the `.env.example` placeholder and the old default are rejected). Same for `ADMIN_PASSWORD` shorter than 12 chars. |
| Deploy fails with `Set POSTGRES_PASSWORD` / `Set APP_DB_PASSWORD` / `Set JWT_SECRET` | Required compose variables are missing in the Environment Variables tab. |
| `password authentication failed for user "kogo_app"` | The `kogo_pg_data` volume predates the role script, or `APP_DB_PASSWORD` was changed after the first start. Run `docker exec -it <db> /docker-entrypoint-initdb.d/10-kogo-app-role.sh` (re-applies role and password), then redeploy. |
| `502 Bad Gateway` / `no available server` | The `api` container is not healthy yet, or the domain lacks the `:4000` suffix (compose) / Ports Exposes is not 4000 (Dockerfile). Check the deployment and container logs. |
| Certificate error right after the first deploy | DNS not pointing to the server yet, or Let's Encrypt still issuing. Check Traefik logs in Coolify. |
| `PostgreSQL is not reachable after 60s` | Wrong `DATABASE_URL`/`DB_*`, database not running, or the API is not in the same network as the database (Option B: use the *internal* URL). |
| Password authentication failed for the superuser after changing `POSTGRES_PASSWORD` | PostgreSQL only uses `POSTGRES_PASSWORD` when the volume is first initialised. Change it inside the database (`ALTER USER kogo PASSWORD '...'`) or recreate the volume (data loss). |
| Metrics are all zero although the tablet synced | The device is still `pending`: approve it (section 6), or check with `?devices=all`. The response field `devices.pending` shows how many devices wait for approval. |
| App cannot re-register: 409 `DEVICE_PROOF_REQUIRED` | The app lost or never stored its `deviceSecret` and its token is invalid (e.g. `JWT_SECRET` rotated). Run `reset-credential` for the device (section 6). |
| Sync or voice returns 403 `DEVICE_REVOKED` | A researcher revoked the device; approve it again if that was a mistake. |
| Every user gets 429 at the same time | An extra proxy in front of Traefik (e.g. Cloudflare) whose IPs are not in `TRUST_PROXY` (section 5). |
| Voice endpoints return 503 `NOT_CONFIGURED` | ElevenLabs key or default voice not set (expected if you rely on on-device TTS). |
| Voice endpoints return 503 `VOICE_BUDGET_EXHAUSTED` | Daily budget used up; raise `ELEVENLABS_DAILY_CHAR_BUDGET` / `ELEVENLABS_DAILY_STT_SECONDS_BUDGET` or wait for the next UTC day. |
| Voice endpoints return 400 `VOICE_NOT_ALLOWED` | The app asked for a voice not in `ELEVENLABS_ALLOWED_VOICE_IDS`. |
| `EACCES` writing `/app/data/tts-cache` | Volume created with root ownership: `docker run --rm -v <volume>:/data alpine chown -R 1000:1000 /data`. The cache is optional; the API keeps working without it. |
| Sync returns `FOREIGN_DEVICE` | The UUID was first synced by another device (e.g. a restored backup on a second tablet). Data is not overwritten by design. |
| Sync rejects items with `INVALID` and "too far in the future" | The tablet clock is more than `SYNC_MAX_CLOCK_SKEW_HOURS` ahead. Fix the tablet's date/time (automatic network time). |
| Sync returns 401 `DEVICE_NOT_REGISTERED` | The database was reset; the app must call `/v2/devices/register` again. |
| Image build hits Docker Hub `429 Too Many Requests` | Log Coolify's server in to Docker Hub or retry later; the build only needs `node:22-alpine` and `postgres:16-alpine`. |

---

## 13. Local development and tests

```bash
cd backend
cp .env.example .env            # set DB_* for your local PostgreSQL and uncomment NODE_ENV=development
npm ci
npm run dev                     # http://127.0.0.1:4000/api/health

npm test                        # build + unit tests (no database needed)
TEST_DATABASE_URL=postgres://postgres:postgres@localhost:5432/kogo_research_test npm run test:integration
npx tsc --noEmit

# Full stack in Docker (same as Coolify)
POSTGRES_PASSWORD=$(openssl rand -hex 24) APP_DB_PASSWORD=$(openssl rand -hex 24) JWT_SECRET=$(openssl rand -hex 48) \
  ADMIN_USERNAME=kogo_admin ADMIN_PASSWORD=dev-admin-password docker compose up -d --build
docker compose down -v          # stop and delete local volumes
```

Without `NODE_ENV=development` the server runs in production mode and refuses to start without a real `JWT_SECRET`. The integration suite refuses to run unless the database name contains `test` (it truncates tables and recreates the `public` schema).
