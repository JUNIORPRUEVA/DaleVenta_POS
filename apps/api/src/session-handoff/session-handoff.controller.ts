import { Body, Controller, HttpCode, Post, Req, UseGuards } from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import { Request } from "express";
import { AuthService } from "../auth/auth.service";

/**
 * Handoff de sesion del sitio publico (Astro) hacia la app Flutter Web.
 *
 * - `POST /auth/handoff/ticket`   (autenticado) emite un ticket de un solo uso.
 * - `POST /auth/handoff/exchange` (publico) lo canjea por tokens una sola vez.
 *
 * El ticket es aleatorio de 256 bits, vive 2 minutos y se guarda solo como
 * hash. Nunca viaja un token reutilizable en la URL.
 */
@Controller("auth/handoff")
export class SessionHandoffController {
  constructor(private readonly auth: AuthService) {}

  @UseGuards(AuthGuard("jwt"))
  @Post("ticket")
  issue(@Req() req: Request, @Body() dto: { platform?: unknown }) {
    const user = req.user as { id?: string | null; sessionId?: string | null };
    return this.auth.createSessionHandoffTicket(
      user,
      typeof dto?.platform === "string" ? dto.platform : "",
    );
  }

  @HttpCode(200)
  @Post("exchange")
  exchange(@Body() dto: { ticket?: unknown }) {
    return this.auth.exchangeSessionHandoffTicket(
      typeof dto?.ticket === "string" ? dto.ticket : "",
    );
  }
}
