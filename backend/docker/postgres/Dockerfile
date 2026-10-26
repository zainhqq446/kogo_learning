# =============================================================================
# PostgreSQL 16 for Kogo Belajar (docker-compose service "db").
# Same as the official postgres:16-alpine image plus one init script that
# creates a NON-superuser application role (APP_DB_USER) owning the database.
# The API connects with that role, so a compromised API container or a SQL
# injection never gets superuser rights (COPY ... PROGRAM, other databases).
# =============================================================================
FROM postgres:16-alpine

COPY 10-kogo-app-role.sh /docker-entrypoint-initdb.d/10-kogo-app-role.sh
RUN chmod 0755 /docker-entrypoint-initdb.d/10-kogo-app-role.sh
