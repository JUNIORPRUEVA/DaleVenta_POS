import {
  Body,
  Controller,
  Delete,
  Get,
  Headers,
  HttpCode,
  Post,
  Req,
  UseGuards,
} from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import { IsOptional, IsString, MaxLength, MinLength } from "class-validator";
import type { Request } from "express";

import { Permissions } from "../../auth/roles.decorator";
import { RolesGuard } from "../../auth/roles.guard";
import { requireTenant, type TenantUser } from "../../auth/tenant-context";
import { EcfCertificationPortalService } from "./ecf-certification-portal.service";

/** Cabecera de la sesion del portal. Nunca viaja en la URL. */
export const PORTAL_TOKEN_HEADER = "x-fullpos-portal";

export class CreatePortalTicketDto {
  @IsOptional()
  @IsString()
  @MaxLength(64)
  companyId?: string;
}

export class ExchangePortalTicketDto {
  @IsString()
  @MinLength(20)
  @MaxLength(128)
  ticket!: string;

  /** Solo para detectar discrepancias: el ticket decide la empresa. */
  @IsOptional()
  @IsString()
  @MaxLength(64)
  companyId?: string;
}

/**
 * Portal de certificacion automatica DOSA.
 *
 * - `POST /tickets` exige un administrador autenticado de la empresa; la empresa
 *   sale del token, jamas del cuerpo.
 * - `POST /sessions` es publico a proposito (el navegador aun no tiene sesion),
 *   pero solo acepta un ticket de un solo uso, caducado y ligado a una empresa.
 * - `GET /context` y `DELETE /sessions` exigen la cabecera del portal.
 *
 * Este controlador no envia nada al proveedor ni a la DGII y no activa e-CF.
 */
@Controller("ecf/certification-portal")
export class EcfCertificationPortalController {
  constructor(private readonly portal: EcfCertificationPortalService) {}

  @Post("tickets")
  @HttpCode(201)
  @UseGuards(AuthGuard("jwt"), RolesGuard)
  @Permissions("manageEcfOnboarding")
  async createTicket(@Req() req: Request): Promise<{
    ok: true;
    ticket: string;
    expiresAt: string;
    ticketTtlSeconds: number;
  }> {
    const user = req.user as TenantUser;
    // La empresa SIEMPRE viene del token.
    const companyId = requireTenant(user);
    const issued = await this.portal.issueTicket({
      companyId,
      userId: user.id,
    });
    return {
      ok: true,
      ticket: issued.ticket,
      expiresAt: issued.expiresAt,
      ticketTtlSeconds: 120,
    };
  }

  @Post("sessions")
  @HttpCode(201)
  async exchange(@Body() body: ExchangePortalTicketDto) {
    const result = await this.portal.exchangeTicket({
      ticket: body?.ticket ?? "",
      companyIdFromClient: body?.companyId ?? null,
    });
    return { ok: true, ...result };
  }

  @Get("context")
  async context(@Headers(PORTAL_TOKEN_HEADER) token?: string) {
    return { ok: true, context: await this.portal.readContext(token) };
  }

  /**
   * Elegibilidad para PREPARAR la certificacion, independiente de la emision.
   *
   * Una empresa con e-CF desactivado puede preparar su certificacion; este
   * endpoint es de solo lectura y no emite ticket ni sesion. Sin permiso
   * administrativo responde 403 (cerrado por defecto).
   */
  @Get("eligibility")
  @UseGuards(AuthGuard("jwt"), RolesGuard)
  @Permissions("manageEcfOnboarding")
  eligibility(@Req() req: Request) {
    const user = req.user as TenantUser;
    const companyId = requireTenant(user);
    return { ok: true, ...this.portal.eligibility(companyId) };
  }

  @Delete("sessions")
  @HttpCode(200)
  async logout(@Headers(PORTAL_TOKEN_HEADER) token?: string) {
    return { ok: true, ...(await this.portal.revoke(token)) };
  }
}
