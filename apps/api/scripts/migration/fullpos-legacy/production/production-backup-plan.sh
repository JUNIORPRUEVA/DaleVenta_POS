#!/usr/bin/env bash
# ============================================================================
# PRE-CUTOVER BACKUP / RESTORE PROCEDURE (Phase 5, Step 6 + Step 10 LEVEL B)
#
# PREPARED ONLY. This script is NOT executed in Phase 5.
# It runs on the production host (root@31.97.99.70), never inside the repo.
# It never prints or copies database credentials: it uses the container's own
# POSTGRES_* environment inside `docker exec`.
#
# Usage on the host:
#   bash /root/fullpos-cutover-backup.sh dump       # create the pre-cutover dump
#   bash /root/fullpos-cutover-backup.sh verify     # verify the newest dump
#   bash /root/fullpos-cutover-backup.sh list       # list available dumps
#   bash /root/fullpos-cutover-backup.sh restore <file>   # LEVEL B (destructive, needs CONFIRM=yes)
# ============================================================================
set -euo pipefail

DB_CONTAINER_FILTER="name=daleventapos_database.1."
BACKUP_DIR="/root/daleventas-backups"
PREFIX="daleventa_before_cafeteria_labomba"
STAMP="$(date -u +%Y%m%d_%H%M%S)"
DUMP_NAME="${PREFIX}_${STAMP}.dump"

# Resolve the RUNNING database container (never guess by name alone).
CID="$(docker ps --filter "$DB_CONTAINER_FILTER" --format '{{.ID}}' | head -1)"
if [ -z "$CID" ]; then
  echo "ABORT: database container not running"; exit 1
fi

container_psql() {
  docker exec "$CID" sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tA -c "$1"'
}

preflight() {
  echo "== PREFLIGHT (read-only) =="
  docker exec "$CID" sh -c 'echo "POSTGRES_DB=$POSTGRES_DB"'
  docker exec "$CID" sh -c 'echo "PGDATA=$PGDATA"; du -sh "$PGDATA"'
  docker exec "$CID" sh -c 'pg_dump --version'
  echo "HOST FREE SPACE:"; df -h / | tail -1
  mkdir -p "$BACKUP_DIR"
  echo "BACKUP_DIR=$BACKUP_DIR"
}

do_dump() {
  preflight
  echo "== DUMP =="
  # Custom format (-Fc) inside the container, one file, no credentials on the command line.
  docker exec "$CID" sh -c "pg_dump -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" -Fc -f /tmp/${DUMP_NAME}"
  # Copy the artifact OUT of the database container so a container loss cannot lose the backup.
  docker cp "${CID}:/tmp/${DUMP_NAME}" "${BACKUP_DIR}/${DUMP_NAME}"
  docker exec "$CID" rm -f "/tmp/${DUMP_NAME}"
  chmod 600 "${BACKUP_DIR}/${DUMP_NAME}"
  echo "DUMP_PATH=${BACKUP_DIR}/${DUMP_NAME}"
  ls -l "${BACKUP_DIR}/${DUMP_NAME}"
  sha256sum "${BACKUP_DIR}/${DUMP_NAME}" | tee "${BACKUP_DIR}/${DUMP_NAME}.sha256"
  echo "RESTORE_TEST_UNAUTHORIZED_UNTIL_CUTOVER" > /dev/null
}

do_verify() {
  local file="${1:-$(ls -t ${BACKUP_DIR}/${PREFIX}_*.dump | head -1)}"
  echo "== VERIFY ${file} =="
  docker cp "$file" "${CID}:/tmp/verify.dump"
  # pg_restore --list parses the archive without touching the database.
  docker exec "$CID" sh -c 'pg_restore --list /tmp/verify.dump | wc -l'
  docker exec "$CID" rm -f /tmp/verify.dump
  echo "SHA256_STORED:"; cat "${file}.sha256" 2>/dev/null || echo "no .sha256 next to the file"
  echo "SHA256_NOW:"; sha256sum "$file"
}

do_list() {
  ls -lt "${BACKUP_DIR}" | head -20
}

# ---------------------------------------------------------------------------
# LEVEL B — FULL DATABASE RESTORE. DESTRUCTIVE. Only for a catastrophic rollback.
# Requires the literal token CONFIRM=yes plus the explicit dump file.
# ---------------------------------------------------------------------------
do_restore() {
  local file="${1:?usage: restore <dump-file>}"
  if [ "${CONFIRM:-}" != "yes" ]; then
    echo "ABORT: LEVEL B restore is destructive and requires CONFIRM=yes"; exit 1
  fi
  echo "!!! LEVEL B RESTORE of $file over the production database !!!"
  echo "Recommended sequence (manual, supervised):"
  echo "  1) stop the API container so no writer is connected:"
  echo "       docker service scale daleventapos_backend=0   # (or the project's scale command)"
  echo "  2) restore:"
  echo "       docker cp $file \${CID}:/tmp/restore.dump"
  echo "       docker exec -i \${CID} sh -c 'pg_restore -U \"\$POSTGRES_USER\" -d \"\$POSTGRES_DB\" --clean --if-exists --no-owner /tmp/restore.dump'"
  echo "       docker exec \${CID} rm -f /tmp/restore.dump"
  echo "  3) start the API again and re-run the reconciliation SQL."
  echo "NOT IMPLEMENTED ON PURPOSE: this script will not drop/restore the live database itself."
  exit 0
}

case "${1:-}" in
  dump)    do_dump ;;
  verify)  do_verify "${2:-}" ;;
  list)    do_list ;;
  restore) do_restore "${2:-}" ;;
  *) echo "usage: $0 {dump|verify|list|restore <file>}"; exit 1 ;;
esac
