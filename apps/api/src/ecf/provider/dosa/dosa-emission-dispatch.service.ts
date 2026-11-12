import { ConflictException, Injectable } from "@nestjs/common";
import { requireTenant, type TenantUser } from "../../../auth/tenant-context";
import { PrismaService } from "../../../prisma/prisma.service";
import { EcfEmissionService } from "../../documents/ecf-emission.service";
import { fingerprint } from "../../documents/ecf-document-idempotency.service";
import type { EcfDocumentType } from "../../fiscal-core/ecf-fiscal-document";
import { mapEcfToDosaDraft } from "./dosa-ecf.mapper";
import { DOSA_GATE_SUPPORTED_TYPES } from "./dosa-emission.gate";
import { assessDosaProviderResponse } from "./dosa-provider-response";
import { DosaEmissionService } from "./dosa-emission.service";
import { DosaEmissionWire } from "./dosa-emission.wire";

/**
 * ORQUESTADOR de emisión DOSA desde un comprobante electrónico de FullPOS.
 *
 * Qué faltaba y qué hace ahora
 * ---------------------------
 * Las piezas existían y estaban probadas por separado, pero nadie las unía:
 * `DosaEmissionService.emit` no tenía llamadores, `DosaEmissionWire` no se
 * instanciaba y la única ruta de despacho usaba el simulador de Alanube. Este
 * servicio es el eslabón que faltaba, y **no reimplementa nada**:
 *
 *  - reutiliza el mapeador oficial (`mapEcfToDosaDraft`) para construir el
 *    cuerpo del proveedor a partir del documento fiscal persistido;
 *  - reutiliza la autorización de `DosaEmissionService.authorizeForDispatch`
 *    (barrera del documento + compuerta fiscal + bóveda de credenciales);
 *  - reutiliza `DosaEmissionWire` + `EcfEmissionService.dispatchOnce` para
 *    reclamar la tentativa, enviar UNA sola vez y persistir evidencia y estado.
 *
 * Por qué el cuerpo se reconstruye aquí y no se reutiliza el preparado
 * -------------------------------------------------------------------
 * `POST /ecf/documents/prepare` guarda el DOM interno (el que usa el proveedor
 * por defecto). DOSA exige su propio contrato (`encabezado` + `detallesItems`).
 * Enviar el primero al cliente de DOSA produciría un comprobante mal formado.
 * Se reconstruye desde `fiscal_document`, que es **inmutable** (trigger en base
 * de datos) y por tanto es la fuente de verdad del comprobante, y la huella que
 * se registra es la del cuerpo realmente enviado.
 *
 * Reglas que el orquestador NO relaja
 * -----------------------------------
 *  - `companyId` sale del contexto autenticado; el documento se busca siempre
 *    con `{ companyId, id }`, así que un id ajeno se comporta como inexistente.
 *  - El RNC emisor es el de la empresa (el de la emisión preparada) y la
 *    barrera lo contrasta con el del cuerpo.
 *  - Sin autorización fiscal (compuerta) no se abre la bóveda ni se envía nada.
 *  - El estado final NUNCA es aceptación fiscal automática: `dispatchOnce` deja
 *    `HUMAN_REVIEW_REQUIRED` ante cualquier respuesta correlacionada.
 */
@Injectable()
export class DosaEmissionDispatchService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly dosa: DosaEmissionService,
    private readonly ecfEmission: EcfEmissionService,
  ) {}

  /**
   * Despacha un comprobante ya preparado al proveedor DOSA de SU empresa.
   *
   * @returns el resultado del orquestador común (estado, observación, HTTP) o un
   *   rechazo fiscal explícito con los motivos. Un rechazo **no** es una
   *   excepción para los bloqueos de negocio: se devuelve con su código para que
   *   la interfaz explique qué falta.
   */
  async dispatch(user: TenantUser, documentId: string) {
    const companyId = requireTenant(user);
    if (!documentId || typeof documentId !== "string") {
      throw new ConflictException("ECF_DOSA_DISPATCH_DOCUMENT_REQUIRED");
    }

    // Aislamiento: el documento de otra empresa se comporta como inexistente.
    const document = await this.prisma.ecfElectronicDocument.findFirst({
      where: { companyId, id: documentId },
      select: {
        id: true,
        documentType: true,
        status: true,
        fiscalDocument: true,
        payloadSummary: true,
      },
    });
    if (!document) {
      throw new ConflictException("ECF_DOSA_DISPATCH_DOCUMENT_NOT_FOUND");
    }

    const documentType = document.documentType as EcfDocumentType;
    // Los mismos tipos que la compuerta fiscal admite: E31 (crédito fiscal),
    // E32 (consumo) y E34 (nota de crédito). La lista se reutiliza en vez de
    // repetirse para que despacho y compuerta no puedan divergir.
    if (!DOSA_GATE_SUPPORTED_TYPES.includes(documentType)) {
      return {
        ok: false as const,
        code: "ECF_DOSA_DISPATCH_TYPE_UNSUPPORTED",
        blockingReasons: [`ECF_DOSA_DISPATCH_TYPE_UNSUPPORTED:${documentType}`],
      };
    }

    const emission = (
      document.payloadSummary as Record<string, any> | null
    )?.emission as
      | { encf?: string; senderTaxId?: string; payload?: unknown }
      | undefined;
    const encf = (emission?.encf ?? "").trim();
    const senderTaxId = (emission?.senderTaxId ?? "").trim();
    if (!encf || !senderTaxId) {
      return {
        ok: false as const,
        code: "ECF_DOSA_DISPATCH_NOT_PREPARED",
        blockingReasons: ["ECF_DOSA_DISPATCH_NOT_PREPARED"],
      };
    }

    // El contrato del proveedor se construye desde el documento fiscal
    // persistido. Si el mapeador bloquea, no hay nada que enviar.
    const mapped = mapEcfToDosaDraft(document.fiscalDocument as never, {
      encf,
    } as never);
    if (!mapped.ok) {
      return {
        ok: false as const,
        code: "ECF_DOSA_DISPATCH_MAPPING_BLOCKED",
        blockingReasons: [mapped.blockedReason],
      };
    }
    const body = mapped.draft.body;

    // Autorización FISCAL antes de abrir la bóveda. `assessDosaEmissionGate` no
    // consulta el estado de certificación; recibir credenciales ACTIVE no
    // convierte a una empresa en emisora autorizada.
    const fiscal = await this.prisma.ecfCompanyConfiguration.findUnique({
      where: { companyId },
      select: { enabled: true, provider: true, certificationStatus: true },
    });
    if (!fiscal?.enabled) {
      return {
        ok: false as const,
        code: "ECF_DOSA_DISPATCH_COMPANY_NOT_OPTED_IN",
        blockingReasons: ["ECF_DOSA_GATE_COMPANY_NOT_OPTED_IN"],
      };
    }
    if (fiscal.provider !== "DOSA") {
      return {
        ok: false as const,
        code: "ECF_DOSA_DISPATCH_PROVIDER_NOT_DOSA",
        blockingReasons: [`ECF_DOSA_DISPATCH_PROVIDER_NOT_DOSA:${fiscal.provider}`],
      };
    }

    const environment = this.dosa.environment;
    // En TEST se admite la autorización de sandbox; en PRODUCCIÓN sólo la de
    // producción. Una empresa suspendida, bloqueada o sin certificar no emite.
    const authorizedStatuses: readonly string[] =
      environment === "production"
        ? ["PRODUCTION_READY"]
        : ["AUTHORIZED_SANDBOX", "PRODUCTION_READY"];
    if (!authorizedStatuses.includes(fiscal.certificationStatus)) {
      return {
        ok: false as const,
        code: "ECF_DOSA_DISPATCH_CERTIFICATION_NOT_AUTHORIZED",
        blockingReasons: [
          `ECF_DOSA_DISPATCH_CERTIFICATION_NOT_AUTHORIZED:${fiscal.certificationStatus}`,
        ],
      };
    }

    // Autorización: barrera del documento + compuerta fiscal + bóveda. Todo el
    // orden vive en `DosaEmissionService`, aquí no se duplica ni se reordena.
    const authorized = await this.dosa.authorizeForDispatch({
      companyId,
      // El RNC de la empresa emisora, no una variable global ni el de FULLTECH.
      rnc: senderTaxId,
      documentType,
      senderTaxId,
      // El e-NCF ya se consumió al preparar: la numeración de ESTE documento
      // existe y pertenece a esta empresa.
      sequenceAvailable: true,
      body,
    });
    if (!authorized.ok) {
      return {
        ok: false as const,
        code: authorized.code,
        blockingReasons: authorized.blockingReasons,
      };
    }

    // `dispatchOnce` reclama la tentativa con `FOR UPDATE`, garantiza una sola
    // tentativa `SEND_TO_PROVIDER` por documento y persiste estado, evidencia y
    // respuesta. El cable sólo traduce: no decide nada.
    const wire = new DosaEmissionWire(authorized.client);
    const outcome = await this.ecfEmission.dispatchOnce(
      user,
      documentId,
      wire,
      {
        // Huella del cuerpo REALMENTE enviado, no la del payload preparado.
        body,
        fingerprint: fingerprint(body),
        // La respuesta de DOSA es plana (`trackId`, `encf`, `estado`,
        // `secuenciaUtilizada`) y no correlaciona con el evaluador común, que
        // está modelado sobre Alanube. Sin este evaluador, una respuesta
        // perfectamente legible quedaría como «resultado desconocido».
        observe: ({ statusCode, body: responseBody }) =>
          assessDosaProviderResponse(statusCode, responseBody, {
            documentType,
            expectedEncf: encf,
            expectedTaxId: senderTaxId,
          }),
      },
    );

    return {
      ok: true as const,
      environment: authorized.environment,
      encf,
      ...outcome,
    };
  }

  /**
   * Comprobantes preparados que todavía NO se enviaron al proveedor.
   *
   * Es una lectura, acotada a la empresa del contexto. Un documento con un
   * intento `SEND_TO_PROVIDER` **no** aparece aunque su estado sea preparado:
   * el intento es evidencia de que ya salió (o de que salió y no sabemos cómo
   * terminó), y reintentarlo duplicaría el comprobante ante la DGII.
   */
  async pending(user: TenantUser, limit = 25) {
    const companyId = requireTenant(user);
    const take = Number.isInteger(limit) ? Math.min(Math.max(limit, 1), 50) : 25;
    // Se pide de más y se filtra: el filtro «sin intento» no es una columna y
    // hacerlo con una subconsulta encarecería la lectura en el servidor de
    // producción, que va justo de CPU.
    const candidates = await this.prisma.ecfElectronicDocument.findMany({
      where: {
        companyId,
        status: { in: ["LOCAL_VALIDATED", "READY_TO_SEND"] },
        externalProviderId: null,
      },
      orderBy: { createdAt: "asc" },
      take: take * 3,
      select: {
        id: true,
        documentType: true,
        status: true,
        createdAt: true,
        sourceType: true,
        sourceId: true,
      },
    });
    if (candidates.length === 0) return { items: [] as typeof candidates };

    const attempted = await this.prisma.ecfElectronicDocumentAttempt.findMany({
      where: {
        companyId,
        documentId: { in: candidates.map((row) => row.id) },
        operation: "SEND_TO_PROVIDER",
      },
      select: { documentId: true },
    });
    const alreadySent = new Set(attempted.map((row) => row.documentId));
    return {
      items: candidates.filter((row) => !alreadySent.has(row.id)).slice(0, take),
    };
  }

  /**
   * Recupera las operaciones pendientes de la empresa: reintenta el envío de
   * cada comprobante preparado que nunca llegó al proveedor.
   *
   * No puede duplicar nada: `dispatchOnce` exige cero intentos previos, reclama
   * el documento de forma atómica y registra el intento ANTES de la red. Si un
   * despacho se corta a medias, el documento queda con su intento y sale de esta
   * lista: la conciliación es un acto humano, no un reintento automático.
   *
   * Los bloqueos fiscales NO son excepciones: se devuelven por documento para
   * que la interfaz pueda explicar qué falta en cada uno.
   */
  async dispatchPending(user: TenantUser, limit = 10) {
    const pending = await this.pending(user, limit);
    const items: Array<{ documentId: string } & Record<string, unknown>> = [];
    for (const candidate of pending.items) {
      try {
        items.push({ documentId: candidate.id, ...(await this.dispatch(user, candidate.id)) });
      } catch (error) {
        items.push({
          documentId: candidate.id,
          ok: false,
          code: error instanceof ConflictException ? error.message : "ECF_DOSA_DISPATCH_ERROR",
        });
      }
    }
    const dispatched = items.filter((item) => item.ok === true).length;
    return { attempted: items.length, dispatched, items };
  }
}
