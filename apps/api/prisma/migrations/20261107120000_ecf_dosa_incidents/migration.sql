-- Incidencias del flujo DOSA: detección, reintento seguro y cierre auditable.
--
-- Tabla aditiva y aislada por empresa. Existe porque hasta ahora un evento que
-- quedaba en `PENDING_CREDENTIALS` o `CONFLICT_PENDING_REVIEW` solo se detectaba
-- mirando la base a mano. No guarda credenciales ni cuerpos de evento: solo
-- referencias (postulación, RNC) y el estado del seguimiento.
--
-- El índice único (company_id, incident_key) es la garantía de "sin alertas
-- repetidas": el barrido hace UPSERT sobre esa clave en vez de insertar.

CREATE TABLE "ecf_dosa_incidents" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "rnc" VARCHAR(32),
    "incident_key" VARCHAR(160) NOT NULL,
    "kind" VARCHAR(48) NOT NULL,
    "severity" VARCHAR(8) NOT NULL,
    "status" VARCHAR(16) NOT NULL DEFAULT 'OPEN',
    "subject_type" VARCHAR(32),
    "subject_ref" VARCHAR(96),
    "detail" JSONB,
    "attempts" INTEGER NOT NULL DEFAULT 0,
    "last_attempt_at" TIMESTAMP(3),
    "next_attempt_at" TIMESTAMP(3),
    "last_error_code" VARCHAR(64),
    "resolution" VARCHAR(48),
    "resolved_at" TIMESTAMP(3),
    "resolved_by_user_id" UUID,
    "first_seen_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_seen_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ecf_dosa_incidents_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "ecf_dosa_incidents_company_id_incident_key_key"
    ON "ecf_dosa_incidents"("company_id", "incident_key");

CREATE INDEX "ecf_dosa_incidents_company_id_status_idx"
    ON "ecf_dosa_incidents"("company_id", "status");

CREATE INDEX "ecf_dosa_incidents_status_next_attempt_at_idx"
    ON "ecf_dosa_incidents"("status", "next_attempt_at");

ALTER TABLE "ecf_dosa_incidents"
    ADD CONSTRAINT "ecf_dosa_incidents_company_id_fkey"
    FOREIGN KEY ("company_id") REFERENCES "companies"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
