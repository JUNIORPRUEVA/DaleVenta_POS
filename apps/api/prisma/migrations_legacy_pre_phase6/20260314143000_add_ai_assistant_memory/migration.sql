CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS ai_assistant_conversation_turns (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL,
  user_id UUID NOT NULL,
  module TEXT NOT NULL DEFAULT 'general',
  route TEXT,
  entity_type TEXT,
  entity_id TEXT,
  user_message TEXT NOT NULL,
  assistant_response TEXT NOT NULL,
  response_source TEXT NOT NULL DEFAULT 'rules-only',
  denied BOOLEAN NOT NULL DEFAULT false,
  citations JSONB,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT ai_assistant_conversation_turns_pkey PRIMARY KEY (id)
);

CREATE INDEX IF NOT EXISTS ai_assistant_conversation_turns_owner_user_created_idx
  ON ai_assistant_conversation_turns (owner_id, user_id, "createdAt");

CREATE INDEX IF NOT EXISTS ai_assistant_conversation_turns_owner_module_created_idx
  ON ai_assistant_conversation_turns (owner_id, module, "createdAt");

CREATE TABLE IF NOT EXISTS ai_assistant_memories (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL,
  user_id UUID NOT NULL,
  scope TEXT NOT NULL DEFAULT 'user',
  module TEXT NOT NULL DEFAULT 'general',
  topic_key TEXT NOT NULL,
  title TEXT NOT NULL,
  summary TEXT NOT NULL,
  keywords JSONB,
  source_count INTEGER NOT NULL DEFAULT 1,
  last_source_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT ai_assistant_memories_pkey PRIMARY KEY (id)
);

CREATE UNIQUE INDEX IF NOT EXISTS ai_assistant_memories_owner_user_scope_topic_key_key
  ON ai_assistant_memories (owner_id, user_id, scope, topic_key);

CREATE INDEX IF NOT EXISTS ai_assistant_memories_owner_user_module_idx
  ON ai_assistant_memories (owner_id, user_id, module);

CREATE INDEX IF NOT EXISTS ai_assistant_memories_owner_user_last_source_idx
  ON ai_assistant_memories (owner_id, user_id, last_source_at);
