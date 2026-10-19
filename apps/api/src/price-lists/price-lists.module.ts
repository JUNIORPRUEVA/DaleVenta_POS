import { Module } from "@nestjs/common";
import { PriceListsController } from "./price-lists.controller";
import { PriceListsService } from "./price-lists.service";
import { PricingEngineService } from "./pricing-engine.service";

@Module({
  controllers: [PriceListsController],
  providers: [PriceListsService, PricingEngineService],
  exports: [PriceListsService, PricingEngineService],
})
export class PriceListsModule {}
