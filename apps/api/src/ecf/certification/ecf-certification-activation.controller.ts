import { Controller, HttpCode, Post, Req, UseGuards } from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import type { Request } from "express";

import { Permissions } from "../../auth/roles.decorator";
import { RolesGuard } from "../../auth/roles.guard";
import { requireTenant, type TenantUser } from "../../auth/tenant-context";
import { EcfCertificationActivationService } from "./ecf-certification-activation.service";

/**
 * Activación y autorización de emisión para el PROPIO cliente.
 *
 * Es la ruta que permite que el cliente complete todo su trámite sin que nadie
 * de Fulltech intervenga: evalúa la evidencia que él mismo produjo, activa la
 * credencial si está completa y deriva el estado de certificación.
 *
 * Garantías:
 * * La empresa sale del TOKEN (`requireTenant`); no hay `companyId` en el DTO ni
 *   en la ruta, así que no existe forma de activar la de otro.
 * * Exige `manageEcfOnboarding`, el mismo permiso que abrir la sesión DOSA.
 * * No acepta «autorízame»: no hay campo para declarar aprobación. La evidencia
 *   se lee de la base de datos.
 * * No emite comprobantes ni llama a DOSA.
 * * Es idempotente: repetirla no activa dos veces ni duplica auditoría.
 */
@Controller("ecf/dosa")
@UseGuards(AuthGuard("jwt"), RolesGuard)
export class EcfCertificationActivationController {
  constructor(private readonly activation: EcfCertificationActivationService) {}

  /**
   * Intenta activar y autorizar AHORA.
   *
   * Devuelve `200` incluso cuando falta evidencia: el resultado trae
   * `blockingReasons` por ambiente para que la interfaz le diga al cliente qué
   * le falta exactamente (`ECF_DOSA_ACTIVATION_DGII_NOT_APPROVED`, etc.) en
   * lugar de un error genérico.
   */
  @Post("activation/attempt")
  @HttpCode(200)
  @Permissions("manageEcfOnboarding")
  async attempt(@Req() req: Request) {
    const companyId = requireTenant(req.user as TenantUser);
    return this.activation.attempt(companyId);
  }
}
