-- Ensure one WhatsApp CRM conversation per customer phone per instance.

UPDATE "whatsapp_conversations"
SET "remote_phone" = NULLIF(
  regexp_replace(
    split_part(split_part(COALESCE("remote_phone", "remote_jid"), '@', 1), ':', 1),
    '\D',
    '',
    'g'
  ),
  ''
)
WHERE "remote_phone" IS DISTINCT FROM NULLIF(
  regexp_replace(
    split_part(split_part(COALESCE("remote_phone", "remote_jid"), '@', 1), ':', 1),
    '\D',
    '',
    'g'
  ),
  ''
);

WITH ranked AS (
  SELECT
    c."id",
    c."instance_id",
    c."remote_phone",
    ROW_NUMBER() OVER (
      PARTITION BY c."instance_id", c."remote_phone"
      ORDER BY COUNT(m."id") DESC, c."created_at" ASC
    ) AS rn
  FROM "whatsapp_conversations" c
  LEFT JOIN "whatsapp_messages" m ON m."conversation_id" = c."id"
  WHERE c."remote_phone" IS NOT NULL
    AND c."remote_phone" <> ''
  GROUP BY c."id", c."instance_id", c."remote_phone", c."created_at"
),
keepers AS (
  SELECT "instance_id", "remote_phone", "id" AS keep_id
  FROM ranked
  WHERE rn = 1
),
duplicates AS (
  SELECT r."id" AS duplicate_id, k.keep_id
  FROM ranked r
  JOIN keepers k
    ON k."instance_id" = r."instance_id"
   AND k."remote_phone" = r."remote_phone"
  WHERE r.rn > 1
)
UPDATE "whatsapp_messages" m
SET "conversation_id" = d.keep_id
FROM duplicates d
WHERE m."conversation_id" = d.duplicate_id;

WITH duplicate_ids AS (
  SELECT c."id"
  FROM "whatsapp_conversations" c
  WHERE c."remote_phone" IS NOT NULL
    AND c."remote_phone" <> ''
    AND EXISTS (
      SELECT 1
      FROM "whatsapp_conversations" k
      WHERE k."instance_id" = c."instance_id"
        AND k."remote_phone" = c."remote_phone"
        AND k."id" <> c."id"
        AND (
          (SELECT COUNT(*) FROM "whatsapp_messages" km WHERE km."conversation_id" = k."id")
          >
          (SELECT COUNT(*) FROM "whatsapp_messages" cm WHERE cm."conversation_id" = c."id")
          OR (
            (SELECT COUNT(*) FROM "whatsapp_messages" km WHERE km."conversation_id" = k."id")
            =
            (SELECT COUNT(*) FROM "whatsapp_messages" cm WHERE cm."conversation_id" = c."id")
            AND k."created_at" < c."created_at"
          )
        )
    )
)
DELETE FROM "whatsapp_conversations" c
USING duplicate_ids d
WHERE c."id" = d."id";

UPDATE "whatsapp_conversations" c
SET
  "last_message_at" = (
    SELECT m."sent_at"
    FROM "whatsapp_messages" m
    WHERE m."conversation_id" = c."id"
    ORDER BY m."sent_at" DESC
    LIMIT 1
  ),
  "unread_count" = (
    SELECT COUNT(*)::int
    FROM "whatsapp_messages" m
    WHERE m."conversation_id" = c."id"
      AND m."direction" = 'INCOMING'
  )
WHERE c."remote_phone" IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS "whatsapp_conversations_instance_id_remote_phone_key"
ON "whatsapp_conversations"("instance_id", "remote_phone");
