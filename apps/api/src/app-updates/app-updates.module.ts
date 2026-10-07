import { Module } from "@nestjs/common";
import { StorageModule } from "../storage/storage.module";
import { AppUpdateReleasesController } from "./app-update-releases.controller";
import { AppReleaseStorageService } from "./app-release-storage.service";
import { AppUpdatesController } from "./app-updates.controller";
import { AppUpdatesService } from "./app-updates.service";

@Module({
  imports: [StorageModule],
  controllers: [AppUpdatesController, AppUpdateReleasesController],
  providers: [AppUpdatesService, AppReleaseStorageService],
})
export class AppUpdatesModule {}
