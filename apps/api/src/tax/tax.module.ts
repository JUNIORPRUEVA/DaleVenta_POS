import { Global, Module } from "@nestjs/common";
import { TaxCalculationService } from "./tax-calculation.service";
import { TaxController } from "./tax.controller";
import { TaxService } from "./tax.service";
import { NcfService } from "./ncf.service";

@Global()
@Module({
  controllers: [TaxController],
  providers: [TaxCalculationService, TaxService, NcfService],
  exports: [TaxCalculationService, TaxService, NcfService],
})
export class TaxModule {}
