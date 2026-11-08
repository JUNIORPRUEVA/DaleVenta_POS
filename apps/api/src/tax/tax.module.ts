import { Global, Module } from "@nestjs/common";
import { TaxCalculationService } from "./tax-calculation.service";
import { TaxController } from "./tax.controller";
import { TaxService } from "./tax.service";

@Global()
@Module({
  controllers: [TaxController],
  providers: [TaxCalculationService, TaxService],
  exports: [TaxCalculationService, TaxService],
})
export class TaxModule {}
