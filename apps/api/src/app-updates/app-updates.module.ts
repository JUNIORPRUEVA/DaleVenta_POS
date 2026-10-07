import { Module } from "@nestjs/common";
import { AppUpdateReleasesController } from "./app-update-releases.controller";
import { AppUpdatesController } from "./app-updates.controller";
import { AppUpdatesService } from "./app-updates.service";

@Module({
  controllers: [AppUpdatesController, AppUpdateReleasesController],
  providers: [AppUpdatesService],
})
export class AppUpdatesModule {}
