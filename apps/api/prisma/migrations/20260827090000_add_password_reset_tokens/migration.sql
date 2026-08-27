CREATE TABLE IF NOT EXISTS "password_reset_tokens" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "user_id" UUID NOT NULL,
  "company_id" UUID NOT NULL,
  "token_hash" TEXT NOT NULL,
  "requested_ip" TEXT,
  "requested_user_agent" TEXT,
  "used_ip" TEXT,
  "used_user_agent" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "expires_at" TIMESTAMP(3) NOT NULL,
  "used_at" TIMESTAMP(3),
  "revoked_at" TIMESTAMP(3),
  "revocation_reason" TEXT,

  CONSTRAINT "password_reset_tokens_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "password_reset_tokens_user_id_fkey"
    FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "password_reset_tokens_company_id_fkey"
    FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE UNIQUE INDEX IF NOT EXISTS "password_reset_tokens_token_hash_key"
  ON "password_reset_tokens" ("token_hash");
CREATE INDEX IF NOT EXISTS "password_reset_tokens_user_state_idx"
  ON "password_reset_tokens" ("user_id", "used_at", "revoked_at");
CREATE INDEX IF NOT EXISTS "password_reset_tokens_company_created_idx"
  ON "password_reset_tokens" ("company_id", "created_at");
CREATE INDEX IF NOT EXISTS "password_reset_tokens_expires_at_idx"
  ON "password_reset_tokens" ("expires_at");

CREATE TABLE IF NOT EXISTS "password_reset_audit_logs" (
  "id" UUID NOT NULL DEFAULT gen_random_uuid(),
  "user_id" UUID,
  "company_id" UUID,
  "action" TEXT NOT NULL,
  "email_hash" TEXT,
  "reason" TEXT,
  "ip_address" TEXT,
  "user_agent" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "password_reset_audit_logs_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "password_reset_audit_logs_user_id_fkey"
    FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT "password_reset_audit_logs_company_id_fkey"
    FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE SET NULL ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS "password_reset_audit_logs_company_created_idx"
  ON "password_reset_audit_logs" ("company_id", "created_at");
CREATE INDEX IF NOT EXISTS "password_reset_audit_logs_user_created_idx"
  ON "password_reset_audit_logs" ("user_id", "created_at");
CREATE INDEX IF NOT EXISTS "password_reset_audit_logs_action_created_idx"
  ON "password_reset_audit_logs" ("action", "created_at");
