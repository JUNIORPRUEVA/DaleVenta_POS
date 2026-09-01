import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";
import { Prisma, Role } from "@prisma/client";
import { randomUUID } from "node:crypto";
import * as bcrypt from "bcryptjs";
import {
  isAdminLike,
  requireTenant,
  type TenantUser,
} from "../auth/tenant-context";
import { PrismaService } from "../prisma/prisma.service";
import { CatalogRealtimeRelayService } from "../products/catalog-realtime-relay.service";
import {
  ProductSourceResolver,
  type ProductSource,
  type ProductSourceContext,
} from "../products/product-source.resolver";
import { TaxService } from "../tax/tax.service";
import {
  backfillZeroConfigInventoryForCompany,
  ensureDefaultWarehouseAndTerminal,
} from "../inventory/zero-config-inventory";
import { DEFAULT_UNIT_OF_MEASURE_ID } from "../products/unit-of-measure.util";

type SettingsPayload = Record<string, unknown>;

@Injectable()
export class SettingsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly realtime: CatalogRealtimeRelayService,
    private readonly productSourceResolver: ProductSourceResolver,
    private readonly taxes: TaxService,
  ) {}

  async getSettings(user: TenantUser) {
    const companyId = requireTenant(user);
    const config = await this.ensureConfig(companyId);
    const fiscal = await this.taxes.getCompanyFiscalSettings(companyId);
    const productSource =
      await this.productSourceResolver.resolveForCompany(companyId);
    return this.toPublicSettings(config, fiscal, productSource);
  }

  async updateSettings(user: TenantUser, dto: SettingsPayload) {
    this.requireAdmin(user);
    const companyId = requireTenant(user);
    // `Company.name` es dato MAESTRO. El PATCH genérico de settings NUNCA lo
    // modifica: un payload legacy (p. ej. de una build Android antigua) que
    // incluya `companyName` se ignora deliberadamente aquí. El nombre solo
    // cambia por la acción EXPLÍCITA y autorizada `updateCompanyName`.
    const data = this.withoutCompanyName(this.settingsData(dto));
    const config = await this.prisma.$transaction(async (tx) => {
      const company = await tx.company.findUnique({
        where: { id: companyId },
        select: {
          name: true,
          measurementUnitsEnabled: true,
          multiWarehouseEnabled: true,
        },
      });
      const measurementUnitsEnabled =
        this.boolValue(dto, "measurementUnitsEnabled") ??
        company?.measurementUnitsEnabled ??
        false;
      const multiWarehouseEnabled =
        this.boolValue(dto, "multiWarehouseEnabled") ??
        company?.multiWarehouseEnabled ??
        false;
      const companyData = this.companyProductSourceData(dto);
      const hasMultiWarehouseChange =
        this.boolValue(dto, "multiWarehouseEnabled") !== undefined &&
        multiWarehouseEnabled !== (company?.multiWarehouseEnabled === true);
      const hasMeasurementUnitsChange =
        this.boolValue(dto, "measurementUnitsEnabled") !== undefined &&
        measurementUnitsEnabled !== (company?.measurementUnitsEnabled === true);
      if (
        this.boolValue(dto, "measurementUnitsEnabled") !== undefined ||
        this.boolValue(dto, "multiWarehouseEnabled") !== undefined ||
        Object.keys(companyData).length > 0
      ) {
        if (hasMultiWarehouseChange && !multiWarehouseEnabled) {
          await this.assertSafeMultiWarehouseDisable(tx, companyId);
        }
        if (hasMeasurementUnitsChange && !measurementUnitsEnabled) {
          await this.assertSafeMeasurementUnitsDisable(tx, companyId);
        }
        await tx.company.update({
          where: { id: companyId },
          data: {
            measurementUnitsEnabled,
            multiWarehouseEnabled,
            ...companyData,
          } as any,
          select: { id: true },
        });
        if (hasMultiWarehouseChange && multiWarehouseEnabled) {
          await ensureDefaultWarehouseAndTerminal(tx, companyId);
          await backfillZeroConfigInventoryForCompany(tx, companyId);
        }
      }
      const companyName = company?.name?.trim() ?? "";
      const updated = await tx.appConfig.upsert({
        where: { companyId },
        create: {
          id: `company_${companyId}`,
          companyId,
          companyName,
          ...data,
        },
        update: data,
      });
      return {
        ...updated,
        measurementUnitsEnabled,
        multiWarehouseEnabled,
      };
    });
    if (this.hasFiscalSettingsData(dto)) {
      await this.taxes.updateFiscalSettings(user, {
        taxEnabled: this.boolValue(dto, "taxEnabled") ?? undefined,
        defaultTaxId: this.stringValue(dto, "defaultTaxId") ?? undefined,
        defaultTaxRate: this.numberValue(dto, "defaultTaxRate") ?? undefined,
        pricesIncludeTax: this.boolValue(dto, "pricesIncludeTax") ?? undefined,
        ncfEnabled: this.boolValue(dto, "ncfEnabled") ?? undefined,
      });
    }
    const fiscal = await this.taxes.getCompanyFiscalSettings(companyId);
    const productSource =
      await this.productSourceResolver.resolveForCompany(companyId);
    return this.toPublicSettings(config, fiscal, productSource);
  }

  async updateCompanyName(user: TenantUser, dto: { companyName?: unknown }) {
    this.requireAdmin(user);
    const companyId = requireTenant(user);
    const companyName =
      typeof dto.companyName === "string" ? dto.companyName.trim() : "";
    if (!companyName) {
      throw new BadRequestException("El nombre de la empresa es obligatorio");
    }
    let previousCompanyName: string | null = null;
    const config = await this.prisma.$transaction(async (tx) => {
      const currentCompany = await tx.company.findUnique({
        where: { id: companyId },
        select: { name: true },
      });
      previousCompanyName = currentCompany?.name?.trim() ?? null;
      await tx.company.update({
        where: { id: companyId },
        data: { name: companyName },
        select: { id: true },
      });
      const updated = await tx.appConfig.upsert({
        where: { companyId },
        create: {
          id: `company_${companyId}`,
          companyId,
          companyName,
        },
        update: { companyName },
      });
      if (previousCompanyName !== companyName) {
        await this.writeCompanySettingsAuditLog(tx, {
          companyId,
          user,
          previousCompanyName,
          nextCompanyName: companyName,
        });
      }
      return updated;
    });
    this.emitCompanyNameUpdated(companyId, companyName);
    const fiscal = await this.taxes.getCompanyFiscalSettings(companyId);
    const productSource =
      await this.productSourceResolver.resolveForCompany(companyId);
    return this.toPublicSettings(config, fiscal, productSource);
  }

  private withoutCompanyName(
    data: Prisma.AppConfigUncheckedCreateInput &
      Prisma.AppConfigUncheckedUpdateInput,
  ): Prisma.AppConfigUncheckedCreateInput &
    Prisma.AppConfigUncheckedUpdateInput {
    const clone = { ...data } as Record<string, unknown>;
    delete clone.companyName;
    return clone as Prisma.AppConfigUncheckedCreateInput &
      Prisma.AppConfigUncheckedUpdateInput;
  }

  async setAdminPin(user: TenantUser, pin: unknown) {
    this.requireAdmin(user);
    const companyId = requireTenant(user);
    const normalizedPin = this.normalizePin(pin);
    const adminAuthorizationPinHash = await bcrypt.hash(normalizedPin, 10);
    const config = await this.prisma.appConfig.upsert({
      where: { companyId },
      create: {
        id: `company_${companyId}`,
        companyId,
        adminAuthorizationPinHash,
      },
      update: { adminAuthorizationPinHash },
    });
    return {
      ok: true,
      hasAdminAuthorizationPin: Boolean(config.adminAuthorizationPinHash),
    };
  }

  async verifyAdminPin(user: TenantUser, pin: unknown, scope: unknown) {
    const companyId = requireTenant(user);
    const normalizedPin = this.normalizePin(pin);
    const permissionScope = this.normalizeAuthorizationScope(scope);
    const config = await this.prisma.appConfig.findUnique({
      where: { companyId },
      select: { adminAuthorizationPinHash: true },
    });
    const hash = config?.adminAuthorizationPinHash ?? "";
    if (!hash) {
      throw new NotFoundException(
        "La empresa no tiene PIN administrativo configurado",
      );
    }
    const ok = await bcrypt.compare(normalizedPin, hash);
    if (!ok) {
      throw new ForbiddenException("PIN administrativo inválido");
    }
    const expiresInSeconds = 600;
    const adminAuthorizationToken = await this.jwt.signAsync(
      {
        sub: user.id,
        companyId,
        tokenType: "admin-authorization",
        permissions: [permissionScope],
      },
      { expiresIn: expiresInSeconds },
    );
    return {
      ok: true,
      expiresInSeconds,
      adminAuthorizationToken,
      permissions: [permissionScope],
    };
  }

  private requireAdmin(user: TenantUser) {
    if (!isAdminLike(user)) {
      throw new ForbiddenException(
        "Solo un administrador puede cambiar esta configuración",
      );
    }
  }

  private normalizePin(pin: unknown) {
    const value = `${pin ?? ""}`.trim();
    if (!/^\d{4}$/.test(value)) {
      throw new BadRequestException(
        "El PIN administrativo debe tener 4 dígitos",
      );
    }
    return value;
  }

  private normalizeAuthorizationScope(scope: unknown) {
    const value = `${scope ?? ""}`.trim();
    if (!/^[A-Za-z][A-Za-z0-9_.:-]{1,80}$/.test(value)) {
      throw new BadRequestException(
        "La autorización administrativa requiere un alcance válido",
      );
    }
    return value;
  }

  private emitCompanyNameUpdated(companyId: string, companyName: string) {
    this.realtime.emitCompany(companyId, "license.event", {
      eventId: `settings_${Date.now()}_${randomUUID().slice(0, 8)}`,
      type: "license.company_name_updated",
      companyId,
      companyName,
      account: {
        businessName: companyName,
      },
      at: new Date().toISOString(),
    });
  }

  private async ensureConfig(companyId: string) {
    const company = await this.prisma.company.findUnique({
      where: { id: companyId },
      select: {
        name: true,
        measurementUnitsEnabled: true,
        multiWarehouseEnabled: true,
      },
    });
    const companyName = company?.name?.trim() ?? "";
    const config = await this.prisma.appConfig.upsert({
      where: { companyId },
      create: {
        id: `company_${companyId}`,
        companyId,
        companyName,
      },
      update: {},
    });
    if (companyName && config.companyName !== companyName) {
      await this.prisma.appConfig.update({
        where: { companyId },
        data: { companyName },
        select: { id: true },
      });
    }
    return {
      ...config,
      companyName,
      measurementUnitsEnabled: company?.measurementUnitsEnabled === true,
      multiWarehouseEnabled: company?.multiWarehouseEnabled === true,
    };
  }

  private async assertSafeMultiWarehouseDisable(
    tx: Prisma.TransactionClient,
    companyId: string,
  ) {
    const distributedRows = await tx.warehouseStock.findMany({
      where: {
        companyId,
        quantity: { not: new Prisma.Decimal(0) },
        warehouse: { isActive: true },
      },
      select: {
        productId: true,
        warehouseId: true,
      },
    });
    const warehousesByProduct = new Map<string, Set<string>>();
    for (const row of distributedRows) {
      const warehouses =
        warehousesByProduct.get(row.productId) ?? new Set<string>();
      warehouses.add(row.warehouseId);
      warehousesByProduct.set(row.productId, warehouses);
    }
    const ambiguousProducts = [...warehousesByProduct.values()].filter(
      (warehouses) => warehouses.size > 1,
    ).length;
    if (ambiguousProducts > 0) {
      throw new BadRequestException(
        "No se puede desactivar multiples almacenes mientras existan productos con stock distribuido en mas de un almacen activo.",
      );
    }
  }

  private async assertSafeMeasurementUnitsDisable(
    tx: Prisma.TransactionClient,
    companyId: string,
  ) {
    const measuredProduct = await tx.product.findFirst({
      where: {
        companyId,
        unitOfMeasureId: { not: DEFAULT_UNIT_OF_MEASURE_ID },
      },
      select: { id: true },
    });
    if (measuredProduct) {
      throw new BadRequestException(
        "No se puede desactivar unidades de medida mientras existan productos con unidades distintas de Unidad.",
      );
    }
  }

  private async writeCompanySettingsAuditLog(
    tx: Prisma.TransactionClient,
    input: {
      companyId: string;
      user: TenantUser;
      previousCompanyName: string | null;
      nextCompanyName: string;
    },
  ) {
    await tx.companyLicenseAuditLog.create({
      data: {
        companyId: input.companyId,
        actorId: input.user.id,
        actorEmail: null,
        action: "settings.company_name_update",
        reason: "company_settings",
        before: { companyName: input.previousCompanyName ?? "" },
        after: { companyName: input.nextCompanyName },
      },
    });
  }

  private stringValue(dto: SettingsPayload, key: string) {
    const value = dto[key];
    return typeof value === "string" ? value.trim() : undefined;
  }

  private boolValue(dto: SettingsPayload, key: string) {
    const value = dto[key];
    if (typeof value === "boolean") return value;
    if (typeof value === "number") {
      if (value === 1) return true;
      if (value === 0) return false;
    }
    if (typeof value === "string") {
      const normalized = value.trim().toLowerCase();
      if (["true", "1", "yes", "si"].includes(normalized)) return true;
      if (["false", "0", "no"].includes(normalized)) return false;
    }
    return undefined;
  }

  private productSourceValue(dto: SettingsPayload): ProductSource | undefined {
    const raw = this.stringValue(dto, "productsSource");
    const source = raw?.toUpperCase();
    if (!source) return undefined;
    if (
      source === "LOCAL" ||
      source === "FULLPOS" ||
      source === "FULLPOS_DIRECT"
    ) {
      return source;
    }
    throw new BadRequestException("Fuente de productos inválida");
  }

  private companyProductSourceData(
    dto: SettingsPayload,
  ): Prisma.CompanyUncheckedUpdateInput {
    const data: Prisma.CompanyUncheckedUpdateInput = {};
    const productSource = this.productSourceValue(dto);
    const fullposCompanyId = this.stringValue(dto, "fullposCompanyId");
    if (productSource !== undefined) {
      (data as any).productSource = productSource;
    }
    if (fullposCompanyId !== undefined) {
      (data as any).fullposCompanyId = fullposCompanyId || null;
    }
    return data;
  }

  private numberValue(dto: SettingsPayload, key: string) {
    const value = dto[key];
    if (typeof value !== "number" || !Number.isFinite(value)) return undefined;
    return value;
  }

  private hasFiscalSettingsData(dto: SettingsPayload) {
    return [
      "taxEnabled",
      "defaultTaxId",
      "defaultTaxRate",
      "pricesIncludeTax",
      "ncfEnabled",
    ].some((key) => Object.prototype.hasOwnProperty.call(dto, key));
  }

  private companyFiscalData(
    dto: SettingsPayload,
  ): Prisma.CompanyUncheckedUpdateInput {
    const data: Prisma.CompanyUncheckedUpdateInput = {};
    const taxEnabled = this.boolValue(dto, "taxEnabled");
    const defaultTaxRate = this.numberValue(dto, "defaultTaxRate");
    const pricesIncludeTax = this.boolValue(dto, "pricesIncludeTax");
    const ncfEnabled = this.boolValue(dto, "ncfEnabled");
    if (taxEnabled !== undefined) data.taxEnabled = taxEnabled;
    if (defaultTaxRate !== undefined)
      data.defaultTaxRate = new Prisma.Decimal(defaultTaxRate);
    if (pricesIncludeTax !== undefined)
      data.pricesIncludeTax = pricesIncludeTax;
    if (ncfEnabled !== undefined) data.ncfEnabled = ncfEnabled;
    return data;
  }

  private settingsData(
    dto: SettingsPayload,
  ): Prisma.AppConfigUncheckedCreateInput &
    Prisma.AppConfigUncheckedUpdateInput {
    const bankAccounts = Array.isArray(dto.bankAccounts)
      ? (dto.bankAccounts as Prisma.InputJsonValue)
      : undefined;
    return {
      companyName: this.stringValue(dto, "companyName"),
      rnc: this.stringValue(dto, "rnc"),
      phone: this.stringValue(dto, "phone"),
      phonePreferential: this.stringValue(dto, "phonePreferential"),
      address: this.stringValue(dto, "address"),
      description: this.stringValue(dto, "description"),
      instagramUrl: this.stringValue(dto, "instagramUrl"),
      facebookUrl: this.stringValue(dto, "facebookUrl"),
      websiteUrl: this.stringValue(dto, "websiteUrl"),
      gpsLocationUrl: this.stringValue(dto, "gpsLocationUrl"),
      businessHours: this.stringValue(dto, "businessHours"),
      bankAccounts,
      legalRepresentativeName: this.stringValue(dto, "legalRepresentativeName"),
      legalRepresentativeCedula: this.stringValue(
        dto,
        "legalRepresentativeCedula",
      ),
      legalRepresentativeRole: this.stringValue(dto, "legalRepresentativeRole"),
      legalRepresentativeNationality: this.stringValue(
        dto,
        "legalRepresentativeNationality",
      ),
      legalRepresentativeCivilStatus: this.stringValue(
        dto,
        "legalRepresentativeCivilStatus",
      ),
      logoBase64: this.stringValue(dto, "logoBase64"),
      openAiApiKey: this.stringValue(dto, "openAiApiKey"),
      evolutionApiBaseUrl: this.stringValue(dto, "evolutionApiBaseUrl"),
      evolutionApiInstanceName: this.stringValue(
        dto,
        "evolutionApiInstanceName",
      ),
      evolutionApiApiKey: this.stringValue(dto, "evolutionApiApiKey"),
      whatsappWebhookEnabled: this.boolValue(dto, "whatsappWebhookEnabled"),
    };
  }

  private toPublicSettings(
    config: {
      companyName: string;
      rnc: string;
      phone: string;
      phonePreferential: string;
      address: string;
      description: string;
      instagramUrl: string;
      facebookUrl: string;
      websiteUrl: string;
      gpsLocationUrl: string;
      businessHours: string;
      bankAccounts: Prisma.JsonValue;
      legalRepresentativeName: string;
      legalRepresentativeCedula: string;
      legalRepresentativeRole: string;
      legalRepresentativeNationality: string;
      legalRepresentativeCivilStatus: string;
      logoBase64: string | null;
      openAiApiKey: string | null;
      openAiModel: string;
      evolutionApiBaseUrl: string;
      evolutionApiInstanceName: string;
      evolutionApiApiKey: string | null;
      whatsappWebhookEnabled: boolean;
      measurementUnitsEnabled?: boolean;
      multiWarehouseEnabled?: boolean;
      adminAuthorizationPinHash: string | null;
    },
    fiscal: {
      taxEnabled: boolean;
      defaultTaxId: string | null;
      defaultTaxRate: Prisma.Decimal | number | string;
      pricesIncludeTax: boolean;
      ncfEnabled: boolean;
    },
    productSource: ProductSourceContext,
  ) {
    return {
      companyName: config.companyName,
      rnc: config.rnc,
      phone: config.phone,
      phonePreferential: config.phonePreferential,
      address: config.address,
      description: config.description,
      instagramUrl: config.instagramUrl,
      facebookUrl: config.facebookUrl,
      websiteUrl: config.websiteUrl,
      gpsLocationUrl: config.gpsLocationUrl,
      businessHours: config.businessHours,
      bankAccounts: Array.isArray(config.bankAccounts)
        ? config.bankAccounts
        : [],
      legalRepresentativeName: config.legalRepresentativeName,
      legalRepresentativeCedula: config.legalRepresentativeCedula,
      legalRepresentativeRole: config.legalRepresentativeRole,
      legalRepresentativeNationality: config.legalRepresentativeNationality,
      legalRepresentativeCivilStatus: config.legalRepresentativeCivilStatus,
      logoBase64: config.logoBase64,
      openAiApiKey: "",
      openAiModel: config.openAiModel,
      hasOpenAiApiKey: Boolean(config.openAiApiKey),
      evolutionApiBaseUrl: config.evolutionApiBaseUrl,
      evolutionApiInstanceName: config.evolutionApiInstanceName,
      evolutionApiApiKey: "",
      hasEvolutionApiApiKey: Boolean(config.evolutionApiApiKey),
      whatsappWebhookEnabled: config.whatsappWebhookEnabled,
      measurementUnitsEnabled: config.measurementUnitsEnabled === true,
      multiWarehouseEnabled: config.multiWarehouseEnabled === true,
      hasAdminAuthorizationPin: Boolean(config.adminAuthorizationPinHash),
      productsSource: productSource.source,
      productsReadOnly: productSource.readOnly,
      productSourceResolution: productSource.resolution,
      productProviderCapabilities: {
        supportsDecimalStock: productSource.supportsDecimalStock,
        supportsNativeUom: productSource.supportsNativeUom,
        supportsProductCreate: productSource.supportsProductCreate,
        supportsProductEdit: productSource.supportsProductEdit,
        supportsStockAdjustment: productSource.supportsStockAdjustment,
      },
      taxEnabled: fiscal.taxEnabled,
      defaultTaxId: fiscal.defaultTaxId,
      defaultTaxRate: this.toNumber(fiscal.defaultTaxRate),
      pricesIncludeTax: fiscal.pricesIncludeTax,
      ncfEnabled: fiscal.ncfEnabled,
    };
  }

  private toNumber(value: Prisma.Decimal | number | string | null | undefined) {
    if (value == null) return 0;
    if (typeof value === "number") return value;
    return Number(value);
  }
}
