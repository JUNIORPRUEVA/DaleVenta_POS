-- CreateEnum
CREATE TYPE "crm_commercial_followup_task_status" AS ENUM ('PENDIENTE', 'COMPLETADA', 'VENCIDA', 'CANCELADA');

-- CreateEnum
CREATE TYPE "crm_commercial_followup_task_priority" AS ENUM ('BAJA', 'NORMAL', 'ALTA', 'URGENTE');

-- CreateTable
CREATE TABLE "crm_commercial_followup_tasks" (
    "id" UUID NOT NULL,
    "cliente_id" UUID NOT NULL,
    "titulo" TEXT NOT NULL,
    "descripcion" TEXT,
    "fecha_vencimiento" TIMESTAMP(3),
    "estado" "crm_commercial_followup_task_status" NOT NULL DEFAULT 'PENDIENTE',
    "prioridad" "crm_commercial_followup_task_priority" NOT NULL DEFAULT 'NORMAL',
    "asignado_usuario_id" UUID,
    "creado_por_usuario_id" UUID NOT NULL,
    "completado_en" TIMESTAMP(3),
    "completado_por_usuario_id" UUID,
    "fecha_creacion" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "fecha_actualizacion" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "crm_commercial_followup_tasks_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "crm_commercial_followup_tasks_cliente_id_estado_idx" ON "crm_commercial_followup_tasks"("cliente_id", "estado");

-- CreateIndex
CREATE INDEX "crm_commercial_followup_tasks_asignado_usuario_id_idx" ON "crm_commercial_followup_tasks"("asignado_usuario_id");

-- CreateIndex
CREATE INDEX "crm_commercial_followup_tasks_fecha_vencimiento_idx" ON "crm_commercial_followup_tasks"("fecha_vencimiento");

-- CreateIndex
CREATE INDEX "crm_commercial_followup_tasks_estado_fecha_vencimiento_idx" ON "crm_commercial_followup_tasks"("estado", "fecha_vencimiento");

-- AddForeignKey
ALTER TABLE "crm_commercial_followup_tasks" ADD CONSTRAINT "crm_commercial_followup_tasks_cliente_id_fkey" FOREIGN KEY ("cliente_id") REFERENCES "crm_commercial_customers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_followup_tasks" ADD CONSTRAINT "crm_commercial_followup_tasks_asignado_usuario_id_fkey" FOREIGN KEY ("asignado_usuario_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_followup_tasks" ADD CONSTRAINT "crm_commercial_followup_tasks_creado_por_usuario_id_fkey" FOREIGN KEY ("creado_por_usuario_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_followup_tasks" ADD CONSTRAINT "crm_commercial_followup_tasks_completado_por_usuario_id_fkey" FOREIGN KEY ("completado_por_usuario_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
