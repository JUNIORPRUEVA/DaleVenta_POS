import { Injectable, Logger, NotFoundException, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Pool } from 'pg';
import {
  classifyFullposImageValue,
  normalizeFullposCatalogImageUrl,
} from './fullpos-product-image.util';
import { DEFAULT_UNIT_OF_MEASURE } from './unit-of-measure.util';
import type { ProductSource } from './product-source.resolver';

type FullposIntegrationProduct = {
  id: string | number;
  sku?: string | null;
  barcode?: string | null;
  code?: string | null;
  codigo?: string | null;
  name?: string | null;
  nombre?: string | null;
  description?: string | null;
  descripcion?: string | null;
  details?: string | null;
  detail?: string | null;
  price?: number | string | null;
  precio?: number | string | null;
  cost?: number | string | null;
  costo?: number | string | null;
  stock?: number | string | null;
  quantity?: number | string | null;
  existencia?: number | string | null;
  category?: string | { name?: string | null; nombre?: string | null } | null;
  categoria?: string | { name?: string | null; nombre?: string | null } | null;
  category_name?: string | null;
  categoriaNombre?: string | null;
  image_url?: string | null;
  imageUrl?: string | null;
  imagen?: string | null;
  fotoUrl?: string | null;
  active?: boolean | null;
  is_active?: boolean | null;
  enabled?: boolean | null;
  status?: string | null;
  estado?: string | null;
  updated_at?: string | null;
  updatedAt?: string | null;
  modifiedAt?: string | null;
  created_at?: string | null;
  createdAt?: string | null;
};

type FullposListResponse = {
  items?: FullposIntegrationProduct[];
  data?: FullposIntegrationProduct[];
  products?: FullposIntegrationProduct[];
  rows?: FullposIntegrationProduct[];
  next_cursor?: string | null;
  nextCursor?: string | null;
};

type RemoteImageValidation = {
  isValid: boolean;
  checkedAt: number;
};

type CatalogProductView = {
  id: string;
  productSource: 'FULLPOS' | 'FULLPOS_DIRECT';
  sourceProductId: string;
  unitOfMeasureId: string;
  unitOfMeasure: typeof DEFAULT_UNIT_OF_MEASURE & {
    id: string;
    category: string;
  };
  nombre: string;
  descripcion: string | null;
  codigo: string | null;
  precio: number;
  costo: number;
  stock: number | null;
  categoria: string | null;
  categoriaNombre: string | null;
  imagen: string | null;
  fotoUrl: string | null;
  originalFotoUrl: string | null;
  activo: boolean;
  estado: string;
  createdAt: string | null;
  updatedAt: string | null;
  fechaActualizacion: string | null;
};

type CatalogProductsResponse = {
  source: 'FULLPOS' | 'FULLPOS_DIRECT';
  readOnly: true;
  total: number;
  fetchedAt: string;
  items: CatalogProductView[];
};

type CatalogProductsOptions = {
  companyId?: string;
  source?: ProductSource;
  fullposCompanyId?: string | null;
};

type CatalogSourceMode = 'direct-db' | 'integration-api';
type ProductsSourcePreference = 'FULLPOS' | 'FULLPOS_DIRECT' | 'LOCAL' | '';

type FullposDbColumnMap = {
  id: string;
  name: string;
  description: string | null;
  code: string | null;
  price: string | null;
  cost: string | null;
  stock: string | null;
  image: string | null;
  active: string | null;
  status: string | null;
  updatedAt: string | null;
  createdAt: string | null;
  deletedAt: string | null;
  company: string;
  categoryName: string | null;
  categoryId: string | null;
};

type FullposCategoryJoin = {
  table: string;
  idColumn: string;
  nameColumn: string;
};

type FullposDirectSchema = {
  productTable: string;
  columnMap: FullposDbColumnMap;
  categoryJoin: FullposCategoryJoin | null;
};

type DirectProductRow = Record<string, unknown>;

@Injectable()
export class CatalogProductsService {
  private readonly logger = new Logger(CatalogProductsService.name);
  private readonly productsSourcePreference: ProductsSourcePreference;
  private readonly fullposBaseUrl: string;
  private readonly fullposIntegrationToken: string;
  private readonly fullposTimeoutMs: number;
  private readonly fullposValidateImages: boolean;
  private readonly fullposDirectDatabaseUrl: string;
  private readonly fullposDirectCompanyId: string;
  private readonly fullposDirectProductsTable: string;
  private readonly fullposDirectCompanyColumn: string;
  private readonly remoteImageValidationCache = new Map<string, RemoteImageValidation>();
  private readonly fullposDirectPool?: Pool;
  private schemaPromise?: Promise<FullposDirectSchema>;

  constructor(private readonly config: ConfigService) {
    const rawSource = (config.get<string>('PRODUCTS_SOURCE') ?? '').trim().toUpperCase();
    this.productsSourcePreference = rawSource === 'FULLPOS' || rawSource === 'FULLPOS_DIRECT' || rawSource === 'LOCAL'
      ? rawSource as ProductsSourcePreference
      : '';
    this.fullposBaseUrl = (config.get<string>('FULLPOS_INTEGRATION_BASE_URL') ?? '')
      .trim()
      .replace(/\/$/, '');
    this.fullposIntegrationToken = (config.get<string>('FULLPOS_INTEGRATION_TOKEN') ?? '').trim();
    this.fullposTimeoutMs = Number(config.get<string>('FULLPOS_INTEGRATION_TIMEOUT_MS') ?? 8000);
    const rawValidateImages = (config.get<string>('FULLPOS_VALIDATE_IMAGES') ?? '').trim().toLowerCase();
    this.fullposDirectDatabaseUrl = (
      config.get<string>('FULLPOS_DIRECT_DATABASE_URL') ??
      config.get<string>('FULLPOS_DB_URL') ??
      ''
    ).trim();
    this.fullposDirectCompanyId = (
      config.get<string>('FULLPOS_DIRECT_COMPANY_ID') ??
      config.get<string>('FULLPOS_COMPANY_ID') ??
      ''
    ).trim();
    this.fullposDirectProductsTable = (config.get<string>('FULLPOS_DIRECT_PRODUCTS_TABLE') ?? '').trim();
    this.fullposDirectCompanyColumn = (config.get<string>('FULLPOS_DIRECT_COMPANY_COLUMN') ?? '').trim();
    this.fullposValidateImages = rawValidateImages.length > 0
      ? ['1', 'true', 'yes', 'on'].includes(rawValidateImages)
      : !this.fullposDirectDatabaseUrl;

    if (this.fullposDirectDatabaseUrl) {
      this.fullposDirectPool = new Pool({
        connectionString: this.fullposDirectDatabaseUrl,
        max: 3,
        idleTimeoutMillis: 15000,
        connectionTimeoutMillis: Math.min(this.fullposTimeoutMs, 5000),
      });
    }
  }

  async findAll(options: CatalogProductsOptions = {}): Promise<CatalogProductsResponse> {
    const mode = this.resolveMode(options.source);

    if (mode === 'direct-db') {
      try {
        const response = await this.findAllFromDirectDb(options);
        this.logger.log(`[catalog-products] source=FULLPOS_DIRECT tenant=${options.companyId ?? 'legacy'} total=${response.total}`);
        return response;
      } catch (error) {
        const message = this.describeDirectDbError(error);
        this.logger.error(`[catalog-products][direct-db] ${message}`);

        if (this.canFallbackToIntegrationApi()) {
          this.logger.warn(
            `[catalog-products][direct-db] falling back to FULLPOS integration API after direct DB failure. error=${message}`,
          );
          const response = await this.findAllFromIntegrationApi(options);
          this.logger.log(`[catalog-products] source=FULLPOS tenant=${options.companyId ?? 'legacy'} total=${response.total} fallback=direct-db`);
          return response;
        }

        throw new ServiceUnavailableException(
          `No se pudo leer el catalogo desde FULLPOS_DIRECT. ${message}`,
        );
      }
    }

    const response = await this.findAllFromIntegrationApi(options);
    this.logger.log(`[catalog-products] source=FULLPOS tenant=${options.companyId ?? 'legacy'} total=${response.total}`);
    return response;
  }

  async findOne(id: string, options: CatalogProductsOptions = {}): Promise<CatalogProductView> {
    const response = await this.findAll(options);
    const found = response.items.find((item) => item.id === id);
    if (!found) {
      throw new NotFoundException('Product not found');
    }
    return found;
  }

  private resolveMode(source?: ProductSource): CatalogSourceMode {
    const preference = source ?? this.productsSourcePreference;
    if (preference === 'FULLPOS') {
      return 'integration-api';
    }

    if (preference === 'FULLPOS_DIRECT') {
      return this.fullposDirectDatabaseUrl ? 'direct-db' : 'integration-api';
    }

    if (this.fullposDirectDatabaseUrl) {
      return 'direct-db';
    }

    return 'integration-api';
  }

  private canFallbackToIntegrationApi(): boolean {
    return this.fullposBaseUrl.length > 0 && this.fullposIntegrationToken.length > 0;
  }

  private async findAllFromDirectDb(options: CatalogProductsOptions): Promise<CatalogProductsResponse> {
    const fullposCompanyId = this.resolveFullposCompanyId(options);
    this.ensureDirectDbConfigured(fullposCompanyId);

    const schema = await this.getDirectSchema();
    const rows = await this.queryDirectProducts(schema, fullposCompanyId);
    const imageStats = { empty: 0, relative: 0, absolute: 0 };

    const mapped = await Promise.all(rows.map(async (row) => {
      const rawImage = this.pickString(row.raw_image, row.imagen, row.fotoUrl);
      imageStats[classifyFullposImageValue(rawImage)] += 1;
      const imageUrl = await this.validateFullposImageUrl(
        normalizeFullposCatalogImageUrl(rawImage, this.fullposBaseUrl),
      );
      const activo = this.asBoolean(row.activo, row.estado);
      const updatedAt = this.pickString(row.updatedAt, row.fechaActualizacion);
      const categoria = this.pickString(row.categoria, row.categoriaNombre);

      return {
        id: this.pickString(row.id)?.trim() ?? '',
        productSource: 'FULLPOS_DIRECT',
        sourceProductId: this.pickString(row.id)?.trim() ?? '',
        unitOfMeasureId: 'UNIT',
        unitOfMeasure: this.defaultExternalUnitOfMeasure(),
        nombre: this.pickString(row.nombre) ?? 'Producto sin nombre',
        descripcion: this.pickString(row.descripcion),
        codigo: this.pickString(row.codigo),
        precio: this.asNumber(row.precio),
        costo: this.asNumber(row.costo),
        stock: this.asNullableNumber(row.stock),
        categoria,
        categoriaNombre: categoria,
        imagen: imageUrl,
        fotoUrl: imageUrl,
        originalFotoUrl: imageUrl,
        activo,
        estado: activo ? 'ACTIVO' : 'INACTIVO',
        createdAt: this.pickString(row.createdAt),
        updatedAt,
        fechaActualizacion: updatedAt,
      } satisfies CatalogProductView;
    }));

    const activeItems = mapped.filter((item) => item.activo);

    this.logger.log(
      `[catalog-products][direct-db] company=${fullposCompanyId} raw=${rows.length} active=${activeItems.length} images(empty=${imageStats.empty},relative=${imageStats.relative},absolute=${imageStats.absolute}) table=${schema.productTable}`,
    );

    return {
      source: 'FULLPOS_DIRECT',
      readOnly: true,
      total: activeItems.length,
      fetchedAt: new Date().toISOString(),
      items: activeItems,
    };
  }

  private async findAllFromIntegrationApi(options: CatalogProductsOptions): Promise<CatalogProductsResponse> {
    this.ensureIntegrationConfigured();

    const rawItems = await this.fetchAllRawProducts(options.fullposCompanyId);
    const imageStats = { empty: 0, relative: 0, absolute: 0 };

    const mapped = await Promise.all(
      rawItems.map(async (item) => {
        const rawImage = this.pickString(item.image_url, item.imageUrl, item.imagen, item.fotoUrl);
        imageStats[classifyFullposImageValue(rawImage)] += 1;
        return this.mapIntegrationProduct(item, rawImage);
      }),
    );

    const activeItems = mapped.filter((item): item is CatalogProductView => item != null && item.activo);

    this.logger.log(
      `[catalog-products][integration-api] company=${options.fullposCompanyId ?? 'legacy'} raw=${rawItems.length} active=${activeItems.length} images(empty=${imageStats.empty},relative=${imageStats.relative},absolute=${imageStats.absolute})`,
    );

    return {
      source: 'FULLPOS',
      readOnly: true,
      total: activeItems.length,
      fetchedAt: new Date().toISOString(),
      items: activeItems,
    };
  }

  private ensureIntegrationConfigured() {
    if (!this.fullposBaseUrl) {
      throw new ServiceUnavailableException('FULLPOS_INTEGRATION_BASE_URL no está configurado');
    }
    if (!this.fullposIntegrationToken) {
      throw new ServiceUnavailableException('FULLPOS_INTEGRATION_TOKEN no está configurado');
    }
  }

  private ensureDirectDbConfigured(fullposCompanyId = this.fullposDirectCompanyId) {
    this.ensureDirectDbConnectionConfigured();
    if (!fullposCompanyId) {
      throw new ServiceUnavailableException(
        'La empresa no tiene mapeo FULLPOS_DIRECT configurado',
      );
    }
  }

  private ensureDirectDbConnectionConfigured() {
    if (!this.fullposDirectDatabaseUrl) {
      throw new ServiceUnavailableException('FULLPOS_DIRECT_DATABASE_URL no está configurado');
    }
    if (!this.fullposDirectPool) {
      throw new ServiceUnavailableException('No se pudo inicializar la conexión directa a FULLPOS');
    }
  }

  private async getDirectSchema(): Promise<FullposDirectSchema> {
    if (!this.schemaPromise) {
      this.schemaPromise = this.detectDirectSchema();
    }
    return this.schemaPromise;
  }

  private async detectDirectSchema(): Promise<FullposDirectSchema> {
    this.ensureDirectDbConnectionConfigured();

    const pool = this.fullposDirectPool!;
    const columnRows = await pool.query<{
      table_name: string;
      column_name: string;
    }>(`
      select table_name, column_name
      from information_schema.columns
      where table_schema = 'public'
      order by table_name, ordinal_position
    `);

    const columnsByTable = new Map<string, string[]>();
    for (const row of columnRows.rows) {
      const key = row.table_name;
      const list = columnsByTable.get(key) ?? [];
      list.push(row.column_name);
      columnsByTable.set(key, list);
    }

    const tableCandidates = this.rankProductTables(columnsByTable);
    if (tableCandidates.length === 0) {
      throw new ServiceUnavailableException('No se pudo detectar la tabla de productos en FULLPOS');
    }

    const productTable = this.fullposDirectProductsTable || tableCandidates[0];
    const productColumns = columnsByTable.get(productTable) ?? [];
    const columnMap = this.buildColumnMap(productColumns);
    if (!columnMap.id || !columnMap.name || !columnMap.company) {
      throw new ServiceUnavailableException(
        `No se pudo mapear id/nombre/empresa en la tabla de productos FULLPOS (${productTable})`,
      );
    }

    const categoryJoin = await this.detectCategoryJoin(pool, productTable, columnMap.categoryId, columnsByTable);

    this.logger.log(
      `[catalog-products][direct-db] schema table=${productTable} companyColumn=${columnMap.company} categoryJoin=${categoryJoin?.table ?? 'none'}`,
    );

    return {
      productTable,
      columnMap,
      categoryJoin,
    };
  }

  private rankProductTables(columnsByTable: Map<string, string[]>): string[] {
    const preferredTableNames = ['products', 'product', 'items', 'inventory_products'];
    const candidates = Array.from(columnsByTable.entries())
      .map(([table, columns]) => ({
        table,
        columns,
        score: this.scoreProductTable(table, columns),
      }))
      .filter((item) => item.score > 0)
      .sort((a, b) => {
        if (b.score !== a.score) return b.score - a.score;
        const aPreferred = preferredTableNames.indexOf(a.table);
        const bPreferred = preferredTableNames.indexOf(b.table);
        if (aPreferred >= 0 || bPreferred >= 0) {
          return (aPreferred === -1 ? 999 : aPreferred) - (bPreferred === -1 ? 999 : bPreferred);
        }
        return a.table.localeCompare(b.table);
      })
      .map((item) => item.table);

    return candidates;
  }

  private scoreProductTable(table: string, columns: string[]): number {
    const loweredTable = table.toLowerCase();
    const loweredColumns = new Set(columns.map((column) => column.toLowerCase()));
    let score = 0;

    if (loweredTable === 'products') score += 100;
    if (loweredTable.includes('product')) score += 40;
    if (loweredColumns.has('name') || loweredColumns.has('nombre')) score += 20;
    if (loweredColumns.has('price') || loweredColumns.has('precio')) score += 20;
    if (loweredColumns.has('company_id') || loweredColumns.has('owner_id')) score += 30;
    if (loweredColumns.has('updated_at') || loweredColumns.has('updatedat')) score += 10;
    if (loweredColumns.has('stock')) score += 10;
    if (loweredColumns.has('image_url') || loweredColumns.has('imagen')) score += 10;

    return score;
  }

  private buildColumnMap(columns: string[]): FullposDbColumnMap {
    return {
      id: this.pickColumn(columns, ['id']) ?? '',
      name: this.pickColumn(columns, ['name', 'nombre']) ?? '',
      description: this.pickColumn(columns, ['description', 'descripcion', 'details', 'detail']),
      code: this.pickColumn(columns, ['sku', 'code', 'codigo', 'barcode']),
      price: this.pickColumn(columns, ['price', 'precio']),
      cost: this.pickColumn(columns, ['cost', 'costo']),
      stock: this.pickColumn(columns, ['stock', 'quantity', 'existencia']),
      image: this.pickColumn(columns, [
        'image_url',
        'imageurl',
        'imagen',
        'image',
        'foto_url',
        'fotoUrl',
        'photo_url',
        'thumbnail_url',
      ]),
      active: this.pickColumn(columns, ['active', 'activo', 'is_active', 'enabled']),
      status: this.pickColumn(columns, ['status', 'estado']),
      updatedAt: this.pickColumn(columns, ['updated_at', 'updatedat', 'modified_at', 'modifiedat']),
      createdAt: this.pickColumn(columns, ['created_at', 'createdat']),
      deletedAt: this.pickColumn(columns, ['deleted_at', 'deletedat']),
      company:
        this.fullposDirectCompanyColumn ||
        this.pickColumn(columns, ['company_id', 'owner_id', 'tenant_id', 'business_id', 'companyid', 'ownerid']) ||
        '',
      categoryName: this.pickColumn(columns, ['category', 'categoria', 'category_name', 'categorianombre']),
      categoryId: this.pickColumn(columns, ['category_id', 'categoria_id', 'categoryid', 'categoriaid']),
    };
  }

  private pickColumn(columns: string[], candidates: string[]): string | null {
    const byLower = new Map(columns.map((column) => [column.toLowerCase(), column]));
    for (const candidate of candidates) {
      const found = byLower.get(candidate.toLowerCase());
      if (found) {
        return found;
      }
    }
    return null;
  }

  private async detectCategoryJoin(
    pool: Pool,
    productTable: string,
    categoryIdColumn: string | null,
    columnsByTable: Map<string, string[]>,
  ): Promise<FullposCategoryJoin | null> {
    if (!categoryIdColumn) {
      return null;
    }

    const fkRows = await pool.query<{
      column_name: string;
      foreign_table_name: string;
      foreign_column_name: string;
    }>(`
      select
        kcu.column_name,
        ccu.table_name as foreign_table_name,
        ccu.column_name as foreign_column_name
      from information_schema.table_constraints tc
      join information_schema.key_column_usage kcu
        on tc.constraint_name = kcu.constraint_name
       and tc.table_schema = kcu.table_schema
      join information_schema.constraint_column_usage ccu
        on ccu.constraint_name = tc.constraint_name
       and ccu.table_schema = tc.table_schema
      where tc.constraint_type = 'FOREIGN KEY'
        and tc.table_schema = 'public'
        and tc.table_name = $1
        and kcu.column_name = $2
    `, [productTable, categoryIdColumn]);

    const fk = fkRows.rows[0];
    if (!fk) {
      return null;
    }

    const categoryColumns = columnsByTable.get(fk.foreign_table_name) ?? [];
    const nameColumn = this.pickColumn(categoryColumns, ['name', 'nombre', 'title', 'descripcion']);
    if (!nameColumn) {
      return null;
    }

    return {
      table: fk.foreign_table_name,
      idColumn: fk.foreign_column_name,
      nameColumn,
    };
  }

  private async queryDirectProducts(schema: FullposDirectSchema, fullposCompanyId: string): Promise<DirectProductRow[]> {
    this.ensureDirectDbConfigured(fullposCompanyId);

    const pool = this.fullposDirectPool!;
    const p = 'p';
    const c = 'c';
    const selectParts = [
      `${p}.${this.q(schema.columnMap.id)}::text as id`,
      `${p}.${this.q(schema.columnMap.name)}::text as nombre`,
      this.selectOrNull(p, schema.columnMap.description, 'descripcion'),
      this.selectOrNull(p, schema.columnMap.code, 'codigo'),
      this.selectOrNull(p, schema.columnMap.price, 'precio'),
      this.selectOrNull(p, schema.columnMap.cost, 'costo'),
      this.selectOrNull(p, schema.columnMap.stock, 'stock'),
      this.selectOrNull(p, schema.columnMap.image, 'raw_image'),
      this.selectOrNull(p, schema.columnMap.active, 'activo'),
      this.selectOrNull(p, schema.columnMap.status, 'estado'),
      this.selectOrNull(p, schema.columnMap.createdAt, 'createdAt'),
      this.selectOrNull(p, schema.columnMap.updatedAt, 'updatedAt'),
      this.selectOrNull(p, schema.columnMap.updatedAt, 'fechaActualizacion'),
      schema.columnMap.categoryName
        ? this.selectOrNull(p, schema.columnMap.categoryName, 'categoria')
        : schema.categoryJoin
          ? `${c}.${this.q(schema.categoryJoin.nameColumn)}::text as categoria`
          : `null::text as categoria`,
      schema.columnMap.categoryName
        ? this.selectOrNull(p, schema.columnMap.categoryName, 'categoriaNombre')
        : schema.categoryJoin
          ? `${c}.${this.q(schema.categoryJoin.nameColumn)}::text as "categoriaNombre"`
          : `null::text as "categoriaNombre"`,
    ];

    const joinClause = schema.categoryJoin && schema.columnMap.categoryId
      ? ` left join ${this.table(schema.categoryJoin.table)} ${c} on ${p}.${this.q(schema.columnMap.categoryId)} = ${c}.${this.q(schema.categoryJoin.idColumn)}`
      : '';

    const whereParts = [`${p}.${this.q(schema.columnMap.company)}::text = $1`];
    if (schema.columnMap.deletedAt) {
      whereParts.push(`${p}.${this.q(schema.columnMap.deletedAt)} is null`);
    }

    const orderByColumn = schema.columnMap.updatedAt ?? schema.columnMap.name;

    const query = `
      select
        ${selectParts.join(',\n        ')}
      from ${this.table(schema.productTable)} ${p}
      ${joinClause}
      where ${whereParts.join(' and ')}
      order by ${p}.${this.q(orderByColumn)} desc nulls last
      limit 5000
    `;

    const result = await pool.query(query, [fullposCompanyId]);
    return result.rows as DirectProductRow[];
  }

  private q(identifier: string): string {
    return `"${identifier.replace(/"/g, '""')}"`;
  }

  private table(identifier: string): string {
    return `public.${this.q(identifier)}`;
  }

  private selectOrNull(alias: string, column: string | null, output: string): string {
    if (!column) {
      return `null::text as ${this.q(output)}`;
    }
    return `${alias}.${this.q(column)}::text as ${this.q(output)}`;
  }

  private async fetchAllRawProducts(fullposCompanyId?: string | null): Promise<FullposIntegrationProduct[]> {
    const items: FullposIntegrationProduct[] = [];
    let cursor: string | null = null;

    for (let page = 0; page < 50; page += 1) {
      const url = new URL(`${this.fullposBaseUrl}/api/integrations/products`);
      url.searchParams.set('limit', '500');
      if (fullposCompanyId) {
        url.searchParams.set('companyId', fullposCompanyId);
      }
      if (cursor) {
        url.searchParams.set('cursor', cursor);
      }

      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), this.fullposTimeoutMs);

      try {
        const response = await fetch(url.toString(), {
          method: 'GET',
          headers: {
            Accept: 'application/json',
            Authorization: `Bearer ${this.fullposIntegrationToken}`,
            ...(fullposCompanyId ? { 'X-Fullpos-Company-Id': fullposCompanyId } : {}),
          },
          signal: controller.signal,
        });

        if (!response.ok) {
          const text = await response.text().catch(() => '');
          this.logger.warn(
            `[catalog-products] upstream failed status=${response.status} body=${text.substring(0, 200)}`,
          );
          throw new ServiceUnavailableException('No se pudieron cargar productos desde FULLPOS');
        }

        const payload = (await response.json()) as FullposListResponse;
        const batch = this.extractRows(payload);
        items.push(...batch);
        cursor = payload.next_cursor ?? payload.nextCursor ?? null;
        if (!cursor) {
          break;
        }
      } finally {
        clearTimeout(timeout);
      }
    }

    return items;
  }

  private extractRows(payload: FullposListResponse): FullposIntegrationProduct[] {
    const candidates = [payload.items, payload.data, payload.products, payload.rows];
    for (const candidate of candidates) {
      if (Array.isArray(candidate)) {
        return candidate;
      }
    }
    return [];
  }

  private async mapIntegrationProduct(
    item: FullposIntegrationProduct,
    rawImage: string | null,
  ): Promise<CatalogProductView | null> {
    const imageUrl = await this.validateFullposImageUrl(
      normalizeFullposCatalogImageUrl(rawImage, this.fullposBaseUrl),
    );
    const updatedAt = this.pickString(item.updated_at, item.updatedAt, item.modifiedAt);
    const categoria = this.extractCategory(item.category, item.categoria, item.category_name, item.categoriaNombre);
    const activo = this.resolveActive(item);
    const estado = activo ? 'ACTIVO' : 'INACTIVO';

    return {
      id: this.pickString(item.id)?.trim() ?? '',
      productSource: 'FULLPOS',
      sourceProductId: this.pickString(item.id)?.trim() ?? '',
      unitOfMeasureId: 'UNIT',
      unitOfMeasure: this.defaultExternalUnitOfMeasure(),
      nombre: this.pickString(item.name, item.nombre) ?? 'Producto sin nombre',
      descripcion: this.pickString(item.description, item.descripcion, item.details, item.detail),
      codigo: this.pickString(item.sku, item.code, item.codigo, item.barcode),
      precio: this.asNumber(item.price, item.precio),
      costo: this.asNumber(item.cost, item.costo),
      stock: this.asNullableNumber(item.stock, item.quantity, item.existencia),
      categoria,
      categoriaNombre: categoria,
      imagen: imageUrl,
      fotoUrl: imageUrl,
      originalFotoUrl: imageUrl,
      activo,
      estado,
      createdAt: this.pickString(item.created_at, item.createdAt),
      updatedAt,
      fechaActualizacion: updatedAt,
    };
  }

  private pickString(...values: unknown[]): string | null {
    for (const value of values) {
      if (value == null) continue;
      const text = String(value).trim();
      if (!text || text.toLowerCase() === 'null' || text.toLowerCase() === 'undefined') {
        continue;
      }
      return text;
    }
    return null;
  }

  private asNumber(...values: unknown[]): number {
    const value = this.asNullableNumber(...values);
    return value ?? 0;
  }

  private asNullableNumber(...values: unknown[]): number | null {
    for (const value of values) {
      if (value == null) continue;
      if (typeof value === 'number' && Number.isFinite(value)) {
        return value;
      }
      const parsed = Number(String(value).replace(',', '.').trim());
      if (Number.isFinite(parsed)) {
        return parsed;
      }
    }
    return null;
  }

  private asBoolean(...values: unknown[]): boolean {
    for (const value of values) {
      if (typeof value === 'boolean') {
        return value;
      }
      if (typeof value === 'number') {
        return value !== 0;
      }
      if (typeof value === 'string') {
        const normalized = value.trim().toLowerCase();
        if (!normalized) continue;
        if (['true', '1', 'yes', 'si', 'activo', 'active', 'enabled'].includes(normalized)) {
          return true;
        }
        if (['false', '0', 'no', 'inactivo', 'inactive', 'disabled', 'deleted'].includes(normalized)) {
          return false;
        }
      }
    }
    return true;
  }

  private extractCategory(...values: unknown[]): string | null {
    for (const value of values) {
      if (value == null) continue;
      if (typeof value === 'string') {
        const text = value.trim();
        if (text) return text;
        continue;
      }
      if (typeof value === 'object') {
        const candidate = value as { name?: unknown; nombre?: unknown };
        const text = this.pickString(candidate.name, candidate.nombre);
        if (text != null) return text;
      }
    }
    return null;
  }

  private resolveActive(item: FullposIntegrationProduct): boolean {
    return this.asBoolean(item.active, item.is_active, item.enabled, item.status, item.estado);
  }

  private resolveFullposCompanyId(options: CatalogProductsOptions): string {
    const companyId = (options.fullposCompanyId ?? this.fullposDirectCompanyId).trim();
    if (!companyId) {
      throw new ServiceUnavailableException(
        'La empresa no tiene mapeo de compañía FULLPOS configurado.',
      );
    }
    return companyId;
  }

  private defaultExternalUnitOfMeasure() {
    return {
      id: 'UNIT',
      category: 'COUNT',
      ...DEFAULT_UNIT_OF_MEASURE,
    };
  }

  private async validateFullposImageUrl(url: string | null): Promise<string | null> {
    const candidate = (url ?? '').trim();
    
    // Empty URL → null
    if (!candidate) {
      return null;
    }

    // If URL is not absolute (no protocol), return it as-is
    // The app or proxy will handle relative paths or the browser will use it as-is
    if (!/^https?:\/\//i.test(candidate)) {
      this.logger.debug(`[catalog-products][image] returning relative/partial url: ${candidate}`);
      return candidate;
    }

    // Remote validation disabled → return as-is
    if (!this.fullposValidateImages) {
      return candidate;
    }

    // Parse URLs for validation
    let parsedUrl: URL;
    let fullposUrl: URL;
    try {
      parsedUrl = new URL(candidate);
      fullposUrl = new URL(this.fullposBaseUrl);
    } catch {
      // Invalid URL format → return anyway (let downstream handle it)
      this.logger.debug(`[catalog-products][image] url parse failed but returning: ${candidate}`);
      return candidate;
    }

    const sameFullposHost = parsedUrl.host.toLowerCase() === fullposUrl.host.toLowerCase();
    const looksLikeUpload = parsedUrl.pathname.toLowerCase().includes('/uploads/');
    
    // If not from same FULLPOS host or not an upload path, return anyway
    // (might be external CDN or different structure)
    if (!sameFullposHost || !looksLikeUpload) {
      this.logger.debug(
        `[catalog-products][image] url not from FULLPOS uploads but keeping: ${candidate}`,
      );
      return candidate;
    }

    // Now do remote validation only for FULLPOS upload URLs
    const cached = this.remoteImageValidationCache.get(candidate);
    const now = Date.now();
    if (cached) {
      const ttlMs = cached.isValid ? 30 * 60 * 1000 : 5 * 60 * 1000; // 30min valid, 5min invalid
      if (now - cached.checkedAt < ttlMs) {
        // Return cached result (but ALWAYS return the URL, never null)
        return candidate;
      }
    }

    // Remote check with timeout
    const controller = new AbortController();
    const timeout = setTimeout(
      () => controller.abort(),
      Math.min(this.fullposTimeoutMs, 3000),
    );

    try {
      let response = await fetch(candidate, {
        method: 'HEAD',
        headers: { Accept: 'image/*,*/*;q=0.8' },
        signal: controller.signal,
      });

      // If HEAD not allowed, try GET
      if (response.status === 405 || response.status === 501) {
        response = await fetch(candidate, {
          method: 'GET',
          headers: { Accept: 'image/*,*/*;q=0.8' },
          signal: controller.signal,
        });
      }

      const contentType = (response.headers.get('content-type') ?? '').toLowerCase();
      const isValid = response.ok && contentType.startsWith('image/');
      
      // Cache result
      this.remoteImageValidationCache.set(candidate, {
        isValid,
        checkedAt: now,
      });
      
      // Always return the URL (even if validation failed)
      if (!isValid) {
        this.logger.warn(
          `[catalog-products][image] validation issue status=${response.status} type=${contentType || 'unknown'} but keeping url: ${candidate}`,
        );
      }
      return candidate;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      
      // Cache as invalid but STILL RETURN THE URL
      this.remoteImageValidationCache.set(candidate, {
        isValid: false,
        checkedAt: now,
      });
      
      this.logger.warn(
        `[catalog-products][image] validation error but keeping url error=${message} url=${candidate}`,
      );
      return candidate;
    } finally {
      clearTimeout(timeout);
    }
  }

  private describeDirectDbError(error: unknown): string {
    if (error instanceof ServiceUnavailableException) {
      const response = error.getResponse();
      if (typeof response === 'string' && response.trim()) {
        return response;
      }
      if (
        response &&
        typeof response === 'object' &&
        'message' in response &&
        typeof (response as { message?: unknown }).message === 'string'
      ) {
        return (response as { message: string }).message;
      }
    }

    if (error instanceof Error) {
      return error.message;
    }

    return 'Revisa FULLPOS_DIRECT_DATABASE_URL, la red interna de EasyPanel y las variables FULLPOS_DIRECT_PRODUCTS_TABLE/FULLPOS_DIRECT_COMPANY_COLUMN.';
  }
}
