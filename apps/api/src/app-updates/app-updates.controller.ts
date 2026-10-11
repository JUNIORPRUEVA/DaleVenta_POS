import { Controller, Get, Query, Req, Res } from "@nestjs/common";
import type { Request, Response } from "express";
import { AppUpdatesService } from "./app-updates.service";
import { AppUpdateManifestDto } from "./dto/app-update-manifest.dto";
import { CheckAppUpdateQueryDto } from "./dto/check-app-update-query.dto";

@Controller("api/app-updates")
export class AppUpdatesController {
  constructor(private readonly appUpdates: AppUpdatesService) {}

  @Get("check")
  check(
    @Query() query: CheckAppUpdateQueryDto,
    @Req() req: Request,
    @Res({ passthrough: true }) res: Response,
  ): Promise<AppUpdateManifestDto> {
    res.setHeader(
      "Cache-Control",
      this.appUpdates.usesPrivateUpdateCheckCache()
        ? "private, no-store"
        : "public, max-age=60",
    );
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
