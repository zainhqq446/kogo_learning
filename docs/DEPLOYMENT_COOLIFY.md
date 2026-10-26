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
| `SYNC_MAX_CLOCK_SKEW_HOURS` | no | `24` | Device timestamps further in the future are clamped to the server's current time (the item is still accepted) |
| `PENDING_DEVICE_MAX_ITEMS` | no | `20000` | Maximum game sessions + answer attempts stored for a device that is still `pending`. Beyond it `POST /api/v2/sync` returns 403 `DEVICE_PENDING_QUOTA` for the whole request; the app keeps the data queued and sends it after approval. Approved devices have no limit |
| `NODE_ENV` | no | `production` | Keep `production` (stack traces only with `development`) |
| `HOST` / `PORT` | no | `0.0.0.0` / `4000` | Bind address / container port |
| `APP_VERSION` | no | `2.0.0` | Reported by `/api/health` |
| `TRUST_PROXY` | no | `loopback, linklocal, uniquelocal` | Peers allowed to set `X-Forwarded-For` (Traefik on the Docker network). See section 5 for Cloudflare |
| `CORS_ORIGIN` | no | empty (disabled) | Comma-separated browser origins, only needed for a web dashboard |
| `RUN_MIGRATIONS_ON_START` | no | `true` | Migrations + reference seed + admin bootstrap at start (advisory-locked). Keep `true` (section 10) |
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
- Keep-alive: Node keeps idle connections open for 95 s (`keepAliveTimeout`, with `headersTimeout` 96 s), longer than Traefik's 90 s idle timeout for upstream connections. Traefik therefore always closes an idle connection first and never sends a request on a connection Node has just closed, which would show up as a sporadic 502.
- The server handles `SIGTERM` gracefully (Node is PID 1 via `exec`).

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

4. **Approve the field-test tablet(s).** Anyone on the internet can call `POST /api/v2/devices/register`, so data from new devices is quarantined: it is stored (up to `PENDING_DEVICE_MAX_ITEMS`, default 20000 sessions + attempts per device), but metrics and exports only include **approved** devices, and only approved devices may use the paid voice proxy. After the tablet's first sync:

```bash
curl -s $BASE/v2/research/devices -H "Authorization: Bearer $ACCESS"
# -> [{"deviceId":"<id>","status":"pending","model":"SM-T225","learners":1,"sessions":3,...}]
curl -s -X POST $BASE/v2/research/devices/<id>/approve -H "Authorization: Bearer $ACCESS" \
  -H 'Content-Type: application/json' -d '{"label":"Tablet TK Pelita"}'
```

   Use `?devices=all` on the metrics/exports to look at pending data before approving, and `POST .../revoke` to exclude a device and block its tokens. A pending device whose sync request would take it above `PENDING_DEVICE_MAX_ITEMS` stored sessions + attempts gets 403 `DEVICE_PENDING_QUOTA` for that request (the app sends up to 200 sessions and 500 attempts per request, so uploads can stop a few hundred items before the limit); its data stays queued on the tablet and is sent after approval. Alternatively set `DEVICE_ENROLLMENT_KEY` and build the field-test APK with `--dart-define=KOGO_ENROLLMENT_KEY=<same value>`, so the app sends it as the `X-Enrollment-Key` header: such devices are approved automatically and unknown devices cannot register at all. The key only applies to new registrations; a tablet that already registered as `pending` still has to be approved.

5. If a tablet loses its `deviceSecret` (for example after `JWT_SECRET` was rotated and the app did not store the secret), re-registration returns 409 `DEVICE_PROOF_REQUIRED`. Run `POST /api/v2/research/devices/<id>/reset-credential`; the next registration of that tablet then succeeds and receives a new secret.

---

## 7. Verify the deployment with curl

```bash
BASE=https://be-kogo.taro.web.id/api
# Random UUID v4 on Linux, macOS (uuidgen) or anywhere with Python 3.
uuid() { cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || python3 -c 'import uuid;print(uuid.uuid4())'; }

# 1. Liveness and readiness
curl -s $BASE/health
curl -s -w '\n%{http_code}\n' $BASE/health/ready          # expect 200 and "database":"up"

# 2. Register a test device (fresh random UUID). Keep reg.json: it holds the one-time deviceSecret.
DEV=$(uuid)
curl -s -X POST $BASE/v2/devices/register -H 'Content-Type: application/json' \
  -d "{\"deviceUuid\":\"$DEV\",\"platform\":\"android\",\"appVersion\":\"smoke-test\"}" > reg.json
DEVICE_TOKEN=$(python3 -c 'import json;print(json.load(open("reg.json"))["data"]["deviceToken"])')
DEVICE_ID=$(python3 -c 'import json,base64;t=json.load(open("reg.json"))["data"]["deviceToken"].split(".")[1];print(json.loads(base64.urlsafe_b64decode(t+"=="))["deviceId"])')

# 3. Sync one learner, one session, one attempt (run twice: same counts, no duplicates)
L=$(uuid); S=$(uuid); A=$(uuid); NOW=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
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

**Option A (database inside the compose stack)** - run on the Coolify host.

Coolify names containers `<service>-<resource UUID>-<timestamp>` and the name changes with every deploy, so do not search for the container by name. Find it by its Docker Compose labels instead: Coolify uses the resource UUID (shown in the resource's URL in the Coolify dashboard and in the container names) as the Compose project name. To check the value, list the `db` containers with their project label:

```bash
docker ps --filter label=com.docker.compose.service=db --format '{{.Label "com.docker.compose.project"}}  {{.Names}}'
```

Save the backup as a script, e.g. `/root/kogo-backup.sh` (`chmod 700`), and run it from cron (`15 2 * * * /root/kogo-backup.sh >> /var/log/kogo-backup.log 2>&1`). It fails loudly when the container is not found or the dump is empty, and only replaces a backup file with a complete, non-empty dump:

```bash
#!/usr/bin/env bash
set -euo pipefail
APP_UUID=<Coolify resource UUID>
BACKUP_DIR=/root/backups
DB=$(docker ps -q --filter "label=com.docker.compose.project=$APP_UUID" --filter label=com.docker.compose.service=db)
[ -n "$DB" ] || { echo "kogo db container not found" >&2; exit 1; }
mkdir -p "$BACKUP_DIR"
OUT="$BACKUP_DIR/kogo_$(date +%F).dump"
trap 'rm -f "$OUT.tmp"' EXIT
# -U / -d: defaults of POSTGRES_USER / POSTGRES_DB in docker-compose.yml (adjust if you changed them).
docker exec "$DB" pg_dump -U kogo -d kogo_research -Fc > "$OUT.tmp"
[ -s "$OUT.tmp" ] || { echo "kogo backup is empty: $OUT.tmp" >&2; exit 1; }
mv "$OUT.tmp" "$OUT"
echo "kogo backup written: $OUT"
```

Restore (drops and recreates the tables, with `kogo_app` as owner). Save it as `/root/kogo-restore.sh` and run `bash /root/kogo-restore.sh /root/backups/kogo_2026-10-25.dump` (as a script, so that `set -e` and `exit` do not close your shell). It uses the same lookup, refuses a missing or empty dump file, and stops the `api` container while the tables are recreated:

```bash
#!/usr/bin/env bash
set -euo pipefail
APP_UUID=<Coolify resource UUID>
DUMP=${1:?usage: kogo-restore.sh <dump file>}
DB=$(docker ps -q --filter "label=com.docker.compose.project=$APP_UUID" --filter label=com.docker.compose.service=db)
[ -n "$DB" ] || { echo "kogo db container not found" >&2; exit 1; }
API=$(docker ps -q --filter "label=com.docker.compose.project=$APP_UUID" --filter label=com.docker.compose.service=api)
[ -s "$DUMP" ] || { echo "dump file missing or empty: $DUMP" >&2; exit 1; }
[ -z "$API" ] || docker stop "$API"
docker exec -i "$DB" pg_restore -U kogo -d kogo_research --clean --if-exists --no-owner --role=kogo_app < "$DUMP"
[ -z "$API" ] || docker start "$API"
```

If `pg_restore` fails, the script stops and leaves `api` stopped; fix the problem and run `docker start` for the `api` container (or redeploy) yourself.

Copy the dumps off the server (S3, another machine) and test a restore once before the field study. A raw copy of the `kogo_pg_data` volume is only consistent when the `db` container is stopped.

**Option B (Coolify PostgreSQL resource)** - enable *Backups* on the database resource (cron schedule + S3 storage) and test a restore once before the field study.

Also export the CSVs after each field-test day as an extra, human-readable copy.

---

## 10. Updates and migrations

- Push to the deployed branch and click **Redeploy** (or enable auto-deploy via webhook).
- Migrations in `backend/migrations/*.sql` run automatically before the server starts, inside a PostgreSQL advisory lock (safe with overlapping old/new containers during a rolling deploy). Applied files are recorded in `schema_migrations`; never edit an applied migration, add a new numbered file instead.
- Reference data (`materi`, `word_types`, `words`, `reward_tiers`) is re-seeded idempotently from `src/data/vocabulary.json` on every start.
- Keep `RUN_MIGRATIONS_ON_START=true` (the default). The new container then migrates the database before it starts serving requests. Do not move migrations to a Coolify *pre-deployment* command: it runs in the old, still running container (so it applies the old code's migrations) and it is skipped on the first deploy, when no container exists yet.
- If you set `RUN_MIGRATIONS_ON_START=false`, run `node dist/scripts/migrate.js` in the **new** container after every deploy, e.g. as Coolify's *post-deployment* command (with the compose build pack, for the `api` container). Note that the flag also disables the reference data seed and the admin bootstrap (`ADMIN_USERNAME`/`ADMIN_PASSWORD`), because both run in the same startup task as the migrations, and that the new container already serves requests against the old schema until the post-deployment command has finished.
- To run the startup task by hand (idempotent, advisory-locked): locally `docker compose run --rm api node dist/scripts/migrate.js`; on the Coolify host `docker exec "$(docker ps -q --filter "label=com.docker.compose.project=$APP_UUID" --filter label=com.docker.compose.service=api)" node dist/scripts/migrate.js` (`APP_UUID` as in section 9).

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
| Sync returns 403 `DEVICE_PENDING_QUOTA` | The tablet is still `pending` and the request would take its stored sessions + attempts above `PENDING_DEVICE_MAX_ITEMS`. Approve it (section 6); the app keeps the data queued and sends it on the next sync. Nothing is lost. |
| Data from a tablet is dated at the sync time instead of when it was played | The tablet clock was more than `SYNC_MAX_CLOCK_SKEW_HOURS` ahead, so the server clamped those timestamps to its own time and accepted the items (they are not rejected). Already accepted items keep the clamped time. Turn on automatic date & time on the tablet so that new data carries the correct time. |
| Sync rejects items with `INVALID` and a timestamp field named in `detail` (e.g. `createdAt: ...`) | The timestamp uses a UTC offset beyond +/-15:59, which the app never sends (it always sends UTC). Check which client produced the item. A wrong tablet clock (reset to 1970, or running ahead) does not cause this: such timestamps are clamped to the server time and accepted. |
| Sync returns 401 `DEVICE_NOT_REGISTERED` | The database was reset; the app must call `/v2/devices/register` again. |
| Image build hits Docker Hub `429 Too Many Requests` | Log Coolify's server in to Docker Hub or retry later; the build only needs `node:22-alpine` and `postgres:16-alpine`. |

---

## 13. Field test checklist

1. **Server ready.** `GET /api/health/ready` returns 200, the admin can log in (section 6), the smoke test passed (section 7) and the nightly backup runs (section 9).
2. **APK.** The release APK talks to `https://be-kogo.taro.web.id/api` by default. For another server, build with `--dart-define=KOGO_BACKEND_URL=https://<host>/api` or change the API address on the tablet in Research mode (*Mode Peneliti*, section *Sinkronisasi Server*). Changing the address makes the app send all local data again to the new server (accepted idempotently).
3. **Device approval.** After its first sync each tablet appears as `pending` in `GET /api/v2/research/devices`: approve it and give it a label (section 6). Alternatively set `DEVICE_ENROLLMENT_KEY` on the server and build the APK with `--dart-define=KOGO_ENROLLMENT_KEY=<same value>`; tablets that register with the key are approved automatically. Approve tablets before the field day: a pending tablet stops uploading once a request would exceed `PENDING_DEVICE_MAX_ITEMS` (403 `DEVICE_PENDING_QUOTA`; the data stays queued on the tablet and is sent after approval).
4. **Match tablets to device IDs.** Research mode shows the first 8 characters of the server's device ID and the approval status (approved or waiting for approval). Compare the prefix with `deviceId` in the device list before approving; tap *Sinkronkan Sekarang* to refresh the status after approval.
5. **Clock.** Turn on automatic date & time on every tablet. Timestamps before 2000-01-01 or more than `SYNC_MAX_CLOCK_SKEW_HOURS` in the future are clamped to the sync time, so the data is kept but its date in metrics becomes the sync date.
6. **End of each day.** Sync every tablet until Research mode shows no unsent data, check that `devices.pending` is 0 in `GET /api/v2/research/metrics`, and export both CSVs as an extra copy (section 8 for handling them).

---

## 14. Local development and tests

```bash
cd backend
cp .env.example .env            # set DB_* for your local PostgreSQL and uncomment NODE_ENV=development
npm ci
npm run dev                     # http://127.0.0.1:4000/api/health

npm test                        # build + unit tests (no database needed)
TEST_DATABASE_URL=postgres://postgres:postgres@localhost:5432/kogo_research_test npm run test:integration
npx tsc --noEmit

# Full stack in Docker (same as Coolify)
ADMIN_PASSWORD=$(openssl rand -hex 12); echo "kogo_admin password: $ADMIN_PASSWORD"   # note it: needed to log in
POSTGRES_PASSWORD=$(openssl rand -hex 24) APP_DB_PASSWORD=$(openssl rand -hex 24) JWT_SECRET=$(openssl rand -hex 48) \
  ADMIN_USERNAME=kogo_admin ADMIN_PASSWORD=$ADMIN_PASSWORD docker compose up -d --build
docker compose down -v          # stop and delete local volumes
```

Note the printed admin password: you need it to log in as `kogo_admin`. The database passwords are only applied when the `kogo_pg_data` volume is first created, so run `docker compose down -v` before starting the stack again with new random values.

Without `NODE_ENV=development` the server runs in production mode and refuses to start without a real `JWT_SECRET`. The integration suite refuses to run unless the database name contains `test` (it truncates tables and recreates the `public` schema).
