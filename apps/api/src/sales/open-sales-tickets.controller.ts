import { Body, Controller, Get, Put, Req, UseGuards } from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import { Request } from "express";
import { RolesGuard } from "../auth/roles.guard";
import type { TenantUser } from "../auth/tenant-context";
import { OpenSalesTicketsService } from "./open-sales-tickets.service";

@UseGuards(AuthGuard("jwt"), RolesGuard)
@Controller("sales/open-tickets")
export class OpenSalesTicketsController {
  constructor(private readonly openTickets: OpenSalesTicketsService) {}

  @Get()
  list(@Req() req: Request) {
    return this.openTickets.getState(req.user as TenantUser);
  }

  @Put()
  replace(@Req() req: Request, @Body() dto: unknown) {
    return this.openTickets.replaceState(req.user as TenantUser, dto);
  }
}
