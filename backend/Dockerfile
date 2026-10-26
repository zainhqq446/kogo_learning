# =============================================================================
# Kogo Belajar backend - production image (Coolify / Docker)
#   build:   docker build -t kogo-backend .
#   run:     docker run --env-file .env -p 127.0.0.1:4000:4000 kogo-backend
# In production run it behind a reverse proxy (Coolify/Traefik terminates TLS).
# X-Forwarded-For is only trusted from private-network peers (TRUST_PROXY
# default), so clients reaching the port directly cannot spoof their IP.
# =============================================================================

ARG NODE_IMAGE=node:22-alpine

# -----------------------------------------------------------------------------
# Stage 1: install all dependencies and compile TypeScript
# -----------------------------------------------------------------------------
FROM ${NODE_IMAGE} AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY tsconfig.json ./
COPY src ./src
COPY migrations ./migrations

# Kompilasi ke dist/ (termasuk dist/data/vocabulary.json), lalu buang test.
RUN npm run build && rm -rf dist/test

# -----------------------------------------------------------------------------
# Stage 2: runtime with production dependencies only
# -----------------------------------------------------------------------------
FROM ${NODE_IMAGE} AS runtime
WORKDIR /app

ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=4000 \
    TTS_CACHE_DIR=/app/data/tts-cache \
    NPM_CONFIG_UPDATE_NOTIFIER=false

COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund && npm cache clean --force

COPY --from=build /app/dist ./dist
COPY migrations ./migrations
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# /app/data: volume untuk cache audio TTS (harus writable oleh user node).
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh \
    && mkdir -p /app/data/tts-cache \
    && chown -R node:node /app/data

USER node

EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD wget -q -O /dev/null "http://127.0.0.1:${PORT:-4000}/api/health" || exit 1

# Entrypoint menjalankan migrasi (RUN_MIGRATIONS_ON_START) lalu `exec node`
# sehingga Node menjadi PID 1 dan menerima SIGTERM untuk graceful shutdown.
ENTRYPOINT ["docker-entrypoint.sh"]
