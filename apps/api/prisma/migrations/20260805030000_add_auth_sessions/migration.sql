CREATE TABLE IF NOT EXISTS "auth_sessions" (
  "id" UUID NOT NULL,
  "user_id" UUID NOT NULL,
  "company_id" UUID,
  "refresh_token_hash" TEXT NOT NULL,
  "token_family" UUID NOT NULL,
  "user_agent" TEXT,
  "ip_address" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "last_used_at" TIMESTAMP(3),
  "expires_at" TIMESTAMP(3) NOT NULL,
  "revoked_at" TIMESTAMP(3),
  "revocation_reason" TEXT,

  CONSTRAINT "auth_sessions_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "auth_sessions_user_id_fkey"
    FOREIGN KEY ("user_id") REFERENCES "users"("id")
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "auth_sessions_company_id_fkey"
    FOREIGN KEY ("company_id") REFERENCES "companies"("id")
    ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX IF NOT EXISTS "auth_sessions_user_id_revoked_at_idx"
  ON "auth_sessions"("user_id", "revoked_at");

CREATE INDEX IF NOT EXISTS "auth_sessions_company_id_revoked_at_idx"
  ON "auth_sessions"("company_id", "revoked_at");

CREATE INDEX IF NOT EXISTS "auth_sessions_token_family_idx"
  ON "auth_sessions"("token_family");

CREATE INDEX IF NOT EXISTS "auth_sessions_expires_at_idx"
  ON "auth_sessions"("expires_at");
