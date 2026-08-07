import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, Role, WarrantyDurationUnit } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { requireTenant } from '../auth/tenant-context';
import { WarrantyProductConfigQueryDto } from './dto/warranty-product-config-query.dto';
import { UpsertWarrantyProductConfigDto } from './dto/upsert-warranty-product-config.dto';

type AuthUser = { id: string; role: Role; companyId?: string | null };
type WarrantyConfigRow = Prisma.WarrantyProductConfigGetPayload<{ include: { category: true } }>;

export type WarrantyConfigResolution = {
  id: string;
  scope: 'product' | 'category' | 'fallback';
  scopeLabel: string;
  hasWarranty: boolean;
  durationValue: number | null;
  durationUnit: WarrantyDurationUnit | null;
  summary: string | null;
  coverageSummary: string | null;
  exclusionsSummary: string | null;
  notes: string | null;
  categoryName: string | null;
  categoryCode: string | null;
  productName: string | null;
};

@Injectable()
export class WarrantyConfigsService {
  constructor(private readonly prisma: PrismaService) {}

  async resolveCompanyOwnerId(fallbackUserId: string) {
    const admin = await this.prisma.user.findFirst({
      where: { role: Role.ADMIN },
      orderBy: { createdAt: 'asc' },
      select: { id: true },
    });
    return admin?.id ?? fallbackUserId;
  }

  async list(user: AuthUser, query: WarrantyProductConfigQueryDto) {
    const ownerId = await this.resolveCompanyOwnerId(user.id);
    const where = this.buildWhere(ownerId, query);
    const items = await this.prisma.warrantyProductConfig.findMany({
      where,
      include: { category: true },
      orderBy: [
        { isActive: 'desc' },
        { productName: 'asc' },
        { categoryName: 'asc' },
        { updatedAt: 'desc' },
      ],
    });
    return { items: items.map((item) => this.mapConfig(item)) };
  }

  async findOne(user: AuthUser, id: string) {
    const ownerId = await this.resolveCompanyOwnerId(user.id);
    const item = await this.prisma.warrantyProductConfig.findFirst({
      where: { id, ownerId },
      include: { category: true },
    });
    if (!item) throw new NotFoundException('La configuración de garantía no existe');
    return this.mapConfig(item);
  }

  async create(user: AuthUser, dto: UpsertWarrantyProductConfigDto) {
    const ownerId = await this.resolveCompanyOwnerId(user.id);
    const data = await this.buildData(requireTenant(user), ownerId, dto);
    const item = await this.prisma.warrantyProductConfig.create({
      data,
      include: { category: true },
    });
    return this.mapConfig(item);
  }

  async update(user: AuthUser, id: string, dto: UpsertWarrantyProductConfigDto) {
    const ownerId = await this.resolveCompanyOwnerId(user.id);
    const existing = await this.prisma.warrantyProductConfig.findFirst({
      where: { id, ownerId },
      select: { id: true },
    });
    if (!existing) throw new NotFoundException('La configuración de garantía no existe');
    const data = await this.buildData(requireTenant(user), ownerId, dto);
    const item = await this.prisma.warrantyProductConfig.update({
      where: { id },
      data,
      include: { category: true },
    });
    return this.mapConfig(item);
  }

  async setActive(user: AuthUser, id: string, isActive: boolean) {
    const ownerId = await this.resolveCompanyOwnerId(user.id);
    const existing = await this.prisma.warrantyProductConfig.findFirst({
      where: { id, ownerId },
      select: { id: true },
    });
    if (!existing) throw new NotFoundException('La configuración de garantía no existe');
    const item = await this.prisma.warrantyProductConfig.update({
      where: { id },
      data: { isActive },
      include: { category: true },
    });
    return this.mapConfig(item);
  }

  async remove(user: AuthUser, id: string) {
    const ownerId = await this.resolveCompanyOwnerId(user.id);
    const existing = await this.prisma.warrantyProductConfig.findFirst({
      where: { id, ownerId },
      select: { id: true },
    });
    if (!existing) throw new NotFoundException('La configuración de garantía no existe');
    await this.prisma.warrantyProductConfig.deleteMany({ where: { id, ownerId } });
    return { ok: true };
  }

  async resolveForService(params: {
    fallbackUserId: string;
    categoryId?: string | null;
    categoryCode?: string | null;
    categoryName?: string | null;
    productNames?: string[];
    serviceTitle?: string | null;
    equipmentInstalledText?: string | null;
  }): Promise<WarrantyConfigResolution | null> {
    const ownerId = await this.resolveCompanyOwnerId(params.fallbackUserId);
    const categoryCode = this.normalizeCode(params.categoryCode ?? params.categoryName ?? '');
    const productCandidates = this.collectProductCandidates(params);
    const productKeys = Array.from(new Set(productCandidates.map((item) => this.normalizeText(item)).filter(Boolean)));

    const where: Prisma.WarrantyProductConfigWhereInput = {
      ownerId,
      isActive: true,
      OR: [
        ...(productKeys.length ? [{ productKey: { in: productKeys } }] : []),
        ...(params.categoryId?.trim() ? [{ categoryId: params.categoryId.trim() }] : []),
        ...(categoryCode ? [{ categoryCode }] : []),
      ],
    };

    const configs = await this.prisma.warrantyProductConfig.findMany({
      where,
      include: { category: true },
      orderBy: [{ updatedAt: 'desc' }],
    });

    const byProduct = productKeys
      .map((key) => configs.find((item) => (item.productKey ?? '').trim() === key))
      .find(Boolean);
    if (byProduct) {
      return this.mapResolution(byProduct, 'product');
    }

    const byCategory = configs.find((item) => {
      if (params.categoryId?.trim() && item.categoryId === params.categoryId.trim()) return true;
      return categoryCode.length > 0 && (item.categoryCode ?? '').trim() === categoryCode;
    });
    if (byCategory) {
      return this.mapResolution(byCategory, 'category');
    }

    return null;
  }

  private buildWhere(ownerId: string, query: WarrantyProductConfigQueryDto): Prisma.WarrantyProductConfigWhereInput {
    const search = (query.search ?? '').trim();
    const products = (query.products ?? [])
      .map((item) => this.normalizeText(item))
      .filter((item) => item.length > 0);
    const categoryCode = this.normalizeCode(query.categoryCode ?? '');

    const where: Prisma.WarrantyProductConfigWhereInput = {
      ownerId,
      ...(query.includeInactive ? {} : { isActive: true }),
      ...(query.categoryId?.trim() ? { categoryId: query.categoryId.trim() } : {}),
      ...(categoryCode ? { categoryCode } : {}),
    };

    const orFilters: Prisma.WarrantyProductConfigWhereInput[] = [];
    if (search) {
      orFilters.push(
        { productName: { contains: search, mode: 'insensitive' } },
        { categoryName: { contains: search, mode: 'insensitive' } },
        { warrantySummary: { contains: search, mode: 'insensitive' } },
        { coverageSummary: { contains: search, mode: 'insensitive' } },
        { exclusionsSummary: { contains: search, mode: 'insensitive' } },
        { notes: { contains: search, mode: 'insensitive' } },
      );
    }
    if (products.length) {
      orFilters.push({ productKey: { in: products } });
    }

    if (orFilters.length) {
      where.AND = [{ OR: orFilters }];
    }

    return where;
  }

  private async buildData(companyId: string, ownerId: string, dto: UpsertWarrantyProductConfigDto) {
    const categoryId = dto.categoryId?.trim() || null;
    const categoryCode = this.normalizeCode(dto.categoryCode ?? '');
    const categoryName = this.cleanText(dto.categoryName);
    const productName = this.cleanText(dto.productName);
    const hasWarranty = dto.hasWarranty ?? true;
    const durationValue = dto.durationValue ?? null;
    const durationUnit = dto.durationUnit ?? null;
    const warrantySummary = this.cleanText(dto.warrantySummary);
    const coverageSummary = this.cleanText(dto.coverageSummary);
    const exclusionsSummary = this.cleanText(dto.exclusionsSummary);
    const notes = this.cleanText(dto.notes);
    const isActive = dto.isActive ?? true;

    if (!categoryId && !categoryCode && !categoryName && !productName) {
      throw new BadRequestException('Debe indicar una categoría, un código de categoría o un producto');
    }
    if ((durationValue == null) !== (durationUnit == null)) {
      throw new BadRequestException('La duración debe incluir valor y unidad');
    }
    if (durationValue != null && durationValue < 0) {
      throw new BadRequestException('La duración no puede ser negativa');
    }
    if (!hasWarranty && durationValue && durationValue > 0) {
      throw new BadRequestException('Una configuración sin garantía no debe incluir duración');
    }

    let resolvedCategoryName = categoryName;
    let resolvedCategoryCode = categoryCode;
    if (categoryId) {
      const category = await this.prisma.serviceCategory.findUnique({
        where: { id: categoryId },
        select: { id: true, name: true, code: true },
      });
      if (!category) throw new BadRequestException('La categoría indicada no existe');
      resolvedCategoryName = (category.name ?? '').trim() || resolvedCategoryName;
      resolvedCategoryCode = (category.code ?? '').trim() || resolvedCategoryCode;
    }

    return {
      companyId,
      ownerId,
      categoryId,
      categoryCode: resolvedCategoryCode || null,
      categoryName: resolvedCategoryName || null,
      productName: productName || null,
      productKey: productName ? this.normalizeText(productName) : null,
      hasWarranty,
      durationValue: hasWarranty ? durationValue : null,
      durationUnit: hasWarranty ? durationUnit : null,
      warrantySummary: warrantySummary || null,
      coverageSummary: coverageSummary || null,
      exclusionsSummary: exclusionsSummary || null,
      notes: notes || null,
      isActive,
    };
  }

  private mapConfig(item: WarrantyConfigRow) {
    return {
      id: item.id,
      ownerId: item.ownerId,
      categoryId: item.categoryId,
      categoryCode: item.categoryCode,
      categoryName: item.category?.name ?? item.categoryName,
      productName: item.productName,
      hasWarranty: item.hasWarranty,
      durationValue: item.durationValue,
      durationUnit: item.durationUnit,
      warrantySummary: item.warrantySummary,
      coverageSummary: item.coverageSummary,
      exclusionsSummary: item.exclusionsSummary,
      notes: item.notes,
      isActive: item.isActive,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      scopeLabel: item.productName?.trim().length ? item.productName
        : (item.category?.name ?? item.categoryName ?? 'General'),
    };
  }

  private mapResolution(item: WarrantyConfigRow, scope: 'product' | 'category'): WarrantyConfigResolution {
    return {
      id: item.id,
      scope,
      scopeLabel: item.productName?.trim().length ? item.productName!.trim()
        : (item.category?.name ?? item.categoryName ?? 'Garantía general'),
      hasWarranty: item.hasWarranty,
      durationValue: item.durationValue,
      durationUnit: item.durationUnit,
      summary: this.cleanText(item.warrantySummary) || null,
      coverageSummary: this.cleanText(item.coverageSummary) || null,
      exclusionsSummary: this.cleanText(item.exclusionsSummary) || null,
      notes: this.cleanText(item.notes) || null,
      categoryName: this.cleanText(item.category?.name ?? item.categoryName) || null,
      categoryCode: this.cleanText(item.category?.code ?? item.categoryCode) || null,
      productName: this.cleanText(item.productName) || null,
    };
  }

  private collectProductCandidates(params: {
    productNames?: string[];
    serviceTitle?: string | null;
    equipmentInstalledText?: string | null;
  }) {
    const items = [
      ...(params.productNames ?? []),
      ...(this.splitEquipmentText(params.equipmentInstalledText) ?? []),
      params.serviceTitle ?? '',
    ];
    return Array.from(new Set(items.map((item) => this.cleanText(item)).filter((item) => item.length > 0)));
  }

  private splitEquipmentText(raw?: string | null) {
    const text = this.cleanText(raw);
    if (!text) return [];
    return text
      .split(/\r?\n|,|;|\|/g)
      .map((item) => item.replace(/^[-*\u2022\s]+/, '').trim())
      .filter((item) => item.length > 0);
  }

  private cleanText(value?: string | null) {
    return (value ?? '').trim();
  }

  private normalizeText(value: string) {
    return value
      .normalize('NFD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, ' ')
      .trim();
  }

  private normalizeCode(value: string) {
    return this.normalizeText(value).replace(/\s+/g, '_');
  }
}
