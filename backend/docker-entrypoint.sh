#!/bin/sh
# Kogo Belajar backend entrypoint.
#  - With arguments: run them as-is (e.g. `docker compose run api node dist/scripts/check_db.js`).
#  - Without arguments: run migrations + reference seed + admin bootstrap (unless
#    RUN_MIGRATIONS_ON_START is false), then `exec` the server so Node is PID 1 and
#    receives SIGTERM directly for a graceful shutdown.
set -e

if [ "$#" -gt 0 ]; then
  exec "$@"
fi

case "$(printf '%s' "${RUN_MIGRATIONS_ON_START:-true}" | tr '[:upper:]' '[:lower:]')" in
  false|0|no|off)
    echo "[entrypoint] RUN_MIGRATIONS_ON_START=false: skipping migrations."
    ;;
  *)
    echo "[entrypoint] Running migrations, reference data seed and admin bootstrap..."
    node dist/scripts/migrate.js
    # Already done above; the server process must not repeat it.
    export RUN_MIGRATIONS_ON_START=false
    ;;
esac

echo "[entrypoint] Starting API server..."
exec node dist/index.js
