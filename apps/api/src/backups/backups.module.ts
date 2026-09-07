import { Module } from "@nestjs/common";
import { PrismaModule } from "../prisma/prisma.module";
import { StorageModule } from "../storage/storage.module";
import { BackupsController } from "./backups.controller";
import { BackupsScheduler } from "./backups.scheduler";
import { BackupStorageService } from "./backup-storage.service";
import { BackupsRestoreService } from "./backups-restore.service";
import { BackupsService } from "./backups.service";

@Module({
  imports: [PrismaModule, StorageModule],
  controllers: [BackupsController],
  providers: [BackupsService, BackupsRestoreService, BackupStorageService, BackupsScheduler],
  exports: [BackupsService],
})
export class BackupsModule {}
