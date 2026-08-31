import { Global, Module } from "@nestjs/common";
import { InventoryMutationService } from "./inventory-mutation.service";
import { InventoryReportingController } from "./inventory-reporting.controller";
import { InventoryReportingService } from "./inventory-reporting.service";

@Global()
@Module({
  controllers: [InventoryReportingController],
  providers: [InventoryMutationService, InventoryReportingService],
  exports: [InventoryMutationService, InventoryReportingService],
})
export class InventoryModule {}
