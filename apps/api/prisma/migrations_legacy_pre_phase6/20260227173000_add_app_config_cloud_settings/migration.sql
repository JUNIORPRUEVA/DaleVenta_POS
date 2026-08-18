CREATE TABLE IF NOT EXISTS "app_config" (
  "id" TEXT NOT NULL,
  "companyName" TEXT NOT NULL DEFAULT '',
  "rnc" TEXT NOT NULL DEFAULT '',
  "phone" TEXT NOT NULL DEFAULT '',
  "address" TEXT NOT NULL DEFAULT '',
  "logoBase64" TEXT,
  "openAiApiKey" TEXT,
  "openAiModel" TEXT NOT NULL DEFAULT 'gpt-4o-mini',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "app_config_pkey" PRIMARY KEY ("id")
);

INSERT INTO "app_config" (
  "id",
  "companyName",
  "rnc",
  "phone",
  "address",
  "openAiModel",
  "createdAt",
  "updatedAt"
)
VALUES (
  'global',
  '',
  '',
  '',
  '',
  'gpt-4o-mini',
  CURRENT_TIMESTAMP,
  CURRENT_TIMESTAMP
)
ON CONFLICT ("id") DO NOTHING;
