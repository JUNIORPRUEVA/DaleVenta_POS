import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Put,
  Req,
  UseGuards,
} from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import { Request } from "express";
import { type TenantUser } from "../auth/tenant-context";
import { type WelcomeProfileInput } from "./onboarding.constants";
import { OnboardingService } from "./onboarding.service";

@UseGuards(AuthGuard("jwt"))
@Controller("onboarding")
export class OnboardingController {
  constructor(private readonly onboarding: OnboardingService) {}

  @Get()
  getState(@Req() req: Request) {
    return this.onboarding.getState(req.user as TenantUser);
  }

  /** Respuestas guardadas de la pantalla de bienvenida (scoped por tenant). */
  @Get("welcome")
  getWelcome(@Req() req: Request) {
    return this.onboarding.getWelcomeProfile(req.user as TenantUser);
  }

  /** Guarda las respuestas una vez; repetir el envio actualiza la misma fila. */
  @Put("welcome")
  saveWelcome(@Req() req: Request, @Body() dto: WelcomeProfileInput) {
    return this.onboarding.saveWelcomeProfile(req.user as TenantUser, dto);
  }

  @Post("start")
  start(@Req() req: Request) {
    return this.onboarding.start(req.user as TenantUser);
  }

  @Post("skip-all")
  skipAll(@Req() req: Request) {
    return this.onboarding.skipAll(req.user as TenantUser);
  }

  @Patch("steps/:step")
  setStep(
    @Req() req: Request,
    @Param("step") step: string,
    @Body() dto: { status?: unknown; completeFlow?: unknown },
  ) {
    return this.onboarding.setStepStatus(
      req.user as TenantUser,
      step,
      (dto.status ?? "").toString(),
      dto.completeFlow === true,
    );
  }

  @Patch("tutorial")
  setTutorial(@Req() req: Request, @Body() dto: { status?: unknown }) {
    return this.onboarding.setTutorial(
      req.user as TenantUser,
      (dto.status ?? "").toString(),
    );
  }

  // --- Onboarding de activación «Activa tu FullPOS» -------------------------
  //
  // El progreso se deriva de los datos reales de la empresa. Estos endpoints
  // solo guardan overrides: omitir una tarea opcional, reabrir el panel y el
  // avance de un recorrido guiado. Todos van scoped por el tenant del token.

  @Get("activation")
  getActivation(@Req() req: Request) {
    return this.onboarding.getActivation(req.user as TenantUser);
  }

  @Post("activation/welcome-seen")
  markActivationWelcomeSeen(@Req() req: Request) {
    return this.onboarding.markActivationWelcomeSeen(req.user as TenantUser);
  }

  @Post("activation/dismiss")
  dismissActivation(@Req() req: Request) {
    return this.onboarding.dismissActivation(req.user as TenantUser);
  }

  @Post("activation/reopen")
  reopenActivation(@Req() req: Request) {
    return this.onboarding.reopenActivation(req.user as TenantUser);
  }

  @Post("activation/tasks/:key/skip")
  skipActivationTask(@Req() req: Request, @Param("key") key: string) {
    return this.onboarding.skipActivationTask(req.user as TenantUser, key);
  }

  @Delete("activation/tasks/:key/skip")
  restoreActivationTask(@Req() req: Request, @Param("key") key: string) {
    return this.onboarding.restoreActivationTask(req.user as TenantUser, key);
  }

  @Patch("activation/tasks/:key/tour")
  setActivationTour(
    @Req() req: Request,
    @Param("key") key: string,
    @Body() dto: { step?: unknown },
  ) {
    return this.onboarding.setActivationTour(
      req.user as TenantUser,
      key,
      dto.step,
    );
  }
}
