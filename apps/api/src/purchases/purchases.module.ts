import { Module } from "@nestjs/common";
import { PurchasesPublicController } from "./purchases-public.controller";
import { PurchasesController } from "./purchases.controller";
import { PurchasesService } from "./purchases.service";

@Module({
  controllers: [PurchasesController, PurchasesPublicController],
  providers: [PurchasesService],
})
export class PurchasesModule {}
