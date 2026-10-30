import {
  BadRequestException,
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Put,
  Req,
  Res,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import { FileInterceptor } from "@nestjs/platform-express";
import { Request, Response } from "express";
import { Permissions } from "../auth/roles.decorator";
import { RolesGuard } from "../auth/roles.guard";
import type { TenantUser } from "../auth/tenant-context";
import {
  RecordEcfDgiiAuthorizationDto,
  RegisterEcfDgiiEvidenceDto,
  ReviewEcfDgiiEvidenceDto,
  UpdateEcfDgiiHabilitationDto,
  UpdateEcfDgiiRequirementDto,
  UploadEcfDgiiDocumentDto,
} from "./dto/ecf-dgii.dto";
import { UpdateEcfConfigDto, UpdateEcfOnboardingStepDto } from "./dto/ecf.dto";
import {
  SaveEcfDgiiDraftDto,
  SubmitEcfDgiiApplicationDto,
} from "./dto/ecf-dgii-application.dto";
import { EcfAlanubeClient } from "./ecf-alanube.client";
import { EcfDgiiApplicationService } from "./dgii/ecf-dgii-application.service";
import { EcfDgiiActivationService } from "./dgii/ecf-dgii-activation.service";
import { EcfSupportGrantService } from "./dgii/ecf-support-grant.service";
import { EcfDgiiDocumentsService } from "./dgii/ecf-dgii-documents.service";
import { EcfDgiiHabilitationService } from "./dgii/ecf-dgii-habilitation.service";
import { EcfService } from "./ecf.service";

/** Forma mínima del archivo que entrega `FileInterceptor`. */
type UploadedDocument = {
  buffer: Buffer;
  originalname: string;
  mimetype: string;
  size: number;
};

@UseGuards(AuthGuard("jwt"), RolesGuard)
@Controller("ecf")
export class EcfController {
  constructor(
    private readonly ecf: EcfService,
    private readonly alanube: EcfAlanubeClient,
    private readonly dgii: EcfDgiiHabilitationService,
    private readonly dgiiDocs: EcfDgiiDocumentsService,
    private readonly application: EcfDgiiApplicationService,
    private readonly activation: EcfDgiiActivationService,
    private readonly supportGrants: EcfSupportGrantService,
  ) {}

  /**
   * Concesiones de asistencia que la EMPRESA otorga a FULLTECH.
   *
   * Sin una de estas concesiones vigentes, el personal de plataforma no puede
   * abrir el expediente. La empresa decide alcance, vigencia y revocación.
   */
  @Get("dgii/support-grants")
  @Permissions("viewEcfOnboarding", "viewEcfDgiiHabilitation")
  listSupportGrants(@Req() req: Request) {
    return this.supportGrants.list(req.user as TenantUser);
  }

  @Post("dgii/support-grants")
  @Permissions("manageEcfOnboarding")
  createSupportGrant(
    @Req() req: Request,
    @Body() body: { scopes?: string[]; expiresAt?: string; reason?: string },
  ) {
    return this.supportGrants.create(req.user as TenantUser, {
      scopes: body?.scopes ?? [],
      expiresAt: body?.expiresAt ?? new Date(0),
      reason: body?.reason ?? null,
    });
  }

  @Post("dgii/support-grants/:id/revoke")
  @Permissions("manageEcfOnboarding")
  revokeSupportGrant(@Req() req: Request, @Param("id") id: string) {
    return this.supportGrants.revoke(req.user as TenantUser, id);
  }

  /** Estado del motor de activación e-CF (self-service). */
  @Get("dgii/activation")  @Permissions("viewEcfOnboarding", "viewEcfDgiiHabilitation")
  getActivation(@Req() req: Request) {
    return this.activation.getActivation(req.user as TenantUser);
  }

  /**
   * Arranca o continúa la activación. Idempotente.
   *
   * Solo ejecuta los pasos de los que el motor es dueño; el resto queda
   * bloqueado con su motivo. El transporte es simulado y así se declara.
   */
  @Post("dgii/activation/start")
  @Permissions("manageEcfOnboarding")
  startActivation(@Req() req: Request) {
    return this.activation.start(req.user as TenantUser);
  }

  /** Reintenta un paso que falló, sin saltarse el orden del catálogo. */
  @Post("dgii/activation/steps/:key/retry")
  @Permissions("manageEcfOnboarding")
  retryActivationStep(@Req() req: Request, @Param("key") key: string) {
    return this.activation.retryStep(req.user as TenantUser, key);
  }

  /** Borrador persistente del expediente + lo que falta para enviarlo. */
  @Get("dgii/application/draft")
  @Permissions("viewEcfOnboarding", "viewEcfDgiiHabilitation")
  getApplicationDraft(@Req() req: Request) {
    return this.application.getDraft(req.user as TenantUser);
  }

  /**
   * Guarda el borrador. Acepta expedientes incompletos a propósito: es trabajo
   * en curso y no toca configuración fiscal ni documentos históricos.
   */
  @Put("dgii/application/draft")
  @Permissions("manageEcfOnboarding", "registerEcfDgiiEvidence")
  saveApplicationDraft(
    @Req() req: Request,
    @Body() dto: SaveEcfDgiiDraftDto,
  ) {
    return this.application.saveDraft(req.user as TenantUser, dto);
  }

  /**
   * Envía el expediente a revisión creando una versión INMUTABLE.
   *
   * Exige la versión vigente del consentimiento; guarda los datos presentados,
   * los hashes de los documentos y quién lo envió. No autoriza nada ante la DGII.
   */
  @Post("dgii/application/submit")
  @Permissions("manageEcfOnboarding", "registerEcfDgiiEvidence")
  submitApplication(
    @Req() req: Request,
    @Body() dto: SubmitEcfDgiiApplicationDto,
  ) {
    return this.application.submit(req.user as TenantUser, dto);
  }

  /** Versiones enviadas del expediente (histórico inmutable). */
  @Get("dgii/application/snapshots")
  @Permissions("viewEcfOnboarding", "viewEcfDgiiHabilitation")
  listApplicationSnapshots(@Req() req: Request) {
    return this.application.listSnapshots(req.user as TenantUser);
  }

  @Get("config")
  @Permissions("viewEcfConfig")
  getConfig(@Req() req: Request) {
    return this.ecf.getConfig(req.user as TenantUser);
  }

  @Patch("config")
  @Permissions("manageEcfConfig")
  updateConfig(@Req() req: Request, @Body() dto: UpdateEcfConfigDto) {
    return this.ecf.updateConfig(req.user as TenantUser, dto);
  }

  @Get("onboarding")
  @Permissions("viewEcfOnboarding")
  getOnboarding(@Req() req: Request) {
    return this.ecf.getOnboarding(req.user as TenantUser);
  }

  @Patch("onboarding/steps/:stepKey")
  @Permissions("manageEcfOnboarding")
  updateStep(
    @Req() req: Request,
    @Param("stepKey") stepKey: string,
    @Body() dto: UpdateEcfOnboardingStepDto,
  ) {
    return this.ecf.updateStep(req.user as TenantUser, stepKey, dto);
  }

  @Get("onboarding/history")
  @Permissions("viewEcfOnboarding")
  listAudit(@Req() req: Request) {
    return this.ecf.listAudit(req.user as TenantUser);
  }

  @Get("provider/status")
  @Permissions("viewEcfConfig")
  getProviderStatus(@Req() req: Request) {
    return this.ecf.getProviderStatus(
      req.user as TenantUser,
      this.alanube.getRuntimeState(),
    );
  }

  // ---------------------------------------------------------------------------
  // Habilitación DGII POR EMPRESA
  //
  // SEGUIMIENTO del proceso de incorporación. Requiere autenticación, RBAC y
  // aislamiento multiempresa. Ninguna de estas rutas concede autorización
  // oficial de emisión: `APPROVED` exige un registro oficial verificado con
  // evidencia documental revisada, y la emisión real permanece bloqueada.
  //
  // Permisos: los nombres nuevos son GRANULARES y no vienen concedidos de
  // fábrica; se listan junto a los antiguos para no retirar accesos ya otorgados
  // (el guard acepta cualquiera de los declarados). La verificación oficial y la
  // revisión de evidencias NO tienen alias: exigen su permiso propio.
  // ---------------------------------------------------------------------------

  @Get("dgii/habilitation")
  @Permissions("viewEcfOnboarding", "viewEcfDgiiHabilitation")
  getDgiiHabilitation(@Req() req: Request) {
    return this.dgii.getHabilitation(req.user as TenantUser);
  }

  @Patch("dgii/habilitation")
  @Permissions("manageEcfOnboarding", "manageEcfDgiiRequirements")
  updateDgiiHabilitation(
    @Req() req: Request,
    @Body() dto: UpdateEcfDgiiHabilitationDto,
  ) {
    return this.dgii.updateHabilitation(req.user as TenantUser, dto);
  }

  @Patch("dgii/requirements/:key")
  @Permissions("manageEcfOnboarding", "manageEcfDgiiRequirements")
  updateDgiiRequirement(
    @Req() req: Request,
    @Param("key") key: string,
    @Body() dto: UpdateEcfDgiiRequirementDto,
  ) {
    return this.dgii.updateRequirement(req.user as TenantUser, key, dto);
  }

  @Get("dgii/history")
  @Permissions("viewEcfOnboarding", "viewEcfDgiiHabilitation")
  listDgiiHistory(@Req() req: Request) {
    return this.dgii.listHistory(req.user as TenantUser);
  }

  @Get("dgii/evidence")
  @Permissions("viewEcfOnboarding", "viewEcfDgiiHabilitation")
  listDgiiEvidence(@Req() req: Request) {
    return this.dgii.listEvidence(req.user as TenantUser);
  }

  @Post("dgii/evidence")
  @Permissions("manageEcfOnboarding", "registerEcfDgiiEvidence")
  registerDgiiEvidence(
    @Req() req: Request,
    @Body() dto: RegisterEcfDgiiEvidenceDto,
  ) {
    return this.dgii.registerEvidence(req.user as TenantUser, dto);
  }

  /** Revisión interna de una evidencia. No autoriza nada por sí sola. */
  @Patch("dgii/evidence/:id/review")
  @Permissions("reviewEcfDgiiEvidence")
  reviewDgiiEvidence(
    @Req() req: Request,
    @Param("id") id: string,
    @Body() dto: ReviewEcfDgiiEvidenceDto,
  ) {
    return this.dgii.reviewEvidence(req.user as TenantUser, id, dto);
  }

  /**
   * Registra la autorización oficial recibida.
   *
   * Exige permiso propio (`recordEcfDgiiOfficialVerification`) y una evidencia
   * de documento OFICIAL ya REVISADA: una carga manual nunca se convierte en
   * autorización oficial.
   */
  @Post("dgii/authorization")
  @Permissions("recordEcfDgiiOfficialVerification")
  recordDgiiAuthorization(
    @Req() req: Request,
    @Body() dto: RecordEcfDgiiAuthorizationDto,
  ) {
    return this.dgii.recordAuthorization(req.user as TenantUser, dto);
  }

  @Post("dgii/authorization/revoke")
  @Permissions("recordEcfDgiiOfficialVerification")
  revokeDgiiAuthorization(@Req() req: Request) {
    return this.dgii.revokeAuthorization(req.user as TenantUser);
  }

  // ---------------------------------------------------------------------------
  // Documentos del expediente
  //
  // La carga valida el tipo REAL por contenido (no por extensión), calcula el
  // SHA-256, escribe en almacenamiento privado y registra la evidencia como
  // MANUAL_DECLARATION. La descarga es autenticada y acotada a la empresa del
  // contexto: un id de otra empresa responde 404, igual que uno inexistente.
  // ---------------------------------------------------------------------------

  @Post("dgii/documents")
  @Permissions("manageEcfOnboarding", "registerEcfDgiiEvidence")
  @UseInterceptors(FileInterceptor("file"))
  uploadDgiiDocument(
    @Req() req: Request,
    @Body() dto: UploadEcfDgiiDocumentDto,
    @UploadedFile() file: UploadedDocument | undefined,
  ) {
    if (!file) throw new BadRequestException("ECF_DGII_DOCUMENT_REQUIRED");
    return this.dgiiDocs.upload(req.user as TenantUser, {
      kind: dto.kind,
      fileName: file.originalname,
      declaredMime: file.mimetype,
      buffer: file.buffer,
      size: file.size,
    });
  }

  @Get("dgii/documents/:id/file")
  @Permissions("viewEcfOnboarding", "viewEcfDgiiHabilitation")
  async downloadDgiiDocument(
    @Req() req: Request,
    @Param("id") id: string,
    @Res({ passthrough: true }) res: Response,
  ) {
    const doc = await this.dgiiDocs.download(req.user as TenantUser, id);
    res.setHeader("Content-Type", doc.mimeType);
    res.setHeader(
      "Content-Disposition",
      `attachment; filename*=UTF-8''${encodeURIComponent(doc.fileName)}`,
    );
    res.setHeader("X-Content-SHA256", doc.sha256 ?? "");
    res.setHeader("Cache-Control", "no-store");
    return doc.buffer;
  }
}

