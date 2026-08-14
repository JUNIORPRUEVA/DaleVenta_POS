import crypto from 'node:crypto';

import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Prisma, Role, type Client } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { normalizePhone } from '../common/utils/normalize-phone';
import { ClientLocationFieldsDto } from './dto/client-location-fields.dto';
import { CreateClientDto } from './dto/create-client.dto';
import { ClientsQueryDto } from './dto/clients-query.dto';
import { UpdateClientLocationDto } from './dto/update-client-location.dto';
import { UpdateClientDto } from './dto/update-client.dto';
import { CatalogRealtimeRelayService } from '../products/catalog-realtime-relay.service';
import { requireTenant } from '../auth/tenant-context';

type AuthUser = { id: string; role: Role; companyId?: string | null };

@Injectable()
export class ClientsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: CatalogRealtimeRelayService,
  ) {}

  private static readonly adminLikeRoles = new Set<Role>([Role.ADMIN, Role.ASISTENTE]);

  private static readonly uuidPattern =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

  private ensureValidClientId(id: string) {
    if (ClientsService.uuidPattern.test(id)) {
      return;
    }

    throw new NotFoundException('Client not found');
  }

  private isAdminLike(user: AuthUser) {
    return ClientsService.adminLikeRoles.has(user.role);
  }

  private buildTechnicianServiceOrderWhere(user: AuthUser): Prisma.ServiceOrderWhereInput {
    return {
      OR: [{ assignedToId: user.id }, { createdById: user.id }],
    };
  }

  private combineWhere(...parts: Array<Prisma.ClientWhereInput | null | undefined>): Prisma.ClientWhereInput {
    const filters = parts.filter((part): part is Prisma.ClientWhereInput => part != null);
    if (filters.length === 0) {
      return {};
    }
    if (filters.length === 1) {
      return filters[0];
    }
    return { AND: filters };
  }

  private async findClientOrThrow(companyId: string, id: string) {
    this.ensureValidClientId(id);

    const client = await this.prisma.client.findFirst({
      where: { id, companyId },
    });

    if (!client) {
      throw new NotFoundException('Client not found');
    }

    return client;
  }

  private async findAccessibleClientOrThrow(user: AuthUser, id: string) {
    const companyId = requireTenant(user);
    return this.findClientOrThrow(companyId, id);
  }

  private assertAdmin(user: AuthUser, message: string) {
    if (user.role !== Role.ADMIN) {
      throw new ForbiddenException(message);
    }
  }

  private toNullableNumber(
    value: Prisma.Decimal | number | string | null | undefined,
  ): number | null {
    if (value == null) return null;
    if (value instanceof Prisma.Decimal) return value.toNumber();
    const numeric = Number(value);
    return Number.isFinite(numeric) ? numeric : null;
  }

  private latestDate(...values: Array<Date | string | null | undefined>) {
    let latest: Date | null = null;

    for (const value of values) {
      if (!value) continue;
      const date = value instanceof Date ? value : new Date(value);
      if (Number.isNaN(date.getTime())) continue;
      if (!latest || date.getTime() > latest.getTime()) {
        latest = date;
      }
    }

    return latest;
  }

  private normalizeLocationUrl(value: string | null | undefined): string | null {
    const normalized = value?.trim();
    return normalized ? normalized : null;
  }

  private buildGoogleMapsUrl(latitude: number, longitude: number) {
    return `https://www.google.com/maps?q=${latitude},${longitude}`;
  }

  private extractCoordinatesFromLocationUrl(locationUrl: string) {
    const decoded = decodeURIComponent(locationUrl);
    const patterns = [
      /[?&]q=\+?(-?\d+(?:\.\d+)?),[\s+]*(-?\d+(?:\.\d+)?)/i,
      /\/maps\/search\/\+?(-?\d+(?:\.\d+)?),[\s+]*(-?\d+(?:\.\d+)?)/i,
      /@\+?(-?\d+(?:\.\d+)?),[\s+]*(-?\d+(?:\.\d+)?)/i,
      /\+?(-?\d+(?:\.\d+)?),[\s+]*(-?\d+(?:\.\d+)?)/,
    ];

    for (const pattern of patterns) {
      const match = decoded.match(pattern);
      if (!match) continue;

      const latitude = Number(match[1]);
      const longitude = Number(match[2]);

      if (
        Number.isFinite(latitude) &&
        Number.isFinite(longitude) &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180
      ) {
        return { latitude, longitude };
      }
    }

    return null;
  }

  private resolveLocationPayload(dto: ClientLocationFieldsDto, allowClear = false) {
    const latitude = dto.latitude;
    const longitude = dto.longitude;
    const locationUrlInput = dto.location_url ?? dto.locationUrl;

    const latitudeWasProvided = latitude !== undefined;
    const longitudeWasProvided = longitude !== undefined;
    const locationUrlWasProvided = locationUrlInput !== undefined;

    if (
      !latitudeWasProvided &&
      !longitudeWasProvided &&
      !locationUrlWasProvided
    ) {
      return null;
    }

    const normalizedLatitude = latitude ?? null;
    const normalizedLongitude = longitude ?? null;
    const locationUrl = this.normalizeLocationUrl(locationUrlInput);

    if (
      allowClear &&
      latitudeWasProvided &&
      longitudeWasProvided &&
      locationUrlWasProvided &&
      normalizedLatitude == null &&
      normalizedLongitude == null &&
      locationUrl == null
    ) {
      return {
        latitude: null,
        longitude: null,
        locationUrl: null,
      };
    }

    if ((normalizedLatitude == null) != (normalizedLongitude == null)) {
      throw new BadRequestException('latitude y longitude deben enviarse juntos.');
    }

    let resolvedLatitude = normalizedLatitude;
    let resolvedLongitude = normalizedLongitude;

    // If explicit coordinates are provided, use them and build URL if needed.
    if (resolvedLatitude != null && resolvedLongitude != null) {
      const finalLocationUrl = locationUrl ?? this.buildGoogleMapsUrl(resolvedLatitude, resolvedLongitude);
      return {
        latitude: new Prisma.Decimal(resolvedLatitude),
        longitude: new Prisma.Decimal(resolvedLongitude),
        locationUrl: finalLocationUrl,
      };
    }

    // Only URL provided: try to extract coordinates, but don't reject if it's a
    // short/redirect link (e.g. maps.app.goo.gl). Store the URL as-is in that case.
    if (!locationUrl) {
      throw new BadRequestException('Debe enviar latitude/longitude o location_url.');
    }

    const extracted = this.extractCoordinatesFromLocationUrl(locationUrl);

    if (extracted) {
      return {
        latitude: new Prisma.Decimal(extracted.latitude),
        longitude: new Prisma.Decimal(extracted.longitude),
        locationUrl,
      };
    }

    // URL provided but coordinates could not be extracted (e.g. short share link).
    // Store the URL without coordinates — the client app will open the link directly.
    return {
      latitude: null,
      longitude: null,
      locationUrl,
    };
  }

  private serializeClient(client: Client | null) {
    if (!client) return client;

    const latitude = this.toNullableNumber(client.latitude);
    const longitude = this.toNullableNumber(client.longitude);
    const locationUrl = client.locationUrl ?? null;

    return {
      ...client,
      latitude,
      longitude,
      locationUrl,
      location_url: locationUrl,
    };
  }

  private serializeClientCollection(clients: Client[]) {
    return clients.map((client) => this.serializeClient(client));
  }

  private emitClientEvent(type: string, client?: Client | null, clientId?: string) {
    const serialized = this.serializeClient(client ?? null);
    const resolvedClientId = clientId?.trim() || serialized?.id?.toString().trim() || undefined;
    this.realtime.emitOps('client.event', {
      eventId: crypto.randomUUID(),
      type,
      clientId: resolvedClientId,
      client: serialized,
    });
  }

  private async assertNoActiveDuplicatePhoneNormalized(
    companyId: string,
    phoneNormalized: string,
    excludeClientId?: string,
  ) {
    if (!phoneNormalized) return;

    const existing = await this.prisma.client.findFirst({
      where: {
        isDeleted: false,
        companyId,
        phoneNormalized,
        ...(excludeClientId ? { id: { not: excludeClientId } } : {}),
      },
      select: { id: true },
    });

    if (existing) {
      throw new ConflictException(
        `Ya existe un cliente activo con ese teléfono (${phoneNormalized}).`,
      );
    }
  }

  async create(user: AuthUser, dto: CreateClientDto) {
    const companyId = requireTenant(user);
    const phoneNormalized = normalizePhone(dto.telefono);
    const locationData = this.resolveLocationPayload(dto);
    await this.assertNoActiveDuplicatePhoneNormalized(companyId, phoneNormalized);
    try {
      const client = await this.prisma.client.create({
        data: {
          nombre: dto.nombre,
          telefono: dto.telefono,
          email: dto.email,
          direccion: dto.direccion,
          notas: dto.notas,
          ownerId: user.id,
          companyId,
          phoneNormalized,
          lastActivityAt: new Date(),
          ...(locationData ?? {}),
        },
      });
      this.emitClientEvent('client.created', client);
      return this.serializeClient(client);
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        throw new ConflictException('Ya existe un cliente con ese teléfono');
      }
      throw error;
    }
  }

  async findAll(user: AuthUser, query: ClientsQueryDto) {
    const companyId = requireTenant(user);
    const page = query.page && query.page > 0 ? query.page : 1;
    const pageSize = query.pageSize && query.pageSize > 0 ? query.pageSize : 20;
    const skip = (page - 1) * pageSize;

    const search = query.search?.trim();
    const phone = query.phone?.trim();
    const phoneCandidate = phone || search;
    const phoneNormalizedSearch = normalizePhone(phoneCandidate);
    const baseWhere: Prisma.ClientWhereInput = {
      companyId,
      ...(query.onlyDeleted === true
        ? { isDeleted: true }
        : query.includeDeleted === true
          ? {}
          : { isDeleted: false }),
    };

    const or: Prisma.ClientWhereInput[] = [
      ...(search
        ? [
            { nombre: { contains: search, mode: Prisma.QueryMode.insensitive } },
            { telefono: { contains: search, mode: Prisma.QueryMode.insensitive } },
            { email: { contains: search, mode: Prisma.QueryMode.insensitive } },
          ]
        : []),
      ...(phoneNormalizedSearch ? [{ phoneNormalized: { contains: phoneNormalizedSearch } }] : []),
    ];

    const where = this.combineWhere(baseWhere, or.length ? { OR: or } : null);

    const [items, total] = await Promise.all([
      this.prisma.client.findMany({
        where,
        orderBy: [{ lastActivityAt: 'desc' }, { createdAt: 'desc' }],
        skip,
        take: pageSize,
      }),
      this.prisma.client.count({ where }),
    ]);

    return {
      items: this.serializeClientCollection(items),
      total,
      page,
      pageSize,
      totalPages: Math.max(1, Math.ceil(total / pageSize)),
    };
  }

  async findOne(user: AuthUser, id: string) {
    const client = await this.findAccessibleClientOrThrow(user, id);
    return this.serializeClient(client);
  }

  async update(user: AuthUser, id: string, dto: UpdateClientDto) {
    await this.findAccessibleClientOrThrow(user, id);
    const telefonoWasProvided = Object.prototype.hasOwnProperty.call(dto, 'telefono');
    const phoneNormalized = telefonoWasProvided ? normalizePhone(dto.telefono) : undefined;
    const locationData = this.resolveLocationPayload(dto, true);
    if (telefonoWasProvided) {
      await this.assertNoActiveDuplicatePhoneNormalized(requireTenant(user), phoneNormalized ?? '', id);
    }

    try {
      const client = await this.prisma.client.update({
        where: { id },
        data: {
          nombre: dto.nombre,
          telefono: dto.telefono,
          email: dto.email,
          direccion: dto.direccion,
          notas: dto.notas,
          ...(telefonoWasProvided ? { phoneNormalized: phoneNormalized ?? '' } : {}),
          ...(locationData ?? {}),
        },
      });
      this.emitClientEvent('client.updated', client);
      return this.serializeClient(client);
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        throw new ConflictException('Ya existe un cliente con ese teléfono');
      }
      throw error;
    }
  }

  async updateLocation(user: AuthUser, id: string, dto: UpdateClientLocationDto) {
    const companyId = requireTenant(user);
    await this.findAccessibleClientOrThrow(user, id);
    const locationData = this.resolveLocationPayload(dto, true);

    if (!locationData) {
      throw new BadRequestException('Debe enviar latitude/longitude o location_url.');
    }

    const result = await this.prisma.client.updateMany({
      where: { id, companyId },
      data: locationData,
    });
    if (result.count !== 1) throw new NotFoundException('Cliente no encontrado');
    const client = await this.findAccessibleClientOrThrow(user, id);

    this.emitClientEvent('client.updated', client);

    return this.serializeClient(client);
  }

  async remove(user: AuthUser, id: string) {
    this.assertAdmin(user, 'Only admin can delete clients');
    const companyId = requireTenant(user);
    await this.findAccessibleClientOrThrow(user, id);
    const result = await this.prisma.client.updateMany({ where: { id, companyId }, data: { isDeleted: true } });
    if (result.count !== 1) throw new NotFoundException('Cliente no encontrado');
    const client = await this.findAccessibleClientOrThrow(user, id);
    this.emitClientEvent('client.deleted', client, id);
    return { ok: true };
  }

  async purgeAllForDebug(user: AuthUser) {
    this.assertAdmin(user, 'Only admin can purge clients');
    const companyId = requireTenant(user);

    const clients = await this.prisma.client.findMany({
      where: { companyId },
      select: { id: true },
    });
    const clientIds = clients.map((item) => item.id);

    if (clientIds.length === 0) {
      return {
        ok: true,
        deletedClients: 0,
        deletedQuotations: 0,
        deletedServiceOrders: 0,
        deletedLegacyServices: 0,
      };
    }

    const quotations = await this.prisma.cotizacion.findMany({
      where: { customerId: { in: clientIds }, companyId },
      select: { id: true },
    });
    const quotationIds = quotations.map((item) => item.id);
    const serviceOrderWhere: Prisma.ServiceOrderWhereInput =
      quotationIds.length > 0
        ? {
            OR: [
              { clientId: { in: clientIds } },
              { quotationId: { in: quotationIds } },
            ],
          }
        : { clientId: { in: clientIds } };

    const result = await this.prisma.$transaction(async (tx) => {
      const deletedServiceOrders = await tx.serviceOrder.deleteMany({
        where: serviceOrderWhere,
      });
      const deletedLegacyServices = await tx.service.deleteMany({
        where: { customerId: { in: clientIds } },
      });
      const deletedQuotations = await tx.cotizacion.deleteMany({
        where: { customerId: { in: clientIds }, companyId },
      });
      const deletedClients = await tx.client.deleteMany({
        where: { id: { in: clientIds }, companyId },
      });

      return {
        deletedClients: deletedClients.count,
        deletedQuotations: deletedQuotations.count,
        deletedServiceOrders: deletedServiceOrders.count,
        deletedLegacyServices: deletedLegacyServices.count,
      };
    });

    this.emitClientEvent('client.bulkDeleted');

    return { ok: true, ...result };
  }

  async getProfile(user: AuthUser, id: string) {
    const client = await this.findAccessibleClientOrThrow(user, id);
    const companyId = requireTenant(user);

    const [createdBy, salesAgg, serviceOrdersAgg, legacyServicesAgg, serviceEvidenceAgg, serviceReportsAgg, cotizacionesAgg] = await this.prisma.$transaction([
      this.prisma.user.findUnique({
        where: { id: client.ownerId },
        select: { id: true, nombreCompleto: true, email: true, role: true },
      }),
      this.prisma.sale.aggregate({
        where: { customerId: id, companyId, isDeleted: false },
        _count: { _all: true },
        _sum: { totalSold: true },
        _max: { saleDate: true },
      }),
      this.prisma.serviceOrder.aggregate({
        where: { clientId: id },
        _count: { _all: true },
        _max: { createdAt: true, updatedAt: true, finalizedAt: true },
      }),
      this.prisma.service.aggregate({
        where: { customerId: id, isDeleted: false },
        _count: { _all: true },
        _sum: { quotedAmount: true },
        _max: { createdAt: true, updatedAt: true, completedAt: true },
      }),
      this.prisma.serviceEvidence.aggregate({
        where: { serviceOrder: { clientId: id } },
        _count: { _all: true },
        _max: { createdAt: true },
      }),
      this.prisma.serviceReport.aggregate({
        where: { serviceOrder: { clientId: id } },
        _count: { _all: true },
        _max: { createdAt: true },
      }),
      this.prisma.cotizacion.aggregate({
        where: { customerId: id, companyId },
        _count: { _all: true },
        _sum: { total: true },
        _max: { updatedAt: true },
      }),
    ]);

    const servicesCount = serviceOrdersAgg._count._all + legacyServicesAgg._count._all;
    const serviceReferencesCount =
      serviceEvidenceAgg._count._all + serviceReportsAgg._count._all;
    const lastServiceAt = this.latestDate(
      serviceOrdersAgg._max.finalizedAt,
      serviceOrdersAgg._max.updatedAt,
      serviceOrdersAgg._max.createdAt,
      legacyServicesAgg._max.completedAt,
      legacyServicesAgg._max.updatedAt,
      legacyServicesAgg._max.createdAt,
    );
    const lastReferenceAt = this.latestDate(
      serviceEvidenceAgg._max.createdAt,
      serviceReportsAgg._max.createdAt,
    );
    const lastActivityAt = this.latestDate(
      client.lastActivityAt,
      salesAgg._max.saleDate,
      lastServiceAt,
      lastReferenceAt,
      cotizacionesAgg._max.updatedAt,
    );

    return {
      client: this.serializeClient(client),
      createdBy,
      metrics: {
        salesCount: salesAgg._count._all,
        salesTotal: salesAgg._sum.totalSold,
        lastSaleAt: salesAgg._max.saleDate,
        servicesCount,
        serviceOrdersCount: serviceOrdersAgg._count._all,
        legacyServicesCount: legacyServicesAgg._count._all,
        serviceReferencesCount,
        legacyServicesTotal: legacyServicesAgg._sum.quotedAmount,
        lastServiceAt,
        lastReferenceAt,
        cotizacionesCount: cotizacionesAgg._count._all,
        cotizacionesTotal: cotizacionesAgg._sum.total,
        lastCotizacionAt: cotizacionesAgg._max.updatedAt,
        lastActivityAt,
      },
    };
  }

  async getTimeline(
    user: AuthUser,
    id: string,
    options: { take?: number; before?: string; types?: string },
  ) {
    await this.findAccessibleClientOrThrow(user, id);

    const take = Math.min(Math.max(options.take ?? 100, 1), 300);
    const before = options.before ? new Date(options.before) : new Date();
    if (Number.isNaN(before.getTime())) {
      throw new BadRequestException('before inválido');
    }
    const types = (options.types ?? '')
      .split(',')
      .map((t) => t.trim())
      .filter(Boolean);

    const rows = await this.prisma.$queryRaw<
      Array<{
        eventType: string;
        eventId: string;
        at: Date;
        title: string;
        amount: any | null;
        status: string | null;
        userId: string | null;
        userName: string | null;
        meta: any;
      }>
    >(Prisma.sql`
      SELECT *
      FROM (
        SELECT
          'sale'::text AS "eventType",
          s.id::text AS "eventId",
          s."saleDate" AS "at",
          'Venta'::text AS title,
          s."totalSold" AS amount,
          NULL::text AS status,
          u.id::text AS "userId",
                u."nombreCompleto"::text AS "userName",
          jsonb_build_object('note', s.note) AS meta
        FROM "Sale" s
              JOIN "users" u ON u.id = s."userId"
        WHERE s."customerId" = ${id}::uuid
          AND s."isDeleted" = false
          AND s."saleDate" < ${before}

        UNION ALL

        SELECT
          'cotizacion'::text AS "eventType",
          c.id::text AS "eventId",
          c."createdAt" AS "at",
          'Cotización'::text AS title,
          c.total AS amount,
          CASE
            WHEN qo."hasFinalizedOrder" THEN 'finalizado'
            WHEN qo."hasOrder" THEN 'pendiente'
            ELSE 'pendiente'
          END::text AS status,
          u.id::text AS "userId",
                u."nombreCompleto"::text AS "userName",
          jsonb_build_object(
            'note', c.note,
            'includeItbis', c."includeItbis",
            'hasOrder', COALESCE(qo."hasOrder", false),
            'hasFinalizedOrder', COALESCE(qo."hasFinalizedOrder", false)
          ) AS meta
        FROM "Cotizacion" c
              JOIN "users" u ON u.id = c."createdByUserId"
              LEFT JOIN (
                SELECT
                  so."quotation_id" AS "quotationId",
                  COUNT(*) > 0 AS "hasOrder",
                  BOOL_OR(so.status = 'finalizado') AS "hasFinalizedOrder"
                FROM service_orders so
                GROUP BY so."quotation_id"
              ) qo ON qo."quotationId" = c.id
        WHERE c."customerId" = ${id}::uuid
          AND c."createdAt" < ${before}

        UNION ALL

        SELECT
          'service'::text AS "eventType",
          s.id::text AS "eventId",
          COALESCE(s."finalized_at", s."updated_at", s."created_at") AS "at",
          'Orden de servicio'::text AS title,
          q.total AS amount,
          s.status::text AS status,
          u.id::text AS "userId",
          u."nombreCompleto"::text AS "userName",
          jsonb_build_object(
            'source', 'service_order',
            'serviceOrderId', s.id,
            'quotationId', s."quotation_id",
            'category', s.category::text,
            'serviceType', s."service_type"::text,
            'scheduledFor', s."scheduled_for",
            'finalizedAt', s."finalized_at",
            'technicalNote', s."technical_note",
            'extraRequirements', s."extra_requirements",
            'assignedToName', a."nombreCompleto"
          ) AS meta
        FROM service_orders s
              JOIN "users" u ON u.id = s."created_by"
              LEFT JOIN "users" a ON a.id = s."assigned_to"
              JOIN "Cotizacion" q ON q.id = s."quotation_id"
        WHERE s."client_id" = ${id}::uuid
          AND s."created_at" < ${before}

        UNION ALL

        SELECT
          'service'::text AS "eventType",
          e.id::text AS "eventId",
          e."created_at" AS "at",
          CASE
            WHEN e.type::text LIKE 'referencia_%' THEN 'Referencia de servicio'
            ELSE 'Evidencia de servicio'
          END::text AS title,
          NULL::numeric AS amount,
          so.status::text AS status,
          u.id::text AS "userId",
          u."nombreCompleto"::text AS "userName",
          jsonb_build_object(
            'source', 'service_evidence',
            'serviceOrderId', so.id,
            'quotationId', so."quotation_id",
            'category', so.category::text,
            'serviceType', so."service_type"::text,
            'evidenceType', e.type::text,
            'contentPreview', NULLIF(LEFT(TRIM(COALESCE(e.content, '')), 180), ''),
            'assignedToName', a."nombreCompleto"
          ) AS meta
        FROM service_evidences e
              JOIN service_orders so ON so.id = e."service_order_id"
              JOIN "users" u ON u.id = e."created_by"
              LEFT JOIN "users" a ON a.id = so."assigned_to"
        WHERE so."client_id" = ${id}::uuid
          AND e."created_at" < ${before}

        UNION ALL

        SELECT
          'service'::text AS "eventType",
          r.id::text AS "eventId",
          r."created_at" AS "at",
          CASE
            WHEN r.type = 'servicio_finalizado' THEN 'Reporte de cierre'
            WHEN r.type = 'requerimiento_cliente' THEN 'Requerimiento del cliente'
            ELSE 'Reporte de servicio'
          END::text AS title,
          NULL::numeric AS amount,
          so.status::text AS status,
          u.id::text AS "userId",
          u."nombreCompleto"::text AS "userName",
          jsonb_build_object(
            'source', 'service_report',
            'serviceOrderId', so.id,
            'quotationId', so."quotation_id",
            'category', so.category::text,
            'serviceType', so."service_type"::text,
            'reportType', r.type::text,
            'contentPreview', NULLIF(LEFT(TRIM(COALESCE(r.report, '')), 180), ''),
            'assignedToName', a."nombreCompleto"
          ) AS meta
        FROM service_reports r
              JOIN service_orders so ON so.id = r."service_order_id"
              JOIN "users" u ON u.id = r."created_by"
              LEFT JOIN "users" a ON a.id = so."assigned_to"
        WHERE so."client_id" = ${id}::uuid
          AND r."created_at" < ${before}

        UNION ALL

        SELECT
          'service'::text AS "eventType",
          s.id::text AS "eventId",
          COALESCE(s."completedAt", s."updatedAt", s."createdAt") AS "at",
          CASE
            WHEN s."completedAt" IS NOT NULL THEN 'Servicio completado'
            ELSE 'Servicio registrado'
          END::text AS title,
          s."quotedAmount" AS amount,
          s.status::text AS status,
          u.id::text AS "userId",
          u."nombreCompleto"::text AS "userName",
          jsonb_build_object(
            'source', 'legacy_service',
            'serviceType', s."serviceType"::text,
            'category', s.category,
            'currentPhase', s."currentPhase"::text,
            'paymentStatus', s."paymentStatus",
            'orderNumber', s."orderNumber",
            'titleSnapshot', s.title,
            'contentPreview', NULLIF(LEFT(TRIM(COALESCE(s.description, '')), 180), ''),
            'technicianName', t."nombreCompleto"
          ) AS meta
        FROM "Service" s
              JOIN "users" u ON u.id = s."createdByUserId"
              LEFT JOIN "users" t ON t.id = s."technicianId"
        WHERE s."customerId" = ${id}::uuid
          AND s."isDeleted" = false
          AND s."createdAt" < ${before}

      ) t
      WHERE (cardinality(${types}::text[]) = 0 OR t."eventType" = ANY(${types}::text[]))
      ORDER BY t."at" DESC, t."eventId" DESC
      LIMIT ${take};
    `);

    return { items: rows, before: before.toISOString(), take };
  }
}
