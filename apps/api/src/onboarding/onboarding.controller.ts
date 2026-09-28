import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Req,
  UseGuards,
} from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import { Request } from "express";
import { type TenantUser } from "../auth/tenant-context";
import { OnboardingService } from "./onboarding.service";

@UseGuards(AuthGuard("jwt"))
@Controller("onboarding")
export class OnboardingController {
  constructor(private readonly onboarding: OnboardingService) {}

  @Get()
  getState(@Req() req: Request) {
    return this.onboarding.getState(req.user as TenantUser);
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
}
