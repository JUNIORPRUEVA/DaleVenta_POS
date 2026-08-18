-- CreateTable
CREATE TABLE "user_whatsapp_instances" (
    "id" UUID NOT NULL DEFAULT gen_random_uuid(),
    "user_id" UUID NOT NULL,
    "instance_name" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "phone_number" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "user_whatsapp_instances_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "user_whatsapp_instances_user_id_key" ON "user_whatsapp_instances"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "user_whatsapp_instances_instance_name_key" ON "user_whatsapp_instances"("instance_name");

-- AddForeignKey
ALTER TABLE "user_whatsapp_instances" ADD CONSTRAINT "user_whatsapp_instances_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
