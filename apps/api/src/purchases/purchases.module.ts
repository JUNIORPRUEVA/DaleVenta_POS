import { Module } from "@nestjs/common";
import { PurchasesPublicController } from "./purchases-public.controller";
import { PurchasesController } from "./purchases.controller";
import { PurchasesService } from "./purchases.service";
import { StorageModule } from "../storage/storage.module";

@Module({
  imports: [StorageModule],
  controllers: [PurchasesController, PurchasesPublicController],
  providers: [PurchasesService],
})
export class PurchasesModule {}
