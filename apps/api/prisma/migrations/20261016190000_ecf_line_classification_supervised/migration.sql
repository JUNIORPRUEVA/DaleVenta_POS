-- Clasificación fiscal SUPERVISADA de partidas (F1).
--
-- Contexto: una partida fuera de inventario no tiene producto del que heredar si
-- es bien o servicio, así que queda con `item_type_snapshot = NULL` y la
-- preparación del e-CF la rechaza —correctamente— en lugar de adivinar. Sin una
-- vía supervisada, esa venta nunca podría facturarse electrónicamente.
--
-- Diseño elegido: un registro APPEND-ONLY, fechado y auditado, que el módulo
-- consulta cuando la clasificación congelada está ausente. La venta y su
-- `SaleItem` NO se modifican: reescribir la clasificación de una venta histórica
-- sería reescribir un hecho, y es exactamente lo que hay que evitar.
--
-- Alcance deliberadamente mínimo: solo los objetos de esta mejora. La deriva
-- PREEXISTENTE y ajena (diferencias de DEFAULT en columnas UUID e índice único
-- parcial de telemetry_outbox) NO se toca aquí.
--
-- Aislamiento multiempresa: cada fila lleva `company_id` y el servicio acota
-- siempre por el `companyId` del contexto autenticado. No se añade una clave
-- foránea compuesta contra las tablas del POS porque los nombres de esas tablas
-- no están declarados en el esquema de Prisma; la pertenencia se valida en el
-- servicio y se verifica con pruebas de dos empresas.

-- CreateTable
CREATE TABLE "ecf_line_classifications" (
    "id" UUID NOT NULL,
    "company_id" UUID NOT NULL,
    "sale_id" UUID NOT NULL,
    "sale_item_id" UUID NOT NULL,
    "classification" "product_item_type" NOT NULL,
    "previous_classification" "product_item_type",
    "reason" VARCHAR(300) NOT NULL,
    "decided_by_user_id" UUID NOT NULL,
    "decided_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ecf_line_classifications_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ecf_line_classifications_company_id_sale_item_id_decided_at_idx" ON "ecf_line_classifications"("company_id", "sale_item_id", "decided_at");

-- CreateIndex
CREATE INDEX "ecf_line_classifications_company_id_sale_id_idx" ON "ecf_line_classifications"("company_id", "sale_id");

-- AddForeignKey
ALTER TABLE "ecf_line_classifications" ADD CONSTRAINT "ecf_line_classifications_company_id_fkey" FOREIGN KEY ("company_id") REFERENCES "companies"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Un motivo vacío no es auditable: si alguien confirmó la clasificación, tiene
-- que poder leerse POR QUÉ lo hizo.
ALTER TABLE "ecf_line_classifications"
  ADD CONSTRAINT "ecf_line_classifications_reason_length_check"
  CHECK (length(btrim("reason")) BETWEEN 3 AND 300);

-- Nada puede quedar sin fecha de decisión ni sin autor.
ALTER TABLE "ecf_line_classifications"
  ADD CONSTRAINT "ecf_line_classifications_decision_identity_check"
  CHECK ("decided_by_user_id" IS NOT NULL AND "decided_at" IS NOT NULL);

-- Inmutabilidad: la tabla es APPEND-ONLY. Corregir una clasificación equivocada
-- consiste en AÑADIR otro registro (y manda el más reciente), nunca en reescribir
-- el anterior. Así el valor previo y el confirmado quedan ambos auditados.
CREATE OR REPLACE FUNCTION ecf_line_classification_immutable()
RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'ECF_LINE_CLASSIFICATION_IMMUTABLE';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER ecf_line_classification_protect
  BEFORE UPDATE OR DELETE ON "ecf_line_classifications"
  FOR EACH ROW EXECUTE FUNCTION ecf_line_classification_immutable();
