import { ConflictException, Injectable } from "@nestjs/common";
import { requireTenant, type TenantUser } from "../../../auth/tenant-context";
import { PrismaService } from "../../../prisma/prisma.service";
import { EcfEmissionService } from "../../documents/ecf-emission.service";
import { fingerprint } from "../../documents/ecf-document-idempotency.service";
import type { EcfDocumentType } from "../../fiscal-core/ecf-fiscal-document";
import { mapEcfToDosaDraft } from "./dosa-ecf.mapper";
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
    if (documentType !== "E31" && documentType !== "E34") {
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
      // Huella del cuerpo REALMENTE enviado, no la del payload preparado.
      { body, fingerprint: fingerprint(body) },
    );

    return {
      ok: true as const,
      environment: authorized.environment,
      encf,
      ...outcome,
    };
  }
}
