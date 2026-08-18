CREATE TABLE IF NOT EXISTS "whatsapp_ai_media_summaries" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "message_id" UUID NOT NULL UNIQUE,
  "media_type" TEXT NOT NULL,
  "summary" TEXT,
  "evidence" JSONB,
  "transcription_status" TEXT NOT NULL DEFAULT 'not_applicable',
  "transcription_text" TEXT,
  "model" TEXT,
  "generated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS "whatsapp_ai_analysis_reports" (
  "id" UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  "conversation_id" UUID,
  "scope" TEXT NOT NULL,
  "date_range_key" TEXT NOT NULL,
  "start_at" TIMESTAMP(3) NOT NULL,
  "end_at" TIMESTAMP(3) NOT NULL,
  "message_fingerprint" TEXT NOT NULL,
  "risk_level" TEXT NOT NULL,
  "summary" TEXT NOT NULL,
  "alerts" JSONB,
  "image_summaries" JSONB,
  "audio_transcription_status" JSONB,
  "report" JSONB NOT NULL,
  "generated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "generated_by" UUID
);

CREATE INDEX IF NOT EXISTS "whatsapp_ai_media_summaries_media_type_idx"
  ON "whatsapp_ai_media_summaries" ("media_type");

CREATE INDEX IF NOT EXISTS "whatsapp_ai_media_summaries_transcription_status_idx"
  ON "whatsapp_ai_media_summaries" ("transcription_status");

CREATE INDEX IF NOT EXISTS "whatsapp_ai_analysis_reports_conversation_generated_idx"
  ON "whatsapp_ai_analysis_reports" ("conversation_id", "generated_at" DESC);

CREATE INDEX IF NOT EXISTS "whatsapp_ai_analysis_reports_scope_range_generated_idx"
  ON "whatsapp_ai_analysis_reports" ("scope", "date_range_key", "generated_at" DESC);

CREATE INDEX IF NOT EXISTS "whatsapp_ai_analysis_reports_risk_level_idx"
  ON "whatsapp_ai_analysis_reports" ("risk_level");

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'whatsapp_ai_media_summaries_message_id_fkey'
  ) THEN
    ALTER TABLE "whatsapp_ai_media_summaries"
      ADD CONSTRAINT "whatsapp_ai_media_summaries_message_id_fkey"
      FOREIGN KEY ("message_id")
      REFERENCES "whatsapp_messages"("id")
      ON DELETE CASCADE
      ON UPDATE CASCADE;
  END IF;
END
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'whatsapp_ai_analysis_reports_conversation_id_fkey'
  ) THEN
    ALTER TABLE "whatsapp_ai_analysis_reports"
      ADD CONSTRAINT "whatsapp_ai_analysis_reports_conversation_id_fkey"
      FOREIGN KEY ("conversation_id")
      REFERENCES "whatsapp_conversations"("id")
      ON DELETE CASCADE
      ON UPDATE CASCADE;
  END IF;
END
$$;
