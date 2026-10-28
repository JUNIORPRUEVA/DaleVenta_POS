import { Module } from "@nestjs/common";
import { SalesController } from "./sales.controller";
import { SalesService } from "./sales.service";
import { SaleAttemptReconciliationService } from "./sale-attempt-reconciliation.service";
import { SalesAdminController } from "./sales-admin.controller";
import { SalesPublicController } from "./sales-public.controller";
import { OpenSalesTicketsController } from "./open-sales-tickets.controller";
import { OpenSalesTicketsService } from "./open-sales-tickets.service";
import { TerminalResolutionService } from "../terminals/terminal-resolution.service";
import { PriceListsModule } from "../price-lists/price-lists.module";

@Module({
  imports: [PriceListsModule],
  controllers: [
    SalesController,
    SalesAdminController,
    SalesPublicController,
    OpenSalesTicketsController,
  ],
  providers: [
    SalesService,
    SaleAttemptReconciliationService,
    OpenSalesTicketsService,
    TerminalResolutionService,
  ],
})
export class SalesModule {}
