-- Create publicidad_images table (separate from service evidence)
CREATE TABLE IF NOT EXISTS "publicidad_images" (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  url TEXT NOT NULL,
  caption TEXT,
  uploaded_by_id UUID NOT NULL REFERENCES "users"(id) ON DELETE RESTRICT,
  created_at TIMESTAMP NOT NULL DEFAULT now(),
  updated_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS "publicidad_images_uploaded_by_idx" ON "publicidad_images"(uploaded_by_id);
CREATE INDEX IF NOT EXISTS "publicidad_images_created_at_idx" ON "publicidad_images"(created_at DESC);
