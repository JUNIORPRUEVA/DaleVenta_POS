import {
  BadGatewayException,
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from "@nestjs/common";
import { Logger } from "@nestjs/common";
import { createHash } from "node:crypto";
import * as fs from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import * as path from "node:path";
import { ConfigService } from "@nestjs/config";
import {
  CompanyManualAudience,
  CompanyManualEntryKind,
  CompanyMemberRole,
  CompanyMemberStatus,
  Prisma,
  Role,
} from "@prisma/client";
import { RedisService } from "../common/redis/redis.service";
import { EvolutionWhatsAppService } from "../notifications/evolution-whatsapp.service";
import { PrismaService } from "../prisma/prisma.service";
import { isAdminLike, requireTenant, TenantUser } from "../auth/tenant-context";
import { normalizePhone } from "../common/utils/normalize-phone";
import { AnalyzeCotizacionAiDto } from "./dto/analyze-cotizacion-ai.dto";
import { ChatCotizacionAiDto } from "./dto/chat-cotizacion-ai.dto";
import { CreateCotizacionPdfShareLinkDto } from "./dto/create-cotizacion-pdf-share-link.dto";
import {
  CreateCotizacionDto,
  CreateCotizacionItemDto,
} from "./dto/create-cotizacion.dto";
import { SendCotizacionWhatsappDto } from "./dto/send-cotizacion-whatsapp.dto";
import { UpdateCotizacionDto } from "./dto/update-cotizacion.dto";

type AiRuntimeConfig = {
  apiKey: string;
  model: string;
  companyName: string;
};

type BusinessRuleRecord = {
  id: string;
  module: string;
  category: string;
  title: string;
  content: string;
  summary: string | null;
  keywords: string[];
  severity: "info" | "warning" | "critical";
  active: boolean;
  createdAt: string | null;
  updatedAt: string | null;
};

const QUOTES_LIST_CACHE_PATTERN = "quotes:list:*";
const QUOTES_DETAIL_CACHE_PATTERN = "quotes:detail:*";

@Injectable()
export class CotizacionesService {
  private readonly logger = new Logger(CotizacionesService.name);
  private static readonly noRuleMessage =
    "No encontré una regla oficial para eso dentro del sistema.";
  private static readonly rulesOnlyReminder =
    "Solo puedo responder con base en el Manual Interno y el conocimiento autorizado de la app. Hazme una pregunta concreta sobre una regla, un proceso o un modulo del sistema.";
  private static readonly unauthorizedMessage =
    "No puedo ayudar con informacion privada de otro usuario ni mostrar datos para los que no tienes autorizacion.";

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly redis: RedisService,
    private readonly evolutionWhatsApp: EvolutionWhatsAppService,
  ) {}

  private buildQuoteInclude() {
    return {
      items: { orderBy: { createdAt: "asc" as const } },
      createdBy: {
        select: {
          id: true,
          nombreCompleto: true,
          email: true,
        },
      },
    } satisfies Prisma.CotizacionInclude;
  }

  private parsePdfBase64(value: string) {
    const trimmed = (value ?? "").trim();
    if (!trimmed) {
      throw new BadRequestException("Debes enviar el PDF de la cotización.");
    }

    const base64 = trimmed.startsWith("data:")
      ? trimmed.slice(trimmed.indexOf(",") + 1)
      : trimmed;

    let bytes: Buffer;
    try {
      bytes = Buffer.from(base64, "base64");
    } catch {
      throw new BadRequestException("El PDF de la cotización no es válido.");
    }

    if (!bytes.length) {
      throw new BadRequestException("El PDF de la cotización llegó vacío.");
    }

    const maxPdfBytes = 8 * 1024 * 1024;
    if (bytes.length > maxPdfBytes) {
      const sizeMb = (bytes.length / (1024 * 1024)).toFixed(2);
      throw new BadRequestException(
        `El PDF de la cotización pesa ${sizeMb} MB y supera el límite de 8 MB para envío por WhatsApp.`,
      );
    }

    return bytes;
  }

  private resolveUploadDir() {
    const fromEnv = (this.config.get<string>("UPLOAD_DIR") ?? "").trim();
    const volumeDir = "/uploads";
    const volumeExists = fs.existsSync(volumeDir);

    if (fromEnv) {
      if ((fromEnv === "./uploads" || fromEnv === "uploads") && volumeExists) {
        return volumeDir;
      }
      return fromEnv;
    }

    return volumeExists ? volumeDir : path.join(process.cwd(), "uploads");
  }

  private publicBaseUrl(requestBaseUrl?: string) {
    const raw =
      (this.config.get<string>("PUBLIC_BASE_URL") ?? "").trim() ||
      (this.config.get<string>("API_BASE_URL") ?? "").trim() ||
      (process.env.PUBLIC_BASE_URL ?? "").trim() ||
      (process.env.API_BASE_URL ?? "").trim() ||
      (requestBaseUrl ?? "").trim();

    return raw.replace(/\/+$/, "");
  }

  private sanitizePdfFileName(value: string, fallback: string) {
    const source = (value || fallback).trim() || fallback;
    const base = path
      .basename(source)
      .replace(/[^a-zA-Z0-9._-]+/g, "_")
      .replace(/^_+|_+$/g, "");
    const withExt = base.toLowerCase().endsWith(".pdf") ? base : `${base}.pdf`;
    return withExt || fallback;
  }

  async resolvePublicPdfDownload(quotationId: string, fileName: string) {
    const safeQuotationId = (quotationId ?? "").trim();
    const safeFileName = this.sanitizePdfFileName(
      fileName ?? "",
      "cotizacion.pdf",
    );
    if (
      !safeQuotationId ||
      safeQuotationId.includes("/") ||
      safeQuotationId.includes("\\")
    ) {
      throw new NotFoundException("PDF de cotización no encontrado.");
    }

    const absolutePath = path.join(
      this.resolveUploadDir(),
      "cotizaciones",
      safeQuotationId,
      safeFileName,
    );

    if (!fs.existsSync(absolutePath)) {
      throw new NotFoundException("PDF de cotización no encontrado.");
    }

    return {
      absolutePath,
      fileName: safeFileName,
    };
  }

  private extractEvolutionHttpStatus(errorMessage: string) {
    const normalized = (errorMessage ?? "").toString();
    const matches = [
      /HTTP\s+(\d{3})/i.exec(normalized),
      /status\s*[:=]\s*(\d{3})/i.exec(normalized),
      /\b(4\d{2}|5\d{2})\b/.exec(normalized),
    ];
    for (const match of matches) {
      if (!match?.[1]) continue;
      const status = Number.parseInt(match[1], 10);
      if (!Number.isNaN(status)) return status;
    }
    return null;
  }

  private mapWhatsAppSendError(error: unknown) {
    if (
      error instanceof BadRequestException ||
      error instanceof ForbiddenException ||
      error instanceof NotFoundException
    ) {
      return error;
    }

    if (error instanceof Error) {
      const message = error.message.trim();
      const normalized = message.toLowerCase();
      const status = this.extractEvolutionHttpStatus(message);

      if (normalized.includes("ephemeralmessage")) {
        return new BadGatewayException(
          "El proveedor Evolution (v2.3.1) tiene un fallo interno al procesar documentos PDF (ephemeralMessage). Debes actualizar Evolution a una versión estable más reciente o aplicar su parche de media para que el envío funcione.",
        );
      }

      if (normalized.includes("timeout")) {
        return new ServiceUnavailableException(
          "No se pudo enviar por WhatsApp porque el servicio tardó demasiado en responder. Revisa conexión e intenta nuevamente.",
        );
      }

      if (status === 401 || status === 403) {
        return new BadRequestException(
          "El servidor de WhatsApp rechazó la conexión (credenciales o instancia). Revisa API Key, instancia y estado de conexión.",
        );
      }

      if (status === 404) {
        return new BadRequestException(
          "La instancia de WhatsApp configurada no existe en el servidor de mensajería. Verifica el nombre de la instancia.",
        );
      }

      if (status === 413) {
        return new BadRequestException(
          "El archivo PDF es demasiado pesado para WhatsApp. Reduce el tamaño del PDF y reintenta.",
        );
      }

      if (status === 415 || status === 422) {
        return new BadRequestException(
          "El servidor de WhatsApp rechazó el formato del PDF enviado. Regenera el PDF e intenta nuevamente.",
        );
      }

      if (status != null && status >= 500) {
        return new BadGatewayException(
          "El proveedor de mensajería WhatsApp reportó un error interno. El envío no se completó; intenta nuevamente en unos minutos.",
        );
      }

      return new BadGatewayException(
        `No se pudo completar el envío por WhatsApp. Detalle técnico: ${message}`,
      );
    }

    return new BadGatewayException(
      "No se pudo completar el envío por WhatsApp por un error inesperado del servidor.",
    );
  }

  private async buildQuoteWhatsAppCaption(customerName: string) {
    const row = await this.prisma.appConfig.findUnique({
      where: { id: "global" },
      select: { companyName: true },
    });

    const companyName = (row?.companyName ?? "").trim() || "FULLTECH";
    const safeCustomerName = customerName.trim() || "cliente";

    return `Hola ${safeCustomerName}, te compartimos tu cotización de ${companyName}. Si deseas continuar, responde a este mensaje y te ayudamos.`;
  }

  private ensureQuoteAccessForSend(
    user: TenantUser,
    quotation: { createdByUserId: string },
  ) {
    if (user.role === Role.ADMIN) return;
    if (quotation.createdByUserId !== user.id) {
      throw new ForbiddenException(
        "No tienes permiso para enviar esta cotización.",
      );
    }
  }

  private async ensureConnectedUserInstance(userId: string) {
    const instance = await this.prisma.userWhatsappInstance.findUnique({
      where: { userId },
      select: {
        id: true,
        instanceName: true,
        status: true,
        phoneNumber: true,
      },
    });

    const status = (instance?.status ?? "").trim().toLowerCase();
    const isConnected = status === "connected" || status === "open";
    if (!instance || !isConnected) {
      throw new BadRequestException(
        "Debes conectar tu WhatsApp antes de enviar cotizaciones.",
      );
    }

    return instance;
  }

  private async resolveAdminDestinationPhones(companyId: string) {
    const adminUsers = await this.prisma.user.findMany({
      where: {
        blocked: false,
        companyMemberships: {
          some: {
            companyId,
            status: CompanyMemberStatus.ACTIVE,
            role: { in: [CompanyMemberRole.OWNER, CompanyMemberRole.ADMIN] },
          },
        },
      },
      select: {
        id: true,
        telefono: true,
        whatsappInstance: {
          select: {
            phoneNumber: true,
          },
        },
      },
    });

    const appConfig = await this.prisma.appConfig.findUnique({
      where: { id: "global" },
      select: {
        phonePreferential: true,
        phone: true,
      },
    });

    const candidates: string[] = [];
    for (const admin of adminUsers) {
      candidates.push(admin.whatsappInstance?.phoneNumber ?? "");
      candidates.push(admin.telefono ?? "");
    }
    candidates.push(appConfig?.phonePreferential ?? "");
    candidates.push(appConfig?.phone ?? "");
    candidates.push(
      this.config.get<string>("QUOTATION_APPROVAL_ADMIN_PHONE") ?? "",
    );
    candidates.push(process.env.QUOTATION_APPROVAL_ADMIN_PHONE ?? "");

    const destinations = Array.from(
      new Set(
        candidates
          .map((value) =>
            this.evolutionWhatsApp.normalizeWhatsAppNumber(
              (value ?? "").trim(),
            ),
          )
          .filter(
            (value): value is string =>
              !!value && value.length >= 11 && value.length <= 15,
          ),
      ),
    );

    if (destinations.length > 0) {
      return destinations;
    }

    throw new BadRequestException(
      "No hay teléfonos admin válidos para recibir cotizaciones por WhatsApp.",
    );
  }

  private isLikelyWhatsAppDestination(number: string) {
    return number.length >= 11 && number.length <= 15;
  }

  private async resolveClientDestination(companyId: string, quotation: {
    id: string;
    customerId: string | null;
    customerPhone: string;
  }) {
    const quotePhoneNormalized = this.evolutionWhatsApp.normalizeWhatsAppNumber(
      quotation.customerPhone,
    );

    if (this.isLikelyWhatsAppDestination(quotePhoneNormalized)) {
      return quotePhoneNormalized;
    }

    if (quotation.customerId) {
      const customer = await this.prisma.client.findFirst({
        where: { id: quotation.customerId, companyId },
        select: { telefono: true, phoneNormalized: true },
      });

      const clientPhoneRaw = (customer?.telefono ?? "").trim();
      const clientPhoneNormalized =
        this.evolutionWhatsApp.normalizeWhatsAppNumber(clientPhoneRaw) ||
        this.evolutionWhatsApp.normalizeWhatsAppNumber(
          (customer?.phoneNormalized ?? "").trim(),
        );

      if (this.isLikelyWhatsAppDestination(clientPhoneNormalized)) {
        await this.prisma.cotizacion.update({
          where: { id: quotation.id },
          data: {
            customerPhone: clientPhoneRaw || clientPhoneNormalized,
            customerPhoneNormalized: normalizePhone(clientPhoneRaw),
          },
        });
        return clientPhoneNormalized;
      }
    }

    throw new BadRequestException(
      "El cliente no tiene teléfono válido para enviar la cotización. Abre el cliente, corrige el teléfono (con código de país) y vuelve a intentar.",
    );
  }

  private buildQuotesListCacheKey(
    user: TenantUser,
    query: { customerPhone?: string; take?: number },
  ) {
    const scope = {
      companyId: user.companyId?.trim() ?? null,
      userId: user.id,
      role: user.role,
      customerPhone: query.customerPhone?.trim() ?? null,
      take: Math.min(Math.max(query.take ?? 80, 1), 500),
    };
    const hash = createHash("sha1").update(JSON.stringify(scope)).digest("hex");
    return `quotes:list:${hash}`;
  }

  private buildQuoteDetailCacheKey(
    user: TenantUser,
    id: string,
  ) {
    const hash = createHash("sha1")
      .update(
        JSON.stringify({
          companyId: user.companyId?.trim() ?? null,
          userId: user.id,
          role: user.role,
          id: id.trim(),
        }),
      )
      .digest("hex");
    return `quotes:detail:${hash}`;
  }

  private async invalidateQuoteCache(reason: string) {
    const [listsDeleted, detailDeleted] = await Promise.all([
      this.redis.delByPattern(QUOTES_LIST_CACHE_PATTERN),
      this.redis.delByPattern(QUOTES_DETAIL_CACHE_PATTERN),
    ]);
    if (this.redis.isEnabled()) {
      this.logger.log(
        `Redis INVALIDATE quotes reason=${reason} lists=${listsDeleted} details=${detailDeleted}`,
      );
    }
  }

  private async resolveCustomerIdByPhone(
    tx: Prisma.TransactionClient,
    input: {
      companyId: string;
      userId: string;
      customerId?: string | null;
      customerName: string;
      customerPhone: string;
      customerPhoneNormalized: string;
    },
  ) {
    if (input.customerId) {
      const customer = await tx.client.findFirst({
        where: {
          id: input.customerId,
          companyId: input.companyId,
          isDeleted: false,
        },
        select: { id: true },
      });
      if (!customer) {
        throw new BadRequestException("Cliente no pertenece a esta empresa.");
      }
      return customer.id;
    }

    if (!input.customerPhoneNormalized) return null;

    const existing = await tx.client.findFirst({
      where: {
        companyId: input.companyId,
        isDeleted: false,
        phoneNormalized: input.customerPhoneNormalized,
      },
      select: { id: true },
    });
    if (existing) return existing.id;

    try {
      const created = await tx.client.create({
        data: {
          ownerId: input.userId,
          companyId: input.companyId,
          nombre: input.customerName,
          telefono: input.customerPhone,
          phoneNormalized: input.customerPhoneNormalized,
          lastActivityAt: new Date(),
        },
        select: { id: true },
      });
      return created.id;
    } catch (e: any) {
      // In case of race condition with unique constraint.
      const found = await tx.client.findFirst({
        where: {
          companyId: input.companyId,
          isDeleted: false,
          phoneNormalized: input.customerPhoneNormalized,
        },
        select: { id: true },
      });
      if (found) return found.id;
      throw e;
    }
  }

  private async touchClientActivity(
    tx: Prisma.TransactionClient,
    companyId: string,
    clientId: string | null,
    at: Date,
  ) {
    if (!clientId) return;
    await tx.client.updateMany({
      where: { id: clientId, companyId },
      data: { lastActivityAt: at },
    });
  }

  async list(
    user: TenantUser,
    query: { customerPhone?: string; take?: number },
  ) {
    const companyId = requireTenant(user);
    const take = Math.min(Math.max(query.take ?? 80, 1), 500);
    const cacheKey = this.buildQuotesListCacheKey(user, query);
    const cached = await this.redis.get<{ items: any[] }>(cacheKey);
    if (cached) {
      if (this.redis.isEnabled()) this.logger.log(`Redis HIT ${cacheKey}`);
      return cached;
    }
    if (this.redis.isEnabled()) this.logger.log(`Redis MISS ${cacheKey}`);

    const where: Prisma.CotizacionWhereInput = { companyId };

    const customerPhone = query.customerPhone?.trim();
    if (customerPhone) {
      const normalized = normalizePhone(customerPhone);
      where.OR = [
        { customerPhone },
        ...(normalized ? [{ customerPhoneNormalized: normalized }] : []),
      ];
    }

    const items = await this.prisma.cotizacion.findMany({
      where,
      take,
      orderBy: { createdAt: "desc" },
      include: this.buildQuoteInclude(),
    });

    const response = { items };
    await this.redis.set(cacheKey, response);
    return response;
  }

  async findOne(user: TenantUser, id: string) {
    const companyId = requireTenant(user);
    const cacheKey = this.buildQuoteDetailCacheKey(user, id);
    const cached = await this.redis.get<any>(cacheKey);
    if (cached) {
      if (this.redis.isEnabled()) this.logger.log(`Redis HIT ${cacheKey}`);
      return cached;
    }
    if (this.redis.isEnabled()) this.logger.log(`Redis MISS ${cacheKey}`);

    const item = await this.prisma.cotizacion.findFirst({
      where: { id, companyId },
      include: this.buildQuoteInclude(),
    });

    if (!item) throw new NotFoundException("Cotización no encontrada");

    await this.redis.set(cacheKey, item);
    return item;
  }

  async create(user: TenantUser, dto: CreateCotizacionDto) {
    const companyId = requireTenant(user);
    if (!dto.items?.length) {
      throw new BadRequestException("Agrega al menos un producto al ticket");
    }

    const customerPhone = dto.customerPhone.trim();
    const customerName = dto.customerName.trim();
    const note = (dto.note ?? "").trim();

    if (!customerPhone) throw new BadRequestException("Teléfono requerido");
    if (!customerName)
      throw new BadRequestException("Nombre de cliente requerido");

    const customerPhoneNormalized = normalizePhone(customerPhone);

    const includeItbis = dto.includeItbis === true;
    const itbisRateRaw = dto.itbisRate ?? 0.18;
    const itbisRate = new Prisma.Decimal(
      Math.max(0, Math.min(itbisRateRaw, 1)),
    );

    const normalized = await this.normalizeItems(companyId, dto.items);

    let subtotal = new Prisma.Decimal(0);
    let subtotalCost = new Prisma.Decimal(0);
    let hasUnknownCost = false;
    for (const line of normalized) {
      subtotal = subtotal.plus(line.lineTotal);
      if (line.subtotalCost == null) {
        hasUnknownCost = true;
      } else {
        subtotalCost = subtotalCost.plus(line.subtotalCost);
      }
    }

    const itbisAmount = includeItbis
      ? subtotal.mul(itbisRate)
      : new Prisma.Decimal(0);
    const grossTotal = subtotal.plus(itbisAmount);
    const generalDiscountAmountRaw = dto.globalDiscountAmount ?? 0;
    const generalDiscountAmount = new Prisma.Decimal(
      Math.max(
        0,
        Math.min(generalDiscountAmountRaw, this.toNumber(grossTotal)),
      ),
    );
    const total = grossTotal.minus(generalDiscountAmount);
    const totalCost = hasUnknownCost ? null : subtotalCost;
    const totalProfit = hasUnknownCost ? null : total.minus(subtotalCost);

    return this.prisma
      .$transaction(async (tx) => {
        const customerId = await this.resolveCustomerIdByPhone(tx, {
          companyId,
          userId: user.id,
          customerId: dto.customerId,
          customerName,
          customerPhone,
          customerPhoneNormalized,
        });

        const created = await tx.cotizacion.create({
          data: {
            companyId,
            createdByUserId: user.id,
            customerId,
            customerName,
            customerPhone,
            customerPhoneNormalized,
            note: note.length ? note : null,
            includeItbis,
            itbisRate,
            globalDiscountAmount: generalDiscountAmount,
            subtotal,
            subtotalCost: totalCost,
            itbisAmount,
            totalCost,
            total,
            totalProfit,
            items: {
              create: normalized.map((item) => ({
                productId: item.productId,
                productNameSnapshot: item.productNameSnapshot,
                productImageSnapshot: item.productImageSnapshot,
                originalUnitPriceSnapshot: item.originalUnitPriceSnapshot,
                qty: item.qty,
                unitPrice: item.unitPrice,
                costUnitSnapshot: item.costUnitSnapshot,
                subtotalCost: item.subtotalCost,
                lineTotal: item.lineTotal,
                profit: item.profit,
              })),
            },
          },
          include: this.buildQuoteInclude(),
        });

        await this.touchClientActivity(
          tx,
          companyId,
          customerId,
          created.createdAt,
        );

        return created;
      })
      .then(async (created) => {
        await this.invalidateQuoteCache("cotizacion.create");
        return created;
      });
  }

  async update(
    user: TenantUser,
    id: string,
    dto: UpdateCotizacionDto,
  ) {
    const companyId = requireTenant(user);
    const current = await this.prisma.cotizacion.findFirst({ where: { id, companyId } });
    if (!current) throw new NotFoundException("Cotización no encontrada");

    if (!isAdminLike(user) && current.createdByUserId !== user.id) {
      throw new ForbiddenException("No puedes editar esta cotización");
    }

    const includeItbis = dto.includeItbis ?? current.includeItbis;
    const itbisRateRaw = dto.itbisRate ?? this.toNumber(current.itbisRate);
    const itbisRate = new Prisma.Decimal(
      Math.max(0, Math.min(itbisRateRaw, 1)),
    );
    const currentGeneralDiscountAmount = this.toNumber(
      (
        current as {
          globalDiscountAmount?: Prisma.Decimal | number | string | null;
        }
      ).globalDiscountAmount,
    );

    const nextItems = dto.items
      ? await this.normalizeItems(companyId, dto.items as CreateCotizacionItemDto[])
      : null;

    let subtotal = new Prisma.Decimal(current.subtotal);
    let subtotalCost =
      current.subtotalCost == null
        ? null
        : new Prisma.Decimal(current.subtotalCost);
    let itbisAmount = new Prisma.Decimal(current.itbisAmount);
    let totalCost =
      current.totalCost == null ? null : new Prisma.Decimal(current.totalCost);
    let total = new Prisma.Decimal(current.total);
    let totalProfit =
      current.totalProfit == null
        ? null
        : new Prisma.Decimal(current.totalProfit);
    let generalDiscountAmount = new Prisma.Decimal(
      Math.max(0, dto.globalDiscountAmount ?? currentGeneralDiscountAmount),
    );

    if (nextItems) {
      subtotal = new Prisma.Decimal(0);
      subtotalCost = new Prisma.Decimal(0);
      let hasUnknownCost = false;
      for (const line of nextItems) {
        subtotal = subtotal.plus(line.lineTotal);
        if (line.subtotalCost == null) {
          hasUnknownCost = true;
        } else {
          subtotalCost = subtotalCost.plus(line.subtotalCost);
        }
      }
      itbisAmount = includeItbis
        ? subtotal.mul(itbisRate)
        : new Prisma.Decimal(0);
      const grossTotal = subtotal.plus(itbisAmount);
      generalDiscountAmount = new Prisma.Decimal(
        Math.max(
          0,
          Math.min(
            this.toNumber(generalDiscountAmount),
            this.toNumber(grossTotal),
          ),
        ),
      );
      total = grossTotal.minus(generalDiscountAmount);
      totalCost = hasUnknownCost ? null : subtotalCost;
      totalProfit = hasUnknownCost ? null : total.minus(subtotalCost);
    } else if (dto.globalDiscountAmount !== undefined) {
      const grossTotal = subtotal.plus(itbisAmount);
      generalDiscountAmount = new Prisma.Decimal(
        Math.max(
          0,
          Math.min(dto.globalDiscountAmount, this.toNumber(grossTotal)),
        ),
      );
      total = grossTotal.minus(generalDiscountAmount);
      totalProfit = totalCost == null ? null : total.minus(totalCost);
    }

    return this.prisma
      .$transaction(async (tx) => {
        if (nextItems) {
          await tx.cotizacionItem.deleteMany({ where: { cotizacionId: id } });
        }

        const nextCustomerName = dto.customerName
          ? dto.customerName.trim()
          : current.customerName;
        const nextCustomerPhone = dto.customerPhone
          ? dto.customerPhone.trim()
          : current.customerPhone;
        const nextCustomerPhoneNormalized = normalizePhone(nextCustomerPhone);

        const nextCustomerId = dto.customerId
          ? dto.customerId
          : dto.customerPhone
            ? await this.resolveCustomerIdByPhone(tx, {
                companyId,
                userId: user.id,
                customerId: null,
                customerName: nextCustomerName,
                customerPhone: nextCustomerPhone,
                customerPhoneNormalized: nextCustomerPhoneNormalized,
              })
            : current.customerId;

        const updated = await tx.cotizacion.update({
          where: { id },
          data: {
            customerId: nextCustomerId,
            customerName: nextCustomerName,
            customerPhone: nextCustomerPhone,
            customerPhoneNormalized: nextCustomerPhoneNormalized,
            note:
              dto.note !== undefined
                ? dto.note?.trim().length
                  ? dto.note.trim()
                  : null
                : current.note,
            includeItbis,
            itbisRate,
            globalDiscountAmount: generalDiscountAmount,
            subtotal,
            subtotalCost,
            itbisAmount,
            totalCost,
            total,
            totalProfit,
            items: nextItems
              ? {
                  create: nextItems.map((item) => ({
                    productId: item.productId,
                    productNameSnapshot: item.productNameSnapshot,
                    productImageSnapshot: item.productImageSnapshot,
                    originalUnitPriceSnapshot: item.originalUnitPriceSnapshot,
                    qty: item.qty,
                    unitPrice: item.unitPrice,
                    costUnitSnapshot: item.costUnitSnapshot,
                    subtotalCost: item.subtotalCost,
                    lineTotal: item.lineTotal,
                    profit: item.profit,
                  })),
                }
              : undefined,
          },
          include: this.buildQuoteInclude(),
        });

        await this.touchClientActivity(
          tx,
          companyId,
          nextCustomerId ?? null,
          updated.updatedAt,
        );

        return updated;
      })
      .then(async (updated) => {
        await this.invalidateQuoteCache("cotizacion.update");
        return updated;
      });
  }

  async remove(user: TenantUser, id: string) {
    const companyId = requireTenant(user);
    const current = await this.prisma.cotizacion.findFirst({ where: { id, companyId } });
    if (!current) throw new NotFoundException("Cotización no encontrada");

    if (!isAdminLike(user) && current.createdByUserId !== user.id) {
      throw new ForbiddenException("No puedes eliminar esta cotización");
    }

    await this.prisma.cotizacion.deleteMany({ where: { id, companyId } });
    await this.invalidateQuoteCache("cotizacion.remove");
    return { ok: true };
  }

  async createPdfShareLink(
    user: TenantUser,
    dto: CreateCotizacionPdfShareLinkDto,
    requestBaseUrl?: string,
  ) {
    const companyId = requireTenant(user);
    const quotationId = dto.quotationId.trim();
    const quotation = await this.prisma.cotizacion.findFirst({
      where: { id: quotationId, companyId },
      select: {
        id: true,
        createdByUserId: true,
        customerName: true,
      },
    });

    if (!quotation) {
      throw new NotFoundException("Cotización no encontrada.");
    }

    this.ensureQuoteAccessForSend(user, quotation);

    const bytes = this.parsePdfBase64(dto.pdfBase64);
    const fileName = this.sanitizePdfFileName(
      dto.fileName ?? "",
      `cotizacion_${quotationId.slice(0, 8)}.pdf`,
    );
    const uploadDir = this.resolveUploadDir();
    const quoteDir = path.join(uploadDir, "cotizaciones", quotationId);
    await mkdir(quoteDir, { recursive: true });
    await writeFile(path.join(quoteDir, fileName), bytes);

    const relativeUrl = `/cotizaciones/public/pdf/${encodeURIComponent(quotationId)}/${encodeURIComponent(fileName)}`;
    const baseUrl = this.publicBaseUrl(requestBaseUrl);
    if (!baseUrl) {
      throw new BadRequestException(
        "No se pudo construir el enlace público del PDF. Configura PUBLIC_BASE_URL o API_BASE_URL.",
      );
    }

    const pdfUrl = `${baseUrl}${relativeUrl}`;
    this.logger.log(
      `Quote PDF public link created quotationId=${quotationId} userId=${user.id} url=${pdfUrl}`,
    );

    return {
      ok: true,
      quotationId,
      fileName,
      pdfUrl,
      expiresIn: null,
      createdAt: new Date().toISOString(),
    };
  }

  async sendWhatsApp(
    user: TenantUser,
    dto: SendCotizacionWhatsappDto,
  ) {
    const companyId = requireTenant(user);
    const quotationId = dto.quotationId.trim();
    const destinationType = dto.destinationType;
    const customMessage = (dto.messageText ?? "").trim();
    const quotation = await this.prisma.cotizacion.findFirst({
      where: { id: quotationId, companyId },
      select: {
        id: true,
        createdByUserId: true,
        customerId: true,
        customerName: true,
        customerPhone: true,
      },
    });

    if (!quotation) {
      throw new NotFoundException("Cotización no encontrada.");
    }

    this.ensureQuoteAccessForSend(user, quotation);

    const senderInstance = await this.ensureConnectedUserInstance(user.id);

    const destinationPhones =
      destinationType === "admin"
        ? await this.resolveAdminDestinationPhones(companyId)
        : [await this.resolveClientDestination(companyId, quotation)];

    const bytes = this.parsePdfBase64(dto.pdfBase64);
    const fileName = (dto.fileName ?? "").trim() || "cotizacion.pdf";
    const caption =
      customMessage || destinationType === "admin"
        ? ""
        : await this.buildQuoteWhatsAppCaption(quotation.customerName);

    try {
      for (const destinationPhone of destinationPhones) {
        if (customMessage) {
          await this.evolutionWhatsApp.sendTextMessage({
            toNumber: destinationPhone,
            message: customMessage,
            senderUserId: user.id,
            requirePersonalInstance: true,
          });
        }

        await this.evolutionWhatsApp.sendPdfDocument({
          toNumber: destinationPhone,
          bytes,
          fileName,
          caption,
          senderUserId: user.id,
          requirePersonalInstance: true,
        });
      }
    } catch (error) {
      this.logger.error(
        `Quote PDF WhatsApp send failed quotationId=${quotationId} userId=${user.id} destinationType=${destinationType} destinationPhones=${destinationPhones.join(",")} instanceId=${senderInstance.id} instanceName=${senderInstance.instanceName} error=${
          error instanceof Error ? error.message : String(error)
        }`,
      );
      throw this.mapWhatsAppSendError(error);
    }

    this.logger.log(
      `Quote PDF WhatsApp sent quotationId=${quotationId} userId=${user.id} destinationType=${destinationType} destinationPhones=${destinationPhones.join(",")} instanceId=${senderInstance.id} instanceName=${senderInstance.instanceName} success=true`,
    );

    return {
      ok: true,
      destinationType,
      destinationPhones,
      totalDestinations: destinationPhones.length,
      sentAt: new Date().toISOString(),
    };
  }

  async purgeAllForDebug(user: TenantUser) {
    const companyId = requireTenant(user);
    if (!isAdminLike(user)) {
      throw new ForbiddenException(
        "Solo un administrador puede limpiar cotizaciones.",
      );
    }

    const quotes = await this.prisma.cotizacion.findMany({
      where: { companyId },
      select: { id: true },
    });
    const quoteIds = quotes.map((item) => item.id);

    if (quoteIds.length === 0) {
      return { ok: true, deletedQuotes: 0, deletedServiceOrders: 0 };
    }

    const result = await this.prisma.$transaction(async (tx) => {
      const deletedServiceOrders = await tx.serviceOrder.deleteMany({
        where: { quotationId: { in: quoteIds } },
      });
      const deletedQuotes = await tx.cotizacion.deleteMany({
        where: { id: { in: quoteIds }, companyId },
      });
      return {
        deletedQuotes: deletedQuotes.count,
        deletedServiceOrders: deletedServiceOrders.count,
      };
    });

    await this.invalidateQuoteCache("cotizacion.debug_purge");
    await this.redis.delByPattern("service-orders:list:*");
    await this.redis.delByPattern("service-orders:detail:*");

    return { ok: true, ...result };
  }

  async analyzeAssistant(
    user: TenantUser,
    dto: AnalyzeCotizacionAiDto,
  ) {
    const rules = await this.loadRelevantBusinessRules(
      user,
      dto.context,
      dto.instruction,
    );
    this.logDebug("analyze.context", dto.context);
    this.logDebug(
      "analyze.rules",
      rules.map((item) => ({ id: item.id, title: item.title })),
    );

    if (rules.length === 0) {
      return {
        source: "rules-only",
        summary: CotizacionesService.noRuleMessage,
        warnings: [],
        relatedRules: [],
      };
    }

    const runtime = await this.getOpenAiRuntimeConfig();
    if (!runtime.apiKey) {
      return {
        source: "rules-only",
        summary:
          "Se cargaron reglas oficiales relacionadas, pero la IA avanzada no está configurada. Las validaciones locales deben seguir utilizándose.",
        warnings: [],
        relatedRules: rules.map((item) => this.toRuleReference(item)),
      };
    }

    const promptPayload = {
      instruction:
        dto.instruction?.trim() ||
        "Revisa esta cotización con base en las reglas oficiales.",
      context: dto.context,
      rules,
    };

    const parsed = await this.requestStrictJsonFromOpenAi<{
      summary?: unknown;
      warnings?: unknown;
      relatedRuleIds?: unknown;
    }>({
      runtime,
      temperature: 0.1,
      systemPrompt:
        "Eres el asistente interno de FULLTECH dentro del módulo de cotización. Solo puedes responder usando las reglas oficiales proporcionadas por el sistema. No inventes precios, no supongas condiciones, no uses conocimiento externo. Si una respuesta no está definida en las reglas disponibles, debes decir claramente que no encontraste una regla oficial. Tu función es ayudar al vendedor, validar cotizaciones y advertir sobre posibles inconsistencias sin bloquear el flujo de trabajo. Siempre que menciones una regla, intenta devolver el identificador o título de la regla relacionada. Responde únicamente JSON válido.",
      userPrompt: `${JSON.stringify(promptPayload)}\n\nDevuelve exactamente este JSON: {"summary":"string","warnings":[{"title":"string","description":"string","type":"info|warning|success","relatedRuleId":"string|null","relatedRuleTitle":"string|null","suggestedAction":"string|null"}],"relatedRuleIds":["string"]}. Si las reglas no cubren el caso, usa como summary exactamente: "${CotizacionesService.noRuleMessage}" y devuelve warnings vacíos.`,
    });

    const relatedRules = this.pickRelatedRules(rules, parsed.relatedRuleIds);
    const warnings = this.normalizeAiWarnings(parsed.warnings, rules);

    this.logDebug("analyze.warnings", warnings);

    return {
      source: "openai",
      summary:
        this.normalizeOptionalString(parsed.summary) ??
        (warnings.length > 0
          ? "Se detectaron advertencias basadas en las reglas oficiales."
          : "La cotización parece correcta según las reglas actuales."),
      warnings,
      relatedRules,
    };
  }

  async chatAssistant(
    user: TenantUser,
    dto: ChatCotizacionAiDto,
  ) {
    const message = dto.message.trim();
    if (!message) {
      throw new BadRequestException("El mensaje es obligatorio");
    }

    if (this.isUnauthorizedDataRequest(message)) {
      return {
        source: "rules-only",
        content: CotizacionesService.unauthorizedMessage,
        relatedRuleId: null,
        relatedRuleTitle: null,
        citations: [],
      };
    }

    const rules = await this.loadRelevantBusinessRules(
      user,
      dto.context,
      message,
    );
    this.logDebug("chat.context", dto.context);
    this.logDebug(
      "chat.rules",
      rules.map((item) => ({ id: item.id, title: item.title })),
    );

    if (rules.length === 0) {
      return {
        source: "rules-only",
        content: CotizacionesService.noRuleMessage,
        relatedRuleId: null,
        relatedRuleTitle: null,
        citations: [],
      };
    }

    const runtime = await this.getOpenAiRuntimeConfig();
    if (!runtime.apiKey) {
      return this.buildRuleOnlyChatFallback(message, rules);
    }

    const parsed = await this.requestStrictJsonFromOpenAi<{
      content?: unknown;
      relatedRuleId?: unknown;
      relatedRuleTitle?: unknown;
      citations?: unknown;
      unsupported?: unknown;
    }>({
      runtime,
      temperature: 0,
      systemPrompt:
        "Eres el asistente interno de FULLTECH dentro del módulo de cotización. Debes responder usando solamente el conocimiento interno autorizado enviado en la solicitud: Manual Interno, guias de modulos, capacidades operativas del sistema y resúmenes de datos autorizados para el usuario actual. No inventes precios, no uses conocimiento externo, no completes huecos con supuestos, no reveles datos privados de otros usuarios ni datos sensibles no incluidos en el conocimiento enviado. Si una respuesta útil se apoya en conocimiento enviado, debes citar al menos una fuente. Si el usuario pide algo no cubierto por la base de conocimiento enviada, debes decirlo claramente. Si el usuario pregunta por como hacer algo en la app, puedes explicarlo solo con base en guias o capacidades enviadas. Si el usuario pide informacion de otra persona o no autorizada, debes negarte. Responde únicamente JSON válido.",
      userPrompt: `${JSON.stringify({ message, context: dto.context, rules })}\n\nDevuelve exactamente este JSON: {"content":"string","relatedRuleId":"string|null","relatedRuleTitle":"string|null","citations":[{"id":"string","title":"string"}],"unsupported":false}. Reglas estrictas: 1) si respondes algo util, citations no puede ir vacio; 2) relatedRuleId o relatedRuleTitle debe apuntar a una regla enviada; 3) no agregues nada que no pueda leerse o inferirse directamente de las reglas; 4) si la pregunta no esta cubierta, usa exactamente este texto en content: "${CotizacionesService.noRuleMessage}" y usa unsupported=true; 5) si el mensaje es ambiguo o solo social, usa exactamente este texto en content: "${CotizacionesService.rulesOnlyReminder}" y usa unsupported=true.`,
    });

    const relatedRule = rules.find(
      (item) => item.id === this.normalizeOptionalString(parsed.relatedRuleId),
    );
    const citations = this.normalizeCitations(parsed.citations, rules);
    const content =
      this.normalizeOptionalString(parsed.content) ??
      CotizacionesService.noRuleMessage;

    const unsupported = parsed.unsupported === true;
    const relatedRuleIdCandidate =
      relatedRule?.id ?? this.normalizeOptionalString(parsed.relatedRuleId);
    const relatedRuleTitleCandidate =
      relatedRule?.title ??
      this.normalizeOptionalString(parsed.relatedRuleTitle);
    const relatedRuleId = this.isManualKnowledgeId(relatedRuleIdCandidate)
      ? relatedRuleIdCandidate
      : null;
    const relatedRuleTitle = this.isManualKnowledgeId(relatedRuleIdCandidate)
      ? relatedRuleTitleCandidate
      : null;

    if (content === CotizacionesService.rulesOnlyReminder) {
      return {
        source: "rules-only",
        content,
        relatedRuleId: null,
        relatedRuleTitle: null,
        citations: [],
      };
    }

    if (unsupported || content === CotizacionesService.noRuleMessage) {
      return this.buildRuleOnlyChatFallback(message, rules);
    }

    if (citations.length === 0 && !relatedRuleId && !relatedRuleTitle) {
      return this.buildRuleOnlyChatFallback(message, rules);
    }

    return {
      source: "openai",
      content,
      relatedRuleId,
      relatedRuleTitle,
      citations,
    };
  }

  private async normalizeItems(companyId: string, items: CreateCotizacionItemDto[]) {
    const productIds = Array.from(
      new Set(
        items.map((i) => i.productId).filter((id): id is string => Boolean(id)),
      ),
    );

    let products: Array<{
      id: string;
      nombre: string;
      imagen: string | null;
      costo: Prisma.Decimal;
    }> = [];
    if (productIds.length) {
      products = await this.prisma.product.findMany({
        where: { id: { in: productIds }, companyId },
        select: { id: true, nombre: true, imagen: true, costo: true },
      });
    }

    const productMap = new Map(products.map((p) => [p.id, p]));

    return items.map((item, index) => {
      const qty = new Prisma.Decimal(item.qty);
      const unitPrice = new Prisma.Decimal(item.unitPrice);

      if (qty.lte(0))
        throw new BadRequestException(
          `Cantidad inválida en item #${index + 1}`,
        );
      if (unitPrice.lt(0))
        throw new BadRequestException(`Precio inválido en item #${index + 1}`);

      const productId = item.productId ?? null;
      const product = productId ? productMap.get(productId) : null;

      const productNameSnapshot = product?.nombre ?? item.productName?.trim();
      if (!productNameSnapshot) {
        throw new BadRequestException(`Nombre requerido en item #${index + 1}`);
      }

      const productImageSnapshot =
        product?.imagen ?? item.productImageSnapshot ?? null;
      const originalUnitPriceSnapshot = product
        ? new Prisma.Decimal(item.originalUnitPriceSnapshot ?? item.unitPrice)
        : item.originalUnitPriceSnapshot != null
          ? new Prisma.Decimal(item.originalUnitPriceSnapshot)
          : unitPrice;
      const costUnitSnapshot = product
        ? new Prisma.Decimal(product.costo)
        : item.costUnitSnapshot != null
          ? new Prisma.Decimal(item.costUnitSnapshot)
          : null;
      const subtotalCost =
        costUnitSnapshot == null ? null : qty.mul(costUnitSnapshot);
      const lineTotal = qty.mul(unitPrice);
      const profit =
        subtotalCost == null ? null : lineTotal.minus(subtotalCost);

      return {
        productId: product?.id ?? productId,
        productNameSnapshot,
        productImageSnapshot,
        originalUnitPriceSnapshot,
        qty,
        unitPrice,
        costUnitSnapshot,
        subtotalCost,
        lineTotal,
        profit,
      };
    });
  }

  private toNumber(
    value: Prisma.Decimal | number | string | null | undefined,
  ): number {
    if (value === null || value === undefined) return 0;
    if (typeof value === "number") return value;
    return Number(value);
  }

  private async resolveCompanyOwnerId(fallbackUserId: string) {
    const admin = await this.prisma.user.findFirst({
      where: { role: Role.ADMIN },
      orderBy: { createdAt: "asc" },
      select: { id: true },
    });
    return admin?.id ?? fallbackUserId;
  }

  private async getOpenAiRuntimeConfig(): Promise<AiRuntimeConfig> {
    const envKey = (
      this.config.get<string>("OPENAI_API_KEY") ??
      process.env.OPENAI_API_KEY ??
      ""
    ).trim();
    const envModel = (
      this.config.get<string>("OPENAI_MODEL") ??
      process.env.OPENAI_MODEL ??
      ""
    ).trim();

    let appConfig: {
      openAiApiKey: string | null;
      openAiModel: string | null;
      companyName: string | null;
    } | null = null;

    try {
      appConfig = await this.prisma.appConfig.findUnique({
        where: { id: "global" },
        select: { openAiApiKey: true, openAiModel: true, companyName: true },
      });
    } catch {
      appConfig = null;
    }

    return {
      apiKey:
        envKey.length > 0 ? envKey : (appConfig?.openAiApiKey ?? "").trim(),
      model:
        envModel.length > 0
          ? envModel
          : (appConfig?.openAiModel ?? "").trim() || "gpt-4o-mini",
      companyName: (appConfig?.companyName ?? "FULLTECH").trim() || "FULLTECH",
    };
  }

  private getOpenAiModelCandidates(preferredModel: string) {
    const autoCandidatesEnv = (
      process.env.OPENAI_MODEL_CANDIDATES ?? ""
    ).trim();
    const autoCandidates =
      autoCandidatesEnv.length > 0
        ? autoCandidatesEnv
            .split(",")
            .map((item) => item.trim())
            .filter((item) => item.length > 0)
        : ["gpt-5", "gpt-4.1", "gpt-4o", "gpt-4o-mini"];

    return [preferredModel, ...autoCandidates].filter(
      (value, index, list) => value.length > 0 && list.indexOf(value) === index,
    );
  }

  private extractJsonObject(raw: string) {
    const trimmed = raw.trim();
    const fenced = trimmed.startsWith("```")
      ? trimmed
          .replace(/^```(?:json)?\s*/i, "")
          .replace(/```$/i, "")
          .trim()
      : trimmed;
    const firstBrace = fenced.indexOf("{");
    const lastBrace = fenced.lastIndexOf("}");
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      return fenced.slice(firstBrace, lastBrace + 1);
    }
    return fenced;
  }

  private async requestStrictJsonFromOpenAi<T>({
    runtime,
    systemPrompt,
    userPrompt,
    temperature,
  }: {
    runtime: AiRuntimeConfig;
    systemPrompt: string;
    userPrompt: string;
    temperature: number;
  }): Promise<T> {
    const modelCandidates = this.getOpenAiModelCandidates(runtime.model);

    for (const candidate of modelCandidates) {
      try {
        const response = await fetch(
          "https://api.openai.com/v1/chat/completions",
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${runtime.apiKey}`,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              model: candidate,
              temperature,
              messages: [
                { role: "system", content: systemPrompt },
                { role: "user", content: userPrompt },
              ],
            }),
          },
        );

        if (!response.ok) {
          this.logDebug("openai.http_error", {
            candidate,
            status: response.status,
          });
          continue;
        }

        const payload = (await response.json()) as {
          choices?: Array<{ message?: { content?: string } }>;
        };
        const content = payload.choices?.[0]?.message?.content?.trim();
        if (!content) continue;

        return JSON.parse(this.extractJsonObject(content)) as T;
      } catch (error) {
        this.logDebug("openai.parse_error", {
          candidate,
          message: error instanceof Error ? error.message : `${error}`,
        });
      }
    }

    throw new BadRequestException(
      "No se pudo generar una respuesta válida desde OpenAI para cotizaciones.",
    );
  }

  private async loadRelevantBusinessRules(
    user: TenantUser,
    context: AnalyzeCotizacionAiDto["context"],
    prompt?: string,
  ) {
    const ownerId = await this.resolveCompanyOwnerId(user.id);
    const where: Prisma.CompanyManualEntryWhereInput = {
      ownerId,
      published: true,
      kind: {
        in: [
          CompanyManualEntryKind.GENERAL_RULE,
          CompanyManualEntryKind.ROLE_RULE,
          CompanyManualEntryKind.POLICY,
          CompanyManualEntryKind.WARRANTY_POLICY,
          CompanyManualEntryKind.RESPONSIBILITY,
          CompanyManualEntryKind.PRICE_RULE,
          CompanyManualEntryKind.SERVICE_RULE,
          CompanyManualEntryKind.PRODUCT_SERVICE,
          CompanyManualEntryKind.MODULE_GUIDE,
        ],
      },
      OR: [
        { audience: CompanyManualAudience.GENERAL },
        {
          audience: CompanyManualAudience.ROLE_SPECIFIC,
          targetRoles: { has: user.role as Role },
        },
      ],
    };

    const entries = await this.prisma.companyManualEntry.findMany({
      where,
      orderBy: [{ sortOrder: "asc" }, { updatedAt: "desc" }, { title: "asc" }],
    });

    const staticKnowledge = this.buildStaticAppKnowledge();
    const authorizedKnowledge = await this.buildAuthorizedDataKnowledge(
      user,
      prompt ?? "",
      context,
    );
    const knowledgeEntries = [
      ...entries.map((entry) => this.toBusinessRuleRecord(entry)),
      ...staticKnowledge,
      ...authorizedKnowledge,
    ];

    const desiredModuleKeys = new Set(
      [
        (context.module ?? "").trim().toLowerCase(),
        "cotizaciones",
        "cotizacion",
        "ventas",
        "manual-interno",
      ].filter((item) => item.length > 0),
    );

    const queryText = [
      prompt,
      context.productType,
      context.productName,
      context.brand,
      context.installationType,
      context.currentDvrType,
      context.requiredDvrType,
      context.notes,
      ...(context.components ?? []),
      ...(context.extraCharges ?? []),
      ...(context.items ?? []).flatMap((item) => [
        item.productName,
        item.category,
        item.notes,
      ]),
    ]
      .filter(
        (item): item is string =>
          typeof item === "string" && item.trim().length > 0,
      )
      .join(" ")
      .toLowerCase();

    const queryTokens = this.tokenize(queryText);

    const scored = knowledgeEntries
      .map((entry) => {
        const moduleKey = (entry.module ?? "").trim().toLowerCase();
        const text = [
          entry.title,
          entry.summary ?? "",
          entry.content,
          moduleKey,
        ]
          .join(" ")
          .toLowerCase();
        const textTokens = new Set(this.tokenize(text));

        let score = 0;
        if (!moduleKey) score += 10;
        if (desiredModuleKeys.has(moduleKey)) score += 6;
        if (moduleKey === "cotizaciones" || moduleKey === "cotizacion")
          score += 4;
        if (
          text.includes("precio") ||
          text.includes("mínimo") ||
          text.includes("minimo")
        )
          score += 2;
        if (text.includes("garant")) score += 2;
        if (
          text.includes("dvr") ||
          text.includes("nvr") ||
          text.includes("xvr")
        )
          score += 3;
        if (text.includes("cámara") || text.includes("camara")) score += 3;
        if (text.includes("instal")) score += 2;
        for (const token of queryTokens) {
          if (textTokens.has(token)) score += token.length >= 5 ? 2 : 1;
        }

        return { entry, score };
      })
      .filter((item) => item.score > 0)
      .sort((left, right) => right.score - left.score)
      .slice(0, 12)
      .map(({ entry }) => entry);

    if (scored.length > 0) {
      return scored;
    }

    return knowledgeEntries.slice(0, 12);
  }

  private buildStaticAppKnowledge(): BusinessRuleRecord[] {
    return [
      this.createAppKnowledgeRecord(
        "app-knowledge:cotizaciones",
        "cotizaciones",
        "guia-app",
        "Uso del modulo de cotizaciones",
        "En cotizaciones puedes buscar productos del catalogo, filtrar por categoria, agregar articulos al ticket, ajustar precios, activar ITBIS, seleccionar cliente, escribir observaciones y finalizar o guardar la cotizacion.",
      ),
      this.createAppKnowledgeRecord(
        "app-knowledge:ventas",
        "ventas",
        "guia-app",
        "Uso del modulo de ventas",
        "En ventas puedes registrar ventas, consultar resúmenes, revisar historiales y trabajar con clientes autorizados dentro de tu alcance.",
      ),
      this.createAppKnowledgeRecord(
        "app-knowledge:clientes",
        "clientes",
        "guia-app",
        "Uso del modulo de clientes",
        "El modulo de clientes permite buscar, crear y consultar clientes. Los usuarios no administradores solo deben trabajar con informacion permitida por su alcance dentro del sistema.",
      ),
      this.createAppKnowledgeRecord(
        "app-knowledge:manual-interno",
        "manual-interno",
        "guia-app",
        "Base de conocimiento del asistente",
        "La base principal del asistente es el Manual Interno de la empresa, complementada por guias funcionales de modulos y resúmenes autorizados del sistema para el usuario actual.",
      ),
      this.createAppKnowledgeRecord(
        "app-knowledge:seguridad",
        "seguridad",
        "politica-app",
        "Politica de autorizacion del asistente",
        "El asistente no debe revelar informacion privada de otros usuarios, credenciales, telefonos, cedulas, salarios ni datos no autorizados. Si el usuario pide algo fuera de su alcance, el asistente debe negarse.",
      ),
    ];
  }

  private async buildAuthorizedDataKnowledge(
    user: TenantUser,
    prompt: string,
    context: AnalyzeCotizacionAiDto["context"],
  ): Promise<BusinessRuleRecord[]> {
    const companyId = requireTenant(user);
    const tokens = new Set(
      this.tokenize(
        [prompt, context.module, context.screenName].filter(Boolean).join(" "),
      ),
    );
    const includeAll = tokens.size === 0;
    const wantsSales =
      includeAll || this.hasAnyToken(tokens, ["venta", "ventas", "comision"]);
    const wantsClients =
      includeAll || this.hasAnyToken(tokens, ["cliente", "clientes"]);
    const wantsQuotes =
      includeAll ||
      this.hasAnyToken(tokens, ["cotizacion", "cotizaciones", "ticket"]);

    const knowledge: BusinessRuleRecord[] = [];

    if (wantsSales) {
      const totalSales = await this.prisma.sale.count({
        where:
          user.role === Role.ADMIN
            ? { companyId, isDeleted: false }
            : { companyId, userId: user.id, isDeleted: false },
      });
      knowledge.push(
        this.createAppKnowledgeRecord(
          "app-data:sales-summary",
          "ventas",
          "dato-autorizado",
          "Resumen autorizado de ventas",
          user.role === Role.ADMIN
            ? `Actualmente hay ${totalSales} ventas activas registradas en el sistema.`
            : `Actualmente tienes ${totalSales} ventas activas registradas bajo tu usuario.`,
        ),
      );
    }

    if (wantsClients) {
      const totalClients = await this.prisma.client.count({
        where:
          user.role === Role.ADMIN
            ? { companyId, isDeleted: false }
            : { companyId, ownerId: user.id, isDeleted: false },
      });
      knowledge.push(
        this.createAppKnowledgeRecord(
          "app-data:clients-summary",
          "clientes",
          "dato-autorizado",
          "Resumen autorizado de clientes",
          user.role === Role.ADMIN
            ? `Actualmente hay ${totalClients} clientes activos registrados en el sistema.`
            : `Actualmente tienes ${totalClients} clientes activos registrados bajo tu gestion.`,
        ),
      );
    }

    if (wantsQuotes) {
      const totalQuotes = await this.prisma.cotizacion.count({
        where:
          user.role === Role.ADMIN
            ? { companyId }
            : { companyId, createdByUserId: user.id },
      });
      knowledge.push(
        this.createAppKnowledgeRecord(
          "app-data:quotes-summary",
          "cotizaciones",
          "dato-autorizado",
          "Resumen autorizado de cotizaciones",
          user.role === Role.ADMIN
            ? `Actualmente hay ${totalQuotes} cotizaciones registradas en el sistema.`
            : `Actualmente tienes ${totalQuotes} cotizaciones registradas bajo tu usuario.`,
        ),
      );
    }

    return knowledge;
  }

  private createAppKnowledgeRecord(
    id: string,
    module: string,
    category: string,
    title: string,
    content: string,
  ): BusinessRuleRecord {
    return {
      id,
      module,
      category,
      title,
      content,
      summary: content,
      keywords: this.tokenize(
        `${title} ${content} ${module} ${category}`,
      ).slice(0, 18),
      severity: "info",
      active: true,
      createdAt: null,
      updatedAt: null,
    };
  }

  private hasAnyToken(tokens: Set<string>, candidates: string[]) {
    for (const candidate of candidates) {
      if (tokens.has(candidate)) {
        return true;
      }
    }
    return false;
  }

  private isUnauthorizedDataRequest(message: string) {
    const text = message.trim().toLowerCase();
    if (!text) return false;
    const asksSensitiveData = [
      "password",
      "contrasena",
      "contraseña",
      "cedula",
      "telefono",
      "correo",
      "email",
      "salario",
      "nomina",
      "ubicacion",
      "location",
    ].some((token) => text.includes(token));
    const asksAboutOtherPerson = [
      "otro usuario",
      "otro vendedor",
      "otro tecnico",
      "otro empleado",
      "de otro usuario",
      "de otro vendedor",
      "de otro tecnico",
      "de otro empleado",
    ].some((token) => text.includes(token));
    return asksSensitiveData && asksAboutOtherPerson;
  }

  private isManualKnowledgeId(id?: string | null) {
    const normalized = (id ?? "").trim().toLowerCase();
    if (!normalized) return false;
    return (
      !normalized.startsWith("app-knowledge:") &&
      !normalized.startsWith("app-data:")
    );
  }

  private toBusinessRuleRecord(entry: {
    id: string;
    title: string;
    summary: string | null;
    content: string;
    moduleKey: string | null;
    kind: CompanyManualEntryKind;
    published: boolean;
    createdAt: Date;
    updatedAt: Date;
  }): BusinessRuleRecord {
    return {
      id: entry.id,
      module: (entry.moduleKey ?? "general").trim().toLowerCase() || "general",
      category: this.mapRuleCategory(entry.kind),
      title: entry.title,
      content: entry.content,
      summary: entry.summary,
      keywords: this.tokenize(
        [entry.title, entry.summary ?? "", entry.content].join(" "),
      ).slice(0, 18),
      severity: this.inferSeverity(entry.kind, entry.title, entry.content),
      active: entry.published,
      createdAt: entry.createdAt?.toISOString() ?? null,
      updatedAt: entry.updatedAt?.toISOString() ?? null,
    };
  }

  private mapRuleCategory(kind: CompanyManualEntryKind) {
    switch (kind) {
      case CompanyManualEntryKind.PRICE_RULE:
        return "precios";
      case CompanyManualEntryKind.WARRANTY_POLICY:
        return "garantias";
      case CompanyManualEntryKind.SERVICE_RULE:
        return "servicios";
      case CompanyManualEntryKind.PRODUCT_SERVICE:
        return "productos";
      case CompanyManualEntryKind.MODULE_GUIDE:
        return "modulo";
      case CompanyManualEntryKind.POLICY:
        return "politicas";
      case CompanyManualEntryKind.GENERAL_RULE:
      case CompanyManualEntryKind.ROLE_RULE:
      case CompanyManualEntryKind.RESPONSIBILITY:
      default:
        return "general";
    }
  }

  private inferSeverity(
    kind: CompanyManualEntryKind,
    title: string,
    content: string,
  ): "info" | "warning" | "critical" {
    const text = `${title} ${content}`.toLowerCase();
    if (
      text.includes("prohib") ||
      text.includes("no permitido") ||
      text.includes("obligatorio")
    ) {
      return "critical";
    }
    if (
      kind === CompanyManualEntryKind.PRICE_RULE ||
      kind === CompanyManualEntryKind.WARRANTY_POLICY ||
      text.includes("mínimo") ||
      text.includes("minimo")
    ) {
      return "warning";
    }
    return "info";
  }

  private tokenize(value: string) {
    return value
      .toLowerCase()
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .split(/[^a-z0-9]+/)
      .map((item) => item.trim())
      .filter((item) => item.length >= 3);
  }

  private normalizeOptionalString(value: unknown) {
    if (typeof value !== "string") return null;
    const trimmed = value.trim();
    return trimmed.length > 0 ? trimmed : null;
  }

  private pickRelatedRules(rules: BusinessRuleRecord[], rawIds: unknown) {
    const ids = Array.isArray(rawIds)
      ? rawIds
          .map((item) => this.normalizeOptionalString(item))
          .filter((item): item is string => !!item)
      : [];
    return rules
      .filter((item) => ids.includes(item.id))
      .map((item) => this.toRuleReference(item));
  }

  private normalizeAiWarnings(
    rawWarnings: unknown,
    rules: BusinessRuleRecord[],
  ) {
    if (!Array.isArray(rawWarnings)) return [];
    return rawWarnings
      .map((item) => {
        if (typeof item !== "object" || item === null || Array.isArray(item))
          return null;
        const row = item as Record<string, unknown>;
        const ruleId = this.normalizeOptionalString(row.relatedRuleId);
        const relatedRule = rules.find((rule) => rule.id === ruleId);
        const typeRaw = this.normalizeOptionalString(row.type) ?? "info";
        const type =
          typeRaw === "warning" || typeRaw === "success" ? typeRaw : "info";
        const title = this.normalizeOptionalString(row.title);
        const description = this.normalizeOptionalString(row.description);
        if (!title || !description) return null;
        return {
          title,
          description,
          type,
          relatedRuleId: relatedRule?.id ?? ruleId,
          relatedRuleTitle:
            relatedRule?.title ??
            this.normalizeOptionalString(row.relatedRuleTitle),
          suggestedAction: this.normalizeOptionalString(row.suggestedAction),
        };
      })
      .filter((item): item is NonNullable<typeof item> => !!item);
  }

  private normalizeCitations(
    rawCitations: unknown,
    rules: BusinessRuleRecord[],
  ) {
    if (!Array.isArray(rawCitations)) return [];
    return rawCitations
      .map((item) => {
        if (typeof item !== "object" || item === null || Array.isArray(item))
          return null;
        const row = item as Record<string, unknown>;
        const id = this.normalizeOptionalString(row.id);
        const rule = rules.find((entry) => entry.id === id);
        const title = rule?.title ?? this.normalizeOptionalString(row.title);
        if (!title) return null;
        return {
          id: rule?.id ?? id,
          title,
        };
      })
      .filter((item): item is NonNullable<typeof item> => !!item);
  }

  private toRuleReference(rule: BusinessRuleRecord) {
    return {
      id: rule.id,
      module: rule.module,
      category: rule.category,
      title: rule.title,
    };
  }

  private buildRuleOnlyChatFallback(
    message: string,
    rules: BusinessRuleRecord[],
  ) {
    const normalizedMessage = message.trim().toLowerCase();
    const hasMeaningfulQuestion = this.tokenize(normalizedMessage).length > 0;
    const matchedRules = hasMeaningfulQuestion
      ? this.rankRulesForPrompt(message, rules).slice(0, 2)
      : [];
    const topRule = matchedRules[0] ?? rules[0];
    if (!topRule) {
      return {
        source: "rules-only",
        content: CotizacionesService.noRuleMessage,
        relatedRuleId: null,
        relatedRuleTitle: null,
        citations: [],
      };
    }

    const selectedRules = matchedRules.length > 0 ? matchedRules : [topRule];
    const citations = selectedRules.map((rule) => this.toRuleReference(rule));
    const summaryParts = selectedRules
      .map((rule, index) => {
        const excerpt = this.buildExcerpt(
          rule.summary?.trim().length ? rule.summary : rule.content,
        );
        const prefix =
          index == 0
            ? `Segun la regla oficial "${rule.title}"`
            : `Tambien aplica "${rule.title}"`;
        return excerpt.length > 0 ? `${prefix}: ${excerpt}` : prefix;
      })
      .filter((item) => item.trim().length > 0);

    const content =
      summaryParts.length > 0
        ? summaryParts.join(" ")
        : `Solo puedo responder con base en reglas oficiales. La regla mas cercana es "${topRule.title}".`;

    return {
      source: "rules-only",
      content,
      relatedRuleId: this.isManualKnowledgeId(topRule.id) ? topRule.id : null,
      relatedRuleTitle: this.isManualKnowledgeId(topRule.id)
        ? topRule.title
        : null,
      citations,
    };
  }

  private rankRulesForPrompt(message: string, rules: BusinessRuleRecord[]) {
    const tokens = new Set(this.tokenize(message));

    return rules
      .map((rule) => {
        const ruleTokens = new Set(
          this.tokenize(
            [
              rule.title,
              rule.summary ?? "",
              rule.content,
              rule.module,
              rule.category,
            ].join(" "),
          ),
        );
        let score = 0;
        for (const token of tokens) {
          if (ruleTokens.has(token)) {
            score += token.length >= 5 ? 2 : 1;
          }
        }
        if (rule.severity === "critical" || rule.severity === "warning") {
          score += 1;
        }
        return { rule, score };
      })
      .filter((item) => item.score > 0)
      .sort((left, right) => right.score - left.score)
      .map((item) => item.rule);
  }

  private buildExcerpt(content: string) {
    const normalized = content.replace(/\s+/g, " ").trim();
    if (normalized.length <= 220) return normalized;
    return `${normalized.slice(0, 217).trim()}...`;
  }

  private logDebug(label: string, payload: unknown) {
    if (process.env.NODE_ENV === "production" && process.env.AI_DEBUG !== "1") {
      return;
    }
    this.logger.debug(`${label}: ${JSON.stringify(payload)}`);
  }
}
