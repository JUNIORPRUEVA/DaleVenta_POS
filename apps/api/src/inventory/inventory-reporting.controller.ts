import { Controller, Get, Query, Req, UseGuards } from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import type { Request } from "express";
import { Permissions } from "../auth/roles.decorator";
import { RolesGuard } from "../auth/roles.guard";
import type { TenantUser } from "../auth/tenant-context";
import { InventoryReportingService } from "./inventory-reporting.service";

@UseGuards(AuthGuard("jwt"), RolesGuard)
@Controller("inventory")
export class InventoryReportingController {
  constructor(private readonly reporting: InventoryReportingService) {}

  @Get("movements")
  @Permissions("viewInventoryHistory", "viewSalesReports")
  movements(@Req() req: Request, @Query() query: Record<string, string>) {
    return this.reporting.listMovements(req.user as TenantUser, query);
  }

  @Get("stock-report")
  @Permissions("viewWarehouseBreakdown", "viewSalesReports")
  stockReport(@Req() req: Request) {
    return this.reporting.stockReport(req.user as TenantUser);
  }

  @Get("reconciliation")
  @Permissions("viewInventoryHistory", "viewSalesReports")
  reconciliation(@Req() req: Request) {
    return this.reporting.reconciliation(req.user as TenantUser);
  }
}
