import { Module } from "@nestjs/common";
import { AppUpdatesController } from "./app-updates.controller";
import { AppUpdatesService } from "./app-updates.service";

@Module({
  controllers: [AppUpdatesController],
  providers: [AppUpdatesService],
})
export class AppUpdatesModule {}
