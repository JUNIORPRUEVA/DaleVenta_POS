import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query, Req, UseGuards } from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import { Request } from "express";
import { Permissions } from "../auth/roles.decorator";
import { RolesGuard } from "../auth/roles.guard";
import type { TenantUser } from "../auth/tenant-context";
import {
  ConfirmEcfLineClassificationDto,
  EcfSalesFiscalQueryDto,
  DeclareEcfAuthorizedSequenceDto,
  ListEcfDocumentsQueryDto,
  PrepareEcfConsumoDto,
  PrepareEcfCreditNoteDto,
  PrepareEcfDocumentDto,
  RegisterEcfSequenceDto,
  RegisterEcfSaleWithoutDocumentDto,
  RenewEcfSequenceDto,
  SimulateEcfDispatchDto,
} from "./dto/ecf-documents.dto";
import { EcfDocumentQueryService } from "./documents/ecf-document-query.service";
import { EcfLineClassificationService } from "./documents/ecf-line-classification.service";
import { EcfPreparationService } from "./documents/ecf-preparation.service";
import { EcfSalesWithoutDocumentService } from "./documents/ecf-sales-without-document.service";
import { EcfSimulatedDispatchService } from "./documents/ecf-simulated-dispatch.service";
import { DosaEmissionDispatchService } from "./provider/dosa/dosa-emission-dispatch.service";

// Read-only, tenant-scoped surface for the client applications, plus ONE
// deliberately simulated write path. Preparing a draft against the REAL provider
// is a controlled operational step that no HTTP route exposes: nothing here can
// reach Alanube or the DGII. The single exception is `simulate-dispatch`, which
// wires `dispatchOnce` against the LOCAL SIMULATOR only and is refused outside a
// local UAT environment (see `ecf-simulated-dispatch.policy.ts`). Real fiscal
// emission therefore remains unreachable by construction.
@UseGuards(AuthGuard("jwt"), RolesGuard)
@Controller("ecf")
export class EcfDocumentsController {
  constructor(
    private readonly documents: EcfDocumentQueryService,
    private readonly preparation: EcfPreparationService,
    private readonly simulatedDispatch: EcfSimulatedDispatchService,
    private readonly lineClassifications: EcfLineClassificationService,
    private readonly dosaDispatch: DosaEmissionDispatchService,
    private readonly salesWithoutDocument: EcfSalesWithoutDocumentService,
  ) {}

  /**
   * Partidas de una venta que necesitan clasificación fiscal supervisada.
   *
   * Es una lectura: informa qué partidas bloquean la preparación y por qué.
   */
  @Get("documents/:saleId/pending-classifications")
  @Permissions("viewEcfDocuments")
  pendingClassifications(@Req() req: Request, @Param("saleId") saleId: string) {
    return this.lineClassifications.listPending(
      req.user as TenantUser,
      saleId,
    );
  }

  /**
   * Confirma la clasificación fiscal de una partida sin producto (F1).
   *
   * Permiso propio y SIN alias: es una decisión fiscal que no debe heredarse de
   * un permiso de gestión genérico. No autoriza nada ante la DGII y no emite.
   */
  @Post("documents/line-classifications")
  @Permissions("confirmEcfLineClassification")
  confirmLineClassification(
    @Req() req: Request,
    @Body() dto: ConfirmEcfLineClassificationDto,
  ) {
    return this.lineClassifications.confirm(req.user as TenantUser, dto);
  }

  @Get("capabilities")
  @Permissions("viewEcfDocuments")
  capabilities(@Req() req: Request) {
    return this.documents.capabilities(req.user as TenantUser);
  }

  /**
   * Prepara un borrador local desde una venta real. No emite: no hay ruta que
   * contacte al proveedor. Consume numeración, por eso exige empresa habilitada.
   */
  @Post("documents/prepare")
  @Permissions("prepareEcfDocuments")
  prepare(@Req() req: Request, @Body() dto: PrepareEcfDocumentDto) {
    return this.preparation.prepareFromSale(req.user as TenantUser, {
      saleId: dto.saleId,
      documentType: dto.documentType,
      paymentType: dto.paymentType,
      incomeType: dto.incomeType,
      sequenceDueDate: dto.sequenceDueDate,
      paymentDeadline: dto.paymentDeadline,
    });
  }

  /**
   * Prepara un borrador local de CONSUMO (E32) desde una venta real.
   *
   * A diferencia de E31, este flujo NO consume numeración de la empresa y NO
   * toca el cupo único de sandbox: deja el comprobante listo, sin e-NCF. La
   * emisión de E32 sigue siendo un paso operativo controlado.
   */
  @Post("documents/prepare-consumo")
  @Permissions("prepareEcfDocuments")
  prepareConsumo(@Req() req: Request, @Body() dto: PrepareEcfConsumoDto) {
    return this.preparation.prepareConsumoFromSale(req.user as TenantUser, {
      saleId: dto.saleId,
      documentType: dto.documentType,
      paymentType: dto.paymentType,
      incomeType: dto.incomeType,
      sequenceDueDate: dto.sequenceDueDate,
      paymentDeadline: dto.paymentDeadline,
    });
  }

  /**
   * Prepara una nota de crédito E34 sobre un comprobante original aceptado.
   * Reserva el crédito fiscal y NO toca inventario, caja, turnos ni abonos.
   */
  @Post("documents/prepare-credit-note")
  @Permissions("prepareEcfDocuments")
  prepareCreditNote(@Req() req: Request, @Body() dto: PrepareEcfCreditNoteDto) {
    return this.preparation.prepareCreditNote(req.user as TenantUser, {
      originalDocumentId: dto.originalDocumentId,
      clientRequestId: dto.clientRequestId,
      refundKind: dto.refundKind,
      lines: dto.lines,
      modificationCode: dto.modificationCode,
      modificationReason: dto.modificationReason,
      paymentType: dto.paymentType,
      creditNoteIndicator: dto.creditNoteIndicator,
      sequenceDueDate: dto.sequenceDueDate,
    });
  }

  /**
   * DESPACHO SIMULADO — validación local de la cadena completa.
   *
   * Cablea `dispatchOnce` a HTTP por primera vez, pero **solo** contra el
   * proveedor SIMULADO: no hay red, no hay credenciales de Alanube y no se
   * declara aceptación de la DGII (una observación correlacionada acaba en
   * `HUMAN_REVIEW_REQUIRED` para revisión humana).
   *
   * La política (`ecf-simulated-dispatch.policy.ts`) rechaza la llamada si el
   * transporte real estuviera activo o si el entorno no es una UAT local.
   */
  @Post("documents/:id/simulate-dispatch")
  @Permissions("prepareEcfDocuments")
  simulateDispatch(
    @Req() req: Request,
    @Param("id") id: string,
    @Body() dto: SimulateEcfDispatchDto,
  ) {
    return this.simulatedDispatch.dispatch(
      req.user as TenantUser,
      id,
      dto.scenario ?? "PROVIDER_ACCEPTED",
    );
  }

  /**
   * DESPACHO AUTORIZADO al proveedor DOSA de la empresa.
   *
   * Es la acción que dispara la emisión real cuando las compuertas lo permiten.
   * No abre ninguna puerta por sí sola: el orquestador pasa por la barrera del
   * documento, la compuerta fiscal y la bóveda de credenciales de ESA empresa y
   * ESE ambiente. Con `DOSA_EMISSION_ENABLED=false` (valor por defecto) la
   * compuerta rechaza antes de tocar la red.
   *
   * El permiso es el mismo que ya gobierna preparar y simular: emitir un
   * comprobante no puede quedar al alcance de quien no puede prepararlo.
   */
  @Post("documents/:id/dispatch-dosa")
  @Permissions("prepareEcfDocuments")
  dispatchDosa(@Req() req: Request, @Param("id") id: string) {
    return this.dosaDispatch.dispatch(req.user as TenantUser, id);
  }

  @Post("documents/:id/recover-dosa")
  @Permissions("prepareEcfDocuments")
  recoverDosa(@Req() req: Request, @Param("id") id: string) {
    return this.dosaDispatch.dispatch(req.user as TenantUser, id, true);
  }

  @Get("sales/:saleId/print")
  printForSale(@Req() req: Request, @Param("saleId", ParseUUIDPipe) saleId: string) {
    return this.documents.printForSale(req.user as TenantUser, saleId);
  }

  @Get("sales/fiscal")
  salesFiscal(@Req() req: Request, @Query() query: EcfSalesFiscalQueryDto) {
    return this.documents.salesFiscal(req.user as TenantUser, query.ids);
  }

  @Get("documents")
  @Permissions("viewEcfDocuments")
  list(@Req() req: Request, @Query() query: ListEcfDocumentsQueryDto) {
    return this.documents.list(req.user as TenantUser, query);
  }
  @Get("documents/summary")
  @Permissions("viewEcfDocuments")
  summary(@Req() req: Request) {
    return this.documents.summary(req.user as TenantUser);
  }

  @Get("documents/eligible-originals")
  @Permissions("viewEcfDocuments")
  eligibleOriginals(@Req() req: Request) {
    return this.documents.eligibleOriginals(req.user as TenantUser);
  }

  /**
   * Comprobantes preparados que nunca llegaron al proveedor.
   *
   * Se declara ANTES de `documents/:id` porque Nest resuelve por orden de
   * declaración y, si no, `pending-dispatch` se leería como un id.
   */
  @Get("documents/pending-dispatch")
  @Permissions("viewEcfDocuments")
  pendingDispatch(@Req() req: Request) {
    return this.dosaDispatch.pending(req.user as TenantUser);
  }

  /**
   * Recupera las operaciones pendientes: reintenta el envío de lo que quedó
   * preparado sin salir. No puede duplicar comprobantes: cada envío exige cero
   * intentos previos y se reclama antes de la red.
   */
  @Post("documents/dispatch-pending")
  @Permissions("prepareEcfDocuments")
  dispatchPending(@Req() req: Request) {
    return this.dosaDispatch.dispatchPending(req.user as TenantUser);
  }

  @Get("documents/:id")
  @Permissions("viewEcfDocuments")
  detail(@Req() req: Request, @Param("id") id: string) {
    return this.documents.detail(req.user as TenantUser, id);
  }

  @Get("documents/:id/print")
  @Permissions("viewEcfDocuments")
  printDocument(@Req() req: Request, @Param("id", ParseUUIDPipe) id: string) {
    return this.documents.printDocument(req.user as TenantUser, id);
  }

  @Get("sequences")
  @Permissions("viewEcfDocuments")
  listSequences(@Req() req: Request) {
    return this.documents.listSequences(req.user as TenantUser);
  }

  @Post("sequences")
  @Permissions("manageEcfSequences")
  registerSequence(@Req() req: Request, @Body() dto: RegisterEcfSequenceDto) {
    return this.documents.registerSequence(req.user as TenantUser, dto);
  }

  @Post("sequences/renew")
  @Permissions("manageEcfSequences")
  renewSequence(@Req() req: Request, @Body() dto: RenewEcfSequenceDto) {
    return this.documents.renewSequence(req.user as TenantUser, dto);
  }

  /** Lo que la DGII autorizó a esta empresa, por tipo de comprobante. */
  @Get("dgii/authorized-sequences")
  @Permissions("viewEcfDocuments")
  listAuthorizedSequences(@Req() req: Request) {
    return this.documents.listAuthorizedSequences(req.user as TenantUser);
  }

  /**
   * Declaración del cliente sobre la numeración autorizada por la DGII.
   *
   * Es la única puerta para habilitar la numeración: sin esta fila, registrar un
   * rango falla con `ECF_SEQUENCE_NOT_AUTHORIZED`.
   */
  @Post("dgii/authorized-sequences")
  @Permissions("manageEcfSequences")
  declareAuthorizedSequence(
    @Req() req: Request,
    @Body() dto: DeclareEcfAuthorizedSequenceDto,
  ) {
    return this.documents.declareAuthorizedSequence(req.user as TenantUser, dto);
  }

  /** Excepciones registradas: ventas hechas sin comprobante electrónico. */
  @Get("sales-without-document")
  @Permissions("viewEcfDocuments")
  listSalesWithoutDocument(@Req() req: Request) {
    return this.salesWithoutDocument.list(req.user as TenantUser);
  }

  /**
   * Registra que una venta se hizo SIN comprobante electrónico.
   *
   * Es la contraparte de la opción «Normal»: el servidor exige que la empresa
   * haya habilitado la excepción y guarda el motivo con la venta y el usuario.
   * Se pide permiso fiscal de preparación porque decide el destino fiscal de una
   * venta ya cerrada; no es una acción genérica de ventas.
   */
  @Post("sales-without-document")
  @Permissions("prepareEcfDocuments")
  registerSaleWithoutDocument(
    @Req() req: Request,
    @Body() dto: RegisterEcfSaleWithoutDocumentDto,
  ) {
    return this.salesWithoutDocument.register(req.user as TenantUser, dto);
  }
}
