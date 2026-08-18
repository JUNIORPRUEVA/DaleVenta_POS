#!/bin/sh
set -eu

RUN_MIGRATIONS="${RUN_MIGRATIONS:-true}"
PRISMA_SYNC_MODE="${PRISMA_SYNC_MODE:-migrate}"
MIGRATION_MAX_RETRIES="${MIGRATION_MAX_RETRIES:-10}"
MIGRATION_RETRY_DELAY_SECONDS="${MIGRATION_RETRY_DELAY_SECONDS:-5}"
MIGRATION_STRICT="${MIGRATION_STRICT:-false}"
FAILED_MIGRATION_NAME="${FAILED_MIGRATION_NAME:-20260502043000_add_status_history_user_name_and_created_at}"

build_database_url_from_parts() {
  DB_HOST="${1:-}"
  DB_PORT="${2:-5432}"
  DB_NAME="${3:-}"
  DB_USER="${4:-}"
  DB_PASSWORD="${5:-}"
  DB_SCHEMA="${6:-public}"
  DB_SSLMODE="${7:-}"

  if [ -z "$DB_HOST" ] || [ -z "$DB_NAME" ] || [ -z "$DB_USER" ]; then
    return 1
  fi

  node -e '
    const host = process.argv[1];
    const port = process.argv[2] || "5432";
    const db = process.argv[3];
    const user = process.argv[4];
    const password = process.argv[5] ?? "";
    const schema = process.argv[6] || "public";
    const sslmode = process.argv[7] ?? "";
    const auth = `${encodeURIComponent(user)}:${encodeURIComponent(password)}@`;
    const query = new URLSearchParams({ schema });
    if (sslmode) query.set("sslmode", sslmode);
    process.stdout.write(`postgresql://${auth}${host}:${port}/${db}?${query.toString()}`);
  ' "$DB_HOST" "$DB_PORT" "$DB_NAME" "$DB_USER" "$DB_PASSWORD" "$DB_SCHEMA" "$DB_SSLMODE"
}

ensure_database_url() {
  if [ -n "${DATABASE_URL:-}" ]; then
    echo "[startup] DATABASE_URL detected"
    return 0
  fi

  GENERATED_DATABASE_URL=""

  GENERATED_DATABASE_URL="$(build_database_url_from_parts \
    "${POSTGRES_HOST:-${DATABASE_HOST:-}}" \
    "${POSTGRES_PORT:-${DATABASE_PORT:-5432}}" \
    "${POSTGRES_DB:-${DATABASE_NAME:-}}" \
    "${POSTGRES_USER:-${DATABASE_USER:-}}" \
    "${POSTGRES_PASSWORD:-${DATABASE_PASSWORD:-}}" \
    "${POSTGRES_SCHEMA:-${DATABASE_SCHEMA:-public}}" \
    "${POSTGRES_SSLMODE:-${DATABASE_SSLMODE:-}}" || true)"

  if [ -z "$GENERATED_DATABASE_URL" ]; then
    GENERATED_DATABASE_URL="$(build_database_url_from_parts \
      "${PGHOST:-}" \
      "${PGPORT:-5432}" \
      "${PGDATABASE:-}" \
      "${PGUSER:-}" \
      "${PGPASSWORD:-}" \
      "${PGSCHEMA:-public}" \
      "${PGSSLMODE:-}" || true)"
  fi

  if [ -z "$GENERATED_DATABASE_URL" ]; then
    echo "[startup] ERROR: DATABASE_URL is not configured."
    echo "[startup] Define DATABASE_URL directly or provide EasyPanel/PG parts:"
    echo "[startup] POSTGRES_HOST, POSTGRES_PORT, POSTGRES_DB, POSTGRES_USER, POSTGRES_PASSWORD"
    echo "[startup] or PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD"
    exit 1
  fi

  export DATABASE_URL="$GENERATED_DATABASE_URL"
  echo "[startup] DATABASE_URL generated from discrete database env vars"
}

preflight() {
  ensure_database_url

  if [ "${JWT_SECRET:-change-me}" = "change-me" ]; then
    echo "[startup] WARNING: JWT_SECRET is using the default insecure value 'change-me'"
  fi

  if [ "${REDIS_ENABLED:-false}" = "true" ] || [ "${REDIS_ENABLED:-false}" = "1" ]; then
    if [ -z "${REDIS_URL:-}" ]; then
      echo "[startup] WARNING: REDIS_ENABLED=true but REDIS_URL is empty. Disabling Redis fallback cache."
      export REDIS_ENABLED=false
    fi
  fi

  echo "[startup] PORT=${PORT:-4000} NODE_ENV=${NODE_ENV:-production} RUN_MIGRATIONS=${RUN_MIGRATIONS} PRISMA_SYNC_MODE=${PRISMA_SYNC_MODE}"
}

run_prisma_migrate_deploy() {
  log_file="${TMPDIR:-/tmp}/prisma-migrate-deploy.$$.$1.log"

  if npx prisma migrate deploy >"$log_file" 2>&1; then
    cat "$log_file"
    rm -f "$log_file"
    return 0
  fi

  status=$?
  cat "$log_file"

  if grep -q "P3009" "$log_file" && grep -q "$FAILED_MIGRATION_NAME" "$log_file"; then
    echo "[startup] detected P3009 for migration ${FAILED_MIGRATION_NAME}"
    echo "[startup] invoking safe resolver"

    if node scripts/resolve-failed-migration.cjs "$FAILED_MIGRATION_NAME" --deploy-after-resolve; then
      echo "[startup] safe resolver completed for migration ${FAILED_MIGRATION_NAME}"
      rm -f "$log_file"
      return 0
    fi

    resolver_status=$?
    echo "[startup] safe resolver failed for migration ${FAILED_MIGRATION_NAME}"
    rm -f "$log_file"
    return "$resolver_status"
  fi

  rm -f "$log_file"
  return "$status"
}

preflight

if [ "$RUN_MIGRATIONS" = "true" ] || [ "$RUN_MIGRATIONS" = "1" ]; then
  if [ "$PRISMA_SYNC_MODE" = "push" ]; then
    if [ "${NODE_ENV:-production}" = "production" ] && [ "${ALLOW_PRODUCTION_DB_PUSH:-false}" != "true" ]; then
      echo "[startup] ERROR: PRISMA_SYNC_MODE=push is blocked in production."
      echo "[startup] Use prisma migrate deploy after the Phase 6 baseline/resolve plan, or set ALLOW_PRODUCTION_DB_PUSH=true only for a documented emergency."
      exit 1
    fi
    echo "[startup] prisma db push for non-production or explicitly approved emergency sync"
    npx prisma db push --accept-data-loss
  else
    echo "[startup] prisma migrate deploy (retries: ${MIGRATION_MAX_RETRIES})"
    attempt=1
    while [ "$attempt" -le "$MIGRATION_MAX_RETRIES" ]; do
      if run_prisma_migrate_deploy "$attempt"; then
        echo "[startup] migrations applied"
        break
      fi

      if [ "$attempt" -eq "$MIGRATION_MAX_RETRIES" ]; then
        echo "[startup] migrations failed after ${MIGRATION_MAX_RETRIES} attempts"
        if [ "$MIGRATION_STRICT" = "true" ] || [ "$MIGRATION_STRICT" = "1" ]; then
          echo "[startup] MIGRATION_STRICT enabled -> exiting"
          exit 1
        fi
        echo "[startup] MIGRATION_STRICT disabled -> continuing startup without successful migrations"
        break
      fi

      echo "[startup] migrate failed (attempt ${attempt}/${MIGRATION_MAX_RETRIES}), retrying in ${MIGRATION_RETRY_DELAY_SECONDS}s..."
      attempt=$((attempt + 1))
      sleep "$MIGRATION_RETRY_DELAY_SECONDS"
    done
  fi
else
  echo "[startup] RUN_MIGRATIONS disabled -> skipping prisma schema sync"
fi

if [ "${RUN_SEED:-}" = "true" ] || [ "${RUN_SEED:-}" = "1" ]; then
  echo "[startup] RUN_SEED enabled -> prisma db seed"
  npx prisma db seed
else
  echo "[startup] RUN_SEED not enabled -> skipping seed"
fi

echo "[startup] starting api"
exec node dist/main.js
