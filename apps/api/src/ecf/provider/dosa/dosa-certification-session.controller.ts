import {
  BadGatewayException,
  BadRequestException,
  ConflictException,
  Controller,
  HttpCode,
  Post,
  Req,
  ServiceUnavailableException,
  UseGuards,
} from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import type { Request } from "express";

import { Permissions } from "../../../auth/roles.decorator";
import { RolesGuard } from "../../../auth/roles.guard";
import { requireTenant, type TenantUser } from "../../../auth/tenant-context";
import { DosaCertificationSessionService } from "./dosa-certification-session.service";

export type DosaSessionHttpResponse = {
  ok: true;
  /** Empresa autenticada: confirma que el enlace es de ESA empresa. */
  companyId: string;
  /** Enlace de sesión emitido por DOSA. Solo se devuelve a esta empresa. */
  sessionUrl: string;
  expiresAt: string;
  attemptNo: number;
  providerPostulationId: string;
  /** `true` cuando se reutilizó una sesión vigente (no se llamó al proveedor). */
  reused: boolean;
  /** Nunca autoriza emisión: abrir la sesión no acredita aprobación fiscal. */
  fiscalAuthorizationGranted: false;
};

/**
 * Apertura automática de la sesión de certificación DOSA.
 *
 * Controlador DELGADO: no decide identidad, no valida correo y no habla con el
 * proveedor. Traduce la petición autenticada al servicio.
 *
 * Garantías:
 * * La empresa sale del TOKEN (`requireTenant`); no hay `companyId` en el DTO.
 * * Exige `manageEcfOnboarding`: un usuario sin permisos no abre sesiones.
 * * `inFlight` evita que un doble clic lance dos peticiones simultáneas en este
 *   proceso; el candado de base cubre el resto de instancias.
 * * No expone la clave de servidor ni el token; el enlace solo va a la empresa
 *   autenticada.
 * * Abrir la sesión NO emite comprobantes ni activa el módulo fiscal.
 */
@Controller("ecf/dosa")
@UseGuards(AuthGuard("jwt"), RolesGuard)
export class DosaCertificationSessionController {
  /** Peticiones en vuelo por empresa: corta el doble clic. */
  private readonly inFlight = new Set<string>();

  constructor(private readonly sessions: DosaCertificationSessionService) {}

  @Post("certification-session")
  @HttpCode(200)
  @Permissions("manageEcfOnboarding")
  async open(@Req() req: Request): Promise<DosaSessionHttpResponse> {
    const user = req.user as TenantUser;
    const companyId = requireTenant(user);

    if (this.inFlight.has(companyId)) {
      throw new ConflictException("ECF_DOSA_SESSION_IN_PROGRESS");
    }
    this.inFlight.add(companyId);
    try {
      const result = await this.sessions.open({
        companyId,
        userId: user.id,
      });

      if (result.ok) {
        return {
          ok: true,
          companyId,
          sessionUrl: result.sessionUrl,
          expiresAt: result.expiresAt,
          attemptNo: result.attemptNo,
          providerPostulationId: result.providerPostulationId,
          reused: result.reused,
          fiscalAuthorizationGranted: false,
        };
      }

      // El `message` de la excepción es SIEMPRE el código, para que el cliente
      // muestre un texto propio sin inventar el motivo.
      switch (result.code) {
        case "ECF_DOSA_SESSION_EMAIL_REQUIRED":
        case "ECF_DOSA_SESSION_RNC_REQUIRED":
        case "ECF_DOSA_SESSION_IN_PROGRESS":
          throw new ConflictException(result.code);
        case "ECF_DOSA_SESSION_EMAIL_INVALID":
          throw new BadRequestException(result.code);
        case "ECF_DOSA_SESSION_DISABLED":
        case "ECF_DOSA_SESSION_UNCERTAIN":
        case "ECF_DOSA_SESSION_NOT_PERSISTED":
          // 503: el cliente cae al asistente manual (fallback seguro).
          throw new ServiceUnavailableException(result.code);
        case "ECF_DOSA_SESSION_PROVIDER_ERROR":
        default:
          throw new BadGatewayException(result.code);
      }
    } finally {
      this.inFlight.delete(companyId);
    }
  }
}
