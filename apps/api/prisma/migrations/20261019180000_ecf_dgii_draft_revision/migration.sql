-- Control de concurrencia optimista del borrador del expediente.
--
-- Añade una revisión monótona por empresa. El servidor solo escribe si la
-- revisión que envió el cliente sigue siendo la vigente, de modo que dos
-- guardados que llegan en orden distinto no pueden terminar aplicando el más
-- antiguo. Es aditivo y no toca ninguna otra tabla.

ALTER TABLE "ecf_dgii_habilitations" ADD COLUMN "draft_revision" INTEGER NOT NULL DEFAULT 0;
