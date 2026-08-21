-- Snapshot obligatorio del vencimiento NCF en la venta.
-- Se copia desde ncf_sequences.valid_until en el momento de emitir la venta,
-- para que reimpresiones e historial NO consulten la secuencia vigente.
ALTER TABLE "Sale"
  ADD COLUMN "ncf_expiration_date" TIMESTAMP(3);
