import type { DosaEcfRequestBody } from "./dosa-ecf.contract";

/** DOSA's documented envelope: the lines belong to detallesItems.items. */
export type DosaOutboundRequestBody = Omit<DosaEcfRequestBody, "detallesItems"> & {
  detallesItems: { items: DosaEcfRequestBody["detallesItems"] };
};

/**
 * Keep the internal draft contract compatible, but serialize the provider's
 * envelope at the HTTP boundary. Also used before computing request evidence,
 * so its fingerprint describes exactly the JSON that leaves the application.
 */
export function toDosaOutboundRequest(
  body: DosaEcfRequestBody | DosaOutboundRequestBody,
): DosaOutboundRequestBody {
  const header = body.encabezado;
  const reference = body.informacionReferencia;
  const credit = header.idDoc.tipoeCF === "34" && reference;
  return {
    ...body,
    encabezado: {
      ...header,
      idDoc: {
        ...header.idDoc,
        ...(header.idDoc.tipoPago !== undefined ? { tipoPago: Number(header.idDoc.tipoPago) } : {}),
        ...(credit ? {
          tipoeCF: reference.NCFModificado.slice(1, 3) as "31" | "32",
          eNCF: reference.NCFModificado,
        } : {}),
      },
      emisor: {
        ...header.emisor,
        fechaEmision: credit ? reference.FechaNCFModificado : header.emisor.fechaEmision ?? header.idDoc.fechaEmision,
      },
    },
    detallesItems: {
      items: Array.isArray(body.detallesItems)
        ? body.detallesItems
        : body.detallesItems.items,
    },
  };
}
