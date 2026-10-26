#!/bin/sh
# -----------------------------------------------------------------------------
# Creates/updates the least-privilege application role for the Kogo API.
#
# - Runs automatically ONCE, when the postgres data volume is first initialised
#   (official image: /docker-entrypoint-initdb.d).
# - Idempotent: for a volume created before this script existed, run it by hand:
#     docker compose exec db /docker-entrypoint-initdb.d/10-kogo-app-role.sh
#   It creates the role (or resets its password), makes it the owner of the
#   database and of every existing table in the public schema.
#
# Env (from docker-compose.yml): POSTGRES_USER, POSTGRES_DB, APP_DB_USER,
# APP_DB_PASSWORD.
# -----------------------------------------------------------------------------
set -eu

APP_DB_USER="${APP_DB_USER:-kogo_app}"
if [ -z "${APP_DB_PASSWORD:-}" ]; then
  echo "[kogo-initdb] APP_DB_PASSWORD is required to create the application role" >&2
  exit 1
fi
if [ "$APP_DB_USER" = "${POSTGRES_USER:-postgres}" ]; then
  echo "[kogo-initdb] APP_DB_USER must differ from POSTGRES_USER (the superuser)" >&2
  exit 1
fi

echo "[kogo-initdb] Ensuring application role '$APP_DB_USER' (no superuser) owns database '$POSTGRES_DB'"
psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER:-postgres}" --dbname "${POSTGRES_DB:-postgres}" \
  --set=app_user="$APP_DB_USER" --set=app_password="$APP_DB_PASSWORD" --set=db_name="${POSTGRES_DB:-postgres}" <<'EOSQL'
SELECT format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS', :'app_user')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user') \gexec
SELECT format('ALTER ROLE %I WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD %L',
              :'app_user', :'app_password') \gexec
SELECT format('ALTER DATABASE %I OWNER TO %I', :'db_name', :'app_user') \gexec
SELECT format('REVOKE ALL ON DATABASE %I FROM PUBLIC', :'db_name') \gexec
-- Existing volumes: hand over every table (SERIAL sequences and indexes follow).
SELECT format('ALTER TABLE public.%I OWNER TO %I', tablename, :'app_user')
FROM pg_tables WHERE schemaname = 'public' \gexec
EOSQL
