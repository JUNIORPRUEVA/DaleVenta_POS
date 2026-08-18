-- CreateEnum
CREATE TYPE "crm_commercial_customer_status" AS ENUM (
  'NUEVO',
  'INTERESADO',
  'COTIZACION',
  'NEGOCIACION',
  'PENDIENTE_PAGO',
  'GANADO',
  'PERDIDO',
  'SEGUIMIENTO',
  'SOPORTE',
  'COBRO_PENDIENTE'
);

-- CreateTable
CREATE TABLE "crm_commercial_customers" (
  "id" UUID NOT NULL,
  "client_id" UUID,
  "nombre" TEXT NOT NULL,
  "telefono" TEXT NOT NULL,
  "direccion" TEXT,
  "ciudad" TEXT,
  "estado_actual" "crm_commercial_customer_status" NOT NULL DEFAULT 'NUEVO',
  "etiqueta" TEXT,
  "responsable_user_id" UUID,
  "ultima_interaccion" TIMESTAMP(3),
  "proxima_accion_fecha" TIMESTAMP(3),
  "proxima_accion" TEXT,
  "observacion" TEXT,
  "created_by_user_id" UUID NOT NULL,
  "fecha_creacion" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "fecha_actualizacion" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "crm_commercial_customers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "crm_commercial_status_history" (
  "id" UUID NOT NULL,
  "cliente_id" UUID NOT NULL,
  "estado_anterior" "crm_commercial_customer_status",
  "estado_nuevo" "crm_commercial_customer_status" NOT NULL,
  "usuario_que_cambio" UUID NOT NULL,
  "nota" TEXT,
  "fecha" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "crm_commercial_status_history_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "crm_commercial_notes" (
  "id" UUID NOT NULL,
  "cliente_id" UUID NOT NULL,
  "usuario_id" UUID NOT NULL,
  "nota" TEXT NOT NULL,
  "fecha_creacion" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "fecha_actualizacion" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "crm_commercial_notes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "crm_commercial_activities" (
  "id" UUID NOT NULL,
  "cliente_id" UUID NOT NULL,
  "creado_por_usuario_id" UUID NOT NULL,
  "asignado_usuario_id" UUID,
  "tipo" TEXT NOT NULL,
  "descripcion" TEXT NOT NULL,
  "fecha_programada" TIMESTAMP(3),
  "fecha_completada" TIMESTAMP(3),
  "fecha_creacion" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "fecha_actualizacion" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "crm_commercial_activities_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "crm_commercial_customers_estado_actual_idx" ON "crm_commercial_customers"("estado_actual");

-- CreateIndex
CREATE INDEX "crm_commercial_customers_responsable_user_id_idx" ON "crm_commercial_customers"("responsable_user_id");

-- CreateIndex
CREATE INDEX "crm_commercial_customers_nombre_idx" ON "crm_commercial_customers"("nombre");

-- CreateIndex
CREATE INDEX "crm_commercial_customers_telefono_idx" ON "crm_commercial_customers"("telefono");

-- CreateIndex
CREATE INDEX "crm_commercial_customers_client_id_idx" ON "crm_commercial_customers"("client_id");

-- CreateIndex
CREATE INDEX "crm_commercial_status_history_cliente_id_fecha_idx" ON "crm_commercial_status_history"("cliente_id", "fecha");

-- CreateIndex
CREATE INDEX "crm_commercial_status_history_usuario_que_cambio_idx" ON "crm_commercial_status_history"("usuario_que_cambio");

-- CreateIndex
CREATE INDEX "crm_commercial_notes_cliente_id_fecha_creacion_idx" ON "crm_commercial_notes"("cliente_id", "fecha_creacion");

-- CreateIndex
CREATE INDEX "crm_commercial_notes_usuario_id_idx" ON "crm_commercial_notes"("usuario_id");

-- CreateIndex
CREATE INDEX "crm_commercial_activities_cliente_id_fecha_creacion_idx" ON "crm_commercial_activities"("cliente_id", "fecha_creacion");

-- CreateIndex
CREATE INDEX "crm_commercial_activities_asignado_usuario_id_idx" ON "crm_commercial_activities"("asignado_usuario_id");

-- AddForeignKey
ALTER TABLE "crm_commercial_customers" ADD CONSTRAINT "crm_commercial_customers_client_id_fkey"
  FOREIGN KEY ("client_id") REFERENCES "Client"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_customers" ADD CONSTRAINT "crm_commercial_customers_responsable_user_id_fkey"
  FOREIGN KEY ("responsable_user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_customers" ADD CONSTRAINT "crm_commercial_customers_created_by_user_id_fkey"
  FOREIGN KEY ("created_by_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_status_history" ADD CONSTRAINT "crm_commercial_status_history_cliente_id_fkey"
  FOREIGN KEY ("cliente_id") REFERENCES "crm_commercial_customers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_status_history" ADD CONSTRAINT "crm_commercial_status_history_usuario_que_cambio_fkey"
  FOREIGN KEY ("usuario_que_cambio") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_notes" ADD CONSTRAINT "crm_commercial_notes_cliente_id_fkey"
  FOREIGN KEY ("cliente_id") REFERENCES "crm_commercial_customers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_notes" ADD CONSTRAINT "crm_commercial_notes_usuario_id_fkey"
  FOREIGN KEY ("usuario_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_activities" ADD CONSTRAINT "crm_commercial_activities_cliente_id_fkey"
  FOREIGN KEY ("cliente_id") REFERENCES "crm_commercial_customers"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_activities" ADD CONSTRAINT "crm_commercial_activities_creado_por_usuario_id_fkey"
  FOREIGN KEY ("creado_por_usuario_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "crm_commercial_activities" ADD CONSTRAINT "crm_commercial_activities_asignado_usuario_id_fkey"
  FOREIGN KEY ("asignado_usuario_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
