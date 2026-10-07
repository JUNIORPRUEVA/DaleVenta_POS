import { Body, Controller, Get, Param, Patch, Post, Query, UseGuards } from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import { Role } from "@prisma/client";
import { Roles } from "../auth/roles.decorator";
import { RolesGuard } from "../auth/roles.guard";
import { AppUpdatesService } from "./app-updates.service";
import {
  AppReleaseListQueryDto,
  CreateAppReleaseDto,
  UpdateAppReleaseDto,
} from "./dto/app-release-admin.dto";

@Controller("api/app-updates/releases")
@UseGuards(AuthGuard("jwt"), RolesGuard)
@Roles(Role.ADMIN)
export class AppUpdateReleasesController {
  constructor(private readonly appUpdates: AppUpdatesService) {}

  @Post()
  create(@Body() dto: CreateAppReleaseDto) {
    return this.appUpdates.createRelease(dto);
  }

  @Get()
  list(@Query() query: AppReleaseListQueryDto) {
    return this.appUpdates.listReleases(query);
  }

  @Get(":id")
  detail(@Param("id") id: string) {
    return this.appUpdates.getRelease(id);
  }

  @Patch(":id")
  update(@Param("id") id: string, @Body() dto: UpdateAppReleaseDto) {
    return this.appUpdates.updateRelease(id, dto);
  }

  @Post(":id/publish")
  publish(@Param("id") id: string) {
    return this.appUpdates.publishRelease(id);
  }

  @Post(":id/revoke")
  revoke(@Param("id") id: string) {
    return this.appUpdates.revokeRelease(id);
  }
}
