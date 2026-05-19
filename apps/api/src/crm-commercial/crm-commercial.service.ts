import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  CrmCommercialCustomerStatus,
  CrmCommercialLibraryItemType,
  CrmCommercialFollowupTaskPriority,
  CrmCommercialFollowupTaskStatus,
  Prisma,
  Role,
  WhatsappMessageDirection,
} from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { ChangeCrmCommercialStatusDto } from './dto/change-crm-commercial-status.dto';
import { CreateCrmCommercialActivityDto } from './dto/create-crm-commercial-activity.dto';
import { CreateCrmCommercialCustomerDto } from './dto/create-crm-commercial-customer.dto';
import { CreateCrmCommercialNoteDto } from './dto/create-crm-commercial-note.dto';
import { CrmCommercialQueryDto } from './dto/crm-commercial-query.dto';
import { UpdateCrmCommercialCustomerDto } from './dto/update-crm-commercial-customer.dto';
import { CreateCrmCommercialFollowupTaskDto } from './dto/create-crm-commercial-followup-task.dto';
import { UpdateCrmCommercialFollowupTaskDto } from './dto/update-crm-commercial-followup-task.dto';
import { CrmCommercialFollowupTaskQueryDto } from './dto/crm-commercial-followup-task-query.dto';
import { UpdateCrmCommercialSettingsDto } from './dto/update-crm-commercial-settings.dto';
import { SendCrmCommercialMessageDto } from './dto/send-crm-commercial-message.dto';
import { WhatsappService } from '../whatsapp/whatsapp.service';
import { normalizeWhatsappPhone } from '../whatsapp-inbox/whatsapp-identity.util';
import { WhatsappInboxService } from '../whatsapp-inbox/whatsapp-inbox.service';
import { RedisService } from '../common/redis/redis.service';
import {
  SendCrmCommercialMediaMessageDto,
  StartCrmCommercialMediaMessageDto,
  ReplyCrmCommercialMediaMessageDto,
} from './dto/send-crm-commercial-media-message.dto';
import { SuggestCrmCommercialOrthographyDto } from './dto/suggest-crm-commercial-orthography.dto';
import { SuggestCrmCommercialReplyDto } from './dto/suggest-crm-commercial-reply.dto';
import { AiAssistantService } from '../ai-assistant/ai-assistant.service';
import {
  CreateCrmCommercialLibraryItemDto,
  CrmCommercialLibraryItemQueryDto,
  UpdateCrmCommercialLibraryItemDto,
} from './dto/crm-commercial-library-item.dto';

type AuthUser = { id: string; role: Role };

type CrmLibraryKnowledgeItem = {
  id: string;
  title: string;
  type: CrmCommercialLibraryItemType;
  contentText: string | null;
  mediaUrl: string | null;
  fileName: string | null;
  mimeType: string | null;
  externalUrl: string | null;
  category: string | null;
  tags: string[];
  isActive: boolean;
};

@Injectable()
export class CrmCommercialService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly whatsappService: WhatsappService,
    private readonly whatsappInboxService: WhatsappInboxService,
    private readonly redis: RedisService,
    private readonly aiAssistantService: AiAssistantService,
  ) {}

  private getCompanyId(): string {
    return process.env.COMPANY_ID ?? '00000000-0000-0000-0000-000000000001';
  }

  private normalizeLibraryText(value: string) {
    return value
      .toLowerCase()
      .replace(/[áàäâ]/g, 'a')
      .replace(/[éèëê]/g, 'e')
      .replace(/[íìïî]/g, 'i')
      .replace(/[óòöô]/g, 'o')
      .replace(/[úùüû]/g, 'u')
      .replace(/[^a-z0-9\s]/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  private libraryTypeFromIntent(intent: string): CrmCommercialLibraryItemType[] {
    switch (intent) {
      case 'pide_ubicacion':
        return [CrmCommercialLibraryItemType.LOCATION, CrmCommercialLibraryItemType.LINK];
      case 'pide_horario':
        return [CrmCommercialLibraryItemType.BUSINESS_HOURS, CrmCommercialLibraryItemType.TEXT];
      case 'pide_cuenta_bancaria':
        return [CrmCommercialLibraryItemType.BANK_ACCOUNT, CrmCommercialLibraryItemType.TEXT];
      case 'pide_catalogo':
      case 'pregunta_precio':
      case 'quiere_cotizacion':
        return [CrmCommercialLibraryItemType.CATALOG, CrmCommercialLibraryItemType.QUOTE_TEMPLATE, CrmCommercialLibraryItemType.TEXT, CrmCommercialLibraryItemType.LINK];
      case 'quiere_instalacion':
      case 'quiere_seguimiento':
        return [CrmCommercialLibraryItemType.FOLLOW_UP, CrmCommercialLibraryItemType.TEXT];
      case 'cliente_molesto':
        return [CrmCommercialLibraryItemType.FAQ, CrmCommercialLibraryItemType.WARRANTY, CrmCommercialLibraryItemType.TEXT];
      case 'quiere_comprar':
        return [CrmCommercialLibraryItemType.PROMOTION, CrmCommercialLibraryItemType.QUOTE_TEMPLATE, CrmCommercialLibraryItemType.TEXT];
      default:
        return [CrmCommercialLibraryItemType.TEXT, CrmCommercialLibraryItemType.FAQ, CrmCommercialLibraryItemType.PROMOTION];
    }
  }

  private buildLibrarySearchTerms(message: string): string[] {
    return this.normalizeLibraryText(message)
      .split(' ')
      .map((term) => term.trim())
      .filter((term) => term.length >= 3)
      .slice(0, 8);
  }

  private async findLibraryItemsForMessage(
    companyId: string,
    message: string,
    limit = 12,
  ) {
    const normalized = this.normalizeLibraryText(message);
    const typeHints = this.libraryTypeFromIntent(
      normalized.includes('ubicacion') || normalized.includes('direccion') || normalized.includes('donde')
        ? 'pide_ubicacion'
        : normalized.includes('horario') || normalized.includes('hora')
          ? 'pide_horario'
          : normalized.includes('cuenta') || normalized.includes('banco') || normalized.includes('transferencia')
            ? 'pide_cuenta_bancaria'
            : normalized.includes('catalogo') || normalized.includes('productos')
              ? 'pide_catalogo'
              : normalized.includes('precio')
                ? 'pregunta_precio'
                : normalized.includes('cotizacion')
                  ? 'quiere_cotizacion'
                  : normalized.includes('seguimiento')
                    ? 'quiere_seguimiento'
                    : normalized.includes('garantia')
                      ? 'cliente_molesto'
                      : normalized.includes('comprar')
                        ? 'quiere_comprar'
                        : 'general',
    );
    const searchTerms = this.buildLibrarySearchTerms(message);

    const items = await this.prisma.crmCommercialLibraryItem.findMany({
      where: {
        companyId,
        isActive: true,
        ...(typeHints.length > 0 ? { type: { in: typeHints } } : {}),
        ...(searchTerms.length > 0
          ? {
              OR: [
                { title: { contains: normalized, mode: 'insensitive' } },
                { description: { contains: normalized, mode: 'insensitive' } },
                { contentText: { contains: normalized, mode: 'insensitive' } },
                { category: { contains: normalized, mode: 'insensitive' } },
                { externalUrl: { contains: normalized, mode: 'insensitive' } },
                { tags: { hasSome: searchTerms } },
              ],
            }
          : {}),
      },
      orderBy: [{ sortOrder: 'asc' }, { updatedAt: 'desc' }],
      take: limit,
    });

    return items.map((item) => ({
      id: item.id,
      title: item.title,
      type: item.type,
      contentText: item.contentText,
      mediaUrl: item.mediaUrl,
      fileName: item.fileName,
      mimeType: item.mimeType,
      externalUrl: item.externalUrl,
      category: item.category,
      tags: item.tags ?? [],
      isActive: item.isActive,
    } satisfies CrmLibraryKnowledgeItem));
  }

  private librarySelect = {
    id: true,
    companyId: true,
    title: true,
    description: true,
    type: true,
    contentText: true,
    mediaUrl: true,
    fileName: true,
    mimeType: true,
    latitude: true,
    longitude: true,
    externalUrl: true,
    category: true,
    tags: true,
    isActive: true,
    sortOrder: true,
    createdByUserId: true,
    updatedByUserId: true,
    useCount: true,
    lastUsedAt: true,
    createdAt: true,
    updatedAt: true,
  } as const;

  private extractEvolutionMessageId(result: unknown): string | undefined {
    if (!result || typeof result !== 'object') return undefined;
    const map = result as Record<string, unknown>;
    const direct = map['id'];
    if (typeof direct === 'string' && direct.trim().length > 0) {
      return direct.trim();
    }
    const key = map['key'];
    if (key && typeof key === 'object') {
      const keyId = (key as Record<string, unknown>)['id'];
      if (typeof keyId === 'string' && keyId.trim().length > 0) {
        return keyId.trim();
      }
    }
    return undefined;
  }

  private normalizeRemoteJidFromPhone(rawPhone: string): {
    normalizedPhone: string;
    remoteJid: string;
  } {
    let normalizedPhone = normalizeWhatsappPhone(rawPhone) ?? rawPhone.replace(/\D/g, '');
    // Evolution usually expects E.164-like number for DR locals (809/829/849 => 1XXXXXXXXXX)
    if (normalizedPhone.length === 10 && /^(809|829|849)/.test(normalizedPhone)) {
      normalizedPhone = `1${normalizedPhone}`;
    }
    if (!normalizedPhone || normalizedPhone.length < 7) {
      throw new BadRequestException('Numero de telefono invalido.');
    }
    return {
      normalizedPhone,
      remoteJid: `${normalizedPhone}@s.whatsapp.net`,
    };
  }

  private stringifyDebug(value: unknown): string {
    try {
      if (typeof value === 'string') return value;
      return JSON.stringify(value);
    } catch {
      return String(value);
    }
  }

  private async ensureInstanceConnectedOrThrow(instanceName: string) {
    const state = await this.whatsappService.getInstanceConnectionState(
      instanceName,
    );
    const normalized = (state ?? '').trim().toLowerCase();
    if (normalized == 'connected' || normalized == 'open') {
      return;
    }
    throw new BadRequestException({
      message:
        `No se pudo enviar el mensaje: la instancia de WhatsApp ` +
        `"${instanceName}" está desconectada (${state || 'desconocido'}). ` +
        `Reconéctala en el panel de instancias y vuelve a intentar.`,
      code: 'CRM_WHATSAPP_INSTANCE_DISCONNECTED',
    });
  }

  async suggestOrthography(
    user: AuthUser,
    dto: SuggestCrmCommercialOrthographyDto,
  ) {
    if (!this.canWrite(user)) {
      throw new ForbiddenException('No tienes permisos para usar corrección IA en CRM Comercial.');
    }

    const text = (dto.text ?? '').toString();
    const previousText = (dto.previousText ?? '').toString();

    const result = await this.aiAssistantService.suggestCommercialOrthography({
      text,
      previousText,
    });

    return {
      suggestion: result.suggestion,
      changed: result.changed,
      skipped: result.skipped,
      reason: result.reason ?? null,
    };
  }

  async suggestReply(user: AuthUser, dto: SuggestCrmCommercialReplyDto) {
    if (!this.canWrite(user)) {
      throw new ForbiddenException('No tienes permisos para usar IA en CRM Comercial.');
    }

    const conversationData = await this.getConversationMessages(user, dto.conversationId, {
      limit: '60',
    });
    const messages = conversationData.items ?? [];
    const normalizedRecent = messages
      .map((msg) => {
        const text = (msg.body ?? msg.caption ?? '').toString().trim();
        if (!text) return null;
        return {
          direction: (msg.direction ?? 'INCOMING').toString().toUpperCase(),
          text,
        };
      })
      .filter((row): row is { direction: string; text: string } => !!row)
      .slice(-12);

    let lastIncomingMessage = '';
    for (var i = normalizedRecent.length - 1; i >= 0; i--) {
      if (normalizedRecent[i].direction == 'INCOMING') {
        lastIncomingMessage = normalizedRecent[i].text;
        break;
      }
    }

    const fromDto = (dto.lastCustomerMessage ?? '').toString().trim();
    const lastCustomerMessage = fromDto.length > 0 ? fromDto : lastIncomingMessage;
    if (!lastCustomerMessage) {
      throw new BadRequestException('No hay un mensaje reciente del cliente para analizar.');
    }

    const companyId = this.getCompanyId();
    const [appConfig, products, libraryItems] = await Promise.all([
      this.prisma.appConfig.findUnique({
        where: { id: 'global' },
        select: {
          address: true,
          gpsLocationUrl: true,
          businessHours: true,
          bankAccounts: true,
        },
      }),
      this.prisma.product.findMany({
        take: 8,
        orderBy: { nombre: 'asc' },
        select: {
          nombre: true,
          categoria: true,
          precio: true,
        },
      }),
      this.findLibraryItemsForMessage(companyId, lastCustomerMessage, 12),
    ]);

    const rawAccounts = Array.isArray(appConfig?.bankAccounts)
      ? (appConfig?.bankAccounts as Array<Record<string, unknown>>)
      : [];
    const bankAccounts = rawAccounts
      .map((entry) => {
        const name = (entry['name'] ?? '').toString().trim();
        const bankName = (entry['bankName'] ?? '').toString().trim();
        const accountNumber = (entry['accountNumber'] ?? '').toString().trim();
        const parts = [name, bankName, accountNumber].filter((part) => part.length > 0);
        if (parts.length === 0) return '';
        return parts.join(' | ');
      })
      .filter((value) => value.length > 0);

    const catalogSummary = products.length === 0
      ? null
      : products
          .map((item) => {
            const category = item.categoria.trim();
            return category.length === 0
              ? item.nombre.trim()
              : `${item.nombre.trim()} (${category})`;
          })
          .filter((row) => row.length > 0)
          .slice(0, 6)
          .join(', ');

    const aiConfigured = await this.aiAssistantService.isCommercialAiConfigured();

    const suggestion = await this.aiAssistantService.suggestCrmCommercialReply({
      lastCustomerMessage,
      recentMessages: normalizedRecent,
      crmStatus:
          (dto.crmStatus ??
                  conversationData.conversation?.crmCustomerStatus ??
                  'NUEVO')
              .toString(),
      customerInfo: {
        name: (conversationData.conversation?.crmCustomerName ??
                conversationData.conversation?.contactName ??
                '')
            .toString(),
        phone: (conversationData.conversation?.remotePhone ?? '').toString(),
      },
      availableBusinessData: {
        location:
            (appConfig?.gpsLocationUrl ?? '').toString().trim().length > 0
                ? (appConfig?.gpsLocationUrl ?? '').toString().trim()
                : (appConfig?.address ?? '').toString().trim(),
        businessHours: (appConfig?.businessHours ?? '').toString().trim(),
        bankAccounts,
        catalogSummary,
        libraryItems,
      },
    });

    return {
      intent: suggestion.intent,
      suggestedReply: suggestion.suggestedReply,
      nextAction: suggestion.nextAction,
      missingData: suggestion.missingData,
      confidence: suggestion.confidence,
      dataUsed: suggestion.dataUsed,
      aiConfigured,
      message: !aiConfigured ? 'La IA no está configurada todavía.' : null,
      autoSend: false,
    };
  }

  async listLibrary(user: AuthUser, query: CrmCommercialLibraryItemQueryDto) {
    if (!this.isAdmin(user)) {
      throw new ForbiddenException('Solo ADMIN puede leer la biblioteca comercial');
    }

    const companyId = this.getCompanyId();
    const where: Prisma.CrmCommercialLibraryItemWhereInput = { companyId };
    if (query.type) where.type = query.type;
    if (typeof query.isActive === 'boolean') where.isActive = query.isActive;
    if (query.category?.trim()) {
      where.category = { contains: query.category.trim(), mode: 'insensitive' };
    }
    if (query.search?.trim()) {
      const search = query.search.trim();
      where.OR = [
        { title: { contains: search, mode: 'insensitive' } },
        { description: { contains: search, mode: 'insensitive' } },
        { contentText: { contains: search, mode: 'insensitive' } },
        { externalUrl: { contains: search, mode: 'insensitive' } },
        { fileName: { contains: search, mode: 'insensitive' } },
        { category: { contains: search, mode: 'insensitive' } },
        { tags: { hasSome: this.buildLibrarySearchTerms(search) } },
      ];
    }

    const items = await this.prisma.crmCommercialLibraryItem.findMany({
      where,
      orderBy: [{ sortOrder: 'asc' }, { updatedAt: 'desc' }],
      take: query.limit ? Math.min(Math.max(query.limit, 1), 200) : 100,
      select: this.librarySelect,
    });

    return { items };
  }

  async createLibraryItem(user: AuthUser, dto: CreateCrmCommercialLibraryItemDto) {
    if (!this.isAdmin(user)) {
      throw new ForbiddenException('Solo ADMIN puede crear recursos de biblioteca');
    }

    const item = await this.prisma.crmCommercialLibraryItem.create({
      data: {
        companyId: (dto.companyId ?? this.getCompanyId()).trim(),
        title: dto.title.trim(),
        description: this.normalizeText(dto.description),
        type: dto.type,
        contentText: this.normalizeText(dto.contentText),
        mediaUrl: this.normalizeText(dto.mediaUrl),
        fileName: this.normalizeText(dto.fileName),
        mimeType: this.normalizeText(dto.mimeType),
        latitude: dto.latitude != null ? new Prisma.Decimal(dto.latitude) : undefined,
        longitude: dto.longitude != null ? new Prisma.Decimal(dto.longitude) : undefined,
        externalUrl: this.normalizeText(dto.externalUrl),
        category: this.normalizeText(dto.category),
        tags: (dto.tags ?? []).map((tag) => tag.trim()).filter((tag) => tag.length > 0),
        isActive: dto.isActive ?? true,
        sortOrder: dto.sortOrder ?? 0,
        createdByUserId: user.id,
        updatedByUserId: user.id,
      },
      select: this.librarySelect,
    });

    return item;
  }

  async updateLibraryItem(
    user: AuthUser,
    id: string,
    dto: UpdateCrmCommercialLibraryItemDto,
  ) {
    if (!this.isAdmin(user)) {
      throw new ForbiddenException('Solo ADMIN puede editar recursos de biblioteca');
    }

    await this.ensureLibraryItemExists(id);
    const item = await this.prisma.crmCommercialLibraryItem.update({
      where: { id },
      data: {
        ...(dto.companyId ? { companyId: dto.companyId.trim() } : {}),
        ...(dto.title != null ? { title: dto.title.trim() } : {}),
        ...(dto.description != null ? { description: this.normalizeText(dto.description) } : {}),
        ...(dto.type != null ? { type: dto.type } : {}),
        ...(dto.contentText != null ? { contentText: this.normalizeText(dto.contentText) } : {}),
        ...(dto.mediaUrl != null ? { mediaUrl: this.normalizeText(dto.mediaUrl) } : {}),
        ...(dto.fileName != null ? { fileName: this.normalizeText(dto.fileName) } : {}),
        ...(dto.mimeType != null ? { mimeType: this.normalizeText(dto.mimeType) } : {}),
        ...(dto.latitude != null ? { latitude: new Prisma.Decimal(dto.latitude) } : {}),
        ...(dto.longitude != null ? { longitude: new Prisma.Decimal(dto.longitude) } : {}),
        ...(dto.externalUrl != null ? { externalUrl: this.normalizeText(dto.externalUrl) } : {}),
        ...(dto.category != null ? { category: this.normalizeText(dto.category) } : {}),
        ...(dto.tags != null
          ? {
              tags: dto.tags.map((tag) => tag.trim()).filter((tag) => tag.length > 0),
            }
          : {}),
        ...(dto.isActive != null ? { isActive: dto.isActive } : {}),
        ...(dto.sortOrder != null ? { sortOrder: dto.sortOrder } : {}),
        updatedByUserId: user.id,
      },
      select: this.librarySelect,
    });

    return item;
  }

  async deleteLibraryItem(user: AuthUser, id: string) {
    if (!this.isAdmin(user)) {
      throw new ForbiddenException('Solo ADMIN puede eliminar recursos de biblioteca');
    }

    await this.ensureLibraryItemExists(id);
    return this.prisma.crmCommercialLibraryItem.update({
      where: { id },
      data: {
        isActive: false,
        updatedByUserId: user.id,
      },
      select: this.librarySelect,
    });
  }

  async useLibraryItem(user: AuthUser, id: string) {
    if (!this.isAdmin(user)) {
      throw new ForbiddenException('Solo ADMIN puede registrar uso de biblioteca');
    }

    await this.ensureLibraryItemExists(id);
    return this.prisma.crmCommercialLibraryItem.update({
      where: { id },
      data: {
        useCount: { increment: 1 },
        lastUsedAt: new Date(),
        updatedByUserId: user.id,
      },
      select: this.librarySelect,
    });
  }

  private async ensureLibraryItemExists(id: string) {
    const item = await this.prisma.crmCommercialLibraryItem.findFirst({
      where: { id, companyId: this.getCompanyId() },
      select: { id: true },
    });
    if (!item) {
      throw new NotFoundException('Recurso de biblioteca no encontrado');
    }
    return item;
  }

  private isAdmin(user: AuthUser): boolean {
    return user.role === Role.ADMIN;
  }

  private canWrite(user: AuthUser): boolean {
    // Temporarily restricted to ADMIN only while module is in development.
    // Extend this list when ready to enable other roles.
    return user.role === Role.ADMIN;
  }

  private parseBool(raw?: string): boolean | undefined {
    if (raw == null) return undefined;
    const value = String(raw).trim().toLowerCase();
    if (['1', 'true', 'yes', 'si'].includes(value)) return true;
    if (['0', 'false', 'no'].includes(value)) return false;
    return undefined;
  }

  private normalizeText(value?: string | null): string | undefined {
    if (value == null) return undefined;
    const trimmed = value.trim();
    return trimmed.length === 0 ? undefined : trimmed;
  }

  private normalizePhone(value: string): string {
    return value.trim().replace(/\s+/g, ' ');
  }

  private parseLimit(raw: string | undefined, fallback: number, max: number) {
    const parsed = Number(raw);
    if (!Number.isFinite(parsed)) return fallback;
    return Math.min(max, Math.max(1, Math.trunc(parsed)));
  }

  private parseDate(raw?: string) {
    if (!raw) return undefined;
    const parsed = new Date(raw);
    if (Number.isNaN(parsed.getTime())) return undefined;
    return parsed;
  }

  private normalizeComparablePhone(value: string | null | undefined) {
    if (!value) return null;
    const byInbox = normalizeWhatsappPhone(value);
    if (byInbox) return byInbox;
    const digits = value.replace(/\D/g, '');
    return digits.length >= 7 ? digits : null;
  }

  private async getSelectedWhatsappInstanceForCrm() {
    const settings = await this.prisma.crmCommercialSetting.upsert({
      where: { id: 'global' },
      create: { id: 'global' },
      update: {},
    });

    const instanceName = settings.selectedWhatsappInstanceName?.trim() ?? '';
    const selectedId = settings.selectedWhatsappInstanceId?.trim() ?? '';

    if (!instanceName && !selectedId) {
      return {
        selectedInstanceId: null as string | null,
        warning: 'Selecciona una instancia para recibir mensajes reales.',
      };
    }

    // Resolve the actual UserWhatsappInstance UUID (stored in whatsapp_conversations.instance_id)
    // Priority: look up by instanceName first (most reliable), fall back to selectedId if it's a UUID
    let resolvedUuid: string | null = null;

    if (instanceName) {
      const waInstance = await this.prisma.userWhatsappInstance.findUnique({
        where: { instanceName },
        select: { id: true },
      });
      resolvedUuid = waInstance?.id ?? null;
    }

    // Fallback: if selectedId looks like a UUID (user instance), use it directly
    if (!resolvedUuid && selectedId && selectedId !== 'company') {
      const waInstance = await this.prisma.userWhatsappInstance.findUnique({
        where: { id: selectedId },
        select: { id: true },
      });
      resolvedUuid = waInstance?.id ?? null;
    }

    if (!resolvedUuid) {
      return {
        selectedInstanceId: null as string | null,
        warning: 'La instancia seleccionada no existe o aún no ha recibido mensajes.',
      };
    }

    return {
      selectedInstanceId: resolvedUuid,
      warning: null as string | null,
    };
  }

  private async ensureClientExists(clientId?: string) {
    if (!clientId) return;
    const client = await this.prisma.client.findUnique({
      where: { id: clientId },
      select: { id: true },
    });
    if (!client) {
      throw new BadRequestException('El cliente principal asociado no existe');
    }
  }

  private async ensureNoDuplicateForCreate(input: {
    nombre: string;
    telefono: string;
    clientId?: string;
  }) {
    if (input.clientId) {
      const byClient = await this.prisma.crmCommercialCustomer.findFirst({
        where: { clientId: input.clientId },
        select: { id: true },
      });
      if (byClient) {
        throw new ConflictException(
          'Ya existe un cliente CRM comercial vinculado a este cliente principal',
        );
      }
    }

    const byNameAndPhone = await this.prisma.crmCommercialCustomer.findFirst({
      where: {
        nombre: { equals: input.nombre, mode: 'insensitive' },
        telefono: input.telefono,
      },
      select: { id: true },
    });
    if (byNameAndPhone) {
      throw new ConflictException(
        'Ya existe un cliente CRM comercial con ese nombre y telefono',
      );
    }
  }

  private async ensureNoDuplicateForUpdate(
    customerId: string,
    input: {
      nombre?: string;
      telefono?: string;
      clientId?: string;
    },
  ) {
    if (input.clientId) {
      const byClient = await this.prisma.crmCommercialCustomer.findFirst({
        where: {
          clientId: input.clientId,
          id: { not: customerId },
        },
        select: { id: true },
      });
      if (byClient) {
        throw new ConflictException(
          'Ese cliente principal ya esta vinculado en CRM comercial',
        );
      }
    }

    if (input.nombre && input.telefono) {
      const byNameAndPhone = await this.prisma.crmCommercialCustomer.findFirst({
        where: {
          id: { not: customerId },
          nombre: { equals: input.nombre, mode: 'insensitive' },
          telefono: input.telefono,
        },
        select: { id: true },
      });
      if (byNameAndPhone) {
        throw new ConflictException(
          'Ya existe un cliente CRM comercial con ese nombre y telefono',
        );
      }
    }
  }

  private async ensureCustomerAccessible(user: AuthUser, customerId: string) {
    const customer = await this.prisma.crmCommercialCustomer.findUnique({
      where: { id: customerId },
      include: {
        responsableUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
      },
    });

    if (!customer) {
      throw new NotFoundException('Cliente CRM comercial no encontrado');
    }

    if (this.isAdmin(user)) return customer;

    if (user.role === Role.VENDEDOR && customer.responsableUserId !== user.id) {
      throw new ForbiddenException(
        'No tienes acceso a este cliente CRM comercial',
      );
    }

    return customer;
  }

  async getAvailableWhatsappInstances(user: AuthUser) {
    if (!this.isAdmin(user)) {
      throw new ForbiddenException('Solo ADMIN puede consultar instancias disponibles');
    }

    const instances = await this.whatsappService.listAllInstancesForCrm();
    return instances.map((instance) => ({
      id: String(instance.id),
      instanceName: String(instance.instanceName ?? ''),
      status: String(instance.status ?? 'pending'),
      webhookEnabled: !!instance.webhookEnabled,
      isCompany: !!instance.isCompany,
      userId: instance.userId ? String(instance.userId) : null,
      userName: String(instance.userName ?? ''),
      userRole: instance.userRole ? String(instance.userRole) : null,
      phoneNumber: instance.phoneNumber ? String(instance.phoneNumber) : null,
    }));
  }

  async getSettings(user: AuthUser) {
    if (!this.isAdmin(user)) {
      throw new ForbiddenException('Solo ADMIN puede ver la configuracion CRM Comercial');
    }

    const [settings, instances] = await Promise.all([
      this.prisma.crmCommercialSetting.upsert({
        where: { id: 'global' },
        create: { id: 'global' },
        update: {},
        include: {
          updatedByUser: {
            select: { id: true, nombreCompleto: true, role: true },
          },
        },
      }),
      this.getAvailableWhatsappInstances(user),
    ]);

    const selectedInstance = settings.selectedWhatsappInstanceId
      ? instances.find((instance) => instance.id === settings.selectedWhatsappInstanceId)
      : null;
    const selectedInstanceExists = settings.selectedWhatsappInstanceId
      ? !!selectedInstance
      : true;

    return {
      ...settings,
      selectedInstanceExists,
      selectedInstanceStatus: selectedInstance?.status ?? null,
      selectedInstanceWebhookEnabled: selectedInstance?.webhookEnabled ?? null,
      warning:
        settings.selectedWhatsappInstanceId && !selectedInstanceExists
          ? 'La instancia seleccionada ya no existe o fue eliminada.'
          : null,
      // Preparado para siguiente fase de mensajes reales
      realMessagesReady:
        !!settings.enabled &&
        !!settings.selectedWhatsappInstanceId &&
        selectedInstanceExists,
    };
  }

  async updateSettings(user: AuthUser, dto: UpdateCrmCommercialSettingsDto) {
    if (!this.isAdmin(user)) {
      throw new ForbiddenException('Solo ADMIN puede actualizar la configuracion CRM Comercial');
    }

    const [current, availableInstances] = await Promise.all([
      this.prisma.crmCommercialSetting.upsert({
        where: { id: 'global' },
        create: { id: 'global' },
        update: {},
      }),
      this.getAvailableWhatsappInstances(user),
    ]);

    let selectedId =
      dto.selectedWhatsappInstanceId != null
        ? dto.selectedWhatsappInstanceId.trim()
        : current.selectedWhatsappInstanceId ?? undefined;
    if (selectedId === '') selectedId = undefined;
    const nextEnabled = dto.enabled ?? current.enabled;

    if (selectedId) {
      const found = availableInstances.find((instance) => instance.id === selectedId);
      const isExplicitSelectionChange = dto.selectedWhatsappInstanceId != null;
      if (!found && (isExplicitSelectionChange || nextEnabled)) {
        throw new BadRequestException(
          'La instancia WhatsApp seleccionada no existe o fue eliminada.',
        );
      }
    }

    if (nextEnabled === true && !selectedId) {
      throw new BadRequestException(
        'Debes seleccionar una instancia antes de habilitar CRM Comercial para mensajes reales.',
      );
    }

    const selectedInstance = selectedId
      ? availableInstances.find((instance) => instance.id === selectedId)
      : null;

    const updated = await this.prisma.crmCommercialSetting.upsert({
      where: { id: 'global' },
      create: {
        id: 'global',
        enabled: nextEnabled,
        selectedWhatsappInstanceId: selectedId ?? null,
        selectedWhatsappInstanceName:
          dto.selectedWhatsappInstanceName?.trim() ||
          selectedInstance?.instanceName ||
          current.selectedWhatsappInstanceName ||
          null,
        updatedByUserId: user.id,
      },
      update: {
        ...(dto.enabled != null ? { enabled: dto.enabled } : {}),
        selectedWhatsappInstanceId: selectedId ?? null,
        selectedWhatsappInstanceName:
          dto.selectedWhatsappInstanceName?.trim() ||
          selectedInstance?.instanceName ||
          current.selectedWhatsappInstanceName ||
          null,
        updatedByUserId: user.id,
      },
      include: {
        updatedByUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
      },
    });

    return this.getSettings(user).then((settings) => ({
      ok: true,
      settings,
      updated,
    }));
  }

  async getConversations(
    user: AuthUser,
    query: { limit?: string; updatedAfter?: string },
  ) {
    if (!this.isAdmin(user)) {
      throw new ForbiddenException('Solo ADMIN puede leer conversaciones de CRM Comercial');
    }

    const selected = await this.getSelectedWhatsappInstanceForCrm();
    if (!selected.selectedInstanceId) {
      return {
        items: [],
        warning: selected.warning,
      };
    }

    const limit = this.parseLimit(query.limit, 60, 200);
    const updatedAfter = this.parseDate(query.updatedAfter);

    const conversations = await this.prisma.whatsappConversation.findMany({
      where: {
        instanceId: selected.selectedInstanceId,
        NOT: [{ remoteJid: { contains: '@g.us' } }],
        ...(updatedAfter
          ? {
              OR: [
                { updatedAt: { gt: updatedAfter } },
                { lastMessageAt: { gt: updatedAfter } },
              ],
            }
          : {}),
      },
      orderBy: [{ lastMessageAt: 'desc' }, { updatedAt: 'desc' }],
      take: limit,
      include: {
        _count: { select: { messages: true } },
        messages: {
          orderBy: { sentAt: 'desc' },
          take: 1,
          select: {
            id: true,
            direction: true,
            messageType: true,
            body: true,
            caption: true,
            sentAt: true,
          },
        },
      },
    });

    // Para el preview del listado queremos el último mensaje del cliente (INCOMING).
    // Cuando el último mensaje real es OUTGOING, buscamos el último INCOMING por conversación
    // (distinct por conversationId) para evitar N+1.
    const outgoingConversationIds: string[] = [];
    for (const conv of conversations) {
      const last = conv.messages[0];
      if ((last?.direction ?? '').toString().toUpperCase() === 'OUTGOING') {
        outgoingConversationIds.push(conv.id);
      }
    }

    const lastIncomingByConversationId = new Map<
      string,
      {
        id: string;
        direction: string;
        messageType: string;
        body: string | null;
        caption: string | null;
        sentAt: Date | null;
      }
    >();
    if (outgoingConversationIds.length > 0) {
      const latestIncoming = await this.prisma.whatsappMessage.findMany({
        where: {
          conversationId: { in: outgoingConversationIds },
          direction: WhatsappMessageDirection.INCOMING,
        },
        orderBy: { sentAt: 'desc' },
        distinct: ['conversationId'],
        select: {
          id: true,
          conversationId: true,
          direction: true,
          messageType: true,
          body: true,
          caption: true,
          sentAt: true,
        },
      });

      for (const msg of latestIncoming) {
        lastIncomingByConversationId.set(msg.conversationId, {
          id: msg.id,
          direction: msg.direction,
          messageType: msg.messageType,
          body: msg.body,
          caption: msg.caption,
          sentAt: msg.sentAt,
        });
      }
    }

    const avatarByConversationId = new Map<string, string>();
    const avatarByIdentity = new Map<string, string>();
    try {
      const inboxConversations = await this.whatsappInboxService.getConversations(
        selected.selectedInstanceId,
        limit,
        updatedAfter,
      );
      for (const item of inboxConversations as Array<{
        id?: string;
        remoteJid?: string | null;
        remotePhone?: string | null;
        remoteAvatarUrl?: string | null;
      }>) {
        const avatar = (item.remoteAvatarUrl ?? '').trim();
        if (!avatar) continue;

        const id = (item.id ?? '').trim();
        if (id) {
          avatarByConversationId.set(id, avatar);
        }

        const normalizedPhone = this.normalizeComparablePhone(item.remotePhone);
        if (normalizedPhone) {
          avatarByIdentity.set(normalizedPhone, avatar);
        }

        const normalizedJid = this.normalizeComparablePhone(item.remoteJid);
        if (normalizedJid) {
          avatarByIdentity.set(normalizedJid, avatar);
        }
      }
    } catch (error) {
      console.warn(
        `[CrmCommercial] No se pudo cargar avatar de conversaciones: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }

    const crmCustomers = await this.prisma.crmCommercialCustomer.findMany({
      select: {
        id: true,
        nombre: true,
        telefono: true,
        estadoActual: true,
      },
    });

    const customerByPhone = new Map<
      string,
      { id: string; nombre: string; estadoActual: CrmCommercialCustomerStatus }
    >();
    for (const customer of crmCustomers) {
      const key = this.normalizeComparablePhone(customer.telefono);
      if (!key) continue;
      if (!customerByPhone.has(key)) {
        customerByPhone.set(key, {
          id: customer.id,
          nombre: customer.nombre,
          estadoActual: customer.estadoActual,
        });
      }
    }

    const items = conversations.map((conversation) => {
      const phone = this.normalizeComparablePhone(
        conversation.remotePhone ?? conversation.remoteJid,
      );
      const linked = phone ? customerByPhone.get(phone) : undefined;
      const last = conversation.messages[0] ?? null;
      const lastDirection = (last?.direction ?? '').toString().toUpperCase();
      const incomingFallback =
        lastDirection === 'OUTGOING'
          ? lastIncomingByConversationId.get(conversation.id) ?? null
          : null;
      const lastForPreview = incomingFallback ?? last;
      const contactName =
        (conversation.remoteName ?? '').trim() ||
        (conversation.remotePhone ?? '').trim() ||
        'Nuevo contacto';
      const avatarUrl =
        avatarByConversationId.get(conversation.id) ??
        (phone ? avatarByIdentity.get(phone) : null) ??
        null;

      return {
        id: conversation.id,
        instanceId: conversation.instanceId,
        remoteJid: conversation.remoteJid,
        remotePhone: conversation.remotePhone,
        remoteName: conversation.remoteName,
        contactName,
        lastMessageAt: conversation.lastMessageAt,
        unreadCount: conversation.unreadCount,
        messageCount: conversation._count.messages,
        lastMessagePreview: lastForPreview?.body ?? lastForPreview?.caption ?? null,
        lastMessageType: lastForPreview?.messageType ?? null,
        lastMessageDirection: lastForPreview?.direction ?? null,
        remoteAvatarUrl: avatarUrl,
        crmCustomerId: linked?.id ?? null,
        crmCustomerName: linked?.nombre ?? null,
        crmCustomerStatus: linked?.estadoActual ?? null,
        isNewContact: !linked,
        canConvertToCrm: !linked,
      };
    });

    return {
      items,
      warning: null,
    };
  }

  async getConversationMessages(
    user: AuthUser,
    conversationId: string,
    query: { limit?: string; before?: string; after?: string },
  ) {
    if (!this.isAdmin(user)) {
      throw new ForbiddenException('Solo ADMIN puede leer mensajes de CRM Comercial');
    }

    const selected = await this.getSelectedWhatsappInstanceForCrm();
    if (!selected.selectedInstanceId) {
      return {
        items: [],
        warning: selected.warning,
      };
    }

    const conversation = await this.prisma.whatsappConversation.findUnique({
      where: { id: conversationId },
      select: {
        id: true,
        instanceId: true,
        remoteJid: true,
        remotePhone: true,
        remoteName: true,
      },
    });

    if (!conversation || conversation.instanceId !== selected.selectedInstanceId) {
      throw new NotFoundException('Conversacion no encontrada para la instancia activa del CRM Comercial');
    }

    const limit = this.parseLimit(query.limit, 120, 300);
    const before = this.parseDate(query.before);
    const after = this.parseDate(query.after);

    const messages = await this.prisma.whatsappMessage.findMany({
      where: {
        conversationId,
        ...(before ? { sentAt: { lt: before } } : {}),
        ...(after ? { sentAt: { gt: after } } : {}),
      },
      orderBy: { sentAt: 'asc' },
      take: limit,
      select: {
        id: true,
        evolutionId: true,
        direction: true,
        messageType: true,
        body: true,
        caption: true,
        mediaUrl: true,
        mediaMimeType: true,
        senderName: true,
        sentAt: true,
        mediaStorageKey: true,
        mediaStatus: true,
        originalFileName: true,
        mediaFileSize: true,
      },
    });

    const conversationPhone = this.normalizeComparablePhone(
      conversation.remotePhone ?? conversation.remoteJid,
    );
    let linkedCustomer:
      | {
          id: string;
          nombre: string;
          estadoActual: CrmCommercialCustomerStatus;
        }
      | null = null;
    if (conversationPhone) {
      const candidates = await this.prisma.crmCommercialCustomer.findMany({
        select: {
          id: true,
          nombre: true,
          telefono: true,
          estadoActual: true,
          updatedAt: true,
        },
        orderBy: { updatedAt: 'desc' },
      });
      for (const candidate of candidates) {
        const key = this.normalizeComparablePhone(candidate.telefono);
        if (key == conversationPhone) {
          linkedCustomer = {
            id: candidate.id,
            nombre: candidate.nombre,
            estadoActual: candidate.estadoActual,
          };
          break;
        }
      }
    }

    return {
      conversation: {
        id: conversation.id,
        remoteJid: conversation.remoteJid,
        remotePhone: conversation.remotePhone,
        remoteName: conversation.remoteName,
        contactName:
          (conversation.remoteName ?? '').trim() ||
          (conversation.remotePhone ?? '').trim() ||
          'Nuevo contacto',
        crmCustomerId: linkedCustomer?.id ?? null,
        crmCustomerName: linkedCustomer?.nombre ?? null,
        crmCustomerStatus: linkedCustomer?.estadoActual ?? null,
        isNewContact: !linkedCustomer,
        canConvertToCrm: !linkedCustomer,
      },
      items: messages,
      warning: null,
    };
  }

  async markConversationRead(user: AuthUser, conversationId: string) {
    if (!this.isAdmin(user)) {
      throw new ForbiddenException('Solo ADMIN puede marcar conversaciones como leidas');
    }

    const selected = await this.getSelectedWhatsappInstanceForCrm();
    if (!selected.selectedInstanceId) {
      throw new BadRequestException('Selecciona una instancia antes de marcar como leido.');
    }

    const conversation = await this.prisma.whatsappConversation.findUnique({
      where: { id: conversationId },
      select: { id: true, instanceId: true },
    });
    if (!conversation || conversation.instanceId !== selected.selectedInstanceId) {
      throw new NotFoundException(
        'Conversacion no encontrada para la instancia activa del CRM Comercial',
      );
    }

    // Reutiliza la logica centralizada del inbox (resetea unreadCount + invalida caches si aplica)
    await this.whatsappInboxService.markRead(conversationId);

    return { ok: true };
  }

  async startConversationMessage(
    user: AuthUser,
    dto: SendCrmCommercialMessageDto,
  ) {
    if (!this.isAdmin(user)) {
      throw new ForbiddenException('Solo ADMIN puede enviar mensajes en CRM Comercial');
    }

    const text = (dto.text ?? '').trim();
    if (!text) {
      throw new BadRequestException('El mensaje no puede estar vacio.');
    }

    const selected = await this.getSelectedWhatsappInstanceForCrm();
    if (!selected.selectedInstanceId) {
      throw new BadRequestException('Selecciona una instancia antes de enviar mensajes.');
    }

    const instance = await this.prisma.userWhatsappInstance.findUnique({
      where: { id: selected.selectedInstanceId },
      select: { id: true, instanceName: true },
    });

    if (!instance) {
      throw new BadRequestException('La instancia seleccionada no existe.');
    }

    const { normalizedPhone, remoteJid } = this.normalizeRemoteJidFromPhone(
      dto.phone ?? '',
    );

    await this.ensureInstanceConnectedOrThrow(instance.instanceName);

    console.log(
      `[CRM-COMMERCIAL][SEND_TEXT][START] instanceName=${instance.instanceName} conversationId=(new) remoteJid=${remoteJid} remotePhone=${dto.phone ?? ''} normalizedPhone=${normalizedPhone}`,
    );
    console.log(
      `[CRM-COMMERCIAL][SEND_TEXT][START] evolutionPayload=${this.stringifyDebug({ number: remoteJid, text })}`,
    );

    let evolutionResult: unknown;
    try {
      evolutionResult = await this.whatsappService.sendTextMessage(
        instance.instanceName,
        remoteJid,
        text,
      );
      console.log(
        `[CRM-COMMERCIAL][SEND_TEXT][START] evolutionResponse=${this.stringifyDebug(evolutionResult)}`,
      );
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);
      console.error(
        `[CRM-COMMERCIAL][SEND_TEXT][START] send failed instanceName=${instance.instanceName} remoteJid=${remoteJid} normalizedPhone=${normalizedPhone} error=${reason}`,
      );
      if (/connection\s*closed/i.test(reason)) {
        throw new BadRequestException({
          message:
            `No se pudo enviar el mensaje: la instancia de WhatsApp ` +
            `"${instance.instanceName}" está desconectada (Connection Closed). ` +
            `Reconéctala y vuelve a intentar.`,
          code: 'CRM_WHATSAPP_INSTANCE_DISCONNECTED',
        });
      }
      throw error;
    }

    const evolutionMessageId = this.extractEvolutionMessageId(evolutionResult);
    const saved = await this.whatsappInboxService.recordOutgoingMessage(
      instance.id,
      remoteJid,
      text,
      evolutionMessageId,
    );

    const savedMessageId =
      (saved as { message?: { id?: string } })?.message?.id ?? null;
    if (savedMessageId) {
      await this.whatsappInboxService.attachEvolutionIdToMessage(
        savedMessageId,
        evolutionMessageId,
      );
    }

    const refreshedConversation = await this.prisma.whatsappConversation.findFirst({
      where: {
        instanceId: instance.id,
        OR: [{ remotePhone: normalizedPhone }, { remoteJid }],
      },
      orderBy: [{ lastMessageAt: 'desc' }, { updatedAt: 'desc' }],
      select: { id: true },
    });

    const normalizedComparable = this.normalizeComparablePhone(normalizedPhone);
    if (normalizedComparable) {
      const customers = await this.prisma.crmCommercialCustomer.findMany({
        select: { id: true, telefono: true, updatedAt: true },
        orderBy: { updatedAt: 'desc' },
      });
      for (const customer of customers) {
        if (this.normalizeComparablePhone(customer.telefono) === normalizedComparable) {
          await this.prisma.crmCommercialActivity.create({
            data: {
              customerId: customer.id,
              activityType: 'MENSAJE_SALIENTE',
              description: `Mensaje enviado por CRM Comercial: ${text.slice(0, 180)}`,
              createdByUserId: user.id,
            },
          });
          break;
        }
      }
    }

    return {
      ok: true,
      conversationId:
        refreshedConversation?.id ??
        ((saved as { conversation?: { id?: string } })?.conversation?.id ?? null),
      messageId: (saved as { message?: { id?: string } })?.message?.id ?? null,
    };
  }

  async replyConversation(
    user: AuthUser,
    conversationId: string,
    dto: SendCrmCommercialMessageDto,
  ) {
    if (!this.isAdmin(user)) {
      throw new ForbiddenException('Solo ADMIN puede responder mensajes en CRM Comercial');
    }

    const text = (dto.text ?? '').trim();
    if (!text) {
      throw new BadRequestException('El mensaje no puede estar vacio.');
    }

    const conversation = await this.prisma.whatsappConversation.findUnique({
      where: { id: conversationId },
      include: {
        instance: {
          select: { id: true, instanceName: true },
        },
      },
    });

    if (!conversation) {
      throw new NotFoundException('Conversacion no encontrada.');
    }

    const remoteJid = (conversation.remoteJid ?? '').trim();
    if (!remoteJid) {
      throw new BadRequestException({
        message: 'No se pudo enviar el mensaje: la conversación no tiene destino válido.',
        code: 'CRM_SEND_MESSAGE_FAILED',
      });
    }

    console.log(
      `[CRM-COMMERCIAL][SEND_TEXT][REPLY] instanceName=${conversation.instance.instanceName} conversationId=${conversationId} remoteJid=${remoteJid} remotePhone=${conversation.remotePhone ?? ''} finalTarget=${remoteJid}`,
    );
    console.log(
      `[CRM-COMMERCIAL][SEND_TEXT][REPLY] evolutionPayload=${this.stringifyDebug({ number: remoteJid, text })}`,
    );

    await this.ensureInstanceConnectedOrThrow(conversation.instance.instanceName);

    let evolutionResult: unknown;
    try {
      evolutionResult = await this.whatsappService.sendTextMessage(
        conversation.instance.instanceName,
        remoteJid,
        text,
      );
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);
      console.error(
        `[CRM-COMMERCIAL][SEND_TEXT][REPLY] send failed instanceName=${conversation.instance.instanceName} conversationId=${conversationId} remoteJid=${remoteJid} error=${reason}`,
      );
      if (/connection\s*closed/i.test(reason)) {
        throw new BadRequestException({
          message:
            `No se pudo enviar el mensaje: la instancia de WhatsApp ` +
            `"${conversation.instance.instanceName}" está desconectada (Connection Closed). ` +
            `Reconéctala y vuelve a intentar.`,
          code: 'CRM_WHATSAPP_INSTANCE_DISCONNECTED',
        });
      }
      throw error;
    }
    console.log(
      `[CRM-COMMERCIAL][SEND_TEXT][REPLY] evolutionResponse=${this.stringifyDebug(evolutionResult)}`,
    );

    const evolutionMessageId = this.extractEvolutionMessageId(evolutionResult);
    let savedMessageId: string | null = null;
    try {
      const saved = await this.whatsappInboxService.recordOutgoingMessage(
        conversation.instanceId,
        remoteJid,
        text,
        evolutionMessageId,
      );

      savedMessageId =
        (saved as { message?: { id?: string } })?.message?.id ?? null;
      if (savedMessageId) {
        await this.whatsappInboxService.attachEvolutionIdToMessage(
          savedMessageId,
          evolutionMessageId,
        );
      }
    } catch (persistError) {
      console.error(
        `[CRM-COMMERCIAL][SEND_TEXT][REPLY] post-send persist warning conversationId=${conversationId} remoteJid=${remoteJid} error=${this.stringifyDebug(persistError)}`,
      );
    }

    try {
      const normalizedComparable = this.normalizeComparablePhone(
        conversation.remotePhone ?? remoteJid,
      );
      if (normalizedComparable) {
        const customers = await this.prisma.crmCommercialCustomer.findMany({
          select: { id: true, telefono: true, updatedAt: true },
          orderBy: { updatedAt: 'desc' },
        });
        for (const customer of customers) {
          if (this.normalizeComparablePhone(customer.telefono) === normalizedComparable) {
            await this.prisma.crmCommercialActivity.create({
              data: {
                customerId: customer.id,
                activityType: 'MENSAJE_SALIENTE',
                description: `Mensaje enviado por CRM Comercial: ${text.slice(0, 180)}`,
                createdByUserId: user.id,
              },
            });
            break;
          }
        }
      }
    } catch (activityError) {
      console.error(
        `[CRM-COMMERCIAL][SEND_TEXT][REPLY] activity-log warning conversationId=${conversationId} remoteJid=${remoteJid} error=${this.stringifyDebug(activityError)}`,
      );
    }

    return {
      ok: true,
      conversationId,
      messageId: savedMessageId,
    };
  }

  async replyConversationMedia(
    user: AuthUser,
    conversationId: string,
    dto: ReplyCrmCommercialMediaMessageDto,
  ) {
    if (!this.isAdmin(user)) {
      throw new ForbiddenException('Solo ADMIN puede responder mensajes en CRM Comercial');
    }

    if (!dto.mediaType || !dto.mimeType || !dto.fileName || !dto.base64Data) {
      throw new BadRequestException('mediaType, mimeType, fileName y base64Data son requeridos.');
    }

    const selected = await this.getSelectedWhatsappInstanceForCrm();
    if (!selected.selectedInstanceId) {
      throw new BadRequestException('Selecciona una instancia antes de enviar mensajes.');
    }

    const conversation = await this.prisma.whatsappConversation.findUnique({
      where: { id: conversationId },
      include: {
        instance: {
          select: { id: true, instanceName: true },
        },
      },
    });

    if (!conversation || conversation.instanceId !== selected.selectedInstanceId) {
      throw new NotFoundException('Conversacion no encontrada para la instancia activa.');
    }

    try {
      const mediaBuffer = Buffer.from(dto.base64Data, 'base64');

      // ── Redis idempotency lock (prevent double-send for same file) ──
      const lockKey = `crm-media:${conversationId}:${dto.fileName}:${mediaBuffer.length}`;
      const acquired = await this.redis.tryLock(lockKey, 30);
      if (!acquired) {
        throw new BadRequestException({
          message: 'El archivo ya está siendo enviado. Por favor espera.',
          code: 'CRM_MEDIA_DUPLICATE',
        });
      }

      const saved = await this.whatsappInboxService.recordOutgoingMediaMessage({
        instanceId: conversation.instanceId,
        remoteJid: conversation.remoteJid,
        bytes: mediaBuffer,
        mediaType: dto.mediaType as 'image' | 'video' | 'audio' | 'document',
        mimeType: dto.mimeType,
        fileName: dto.fileName,
        caption: dto.caption,
      });

      const evolutionResult = await this.whatsappService.sendMediaMessage({
        instanceName: conversation.instance.instanceName,
        remoteJid: conversation.remoteJid,
        bytes: mediaBuffer,
        mediaType: dto.mediaType as 'image' | 'video' | 'audio' | 'document',
        mimeType: dto.mimeType,
        fileName: dto.fileName,
        caption: dto.caption,
      });

      const savedMessageId =
        (saved as { message?: { id?: string } })?.message?.id ?? null;
      if (savedMessageId) {
        await this.whatsappInboxService.attachEvolutionIdToMessage(
          savedMessageId,
          this.extractEvolutionMessageId(evolutionResult),
        );
      }

      const normalizedComparable = this.normalizeComparablePhone(
        conversation.remotePhone ?? conversation.remoteJid,
      );
      if (normalizedComparable) {
        const customers = await this.prisma.crmCommercialCustomer.findMany({
          select: { id: true, telefono: true, updatedAt: true },
          orderBy: { updatedAt: 'desc' },
        });
        for (const customer of customers) {
          if (
            this.normalizeComparablePhone(customer.telefono) ===
            normalizedComparable
          ) {
            await this.prisma.crmCommercialActivity.create({
              data: {
                customerId: customer.id,
                activityType: 'MENSAJE_MEDIA_SALIENTE',
                description: `${dto.mediaType.toUpperCase()} enviado por CRM Comercial${dto.caption ? ': ' + dto.caption.slice(0, 100) : ''}`,
                createdByUserId: user.id,
              },
            });
            break;
          }
        }
      }

      return {
        ok: true,
        conversationId,
        messageId: (saved as { message?: { id?: string } })?.message?.id ?? null,
      };
    } catch (error) {
      console.error('[CrmCommercial][ReplyMedia] Error:', {
        conversationId,
        mediaType: dto.mediaType,
        error: error instanceof Error ? error.message : String(error),
      });
      throw new BadRequestException(
        `No se pudo enviar el archivo: ${error instanceof Error ? error.message : 'Error desconocido'}`,
      );
    }
  }

  async deleteConversationMessage(
    user: AuthUser,
    conversationId: string,
    messageId: string,
  ) {
    if (!this.isAdmin(user)) {
      throw new ForbiddenException('Solo ADMIN puede eliminar mensajes en CRM Comercial');
    }

    const conversation = await this.prisma.whatsappConversation.findUnique({
      where: { id: conversationId },
      include: { instance: { select: { instanceName: true } } },
    });

    if (!conversation) {
      throw new NotFoundException('Conversacion no encontrada.');
    }

    const message = await this.prisma.whatsappMessage.findFirst({
      where: {
        id: messageId,
        conversationId,
      },
      select: {
        id: true,
        direction: true,
        evolutionId: true,
      },
    });

    if (!message) {
      throw new NotFoundException('Mensaje no encontrado en esta conversación.');
    }

    if (message.direction !== 'OUTGOING') {
      throw new BadRequestException('Solo se pueden eliminar mensajes salientes.');
    }

    if (!message.evolutionId) {
      throw new BadRequestException('Este mensaje no tiene identificador remoto para eliminarse.');
    }

    await this.whatsappService.deleteMessage({
      instanceName: conversation.instance.instanceName,
      remoteJid: conversation.remoteJid,
      messageId: message.evolutionId,
      fromMe: true,
    });

    await this.prisma.whatsappMessage.delete({ where: { id: message.id } });

    return {
      ok: true,
      conversationId,
      messageId,
      deleted: true,
    };
  }

  async startConversationMediaMessage(
    user: AuthUser,
    dto: StartCrmCommercialMediaMessageDto,
  ) {
    if (!this.isAdmin(user)) {
      throw new ForbiddenException(
        'Solo ADMIN puede iniciar conversaciones en CRM Comercial',
      );
    }

    if (!dto.phone) {
      throw new BadRequestException('phone requerido.');
    }

    if (!dto.mediaType || !dto.mimeType || !dto.fileName || !dto.base64Data) {
      throw new BadRequestException('mediaType, mimeType, fileName y base64Data son requeridos.');
    }

    const { normalizedPhone, remoteJid } =
      this.normalizeRemoteJidFromPhone(dto.phone);

    const selected = await this.getSelectedWhatsappInstanceForCrm();
    if (!selected.selectedInstanceId) {
      throw new BadRequestException('Selecciona una instancia antes de enviar mensajes.');
    }

    try {
      const mediaBuffer = Buffer.from(dto.base64Data, 'base64');

      // ── Redis idempotency lock ──
      const lockKey = `crm-start-media:${normalizedPhone}:${dto.fileName}:${mediaBuffer.length}`;
      const acquired = await this.redis.tryLock(lockKey, 30);
      if (!acquired) {
        throw new BadRequestException({
          message: 'El archivo ya está siendo enviado. Por favor espera.',
          code: 'CRM_MEDIA_DUPLICATE',
        });
      }

      const saved = await this.whatsappInboxService.recordOutgoingMediaMessage({
        instanceId: selected.selectedInstanceId,
        remoteJid,
        bytes: mediaBuffer,
        mediaType: dto.mediaType as 'image' | 'video' | 'audio' | 'document',
        mimeType: dto.mimeType,
        fileName: dto.fileName,
        caption: dto.caption,
      });

      const instance = await this.prisma.userWhatsappInstance.findUnique({
        where: { id: selected.selectedInstanceId },
        select: { instanceName: true },
      });

      if (!instance) {
        throw new BadRequestException(
          'La instancia seleccionada no existe.',
        );
      }

      const evolutionResult = await this.whatsappService.sendMediaMessage({
        instanceName: instance.instanceName,
        remoteJid,
        bytes: mediaBuffer,
        mediaType: dto.mediaType as 'image' | 'video' | 'audio' | 'document',
        mimeType: dto.mimeType,
        fileName: dto.fileName,
        caption: dto.caption,
      });

      const savedMessageId =
        (saved as { message?: { id?: string } })?.message?.id ?? null;
      if (savedMessageId) {
        await this.whatsappInboxService.attachEvolutionIdToMessage(
          savedMessageId,
          this.extractEvolutionMessageId(evolutionResult),
        );
      }

      const customers = await this.prisma.crmCommercialCustomer.findMany({
        select: { id: true, telefono: true, updatedAt: true },
        orderBy: { updatedAt: 'desc' },
      });
      for (const customer of customers) {
        if (this.normalizeComparablePhone(customer.telefono) === normalizedPhone) {
          await this.prisma.crmCommercialActivity.create({
            data: {
              customerId: customer.id,
              activityType: 'MENSAJE_MEDIA_INICIADO',
              description: `${dto.mediaType.toUpperCase()} enviado por CRM Comercial${dto.caption ? ': ' + dto.caption.slice(0, 100) : ''}`,
              createdByUserId: user.id,
            },
          });
          break;
        }
      }

      return {
        ok: true,
        phone: normalizedPhone,
        messageId: (saved as { message?: { id?: string } })?.message?.id ?? null,
      };
    } catch (error) {
      console.error('[CrmCommercial][StartMediaMessage] Error:', {
        phone: normalizedPhone,
        mediaType: dto.mediaType,
        error: error instanceof Error ? error.message : String(error),
      });
      throw new BadRequestException(
        `No se pudo enviar el archivo: ${error instanceof Error ? error.message : 'Error desconocido'}`,
      );
    }
  }

  async create(user: AuthUser, dto: CreateCrmCommercialCustomerDto) {
    if (!this.canWrite(user)) {
      throw new ForbiddenException('No tienes permisos para crear clientes CRM');
    }

    const phone = this.normalizePhone(dto.telefono);
    if (!phone) {
      throw new BadRequestException('Telefono requerido');
    }

    const assignedUserId =
      user.role === Role.VENDEDOR ? user.id : dto.responsableUserId ?? user.id;

    const normalizedName = dto.nombre.trim();
    await this.ensureClientExists(dto.clientId);
    await this.ensureNoDuplicateForCreate({
      nombre: normalizedName,
      telefono: phone,
      clientId: dto.clientId,
    });

    const created = await this.prisma.crmCommercialCustomer.create({
      data: {
        nombre: normalizedName,
        telefono: phone,
        direccion: this.normalizeText(dto.direccion),
        ciudad: this.normalizeText(dto.ciudad),
        etiqueta: this.normalizeText(dto.etiqueta),
        clientId: dto.clientId,
        responsableUserId: assignedUserId,
        estadoActual: dto.estadoActual ?? CrmCommercialCustomerStatus.NUEVO,
        nextAction: this.normalizeText(dto.nextAction),
        nextActionAt: dto.nextActionAt ? new Date(dto.nextActionAt) : null,
        observacion: this.normalizeText(dto.observacion),
        createdByUserId: user.id,
      },
      include: {
        responsableUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
        createdByUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
      },
    });

    await this.prisma.crmCommercialStatusHistory.create({
      data: {
        customerId: created.id,
        estadoAnterior: null,
        estadoNuevo: created.estadoActual,
        changedByUserId: user.id,
        nota: 'Registro inicial en CRM comercial',
      },
    });

    return created;
  }

  async findAll(user: AuthUser, query: CrmCommercialQueryDto) {
    const page = Math.max(1, Number(query.page ?? 1));
    const pageSize = Math.min(200, Math.max(1, Number(query.pageSize ?? 20)));
    const skip = (page - 1) * pageSize;

    const andFilters: Prisma.CrmCommercialCustomerWhereInput[] = [];
    if (query.status) {
      andFilters.push({ estadoActual: query.status });
    }
    if (query.responsableUserId) {
      andFilters.push({ responsableUserId: query.responsableUserId });
    }
    if (query.q) {
      andFilters.push({
        OR: [
          { nombre: { contains: query.q, mode: 'insensitive' } },
          { telefono: { contains: query.q, mode: 'insensitive' } },
          { direccion: { contains: query.q, mode: 'insensitive' } },
          { ciudad: { contains: query.q, mode: 'insensitive' } },
        ],
      });
    }

    const onlyMine = this.parseBool(query.onlyMine) ?? false;
    if (!this.isAdmin(user) && user.role === Role.VENDEDOR) {
      andFilters.push({ responsableUserId: user.id });
    } else if (onlyMine) {
      andFilters.push({ responsableUserId: user.id });
    }

    const where: Prisma.CrmCommercialCustomerWhereInput =
      andFilters.length > 0 ? { AND: andFilters } : {};

    const [total, items] = await this.prisma.$transaction([
      this.prisma.crmCommercialCustomer.count({ where }),
      this.prisma.crmCommercialCustomer.findMany({
        where,
        skip,
        take: pageSize,
        orderBy: [{ updatedAt: 'desc' }, { createdAt: 'desc' }],
        include: {
          responsableUser: {
            select: { id: true, nombreCompleto: true, role: true },
          },
          createdByUser: {
            select: { id: true, nombreCompleto: true, role: true },
          },
          client: {
            select: {
              id: true,
              nombre: true,
              telefono: true,
              email: true,
            },
          },
        },
      }),
    ]);

    return {
      page,
      pageSize,
      total,
      totalPages: Math.max(1, Math.ceil(total / pageSize)),
      items,
    };
  }

  async findOne(user: AuthUser, id: string) {
    await this.ensureCustomerAccessible(user, id);

    return this.prisma.crmCommercialCustomer.findUnique({
      where: { id },
      include: {
        responsableUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
        createdByUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
        client: {
          select: {
            id: true,
            nombre: true,
            telefono: true,
            email: true,
            direccion: true,
          },
        },
        statusHistory: {
          orderBy: { createdAt: 'desc' },
          take: 120,
          include: {
            changedByUser: {
              select: { id: true, nombreCompleto: true, role: true },
            },
          },
        },
        notes: {
          orderBy: { createdAt: 'desc' },
          take: 120,
          include: {
            authorUser: {
              select: { id: true, nombreCompleto: true, role: true },
            },
          },
        },
        activities: {
          orderBy: { createdAt: 'desc' },
          take: 120,
          include: {
            createdByUser: {
              select: { id: true, nombreCompleto: true, role: true },
            },
            assignedToUser: {
              select: { id: true, nombreCompleto: true, role: true },
            },
          },
        },
      },
    });
  }

  async update(user: AuthUser, id: string, dto: UpdateCrmCommercialCustomerDto) {
    if (!this.canWrite(user)) {
      throw new ForbiddenException('No tienes permisos para editar clientes CRM');
    }

    const current = await this.ensureCustomerAccessible(user, id);

    let assignedUserId = dto.responsableUserId;
    if (user.role === Role.VENDEDOR) {
      assignedUserId = current.responsableUserId ?? user.id;
    }

    const normalizedName = dto.nombre?.trim() ?? current.nombre;
    const normalizedPhone = dto.telefono
      ? this.normalizePhone(dto.telefono)
      : current.telefono;
    const nextClientId = dto.clientId ?? current.clientId ?? undefined;

    await this.ensureClientExists(nextClientId);
    await this.ensureNoDuplicateForUpdate(id, {
      nombre: normalizedName,
      telefono: normalizedPhone,
      clientId: nextClientId,
    });

    const updated = await this.prisma.crmCommercialCustomer.update({
      where: { id },
      data: {
        nombre: dto.nombre?.trim(),
        telefono: dto.telefono ? this.normalizePhone(dto.telefono) : undefined,
        direccion:
          dto.direccion == null ? undefined : this.normalizeText(dto.direccion),
        ciudad: dto.ciudad == null ? undefined : this.normalizeText(dto.ciudad),
        etiqueta:
          dto.etiqueta == null ? undefined : this.normalizeText(dto.etiqueta),
        clientId: dto.clientId,
        responsableUserId: assignedUserId,
        nextActionAt:
          dto.nextActionAt == null ? undefined : new Date(dto.nextActionAt),
        nextAction:
          dto.nextAction == null ? undefined : this.normalizeText(dto.nextAction),
        observacion:
          dto.observacion == null ? undefined : this.normalizeText(dto.observacion),
      },
      include: {
        responsableUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
        createdByUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
      },
    });

    return updated;
  }

  async changeStatus(
    user: AuthUser,
    id: string,
    dto: ChangeCrmCommercialStatusDto,
  ) {
    if (!this.canWrite(user)) {
      throw new ForbiddenException('No tienes permisos para cambiar estado');
    }

    const customer = await this.ensureCustomerAccessible(user, id);

    if (customer.estadoActual === dto.status) {
      return this.prisma.crmCommercialCustomer.findUnique({
        where: { id },
        include: {
          responsableUser: {
            select: { id: true, nombreCompleto: true, role: true },
          },
        },
      });
    }

    const updated = await this.prisma.crmCommercialCustomer.update({
      where: { id },
      data: {
        estadoActual: dto.status,
        lastInteractionAt: new Date(),
      },
      include: {
        responsableUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
      },
    });

    await this.prisma.crmCommercialStatusHistory.create({
      data: {
        customerId: id,
        estadoAnterior: customer.estadoActual,
        estadoNuevo: dto.status,
        changedByUserId: user.id,
        nota: this.normalizeText(dto.note),
      },
    });

    return updated;
  }

  async addNote(user: AuthUser, id: string, dto: CreateCrmCommercialNoteDto) {
    if (!this.canWrite(user)) {
      throw new ForbiddenException('No tienes permisos para agregar notas');
    }

    await this.ensureCustomerAccessible(user, id);

    const note = await this.prisma.crmCommercialNote.create({
      data: {
        customerId: id,
        authorUserId: user.id,
        note: dto.note.trim(),
      },
      include: {
        authorUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
      },
    });

    await this.prisma.crmCommercialCustomer.update({
      where: { id },
      data: {
        lastInteractionAt: new Date(),
      },
    });

    return note;
  }

  async addActivity(
    user: AuthUser,
    id: string,
    dto: CreateCrmCommercialActivityDto,
  ) {
    if (!this.canWrite(user)) {
      throw new ForbiddenException('No tienes permisos para registrar actividades');
    }

    await this.ensureCustomerAccessible(user, id);

    return this.prisma.crmCommercialActivity.create({
      data: {
        customerId: id,
        createdByUserId: user.id,
        assignedToUserId: dto.assignedToUserId,
        activityType: dto.type.trim(),
        description: dto.description.trim(),
        dueAt: dto.dueAt ? new Date(dto.dueAt) : null,
      },
      include: {
        createdByUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
        assignedToUser: {
          select: { id: true, nombreCompleto: true, role: true },
        },
      },
    });
  }

  // ─── Phase 2: Follow-up Tasks ─────────────────────────────────────────────

  private taskUserInclude = {
    select: { id: true, nombreCompleto: true, role: true },
  } as const;

  async createFollowupTask(
    user: AuthUser,
    customerId: string,
    dto: CreateCrmCommercialFollowupTaskDto,
  ) {
    await this.ensureCustomerAccessible(user, customerId);

    const task = await this.prisma.crmCommercialFollowupTask.create({
      data: {
        customerId,
        title: dto.title.trim(),
        description: this.normalizeText(dto.description),
        dueDate: dto.dueDate ? new Date(dto.dueDate) : null,
        priority: dto.priority ?? CrmCommercialFollowupTaskPriority.NORMAL,
        assignedUserId: dto.assignedUserId,
        createdByUserId: user.id,
      },
      include: {
        assignedUser: { select: { id: true, nombreCompleto: true, role: true } },
        createdByUser: { select: { id: true, nombreCompleto: true, role: true } },
        completedByUser: { select: { id: true, nombreCompleto: true, role: true } },
      },
    });

    await this.prisma.crmCommercialActivity.create({
      data: {
        customerId,
        createdByUserId: user.id,
        activityType: 'TAREA_CREADA',
        description: `Tarea de seguimiento creada: ${task.title}`,
      },
    });

    return task;
  }

  async listFollowupTasks(
    user: AuthUser,
    query: CrmCommercialFollowupTaskQueryDto,
  ) {
    const now = new Date();
    const andFilters: Prisma.CrmCommercialFollowupTaskWhereInput[] = [];

    if (query.customerId) {
      andFilters.push({ customerId: query.customerId });
    }
    if (query.assignedUserId) {
      andFilters.push({ assignedUserId: query.assignedUserId });
    }
    if (query.priority) {
      andFilters.push({
        priority: query.priority as CrmCommercialFollowupTaskPriority,
      });
    }

    const overdueOnly = this.parseBool(query.overdueOnly) ?? false;
    if (overdueOnly) {
      andFilters.push({
        status: CrmCommercialFollowupTaskStatus.PENDIENTE,
        dueDate: { lt: now },
      });
    } else if (query.status) {
      andFilters.push({
        status: query.status as CrmCommercialFollowupTaskStatus,
      });
    }

    if (query.dueFrom) {
      andFilters.push({ dueDate: { gte: new Date(query.dueFrom) } });
    }
    if (query.dueTo) {
      andFilters.push({ dueDate: { lte: new Date(query.dueTo) } });
    }

    const tasks = await this.prisma.crmCommercialFollowupTask.findMany({
      where: andFilters.length > 0 ? { AND: andFilters } : {},
      include: {
        assignedUser: { select: { id: true, nombreCompleto: true, role: true } },
        createdByUser: { select: { id: true, nombreCompleto: true, role: true } },
        completedByUser: { select: { id: true, nombreCompleto: true, role: true } },
      },
      orderBy: [{ dueDate: 'asc' }, { createdAt: 'desc' }],
    });

    return tasks.map((task) => ({
      ...task,
      effectiveStatus:
        task.status === CrmCommercialFollowupTaskStatus.PENDIENTE &&
        task.dueDate &&
        task.dueDate < now
          ? CrmCommercialFollowupTaskStatus.VENCIDA
          : task.status,
    }));
  }

  async updateFollowupTask(
    user: AuthUser,
    taskId: string,
    dto: UpdateCrmCommercialFollowupTaskDto,
  ) {
    const task = await this.prisma.crmCommercialFollowupTask.findUnique({
      where: { id: taskId },
      select: {
        id: true,
        customerId: true,
        title: true,
        dueDate: true,
        priority: true,
        status: true,
      },
    });
    if (!task) {
      throw new NotFoundException('Tarea de seguimiento no encontrada');
    }

    const updateData: {
      title?: string;
      description?: string | null;
      assignedUserId?: string | null;
      dueDate?: Date;
      priority?: CrmCommercialFollowupTaskPriority;
    } = {};
    const activityParts: string[] = [];

    if (dto.title !== undefined) updateData.title = dto.title.trim();
    if (dto.description !== undefined) {
      updateData.description = this.normalizeText(dto.description) ?? null;
    }
    if (dto.assignedUserId !== undefined) {
      updateData.assignedUserId = dto.assignedUserId || null;
    }
    if (dto.dueDate !== undefined) {
      const newDate = new Date(dto.dueDate);
      if (!task.dueDate || task.dueDate.getTime() !== newDate.getTime()) {
        activityParts.push(
          `Fecha cambiada a ${newDate.toLocaleDateString('es-DO')}`,
        );
      }
      updateData.dueDate = newDate;
    }
    if (dto.priority !== undefined && dto.priority !== task.priority) {
      activityParts.push(`Prioridad cambiada a ${dto.priority}`);
      updateData.priority = dto.priority;
    }

    const updated = await this.prisma.crmCommercialFollowupTask.update({
      where: { id: taskId },
      data: updateData,
      include: {
        assignedUser: { select: { id: true, nombreCompleto: true, role: true } },
        createdByUser: { select: { id: true, nombreCompleto: true, role: true } },
        completedByUser: { select: { id: true, nombreCompleto: true, role: true } },
      },
    });

    if (activityParts.length > 0) {
      await this.prisma.crmCommercialActivity.create({
        data: {
          customerId: task.customerId,
          createdByUserId: user.id,
          activityType: 'TAREA_MODIFICADA',
          description: `Tarea "${updated.title}": ${activityParts.join(', ')}`,
        },
      });
    }

    return updated;
  }

  async completeFollowupTask(user: AuthUser, taskId: string) {
    const task = await this.prisma.crmCommercialFollowupTask.findUnique({
      where: { id: taskId },
      select: { id: true, customerId: true, title: true, status: true },
    });
    if (!task) {
      throw new NotFoundException('Tarea de seguimiento no encontrada');
    }
    if (task.status === CrmCommercialFollowupTaskStatus.COMPLETADA) {
      throw new BadRequestException('La tarea ya está completada');
    }
    if (task.status === CrmCommercialFollowupTaskStatus.CANCELADA) {
      throw new BadRequestException(
        'No se puede completar una tarea cancelada',
      );
    }

    const completed = await this.prisma.crmCommercialFollowupTask.update({
      where: { id: taskId },
      data: {
        status: CrmCommercialFollowupTaskStatus.COMPLETADA,
        completedAt: new Date(),
        completedByUserId: user.id,
      },
      include: {
        assignedUser: { select: { id: true, nombreCompleto: true, role: true } },
        createdByUser: { select: { id: true, nombreCompleto: true, role: true } },
        completedByUser: { select: { id: true, nombreCompleto: true, role: true } },
      },
    });

    await this.prisma.crmCommercialActivity.create({
      data: {
        customerId: task.customerId,
        createdByUserId: user.id,
        activityType: 'TAREA_COMPLETADA',
        description: `Tarea completada: ${task.title}`,
      },
    });

    return completed;
  }

  async cancelFollowupTask(user: AuthUser, taskId: string) {
    const task = await this.prisma.crmCommercialFollowupTask.findUnique({
      where: { id: taskId },
      select: { id: true, customerId: true, title: true, status: true },
    });
    if (!task) {
      throw new NotFoundException('Tarea de seguimiento no encontrada');
    }
    if (task.status === CrmCommercialFollowupTaskStatus.COMPLETADA) {
      throw new BadRequestException(
        'No se puede cancelar una tarea completada',
      );
    }
    if (task.status === CrmCommercialFollowupTaskStatus.CANCELADA) {
      throw new BadRequestException('La tarea ya está cancelada');
    }

    const cancelled = await this.prisma.crmCommercialFollowupTask.update({
      where: { id: taskId },
      data: { status: CrmCommercialFollowupTaskStatus.CANCELADA },
      include: {
        assignedUser: { select: { id: true, nombreCompleto: true, role: true } },
        createdByUser: { select: { id: true, nombreCompleto: true, role: true } },
        completedByUser: { select: { id: true, nombreCompleto: true, role: true } },
      },
    });

    await this.prisma.crmCommercialActivity.create({
      data: {
        customerId: task.customerId,
        createdByUserId: user.id,
        activityType: 'TAREA_CANCELADA',
        description: `Tarea cancelada: ${task.title}`,
      },
    });

    return cancelled;
  }
}
