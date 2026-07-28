import { ConflictException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Prisma, Product } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { requireTenant, type TenantUser } from '../auth/tenant-context';
import { CatalogProductsService } from './catalog-products.service';
import { CreateProductDto } from './dto/create-product.dto';
import { UpdateProductDto } from './dto/update-product.dto';

type ProductsSource = 'FULLPOS' | 'FULLPOS_DIRECT' | 'LOCAL';

@Injectable()
export class ProductsService {
  private readonly logger = new Logger(ProductsService.name);
  private readonly publicBaseUrl: string;
  private readonly productsSource: ProductsSource;
  private readonly allowLocalFallback: boolean;

  constructor(
    private readonly prisma: PrismaService,
    private readonly catalogProducts: CatalogProductsService,
    private readonly config: ConfigService,
  ) {
    const base = this.config.get<string>('PUBLIC_BASE_URL') ?? this.config.get<string>('API_BASE_URL') ?? '';
    this.publicBaseUrl = base.trim().replace(/\/$/, '');

    const rawFallback = (this.config.get<string>('PRODUCTS_ALLOW_LOCAL_FALLBACK') ?? '').trim().toLowerCase();
    this.allowLocalFallback = rawFallback === '1' || rawFallback === 'true' || rawFallback === 'yes';

    const rawSource = (this.config.get<string>('PRODUCTS_SOURCE') ?? '').trim().toUpperCase();
    let computed: ProductsSource = 'LOCAL';
    if (rawSource && rawSource !== 'LOCAL') {
      this.logger.warn(
        `PRODUCTS_SOURCE=${rawSource} ignorado: el catálogo administrado por FullTech usa fuente LOCAL.`,
      );
    }

    this.productsSource = computed;
  }

  isReadOnly() {
    return this.productsSource === 'FULLPOS' || this.productsSource === 'FULLPOS_DIRECT';
  }

  getSource(): ProductsSource {
    return this.productsSource;
  }

  private assertWritable() {
    if (this.productsSource === 'FULLPOS' || this.productsSource === 'FULLPOS_DIRECT') {
      throw new ConflictException('Productos en modo solo-lectura: fuente FULLPOS (cloud). Administra productos en FULLPOS.');
    }
  }

  private isSchemaMismatch(error: unknown) {
    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      return error.code === 'P2021' || error.code === 'P2022';
    }

    if (typeof error === 'object' && error !== null) {
      const value = error as { code?: unknown; message?: unknown };
      const code = typeof value.code === 'string' ? value.code : '';
      const message = typeof value.message === 'string' ? value.message : '';
      return (
        code === 'P2021' ||
        code === 'P2022' ||
        message.includes('does not exist in the current database') ||
        message.toLowerCase().includes('column')
      );
    }

    return false;
  }

  create(user: TenantUser, dto: CreateProductDto): Promise<any> {
    this.assertWritable();
    const companyId = requireTenant(user);
    return this.prisma.$transaction(async (tx) => {
      const normalizedImagePath = this.normalizeImagePathForStorage(dto.fotoUrl);
      const data = {
        nombre: dto.nombre,
        categoria: dto.categoria,
        precio: new Prisma.Decimal(dto.precio),
        costo: new Prisma.Decimal(dto.costo),
        stock: new Prisma.Decimal(dto.stock ?? 0),
        imagen: normalizedImagePath,
        companyId,
      };

      if (dto.fotoUrl !== normalizedImagePath) {
        this.logger.log(`normalize create image path: "${dto.fotoUrl ?? ''}" -> "${normalizedImagePath ?? ''}"`);
      }

      try {
        const product = await tx.product.create({ data });
        return this.mapProduct(product);
      } catch (error) {
        if (!this.isSchemaMismatch(error)) throw error;
        const product = await tx.product.create({ data });
        return this.mapProduct(product);
      }
    });
  }

  async findAll(user: TenantUser): Promise<any[]> {
    const companyId = requireTenant(user);
    if (this.productsSource === 'FULLPOS' || this.productsSource === 'FULLPOS_DIRECT') {
      try {
        const response = await this.catalogProducts.findAll();
        return response.items;
      } catch (error) {
        if (!this.allowLocalFallback) {
          throw error;
        }

        const message = error instanceof Error ? error.message : String(error);
        this.logger.warn(
          `FULLPOS products failed; falling back to LOCAL because PRODUCTS_ALLOW_LOCAL_FALLBACK=true. error=${message}`,
        );
        // fall through to LOCAL
      }
    }

    try {
      const products = await this.prisma.product.findMany({ where: { companyId }, orderBy: { nombre: 'asc' } });
      return products.map((p) => this.mapProduct(p));
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      const products = await this.prisma.product.findMany({ where: { companyId }, orderBy: { nombre: 'asc' } });
      return products.map((p) => this.mapProduct(p));
    }
  }

  async findOne(user: TenantUser, id: string): Promise<any> {
    const companyId = requireTenant(user);
    if (this.productsSource === 'FULLPOS') {
      try {
        return await this.catalogProducts.findOne(id);
      } catch (error) {
        if (!this.allowLocalFallback) {
          throw error;
        }

        const message = error instanceof Error ? error.message : String(error);
        this.logger.warn(
          `FULLPOS product lookup failed; falling back to LOCAL because PRODUCTS_ALLOW_LOCAL_FALLBACK=true. id=${id} error=${message}`,
        );
        // fall through to LOCAL
      }
    }

    let product: Product | null = null;
    try {
      product = await this.prisma.product.findFirst({ where: { id, companyId } });
    } catch (error) {
      if (!this.isSchemaMismatch(error)) throw error;
      product = await this.prisma.product.findFirst({ where: { id, companyId } });
    }
    if (!product) throw new NotFoundException('Product not found');
    return this.mapProduct(product);
  }

  async update(user: TenantUser, id: string, dto: UpdateProductDto): Promise<any> {
    this.assertWritable();
    const companyId = requireTenant(user);
    await this.findOne(user, id);
    return this.prisma.$transaction(async (tx) => {
      const normalizedImagePath = dto.fotoUrl === undefined
        ? undefined
        : this.normalizeImagePathForStorage(dto.fotoUrl);
      const data = {
        nombre: dto.nombre,
        categoria: dto.categoria,
        precio: dto.precio === undefined ? undefined : new Prisma.Decimal(dto.precio),
        costo: dto.costo === undefined ? undefined : new Prisma.Decimal(dto.costo),
        stock: dto.stock === undefined ? undefined : new Prisma.Decimal(dto.stock),
        imagen: normalizedImagePath,
      };

      if (dto.fotoUrl !== undefined && dto.fotoUrl !== normalizedImagePath) {
        this.logger.log(`normalize update image path: "${dto.fotoUrl}" -> "${normalizedImagePath ?? ''}"`);
      }

      try {
        const updated = await tx.product.update({ where: { id }, data });
        return this.mapProduct(updated);
      } catch (error) {
        if (!this.isSchemaMismatch(error)) throw error;
        const updated = await tx.product.update({ where: { id }, data });
        return this.mapProduct(updated);
      }
    });
  }

  async remove(user: TenantUser, id: string) {
    this.assertWritable();
    await this.findOne(user, id);
    await this.prisma.product.delete({ where: { id } });
    return { ok: true };
  }

  async purgeAllForDebug(user: TenantUser) {
    this.assertWritable();
    const companyId = requireTenant(user);
    const deleted = await this.prisma.product.deleteMany({ where: { companyId } });
    return {
      ok: true,
      deletedProducts: deleted.count,
    };
  }

  private mapProduct(product: Product) {
    const fotoUrl = this.resolveUrl(product.imagen ?? null);
    return {
      ...product,
      fotoUrl,
      stock: Number(product.stock ?? 0),
      cantidadDisponible: Number(product.stock ?? 0),
      categoria: product.categoria ?? null,
      categoriaNombre: product.categoria ?? null,
    };
  }

  private resolveUrl(url: string | null): string | null {
    if (!url) return null;

    const extractUploadsPath = (value: string): string | null => {
      const normalized = value.replace(/\\/g, '/').trim();
      const marker = '/uploads/';
      const markerIndex = normalized.indexOf(marker);
      if (markerIndex >= 0) {
        return normalized.substring(markerIndex);
      }
      if (normalized.startsWith('uploads/')) {
        return `/${normalized}`;
      }
      if (normalized.startsWith('./uploads/')) {
        return normalized.substring(1);
      }
      return null;
    };

    if (/^https?:\/\//i.test(url)) {
      if (!this.publicBaseUrl) return url;

      try {
        const parsed = new URL(url);
        const publicHost = new URL(this.publicBaseUrl).host.toLowerCase();
        const currentHost = parsed.host.toLowerCase();
        const normalizedPath = extractUploadsPath(parsed.pathname);

        // Preserve fully-qualified URLs to external hosts.
        // Do not rewrite FULLPOS-hosted upload URLs to the API public host unless
        // they are already served from the same domain.
        if (currentHost !== publicHost) {
          return url;
        }

        if (normalizedPath) {
          const query = parsed.search ?? '';
          return `${this.publicBaseUrl}${normalizedPath}${query}`;
        }
      } catch {
        return url;
      }

      return url;
    }

    const uploadsPath = extractUploadsPath(url);
    if (uploadsPath) {
      if (!this.publicBaseUrl) return uploadsPath;
      return `${this.publicBaseUrl}${uploadsPath}`;
    }

    if (!this.publicBaseUrl) return url;
    const normalized = url.startsWith('/') ? url : `/${url}`;
    return `${this.publicBaseUrl}${normalized}`;
  }

  private normalizeImagePathForStorage(raw?: string | null): string | null {
    if (raw === undefined || raw === null) return null;

    const extractUploadsPath = (value: string): string | null => {
      const normalized = value.replace(/\\/g, '/').trim();
      const marker = '/uploads/';
      const markerIndex = normalized.indexOf(marker);
      if (markerIndex >= 0) {
        return normalized.substring(markerIndex);
      }
      if (normalized.startsWith('uploads/')) {
        return `/${normalized}`;
      }
      if (normalized.startsWith('./uploads/')) {
        return normalized.substring(1);
      }
      return null;
    };

    const value = raw.trim();
    if (!value) return null;

    if (/^https?:\/\//i.test(value)) {
      try {
        const parsed = new URL(value);
        const uploadsPath = extractUploadsPath(parsed.pathname);
        if (uploadsPath) return uploadsPath;
        return null;
      } catch {
        return null;
      }
    }

    const uploadsPath = extractUploadsPath(value);
    if (uploadsPath) return uploadsPath;

    return null;
  }

}
