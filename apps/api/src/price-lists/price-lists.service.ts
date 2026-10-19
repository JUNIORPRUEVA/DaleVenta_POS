import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { PriceListRuleMode, Prisma, Role } from "@prisma/client";
import { requireTenant, type TenantUser } from "../auth/tenant-context";
import { PrismaService } from "../prisma/prisma.service";
import {
  AssignClientPriceListDto,
  CreatePriceListDto,
  ResolvePriceListLineDto,
  UpdatePriceListDto,
  UpsertPriceListRuleDto,
} from "./dto/price-list.dto";
import { PricingEngineService } from "./pricing-engine.service";

@Injectable()
export class PriceListsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly pricing: PricingEngineService,
  ) {}

  async list(user: TenantUser) {
    const companyId = requireTenant(user);
    return this.prisma.priceList.findMany({
      where: { companyId },
      orderBy: [{ active: "desc" }, { priority: "desc" }, { name: "asc" }],
      include: {
        _count: { select: { productRules: true, clients: true } },
        productRules: {
          where: { active: true },
          orderBy: [{ product: { nombre: "asc" } }, { minQuantity: "asc" }],
          include: {
            product: { select: { id: true, nombre: true, precio: true } },
            tiers: { orderBy: { minQuantity: "asc" } },
          },
        },
      },
    });
  }

  async findOne(user: TenantUser, id: string) {
    const companyId = requireTenant(user);
    await this.findPriceListOrThrow(companyId, id);
    return this.prisma.priceList.findFirst({
      where: { id, companyId },
      include: {
        productRules: {
          orderBy: [{ product: { nombre: "asc" } }, { minQuantity: "asc" }],
          include: {
            product: { select: { id: true, nombre: true, precio: true } },
            tiers: { orderBy: { minQuantity: "asc" } },
          },
        },
        _count: { select: { clients: true } },
      },
    });
  }

  async create(user: TenantUser, dto: CreatePriceListDto) {
    this.requireAdminLike(user);
    const companyId = requireTenant(user);
    const name = this.requiredName(dto.name);
    return this.prisma.priceList.create({
      data: {
        companyId,
        name,
        description: this.nullableText(dto.description),
        active: dto.active ?? true,
        priority: dto.priority ?? 0,
      },
    });
  }

  async update(user: TenantUser, id: string, dto: UpdatePriceListDto) {
    this.requireAdminLike(user);
    const companyId = requireTenant(user);
    await this.findPriceListOrThrow(companyId, id);
    return this.prisma.priceList.update({
      where: { id },
      data: {
        ...(dto.name !== undefined ? { name: this.requiredName(dto.name) } : {}),
        ...(dto.description !== undefined
          ? { description: this.nullableText(dto.description) }
          : {}),
        ...(dto.active !== undefined ? { active: dto.active } : {}),
        ...(dto.priority !== undefined ? { priority: dto.priority } : {}),
      },
    });
  }

  async upsertRule(
    user: TenantUser,
    priceListId: string,
    dto: UpsertPriceListRuleDto,
  ) {
    this.requireAdminLike(user);
    const companyId = requireTenant(user);
    await this.findPriceListOrThrow(companyId, priceListId);
    await this.findProductOrThrow(companyId, dto.productId);
    this.assertRulePayload(dto.mode as PriceListRuleMode, dto);

    const minQuantity = new Prisma.Decimal(dto.minQuantity ?? 1);
    const existing = await this.prisma.priceListProductRule.findUnique({
      where: {
        priceListId_productId_minQuantity: {
          priceListId,
          productId: dto.productId,
          minQuantity,
        },
      },
      select: { id: true },
    });
    const data = {
      companyId,
      priceListId,
      productId: dto.productId,
      mode: dto.mode as PriceListRuleMode,
      fixedPrice:
        dto.fixedPrice == null ? null : new Prisma.Decimal(dto.fixedPrice),
      discountPercent:
        dto.discountPercent == null
          ? null
          : new Prisma.Decimal(dto.discountPercent),
      minQuantity,
      active: dto.active ?? true,
    };
    const rule = existing
      ? await this.prisma.priceListProductRule.update({
          where: { id: existing.id },
          data,
        })
      : await this.prisma.priceListProductRule.create({ data });

    if (dto.tiers) {
      await this.replaceTiers(companyId, rule.id, dto);
    }
    return this.prisma.priceListProductRule.findUnique({
      where: { id: rule.id },
      include: { tiers: { orderBy: { minQuantity: "asc" } } },
    });
  }

  async assignClient(
    user: TenantUser,
    clientId: string,
    dto: AssignClientPriceListDto,
  ) {
    this.requireAdminLike(user);
    const companyId = requireTenant(user);
    await this.findClientOrThrow(companyId, clientId);
    const priceListId = dto.priceListId?.trim() || null;
    if (priceListId) {
      await this.findPriceListOrThrow(companyId, priceListId);
    }
    return this.prisma.client.update({
      where: { id: clientId },
      data: { defaultPriceListId: priceListId },
      select: {
        id: true,
        nombre: true,
        defaultPriceListId: true,
        defaultPriceList: { select: { id: true, name: true, active: true } },
      },
    });
  }

  async resolveLine(user: TenantUser, dto: ResolvePriceListLineDto) {
    const companyId = requireTenant(user);
    const company = await this.prisma.company.findUnique({
      where: { id: companyId },
      select: { wholesalePriceListsEnabled: true },
    });
    const product = await this.findProductOrThrow(companyId, dto.productId);
    const selectedPriceListId = await this.resolveSelectedPriceListId(
      companyId,
      dto,
    );
    if (!selectedPriceListId) {
      return this.toPublicResolution(
        this.pricing.resolveLine({
          moduleEnabled: company?.wholesalePriceListsEnabled === true,
          baseUnitPrice: product.precio,
          quantity: dto.qty,
          rule: null,
        }),
      );
    }

    const priceList = await this.prisma.priceList.findFirst({
      where: { id: selectedPriceListId, companyId, active: true },
      select: { id: true, name: true },
    });
    if (!priceList) {
      throw new BadRequestException("Lista de precios inválida o inactiva");
    }
    const rule = await this.prisma.priceListProductRule.findFirst({
      where: {
        companyId,
        priceListId: selectedPriceListId,
        productId: product.id,
        active: true,
        minQuantity: { lte: new Prisma.Decimal(dto.qty) },
      },
      orderBy: { minQuantity: "desc" },
      include: { tiers: { orderBy: { minQuantity: "asc" } } },
    });
    return this.toPublicResolution(
      this.pricing.resolveLine({
        moduleEnabled: company?.wholesalePriceListsEnabled === true,
        baseUnitPrice: product.precio,
        quantity: dto.qty,
        rule: rule
          ? {
              id: rule.id,
              priceListId: priceList.id,
              priceListName: priceList.name,
              mode: rule.mode,
              fixedPrice: rule.fixedPrice,
              discountPercent: rule.discountPercent,
              minQuantity: rule.minQuantity,
              tiers: rule.tiers,
            }
          : null,
      }),
    );
  }

  async resolveDocumentPricing(input: {
    companyId: string;
    user: TenantUser;
    customerId?: string | null;
    requestedPriceListId?: string | null;
    requestedPriceListManualOverride?: boolean;
    lines: Array<{
      index: number;
      productId?: string | null;
      quantity: Prisma.Decimal | number | string;
      unitPrice: Prisma.Decimal | number | string;
      appliedPriceListId?: string | null;
      appliedPricingRuleId?: string | null;
    }>;
  }) {
    const company = await this.prisma.company.findUnique({
      where: { id: input.companyId },
      select: { wholesalePriceListsEnabled: true },
    });
    const moduleEnabled = company?.wholesalePriceListsEnabled === true;
    const hasWholesalePayload =
      Boolean(input.requestedPriceListId) ||
      input.requestedPriceListManualOverride === true ||
      input.lines.some(
        (line) => line.appliedPriceListId || line.appliedPricingRuleId,
      );
    if (!moduleEnabled) {
      if (hasWholesalePayload) {
        throw new BadRequestException(
          "Mayoreo no está activo para esta empresa.",
        );
      }
      return {
        moduleEnabled,
        priceListId: null,
        priceListName: null,
        manualOverride: false,
        lines: new Map<number, DocumentPricingLine>(),
      };
    }

    const selected = await this.resolveDocumentPriceList(input);
    if (!selected) {
      if (hasWholesalePayload) {
        throw new BadRequestException(
          "No hay una lista de precios válida para el documento.",
        );
      }
      return {
        moduleEnabled,
        priceListId: null,
        priceListName: null,
        manualOverride: false,
        lines: new Map<number, DocumentPricingLine>(),
      };
    }

    const productIds = Array.from(
      new Set(
        input.lines
          .map((line) => line.productId?.trim())
          .filter((id): id is string => Boolean(id)),
      ),
    );
    const [products, rules] = await Promise.all([
      this.prisma.product.findMany({
        where: { companyId: input.companyId, id: { in: productIds } },
        select: { id: true, precio: true },
      }),
      this.prisma.priceListProductRule.findMany({
        where: {
          companyId: input.companyId,
          priceListId: selected.id,
          productId: { in: productIds },
          active: true,
        },
        include: { tiers: { orderBy: { minQuantity: "asc" } } },
      }),
    ]);
    const productMap = new Map(products.map((product) => [product.id, product]));
    const rulesByProduct = new Map<string, typeof rules>();
    for (const rule of rules) {
      const bucket = rulesByProduct.get(rule.productId) ?? [];
      bucket.push(rule);
      rulesByProduct.set(rule.productId, bucket);
    }

    const resolved = new Map<number, DocumentPricingLine>();
    for (const line of input.lines) {
      const productId = line.productId?.trim();
      if (!productId) continue;
      const product = productMap.get(productId);
      if (!product) {
        throw new BadRequestException(
          `Producto inválido en item #${line.index + 1}`,
        );
      }
      const rule = this.bestRuleForQuantity(
        rulesByProduct.get(productId) ?? [],
        new Prisma.Decimal(line.quantity),
      );
      const result = this.pricing.resolveLine({
        moduleEnabled: true,
        baseUnitPrice: product.precio,
        quantity: line.quantity,
        rule: rule
          ? {
              id: rule.id,
              priceListId: selected.id,
              priceListName: selected.name,
              mode: rule.mode,
              fixedPrice: rule.fixedPrice,
              discountPercent: rule.discountPercent,
              minQuantity: rule.minQuantity,
              tiers: rule.tiers,
            }
          : null,
      });
      if (!result.applied) {
        if (line.appliedPriceListId || line.appliedPricingRuleId) {
          throw new BadRequestException(
            `El item #${line.index + 1} no tiene una regla mayorista aplicable.`,
          );
        }
        continue;
      }
      const submitted = new Prisma.Decimal(line.unitPrice).toDecimalPlaces(2);
      if (submitted.minus(result.unitPrice).abs().gt("0.009")) {
        throw new BadRequestException(
          `El precio del item #${line.index + 1} no coincide con la lista aplicada.`,
        );
      }
      resolved.set(line.index, {
        priceListId: selected.id,
        priceListName: selected.name,
        ruleId: result.ruleId,
        ruleMode: result.ruleMode,
        unitPrice: result.unitPrice,
        originalUnitPrice: result.originalUnitPrice,
        snapshot: {
          priceListId: selected.id,
          priceListName: selected.name,
          ruleId: result.ruleId,
          ruleMode: result.ruleMode,
          minQuantity: result.minQuantity?.toString() ?? null,
          discountPercent: result.discountPercent?.toString() ?? null,
        },
      });
    }

    return {
      moduleEnabled,
      priceListId: selected.id,
      priceListName: selected.name,
      manualOverride: selected.manualOverride,
      lines: resolved,
    };
  }

  private async replaceTiers(
    companyId: string,
    ruleId: string,
    dto: UpsertPriceListRuleDto,
  ) {
    await this.prisma.$transaction(async (tx) => {
      await tx.priceListQuantityTier.deleteMany({ where: { ruleId, companyId } });
      if (!dto.tiers?.length) return;
      await tx.priceListQuantityTier.createMany({
        data: dto.tiers.map((tier) => {
          const mode = (tier.mode ?? dto.mode) as PriceListRuleMode;
          this.assertRulePayload(mode, {
            ...dto,
            fixedPrice: tier.fixedPrice ?? dto.fixedPrice,
            discountPercent: tier.discountPercent ?? dto.discountPercent,
          });
          return {
            companyId,
            ruleId,
            minQuantity: new Prisma.Decimal(tier.minQuantity),
            mode,
            fixedPrice:
              tier.fixedPrice == null ? null : new Prisma.Decimal(tier.fixedPrice),
            discountPercent:
              tier.discountPercent == null
                ? null
                : new Prisma.Decimal(tier.discountPercent),
          };
        }),
      });
    });
  }

  private async resolveSelectedPriceListId(
    companyId: string,
    dto: ResolvePriceListLineDto,
  ) {
    if (dto.priceListId) return dto.priceListId;
    if (!dto.clientId) return null;
    const client = await this.prisma.client.findFirst({
      where: { id: dto.clientId, companyId, isDeleted: false },
      select: { defaultPriceListId: true },
    });
    if (!client) {
      throw new BadRequestException("Cliente inválido para esta empresa");
    }
    return client.defaultPriceListId;
  }

  private async resolveDocumentPriceList(input: {
    companyId: string;
    user: TenantUser;
    customerId?: string | null;
    requestedPriceListId?: string | null;
    requestedPriceListManualOverride?: boolean;
  }) {
    const requestedPriceListId = input.requestedPriceListId?.trim() || null;
    let clientDefaultPriceListId: string | null = null;
    if (input.customerId) {
      const client = await this.prisma.client.findFirst({
        where: {
          id: input.customerId,
          companyId: input.companyId,
          isDeleted: false,
        },
        select: { defaultPriceListId: true },
      });
      if (!client) {
        throw new BadRequestException("Cliente inválido para esta empresa");
      }
      clientDefaultPriceListId = client.defaultPriceListId;
    }
    const selectedId = requestedPriceListId ?? clientDefaultPriceListId;
    if (!selectedId) return null;
    const manualOverride =
      requestedPriceListId != null && requestedPriceListId !== clientDefaultPriceListId;
    if (manualOverride && !this.canSelectManualPriceList(input.user)) {
      throw new ForbiddenException(
        "No tienes permiso para seleccionar otra lista de precios.",
      );
    }
    const priceList = await this.prisma.priceList.findFirst({
      where: { id: selectedId, companyId: input.companyId, active: true },
      select: { id: true, name: true },
    });
    if (!priceList) {
      throw new BadRequestException("Lista de precios inválida o inactiva");
    }
    return { ...priceList, manualOverride };
  }

  private bestRuleForQuantity<T extends { minQuantity: Prisma.Decimal; createdAt: Date; id: string }>(
    rules: T[],
    quantity: Prisma.Decimal,
  ) {
    return [...rules]
      .filter((rule) => new Prisma.Decimal(rule.minQuantity).lte(quantity))
      .sort((a, b) => {
        const quantityCompare = new Prisma.Decimal(b.minQuantity).cmp(
          new Prisma.Decimal(a.minQuantity),
        );
        if (quantityCompare !== 0) return quantityCompare;
        return a.createdAt.getTime() - b.createdAt.getTime();
      })[0];
  }

  private async findPriceListOrThrow(companyId: string, id: string) {
    const row = await this.prisma.priceList.findFirst({
      where: { id, companyId },
      select: { id: true },
    });
    if (!row) throw new NotFoundException("Lista de precios no encontrada");
    return row;
  }

  private async findProductOrThrow(companyId: string, id: string) {
    const product = await this.prisma.product.findFirst({
      where: { id, companyId, archivedAt: null },
      select: { id: true, precio: true },
    });
    if (!product) throw new BadRequestException("Producto inválido");
    return product;
  }

  private async findClientOrThrow(companyId: string, id: string) {
    const client = await this.prisma.client.findFirst({
      where: { id, companyId, isDeleted: false },
      select: { id: true },
    });
    if (!client) throw new BadRequestException("Cliente inválido");
    return client;
  }

  private assertRulePayload(
    mode: PriceListRuleMode,
    dto: { fixedPrice?: number; discountPercent?: number },
  ) {
    if (mode === PriceListRuleMode.FIXED_PRICE && dto.fixedPrice == null) {
      throw new BadRequestException("La regla requiere precio fijo");
    }
    if (
      mode === PriceListRuleMode.PERCENT_DISCOUNT &&
      dto.discountPercent == null
    ) {
      throw new BadRequestException("La regla requiere porcentaje de descuento");
    }
  }

  private requiredName(value: string) {
    const name = value.trim();
    if (!name) throw new BadRequestException("El nombre es obligatorio");
    return name;
  }

  private nullableText(value: string | null | undefined) {
    if (value == null) return null;
    const text = value.trim();
    return text.length ? text : null;
  }

  private requireAdminLike(user: TenantUser) {
    if (user.role !== "ADMIN" && user.role !== "ASISTENTE") {
      throw new ForbiddenException("No autorizado para administrar listas");
    }
  }

  private canSelectManualPriceList(user: TenantUser) {
    if (user.role === Role.ADMIN || user.role === Role.ASISTENTE) return true;
    if (user.adminAuthorized === true) return true;
    if (user.authorizedPermissions?.includes("selectManualPriceList")) {
      return true;
    }
    const permissions = this.normalizeBooleanMap(user.userPermissions);
    return (
      permissions.selectManualPriceList === true ||
      permissions.managePriceLists === true
    );
  }

  private normalizeBooleanMap(value: unknown) {
    if (!value || typeof value !== "object" || Array.isArray(value)) {
      return {} as Record<string, boolean>;
    }
    const result: Record<string, boolean> = {};
    for (const [key, entry] of Object.entries(value)) {
      result[key] = entry === true;
    }
    return result;
  }

  private toPublicResolution(
    result: ReturnType<PricingEngineService["resolveLine"]>,
  ) {
    return {
      ...result,
      unitPrice: result.unitPrice.toNumber(),
      originalUnitPrice: result.originalUnitPrice.toNumber(),
      discountPercent: result.discountPercent?.toNumber() ?? null,
      minQuantity: result.minQuantity?.toNumber() ?? null,
    };
  }
}

type DocumentPricingLine = {
  priceListId: string;
  priceListName: string;
  ruleId: string | null;
  ruleMode: PriceListRuleMode | null;
  unitPrice: Prisma.Decimal;
  originalUnitPrice: Prisma.Decimal;
  snapshot: Prisma.InputJsonValue;
};
