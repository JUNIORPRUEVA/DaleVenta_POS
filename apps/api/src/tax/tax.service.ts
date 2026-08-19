import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { Prisma } from "@prisma/client";
import {
  isAdminLikeForScope,
  requireTenant,
  type TenantUser,
} from "../auth/tenant-context";
import { PrismaService } from "../prisma/prisma.service";
import {
  TaxCalculationService,
  type TaxPriceMode,
} from "./tax-calculation.service";
import { UpdateFiscalSettingsDto, UpsertTaxDto } from "./tax.dto";

@Injectable()
export class TaxService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly calculator: TaxCalculationService,
  ) {}

  async listTaxes(user: TenantUser) {
    const companyId = requireTenant(user);
    await this.ensureDefaultTaxIfNeeded(companyId);
    return this.prisma.tax.findMany({
      where: { companyId },
      orderBy: [{ isDefault: "desc" }, { name: "asc" }],
    });
  }

  async createTax(user: TenantUser, dto: UpsertTaxDto) {
    this.requireAdmin(user);
    const companyId = requireTenant(user);
    const rate = this.normalizeRate(dto.rate);
    return this.prisma.$transaction(async (tx) => {
      if (dto.isDefault === true) {
        await tx.tax.updateMany({
          where: { companyId },
          data: { isDefault: false },
        });
      }
      const tax = await tx.tax.create({
        data: {
          companyId,
          name: dto.name.trim(),
          rate,
          isActive: dto.isActive ?? true,
          isDefault: dto.isDefault ?? false,
        },
      });
      if (tax.isDefault) {
        await tx.company.update({
          where: { id: companyId },
          data: { defaultTaxId: tax.id, defaultTaxRate: tax.rate },
        });
      }
      return tax;
    });
  }

  async updateTax(user: TenantUser, id: string, dto: Partial<UpsertTaxDto>) {
    this.requireAdmin(user);
    const companyId = requireTenant(user);
    const existing = await this.prisma.tax.findFirst({
      where: { id, companyId },
    });
    if (!existing) throw new NotFoundException("Impuesto no encontrado");
    return this.prisma.$transaction(async (tx) => {
      if (dto.isDefault === true) {
        await tx.tax.updateMany({
          where: { companyId },
          data: { isDefault: false },
        });
      }
      const tax = await tx.tax.update({
        where: { id },
        data: {
          ...(dto.name !== undefined ? { name: dto.name.trim() } : {}),
          ...(dto.rate !== undefined
            ? { rate: this.normalizeRate(dto.rate) }
            : {}),
          ...(dto.isActive !== undefined ? { isActive: dto.isActive } : {}),
          ...(dto.isDefault !== undefined ? { isDefault: dto.isDefault } : {}),
        },
      });
      if (tax.isDefault) {
        await tx.company.update({
          where: { id: companyId },
          data: { defaultTaxId: tax.id, defaultTaxRate: tax.rate },
        });
      }
      return tax;
    });
  }

  async getFiscalSettings(user: TenantUser) {
    const companyId = requireTenant(user);
    const company = await this.getCompanyFiscalSettings(companyId);
    const taxes = await this.listTaxes(user);
    return { ...company, taxes };
  }

  async updateFiscalSettings(user: TenantUser, dto: UpdateFiscalSettingsDto) {
    this.requireAdmin(user);
    const companyId = requireTenant(user);
    return this.prisma.$transaction(async (tx) => {
      let defaultTaxId = dto.defaultTaxId?.trim() || undefined;
      let defaultTaxRate =
        dto.defaultTaxRate === undefined
          ? undefined
          : this.normalizeRate(dto.defaultTaxRate);

      if (dto.taxEnabled === true && !defaultTaxId) {
        const tax = await this.ensureDefaultTaxIfNeeded(companyId, tx);
        defaultTaxId = tax.id;
        defaultTaxRate = tax.rate;
      } else if (defaultTaxId) {
        const tax = await tx.tax.findFirst({
          where: { id: defaultTaxId, companyId, isActive: true },
        });
        if (!tax)
          throw new BadRequestException("Impuesto predeterminado invalido");
        defaultTaxRate = tax.rate;
        await tx.tax.updateMany({
          where: { companyId },
          data: { isDefault: false },
        });
        await tx.tax.update({
          where: { id: tax.id },
          data: { isDefault: true },
        });
      }

      const company = await tx.company.update({
        where: { id: companyId },
        data: {
          ...(dto.taxEnabled !== undefined
            ? { taxEnabled: dto.taxEnabled }
            : {}),
          ...(defaultTaxId !== undefined ? { defaultTaxId } : {}),
          ...(defaultTaxRate !== undefined ? { defaultTaxRate } : {}),
          ...(dto.pricesIncludeTax !== undefined
            ? { pricesIncludeTax: dto.pricesIncludeTax }
            : {}),
          ...(dto.ncfEnabled !== undefined
            ? { ncfEnabled: dto.ncfEnabled }
            : {}),
        },
        select: this.companyFiscalSelect(),
      });
      return company;
    });
  }

  async getCompanyFiscalSettings(companyId: string) {
    const company = await this.prisma.company.findUnique({
      where: { id: companyId },
      select: this.companyFiscalSelect(),
    });
    if (!company) throw new NotFoundException("Empresa no encontrada");
    return company;
  }

  resolvePriceMode(settings: {
    taxEnabled: boolean;
    pricesIncludeTax: boolean;
  }): TaxPriceMode {
    if (!settings.taxEnabled) return "NO_TAX";
    return settings.pricesIncludeTax ? "TAX_INCLUDED" : "TAX_ADDED";
  }

  async ensureDefaultTaxIfNeeded(
    companyId: string,
    tx: Prisma.TransactionClient = this.prisma,
  ) {
    const company = await tx.company.findUnique({
      where: { id: companyId },
      select: { taxEnabled: true, defaultTaxId: true },
    });
    if (!company?.taxEnabled) {
      const existing = await tx.tax.findFirst({
        where: { companyId, name: "ITBIS" },
      });
      if (existing) return existing;
      return tx.tax.create({
        data: {
          companyId,
          name: "ITBIS",
          rate: new Prisma.Decimal(0.18),
          isActive: true,
          isDefault: false,
        },
      });
    }

    const currentDefault = company.defaultTaxId
      ? await tx.tax.findFirst({
          where: { id: company.defaultTaxId, companyId, isActive: true },
        })
      : null;
    if (currentDefault) return currentDefault;

    const existing = await tx.tax.findFirst({
      where: { companyId, name: "ITBIS" },
    });
    if (existing) {
      await tx.tax.updateMany({
        where: { companyId },
        data: { isDefault: false },
      });
      const updated = await tx.tax.update({
        where: { id: existing.id },
        data: { rate: existing.rate, isActive: true, isDefault: true },
      });
      await tx.company.update({
        where: { id: companyId },
        data: { defaultTaxId: updated.id, defaultTaxRate: updated.rate },
      });
      return updated;
    }

    const tax = await tx.tax.create({
      data: {
        companyId,
        name: "ITBIS",
        rate: new Prisma.Decimal(0.18),
        isActive: true,
        isDefault: true,
      },
    });
    await tx.company.update({
      where: { id: companyId },
      data: { defaultTaxId: tax.id, defaultTaxRate: tax.rate },
    });
    return tax;
  }

  get calculatorService() {
    return this.calculator;
  }

  private requireAdmin(user: TenantUser) {
    if (!isAdminLikeForScope(user, "company.settings")) {
      throw new ForbiddenException(
        "Solo un administrador puede cambiar configuracion fiscal",
      );
    }
  }

  private normalizeRate(value: number | Prisma.Decimal) {
    const rate = new Prisma.Decimal(value);
    if (rate.lt(0) || rate.gt(1)) {
      throw new BadRequestException("La tasa debe estar entre 0 y 1");
    }
    return rate;
  }

  private companyFiscalSelect() {
    return {
      id: true,
      taxEnabled: true,
      defaultTaxId: true,
      defaultTaxRate: true,
      pricesIncludeTax: true,
      ncfEnabled: true,
    } satisfies Prisma.CompanySelect;
  }
}
