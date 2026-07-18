import { Module } from "@nestjs/common";
import { SalesController } from "./sales.controller";
import { SalesService } from "./sales.service";
import { SalesAdminController } from "./sales-admin.controller";
import { SalesPublicController } from "./sales-public.controller";

@Module({
  controllers: [SalesController, SalesAdminController, SalesPublicController],
  providers: [SalesService],
})
export class SalesModule {}
