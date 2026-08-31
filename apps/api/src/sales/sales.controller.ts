import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Post,
  Query,
  Req,
  UseGuards,
} from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import { Role } from "@prisma/client";
import { Request } from "express";
import { Permissions, Roles } from "../auth/roles.decorator";
import { RolesGuard } from "../auth/roles.guard";
import type { TenantUser } from "../auth/tenant-context";
import { SalesService } from "./sales.service";
import { CreateSaleDto, CreateSaleReturnDto } from "./dto/create-sale.dto";
import { CreateSalePdfShareLinkDto } from "./dto/create-sale-pdf-share-link.dto";
import { SalesRangeQueryDto } from "./dto/sales-range-query.dto";

@UseGuards(AuthGuard("jwt"), RolesGuard)
@Controller("sales")
export class SalesController {
  constructor(private readonly sales: SalesService) {}

  @Get()
  listMine(@Req() req: Request, @Query() query: SalesRangeQueryDto) {
    const user = req.user as TenantUser;
    return this.sales.listMine(
      user,
      query.from,
      query.to,
      query.customerId,
      query.includeDeleted === "true",
      query.limit,
    );
  }

  @Get("invoices")
  listInvoices(@Req() req: Request, @Query() query: SalesRangeQueryDto) {
    const user = req.user as TenantUser;
    return this.sales.listInvoices(
      user,
      query.from,
      query.to,
      query.customerId,
      query.includeDeleted === "true",
      query.limit,
    );
  }

  @Get("credits")
  listCredits(@Req() req: Request, @Query("includePaid") includePaid?: string) {
    const user = req.user as TenantUser;
    return this.sales.listCredits(user, includePaid === "true");
  }

  @Get("summary")
  summaryMine(@Req() req: Request, @Query() query: SalesRangeQueryDto) {
    const user = req.user as TenantUser;
    return this.sales.summaryMine(user, query.from, query.to, query.customerId);
  }

  @Post()
  create(@Req() req: Request, @Body() dto: CreateSaleDto) {
    const user = req.user as TenantUser;
    dto.deviceFingerprint ??= this.headerValue(req, "x-client-device-id");
    return this.sales.create(user, dto);
  }

  @Post("calculate")
  calculate(@Req() req: Request, @Body() dto: CreateSaleDto) {
    const user = req.user as TenantUser;
    return this.sales.calculate(user, dto);
  }

  @Post("pdf-share-link")
  createPdfShareLink(
    @Req() req: Request,
    @Body() dto: CreateSalePdfShareLinkDto,
  ) {
    const user = req.user as TenantUser;
    const forwardedProto = `${req.headers["x-forwarded-proto"] ?? ""}`
      .split(",")[0]
      .trim();
    const proto = forwardedProto || req.protocol || "http";
    const host = req.get("host") ?? "";
    const requestBaseUrl = host ? `${proto}://${host}` : undefined;
    return this.sales.createInvoicePdfShareLink(user, dto, requestBaseUrl);
  }

  @Delete("debug/purge")
  @Roles(Role.ADMIN)
  purgeAllForDebug(@Req() req: Request) {
    const user = req.user as TenantUser;
    return this.sales.purgeAllForDebug(user);
  }

  @Delete(":id")
  @Permissions("cancelSales")
  remove(@Req() req: Request, @Param("id") id: string) {
    const user = req.user as TenantUser;
    return this.sales.remove(user, id);
  }

  @Post(":id/credit-payments")
  addCreditPayment(
    @Req() req: Request,
    @Param("id") id: string,
    @Body()
    dto: { cashAmount?: number; transferAmount?: number; note?: string },
  ) {
    const user = req.user as TenantUser;
    return this.sales.addCreditPayment(user, id, dto);
  }

  @Post(":id/return")
  @Permissions("refundSales")
  returnSale(
    @Req() req: Request,
    @Param("id") id: string,
    @Body() dto: CreateSaleReturnDto,
  ) {
    const user = req.user as TenantUser;
    return this.sales.returnSale(user, id, dto);
  }

  private headerValue(req: Request, name: string) {
    const value = req.headers[name];
    const text = Array.isArray(value) ? value[0] : value;
    const trimmed = `${text ?? ""}`.trim();
    return trimmed.length > 0 ? trimmed : undefined;
  }
}
