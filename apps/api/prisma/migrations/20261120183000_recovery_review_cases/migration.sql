CREATE TABLE "recovery_review_cases" (
 "id" UUID PRIMARY KEY, "company_id" UUID NOT NULL, "source_user_id" UUID NOT NULL,
 "source_action_id" VARCHAR(300) NOT NULL, "action_type" VARCHAR(40) NOT NULL,
 "operation_id" VARCHAR(200) NOT NULL, "original_session_id" VARCHAR(128),
 "expected_amount" DECIMAL(12,2), "snapshot_hash" VARCHAR(64) NOT NULL,
 "payload_summary" JSONB NOT NULL, "status" VARCHAR(40) NOT NULL DEFAULT 'OPEN',
 "version" INTEGER NOT NULL DEFAULT 1, "registered_entity_id" VARCHAR(128),
 "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updated_at" TIMESTAMP(3) NOT NULL
);
CREATE UNIQUE INDEX "recovery_review_case_operation_key" ON "recovery_review_cases" ("company_id","source_user_id","action_type","operation_id");
CREATE INDEX "recovery_review_cases_company_id_status_created_at_idx" ON "recovery_review_cases" ("company_id","status","created_at");
CREATE TABLE "recovery_review_events" (
 "id" UUID PRIMARY KEY, "company_id" UUID NOT NULL, "case_id" UUID NOT NULL,
 "actor_user_id" UUID NOT NULL, "actor_role" VARCHAR(40) NOT NULL, "kind" VARCHAR(40) NOT NULL,
 "note" TEXT, "evidence_reference" VARCHAR(500), "case_version" INTEGER NOT NULL,
 "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX "recovery_review_events_company_id_case_id_created_at_idx" ON "recovery_review_events" ("company_id","case_id","created_at");
