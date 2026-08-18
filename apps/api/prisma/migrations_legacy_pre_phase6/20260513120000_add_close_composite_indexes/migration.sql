-- Add composite indexes to optimize Close queries
-- These indexes improve performance for:
-- 1. Queries filtering by date + type
-- 2. Queries filtering by user + date
-- 3. Queries filtering by date + createdById + type

CREATE INDEX "Close_date_type_idx" ON "Close"("date" DESC, "type");
CREATE INDEX "Close_createdById_date_idx" ON "Close"("createdById", "date" DESC);
CREATE INDEX "Close_date_createdById_type_idx" ON "Close"("date" DESC, "createdById", "type");
