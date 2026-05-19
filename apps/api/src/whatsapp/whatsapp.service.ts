import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ModuleRef } from '@nestjs/core';
import * as http from 'node:http';
import * as https from 'node:https';
import { ConfigService } from '@nestjs/config';
import { PrismaService } from '../prisma/prisma.service';
import { CreateWhatsappInstanceDto } from './dto/create-whatsapp-instance.dto';

@Injectable()
export class WhatsappService {
  private readonly requestTimeoutMs = 10_000;

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
    private readonly moduleRef: ModuleRef,
  ) {
    // Startup sanity-check: Evolution API URL must NOT point to this server itself.
    const evoUrl = (config.get<string>('EVOLUTION_API_URL') ?? '')
      .trim()
      .replace(/\/$/, '');
    const selfUrl = (config.get<string>('PUBLIC_BASE_URL') ?? '')
      .trim()
      .replace(/\/$/, '');
    if (!evoUrl) {
      console.warn(
        '[WhatsApp] ADVERTENCIA: EVOLUTION_API_URL no está configurada. Las funciones de WhatsApp no funcionarán.',
      );
    } else if (!/^https?:\/\//i.test(evoUrl)) {
      console.error(
        `[WhatsApp] CONFIGURACION INVALIDA: EVOLUTION_API_URL debe iniciar con http:// o https://. Valor actual: ${evoUrl}`,
      );
    } else if (selfUrl && evoUrl.toLowerCase() === selfUrl.toLowerCase()) {
      console.error(
        `[WhatsApp] ¡CONFIGURACIÓN CRÍTICA INCORRECTA! EVOLUTION_API_URL apunta a este mismo servidor (${evoUrl}). ` +
          'Debes configurar EVOLUTION_API_URL con la URL del servidor Evolution API externo, NO la de este API.',
      );
    }
  }

  private get evolutionBaseUrl(): string {
    const raw = (this.config.get<string>('EVOLUTION_API_URL') ?? '').trim();
    if (!raw) return '';
    if (!/^https?:\/\//i.test(raw)) {
      throw new ServiceUnavailableException(
        `EVOLUTION_API_URL invalida: debe iniciar con http:// o https://. Valor actual: ${raw}`,
      );
    }
    return raw.endsWith('/') ? raw.slice(0, -1) : raw;
  }

  private get evolutionApiKey(): string {
    return (this.config.get<string>('EVOLUTION_API_KEY') ?? '').trim();
  }

  private buildHeaders() {
    return {
      'Content-Type': 'application/json',
      apikey: this.evolutionApiKey,
    };
  }

  private resolvePublicBaseUrl(): string {
    const raw = (
      this.config.get<string>('PUBLIC_BASE_URL') ??
      this.config.get<string>('API_BASE_URL') ??
      ''
    ).trim();
    if (!raw) {
      throw new ServiceUnavailableException(
        'PUBLIC_BASE_URL o API_BASE_URL no está configurada para construir el webhook de WhatsApp.',
      );
    }
    if (!/^https?:\/\//i.test(raw)) {
      throw new ServiceUnavailableException(
        `PUBLIC_BASE_URL inválida: debe iniciar con http:// o https://. Valor actual: ${raw}`,
      );
    }
    return raw.endsWith('/') ? raw.slice(0, -1) : raw;
  }

  private buildWebhookUrl(instanceName: string): string {
    return `${this.resolvePublicBaseUrl()}/whatsapp-inbox/webhook/${encodeURIComponent(instanceName)}`;
  }

  private async isGlobalWebhookEnabled(): Promise<boolean> {
    try {
      const config = await this.prisma.appConfig.upsert({
        where: { id: 'global' },
        create: { id: 'global' },
        update: {},
      });
      return !!config.whatsappWebhookEnabled;
    } catch (error) {
      console.warn(
        `[WhatsApp][Webhook] No se pudo leer app_config para webhook global: ${this.describeEvolutionError(error)}`,
      );
      return false;
    }
  }

  private async configureInstanceWebhook(
    instanceName: string,
    enabled: boolean,
  ): Promise<void> {
    const webhookUrl = this.buildWebhookUrl(instanceName);
    const events = [
      'MESSAGES_UPSERT',
      'MESSAGES_UPDATE',
      'MESSAGES_DELETE',
      'SEND_MESSAGE',
      'CONNECTION_UPDATE',
    ];

    // Evolution API v2 official format.
    // SEND_MESSAGE is required to see messages sent directly from the connected WhatsApp instance.
    const payload = {
      enabled,
      url: webhookUrl,
      webhook_by_events: false,
      webhook_base64: true,
      events,
    };

    // Some deployed Evolution builds still accept only the manager-style nested shape.
    const legacyPayload = {
      webhook: {
        enabled,
        url: webhookUrl,
        byEvents: false,
        base64: true,
        webhookByEvents: false,
        webhookBase64: true,
        events,
      },
    };

    try {
      await this.fetchEvolution(
        `/webhook/set/${encodeURIComponent(instanceName)}`,
        {
          method: 'POST',
          body: JSON.stringify(payload),
        },
      );
    } catch (error) {
      console.warn(
        `[WhatsApp][Webhook] Formato oficial falló para "${instanceName}", intentando formato legacy: ${this.describeEvolutionError(error)}`,
      );
      await this.fetchEvolution(
        `/webhook/set/${encodeURIComponent(instanceName)}`,
        {
          method: 'POST',
          body: JSON.stringify(legacyPayload),
        },
      );
    }

    console.log(
      `[WhatsApp][Webhook] Configurado webhook para "${instanceName}" enabled=${enabled} events=${events.join(',')} url=${webhookUrl}`,
    );
  }

  async syncWebhookConfigurationForAllInstances(enabled: boolean) {
    const instances = await this.prisma.userWhatsappInstance.findMany({
      select: { instanceName: true, userId: true },
      orderBy: { createdAt: 'asc' },
    });

    let updated = 0;
    for (const instance of instances) {
      try {
        await this.configureInstanceWebhook(instance.instanceName, enabled);
        updated++;
      } catch (error) {
        console.error(
          `[WhatsApp][Webhook] Error sincronizando webhook para "${instance.instanceName}": ${this.describeEvolutionError(error)}`,
        );
      }
    }

    console.log(
      `[WhatsApp][Webhook] Sincronización global completada. enabled=${enabled}, actualizadas=${updated}/${instances.length}`,
    );

    return { updated, total: instances.length, enabled };
  }

  // ─── CRM: list all instances with webhook status ────────────────────────

  async listAllInstancesForCrm() {
    // 1. User instances
    const userInstances = await this.prisma.userWhatsappInstance.findMany({
      orderBy: { createdAt: 'asc' },
      select: {
        id: true,
        instanceName: true,
        status: true,
        phoneNumber: true,
        webhookEnabled: true,
        user: {
          select: {
            id: true,
            nombreCompleto: true,
            email: true,
            role: true,
          },
        },
      },
    });

    const userEntries: Array<{
      id: string;
      instanceName: string;
      status: string;
      phoneNumber: string | null;
      webhookEnabled: boolean;
      isCompany: boolean;
      userId: string | null;
      userName: string;
      userRole: string | null;
    }> = userInstances.map((inst) => ({
      id: inst.id,
      instanceName: inst.instanceName,
      status: inst.status,
      phoneNumber: inst.phoneNumber ?? null,
      webhookEnabled: inst.webhookEnabled,
      isCompany: false,
      userId: inst.user?.id ?? null,
      userName: inst.user?.nombreCompleto ?? inst.user?.email ?? 'Sin nombre',
      userRole: (inst.user?.role as string | null) ?? null,
    }));

    // 2. Company instance
    const appConfig = await this.prisma.appConfig.findUnique({
      where: { id: 'global' },
      select: {
        evolutionApiInstanceName: true,
        whatsappWebhookEnabled: true,
      },
    });

    const companyInstanceName = (
      appConfig?.evolutionApiInstanceName ?? ''
    ).trim();

    if (companyInstanceName) {
      const companyStatus =
        await this.getInstanceStateFromEvolution(companyInstanceName);
      userEntries.unshift({
        id: 'company',
        instanceName: companyInstanceName,
        status: companyStatus,
        phoneNumber: null,
        webhookEnabled: appConfig?.whatsappWebhookEnabled ?? false,
        isCompany: true,
        userId: null,
        userName: 'Empresa (instancia principal)',
        userRole: null,
      });
    }

    return userEntries;
  }

  // ─── CRM: set webhook for a specific instance ────────────────────────────

  async setInstanceWebhookForAdmin(instanceName: string, enabled: boolean) {
    const appConfig = await this.prisma.appConfig.findUnique({
      where: { id: 'global' },
      select: { evolutionApiInstanceName: true },
    });

    const companyName = (appConfig?.evolutionApiInstanceName ?? '').trim();
    const isCompany = companyName && instanceName === companyName;

    // Build the URL that will be configured (for response)
    const webhookUrl = this.buildWebhookUrl(instanceName);

    // This now throws if Evolution API fails — DB is only updated on success
    await this.configureInstanceWebhook(instanceName, enabled);

    if (isCompany) {
      await this.prisma.appConfig.update({
        where: { id: 'global' },
        data: { whatsappWebhookEnabled: enabled },
      });
    } else {
      const existing = await this.prisma.userWhatsappInstance.findUnique({
        where: { instanceName },
        select: { id: true },
      });
      if (!existing) {
        throw new NotFoundException(
          `Instancia "${instanceName}" no encontrada.`,
        );
      }
      await this.prisma.userWhatsappInstance.update({
        where: { instanceName },
        data: { webhookEnabled: enabled },
      });
    }

    return { ok: true, instanceName, enabled, webhookUrl };
  }

  // ─── Helper: get instance state from Evolution API ───────────────────────

  private async getInstanceStateFromEvolution(
    instanceName: string,
  ): Promise<string> {
    try {
      const raw = await this.fetchEvolution(
        `/instance/connectionState/${encodeURIComponent(instanceName)}`,
        { method: 'GET' },
      );
      const data = raw as Record<string, unknown>;
      const state = (data?.['instance'] as Record<string, unknown>)?.[
        'state'
      ] as string | undefined;
      if (state === 'open') return 'connected';
      if (state) return state;
      return 'pending';
    } catch {
      return 'pending';
    }
  }

  async getInstanceConnectionState(instanceName: string): Promise<string> {
    const name = (instanceName ?? '').trim();
    if (!name) return 'pending';
    return this.getInstanceStateFromEvolution(name);
  }

  async handleIncomingWebhook(
    instanceName: string,
    payload: unknown,
    eventNameFromRoute?: string,
  ) {
    const record = await this.prisma.userWhatsappInstance.findUnique({
      where: { instanceName },
      select: { userId: true, instanceName: true },
    });

    if (!record) {
      console.warn(
        `[WhatsApp][Webhook] Webhook recibido para instancia no registrada "${instanceName}".`,
      );
      return { ok: true, ignored: true, reason: 'instance_not_registered' };
    }

    const {
      WhatsappInboxService,
    } = require('../whatsapp-inbox/whatsapp-inbox.service');
    const inboxService = this.moduleRef.get(WhatsappInboxService, {
      strict: false,
    });
    if (!inboxService) {
      console.error(
        `[WhatsApp][Webhook] Inbox service unavailable, no se puede procesar webhook para "${instanceName}".`,
      );
      return { ok: true, ignored: true, reason: 'inbox_service_unavailable' };
    }

    console.log(
      `[WhatsApp][Webhook] Delegando webhook a WhatsappInboxService para instancia "${instanceName}" userId=${record.userId} eventName=${eventNameFromRoute ?? '-'}`,
    );

    return inboxService.handleIncomingWebhook(
      instanceName,
      payload,
      eventNameFromRoute,
    );
  }

  private buildInstanceName(userId: string, custom?: string): string {
    const userSuffix = userId.replace(/-/g, '').substring(0, 16);
    const sanitizedCustom = (custom ?? '')
      .trim()
      .replace(/[^a-zA-Z0-9_-]/g, '_')
      .replace(/_+/g, '_')
      .replace(/^_+|_+$/g, '');

    if (sanitizedCustom.length >= 3) {
      const prefix = sanitizedCustom.substring(0, 40);
      return `${prefix}_${userSuffix}`;
    }

    // Auto-generate a unique instance name per user.
    return `user_${userSuffix}`;
  }

  private describeEvolutionError(error: unknown): string {
    if (error instanceof Error) {
      const code = (error as Error & { code?: string }).code;
      return code ? `${error.message} [${code}]` : error.message;
    }
    return String(error);
  }

  private isEvolutionUnavailableError(error: unknown): boolean {
    return error instanceof ServiceUnavailableException;
  }

  private async performEvolutionRequest(
    url: URL,
    init: { method?: string; headers?: Record<string, string>; body?: string },
  ): Promise<{ status: number; contentType: string; bodyText: string }> {
    const client = url.protocol === 'https:' ? https : http;

    return new Promise((resolve, reject) => {
      const req = client.request(
        url,
        {
          method: init.method ?? 'GET',
          headers: init.headers,
          family: 4,
          servername: url.hostname,
          timeout: this.requestTimeoutMs,
        },
        (res) => {
          const chunks: Buffer[] = [];
          res.on('data', (chunk) => chunks.push(Buffer.from(chunk)));
          res.on('end', () => {
            const bodyText = Buffer.concat(chunks).toString('utf8');
            resolve({
              status: res.statusCode ?? 0,
              contentType: Array.isArray(res.headers['content-type'])
                ? res.headers['content-type'].join(',')
                : (res.headers['content-type'] ?? ''),
              bodyText,
            });
          });
        },
      );

      req.on('timeout', () => {
        req.destroy(
          new Error(`Evolution API timeout after ${this.requestTimeoutMs}ms`),
        );
      });
      req.on('error', reject);

      if (init.body) {
        req.write(init.body);
      }
      req.end();
    });
  }

  private async fetchEvolution<T = unknown>(
    path: string,
    options?: RequestInit,
  ): Promise<T> {
    const base = this.evolutionBaseUrl;
    if (!base) {
      throw new BadRequestException(
        'Evolution API no configurada. Falta EVOLUTION_API_URL en variables de entorno.',
      );
    }
    const url = `${base}${path}`;
    try {
      const response = await this.performEvolutionRequest(new URL(url), {
        method: options?.method,
        headers: {
          ...this.buildHeaders(),
          ...((options?.headers as Record<string, string> | undefined) ?? {}),
        },
        body: typeof options?.body === 'string' ? options.body : undefined,
      });

      let body: unknown;
      const contentType = response.contentType;
      if (contentType.includes('application/json')) {
        body = response.bodyText ? JSON.parse(response.bodyText) : null;
      } else {
        body = response.bodyText;
      }

      if (response.status < 200 || response.status >= 300) {
        const bodyPreview =
          typeof body === 'string'
            ? body.trim()
            : (() => {
                try {
                  return JSON.stringify(body ?? null);
                } catch {
                  return String(body ?? '');
                }
              })();
        const requestPayload =
          typeof options?.body === 'string' ? options.body : '';
        console.error(
          `[WhatsApp][Evolution] HTTP ${response.status} url=${url} payload=${requestPayload} response=${bodyPreview}`,
        );
        const msg =
          bodyPreview ||
          ((body as { message?: string })?.message ?? `HTTP ${response.status}`);
        throw new BadRequestException(
          `Evolution API error (HTTP ${response.status}): ${msg}`,
        );
      }

      return body as T;
    } catch (error) {
      if (
        error instanceof BadRequestException ||
        error instanceof NotFoundException ||
        error instanceof ConflictException ||
        error instanceof ServiceUnavailableException
      ) {
        throw error;
      }

      const detail = this.describeEvolutionError(error);
      console.error(`[WhatsApp][Evolution] Request failed ${url}: ${detail}`);
      throw new ServiceUnavailableException(
        `No se pudo conectar con Evolution API. Verifica EVOLUTION_API_URL, DNS, SSL y conectividad saliente del contenedor API. Detalle: ${detail}`,
      );
    }
  }

  // ─── Instance management ────────────────────────────────────────────────

  async createInstance(userId: string, dto: CreateWhatsappInstanceDto) {
    const existing = await this.prisma.userWhatsappInstance.findUnique({
      where: { userId },
    });

    if (existing) {
      throw new ConflictException(
        'Este usuario ya tiene una instancia de WhatsApp registrada.',
      );
    }

    // Guard: instance name must not clash with the company's dedicated instance.
    const appConfig = await this.prisma.appConfig.findUnique({
      where: { id: 'global' },
      select: { evolutionApiInstanceName: true },
    });
    const companyInstanceName = (appConfig?.evolutionApiInstanceName ?? '')
      .trim()
      .toLowerCase();
    const instanceName = this.buildInstanceName(userId, dto.instanceName);
    if (
      companyInstanceName &&
      instanceName.toLowerCase() === companyInstanceName
    ) {
      throw new ConflictException(
        'El nombre de instancia coincide con la instancia de la empresa. Usa un nombre diferente.',
      );
    }
    const webhookEnabled = await this.isGlobalWebhookEnabled();

    // Create instance in Evolution API (if configured)
    if (this.evolutionBaseUrl) {
      try {
        await this.fetchEvolution(`/instance/create`, {
          method: 'POST',
          body: JSON.stringify({
            instanceName,
            qrcode: true,
            integration: 'WHATSAPP-BAILEYS',
            ...(dto.phoneNumber ? { number: dto.phoneNumber } : {}),
          }),
        });
      } catch (err) {
        // If Evolution API is not reachable, still save the record locally
        // so the user can retry QR fetching later
        const msg = err instanceof Error ? err.message : String(err);
        if (!msg.includes('Evolution API no configurada')) {
          // Log but don't block — instance record will be created as pending
          console.error(`[WhatsApp] createInstance Evolution error: ${msg}`);
        }
      }
    }

    const record = await this.prisma.userWhatsappInstance.create({
      data: {
        userId,
        instanceName,
        status: 'pending',
        ...(dto.phoneNumber ? { phoneNumber: dto.phoneNumber } : {}),
      },
    });

    try {
      await this.configureInstanceWebhook(instanceName, webhookEnabled);
    } catch (webhookErr) {
      console.error(
        `[WhatsApp] No se pudo configurar webhook al crear instancia "${instanceName}": ${this.describeEvolutionError(webhookErr)}`,
      );
    }

    return record;
  }

  async getInstanceStatus(userId: string) {
    const record = await this.prisma.userWhatsappInstance.findUnique({
      where: { userId },
    });

    if (!record) {
      return {
        exists: false,
        status: null,
        instanceName: null,
        phoneNumber: null,
      };
    }

    // Try to get live status from Evolution API
    if (this.evolutionBaseUrl && record.instanceName) {
      try {
        const data = await this.fetchEvolution<{
          instance?: { state?: string };
        }>(
          `/instance/connectionState/${encodeURIComponent(record.instanceName)}`,
        );

        const state = data?.instance?.state ?? '';
        const isConnected = state === 'open';
        const newStatus = isConnected ? 'connected' : 'pending';

        if (newStatus !== record.status) {
          await this.prisma.userWhatsappInstance.update({
            where: { userId },
            data: { status: newStatus },
          });
          record.status = newStatus;
        }
      } catch (error) {
        console.warn(
          `[WhatsApp][status] No se pudo consultar estado en Evolution para "${record.instanceName}": ${this.describeEvolutionError(error)}`,
        );
        // Could not reach Evolution API — return stored status
      }
    }

    return {
      exists: true,
      status: record.status,
      instanceName: record.instanceName,
      phoneNumber: record.phoneNumber,
      id: record.id,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    };
  }

  async getQrCode(userId: string) {
    console.log(`[WhatsApp][QR] Solicitando QR para userId=${userId}`);
    const record = await this.prisma.userWhatsappInstance.findUnique({
      where: { userId },
    });

    if (!record) {
      console.warn(
        `[WhatsApp][QR] Sin instancia registrada para userId=${userId}`,
      );
      throw new NotFoundException(
        'No hay instancia de WhatsApp registrada. Crea una instancia primero.',
      );
    }

    if (!this.evolutionBaseUrl) {
      throw new BadRequestException(
        'Evolution API no configurada en el servidor.',
      );
    }

    // If already connected, no need to call /connect (it would return 400)
    if (record.status === 'connected') {
      console.log(
        `[WhatsApp][QR] Instancia "${record.instanceName}" ya conectada. No se solicita QR.`,
      );
      return {
        instanceName: record.instanceName,
        qrBase64: '',
        status: 'connected',
      };
    }

    console.log(
      `[WhatsApp][QR] Intentando conectar instancia "${record.instanceName}" (status=${record.status})...`,
    );

    type QrPayload = {
      base64?: string;
      code?: string;
      qrcode?: { base64?: string; code?: string };
    };

    const extractBase64 = (qrData: QrPayload) =>
      qrData?.base64 ?? qrData?.qrcode?.base64 ?? '';

    const tryConnect = () =>
      this.fetchEvolution<QrPayload>(
        `/instance/connect/${encodeURIComponent(record.instanceName)}`,
      );

    // First attempt
    try {
      const qrData = await tryConnect();
      console.log(
        `[WhatsApp][QR] QR obtenido para "${record.instanceName}" en primer intento.`,
      );
      return {
        instanceName: record.instanceName,
        qrBase64: extractBase64(qrData),
        status: record.status,
      };
    } catch (firstErr) {
      if (this.isEvolutionUnavailableError(firstErr)) {
        console.error(
          `[WhatsApp][QR] Evolution no disponible al conectar "${record.instanceName}": ${this.describeEvolutionError(firstErr)}`,
        );
        throw firstErr;
      }

      // Instance likely doesn't exist in Evolution API (e.g. was never created
      // due to a prior network error). Try to recreate it, then retry.
      console.warn(
        `[WhatsApp] getQrCode first attempt failed for "${record.instanceName}", attempting recreation: ${firstErr instanceof Error ? firstErr.message : firstErr}`,
      );
      try {
        await this.fetchEvolution(`/instance/create`, {
          method: 'POST',
          body: JSON.stringify({
            instanceName: record.instanceName,
            qrcode: true,
            integration: 'WHATSAPP-BAILEYS',
            ...(record.phoneNumber ? { number: record.phoneNumber } : {}),
          }),
        });
        try {
          await this.configureInstanceWebhook(
            record.instanceName,
            await this.isGlobalWebhookEnabled(),
          );
        } catch (_webhookErr) {
          /* non-blocking in QR retry flow */
        }
      } catch (createErr) {
        if (this.isEvolutionUnavailableError(createErr)) {
          console.error(
            `[WhatsApp][QR] Evolution no disponible al recrear "${record.instanceName}": ${this.describeEvolutionError(createErr)}`,
          );
          throw createErr;
        }

        // If 409 (already exists), that's fine — continue to retry connect
        const msg =
          createErr instanceof Error ? createErr.message : String(createErr);
        if (!msg.includes('409') && !msg.toLowerCase().includes('already')) {
          console.error(
            `[WhatsApp][QR] Recreación de instancia fallida para "${record.instanceName}": ${msg}`,
          );
          throw new BadRequestException(
            `No se pudo obtener el QR. Intenta eliminar y volver a crear la instancia.`,
          );
        }
        console.warn(
          `[WhatsApp][QR] Recreación: instancia "${record.instanceName}" ya existía (409), reintentando connect.`,
        );
      }

      // Retry connect after recreation
      try {
        const qrData = await tryConnect();
        console.log(
          `[WhatsApp][QR] QR obtenido para "${record.instanceName}" luego de recreación.`,
        );
        return {
          instanceName: record.instanceName,
          qrBase64: extractBase64(qrData),
          status: record.status,
        };
      } catch (retryErr) {
        if (this.isEvolutionUnavailableError(retryErr)) {
          console.error(
            `[WhatsApp][QR] Evolution no disponible en reintento para "${record.instanceName}": ${this.describeEvolutionError(retryErr)}`,
          );
          throw retryErr;
        }

        const msg =
          retryErr instanceof Error ? retryErr.message : String(retryErr);
        console.error(
          `[WhatsApp][QR] Fallo definitivo al obtener QR para "${record.instanceName}": ${msg}`,
        );
        throw new BadRequestException(`No se pudo obtener el QR: ${msg}`);
      }
    }
  }

  async deleteInstance(userId: string) {
    const record = await this.prisma.userWhatsappInstance.findUnique({
      where: { userId },
    });

    if (!record) {
      throw new NotFoundException(
        'No hay instancia de WhatsApp para eliminar.',
      );
    }

    // Delete from Evolution API
    if (this.evolutionBaseUrl) {
      try {
        await this.fetchEvolution(
          `/instance/delete/${encodeURIComponent(record.instanceName)}`,
          { method: 'DELETE' },
        );
      } catch (err) {
        console.error(
          `[WhatsApp] deleteInstance Evolution error: ${err instanceof Error ? err.message : err}`,
        );
      }
    }

    await this.prisma.userWhatsappInstance.delete({ where: { userId } });
    return { deleted: true };
  }

  // ─── Admin ──────────────────────────────────────────────────────────────

  async listUsersWithWhatsappStatus() {
    const users = await this.prisma.user.findMany({
      select: {
        id: true,
        nombreCompleto: true,
        email: true,
        role: true,
        whatsappInstance: {
          select: {
            id: true,
            instanceName: true,
            status: true,
            phoneNumber: true,
            createdAt: true,
            updatedAt: true,
          },
        },
      },
      orderBy: { nombreCompleto: 'asc' },
    });

    return users.map((u) => ({
      id: u.id,
      nombreCompleto: u.nombreCompleto,
      email: u.email,
      role: u.role,
      whatsapp: u.whatsappInstance
        ? {
            id: u.whatsappInstance.id,
            instanceName: u.whatsappInstance.instanceName,
            status: u.whatsappInstance.status,
            phoneNumber: u.whatsappInstance.phoneNumber,
            createdAt: u.whatsappInstance.createdAt,
            updatedAt: u.whatsappInstance.updatedAt,
          }
        : null,
    }));
  }

  // ─── Company instance (stored in AppConfig) ─────────────────────────────

  private async getCompanyInstanceName(): Promise<string> {
    const row = await this.prisma.appConfig.findUnique({
      where: { id: 'global' },
      select: { evolutionApiInstanceName: true },
    });
    return (row?.evolutionApiInstanceName ?? '').trim();
  }

  private async setCompanyInstanceName(name: string): Promise<void> {
    await this.prisma.appConfig.upsert({
      where: { id: 'global' },
      create: { id: 'global', evolutionApiInstanceName: name },
      update: { evolutionApiInstanceName: name },
    });
  }

  async createCompanyInstance(dto: CreateWhatsappInstanceDto) {
    const existing = await this.getCompanyInstanceName();
    if (existing) {
      throw new ConflictException(
        'Ya existe una instancia de la empresa. Elimínala primero para crear una nueva.',
      );
    }

    const sanitized = (dto.instanceName ?? '')
      .trim()
      .replace(/[^a-zA-Z0-9_-]/g, '_')
      .replace(/_+/g, '_')
      .replace(/^_+|_+$/g, '');

    const instanceName = sanitized.length >= 3 ? sanitized : 'empresa';

    if (this.evolutionBaseUrl) {
      try {
        await this.fetchEvolution(`/instance/create`, {
          method: 'POST',
          body: JSON.stringify({
            instanceName,
            qrcode: true,
            integration: 'WHATSAPP-BAILEYS',
            ...(dto.phoneNumber ? { number: dto.phoneNumber } : {}),
          }),
        });
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        if (!msg.includes('409') && !msg.toLowerCase().includes('already')) {
          console.error(
            `[WhatsApp][Company] createCompanyInstance Evolution error: ${msg}`,
          );
        }
      }
    }

    await this.setCompanyInstanceName(instanceName);

    const webhookEnabled = await this.isGlobalWebhookEnabled();
    try {
      await this.configureInstanceWebhook(instanceName, webhookEnabled);
    } catch (webhookErr) {
      console.error(
        `[WhatsApp] No se pudo configurar webhook al crear instancia empresa "${instanceName}": ${this.describeEvolutionError(webhookErr)}`,
      );
    }

    return { instanceName, status: 'pending' };
  }

  async getCompanyInstanceStatus() {
    const instanceName = await this.getCompanyInstanceName();
    if (!instanceName) {
      return { exists: false, instanceName: null, status: null };
    }

    if (this.evolutionBaseUrl) {
      try {
        const data = await this.fetchEvolution<{
          instance?: { state?: string };
        }>(`/instance/connectionState/${encodeURIComponent(instanceName)}`);
        const state = data?.instance?.state ?? '';
        const isConnected = state === 'open';
        return {
          exists: true,
          instanceName,
          status: isConnected ? 'connected' : 'pending',
        };
      } catch {
        // fall through to return stored
      }
    }

    return { exists: true, instanceName, status: 'pending' };
  }

  async getCompanyInstanceQr() {
    const instanceName = await this.getCompanyInstanceName();
    if (!instanceName) {
      throw new NotFoundException(
        'No hay instancia de la empresa registrada. Crea una instancia primero.',
      );
    }

    if (!this.evolutionBaseUrl) {
      throw new BadRequestException(
        'Evolution API no configurada en el servidor.',
      );
    }

    type QrPayload = {
      base64?: string;
      code?: string;
      qrcode?: { base64?: string; code?: string };
    };
    const extractBase64 = (qrData: QrPayload) =>
      qrData?.base64 ?? qrData?.qrcode?.base64 ?? '';

    const tryConnect = () =>
      this.fetchEvolution<QrPayload>(
        `/instance/connect/${encodeURIComponent(instanceName)}`,
      );

    try {
      const qrData = await tryConnect();
      return {
        instanceName,
        qrBase64: extractBase64(qrData),
        status: 'pending',
      };
    } catch (firstErr) {
      if (this.isEvolutionUnavailableError(firstErr)) throw firstErr;

      // Try to recreate in Evolution API
      try {
        await this.fetchEvolution(`/instance/create`, {
          method: 'POST',
          body: JSON.stringify({
            instanceName,
            qrcode: true,
            integration: 'WHATSAPP-BAILEYS',
          }),
        });
        try {
          await this.configureInstanceWebhook(
            instanceName,
            await this.isGlobalWebhookEnabled(),
          );
        } catch (_webhookErr) {
          /* non-blocking in QR retry flow */
        }
      } catch (createErr) {
        const msg =
          createErr instanceof Error ? createErr.message : String(createErr);
        if (!msg.includes('409') && !msg.toLowerCase().includes('already')) {
          throw new BadRequestException(`No se pudo obtener el QR: ${msg}`);
        }
      }

      const qrData = await tryConnect();
      return {
        instanceName,
        qrBase64: extractBase64(qrData),
        status: 'pending',
      };
    }
  }

  async deleteCompanyInstance() {
    const instanceName = await this.getCompanyInstanceName();
    if (!instanceName) {
      throw new NotFoundException(
        'No hay instancia de la empresa para eliminar.',
      );
    }

    if (this.evolutionBaseUrl) {
      try {
        await this.fetchEvolution(
          `/instance/delete/${encodeURIComponent(instanceName)}`,
          { method: 'DELETE' },
        );
      } catch (err) {
        console.error(
          `[WhatsApp][Company] deleteCompanyInstance Evolution error: ${err instanceof Error ? err.message : err}`,
        );
      }
    }

    await this.setCompanyInstanceName('');
    return { deleted: true };
  }

  // ─── Send text message via Evolution API ────────────────────────────────

  async sendTextMessage(
    instanceName: string,
    remoteJid: string,
    text: string,
  ): Promise<unknown> {
    const payload = {
      number: remoteJid,
      text,
    };
    console.log(
      `[WhatsApp][Evolution][sendText] endpoint=/message/sendText/${encodeURIComponent(instanceName)} instanceName=${instanceName} payload=${JSON.stringify(payload)}`,
    );
    return this.fetchEvolution(
      `/message/sendText/${encodeURIComponent(instanceName)}`,
      {
        method: 'POST',
        body: JSON.stringify(payload),
      },
    );
  }

  async sendMediaMessage(params: {
    instanceName: string;
    remoteJid: string;
    bytes: Buffer | Uint8Array;
    mediaType: 'image' | 'video' | 'audio' | 'document';
    mimeType: string;
    fileName: string;
    caption?: string | null;
  }): Promise<unknown> {
    const mediaBase64 = Buffer.from(params.bytes).toString('base64');
    return this.fetchEvolution(
      `/message/sendMedia/${encodeURIComponent(params.instanceName)}`,
      {
        method: 'POST',
        body: JSON.stringify({
          number: params.remoteJid,
          mediatype: params.mediaType,
          mimetype: params.mimeType,
          media: mediaBase64,
          fileName: params.fileName,
          ...(params.caption?.trim() ? { caption: params.caption.trim() } : {}),
        }),
      },
    );
  }

  async deleteMessage(params: {
    instanceName: string;
    remoteJid: string;
    messageId: string;
    fromMe?: boolean;
  }): Promise<unknown> {
    const payload = {
      id: params.messageId,
      remoteJid: params.remoteJid,
      fromMe: params.fromMe ?? true,
    };
    return this.fetchEvolution(
      `/message/delete/${encodeURIComponent(params.instanceName)}`,
      {
        method: 'DELETE',
        body: JSON.stringify(payload),
      },
    );
  }

  async findChatMessages(
    instanceName: string,
    remoteJid: string,
  ): Promise<unknown> {
    return this.fetchEvolution(
      `/chat/findMessages/${encodeURIComponent(instanceName)}`,
      {
        method: 'POST',
        body: JSON.stringify({
          where: {
            key: { remoteJid },
          },
          take: 80,
          limit: 80,
          orderBy: {
            messageTimestamp: 'desc',
          },
        }),
      },
    );
  }

  async getBase64FromMediaMessage(
    instanceName: string,
    message: unknown,
  ): Promise<unknown> {
    return this.fetchEvolution(
      `/chat/getBase64FromMediaMessage/${encodeURIComponent(instanceName)}`,
      {
        method: 'POST',
        body: JSON.stringify({ message }),
      },
    );
  }

  async findChats(instanceName: string, limit = 30): Promise<unknown> {
    return this.fetchEvolution(
      `/chat/findChats/${encodeURIComponent(instanceName)}`,
      {
        method: 'POST',
        body: JSON.stringify({
          take: limit,
          limit,
          orderBy: {
            updatedAt: 'desc',
          },
        }),
      },
    );
  }
}
