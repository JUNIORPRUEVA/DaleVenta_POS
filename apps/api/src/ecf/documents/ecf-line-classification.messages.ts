/**
 * Mensajes de la clasificación fiscal supervisada (F1).
 *
 * Viven aparte de la política para que esta siga siendo pura y para que el texto
 * que lee el usuario tenga un único origen. Están en español, en el tono del
 * resto del producto, y ninguno promete algo que el sistema no haga.
 */
export const ECF_LINE_CLASSIFICATION_MESSAGES = {
  unknown: "La clasificación debe ser BIEN o SERVICIO.",
  reasonRequired:
    "Indica el motivo de la clasificación (entre 3 y 300 caracteres).",
  fiscallyFrozen:
    "Este comprobante ya fue enviado o está en revisión: cambiar su clasificación alteraría un documento que ya salió. Requiere revisión humana.",
  unchanged: "La partida ya tiene confirmada esa misma clasificación.",
  itemNotFound: "La partida no pertenece a esta venta de la empresa.",
  saleNotFound: "Venta no encontrada.",
  alreadyClassified:
    "La partida ya tiene una clasificación congelada en la venta: no se puede reclasificar.",
} as const;
