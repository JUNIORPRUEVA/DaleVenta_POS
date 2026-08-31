import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Req,
  UseGuards,
} from "@nestjs/common";
import { AuthGuard } from "@nestjs/passport";
import { Role } from "@prisma/client";
import type { Request } from "express";
import { Permissions, Roles } from "../auth/roles.decorator";
import { RolesGuard } from "../auth/roles.guard";
import type { TenantUser } from "../auth/tenant-context";
import {
  CreateWarehouseTransferDto,
  CreateWarehouseDto,
  UpdateTerminalWarehouseDto,
  UpdateWarehouseDto,
} from "./dto/warehouse.dto";
import { WarehousesService } from "./warehouses.service";

@UseGuards(AuthGuard("jwt"), RolesGuard)
@Controller("warehouses")
export class WarehousesController {
  constructor(private readonly warehouses: WarehousesService) {}

  @Get()
  @Permissions("viewWarehouses", "manageWarehouses")
  list(@Req() req: Request) {
    return this.warehouses.list(req.user as TenantUser);
  }

  @Get("terminals")
  @Permissions("viewTerminals", "manageTerminals", "manageWarehouses")
  listTerminals(@Req() req: Request) {
    return this.warehouses.listTerminals(req.user as TenantUser);
  }

  @Get("products/:productId/stock")
  @Permissions("viewWarehouseBreakdown", "manageWarehouses")
  stockBreakdown(@Req() req: Request, @Param("productId") productId: string) {
    return this.warehouses.productStockBreakdown(
      req.user as TenantUser,
      productId,
    );
  }

  @Get("transfers")
  @Permissions("viewTransfers", "createTransfers", "manageWarehouses")
  listTransfers(@Req() req: Request) {
    return this.warehouses.listTransfers(req.user as TenantUser);
  }

  @Get("transfers/:id")
  @Permissions("viewTransfers", "createTransfers", "manageWarehouses")
  getTransfer(@Req() req: Request, @Param("id") id: string) {
    return this.warehouses.getTransfer(req.user as TenantUser, id);
  }

  @Roles(Role.ADMIN)
  @Permissions("createTransfers", "manageWarehouses")
  @Post("transfers")
  createTransfer(@Req() req: Request, @Body() dto: CreateWarehouseTransferDto) {
    return this.warehouses.createTransfer(req.user as TenantUser, dto);
  }

  @Roles(Role.ADMIN)
  @Permissions("createTransfers", "manageWarehouses")
  @Delete("transfers/:id")
  deleteTransfer(@Req() _req: Request, @Param("id") _id: string) {
    return this.warehouses.deleteTransfer();
  }

  @Roles(Role.ADMIN)
  @Permissions("createWarehouses", "manageWarehouses")
  @Post()
  create(@Req() req: Request, @Body() dto: CreateWarehouseDto) {
    return this.warehouses.create(req.user as TenantUser, dto);
  }

  @Roles(Role.ADMIN)
  @Permissions("editWarehouses", "manageWarehouses")
  @Patch(":id")
  update(
    @Req() req: Request,
    @Param("id") id: string,
    @Body() dto: UpdateWarehouseDto,
  ) {
    return this.warehouses.update(req.user as TenantUser, id, dto);
  }

  @Roles(Role.ADMIN)
  @Permissions("changeDefaultWarehouse", "manageWarehouses")
  @Patch(":id/default")
  setDefault(@Req() req: Request, @Param("id") id: string) {
    return this.warehouses.setDefault(req.user as TenantUser, id);
  }

  @Roles(Role.ADMIN)
  @Permissions("activateWarehouses", "manageWarehouses")
  @Patch(":id/activate")
  activate(@Req() req: Request, @Param("id") id: string) {
    return this.warehouses.activate(req.user as TenantUser, id);
  }

  @Roles(Role.ADMIN)
  @Permissions("activateWarehouses", "manageWarehouses")
  @Patch(":id/deactivate")
  deactivate(@Req() req: Request, @Param("id") id: string) {
    return this.warehouses.deactivate(req.user as TenantUser, id);
  }

  @Roles(Role.ADMIN)
  @Permissions("manageTerminals", "manageWarehouses")
  @Patch("terminals/:id/default-warehouse")
  updateTerminalWarehouse(
    @Req() req: Request,
    @Param("id") id: string,
    @Body() dto: UpdateTerminalWarehouseDto,
  ) {
    return this.warehouses.updateTerminalWarehouse(
      req.user as TenantUser,
      id,
      dto,
    );
  }
}
