import { Controller, Get, Header, Query, Req } from "@nestjs/common";
import type { Request } from "express";
import { AppUpdatesService } from "./app-updates.service";
import { AppUpdateManifestDto } from "./dto/app-update-manifest.dto";
import { CheckAppUpdateQueryDto } from "./dto/check-app-update-query.dto";

@Controller("api/app-updates")
export class AppUpdatesController {
  constructor(private readonly appUpdates: AppUpdatesService) {}

  @Get("check")
  @Header("Cache-Control", "public, max-age=60")
  check(
    @Query() query: CheckAppUpdateQueryDto,
    @Req() req: Request,
  ): Promise<AppUpdateManifestDto> {
    return this.appUpdates.check(query, this.clientKey(req));
  }

  private clientKey(req: Request) {
    const forwarded = req.headers["x-forwarded-for"];
    if (typeof forwarded === "string" && forwarded.trim().length > 0) {
      return forwarded.split(",")[0]?.trim() || req.ip || "unknown";
    }
    if (Array.isArray(forwarded) && forwarded[0]) return forwarded[0];
    return req.ip || "unknown";
  }
}
