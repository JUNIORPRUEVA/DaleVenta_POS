import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ProductsService } from '../products/products.service';
import { UpdateWebsiteProductDto } from './dto/update-website-product.dto';

type WebsiteOverrideRow = {
  product_id: string;
  title: string | null;
  description: string | null;
  category: string | null;
  image_url: string | null;
  extra_image_urls: unknown;
  visible: boolean;
  featured: boolean;
  sort_order: number;
  seo_title: string | null;
  seo_description: string | null;
  updated_at: Date;
};

@Injectable()
export class WebsiteService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly products: ProductsService,
  ) {}

  async getAdminProducts() {
    const [products, overrides] = await Promise.all([
      this.products.findAll(),
      this.getOverrides(),
    ]);
    return {
      total: products.length,
      items: products.map((product) => this.mergeProduct(product, overrides.get(String(product.id)), true)),
    };
  }

  async getPublicStorefront() {
    const [products, overrides] = await Promise.all([
      this.products.findAll(),
      this.getOverrides(),
    ]);
    const items = products
      .map((product) => this.mergeProduct(product, overrides.get(String(product.id)), false))
      .filter((product) => product.visible)
      .sort((a, b) => {
        if (a.sortOrder !== b.sortOrder) return a.sortOrder - b.sortOrder;
        return a.name.localeCompare(b.name);
      });

    return {
      company: {
        name: 'FULLTECH SRL',
        tradeName: 'FULLTECH',
        serviceZone: 'Higüey, La Altagracia, República Dominicana',
      },
      categories: Array.from(new Set(items.map((item) => item.category).filter(Boolean))).sort(),
      featured: items.filter((item) => item.featured).slice(0, 8),
      products: items,
      updatedAt: new Date().toISOString(),
    };
  }

  async updateProduct(productId: string, dto: UpdateWebsiteProductDto) {
    const extraImageUrls = Array.isArray(dto.extraImageUrls)
      ? dto.extraImageUrls.map((url) => `${url}`.trim()).filter(Boolean)
      : [];

    await this.prisma.$executeRaw`
      INSERT INTO website_product_overrides (
        product_id,
        title,
        description,
        category,
        image_url,
        extra_image_urls,
        visible,
        featured,
        sort_order,
        seo_title,
        seo_description
      ) VALUES (
        ${productId},
        ${this.clean(dto.title)},
        ${this.clean(dto.description)},
        ${this.clean(dto.category)},
        ${this.clean(dto.imageUrl)},
        ${extraImageUrls.length ? JSON.stringify(extraImageUrls) : null}::jsonb,
        ${dto.visible ?? true},
        ${dto.featured ?? false},
        ${dto.sortOrder ?? 0},
        ${this.clean(dto.seoTitle)},
        ${this.clean(dto.seoDescription)}
      )
      ON CONFLICT (product_id) DO UPDATE SET
        title = EXCLUDED.title,
        description = EXCLUDED.description,
        category = EXCLUDED.category,
        image_url = EXCLUDED.image_url,
        extra_image_urls = EXCLUDED.extra_image_urls,
        visible = EXCLUDED.visible,
        featured = EXCLUDED.featured,
        sort_order = EXCLUDED.sort_order,
        seo_title = EXCLUDED.seo_title,
        seo_description = EXCLUDED.seo_description
    `;

    const products = await this.getAdminProducts();
    return products.items.find((item) => item.id === productId) ?? { ok: true };
  }

  private clean(value?: string | null) {
    const text = (value ?? '').trim();
    return text.length ? text : null;
  }

  private async getOverrides() {
    const rows = await this.prisma.$queryRaw<WebsiteOverrideRow[]>`
      SELECT
        product_id,
        title,
        description,
        category,
        image_url,
        extra_image_urls,
        visible,
        featured,
        sort_order,
        seo_title,
        seo_description,
        updated_at
      FROM website_product_overrides
    `;
    return new Map(rows.map((row) => [row.product_id, row]));
  }

  private mergeProduct(product: any, override?: WebsiteOverrideRow, includeBase = false) {
    const baseCategory = product.categoriaNombre ?? product.categoria ?? 'Sin categoría';
    const extraImageUrls = Array.isArray(override?.extra_image_urls)
      ? override?.extra_image_urls
      : [];
    const merged = {
      id: String(product.id),
      name: override?.title?.trim() || product.nombre || 'Producto sin nombre',
      baseName: product.nombre || '',
      description: override?.description?.trim() || product.descripcion || '',
      baseDescription: product.descripcion || '',
      code: product.codigo ?? null,
      category: override?.category?.trim() || baseCategory,
      baseCategory,
      price: Number(product.precio ?? 0),
      stock: product.stock == null ? null : Number(product.stock),
      image: override?.image_url?.trim() || product.fotoUrl || product.imagen || null,
      baseImage: product.fotoUrl || product.imagen || null,
      extraImages: extraImageUrls,
      visible: override?.visible ?? true,
      featured: override?.featured ?? false,
      sortOrder: override?.sort_order ?? 0,
      seoTitle: override?.seo_title ?? null,
      seoDescription: override?.seo_description ?? null,
      updatedAt: override?.updated_at?.toISOString?.() ?? product.updatedAt ?? product.createdAt ?? null,
    };

    return includeBase ? merged : {
      id: merged.id,
      name: merged.name,
      description: merged.description,
      code: merged.code,
      category: merged.category,
      price: merged.price,
      stock: merged.stock,
      image: merged.image,
      extraImages: merged.extraImages,
      visible: merged.visible,
      featured: merged.featured,
      sortOrder: merged.sortOrder,
      seoTitle: merged.seoTitle,
      seoDescription: merged.seoDescription,
      updatedAt: merged.updatedAt,
    };
  }
}
