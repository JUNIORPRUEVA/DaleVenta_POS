import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Prisma, Role } from '@prisma/client';
import { randomUUID } from 'node:crypto';
import * as bcrypt from 'bcryptjs';
import { requireTenant, type TenantUser } from '../auth/tenant-context';
import { PrismaService } from '../prisma/prisma.service';
import { CatalogRealtimeRelayService } from '../products/catalog-realtime-relay.service';

type SettingsPayload = Record<string, unknown>;

@Injectable()
export class SettingsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly realtime: CatalogRealtimeRelayService,
  ) {}

  async getSettings(user: TenantUser) {
    const companyId = requireTenant(user);
    const config = await this.ensureConfig(companyId);
    return this.toPublicSettings(config);
  }

  async updateSettings(user: TenantUser, dto: SettingsPayload) {
    this.requireAdmin(user);
    const companyId = requireTenant(user);
    const data = this.settingsData(dto);
    let changedCompanyName: string | null = null;
    const config = await this.prisma.$transaction(async (tx) => {
      const updated = await tx.appConfig.upsert({
        where: { companyId },
        create: {
          id: `company_${companyId}`,
          companyId,
          ...data,
        },
        update: data,
      });
      const companyName = data.companyName?.trim();
      if (companyName) {
        await tx.company.update({
          where: { id: companyId },
          data: { name: companyName },
        });
        changedCompanyName = companyName;
      }
      return updated;
    });
    if (changedCompanyName) {
      this.emitCompanyNameUpdated(companyId, changedCompanyName);
    }
    return this.toPublicSettings(config);
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

  async verifyAdminPin(user: TenantUser, pin: unknown) {
    const companyId = requireTenant(user);
    const normalizedPin = this.normalizePin(pin);
    const config = await this.prisma.appConfig.findUnique({
      where: { companyId },
      select: { adminAuthorizationPinHash: true },
    });
    const hash = config?.adminAuthorizationPinHash ?? '';
    if (!hash) {
      throw new NotFoundException(
        'La empresa no tiene PIN administrativo configurado',
      );
    }
    const ok = await bcrypt.compare(normalizedPin, hash);
    if (!ok) {
      throw new ForbiddenException('PIN administrativo inválido');
    }
    const expiresInSeconds = 600;
    const adminAuthorizationToken = await this.jwt.signAsync(
      {
        sub: user.id,
        companyId,
        tokenType: 'admin-authorization',
      },
      { expiresIn: expiresInSeconds },
    );
    return {
      ok: true,
      expiresInSeconds,
      adminAuthorizationToken,
    };
  }

  private requireAdmin(user: TenantUser) {
    if (user.role !== Role.ADMIN) {
      throw new ForbiddenException(
        'Solo un administrador puede cambiar esta configuración',
      );
    }
  }

  private normalizePin(pin: unknown) {
    const value = `${pin ?? ''}`.trim();
    if (!/^\d{4}$/.test(value)) {
      throw new BadRequestException(
        'El PIN administrativo debe tener 4 dígitos',
      );
    }
    return value;
  }

  private emitCompanyNameUpdated(companyId: string, companyName: string) {
    this.realtime.emitCompany(companyId, 'license.event', {
      eventId: `settings_${Date.now()}_${randomUUID().slice(0, 8)}`,
      type: 'license.company_name_updated',
      companyId,
      companyName,
      account: {
        businessName: companyName,
      },
      at: new Date().toISOString(),
    });
  }

  private async ensureConfig(companyId: string) {
    return this.prisma.appConfig.upsert({
      where: { companyId },
      create: {
        id: `company_${companyId}`,
        companyId,
      },
      update: {},
    });
  }

  private stringValue(dto: SettingsPayload, key: string) {
    const value = dto[key];
    return typeof value === 'string' ? value.trim() : undefined;
  }

  private boolValue(dto: SettingsPayload, key: string) {
    const value = dto[key];
    return typeof value === 'boolean' ? value : undefined;
  }

  private settingsData(
    dto: SettingsPayload,
  ): Prisma.AppConfigUncheckedCreateInput &
    Prisma.AppConfigUncheckedUpdateInput {
    const bankAccounts = Array.isArray(dto.bankAccounts)
      ? (dto.bankAccounts as Prisma.InputJsonValue)
      : undefined;
    return {
      companyName: this.stringValue(dto, 'companyName'),
      rnc: this.stringValue(dto, 'rnc'),
      phone: this.stringValue(dto, 'phone'),
      phonePreferential: this.stringValue(dto, 'phonePreferential'),
      address: this.stringValue(dto, 'address'),
      description: this.stringValue(dto, 'description'),
      instagramUrl: this.stringValue(dto, 'instagramUrl'),
      facebookUrl: this.stringValue(dto, 'facebookUrl'),
      websiteUrl: this.stringValue(dto, 'websiteUrl'),
      gpsLocationUrl: this.stringValue(dto, 'gpsLocationUrl'),
      businessHours: this.stringValue(dto, 'businessHours'),
      bankAccounts,
      legalRepresentativeName: this.stringValue(dto, 'legalRepresentativeName'),
      legalRepresentativeCedula: this.stringValue(
        dto,
        'legalRepresentativeCedula',
      ),
      legalRepresentativeRole: this.stringValue(dto, 'legalRepresentativeRole'),
      legalRepresentativeNationality: this.stringValue(
        dto,
        'legalRepresentativeNationality',
      ),
      legalRepresentativeCivilStatus: this.stringValue(
        dto,
        'legalRepresentativeCivilStatus',
      ),
      logoBase64: this.stringValue(dto, 'logoBase64'),
      openAiApiKey: this.stringValue(dto, 'openAiApiKey'),
      evolutionApiBaseUrl: this.stringValue(dto, 'evolutionApiBaseUrl'),
      evolutionApiInstanceName: this.stringValue(
        dto,
        'evolutionApiInstanceName',
      ),
      evolutionApiApiKey: this.stringValue(dto, 'evolutionApiApiKey'),
      whatsappWebhookEnabled: this.boolValue(dto, 'whatsappWebhookEnabled'),
    };
  }

  private toPublicSettings(config: {
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
    adminAuthorizationPinHash: string | null;
  }) {
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
      openAiApiKey: '',
      openAiModel: config.openAiModel,
      hasOpenAiApiKey: Boolean(config.openAiApiKey),
      evolutionApiBaseUrl: config.evolutionApiBaseUrl,
      evolutionApiInstanceName: config.evolutionApiInstanceName,
      evolutionApiApiKey: '',
      hasEvolutionApiApiKey: Boolean(config.evolutionApiApiKey),
      whatsappWebhookEnabled: config.whatsappWebhookEnabled,
      hasAdminAuthorizationPin: Boolean(config.adminAuthorizationPinHash),
      productsSource: 'LOCAL',
      productsReadOnly: false,
    };
  }
}
