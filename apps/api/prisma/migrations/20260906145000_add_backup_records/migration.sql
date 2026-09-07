CREATE TYPE "backup_type" AS ENUM ('MANUAL', 'AUTOMATIC', 'PRE_RESTORE_SAFETY');

CREATE TYPE "backup_status" AS ENUM ('PENDING', 'COMPLETE', 'FAILED');

CREATE TABLE "backup_records" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "company_id" UUID NOT NULL,
    "created_by_user_id" UUID,
    "type" "backup_type" NOT NULL,
    "status" "backup_status" NOT NULL DEFAULT 'PENDING',
    "format_version" INTEGER NOT NULL,
    "storage_key" TEXT NOT NULL,
    "size_bytes" BIGINT NOT NULL DEFAULT 0,
    "checksum" TEXT,
    "company_name_snapshot" TEXT NOT NULL,
    "failure_reason" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "validated_at" TIMESTAMP(3),
    "deleted_at" TIMESTAMP(3),

    CONSTRAINT "backup_records_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "backup_records_company_id_created_at_idx" ON "backup_records"("company_id", "created_at");
CREATE INDEX "backup_records_company_id_type_status_created_at_idx" ON "backup_records"("company_id", "type", "status", "created_at");
CREATE INDEX "backup_records_company_id_deleted_at_idx" ON "backup_records"("company_id", "deleted_at");

ALTER TABLE "backup_records"
ADD CONSTRAINT "backup_records_company_id_fkey"
FOREIGN KEY ("company_id") REFERENCES "companies"("id")
ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "backup_records"
ADD CONSTRAINT "backup_records_created_by_user_id_fkey"
FOREIGN KEY ("created_by_user_id") REFERENCES "users"("id")
ON DELETE SET NULL ON UPDATE CASCADE;
