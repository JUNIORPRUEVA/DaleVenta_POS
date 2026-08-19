CREATE TABLE "admin_authorization_capabilities" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "jti" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "session_id" UUID NOT NULL,
    "scopes" JSONB NOT NULL DEFAULT '[]',
    "expires_at" TIMESTAMP(3) NOT NULL,
    "consumed_at" TIMESTAMP(3),
    "consumed_by_path" TEXT,
    "revoked_at" TIMESTAMP(3),
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "admin_authorization_capabilities_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "admin_authorization_capabilities_jti_key" ON "admin_authorization_capabilities"("jti");
CREATE INDEX "admin_authorization_capabilities_company_id_user_id_consumed_at_idx" ON "admin_authorization_capabilities"("company_id", "user_id", "consumed_at");
CREATE INDEX "admin_authorization_capabilities_session_id_revoked_at_idx" ON "admin_authorization_capabilities"("session_id", "revoked_at");
CREATE INDEX "admin_authorization_capabilities_expires_at_idx" ON "admin_authorization_capabilities"("expires_at");

ALTER TABLE "admin_authorization_capabilities"
ADD CONSTRAINT "admin_authorization_capabilities_company_id_fkey"
FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "admin_authorization_capabilities"
ADD CONSTRAINT "admin_authorization_capabilities_user_id_fkey"
FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "admin_authorization_capabilities"
ADD CONSTRAINT "admin_authorization_capabilities_session_id_fkey"
FOREIGN KEY ("session_id") REFERENCES "auth_sessions"("id") ON DELETE CASCADE ON UPDATE CASCADE;
