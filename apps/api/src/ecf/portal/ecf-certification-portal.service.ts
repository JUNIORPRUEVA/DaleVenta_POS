import { createHash, randomBytes } from "node:crypto";

import {
  ConflictException,
  ForbiddenException,
  GoneException,
  Injectable,
  NotFoundException,
  UnauthorizedException,
} from "@nestjs/common";

import { PrismaService } from "../../prisma/prisma.service";
import {
  PORTAL_PILOT_COMPANIES_ENV,
  isEcfPortalPilotCompany,
  parsePilotCompanyIds,
} from "./ecf-portal-pilot.policy";

/** Vida del ticket de un solo uso que la app canjea al abrir el portal. */
export const PORTAL_TICKET_TTL_SECONDS = 120;

/** Vida de la sesion del portal una vez canjeado el ticket. */
export const PORTAL_SESSION_TTL_SECONDS = 30 * 60;

// La regla del piloto vive en `ecf-portal-pilot.policy` para que la
// configuracion de empresa use exactamente la misma. Se reexporta aqui porque
// este modulo es el punto de entrada historico de esas constantes.
export { PORTAL_PILOT_COMPANIES_ENV, parsePilotCompanyIds };

/** Estado de cada hito del recorrido, tal como lo pinta el portal. */
export type PortalMilestoneState = "pending" | "in_progress" | "done" | "locked";

export interface PortalContext {
  company: { id: string; commercialName: string | null; taxId: string | null };
  postulation: {
    attemptNo: number;
    status: string;
    providerPostulationId: string | null;
    startedAt: string | null;
  } | null;
  milestones: {
    application: PortalMilestoneState;
    tests: PortalMilestoneState;
    certification: PortalMilestoneState;
  };
  /** `true` solo si la empresa ya tiene e-CF habilitado; nunca se activa aqui. */
  ecfEnabled: boolean;
  sessionExpiresAt: string;
}

export interface PortalSessionResult {
  token: string;
  expiresAt: string;
  context: PortalContext;
}

/**
 * Portal de certificacion automatica.
 *
 * Reglas que este servicio garantiza y que las pruebas comprueban:
 *  - La empresa y el usuario salen SIEMPRE del ticket o de la sesion guardada,
 *    nunca de un dato del navegador.
 *  - El ticket es de un solo uso y vence: reutilizarlo es un conflicto.
 *  - Ni el ticket ni la sesion se guardan en claro (solo su SHA-256).
 *  - Este servicio NO escribe en el proveedor ni en la DGII, y NUNCA activa
 *    e-CF: leer el contexto es una operacion de solo lectura.
 */
@Injectable()
export class EcfCertificationPortalService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * `true` solo para las empresas autorizadas del piloto.
   *
   * Se lee en cada llamada (no en el constructor) para que retirar una empresa
   * del piloto surta efecto sin reiniciar, y para que Nest no tenga que
   * resolver un segundo parametro de constructor.
   */
  isPilotCompany(companyId: string): boolean {
    return isEcfPortalPilotCompany(companyId);
  }

  /**
   * Elegibilidad de SOLO LECTURA: separa "preparar" de "emitir".
   *
   * No crea tickets, ni sesiones, ni escribe nada. Sirve para que la app decida
   * si muestra la entrada del portal. Cerrada por defecto: si el piloto no esta
   * configurado, `eligible` es `false` y el motivo lo explica.
   */
  eligibility(companyId: string): {
    eligible: boolean;
    companyId: string;
    reason: "ELIGIBLE" | "PILOT_NOT_INCLUDED";
    portalPath: string;
  } {
    const eligible = this.isPilotCompany(companyId);
    return {
      eligible,
      companyId,
      reason: eligible ? "ELIGIBLE" : "PILOT_NOT_INCLUDED",
      portalPath: "/ecf/certificacion",
    };
  }

  /** Emite un ticket de un solo uso para el administrador autenticado. */
  async issueTicket(input: {
    companyId: string;
    userId: string;
  }): Promise<{ ticket: string; expiresAt: string }> {
    // Compuerta del piloto: una empresa fuera de la lista no obtiene capacidad.
    if (!this.isPilotCompany(input.companyId)) {
      throw new ForbiddenException("PORTAL_PILOT_NOT_INCLUDED");
    }
    await this.requireDosaIntention(input.companyId);

    const ticket = newToken();
    const expiresAt = new Date(Date.now() + PORTAL_TICKET_TTL_SECONDS * 1000);

    // Un ticket nuevo invalida los anteriores sin consumir de la empresa: no
    // interesa acumular capacidades vivas.
    await this.prisma.$transaction([
      this.prisma.ecfCertificationPortalTicket.updateMany({
        where: { companyId: input.companyId, usedAt: null },
        data: { usedAt: new Date() },
      }),
      this.prisma.ecfCertificationPortalTicket.create({
        data: {
          companyId: input.companyId,
          userId: input.userId,
          tokenHash: hashToken(ticket),
          expiresAt,
        },
      }),
    ]);

    return { ticket, expiresAt: expiresAt.toISOString() };
  }

  /** Canjea el ticket por una sesion de portal. El ticket se consume aqui. */
  async exchangeTicket(input: {
    ticket: string;
    companyIdFromClient?: string | null;
  }): Promise<PortalSessionResult> {
    const raw = (input.ticket ?? "").trim();
    if (raw.length < 20) throw new UnauthorizedException("PORTAL_TICKET_INVALID");

    const row = await this.prisma.ecfCertificationPortalTicket.findUnique({
      where: { tokenHash: hashToken(raw) },
    });
    if (!row) throw new UnauthorizedException("PORTAL_TICKET_INVALID");
    if (row.usedAt) throw new ConflictException("PORTAL_TICKET_ALREADY_USED");
    if (row.expiresAt.getTime() <= Date.now()) {
      throw new GoneException("PORTAL_TICKET_EXPIRED");
    }

    // Defensa en profundidad: aunque el ticket exista, si la empresa no esta
    // autorizada (p. ej. se retiro del piloto) no se abre sesion.
    if (!this.isPilotCompany(row.companyId)) {
      throw new ForbiddenException("PORTAL_PILOT_NOT_INCLUDED");
    }
    await this.requireDosaIntention(row.companyId);

    // Si el navegador dice pertenecer a otra empresa, no se canjea nada: el
    // ticket manda y la discrepancia se reporta.
    const claimed = (input.companyIdFromClient ?? "").trim();
    if (claimed.length > 0 && claimed !== row.companyId) {
      throw new ForbiddenException("PORTAL_TICKET_COMPANY_MISMATCH");
    }

    // Consumo atomico: solo una peticion puede marcar `used_at`.
    const consumed = await this.prisma.ecfCertificationPortalTicket.updateMany({
      where: { id: row.id, usedAt: null },
      data: { usedAt: new Date() },
    });
    if (consumed.count !== 1) {
      throw new ConflictException("PORTAL_TICKET_ALREADY_USED");
    }

    const token = newToken();
    const expiresAt = new Date(
      Date.now() + PORTAL_SESSION_TTL_SECONDS * 1000,
    );
    const session = await this.prisma.ecfCertificationPortalSession.create({
      data: {
        companyId: row.companyId,
        userId: row.userId,
        ticketId: row.id,
        tokenHash: hashToken(token),
        expiresAt,
      },
    });

    return {
      token,
      expiresAt: expiresAt.toISOString(),
      context: await this.buildContext(session.id),
    };
  }

  /** Contexto de la sesion. Solo lectura: no escribe nada en el proveedor. */
  async readContext(token: string | null | undefined): Promise<PortalContext> {
    const session = await this.requireSession(token);
    await this.requireDosaIntention(session.companyId);
    await this.prisma.ecfCertificationPortalSession.update({
      where: { id: session.id },
      data: { lastSeenAt: new Date() },
    });
    return this.buildContext(session.id, session.companyId);
  }

  /** Revoca la sesion actual (salir del portal). */
  async revoke(token: string | null | undefined): Promise<{ revoked: boolean }> {
    const raw = (token ?? "").trim();
    if (raw.length < 20) return { revoked: false };
    const result = await this.prisma.ecfCertificationPortalSession.updateMany({
      where: { tokenHash: hashToken(raw), revokedAt: null },
      data: { revokedAt: new Date() },
    });
    return { revoked: result.count === 1 };
  }

  /** Resuelve la sesion guardada; cualquier fallo es un 401, sin detalles. */
  private async requireSession(token: string | null | undefined) {
    const raw = (token ?? "").trim();
    if (raw.length < 20) throw new UnauthorizedException("PORTAL_SESSION_INVALID");

    const session = await this.prisma.ecfCertificationPortalSession.findUnique({
      where: { tokenHash: hashToken(raw) },
    });
    if (!session || session.revokedAt) {
      throw new UnauthorizedException("PORTAL_SESSION_INVALID");
    }
    if (session.expiresAt.getTime() <= Date.now()) {
      throw new UnauthorizedException("PORTAL_SESSION_EXPIRED");
    }
    // Si la empresa sale del piloto, las sesiones vivas dejan de servir.
    if (!this.isPilotCompany(session.companyId)) {
      throw new ForbiddenException("PORTAL_PILOT_NOT_INCLUDED");
    }
    return session;
  }

  /** Un ticket no puede reutilizar un intento histórico de otro proveedor. */
  private async requireDosaIntention(companyId: string): Promise<void> {
    const intention = await this.prisma.ecfDosaCertificationSession.findFirst({
      where: { companyId },
      orderBy: { createdAt: "desc" },
      select: { id: true },
    });
    if (!intention) throw new ConflictException("PORTAL_INTENTION_REQUIRED");
    const audits = await this.prisma.ecfAuditLog.findMany({
      where: { companyId, targetType: "DOSA_CERTIFICATION_INTENT", targetId: intention.id },
      select: { metadata: true },
    });
    const providers = audits.map((entry) => {
      const metadata = entry.metadata;
      return metadata && typeof metadata === "object" && !Array.isArray(metadata)
        ? (metadata as Record<string, unknown>).provider
        : null;
    });
    if (providers.length === 0 || providers.some((provider) => provider !== "DOSA")) {
      throw new ConflictException("PORTAL_INTENTION_PROVIDER_UNVERIFIED");
    }
  }

  private async buildContext(
    sessionId: string,
    _companyIdHint?: string,
  ): Promise<PortalContext> {
    const session = await this.prisma.ecfCertificationPortalSession.findUnique({
      where: { id: sessionId },
    });
    if (!session) throw new UnauthorizedException("PORTAL_SESSION_INVALID");

    const company = await this.prisma.company.findUnique({
      where: { id: session.companyId },
      select: { id: true, name: true },
    });
    if (!company) throw new UnauthorizedException("PORTAL_SESSION_INVALID");

    const [postulation, ecfConfig] = await Promise.all([
      this.prisma.ecfDosaCertificationSession.findFirst({
        where: { companyId: company.id },
        orderBy: { createdAt: "desc" },
        select: {
          rnc: true,
          attemptNo: true,
          status: true,
          providerPostulationId: true,
          createdAt: true,
        },
      }),
      this.prisma.ecfCompanyConfiguration.findUnique({
        where: { companyId: company.id },
        select: { enabled: true },
      }),
    ]);

    return {
      company: {
        id: company.id,
        commercialName: company.name ?? null,
        // El RNC sale del expediente de la empresa, nunca del navegador.
        taxId: postulation?.rnc ?? null,
      },
      postulation: postulation
        ? {
            attemptNo: postulation.attemptNo,
            status: postulation.status,
            providerPostulationId: postulation.providerPostulationId ?? null,
            startedAt: postulation.createdAt.toISOString(),
          }
        : null,
      milestones: milestonesFor(postulation?.status ?? null),
      ecfEnabled: ecfConfig?.enabled === true,
      sessionExpiresAt: session.expiresAt.toISOString(),
    };
  }
}

/**
 * Traduce el estado de la sesion del proveedor al recorrido visible.
 *
 * `COMPLETED` cierra la SOLICITUD; no significa certificacion DGII aprobada ni
 * habilita e-CF, y por eso los hitos siguientes quedan en `pending`.
 */
export function milestonesFor(status: string | null): PortalContext["milestones"] {
  switch (status) {
    case "COMPLETED":
      return {
        application: "done",
        tests: "pending",
        certification: "pending",
      };
    case "RUNNING":
    case "ATTENTION":
    case "NOT_STARTED":
      return {
        application: "in_progress",
        tests: "locked",
        certification: "locked",
      };
    case "FAILED":
    case "CANCELLED":
    case "EXPIRED":
      return {
        application: "pending",
        tests: "locked",
        certification: "locked",
      };
    default:
      return {
        application: "pending",
        tests: "locked",
        certification: "locked",
      };
  }
}

function newToken(): string {
  return randomBytes(32).toString("base64url");
}

/** Solo el hash se persiste: una copia de la tabla no permite abrir nada. */
export function hashToken(value: string): string {
  return createHash("sha256").update(value, "utf8").digest("hex");
}
