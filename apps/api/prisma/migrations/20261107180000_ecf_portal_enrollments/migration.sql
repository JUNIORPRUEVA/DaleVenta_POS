-- Elegibilidad del asistente e-CF POR EMPRESA, en base de datos.
--
-- Motivo: hasta ahora una empresa solo podía entrar al portal de certificación
-- si su `companyId` figuraba en `ECF_PORTAL_PILOT_COMPANY_IDS`, una variable del
-- despliegue. Eso obligaba a un cambio de infraestructura por cada cliente nuevo
-- y hacía imposible auditar quién autorizó qué.
--
-- Diseño:
--  * Historial completo: una fila por autorización. Revocar es marcar `revoked_at`,
--    no borrar.
--  * Como mucho UNA fila vigente por empresa (índice único parcial). Así dos
--    autorizaciones simultáneas no pueden coexistir.
--  * `source` dice de dónde viene la autorización. `AUTO_ELIGIBLE` se escribe
--    solo si la regla de elegibilidad está habilitada; por defecto está apagada,
--    así que el sistema sigue fallando cerrado.
--  * No guarda credenciales ni datos fiscales: solo la autorización.

CREATE TABLE "ecf_portal_enrollments" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    -- `ADMIN_AUTHORIZATION` (una persona la concede), `CONTRACT_REFERENCE`
    -- (existe una referencia contractual verificable) o `AUTO_ELIGIBLE`
    -- (la regla automática la concedió).
    "source" VARCHAR(32) NOT NULL,
    "status" VARCHAR(16) NOT NULL DEFAULT 'ACTIVE',
    "reason" VARCHAR(500),
    -- Referencia de la autorización contractual, si la hay (nº de contrato,
    -- correo del proveedor, etc.). Nunca un secreto.
    "contract_reference" VARCHAR(160),
    "authorized_by_user_id" UUID,
    "expires_at" TIMESTAMP(3),
    "revoked_at" TIMESTAMP(3),
    "revoked_by_user_id" UUID,
    "revocation_reason" VARCHAR(500),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ecf_portal_enrollments_pkey" PRIMARY KEY ("id")
);

-- Una sola autorización vigente por empresa.
CREATE UNIQUE INDEX "ecf_portal_enrollments_active_company_key"
    ON "ecf_portal_enrollments"("company_id")
    WHERE "status" = 'ACTIVE';

CREATE INDEX "ecf_portal_enrollments_company_id_created_at_idx"
    ON "ecf_portal_enrollments"("company_id", "created_at");

ALTER TABLE "ecf_portal_enrollments"
    ADD CONSTRAINT "ecf_portal_enrollments_company_id_fkey"
    FOREIGN KEY ("company_id") REFERENCES "companies"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
