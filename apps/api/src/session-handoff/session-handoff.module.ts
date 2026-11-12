import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { SessionHandoffController } from "./session-handoff.controller";

/**
 * Modulo aislado del handoff de sesion. Reutiliza `AuthService` (exportado por
 * `AuthModule`) para no duplicar la firma de tokens, la rotacion de sesiones ni
 * las validaciones de licencia.
 */
@Module({
  imports: [AuthModule],
  controllers: [SessionHandoffController],
})
export class SessionHandoffModule {}
