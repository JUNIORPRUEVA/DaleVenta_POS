import {
  Body,
  ConflictException,
  BadRequestException,
  Controller,
  Get,
  NotFoundException,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  Req,
  Res,
  UseGuards,
} from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import { EcfDgiiHabilitationState, Prisma } from "@prisma/client";
import { Request, Response } from "express";
import type { TenantUser } from "../../auth/tenant-context";
import { PrismaService } from "../../prisma/prisma.service";
import { EcfDgiiActivationService } from "../dgii/ecf-dgii-activation.service";
import { EcfDgiiDocumentsService } from "../dgii/ecf-dgii-documents.service";
import { EcfDgiiHabilitationService } from "../dgii/ecf-dgii-habilitation.service";
import {
  ReviewEcfDgiiEvidenceDto,
  UpdateEcfDgiiRequirementDto,
} from "../dto/ecf-dgii.dto";
import {
  AuthorizeEcfCertificationDto,
  DecideEcfDgiiApplicationDto,
  CloseDosaIncidentDto,
  GrantEcfPortalEnrollmentDto,
  RevokeEcfCertificationDto,
  RevokeEcfPortalEnrollmentDto,
} from "../dto/ecf-platform.dto";
import { PlatformStaffGuard } from "./platform-staff.guard";
import { DosaIncidentService } from "../provider/dosa/dosa-incident.service";
import { EcfPortalEnrollmentService } from "../portal/ecf-portal-enrollment.service";
import { EcfCertificationAuthorizationService } from "../certification/ecf-certification-authorization.service";
import { EcfSupportGrantGuard } from "../dgii/ecf-support-grant.guard";
import { EcfSupportGrantService } from "../dgii/ecf-support-grant.service";

const STATES = new Set<string>(Object.values(EcfDgiiHabilitationState));

/**
 * Rutas de PLATAFORMA (personal de Fulltech).
 *
 * Deliberadamente **fuera** de `EcfController`: ese controlador deriva la
 * empresa del contexto autenticado y nunca acepta un `companyId`. Aquí se
 * consulta y se decide a través de empresas, así que la autorización es
 * distinta: no usa `RolesGuard` (que concede todo a cualquier ADMIN de empresa)
 * sino `PlatformStaffGuard`.
 *
 * La decisión de revisión NO tiene un camino propio: delega en
 * `EcfDgiiHabilitationService.updateHabilitationForCompany`, de modo que se
 * aplican las mismas transiciones, el mismo motivo obligatorio y la misma
 * auditoría que cuando actúa la propia empresa. Este controlador no puede
 * aprobar nada: `APPROVED` sigue exigiendo registro oficial verificado.
 */
@UseGuards(AuthGuard("jwt"), PlatformStaffGuard, EcfSupportGrantGuard)
@Controller("ecf/platform")
export class EcfPlatformController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly habilitation: EcfDgiiHabilitationService,
    private readonly documents: EcfDgiiDocumentsService,
    private readonly activation: EcfDgiiActivationService,
    private readonly grants: EcfSupportGrantService,
    private readonly dosaIncidents: DosaIncidentService,
    private readonly portalEnrollments: EcfPortalEnrollmentService,
    private readonly certification: EcfCertificationAuthorizationService,
  ) {}

  /**
   * Identidad de plataforma.
   *
   * Solo responde si `PlatformStaffGuard` dejó pasar la petición, así que un
   * `200` es prueba de pertenencia y un `403 PLATFORM_STAFF_REQUIRED` es prueba
   * de lo contrario. El cliente no adivina su rol: lo pregunta.
   */
  @Get("me")
  me() {
    return { isPlatformStaff: true };
  }

  /**
   * Bandeja multiempresa de expedientes DGII.
   *
   * Devuelve solo metadatos de seguimiento. No incluye documentos ni evidencias:
   * el contenido documental se sirve por su ruta autenticada y acotada.
   */
  @Get("dgii/applications")
  async listApplications(
    @Query("state") state?: string,
    @Query("take") take?: string,
    @Query("skip") skip?: string,
  ) {
    const takeN = Math.min(Math.max(Number(take) || 50, 1), 200);
    const skipN = Math.max(Number(skip) || 0, 0);

    const requestedState = (state ?? "").trim();
    // La bandeja solo muestra empresas que AUTORIZARON asistencia. Sin filtro,
    // el nombre y el estado del expediente de un cliente sin concesión se
    // filtraban por el simple hecho de pertenecer al staff.
    const grantedCompanyIds = await this.grants.activeCompanyIds();
    const where: Prisma.EcfDgiiHabilitationWhereInput = {
      companyId: { in: grantedCompanyIds },
      ...(requestedState.length > 0 && STATES.has(requestedState)
        ? { state: requestedState as EcfDgiiHabilitationState }
        : {}),
    };

    const [rows, total] = await this.prisma.$transaction([
      this.prisma.ecfDgiiHabilitation.findMany({
        where,
        orderBy: { updatedAt: "desc" },
        take: takeN,
        skip: skipN,
        select: {
          companyId: true,
          state: true,
          reviewState: true,
          observations: true,
          startedAt: true,
          authorizedAt: true,
          authorizationSource: true,
          updatedAt: true,
          company: { select: { name: true } },
        },
      }),
      this.prisma.ecfDgiiHabilitation.count({ where }),
    ]);

    return {
      total,
      take: takeN,
      skip: skipN,
      items: rows.map((row) => ({
        companyId: row.companyId,
        companyName: row.company?.name ?? null,
        state: row.state,
        reviewState: row.reviewState,
        observations: row.observations,
        startedAt: row.startedAt,
        authorizedAt: row.authorizedAt,
        authorizationSource: row.authorizationSource,
        updatedAt: row.updatedAt,
        // La habilitación oficial se decide por el registro, no por el estado.
        hasOfficialAuthorization:
          row.authorizationSource === "DGII_OFFICIAL_RECORD" &&
          row.authorizedAt !== null,
      })),
    };
  }

  /**
   * Detalle de UN expediente para revisión.
   *
   * Solo metadatos: la evidencia se lista sin su referencia de almacenamiento
   * (que es una ubicación interna) y el contenido se descarga por la ruta
   * autenticada del expediente, nunca desde aqui.
   */
  @Get("dgii/applications/:companyId")
  async getApplication(@Param("companyId", new ParseUUIDPipe()) companyId: string) {
    const record = await this.prisma.ecfDgiiHabilitation.findUnique({
      where: { companyId },
      select: {
        companyId: true,
        state: true,
        reviewState: true,
        observations: true,
        responsibleUserId: true,
        startedAt: true,
        authorizedAt: true,
        authorizationSource: true,
        externalId: true,
        authorizationEvidenceId: true,
        updatedAt: true,
        company: { select: { name: true } },
      },
    });
    if (!record) {
      throw new NotFoundException("ECF_DGII_APPLICATION_NOT_FOUND");
    }

    const [evidence, company] = await Promise.all([
      this.prisma.ecfEvidence.findMany({
        where: { companyId },
        orderBy: { createdAt: "desc" },
        take: 100,
        select: {
          id: true,
          kind: true,
          source: true,
          reviewStatus: true,
          fileName: true,
          mimeType: true,
          sha256: true,
          description: true,
          createdAt: true,
          reviewedAt: true,
          reviewNote: true,
        },
      }),
      this.prisma.appConfig.findFirst({
        where: { companyId },
        select: { rnc: true },
      }),
    ]);

    return {
      companyId: record.companyId,
      companyName: record.company?.name ?? null,
      rnc: company?.rnc ?? null,
      state: record.state,
      reviewState: record.reviewState,
      observations: record.observations,
      responsibleUserId: record.responsibleUserId,
      startedAt: record.startedAt,
      authorizedAt: record.authorizedAt,
      authorizationSource: record.authorizationSource,
      externalId: record.externalId,
      authorizationEvidenceId: record.authorizationEvidenceId,
      updatedAt: record.updatedAt,
      hasOfficialAuthorization:
        record.authorizationSource === "DGII_OFFICIAL_RECORD" &&
        record.authorizedAt !== null,
      evidence,
    };
  }

  /**
   * Decisión del personal de plataforma sobre un expediente.
   *
   * Es la MISMA operación que hace la empresa sobre su propio expediente: la
   * empresa se pasa como parámetro, no se deriva del contexto, y el servicio
   * aplica su política. Por eso un `APPROVED` sin registro oficial sigue siendo
   * rechazado. El actor queda en la auditoría con su identificador real.
   */
  @Patch("dgii/applications/:companyId")
  async decideApplication(
    @Req() req: Request,
    @Param("companyId", new ParseUUIDPipe()) companyId: string,
    @Body() dto: DecideEcfDgiiApplicationDto,
  ) {
    return this.habilitation.updateHabilitationForCompany({
      companyId,
      actorUserId: (req.user as TenantUser).id,
      dto,
    });
  }

  /**
   * Requisitos del expediente con su seguimiento.
   *
   * El catálogo es cerrado; un requisito sin seguimiento llega con `tracking:
   * null`, nunca con un estado inventado.
   */
  @Get("dgii/applications/:companyId/requirements")
  async listRequirements(
    @Param("companyId", new ParseUUIDPipe()) companyId: string,
  ) {
    const items = await this.habilitation.requirementsForCompany(companyId);
    return { companyId, items };
  }

  /**
   * Estado del MOTOR DE ACTIVACIÓN de una empresa. Solo lectura.
   *
   * El personal de plataforma ve lo mismo que el cliente: qué pasos están
   * resueltos y cuáles dependen del cliente, del proveedor o de la DGII. No hay
   * ruta de escritura: el motor lo gobierna la empresa dueña del expediente y
   * la plataforma no puede adelantar ni completar pasos desde aquí.
   */
  @Get("dgii/applications/:companyId/activation")
  async getActivation(
    @Param("companyId", new ParseUUIDPipe()) companyId: string,
  ) {
    return this.activation.getActivationForCompany(companyId);
  }

  /**
   * Alcance con el que el personal está accediendo a este expediente.
   *
   * Lo concede la empresa y caduca: mostrarlo evita que un revisor crea que
   * tiene un permiso permanente. Si no hubiera concesión vigente, el
   * `EcfSupportGrantGuard` habría respondido 403 antes de llegar aquí.
   */
  @Get("dgii/applications/:companyId/access")
  async getAccess(
    @Param("companyId", new ParseUUIDPipe()) companyId: string,
  ) {
    const grant = await this.grants.activeGrantForCompany(companyId);
    return { companyId, grant };
  }

  /**
   * Bandeja de incidencias del flujo DOSA.
   *
   * Mismo criterio que la bandeja DGII: solo empresas que autorizaron
   * asistencia. Sin ese filtro, el estado operativo de un cliente sin concesión
   * se filtraría por el simple hecho de pertenecer al staff.
   *
   * No expone credenciales: la incidencia guarda referencias (empresa, RNC,
   * postulación) y estados, nunca claves ni el cuerpo del evento.
   */
  @Get("dosa/incidents")
  async listDosaIncidents(
    @Query("status") status?: string,
    @Query("take") take?: string,
    @Query("skip") skip?: string,
  ) {
    const grantedCompanyIds = await this.grants.activeCompanyIds();
    return this.dosaIncidents.list({
      companyIds: grantedCompanyIds,
      status: status ?? null,
      take: Number(take) || undefined,
      skip: Number(skip) || undefined,
    });
  }

  /** Incidencias de UNA empresa. El guard ya validó la concesión. */
  @Get("dosa/incidents/:companyId")
  async listCompanyDosaIncidents(
    @Param("companyId", new ParseUUIDPipe()) companyId: string,
    @Query("status") status?: string,
  ) {
    return this.dosaIncidents.list({ companyIds: [companyId], status: status ?? null });
  }

  /**
   * Ejecuta un barrido AHORA.
   *
   * Es la misma rutina que corre el planificador; existe para que un
   * administrador pueda refrescar sin esperar el ciclo. No reenvía nada a DOSA
   * ni relaja ninguna verificación.
   */
  @Post("dosa/incidents/sweep")
  async sweepDosaIncidents() {
    return this.dosaIncidents.scan();
  }

  /**
   * Estado del acceso al asistente e-CF para una empresa concreta.
   *
   * Devuelve la decisión vigente y el histórico de autorizaciones. Es de solo
   * lectura: no inscribe a nadie.
   */
  @Get("dosa/portal-enrollments/:companyId")
  async getPortalEnrollment(
    @Param("companyId", new ParseUUIDPipe()) companyId: string,
  ) {
    const [eligibility, history] = await Promise.all([
      this.portalEnrollments.eligibility(companyId),
      this.portalEnrollments.history(companyId),
    ]);
    return { eligibility, history };
  }

  /**
   * Autoriza el asistente e-CF para una empresa.
   *
   * Sustituye a la lista de entorno: la autorización queda en base de datos,
   * es idempotente (no duplica una vigente) y registra quién la dio y por qué.
   * NO emite comprobantes, no habilita la transmisión y no toca credenciales.
   */
  @Post("dosa/portal-enrollments/:companyId/grant")
  async grantPortalEnrollment(
    @Req() req: Request,
    @Param("companyId", new ParseUUIDPipe()) companyId: string,
    @Body() dto: GrantEcfPortalEnrollmentDto,
  ) {
    const result = await this.portalEnrollments.grant({
      companyId,
      source: dto.source,
      reason: dto.reason,
      contractReference: dto.contractReference ?? null,
      expiresAt: dto.expiresAt ? new Date(dto.expiresAt) : null,
      actorUserId: (req.user as TenantUser).id,
    });
    if (!result.ok) {
      throw new BadRequestException(result.blockedReason);
    }
    return {
      companyId,
      created: result.created,
      enrollmentId: result.id,
    };
  }

  /**
   * Revoca la autorización vigente de una empresa.
   *
   * Conserva la fila (nunca borra) para que el histórico siga siendo auditable.
   */
  @Post("dosa/portal-enrollments/:companyId/revoke")
  async revokePortalEnrollment(
    @Req() req: Request,
    @Param("companyId", new ParseUUIDPipe()) companyId: string,
    @Body() dto: RevokeEcfPortalEnrollmentDto,
  ) {
    const result = await this.portalEnrollments.revoke({
      companyId,
      reason: dto.reason,
      actorUserId: (req.user as TenantUser).id,
    });
    if (!result.ok) {
      throw new BadRequestException(result.blockedReason);
    }
    return { companyId, revoked: result.revoked };
  }

  /**
   * Cierra una incidencia con un motivo del catálogo.
   *
   * Cerrar NO activa credenciales, no rota material y no cambia el estado de
   * certificación: solo deja constancia de que una persona revisó el caso.
   */
  @Post("dosa/incidents/:companyId/:incidentId/close")
  async closeDosaIncident(
    @Req() req: Request,
    @Param("companyId", new ParseUUIDPipe()) companyId: string,
    @Param("incidentId", new ParseUUIDPipe()) incidentId: string,
    @Body() dto: CloseDosaIncidentDto,
  ) {
    const result = await this.dosaIncidents.close({
      incidentId,
      companyId,
      resolution: dto.resolution,
      actorUserId: (req.user as TenantUser).id,
    });
    if (!result.ok) {
      throw new ConflictException(result.blockedReason);
    }
    return { ok: true };
  }

  /**
   * Registra la revisión de UN requisito.
   *
   * Se guarda como seguimiento interno con su autor y su fecha, y la auditoría es
   * la misma que genera la empresa (`DGII_HABILITATION_UPDATED`). No mueve el
   * estado del expediente: revisar un requisito no aprueba nada.
   */
  @Patch("dgii/applications/:companyId/requirements/:key")
  async reviewRequirement(
    @Req() req: Request,
    @Param("companyId", new ParseUUIDPipe()) companyId: string,
    @Param("key") key: string,
    @Body() dto: UpdateEcfDgiiRequirementDto,
  ) {
    return this.habilitation.updateRequirementForCompany({
      companyId,
      actorUserId: (req.user as TenantUser).id,
      key,
      dto,
    });
  }

  /**
   * Revisa INTERNAMENTE una evidencia del expediente.
   *
   * Mismas reglas que en la empresa: el rechazo exige motivo y la revisión no
   * convierte la evidencia en registro oficial. Es un acto auditado.
   */
  @Patch("dgii/applications/:companyId/evidence/:evidenceId")
  async reviewEvidence(
    @Req() req: Request,
    @Param("companyId", new ParseUUIDPipe()) companyId: string,
    @Param("evidenceId", new ParseUUIDPipe()) evidenceId: string,
    @Body() dto: ReviewEcfDgiiEvidenceDto,
  ) {
    return this.habilitation.reviewEvidenceForCompany({
      companyId,
      actorUserId: (req.user as TenantUser).id,
      evidenceId,
      dto,
    });
  }

  /**
   * Descarga autorizada de un documento del expediente.
   *
   * La evidencia debe pertenecer a esa empresa; un identificador ajeno responde
   * igual que uno inexistente. `storageRef` no sale del servidor y la respuesta
   * no es cacheable.
   */
  @Get("dgii/applications/:companyId/documents/:evidenceId/file")
  async downloadDocument(
    @Param("companyId", new ParseUUIDPipe()) companyId: string,
    @Param("evidenceId", new ParseUUIDPipe()) evidenceId: string,
    @Res({ passthrough: true }) res: Response,
  ) {
    const doc = await this.documents.downloadForCompany(companyId, evidenceId);
    res.setHeader("Content-Type", doc.mimeType);
    res.setHeader(
      "Content-Disposition",
      `attachment; filename*=UTF-8''${encodeURIComponent(doc.fileName)}`,
    );
    res.setHeader("X-Content-SHA256", doc.sha256 ?? "");
    res.setHeader("Cache-Control", "no-store");
    return doc.buffer;
  }

  /**
   * Situación de AUTORIZACIÓN DE EMISIÓN de una empresa. Solo lectura.
   *
   * Devuelve el estado de certificación vigente, los objetivos que la política
   * permite ahora y el histórico de autorizaciones. No cambia nada.
   */
  @Get("dosa/certification/:companyId")
  async getCertificationAuthorization(
    @Param("companyId", new ParseUUIDPipe()) companyId: string,
  ) {
    const snapshot = await this.certification.snapshot(companyId);
    if (!snapshot) {
      throw new NotFoundException("ECF_CERTIFICATION_CONFIGURATION_NOT_FOUND");
    }
    return snapshot;
  }

  /**
   * Autoriza la emisión electrónica de una empresa.
   *
   * Sustituye al `UPDATE` manual en la base: la transición se valida contra la
   * política (`AUTHORIZED_SANDBOX` antes de `PRODUCTION_READY`, nunca desde
   * `BLOCKED`), el motivo es obligatorio y la fila de auditoría guarda estado
   * anterior, estado nuevo, actor y referencia de evidencia.
   *
   * NO emite: la emisión sigue exigiendo configuración habilitada, proveedor
   * DOSA, credenciales activas y la bandera global. Esta ruta solo levanta la
   * compuerta de certificación.
   */
  @Post("dosa/certification/:companyId/authorize")
  async authorizeEcfCertification(
    @Req() req: Request,
    @Param("companyId", new ParseUUIDPipe()) companyId: string,
    @Body() dto: AuthorizeEcfCertificationDto,
  ) {
    const result = await this.certification.authorize({
      companyId,
      target: dto.target,
      reason: dto.reason,
      evidenceReference: dto.evidenceReference ?? null,
      actorUserId: (req.user as TenantUser).id,
    });
    if (!result.ok) {
      // Un rechazo de política es un conflicto con el estado actual, no una
      // petición mal formada: el operador tiene que resolver algo antes.
      throw result.blockedReason === "ECF_CERTIFICATION_CONFIGURATION_NOT_FOUND"
        ? new NotFoundException(result.blockedReason)
        : new ConflictException(result.blockedReason);
    }
    return {
      companyId: result.companyId,
      changed: result.changed,
      from: result.from,
      to: result.to,
    };
  }

  /**
   * Revoca la autorización de emisión de una empresa.
   *
   * Deja el estado en `SUSPENDED`, que la derivación automática no puede
   * levantar: reactivar exige una nueva autorización explícita por esta vía.
   */
  @Post("dosa/certification/:companyId/revoke")
  async revokeEcfCertification(
    @Req() req: Request,
    @Param("companyId", new ParseUUIDPipe()) companyId: string,
    @Body() dto: RevokeEcfCertificationDto,
  ) {
    const result = await this.certification.revoke({
      companyId,
      reason: dto.reason,
      actorUserId: (req.user as TenantUser).id,
    });
    if (!result.ok) {
      throw result.blockedReason === "ECF_CERTIFICATION_CONFIGURATION_NOT_FOUND"
        ? new NotFoundException(result.blockedReason)
        : new ConflictException(result.blockedReason);
    }
    return {
      companyId: result.companyId,
      changed: result.changed,
      from: result.from,
      to: result.to,
    };
  }
}
