ALTER TABLE "marketing_research_configs"
ALTER COLUMN "research_frequency_days" SET DEFAULT 7;

UPDATE "marketing_research_configs"
SET "research_frequency_days" = 7
WHERE "research_frequency_days" <> 7;
