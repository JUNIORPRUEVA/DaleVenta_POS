import { Body, Controller, Get, Param, Patch, Post, Req, UseGuards } from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import { Request } from "express";
import { RolesGuard } from "../auth/roles.guard";
import type { TenantUser } from "../auth/tenant-context";
import { TaxService } from "./tax.service";
import { UpdateFiscalSettingsDto, UpsertTaxDto } from "./tax.dto";

@UseGuards(AuthGuard("jwt"), RolesGuard)
@Controller()
export class TaxController {
  constructor(private readonly taxes: TaxService) {}

  @Get("taxes")
  listTaxes(@Req() req: Request) {
    return this.taxes.listTaxes(req.user as TenantUser);
  }

  @Post("taxes")
  createTax(@Req() req: Request, @Body() dto: UpsertTaxDto) {
    return this.taxes.createTax(req.user as TenantUser, dto);
  }

  @Patch("taxes/:id")
  updateTax(@Req() req: Request, @Param("id") id: string, @Body() dto: Partial<UpsertTaxDto>) {
    return this.taxes.updateTax(req.user as TenantUser, id, dto);
  }

  @Get("company/fiscal-settings")
  getFiscalSettings(@Req() req: Request) {
    return this.taxes.getFiscalSettings(req.user as TenantUser);
  }

  @Patch("company/fiscal-settings")
  updateFiscalSettings(@Req() req: Request, @Body() dto: UpdateFiscalSettingsDto) {
    return this.taxes.updateFiscalSettings(req.user as TenantUser, dto);
  }
}
