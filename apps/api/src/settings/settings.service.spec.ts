import { BadRequestException, ForbiddenException } from '@nestjs/common';
import { Role } from '@prisma/client';
import { SettingsService } from './settings.service';

describe('SettingsService company master data protection', () => {
  const fiscal = {
    taxEnabled: false,
    defaultTaxId: null,
    defaultTaxRate: 0,
    pricesIncludeTax: false,
    ncfEnabled: false,
  };

  function buildService(prisma: any) {
    return new SettingsService(
      prisma,
      {} as any,
      { emitCompany: jest.fn() } as any,
      { getCompanyFiscalSettings: jest.fn().mockResolvedValue(fiscal), updateFiscalSettings: jest.fn() } as any,
    );
  }

  it('serves companies.name as the canonical companyName when appConfig is stale', async () => {
    const prisma = {
      company: {
        findUnique: jest.fn().mockResolvedValue({ name: 'Nombre Nuevo' }),
      },
      appConfig: {
        upsert: jest.fn().mockResolvedValue({
          companyName: 'Nombre Viejo',
          rnc: '',
          phone: '',
          phonePreferential: '',
          address: '',
          description: '',
          instagramUrl: '',
          facebookUrl: '',
          websiteUrl: '',
          gpsLocationUrl: '',
          businessHours: '',
          bankAccounts: [],
          legalRepresentativeName: '',
          legalRepresentativeCedula: '',
          legalRepresentativeRole: '',
          legalRepresentativeNationality: '',
          legalRepresentativeCivilStatus: '',
          logoBase64: null,
          openAiApiKey: null,
          openAiModel: 'gpt-4o-mini',
          evolutionApiBaseUrl: '',
          evolutionApiInstanceName: '',
          evolutionApiApiKey: null,
          whatsappWebhookEnabled: false,
          adminAuthorizationPinHash: null,
        }),
      },
    };
    const service = buildService(prisma);

    const settings = await service.getSettings({
      id: 'user-a',
      role: Role.CAJERO,
      companyId: 'company-a',
    });

    expect(settings.companyName).toBe('Nombre Nuevo');
    expect(prisma.company.findUnique).toHaveBeenCalledWith({
      where: { id: 'company-a' },
      select: { name: true },
    });
  });

  it('rejects stale company writes from non-admin users before touching prisma', async () => {
    const prisma = {
      $transaction: jest.fn(),
    };
    const service = buildService(prisma);

    await expect(
      service.updateSettings(
        { id: 'employee-a', role: Role.CAJERO, companyId: 'company-a' },
        { companyName: 'Nombre Viejo' },
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('rejects empty company names instead of creating an appConfig/company mismatch', async () => {
    const prisma = {
      $transaction: jest.fn(),
    };
    const service = buildService(prisma);

    await expect(
      service.updateSettings(
        { id: 'admin-a', role: Role.ADMIN, companyId: 'company-a' },
        { companyName: '   ' },
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('updates only the authenticated tenant company and writes an audit record', async () => {
    const tx = {
      company: {
        findUnique: jest.fn().mockResolvedValue({ name: 'Nombre Viejo' }),
        update: jest.fn().mockResolvedValue({}),
      },
      appConfig: {
        upsert: jest.fn().mockResolvedValue({
          companyName: 'Nombre Nuevo',
          rnc: '',
          phone: '',
          phonePreferential: '',
          address: '',
          description: '',
          instagramUrl: '',
          facebookUrl: '',
          websiteUrl: '',
          gpsLocationUrl: '',
          businessHours: '',
          bankAccounts: [],
          legalRepresentativeName: '',
          legalRepresentativeCedula: '',
          legalRepresentativeRole: '',
          legalRepresentativeNationality: '',
          legalRepresentativeCivilStatus: '',
          logoBase64: null,
          openAiApiKey: null,
          openAiModel: 'gpt-4o-mini',
          evolutionApiBaseUrl: '',
          evolutionApiInstanceName: '',
          evolutionApiApiKey: null,
          whatsappWebhookEnabled: false,
          adminAuthorizationPinHash: null,
        }),
      },
      companyLicenseAuditLog: {
        create: jest.fn().mockResolvedValue({}),
      },
    };
    const prisma = {
      $transaction: jest.fn((callback) => callback(tx)),
    };
    const service = buildService(prisma);

    await service.updateSettings(
      { id: 'admin-a', role: Role.ADMIN, companyId: 'company-a' },
      { companyName: 'Nombre Nuevo' },
    );

    expect(tx.company.update).toHaveBeenCalledWith({
      where: { id: 'company-a' },
      data: { name: 'Nombre Nuevo' },
    });
    expect(tx.company.update).not.toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 'company-b' } }),
    );
    expect(tx.companyLicenseAuditLog.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          companyId: 'company-a',
          actorId: 'admin-a',
          action: 'settings.company_name_update',
          before: { companyName: 'Nombre Viejo' },
          after: { companyName: 'Nombre Nuevo' },
        }),
      }),
    );
  });
});
