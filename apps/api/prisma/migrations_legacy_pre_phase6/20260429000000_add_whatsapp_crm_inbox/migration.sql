-- CreateEnum (idempotent)
DO $$ BEGIN
  CREATE TYPE "whatsapp_message_direction" AS ENUM ('INCOMING', 'OUTGOING');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE "whatsapp_message_type" AS ENUM ('TEXT', 'IMAGE', 'AUDIO', 'VIDEO', 'DOCUMENT', 'STICKER', 'OTHER');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- CreateTable
CREATE TABLE "whatsapp_conversations" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "instance_id" UUID NOT NULL,
    "remote_jid" TEXT NOT NULL,
    "remote_phone" TEXT,
    "remote_name" TEXT,
    "last_message_at" TIMESTAMP(3),
    "unread_count" INTEGER NOT NULL DEFAULT 0,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "whatsapp_conversations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "whatsapp_messages" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "conversation_id" UUID NOT NULL,
    "evolution_id" TEXT,
    "direction" "whatsapp_message_direction" NOT NULL,
    "message_type" "whatsapp_message_type" NOT NULL DEFAULT 'TEXT',
    "body" TEXT,
    "media_url" TEXT,
    "media_mime_type" TEXT,
    "caption" TEXT,
    "sender_name" TEXT,
    "sent_at" TIMESTAMP(3) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "raw_payload" JSONB,

    CONSTRAINT "whatsapp_messages_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_conversations_instance_id_remote_jid_key" ON "whatsapp_conversations"("instance_id", "remote_jid");

-- CreateIndex
CREATE INDEX "whatsapp_conversations_instance_id_last_message_at_idx" ON "whatsapp_conversations"("instance_id", "last_message_at" DESC);

-- CreateIndex
CREATE UNIQUE INDEX "whatsapp_messages_evolution_id_key" ON "whatsapp_messages"("evolution_id");

-- CreateIndex
CREATE INDEX "whatsapp_messages_conversation_id_sent_at_idx" ON "whatsapp_messages"("conversation_id", "sent_at" DESC);

-- AddForeignKey
ALTER TABLE "whatsapp_conversations" ADD CONSTRAINT "whatsapp_conversations_instance_id_fkey" FOREIGN KEY ("instance_id") REFERENCES "user_whatsapp_instances"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "whatsapp_messages" ADD CONSTRAINT "whatsapp_messages_conversation_id_fkey" FOREIGN KEY ("conversation_id") REFERENCES "whatsapp_conversations"("id") ON DELETE CASCADE ON UPDATE CASCADE;
