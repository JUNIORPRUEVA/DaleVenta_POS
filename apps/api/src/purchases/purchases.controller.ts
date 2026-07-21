import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Param,
  Patch,
  Post,
  Query,
  Req,
  UploadedFile,
  UseGuards,
  UseInterceptors,
} from "@nestjs/common";
import { FileInterceptor } from "@nestjs/platform-express";
import { AuthGuard } from "@nestjs/passport";
import { Role } from "@prisma/client";
import type { Express, Request } from "express";
import { memoryStorage } from "multer";
import { Roles } from "../auth/roles.decorator";
import { RolesGuard } from "../auth/roles.guard";
import {
  CreatePurchaseInvoiceDto,
  CreatePurchaseOrderPdfShareLinkDto,
  CreatePurchaseOrderDto,
  ReceivePurchaseOrderDto,
  UpdatePurchaseOrderDto,
  UpsertSupplierDto,
} from "./dto/purchases.dto";
import { PurchasesService } from "./purchases.service";

type RequestUser = { id: string; role: Role };

@UseGuards(AuthGuard("jwt"), RolesGuard)
@Roles(Role.ADMIN)
@Controller("purchases")
export class PurchasesController {
  constructor(private readonly purchases: PurchasesService) {}

  @Get("suppliers")
  listSuppliers(
    @Query("q") q?: string,
    @Query("includeInactive") includeInactive?: string,
  ) {
    return this.purchases.listSuppliers(q, includeInactive === "true");
  }

  @Post("suppliers")
  @Roles(Role.ADMIN)
  createSupplier(@Body() dto: UpsertSupplierDto) {
    return this.purchases.createSupplier(dto);
  }

  @Patch("suppliers/:id")
  @Roles(Role.ADMIN)
  updateSupplier(@Param("id") id: string, @Body() dto: UpsertSupplierDto) {
    return this.purchases.updateSupplier(id, dto);
  }

  @Delete("suppliers/:id")
  @Roles(Role.ADMIN)
  deactivateSupplier(@Param("id") id: string) {
    return this.purchases.deactivateSupplier(id);
  }

  @Get("orders")
  listOrders(
    @Req() req: Request,
    @Query("q") q?: string,
    @Query("status") status?: string,
    @Query("supplierId") supplierId?: string,
  ) {
    return this.purchases.listOrders(req.user as RequestUser, {
      q,
      status,
      supplierId,
    });
  }

  @Get("invoices")
  listInvoices(
    @Query("q") q?: string,
    @Query("supplierId") supplierId?: string,
    @Query("purchaseOrderId") purchaseOrderId?: string,
  ) {
    return this.purchases.listInvoices({ q, supplierId, purchaseOrderId });
  }

  @Post("invoices")
  @Roles(Role.ADMIN)
  @UseInterceptors(
    FileInterceptor("file", {
      storage: memoryStorage(),
      fileFilter: (_req, file, cb) => {
        const allowed =
          /^image\/(png|jpe?g|webp)$/.test(file.mimetype) ||
          file.mimetype === "application/pdf" ||
          file.mimetype === "application/msword" ||
          file.mimetype ===
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ||
          file.mimetype === "application/vnd.ms-excel" ||
          file.mimetype ===
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
        if (!allowed) {
          return cb(
            new BadRequestException(
              "Solo se permiten facturas en PDF, imagen, Word o Excel.",
            ),
            false,
          );
        }
        cb(null, true);
      },
      limits: { fileSize: 20 * 1024 * 1024 },
    }),
  )
  createInvoice(
    @Req() req: Request,
    @Body() dto: CreatePurchaseInvoiceDto,
    @UploadedFile() file?: Express.Multer.File,
  ) {
    if (!file?.buffer?.length) {
      throw new BadRequestException("Selecciona el archivo de la factura.");
    }
    const forwardedProto = `${req.headers["x-forwarded-proto"] ?? ""}`
      .split(",")[0]
      .trim();
    const proto = forwardedProto || req.protocol || "http";
    const forwardedHost = `${req.headers["x-forwarded-host"] ?? ""}`
      .split(",")[0]
      .trim();
    const host = forwardedHost || req.get("host") || "";
    const requestBaseUrl = host ? `${proto}://${host}` : undefined;
    return this.purchases.createInvoice(
      req.user as RequestUser,
      dto,
      file,
      requestBaseUrl,
    );
  }

  @Delete("invoices/:id")
  @Roles(Role.ADMIN)
  deleteInvoice(@Param("id") id: string) {
    return this.purchases.deleteInvoice(id);
  }

  @Get("orders/:id")
  getOrder(@Req() req: Request, @Param("id") id: string) {
    return this.purchases.getOrder(req.user as RequestUser, id);
  }

  @Post("orders")
  @Roles(Role.ADMIN)
  createOrder(@Req() req: Request, @Body() dto: CreatePurchaseOrderDto) {
    return this.purchases.createOrder(req.user as RequestUser, dto);
  }

  @Patch("orders/:id")
  @Roles(Role.ADMIN)
  updateOrder(
    @Req() req: Request,
    @Param("id") id: string,
    @Body() dto: UpdatePurchaseOrderDto,
  ) {
    return this.purchases.updateOrder(req.user as RequestUser, id, dto);
  }

  @Post("orders/:id/duplicate")
  @Roles(Role.ADMIN)
  duplicateOrder(@Req() req: Request, @Param("id") id: string) {
    return this.purchases.duplicateOrder(req.user as RequestUser, id);
  }

  @Post("orders/:id/approve")
  @Roles(Role.ADMIN)
  approveOrder(@Req() req: Request, @Param("id") id: string) {
    return this.purchases.approveOrder(req.user as RequestUser, id);
  }

  @Post("orders/:id/send")
  @Roles(Role.ADMIN)
  markSent(@Req() req: Request, @Param("id") id: string) {
    return this.purchases.markSent(req.user as RequestUser, id);
  }

  @Post("orders/:id/cancel")
  @Roles(Role.ADMIN)
  cancelOrder(
    @Req() req: Request,
    @Param("id") id: string,
    @Body() dto: { reason?: string },
  ) {
    return this.purchases.cancelOrder(req.user as RequestUser, id, dto.reason);
  }

  @Delete("orders/:id")
  @Roles(Role.ADMIN)
  deleteDraft(@Req() req: Request, @Param("id") id: string) {
    return this.purchases.deleteDraft(req.user as RequestUser, id);
  }

  @Post("orders/:id/receive")
  @Roles(Role.ADMIN)
  receiveOrder(
    @Req() req: Request,
    @Param("id") id: string,
    @Body() dto: ReceivePurchaseOrderDto,
  ) {
    return this.purchases.receiveOrder(req.user as RequestUser, id, dto);
  }

  @Get("recommendations")
  recommendations() {
    return this.purchases.recommendations();
  }

  @Post("pdf-share-link")
  @Roles(Role.ADMIN)
  createPdfShareLink(
    @Req() req: Request,
    @Body() dto: CreatePurchaseOrderPdfShareLinkDto,
  ) {
    const forwardedProto = `${req.headers["x-forwarded-proto"] ?? ""}`
      .split(",")[0]
      .trim();
    const proto = forwardedProto || req.protocol || "http";
    const host = req.get("host") ?? "";
    const requestBaseUrl = host ? `${proto}://${host}` : undefined;
    return this.purchases.createPdfShareLink(
      req.user as RequestUser,
      dto,
      requestBaseUrl,
    );
  }
}
