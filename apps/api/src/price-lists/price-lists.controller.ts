import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Post,
  Req,
  UseGuards,
} from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import { Request } from "express";
import { Permissions, Roles } from "../auth/roles.decorator";
import { RolesGuard } from "../auth/roles.guard";
import { type TenantUser } from "../auth/tenant-context";
import { PriceListsService } from "./price-lists.service";
import {
  AssignClientPriceListDto,
  CreatePriceListDto,
  ResolvePriceListLineDto,
  UpdatePriceListDto,
  UpsertPriceListRuleDto,
} from "./dto/price-list.dto";
import { Role } from "@prisma/client";

@UseGuards(AuthGuard("jwt"), RolesGuard)
@Controller("price-lists")
export class PriceListsController {
  constructor(private readonly priceLists: PriceListsService) {}

  @Get()
  @Permissions("viewSales", "viewQuotes", "viewClients")
  list(@Req() req: Request) {
    return this.priceLists.list(req.user as TenantUser);
  }

  @Get(":id")
  @Permissions("viewSales", "viewQuotes", "viewClients")
  findOne(@Req() req: Request, @Param("id") id: string) {
    return this.priceLists.findOne(req.user as TenantUser, id);
  }

  @Post()
  @Permissions("managePriceLists")
  @Roles(Role.ADMIN, Role.ASISTENTE)
  create(@Req() req: Request, @Body() dto: CreatePriceListDto) {
    return this.priceLists.create(req.user as TenantUser, dto);
  }

  @Patch(":id")
  @Permissions("managePriceLists")
  @Roles(Role.ADMIN, Role.ASISTENTE)
  update(
    @Req() req: Request,
    @Param("id") id: string,
    @Body() dto: UpdatePriceListDto,
  ) {
    return this.priceLists.update(req.user as TenantUser, id, dto);
  }

  @Post(":id/rules")
  @Permissions("managePriceLists")
  @Roles(Role.ADMIN, Role.ASISTENTE)
  upsertRule(
    @Req() req: Request,
    @Param("id") id: string,
    @Body() dto: UpsertPriceListRuleDto,
  ) {
    return this.priceLists.upsertRule(req.user as TenantUser, id, dto);
  }

  @Patch("clients/:clientId")
  @Permissions("managePriceLists")
  @Roles(Role.ADMIN, Role.ASISTENTE)
  assignClient(
    @Req() req: Request,
    @Param("clientId") clientId: string,
    @Body() dto: AssignClientPriceListDto,
  ) {
    return this.priceLists.assignClient(req.user as TenantUser, clientId, dto);
  }

  @Post("resolve-line")
  @Permissions("viewSales", "viewQuotes")
  resolveLine(@Req() req: Request, @Body() dto: ResolvePriceListLineDto) {
    return this.priceLists.resolveLine(req.user as TenantUser, dto);
  }
}
