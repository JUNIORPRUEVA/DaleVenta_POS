ALTER TABLE "Sale"
  ADD COLUMN "terminal_id" UUID,
  ADD COLUMN "terminal_name_snapshot" TEXT,
  ADD COLUMN "terminal_code_snapshot" TEXT;

ALTER TABLE "cash_sessions"
  ADD COLUMN "terminal_id" UUID,
  ADD COLUMN "terminal_name_snapshot" TEXT,
  ADD COLUMN "terminal_code_snapshot" TEXT;

CREATE INDEX "Sale_terminal_id_idx" ON "Sale"("terminal_id");
CREATE INDEX "cash_sessions_terminal_id_idx" ON "cash_sessions"("terminal_id");

ALTER TABLE "Sale"
  ADD CONSTRAINT "Sale_terminal_id_fkey"
  FOREIGN KEY ("terminal_id") REFERENCES "terminals"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "cash_sessions"
  ADD CONSTRAINT "cash_sessions_terminal_id_fkey"
  FOREIGN KEY ("terminal_id") REFERENCES "terminals"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
