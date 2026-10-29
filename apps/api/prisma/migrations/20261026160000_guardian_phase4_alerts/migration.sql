-- APPYRA Guardian AI — Fase 4 (aditivo): cola de alertas administrativas 24/7.

-- CreateEnum
CREATE TYPE "GuardianAlertState" AS ENUM ('PENDING', 'SENDING', 'SENT', 'DELIVERED', 'FAILED_PERMANENT', 'DEAD');

-- CreateTable
CREATE TABLE "guardian_alerts" (
    "id" UUID NOT NULL,
    "incident_id" UUID NOT NULL,
    "channel" VARCHAR(40) NOT NULL,
    "recipient_hash" VARCHAR(80) NOT NULL,
    "dedupe_key" VARCHAR(200) NOT NULL,
    "kind" VARCHAR(20) NOT NULL DEFAULT 'initial',
    "state" "GuardianAlertState" NOT NULL DEFAULT 'PENDING',
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "next_attempt_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "locked_at" TIMESTAMP(3),
    "locked_by" VARCHAR(120),
    "provider_message_id" VARCHAR(200),
    "last_error" VARCHAR(600),
    "sent_at" TIMESTAMP(3),
    "delivered_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "guardian_alerts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "guardian_alert_attempts" (
    "id" BIGSERIAL NOT NULL,
    "alert_id" UUID NOT NULL,
    "attempt" INTEGER NOT NULL,
    "channel" VARCHAR(40) NOT NULL,
    "outcome" VARCHAR(20) NOT NULL,
    "http_status" INTEGER,
    "detail" VARCHAR(600),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "guardian_alert_attempts_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "guardian_alerts_dedupe_key_key" ON "guardian_alerts"("dedupe_key");

-- CreateIndex
CREATE INDEX "guardian_alerts_state_next_attempt_at_idx" ON "guardian_alerts"("state", "next_attempt_at");

-- CreateIndex
CREATE INDEX "guardian_alerts_incident_id_idx" ON "guardian_alerts"("incident_id");

-- CreateIndex
CREATE INDEX "guardian_alerts_locked_at_idx" ON "guardian_alerts"("locked_at");

-- CreateIndex
CREATE INDEX "guardian_alert_attempts_alert_id_created_at_idx" ON "guardian_alert_attempts"("alert_id", "created_at");

-- AddForeignKey
ALTER TABLE "guardian_alert_attempts" ADD CONSTRAINT "guardian_alert_attempts_alert_id_fkey" FOREIGN KEY ("alert_id") REFERENCES "guardian_alerts"("id") ON DELETE CASCADE ON UPDATE CASCADE;

