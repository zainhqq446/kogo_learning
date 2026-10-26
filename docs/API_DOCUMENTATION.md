# Kogo Belajar Backend - API Reference

Backend for the **Kogo Belajar** Android app (Indonesian word pronunciation practice for children aged 5-6 with voice recognition). The app is **offline-first** (SQLite on the device); this backend only:

1. receives research data for the thesis field test (`POST /api/v2/sync`),
2. proxies optional premium text-to-speech / speech-to-text to ElevenLabs,
3. serves researcher metrics and CSV exports.

Deployment: see [DEPLOYMENT_COOLIFY.md](./DEPLOYMENT_COOLIFY.md).

---

## 1. Conventions

| Item | Value |
| :--- | :--- |
| Production base URL | `https://be-kogo.taro.web.id/api` |
| Local base URL | `http://localhost:4000/api` (Android emulator: `http://10.0.2.2:4000/api`) |
| Content type | `application/json` (except audio and CSV responses) |
| JSON body limit | 1 MB (STT route: `MAX_AUDIO_UPLOAD_BYTES`, default 2 MB) |
| Timestamps | ISO 8601 **with timezone** (`Z` or `+HH:MM`/`-HH:MM`), e.g. `2026-10-25T08:00:00.000Z`. In Dart use `DateTime.now().toUtc().toIso8601String()`. Timestamps without `Z`/offset are rejected. Device timestamps sent to `POST /api/v2/sync` follow extra rules (section 5.2). |
| UUIDs | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` (hex, case-insensitive; stored lower-case). Use UUID v4 on the device. |

### Success envelope

```json
{ "status": "success", "data": { } }
```

### Error envelope

```json
{
  "status": "error",
  "statusCode": 400,
  "code": "VALIDATION_ERROR",
  "message": "Validation failed",
  "errors": [{ "path": "learners.0.age", "message": "age must be 5 or 6" }]
}
```

Clients should branch on `code`, not on `message` (messages may be Indonesian or English). Stack traces and raw database errors are never returned.

| HTTP | `code` | Meaning |
| :---: | :--- | :--- |
| 400 | `VALIDATION_ERROR`, `INVALID_JSON`, `INVALID_INPUT`, `CONSTRAINT_VIOLATION`, `BAD_REQUEST` | Invalid request (strings containing NUL / U+0000 are rejected as `VALIDATION_ERROR` or `INVALID_INPUT`, never 500) |
| 400 | `VOICE_NOT_ALLOWED`, `MODEL_NOT_ALLOWED` | Requested ElevenLabs voice/model is not in the server allowlist |
| 401 | `UNAUTHORIZED`, `INVALID_TOKEN`, `TOKEN_EXPIRED` | Missing/invalid token or wrong token type |
| 401 | `INVALID_CREDENTIALS` | Login failed (same response for unknown user, wrong password, inactive account) |
| 401 | `ACCOUNT_DISABLED` | The access token is valid but the account was deactivated or deleted since login |
| 401 | `DEVICE_NOT_REGISTERED` | Device token refers to a device that no longer exists: register again |
| 403 | `FORBIDDEN` | Authenticated but role not allowed |
| 403 | `DEVICE_NOT_APPROVED` | Device is still `pending` (voice proxy only; sync is allowed) |
| 403 | `DEVICE_PENDING_QUOTA` | Sync only: the device is still `pending` and the request would take its stored game sessions + answer attempts above `PENDING_DEVICE_MAX_ITEMS` (default 20000). Nothing from the request is stored; keep the data queued and retry after a researcher approves the device |
| 403 | `DEVICE_REVOKED` | A researcher revoked this device (sync, voice and re-registration refused) |
| 403 | `ENROLLMENT_REQUIRED` | `DEVICE_ENROLLMENT_KEY` is configured and the `X-Enrollment-Key` header is missing or wrong |
| 404 | `NOT_FOUND` | Unknown route or resource |
| 409 | `DEVICE_PROOF_REQUIRED` | Re-registration of a known `deviceUuid` without `deviceSecret` or a valid device token |
| 409 | `USERNAME_TAKEN`, `PARTICIPANT_EXISTS`, `DUPLICATE_RESOURCE`, `INVALID_REFERENCE`, `CONFLICT` | Conflict |
| 413 | `PAYLOAD_TOO_LARGE` | Body larger than the limit |
| 415 | `UNSUPPORTED_MEDIA_TYPE` | Unsupported audio type / encoding |
| 429 | `RATE_LIMITED` | Too many requests (see `RateLimit` / `RateLimit-Policy` headers) |
| 500 | `INTERNAL_ERROR` | Unexpected server error |
| 502/504 | `UPSTREAM_ERROR`, `UPSTREAM_TIMEOUT` | ElevenLabs failed or timed out |
| 503 | `NOT_CONFIGURED`, `UPSTREAM_RATE_LIMITED`, `SERVICE_UNAVAILABLE` | Feature not configured / provider busy |
| 503 | `VOICE_BUDGET_EXHAUSTED` | Daily ElevenLabs budget used up: fall back to on-device speech until the next UTC day |

---

## 2. Authentication

All tokens are JWT signed with **HS256 only** and sent as `Authorization: Bearer <token>`.

| Token | Obtained from | `tokenType` | Lifetime | Accepted by |
| :--- | :--- | :--- | :--- | :--- |
| Device token | `POST /api/v2/devices/register` | `device` (`role: "device"`, `sub` = `deviceId`, the server's internal id) | `DEVICE_TOKEN_TTL` (default 180 days) | `/api/v2/sync`; `/api/voice/*` once the device is approved |
| Access token | `POST /api/auth/login` | `access` | `JWT_EXPIRES_IN` (default 15 min) | `/api/auth/me`, `/api/v2/research/*`, `/api/research/*`, `/api/voice/*` (staff roles only) |
| Refresh token | `POST /api/auth/login` | `refresh` | `JWT_REFRESH_EXPIRES_IN` (default 7 days) | **Never accepted as an access token** (no refresh endpoint yet: log in again) |

Roles: `admin`, `researcher`, `teacher` (staff) and `child`, `student`.

- There is **no public registration**. The first admin is created at startup from `ADMIN_USERNAME` / `ADMIN_PASSWORD`; an admin creates `researcher`/`teacher` accounts, and staff create `child`/`student` accounts, through `POST /api/auth/register` with an access token. The v2 app does not use user accounts at all (devices + learners).
- Account status is checked on **every** request: a deactivated or deleted account gets `401 ACCOUNT_DISABLED` immediately and a role change applies immediately (the JWT role is not trusted on its own).
- Device tokens are bound to the server-side device id. The app's random `deviceUuid` plus the `deviceSecret` returned by the first registration are the device's credentials: keep both private (do not derive the UUID from hardware IDs, do not show either in the UI). Neither is ever put into tokens or exports.

### Rate limits

| Route group | Limit | Key |
| :--- | :--- | :--- |
| `POST /auth/login`, `/auth/register`, `/auth/register/child` | 10 / 15 min | client IP |
| `POST /v2/devices/register` | 20 / hour | client IP |
| `POST /v2/sync`, `POST /research/sync/batch` | 60 / min | device (or user) |
| `/voice/*` | 120 / min (checked before authentication) | client IP |
| `/voice/tts`, `/voice/stt` (and aliases) | 60 / min | device (or user) |

The client IP is taken from `X-Forwarded-For` only when the direct peer is on a private network (`TRUST_PROXY` default `loopback, linklocal, uniquelocal` = Coolify's Traefik on the Docker network). A client that reaches the container directly cannot spoof its IP.

---

## 3. Endpoint summary

| Method | Path | Auth | Description |
| :---: | :--- | :--- | :--- |
| GET | `/api/health` | public | Liveness (no database, no secrets) |
| GET | `/api/health/ready` | public | Readiness: 200 if PostgreSQL is reachable, else 503 |
| POST | `/api/v2/devices/register` | public (rate limited); known devices need `deviceSecret` or their device token | Register device, get device token |
| POST | `/api/v2/sync` | device token | Upload learners, game sessions and answer attempts |
| GET | `/api/v2/research/metrics` | admin, researcher | Thesis metrics (overall / per learner / per materi / per game) |
| GET | `/api/v2/research/export/attempts.csv` | admin, researcher | CSV export of answer attempts |
| GET | `/api/v2/research/export/sessions.csv` | admin, researcher | CSV export of game sessions |
| GET | `/api/v2/research/devices` | admin, researcher | List devices with status and data counts |
| POST | `/api/v2/research/devices/:deviceId/approve` | admin, researcher | Approve (or un-revoke) a device, optional `label` |
| POST | `/api/v2/research/devices/:deviceId/revoke` | admin, researcher | Revoke a device |
| POST | `/api/v2/research/devices/:deviceId/reset-credential` | admin, researcher | Let a device that lost its `deviceSecret` claim a new one once |
| GET | `/api/voice/status` | staff access token or approved device | ElevenLabs proxy configuration |
| POST | `/api/voice/tts` (alias `/api/voice/synthesize`) | staff access token or approved device | Text-to-speech (MP3) |
| POST | `/api/voice/stt` (alias `/api/voice/transcribe`) | staff access token or approved device | Speech-to-text |
| POST | `/api/auth/login` | public (rate limited) | Staff/child login |
| POST | `/api/auth/register` | access token: admin (any role), researcher/teacher (child/student only) | Create account |
| POST | `/api/auth/register/child` | access token: admin, researcher, teacher | Create child account |
| GET | `/api/auth/me` | access token | Current user profile |
| POST | `/api/auth/logout` | access token | Stateless logout (client deletes tokens) |
| * | `/api/research/*` | access token + role | Legacy v1 research API (section 8) |

---

## 4. Health

### `GET /api/health`

```json
{ "status": "ok", "service": "kogo-voice-learning-backend", "version": "2.0.0", "timestamp": "2026-10-25T08:00:00.000Z", "uptimeSeconds": 42 }
```

Always 200 while the process serves HTTP. Used by the Docker `HEALTHCHECK`.

### `GET /api/health/ready`

- 200 `{ "status": "ready", "checks": { "database": "up" }, "latencyMs": 3, ... }`
- 503 `{ "status": "not_ready", "checks": { "database": "down" }, ... }` (details only in server logs)

---

## 5. API v2 (used by the Flutter app)

### 5.1 `POST /api/v2/devices/register`

Request:

```json
{
  "deviceUuid": "3f1c9a2e-5b7d-4c8e-9f0a-1b2c3d4e5f60",
  "platform": "android",
  "appVersion": "2.0.0+12",
  "model": "SM-T225",
  "deviceSecret": "only when re-registering (value from the first response)"
}
```

| Field / header | Rules |
| :--- | :--- |
| `deviceUuid` | random UUID v4 generated once by the app and stored privately |
| `platform` | must be `"android"` |
| `appVersion` | 1-32 chars |
| `model` | optional, max 64 chars |
| `deviceSecret` | optional; required to re-register a known `deviceUuid` unless a valid device token is sent |
| `Authorization: Bearer <deviceToken>` | optional; a still-valid token of the same device also proves ownership (token refresh) |
| `X-Enrollment-Key` | required for **new** devices only when the server sets `DEVICE_ENROLLMENT_KEY` |

Responses:

- **201** new device. `deviceSecret` is returned **once**: store it next to the `deviceUuid` (e.g. Android encrypted shared preferences) and never log or display it.

  ```json
  { "status": "success", "data": { "deviceToken": "eyJhbGciOiJIUzI1NiIs...", "expiresIn": 15552000,
                                   "deviceSecret": "q3Jx...43 chars...", "approved": false } }
  ```

- **200** known device with proof of ownership: new token (app version / model updated). `deviceSecret` is only included when the device had none (registered before this version, or after a researcher's `reset-credential`).
- **409 `DEVICE_PROOF_REQUIRED`** known `deviceUuid` without a matching `deviceSecret` or device token. The `deviceUuid` alone is not a credential, so a leaked UUID cannot be used to impersonate the tablet.
- **403 `DEVICE_REVOKED`** the device was revoked by a researcher. **403 `ENROLLMENT_REQUIRED`** see `X-Enrollment-Key`.

`approved`: without `DEVICE_ENROLLMENT_KEY` new devices start as **pending**. They can sync (data is stored, up to `PENDING_DEVICE_MAX_ITEMS` game sessions + answer attempts, see section 5.2) but their data is excluded from metrics/exports by default and they cannot use the voice proxy until a researcher approves them (section 5.5). Devices registered with a valid enrollment key are approved immediately.

`expiresIn` is in seconds. Re-register (sending `deviceSecret`, or the current token as `Authorization`) when the token is close to expiry or when a call returns `401` (`TOKEN_EXPIRED`, `INVALID_TOKEN`, `DEVICE_NOT_REGISTERED`). On `409 DEVICE_PROOF_REQUIRED` ask the researcher to run `reset-credential` for this device.

### 5.2 `POST /api/v2/sync`

Header: `Authorization: Bearer <deviceToken>`.

```json
{
  "learners": [
    { "clientUuid": "uuid", "name": "Ani", "school": "TK Pelita", "age": 5,
      "createdAt": "2026-10-25T01:00:00.000Z", "updatedAt": "2026-10-25T01:00:00.000Z" }
  ],
  "sessions": [
    { "clientUuid": "uuid", "learnerUuid": "uuid", "materi": "two-syllable", "nodeIndex": 3,
      "gameType": "speaking", "status": "completed", "totalItems": 4, "firstTryCorrect": 3, "stars": 2,
      "startedAt": "2026-10-25T01:00:00.000Z", "endedAt": "2026-10-25T01:03:10.000Z" }
  ],
  "attempts": [
    { "clientUuid": "uuid", "sessionUuid": "uuid", "learnerUuid": "uuid", "gameType": "speaking",
      "targetText": "bola", "answerText": "bola", "isCorrect": true, "attemptNumber": 1,
      "similarity": 1.0, "responseMs": 1450, "sttError": null, "createdAt": "2026-10-25T01:00:20.000Z" }
  ]
}
```

| Array | Max items | Item rules |
| :--- | :---: | :--- |
| `learners` | 50 | `name` 2-40, `school` 2-60, `age` 5 or 6 |
| `sessions` | 200 | `materi` in `letters`, `two-syllable`, `three-syllable`, `multiple`; `gameType` in `speaking`, `find-object`, `missing-letter`, `matching`, `listening`, `fill-blank`; `status` in `started`, `completed`, `abandoned`; `nodeIndex` >= 0; `totalItems` 0-20; `firstTryCorrect` 0-20 and <= `totalItems`; `stars` 0-3; `endedAt` ISO or `null` |
| `attempts` | 1000 | `targetText` 1-60, `answerText` 0-200, `attemptNumber` >= 1, `similarity` 0-1 or `null`, `responseMs` >= 0 or `null`, `sttError` <= 40 chars or `null` |

All arrays are optional. More items than the maximum -> **400** for the whole request (split into several requests). Strings must not contain NUL (U+0000).

Device timestamps (`createdAt`, `updatedAt`, `startedAt`, `endedAt`) come from the tablet clock:

- The offset must be `Z` or between `-15:59` and `+15:59` (the range PostgreSQL can store). Otherwise the item is rejected as `INVALID` (`detail` names the field); the rest of the request is still processed. The app always sends UTC (`Z`).
- A timestamp that can only come from a wrong tablet clock, either before `2000-01-01T00:00:00Z` (e.g. a clock reset to 1970 after the battery ran flat) or more than `SYNC_MAX_CLOCK_SKEW_HOURS` (default 24 h) in the future, is **clamped** to the server's current time and the item is accepted. A wrong clock therefore never causes data loss, but the clamped fields carry the sync time, so date filters in metrics and exports count those items on the day they were synced.
- Because each field is clamped on its own, a session whose `endedAt` would end up before `startedAt` is stored with `endedAt = startedAt`.
- Any other timestamp (from 2000-01-01 up to the skew limit) is stored as sent.

Semantics:

- One database transaction per request; idempotent upserts keyed by `clientUuid`. Re-sending the same payload never creates duplicates.
- Ownership: every learner/session/attempt belongs to the device that first synced it. Items owned by another device are **rejected**, never overwritten.
- Learners: insert, or update `name`/`school`/`age`/`updatedAt`. Every update from the owning device is applied (the device's SQLite is the source of truth; the result does not depend on the tablet clock).
- Sessions: insert, or update `status`/totals/`stars`/`endedAt`. Status never goes backwards (`started` < `abandoned` < `completed`): a `completed` session stays completed, and its results (`totalItems`, `firstTryCorrect`, `stars`, `endedAt`) are final once completed.
- Attempts: insert-only.
- `accepted` counts distinct `clientUuid`s; a duplicate inside one request is stored and counted once.
- Pending (unapproved) devices can sync until they have stored `PENDING_DEVICE_MAX_ITEMS` (default 20000) game sessions + answer attempts in total. A request that would go above the limit is refused as a whole with **403 `DEVICE_PENDING_QUOTA`** and nothing is written. Learners and re-sent items that are already stored do not count. The app keeps the data queued and sends it after a researcher approves the device; approved devices have no limit. This bounds what an unknown device can store through the open registration.
- Revoked devices get **403 `DEVICE_REVOKED`** for the whole request.
- A session's `learnerUuid` and an attempt's `sessionUuid`/`learnerUuid` must exist in the database (synced earlier by this device) or be accepted in the same request.
- After sessions are processed the server maintains `stars` (best stars per learner + materi + node, from `completed` sessions only) and `rewards` (Perunggu 10, Perak 50, Emas 150, Berlian 300 total stars; `earned_at` = first time reached).

Response **200** (also when some items were rejected):

```json
{
  "status": "success",
  "data": {
    "accepted": { "learners": 1, "sessions": 1, "attempts": 1 },
    "rejected": [
      { "type": "attempt", "clientUuid": "uuid", "code": "UNKNOWN_SESSION" },
      { "type": "learner", "clientUuid": "uuid", "code": "INVALID", "detail": "age: age must be 5 or 6" }
    ]
  }
}
```

| Rejection `code` | Meaning | Suggested client action |
| :--- | :--- | :--- |
| `UNKNOWN_LEARNER` | Referenced learner not found / rejected | Send the learner first (or in the same request) |
| `UNKNOWN_SESSION` | Referenced session not found / rejected | Send the session first (or in the same request) |
| `FOREIGN_DEVICE` | UUID belongs to another device | Do not retry; regenerate UUIDs if this is a copy |
| `INVALID` | Item failed validation (`detail` explains), e.g. a UTC offset beyond +/-15:59 or a name with forbidden characters | Fix or drop the item; retrying unchanged will fail again |

Mark an item as synced when it is not listed in `rejected` (accepted items include unchanged duplicates). When the whole request fails (error envelope instead of 200, e.g. `401`, `403 DEVICE_REVOKED`, `403 DEVICE_PENDING_QUOTA`, `429 RATE_LIMITED`, `5xx`), nothing was stored: keep every item queued.

### 5.3 `GET /api/v2/research/metrics`

Role `admin` or `researcher`. Query (all optional; an empty value such as `?from=` means "no filter"):

| Param | Meaning |
| :--- | :--- |
| `learnerUuid` | one learner |
| `from`, `to` | `YYYY-MM-DD` or ISO datetime with offset; both inclusive. A date-only `from` starts at 00:00 UTC; a date-only `to` covers the whole UTC day. The two forms can be mixed, e.g. a datetime `from` with a date-only `to`: `from=2026-10-25T08:00:00%2B07:00&to=2026-10-25` runs from 08:00 WIB to the end of 25 October (UTC). `from` later than the end of `to` -> 400 `VALIDATION_ERROR`. URL-encode `+` in offsets as `%2B` (a literal `+` in a query string is read as a space). To filter by local days in Indonesia, use datetimes with `%2B07:00`. Sessions are filtered by `startedAt`, attempts by `createdAt`. |
| `devices` | `approved` (default): only data from devices approved by a researcher. `all`: also pending devices (to review data before approving). Revoked devices are always excluded. |

```json
{
  "status": "success",
  "data": {
    "overall": { "sttAttempts": 16, "sttCorrect": 10, "sttAccuracy": 62.5, "sttErrors": 2, "errorRate": 40,
                 "errorRatePerAttempt": 12.5, "avgResponseMs": 1680, "sessionsStarted": 5, "sessionsCompleted": 3,
                 "taskCompletion": 60, "totalStars": 6 },
    "perLearner": [ { "learnerUuid": "uuid", "name": "Ani", "school": "TK Pelita", "age": 5, "sttAttempts": 12, "...": "..." } ],
    "perMateri": [ { "materi": "letters", "...": "..." } ],
    "perGame": [ { "gameType": "speaking", "...": "..." } ],
    "targets": { "sttAccuracyMinPercent": 70, "taskCompletionMinPercent": 75, "responseTimeMaxMs": 3000, "errorRateMaxPercent": 10 },
    "deviceFilter": "approved",
    "devices": { "approved": 1, "pending": 0, "revoked": 0 }
  }
}
```

If `overall` is all zeros right after the field test started, check `devices.pending`: the tablet has synced but has not been approved yet.

Metric definitions (thesis Table 3.1). Percentages have 2 decimals; `null` when the denominator is 0. All values are JSON numbers.

| Field | Formula |
| :--- | :--- |
| `sttAttempts` | number of attempts with `gameType = speaking` |
| `sttCorrect` | speaking attempts with `isCorrect = true` |
| `sttAccuracy` | `sttCorrect / sttAttempts x 100` (target >= 70%) |
| `sttErrors` | speaking attempts with `sttError` not null |
| `errorRate` | (sessions with >= 1 STT error / `sessionsStarted`) x 100. This is the thesis "System Error Rate" of Table 3.1, `(Error / Total Sesi) x 100%`, target <= 10%. The app's on-device research page (Research mode) shows the same per-session formula, so the app and the server report comparable values |
| `errorRatePerAttempt` | `sttErrors / sttAttempts x 100`. Supplementary per-attempt diagnostic only; it is **not** the Table 3.1 metric and is not what the app shows. Report `errorRate` for Table 3.1 |
| `avgResponseMs` | mean `responseMs` of speaking attempts, rounded (target <= 3000 ms) |
| `sessionsStarted` | all sessions (any status) |
| `sessionsCompleted` | sessions with status `completed` |
| `taskCompletion` | `sessionsCompleted / sessionsStarted x 100` (target >= 75%) |
| `totalStars` | sum of best stars per learner + materi + node from completed sessions |

`perLearner` lists every learner (zeros when inactive in the period); `perMateri` and `perGame` always list all codes in curriculum order. Every call is written to `audit_logs`.

### 5.4 CSV exports

`GET /api/v2/research/export/attempts.csv` and `GET /api/v2/research/export/sessions.csv` (role `admin` or `researcher`, same query filters as metrics).

- `Content-Type: text/csv; charset=utf-8`, `Content-Disposition: attachment; filename="kogo-attempts-YYYYMMDD-HHMMSS.csv"`.
- UTF-8 BOM (Excel friendly), header row, CRLF line endings, RFC 4180 quoting.
- Formula-injection guard: text cells starting with `=`, `+`, `-`, `@`, tab or CR are prefixed with `'`. The same characters directly after a `;` are neutralised as well (`x;=1+1;y` is exported as `x;'=1+1;y`), because Excel with an Indonesian or other European locale uses `;` as the column separator and would otherwise turn that segment into a formula cell.

- Streamed in batches of 2000 rows (keyset pagination), so large exports never load fully into memory. If the database fails mid-export the connection is aborted (a truncated download never looks like a complete file). Every export is written to `audit_logs` with the row count.

Columns (`device_id` is the server's internal device id and `device_label` the researcher's label; the `deviceUuid` credential is never exported):

- attempts: `attempt_uuid, session_uuid, learner_uuid, learner_name, school, age, device_id, device_label, materi, node_index, game_type, target_text, answer_text, is_correct, attempt_number, similarity, response_ms, stt_error, created_at, synced_at`
- sessions: `session_uuid, learner_uuid, learner_name, school, age, device_id, device_label, materi, node_index, game_type, status, total_items, first_try_correct, stars, started_at, ended_at, duration_seconds, synced_at`

The exports contain children's names and schools: store downloaded files securely and delete them when the study's retention period ends.

### 5.5 Device management (researcher)

Role `admin` or `researcher`. All actions are written to `audit_logs`.

`GET /api/v2/research/devices`

```json
{ "status": "success", "count": 1, "data": [
  { "deviceId": "uuid", "label": null, "platform": "android", "appVersion": "2.0.0", "model": "SM-T225",
    "status": "pending", "createdAt": "...", "lastSeenAt": "...", "approvedAt": null, "revokedAt": null,
    "learners": 3, "sessions": 12, "attempts": 140 } ] }
```

| Endpoint | Effect |
| :--- | :--- |
| `POST /api/v2/research/devices/:deviceId/approve` body `{ "label": "Tablet TK Pelita" }` (optional) | `status` -> `approved`; clears a revocation. Its data now counts in metrics/exports and it may use the voice proxy. |
| `POST /api/v2/research/devices/:deviceId/revoke` | `status` -> `revoked`: sync, voice and re-registration return 403 `DEVICE_REVOKED`; its data is excluded from metrics/exports. Approve again to undo. |
| `POST /api/v2/research/devices/:deviceId/reset-credential` | Clears the stored `deviceSecret` hash: the next registration with that `deviceUuid` succeeds without proof and receives a new `deviceSecret` (once). Use it when a tablet lost its secret/token (e.g. after `JWT_SECRET` was rotated). |

---

## 6. Voice proxy (ElevenLabs, optional)

Requires either the access token of an active **staff** account (`admin`, `researcher`, `teacher`; child/student accounts get 403) or the device token of an **approved, non-revoked** device (pending -> 403 `DEVICE_NOT_APPROVED`, revoked -> 403 `DEVICE_REVOKED`, deleted -> 401 `DEVICE_NOT_REGISTERED`). When `ELEVENLABS_API_KEY` (and for TTS `ELEVENLABS_DEFAULT_VOICE_ID`) is not configured the endpoints return **503 `NOT_CONFIGURED`**; the app should fall back to on-device TTS/STT.

Cost controls (spend is bounded even if a device token leaks):

- rate limits per client IP (120/min, before authentication) and per device/user (60/min);
- daily budgets stored in PostgreSQL (UTC day): `ELEVENLABS_DAILY_CHAR_BUDGET` characters sent to TTS on cache misses (default 20000) and `ELEVENLABS_DAILY_STT_SECONDS_BUDGET` seconds of STT audio (default 1800). When exhausted: **503 `VOICE_BUDGET_EXHAUSTED`**. Cache hits are free;
- the disk cache is capped at `TTS_CACHE_MAX_MB` (default 256 MB, least recently used files are removed).

### `GET /api/voice/status`

```json
{ "status": "success", "configured": false, "ttsConfigured": false, "sttConfigured": false, "defaultVoiceId": null,
  "defaultModelId": "eleven_multilingual_v2", "sttModelId": "scribe_v2", "allowedVoiceIds": [], "allowedModelIds": ["eleven_multilingual_v2"],
  "languageCode": "id", "maxTextLength": 300, "maxAudioUploadBytes": 2097152,
  "dailyTtsCharBudget": 20000, "dailySttSecondsBudget": 1800,
  "moods": ["excited", "celebratory", "playful", "curious", "warm", "encouraging", "gentle", "patient"] }
```

### `POST /api/voice/tts` (alias `/api/voice/synthesize`)

```json
{ "text": "Hebat! Kamu berhasil!", "mood": "celebratory" }
```

| Field | Rules |
| :--- | :--- |
| `text` | 1-300 characters (`TTS_MAX_TEXT_LENGTH`) |
| `mood` | optional: `excited`, `celebratory`, `playful`, `curious`, `warm`, `encouraging`, `gentle`, `patient` |
| `voiceId`, `modelId` | optional; must be in `ELEVENLABS_ALLOWED_VOICE_IDS` / `ELEVENLABS_ALLOWED_MODEL_IDS` (the defaults are always allowed), otherwise 400 |
| `settings` | optional overrides `{ stability 0-1, similarityBoost 0-1, style 0-1, speed 0.7-1.2, useSpeakerBoost }` (win over `mood`). Values are snapped to steps of 0.1 (speed 0.05) so tiny variations cannot force paid cache misses. Prefer `mood`. |

Moods map to ElevenLabs `voice_settings` for intonation variety (default stability 0.45 / style 0.40 / speed 0.95):

| Mood | stability | style | speed |
| :--- | :---: | :---: | :---: |
| excited, celebratory | 0.30 | 0.60 | 1.00 |
| playful | 0.35 | 0.55 | 1.00 |
| curious | 0.40 | 0.50 | 0.97 |
| encouraging | 0.45 | 0.45 | 0.97 |
| warm | 0.50 | 0.35 | 0.95 |
| gentle | 0.60 | 0.20 | 0.92 |
| patient | 0.60 | 0.20 | 0.90 |

Response 200: `audio/mpeg` (`mp3_22050_32`), headers `Cache-Control: private, max-age=86400` and `X-Cache: HIT|MISS`. Audio is cached on disk (`TTS_CACHE_DIR`) by `sha256(text|voice|model|settings|language|format)`, so repeated phrases cost no ElevenLabs credits. `language_code=id` is sent for models that support it (Flash/Turbo v2.5, v3); `eleven_multilingual_v2` detects Indonesian from the text. `apply_text_normalization` is `auto` by default.

### `POST /api/voice/stt` (alias `/api/voice/transcribe`)

Either raw audio (`Content-Type: audio/wav`, `audio/mp4`, `audio/mpeg`, `audio/ogg`, `audio/webm`, `application/octet-stream`, ...) or JSON:

```json
{ "audioBase64": "UklGR...", "mimeType": "audio/wav", "languageCode": "id" }
```

Maximum decoded size: `MAX_AUDIO_UPLOAD_BYTES` (2 MB) -> 413 above. Model `ELEVENLABS_STT_MODEL_ID` (default `scribe_v2`), language `id`. Before uploading, the server reserves a conservative estimate of the audio length (size / 2000 bytes per second) from the daily STT budget and settles it to the duration ElevenLabs reports. Send short clips (one word = a few seconds of 16 kHz mono WAV or AAC).

```json
{ "status": "success", "data": { "text": "bola", "languageCode": "ind", "durationSecs": 1.2, "words": [] } }
```

---

## 7. Auth endpoints

### `POST /api/auth/login`

```json
{ "username": "peneliti", "password": "..." }
```

200:

```json
{ "status": "success", "message": "Login berhasil",
  "data": { "user": { "id": "uuid", "username": "peneliti", "fullName": "...", "role": "researcher", "isActive": true, "createdAt": "..." },
            "tokens": { "accessToken": "...", "refreshToken": "...", "expiresIn": "15m" } } }
```

401 `INVALID_CREDENTIALS` with the same message (`Username atau kata sandi tidak cocok.`) and similar timing for unknown users, wrong passwords and inactive accounts.

### `POST /api/auth/register`

Requires an access token (no public registration, so the endpoint cannot be used to enumerate usernames or participant codes):

- `admin`: may create any role (`admin`, `researcher`, `teacher`, `child`, `student`).
- `researcher`, `teacher`: may create `child` (default) or `student` only; staff roles -> **403**.
- Without a token -> **401**; with a `child`/`student` token -> **403**.

```json
{ "username": "ani_5", "password": "min6chars", "fullName": "Ani", "ageYears": 5, "schoolName": "TK Pelita", "role": "child" }
```

201 with the profile. 409 `USERNAME_TAKEN`; for children a pseudonymous participant (`participant_code` = upper-case username) is created and an existing participant is never taken over (409 `PARTICIPANT_EXISTS`).

### `POST /api/auth/register/child`

Staff access token required (`admin`, `researcher`, `teacher`). Same body as above with required `ageYears` and `schoolName`; role is always `child`.

### `GET /api/auth/me` / `POST /api/auth/logout`

Access token required. Logout is stateless (delete the tokens on the client).

---

## 8. Legacy research API (`/api/research/*`, v1)

Kept for backward compatibility with the previous app; the new app uses `/api/v2`. All routes require a user **access token** and the listed role.

| Method | Path | Roles |
| :---: | :--- | :--- |
| GET | `/participants` | admin, researcher, teacher |
| POST | `/participants` | admin, researcher (409 `PARTICIPANT_EXISTS` on duplicates) |
| POST | `/participants/batch` | admin, researcher (1-200 items) |
| GET | `/participants/:code` | admin, researcher, teacher |
| GET | `/devices` | admin, researcher |
| POST | `/devices` | admin, researcher, teacher |
| GET | `/sessions?limit=1..500&offset=0..` | admin, researcher, teacher |
| POST | `/sessions` | admin, researcher, teacher |
| GET | `/attempts?sessionId=uuid&limit=&offset=` | admin, researcher |
| POST | `/attempts` | admin, researcher, teacher |
| GET | `/summary` | admin, researcher |
| POST | `/sync/batch` | admin, researcher, teacher (max 200 sessions, 1000 attempts) |

Invalid `limit`/`offset`/`sessionId` return 400. Per-item errors in `/sync/batch` contain safe messages only. Legacy attempts reference the legacy curriculum (`questions`); seed it manually with `npm run db:seed:curriculum` if you still need these routes.

---

## 9. curl quick reference

```bash
BASE=https://be-kogo.taro.web.id/api
uuid() { cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || python3 -c 'import uuid;print(uuid.uuid4())'; }

curl -s $BASE/health
curl -s -o /dev/null -w '%{http_code}\n' $BASE/health/ready

# Device registration (save deviceSecret!) + sync. Use fresh UUIDs: a known deviceUuid needs its deviceSecret (409).
curl -s -X POST $BASE/v2/devices/register -H 'Content-Type: application/json' \
  -d "{\"deviceUuid\":\"$(uuid)\",\"platform\":\"android\",\"appVersion\":\"2.0.0\"}" > reg.json
DEVICE_TOKEN=$(python3 -c 'import json;print(json.load(open("reg.json"))["data"]["deviceToken"])')
DEVICE_ID=$(python3 -c 'import json,base64;t=json.load(open("reg.json"))["data"]["deviceToken"].split(".")[1];print(json.loads(base64.urlsafe_b64decode(t+"=="))["deviceId"])')
curl -s -X POST $BASE/v2/sync -H "Authorization: Bearer $DEVICE_TOKEN" -H 'Content-Type: application/json' \
  -d "{\"learners\":[{\"clientUuid\":\"$(uuid)\",\"name\":\"Ani\",\"school\":\"TK Pelita\",\"age\":5,\"createdAt\":\"2026-10-25T01:00:00.000Z\",\"updatedAt\":\"2026-10-25T01:00:00.000Z\"}]}"

# Researcher
ACCESS=$(curl -s -X POST $BASE/auth/login -H 'Content-Type: application/json' \
  -d '{"username":"kogo_admin","password":"<ADMIN_PASSWORD>"}' \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["data"]["tokens"]["accessToken"])')
curl -s "$BASE/v2/research/devices" -H "Authorization: Bearer $ACCESS"
curl -s -X POST "$BASE/v2/research/devices/$DEVICE_ID/approve" -H "Authorization: Bearer $ACCESS" \
  -H 'Content-Type: application/json' -d '{"label":"Tablet TK Pelita"}'
curl -s "$BASE/v2/research/metrics?from=2026-10-01&to=2026-10-31" -H "Authorization: Bearer $ACCESS"
curl -s -OJ "$BASE/v2/research/export/attempts.csv" -H "Authorization: Bearer $ACCESS"

# TTS (needs ElevenLabs configured and an approved device)
curl -s -X POST $BASE/voice/tts -H "Authorization: Bearer $DEVICE_TOKEN" -H 'Content-Type: application/json' \
  -d '{"text":"Ayo ucapkan bola!","mood":"encouraging"}' -o bola.mp3
```

---

## 10. Changes in 2.0 (security hardening)

Security review follow-up:

- Device registration: a known `deviceUuid` needs proof of ownership (`deviceSecret` issued once at first registration, or a valid device token); otherwise 409 `DEVICE_PROOF_REQUIRED`. The device token's `sub` is the internal device id, and exports use `device_id`/`device_label`, so the `deviceUuid` credential is never exposed.
- Device trust: new devices are `pending` unless registered with `DEVICE_ENROLLMENT_KEY`. Researchers approve/revoke devices (section 5.5); metrics and exports default to approved devices; revoked devices lose sync, voice and registration immediately.
- Voice proxy: staff accounts or approved devices only (no child accounts), per-IP limit before auth, daily character/second budgets in PostgreSQL, settings snapped to a coarse grid, size-capped cache.
- Account status and role are re-read from the database on every authenticated request.
- No public registration endpoints (account enumeration removed).
- Sync: owning-device learner updates always apply; completed session results are final; duplicates counted once; NUL characters rejected per item (and SQLSTATE 22021/22P05 map to 400).
- Sync timestamps: values before 2000-01-01 or more than `SYNC_MAX_CLOCK_SKEW_HOURS` in the future are clamped to the server time instead of being rejected (a wrong tablet clock no longer makes the app drop data permanently); values with a UTC offset beyond +/-15:59 are rejected per item as `INVALID` instead of failing the whole request.
- Sync quota: a pending device may store at most `PENDING_DEVICE_MAX_ITEMS` (default 20000) sessions + attempts; beyond it the request returns 403 `DEVICE_PENDING_QUOTA` and the app retries after approval.
- Metrics: empty query values are ignored; a datetime `from` can be combined with a date-only `to` (whole day, inclusive); new `errorRatePerAttempt` (supplementary per-attempt diagnostic, not the Table 3.1 metric), `deviceFilter`, `devices`.
- CSV exports are streamed; the formula-injection guard also covers segments after `;`.
- `TRUST_PROXY` defaults to private-network peers only; publicly known JWT secrets are ignored in every environment.

Initial 2.0 changes:

- Voice endpoints now require a token, are rate limited, and only allow server-configured voices/models (they were open proxies to a paid API).
- Public registration was first limited to children and then removed entirely; staff accounts come from the admin bootstrap.
- Refresh tokens are no longer accepted as access tokens; JWTs are pinned to HS256; production refuses to start without a strong `JWT_SECRET`.
- `/api/health` no longer exposes environment or database errors; use `/api/health/ready` for readiness.
- CORS is disabled unless `CORS_ORIGIN` is set; `trust proxy` only trusts private-network peers (Traefik).
- Errors carry a stable `code`; PostgreSQL messages and stack traces are never returned.
- Array sizes and query parameters are validated.
- The out-of-scope 300-word list (`learning_words`) was removed; curriculum reference data comes from `src/data/vocabulary.json`.
