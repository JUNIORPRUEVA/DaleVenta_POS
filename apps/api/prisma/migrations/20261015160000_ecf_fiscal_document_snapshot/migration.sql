-- Persistencia íntegra del comprobante preparado (aditiva).
--
-- Hasta ahora el documento preparado solo dejaba un RESUMEN (payload_summary) y
-- una huella (payload_fingerprint). Con eso no era posible reconstruir
-- exactamente lo que se preparó: se sabía el total y cuántas líneas había, pero
-- no las partidas, ni el emisor, ni el receptor, ni las referencias.
--
-- Esta columna guarda el documento fiscal COMPLETO tal como se preparó. Se
-- escribe una sola vez, en la preparación, y a partir de ahí es inmutable: una
-- edición posterior del producto, del cliente o de la venta no puede alterarlo
-- en silencio. La huella ya persistida permite verificar la reconstrucción.
--
-- No se toca ninguna fila existente: queda NULL en los documentos anteriores y
-- la columna es opcional por diseño.

ALTER TABLE ecf_electronic_documents ADD COLUMN fiscal_document JSONB;

CREATE FUNCTION ecf_protect_fiscal_document() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  -- Una vez escrito, el documento fiscal no cambia NUNCA. Distinto de las
  -- demás columnas: el resto de la fila puede evolucionar (estado, resumen de
  -- emisión, evidencia) sin que el contenido preparado se altere.
  IF OLD.fiscal_document IS NOT NULL
     AND NEW.fiscal_document IS DISTINCT FROM OLD.fiscal_document
  THEN RAISE EXCEPTION 'ECF_FISCAL_DOCUMENT_IMMUTABLE'; END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER ecf_protect_fiscal_document BEFORE UPDATE ON ecf_electronic_documents
  FOR EACH ROW EXECUTE FUNCTION ecf_protect_fiscal_document();
