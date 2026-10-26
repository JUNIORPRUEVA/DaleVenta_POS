-- APPYRA Guardian AI — latido de workers (aditivo, sin tocar tablas existentes).
-- Permite al watchdog independiente detectar un worker detenido aunque no haya
-- trabajo pendiente en la cola.

CREATE TABLE IF NOT EXISTS "guardian_worker_heartbeats" (
  "worker_name" VARCHAR(60) NOT NULL,
  "last_seen_at" TIMESTAMP(3) NOT NULL,
  "cycle_count" BIGINT NOT NULL DEFAULT 0,
  "processed_last_cycle" INTEGER NOT NULL DEFAULT 0,
  "host" VARCHAR(120),
  "pid" INTEGER,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "guardian_worker_heartbeats_pkey" PRIMARY KEY ("worker_name")
);

CREATE INDEX IF NOT EXISTS "guardian_worker_heartbeats_last_seen_at_idx"
  ON "guardian_worker_heartbeats" ("last_seen_at");
