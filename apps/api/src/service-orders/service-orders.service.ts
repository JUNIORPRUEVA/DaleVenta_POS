import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  Prisma,
  ServiceEvidenceType,
  ServiceOrderCategory,
  ServiceOrderStatus,
  ServiceOrderType,
  ServiceReportType,
} from '@prisma/client';
import { requireTenant, type TenantUser, isAdminLike } from '../auth/tenant-context';
import {
  normalizePagePagination,
  toPageResult,
} from '../common/pagination/page-pagination';
import { PrismaService } from '../prisma/prisma.service';
import {
  SERVICE_ORDER_DEFAULT_STATUSES,
  SERVICE_ORDER_TRANSITIONS,
} from './service-orders.constants';
import {
  CloneServiceOrderDto,
  CreateServiceEvidenceDto,
  CreateServiceOrderDto,
  CreateServiceReportDto,
  UpdateServiceOrderDto,
} from './dto/service-order.dto';
import { ServiceOrdersQueryDto } from './dto/service-orders-query.dto';

type RequestUser = TenantUser;

type ServiceOrdersSyncCursor = {
  updatedAt: string;
  id: string;
};

type ServiceOrderSyncTombstone = {
  id: string;
  deletedAt: string | null;
  reason: 'cancelled' | 'deleted';
  version: string | null;
};

const includeRelations = {
  client: true,
  statusHistory: {
    orderBy: { changedAt: 'asc' as const },
  },
  evidences: {
    orderBy: { createdAt: 'asc' as const },
  },
  reports: {
    orderBy: { createdAt: 'asc' as const },
  },
};

@Injectable()
export class ServiceOrdersService {
  constructor(private readonly prisma: PrismaService) {}

  async list(user: RequestUser, query: ServiceOrdersQueryDto) {
    const companyId = requireTenant(user);
    const pagination = normalizePagePagination({
      page: query.page,
      limit: query.limit,
    });
    const where = this.buildListWhere(user, companyId, query);
    const rows = await this.prisma.serviceOrder.findMany({
      where,
      include: includeRelations,
      orderBy: [
        { lastStatusChangedAt: 'desc' },
        { createdAt: 'desc' },
        { id: 'desc' },
      ],
      skip: pagination.skip,
      take: pagination.take,
    });
    return toPageResult(rows.map((row) => this.toDto(row)), pagination);
  }

  async sync(
    user: RequestUser,
    query: { cursor?: string | null; limit?: number | string | null },
  ) {
    const companyId = requireTenant(user);
    const limit = this.normalizeSyncLimit(query.limit);
    const cursor = this.decodeSyncCursor(query.cursor);
    const cursorWhere = this.buildSyncCursorWhere(cursor);
    const rows = await this.prisma.serviceOrder.findMany({
      where: {
        client: { companyId },
        ...this.visibilityWhere(user),
        ...(cursorWhere ? cursorWhere : {}),
      },
      include: includeRelations,
      orderBy: [{ updatedAt: 'asc' }, { id: 'asc' }],
      take: limit + 1,
    });
    const pageRows = rows.slice(0, limit);
    const hasMore = rows.length > limit;
    const nextCursor = pageRows.length
      ? this.encodeSyncCursor(pageRows[pageRows.length - 1])
      : query.cursor ?? null;
    const activeRows = pageRows.filter(
      (row) => !row.deletedAt && row.status !== ServiceOrderStatus.CANCELADO,
    );
    const tombstoneRows = pageRows.filter(
      (row) => row.deletedAt || row.status === ServiceOrderStatus.CANCELADO,
    );
    return {
      items: activeRows.map((row) => this.toDto(row)),
      tombstones: tombstoneRows.map((row) => this.toTombstone(row)),
      nextCursor,
      hasMore,
      serverTime: new Date().toISOString(),
    };
  }

  async getOne(user: RequestUser, id: string) {
    const companyId = requireTenant(user);
    const row = await this.prisma.serviceOrder.findFirst({
      where: {
        id,
        client: { companyId },
        deletedAt: null,
        ...this.visibilityWhere(user),
      },
      include: includeRelations,
    });
    if (!row) throw new NotFoundException('Orden de servicio no encontrada');
    return this.toDto(row);
  }

  async create(user: RequestUser, dto: CreateServiceOrderDto) {
    const companyId = requireTenant(user);
    const input = this.normalizeCreateInput(dto);
    if (!input.clientId || !input.category || !input.serviceType) {
      throw new BadRequestException('Datos incompletos para la orden');
    }
    const client = await this.requireClient(companyId, input.clientId);
    if (input.quotationId) {
      await this.requireQuotation(companyId, input.quotationId);
    }
    await this.assertNoOpenOrder(client.id);
    const now = new Date();
    const row = await this.prisma.serviceOrder.create({
      data: {
        clientId: client.id,
        quotationId: input.quotationId,
        category: input.category,
        serviceType: input.serviceType,
        status: input.status,
        technicalNote: input.technicalNote,
        extraRequirements: input.extraRequirements,
        assignedToId: input.assignedToId,
        scheduledFor: input.scheduledFor,
        createdById: user.id,
        lastStatusChangedAt: now,
        lastStatusChangedByUserId: user.id,
        statusHistory: {
          create: {
            previousStatus: null,
            nextStatus: input.status,
            changedAt: now,
            changedByUserId: user.id,
          },
        },
      },
      include: includeRelations,
    });
    return this.toDto(row);
  }

  async update(user: RequestUser, id: string, dto: UpdateServiceOrderDto) {
    const companyId = requireTenant(user);
    await this.getExistingScoped(user, companyId, id);
    const input = this.normalizeCreateInput(dto, { partial: true });
    if (input.clientId) await this.requireClient(companyId, input.clientId);
    if (input.quotationId) await this.requireQuotation(companyId, input.quotationId);
    const row = await this.prisma.serviceOrder.update({
      where: { id },
      data: {
        ...(input.clientId ? { clientId: input.clientId } : {}),
        ...(input.quotationId !== undefined ? { quotationId: input.quotationId } : {}),
        ...(input.category ? { category: input.category } : {}),
        ...(input.serviceType ? { serviceType: input.serviceType } : {}),
        ...(input.technicalNote !== undefined
          ? { technicalNote: input.technicalNote }
          : {}),
        ...(input.extraRequirements !== undefined
          ? { extraRequirements: input.extraRequirements }
          : {}),
        ...(input.assignedToId !== undefined
          ? { assignedToId: input.assignedToId }
          : {}),
        ...(input.scheduledFor !== undefined
          ? { scheduledFor: input.scheduledFor }
          : {}),
      },
      include: includeRelations,
    });
    return this.toDto(row);
  }

  async updateStatus(
    user: RequestUser,
    id: string,
    statusText: string,
    scheduledAt?: string | null,
  ) {
    const companyId = requireTenant(user);
    const current = await this.getExistingScoped(user, companyId, id);
    const nextStatus = this.parseStatus(statusText);
    const allowed = SERVICE_ORDER_TRANSITIONS[current.status] ?? [];
    if (!allowed.includes(nextStatus)) {
      throw new BadRequestException('Transición inválida para la orden');
    }
    const changedAt = new Date();
    const row = await this.prisma.serviceOrder.update({
      where: { id },
      data: {
        status: nextStatus,
        scheduledFor: scheduledAt ? new Date(scheduledAt) : current.scheduledFor,
        finalizedAt:
          nextStatus === ServiceOrderStatus.FINALIZADO
            ? changedAt
            : current.finalizedAt,
        lastStatusChangedAt: changedAt,
        lastStatusChangedByUserId: user.id,
        statusHistory: {
          create: {
            previousStatus: current.status,
            nextStatus,
            changedAt,
            changedByUserId: user.id,
          },
        },
      },
      include: includeRelations,
    });
    return this.toDto(row);
  }

  async delete(user: RequestUser, id: string) {
    const companyId = requireTenant(user);
    await this.getExistingScoped(user, companyId, id);
    await this.prisma.serviceOrder.update({
      where: { id },
      data: { deletedAt: new Date() },
    });
    return { ok: true };
  }

  async clone(user: RequestUser, id: string, dto: CloneServiceOrderDto) {
    const companyId = requireTenant(user);
    const source = await this.getExistingScoped(user, companyId, id);
    if (source.status !== ServiceOrderStatus.FINALIZADO) {
      throw new ConflictException(
        'Debes finalizarla antes de crear otra orden relacionada',
      );
    }
    const serviceType = this.parseType(dto.serviceType ?? dto.service_type);
    const clientId = dto.clientId ?? dto.client_id ?? source.clientId;
    const quotationId =
      dto.quotationId ?? dto.quotation_id ?? source.quotationId ?? null;
    await this.requireClient(companyId, clientId);
    if (quotationId) await this.requireQuotation(companyId, quotationId);
    await this.assertNoOpenOrder(clientId);
    const now = new Date();
    const row = await this.prisma.serviceOrder.create({
      data: {
        clientId,
        quotationId,
        category: source.category,
        serviceType,
        status: ServiceOrderStatus.PENDIENTE,
        parentOrderId: source.id,
        createdById: user.id,
        assignedToId: dto.assignedToId ?? dto.assigned_to ?? source.assignedToId,
        technicalNote:
          dto.technicalNote ?? dto.technical_note ?? source.technicalNote,
        extraRequirements:
          dto.extraRequirements ??
          dto.extra_requirements ??
          source.extraRequirements,
        lastStatusChangedAt: now,
        lastStatusChangedByUserId: user.id,
        statusHistory: {
          create: {
            previousStatus: null,
            nextStatus: ServiceOrderStatus.PENDIENTE,
            changedAt: now,
            changedByUserId: user.id,
          },
        },
      },
      include: includeRelations,
    });
    return this.toDto(row);
  }

  async addEvidence(
    user: RequestUser,
    id: string,
    dto: CreateServiceEvidenceDto,
  ) {
    const companyId = requireTenant(user);
    await this.getExistingScoped(user, companyId, id);
    const row = await this.prisma.serviceEvidence.create({
      data: {
        serviceOrderId: id,
        type: this.parseEvidenceType(dto.type),
        content: dto.content.trim(),
        createdById: user.id,
      },
    });
    return this.evidenceToDto(row);
  }

  async addReport(user: RequestUser, id: string, dto: CreateServiceReportDto) {
    const companyId = requireTenant(user);
    await this.getExistingScoped(user, companyId, id);
    const row = await this.prisma.serviceReport.create({
      data: {
        serviceOrderId: id,
        type: dto.type ? this.parseReportType(dto.type) : ServiceReportType.OTROS,
        report: dto.report.trim(),
        createdById: user.id,
      },
    });
    return this.reportToDto(row);
  }

  async purgeAllForDebug(user: RequestUser) {
    const companyId = requireTenant(user);
    const result = await this.prisma.serviceOrder.deleteMany({
      where: { client: { companyId } },
    });
    return { ok: true, deletedServiceOrders: result.count };
  }

  private buildListWhere(
    user: RequestUser,
    companyId: string,
    query: ServiceOrdersQueryDto,
  ): Prisma.ServiceOrderWhereInput {
    const statuses = this.parseStatuses(query.statuses ?? query.status);
    const dateRange = this.parseDateRange(query.from, query.to);
    const search = (query.search ?? '').trim();
    return {
      client: { companyId },
      deletedAt: null,
      ...this.visibilityWhere(user),
      status: { in: statuses },
      ...(dateRange ? { lastStatusChangedAt: dateRange } : {}),
      ...(search
        ? {
            OR: [
              { technicalNote: { contains: search, mode: 'insensitive' } },
              { extraRequirements: { contains: search, mode: 'insensitive' } },
              { client: { nombre: { contains: search, mode: 'insensitive' } } },
              { client: { telefono: { contains: search, mode: 'insensitive' } } },
            ],
          }
        : {}),
    };
  }

  private buildSyncCursorWhere(
    cursor: ServiceOrdersSyncCursor | null,
  ): Prisma.ServiceOrderWhereInput | null {
    if (!cursor) return null;
    const updatedAt = new Date(cursor.updatedAt);
    if (Number.isNaN(updatedAt.getTime()) || !cursor.id) {
      throw new BadRequestException('Cursor de sincronización inválido');
    }
    return {
      OR: [
        { updatedAt: { gt: updatedAt } },
        { updatedAt, id: { gt: cursor.id } },
      ],
    };
  }

  private normalizeSyncLimit(value?: number | string | null) {
    const parsed = Number(value ?? 200);
    if (!Number.isFinite(parsed)) return 200;
    return Math.min(Math.max(Math.trunc(parsed), 1), 200);
  }

  private encodeSyncCursor(row: { updatedAt: Date | string | null; id: string }) {
    const updatedAt =
      row.updatedAt instanceof Date
        ? row.updatedAt.toISOString()
        : row.updatedAt ?? null;
    if (!updatedAt) return null;
    const payload: ServiceOrdersSyncCursor = { updatedAt, id: row.id };
    return Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url');
  }

  private decodeSyncCursor(value?: string | null): ServiceOrdersSyncCursor | null {
    const raw = (value ?? '').trim();
    if (!raw) return null;
    try {
      const decoded = JSON.parse(
        Buffer.from(raw, 'base64url').toString('utf8'),
      ) as ServiceOrdersSyncCursor;
      if (typeof decoded.updatedAt !== 'string' || typeof decoded.id !== 'string') {
        throw new Error('Invalid cursor payload');
      }
      return decoded;
    } catch {
      throw new BadRequestException('Cursor de sincronización inválido');
    }
  }

  private visibilityWhere(user: RequestUser): Prisma.ServiceOrderWhereInput {
    if (isAdminLike(user)) return {};
    return {
      OR: [{ createdById: user.id }, { assignedToId: user.id }],
    };
  }

  private async getExistingScoped(user: RequestUser, companyId: string, id: string) {
    const row = await this.prisma.serviceOrder.findFirst({
      where: {
        id,
        client: { companyId },
        deletedAt: null,
        ...this.visibilityWhere(user),
      },
    });
    if (!row) throw new NotFoundException('Orden de servicio no encontrada');
    return row;
  }

  private async requireClient(companyId: string, id: string) {
    const row = await this.prisma.client.findFirst({
      where: { id, companyId, isDeleted: false },
      select: { id: true },
    });
    if (!row) throw new BadRequestException('client_id inválido');
    return row;
  }

  private async requireQuotation(companyId: string, id: string) {
    const row = await this.prisma.cotizacion.findFirst({
      where: { id, companyId },
      select: { id: true },
    });
    if (!row) throw new BadRequestException('quotation_id inválido');
    return row;
  }

  private async assertNoOpenOrder(clientId: string) {
    const existing = await this.prisma.serviceOrder.findFirst({
      where: {
        clientId,
        deletedAt: null,
        status: {
          in: [
            ServiceOrderStatus.PENDIENTE,
            ServiceOrderStatus.EN_PROCESO,
            ServiceOrderStatus.EN_PAUSA,
            ServiceOrderStatus.POSPUESTA,
          ],
        },
      },
      select: { id: true },
    });
    if (existing) {
      throw new ConflictException(
        'Debes finalizarla antes de crear otra orden para este cliente',
      );
    }
  }

  private normalizeCreateInput(
    dto: CreateServiceOrderDto,
    options: { partial?: boolean } = {},
  ) {
    const clientId = dto.clientId ?? dto.client_id;
    if (!options.partial && !clientId) {
      throw new BadRequestException('client_id es requerido');
    }
    return {
      clientId,
      quotationId: dto.quotationId ?? dto.quotation_id ?? null,
      category:
        dto.category == null ? undefined : this.parseCategory(dto.category),
      serviceType:
        dto.serviceType == null && dto.service_type == null
          ? options.partial
            ? undefined
            : this.parseType('instalacion')
          : this.parseType(dto.serviceType ?? dto.service_type),
      status:
        dto.status == null
          ? ServiceOrderStatus.PENDIENTE
          : this.parseStatus(dto.status),
      technicalNote: dto.technicalNote ?? dto.technical_note,
      extraRequirements: dto.extraRequirements ?? dto.extra_requirements,
      assignedToId: dto.assignedToId ?? dto.assigned_to,
      scheduledFor:
        dto.scheduledFor || dto.scheduled_for
          ? new Date(dto.scheduledFor ?? dto.scheduled_for!)
          : undefined,
    };
  }

  private parseStatuses(value?: string | null) {
    const raw = (value ?? '').trim();
    if (!raw) return SERVICE_ORDER_DEFAULT_STATUSES;
    return raw
      .split(',')
      .map((item) => this.parseStatus(item))
      .filter((item, index, all) => all.indexOf(item) === index);
  }

  private parseDateRange(from?: string, to?: string): Prisma.DateTimeFilter | null {
    if (!from && !to) return null;
    return {
      ...(from ? { gte: new Date(from) } : {}),
      ...(to ? { lte: new Date(to) } : {}),
    };
  }

  private parseCategory(value?: string) {
    return this.enumFromApi(ServiceOrderCategory, value, 'category');
  }

  private parseType(value?: string) {
    return this.enumFromApi(ServiceOrderType, value, 'service_type');
  }

  private parseStatus(value?: string) {
    return this.enumFromApi(ServiceOrderStatus, value, 'status');
  }

  private parseEvidenceType(value?: string) {
    return this.enumFromApi(ServiceEvidenceType, value, 'type');
  }

  private parseReportType(value?: string) {
    return this.enumFromApi(ServiceReportType, value, 'type');
  }

  private enumFromApi<T extends Record<string, string>>(
    enumType: T,
    value: string | undefined,
    field: string,
  ): T[keyof T] {
    const normalized = (value ?? '').trim().toLowerCase();
    const found = Object.values(enumType).find(
      (item) => item.toLowerCase() === normalized,
    );
    if (!found) throw new BadRequestException(`${field} inválido`);
    return found as T[keyof T];
  }

  private enumToApi(value: string) {
    return value.toLowerCase();
  }

  private toDto(row: any) {
    return {
      id: row.id,
      clientId: row.clientId,
      client: row.client ? this.clientToDto(row.client) : null,
      quotationId: row.quotationId,
      category: this.enumToApi(row.category),
      serviceType: this.enumToApi(row.serviceType),
      status: this.enumToApi(row.status),
      technicalNote: row.technicalNote,
      extraRequirements: row.extraRequirements,
      parentOrderId: row.parentOrderId,
      createdById: row.createdById,
      assignedToId: row.assignedToId,
      scheduledFor: row.scheduledFor?.toISOString() ?? null,
      finalizedAt: row.finalizedAt?.toISOString() ?? null,
      technicianConfirmedAt: row.technicianConfirmedAt?.toISOString() ?? null,
      technicianConfirmedById: row.technicianConfirmedById,
      lastStatusChangedAt: row.lastStatusChangedAt?.toISOString() ?? null,
      lastStatusChangedByUserId: row.lastStatusChangedByUserId,
      deletedAt: row.deletedAt?.toISOString() ?? null,
      createdAt: row.createdAt?.toISOString() ?? null,
      updatedAt: row.updatedAt?.toISOString() ?? null,
      statusHistory: (row.statusHistory ?? []).map((item: any) =>
        this.statusHistoryToDto(item),
      ),
      evidences: (row.evidences ?? []).map((item: any) =>
        this.evidenceToDto(item),
      ),
      reports: (row.reports ?? []).map((item: any) => this.reportToDto(item)),
    };
  }

  private clientToDto(row: any) {
    return {
      id: row.id,
      ownerId: row.ownerId,
      nombre: row.nombre,
      telefono: row.telefono,
      direccion: row.direccion,
      locationUrl: row.locationUrl,
      latitude: row.latitude,
      longitude: row.longitude,
      correo: row.email,
      taxId: row.taxId,
      businessName: row.businessName,
      taxIdType: row.taxIdType,
      createdAt: row.createdAt?.toISOString() ?? null,
      updatedAt: row.updatedAt?.toISOString() ?? null,
      isDeleted: row.isDeleted,
    };
  }

  private statusHistoryToDto(row: any) {
    return {
      id: row.id,
      serviceOrderId: row.serviceOrderId,
      previousStatus: row.previousStatus ? this.enumToApi(row.previousStatus) : null,
      nextStatus: this.enumToApi(row.nextStatus),
      changedAt: row.changedAt?.toISOString() ?? null,
      createdAt: row.createdAt?.toISOString() ?? null,
      changedByUserId: row.changedByUserId,
      changedByUserName: row.changedByUserName,
      note: row.note,
    };
  }

  private evidenceToDto(row: any) {
    return {
      id: row.id,
      serviceOrderId: row.serviceOrderId,
      type: this.enumToApi(row.type),
      content: row.content,
      createdById: row.createdById,
      createdAt: row.createdAt?.toISOString() ?? null,
    };
  }

  private reportToDto(row: any) {
    return {
      id: row.id,
      serviceOrderId: row.serviceOrderId,
      type: this.enumToApi(row.type),
      report: row.report,
      createdById: row.createdById,
      createdAt: row.createdAt?.toISOString() ?? null,
    };
  }

  private toTombstone(row: any): ServiceOrderSyncTombstone {
    const version = row.updatedAt?.toISOString() ?? null;
    const deletedAt = row.deletedAt?.toISOString() ?? null;
    return {
      id: row.id,
      deletedAt: deletedAt ?? row.lastStatusChangedAt?.toISOString() ?? version,
      reason: deletedAt ? 'deleted' : 'cancelled',
      version,
    };
  }
}
