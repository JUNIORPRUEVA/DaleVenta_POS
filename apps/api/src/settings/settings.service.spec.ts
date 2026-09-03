import { BadRequestException, ForbiddenException } from "@nestjs/common";
import { Role } from "@prisma/client";
import * as bcrypt from "bcryptjs";
import { SettingsService } from "./settings.service";

describe("SettingsService company master data protection", () => {
  const fiscal = {
    taxEnabled: false,
    defaultTaxId: null,
    defaultTaxRate: 0,
    pricesIncludeTax: false,
    ncfEnabled: false,
  };

  function baseConfig() {
    return {
      companyName: "FullPOS Cloud",
      rnc: "",
      phone: "",
      phonePreferential: "",
      address: "",
      description: "",
      instagramUrl: "",
      facebookUrl: "",
      websiteUrl: "",
      gpsLocationUrl: "",
      businessHours: "",
      bankAccounts: [],
      legalRepresentativeName: "",
      legalRepresentativeCedula: "",
      legalRepresentativeRole: "",
      legalRepresentativeNationality: "",
      legalRepresentativeCivilStatus: "",
      logoBase64: null,
      openAiApiKey: null,
      openAiModel: "gpt-4o-mini",
      evolutionApiBaseUrl: "",
      evolutionApiInstanceName: "",
      evolutionApiApiKey: null,
      whatsappWebhookEnabled: false,
      adminAuthorizationPinHash: null,
    };
  }

  function buildService(prisma: any) {
    const productSourceResolver = {
      resolveForCompany: jest.fn(async (companyId: string) => ({
        companyId,
        source: "LOCAL",
        readOnly: false,
        fullposCompanyId: null,
        supportsDecimalStock: true,
        supportsNativeUom: true,
        supportsProductCreate: true,
        supportsProductEdit: true,
        supportsStockAdjustment: true,
        resolution: "safe-default",
      })),
    };
    return new SettingsService(
      prisma,
      {} as any,
      { emitCompany: jest.fn() } as any,
      productSourceResolver as any,
      {
        getCompanyFiscalSettings: jest.fn().mockResolvedValue(fiscal),
        updateFiscalSettings: jest.fn(),
      } as any,
    );
  }

  function buildDisableGuardTx(
    productFindFirstResult: unknown,
    appConfigExtra: Record<string, unknown> = {},
  ) {
    const tx = {
      company: {
        findUnique: jest.fn().mockResolvedValue({
          name: "FullPOS Cloud",
          measurementUnitsEnabled: true,
          multiWarehouseEnabled: false,
        }),
        update: jest.fn().mockResolvedValue({ id: "company-a" }),
      },
      product: {
        findFirst: jest.fn().mockResolvedValue(productFindFirstResult),
      },
      appConfig: {
        upsert: jest
          .fn()
          .mockResolvedValue({ ...baseConfig(), ...appConfigExtra }),
      },
    };
    const prisma = {
      $transaction: jest.fn((callback) => callback(tx)),
    };
    return { tx, prisma };
  }

  it("serves companies.name as the canonical companyName when appConfig is stale", async () => {
    const prisma = {
      company: {
        findUnique: jest.fn().mockResolvedValue({
          name: "Nombre Nuevo",
          measurementUnitsEnabled: false,
          multiWarehouseEnabled: false,
        }),
      },
      appConfig: {
        upsert: jest.fn().mockResolvedValue({
          companyName: "Nombre Viejo",
          rnc: "",
          phone: "",
          phonePreferential: "",
          address: "",
          description: "",
          instagramUrl: "",
          facebookUrl: "",
          websiteUrl: "",
          gpsLocationUrl: "",
          businessHours: "",
          bankAccounts: [],
          legalRepresentativeName: "",
          legalRepresentativeCedula: "",
          legalRepresentativeRole: "",
          legalRepresentativeNationality: "",
          legalRepresentativeCivilStatus: "",
          logoBase64: null,
          openAiApiKey: null,
          openAiModel: "gpt-4o-mini",
          evolutionApiBaseUrl: "",
          evolutionApiInstanceName: "",
          evolutionApiApiKey: null,
          whatsappWebhookEnabled: false,
          adminAuthorizationPinHash: null,
        }),
        update: jest.fn().mockResolvedValue({ id: "company_company-a" }),
      },
    };
    const service = buildService(prisma);

    const settings = await service.getSettings({
      id: "user-a",
      role: Role.CAJERO,
      companyId: "company-a",
    });

    expect(settings.companyName).toBe("Nombre Nuevo");
    expect(prisma.company.findUnique).toHaveBeenCalledWith({
      where: { id: "company-a" },
      select: {
        name: true,
        measurementUnitsEnabled: true,
        multiWarehouseEnabled: true,
      },
    });
    expect(prisma.appConfig.update).toHaveBeenCalledWith({
      where: { companyId: "company-a" },
      data: { companyName: "Nombre Nuevo" },
      select: { id: true },
    });
  });

  it("rejects stale company writes from non-admin users before touching prisma", async () => {
    const prisma = {
      $transaction: jest.fn(),
    };
    const service = buildService(prisma);

    await expect(
      service.updateSettings(
        { id: "employee-a", role: Role.CAJERO, companyId: "company-a" },
        { companyName: "Nombre Viejo" },
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it("rejects empty company names on the dedicated rename endpoint", async () => {
    const prisma = {
      $transaction: jest.fn(),
    };
    const service = buildService(prisma);

    await expect(
      service.updateCompanyName(
        { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
        { companyName: "   " },
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it("rejects renames from non-admin users before touching prisma", async () => {
    const prisma = {
      $transaction: jest.fn(),
    };
    const service = buildService(prisma);

    await expect(
      service.updateCompanyName(
        { id: "cashier-a", role: Role.CAJERO, companyId: "company-a" },
        { companyName: "Nombre Nuevo" },
      ),
    ).rejects.toBeInstanceOf(ForbiddenException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it("renames only through the explicit endpoint, tenant-scoped and audited", async () => {
    const tx = {
      company: {
        findUnique: jest.fn().mockResolvedValue({ name: "Nombre Viejo" }),
        update: jest.fn().mockResolvedValue({ id: "company-a" }),
      },
      appConfig: {
        upsert: jest.fn().mockResolvedValue({
          companyName: "Nombre Nuevo",
          rnc: "",
          phone: "",
          phonePreferential: "",
          address: "",
          description: "",
          instagramUrl: "",
          facebookUrl: "",
          websiteUrl: "",
          gpsLocationUrl: "",
          businessHours: "",
          bankAccounts: [],
          legalRepresentativeName: "",
          legalRepresentativeCedula: "",
          legalRepresentativeRole: "",
          legalRepresentativeNationality: "",
          legalRepresentativeCivilStatus: "",
          logoBase64: null,
          openAiApiKey: null,
          openAiModel: "gpt-4o-mini",
          evolutionApiBaseUrl: "",
          evolutionApiInstanceName: "",
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

    await service.updateCompanyName(
      { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
      { companyName: "Nombre Nuevo" },
    );

    expect(tx.company.update).toHaveBeenCalledWith({
      where: { id: "company-a" },
      data: { name: "Nombre Nuevo" },
      select: { id: true },
    });
    expect(tx.company.update).not.toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: "company-b" } }),
    );
    expect(tx.appConfig.upsert).toHaveBeenCalledWith(
      expect.objectContaining({ update: { companyName: "Nombre Nuevo" } }),
    );
    expect(tx.companyLicenseAuditLog.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          companyId: "company-a",
          actorId: "admin-a",
          action: "settings.company_name_update",
          before: { companyName: "Nombre Viejo" },
          after: { companyName: "Nombre Nuevo" },
        }),
      }),
    );
  });

  it("persists fiscal false values without touching Company.name", async () => {
    let fiscalState = {
      taxEnabled: true,
      defaultTaxId: "tax-18",
      defaultTaxRate: 0.18,
      pricesIncludeTax: true,
      ncfEnabled: true,
    };
    const taxes = {
      getCompanyFiscalSettings: jest.fn(async () => fiscalState),
      updateFiscalSettings: jest.fn(async (_user, dto) => {
        fiscalState = { ...fiscalState, ...dto };
        return fiscalState;
      }),
    };
    const tx = {
      company: {
        findUnique: jest.fn().mockResolvedValue({
          name: "FullPOS Cloud",
          measurementUnitsEnabled: false,
          multiWarehouseEnabled: false,
        }),
        update: jest.fn().mockResolvedValue({}),
      },
      appConfig: {
        upsert: jest.fn().mockResolvedValue({
          companyName: "FullPOS Cloud",
          rnc: "",
          phone: "",
          phonePreferential: "",
          address: "",
          description: "",
          instagramUrl: "",
          facebookUrl: "",
          websiteUrl: "",
          gpsLocationUrl: "",
          businessHours: "",
          bankAccounts: [],
          legalRepresentativeName: "",
          legalRepresentativeCedula: "",
          legalRepresentativeRole: "",
          legalRepresentativeNationality: "",
          legalRepresentativeCivilStatus: "",
          logoBase64: null,
          openAiApiKey: null,
          openAiModel: "gpt-4o-mini",
          evolutionApiBaseUrl: "",
          evolutionApiInstanceName: "",
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
    const service = new SettingsService(
      prisma as any,
      {} as any,
      { emitCompany: jest.fn() } as any,
      {
        resolveForCompany: jest.fn(async (companyId: string) => ({
          companyId,
          source: "LOCAL",
          readOnly: false,
          fullposCompanyId: null,
          supportsDecimalStock: true,
          supportsNativeUom: true,
          supportsProductCreate: true,
          supportsProductEdit: true,
          supportsStockAdjustment: true,
          resolution: "safe-default",
        })),
      } as any,
      taxes as any,
    );

    const response = await service.updateSettings(
      { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
      {
        // Payload legado: contiene companyName, pero el PATCH genérico NO debe
        // modificar Company.name (ni propagarlo a AppConfig).
        companyName: "DaleVenta POS",
        taxEnabled: false,
        pricesIncludeTax: false,
        ncfEnabled: false,
        defaultTaxRate: 0.18,
      },
    );

    expect(tx.company.update).not.toHaveBeenCalled();
    const upsertCall = tx.appConfig.upsert.mock.calls[0][0];
    expect(upsertCall.update).not.toHaveProperty("companyName");
    expect(taxes.updateFiscalSettings).toHaveBeenCalledWith(
      expect.objectContaining({ companyId: "company-a" }),
      {
        taxEnabled: false,
        defaultTaxId: undefined,
        defaultTaxRate: 0.18,
        pricesIncludeTax: false,
        ncfEnabled: false,
      },
    );
    expect(response.taxEnabled).toBe(false);
    expect(response.pricesIncludeTax).toBe(false);
    expect(response.ncfEnabled).toBe(false);
  });

  it("forwards defaultTaxId from generic settings sync to fiscal settings", async () => {
    let fiscalState = {
      taxEnabled: true,
      defaultTaxId: "tax-old",
      defaultTaxRate: 0.12,
      pricesIncludeTax: false,
      ncfEnabled: false,
    };
    const taxes = {
      getCompanyFiscalSettings: jest.fn(async () => fiscalState),
      updateFiscalSettings: jest.fn(async (_user, dto) => {
        fiscalState = { ...fiscalState, ...dto };
        return fiscalState;
      }),
    };
    const tx = {
      company: {
        findUnique: jest.fn().mockResolvedValue({
          name: "FullPOS Cloud",
          measurementUnitsEnabled: false,
          multiWarehouseEnabled: true,
        }),
      },
      appConfig: {
        upsert: jest.fn().mockResolvedValue(baseConfig()),
      },
    };
    const prisma = {
      $transaction: jest.fn(async (callback) => callback(tx)),
    };
    const service = new SettingsService(
      prisma as any,
      { signAsync: jest.fn() } as any,
      { emitCompany: jest.fn() } as any,
      {
        resolveForCompany: jest.fn(async () => ({
          source: "LOCAL",
          readOnly: false,
          resolution: "company",
        })),
      } as any,
      taxes as any,
    );

    await service.updateSettings(
      { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
      {
        taxEnabled: true,
        defaultTaxId: "tax-new",
        defaultTaxRate: 0.18,
        pricesIncludeTax: true,
        ncfEnabled: true,
      },
    );

    expect(taxes.updateFiscalSettings).toHaveBeenCalledWith(
      expect.objectContaining({ companyId: "company-a" }),
      {
        taxEnabled: true,
        defaultTaxId: "tax-new",
        defaultTaxRate: 0.18,
        pricesIncludeTax: true,
        ncfEnabled: true,
      },
    );
  });

  it("persists measurementUnitsEnabled on Company without changing Company.name", async () => {
    const tx = {
      company: {
        findUnique: jest.fn().mockResolvedValue({
          name: "FullPOS Cloud",
          measurementUnitsEnabled: false,
          multiWarehouseEnabled: false,
        }),
        update: jest.fn().mockResolvedValue({}),
      },
      appConfig: {
        upsert: jest.fn().mockResolvedValue({
          companyName: "FullPOS Cloud",
          rnc: "",
          phone: "",
          phonePreferential: "",
          address: "",
          description: "",
          instagramUrl: "",
          facebookUrl: "",
          websiteUrl: "",
          gpsLocationUrl: "",
          businessHours: "",
          bankAccounts: [],
          legalRepresentativeName: "",
          legalRepresentativeCedula: "",
          legalRepresentativeRole: "",
          legalRepresentativeNationality: "",
          legalRepresentativeCivilStatus: "",
          logoBase64: null,
          openAiApiKey: null,
          openAiModel: "gpt-4o-mini",
          evolutionApiBaseUrl: "",
          evolutionApiInstanceName: "",
          evolutionApiApiKey: null,
          whatsappWebhookEnabled: false,
          measurementUnitsEnabled: true,
          adminAuthorizationPinHash: null,
        }),
      },
    };
    const prisma = {
      $transaction: jest.fn((callback) => callback(tx)),
    };
    const service = buildService(prisma);

    const response = await service.updateSettings(
      { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
      { measurementUnitsEnabled: true },
    );

    expect(tx.company.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: "company-a" },
        data: expect.objectContaining({ measurementUnitsEnabled: true }),
        select: { id: true },
      }),
    );
    expect(tx.company.update).not.toHaveBeenCalledWith(
      expect.objectContaining({ data: expect.objectContaining({ name: "" }) }),
    );
    expect(tx.appConfig.upsert.mock.calls[0][0].update).not.toHaveProperty(
      "measurementUnitsEnabled",
    );
    expect(tx.appConfig.upsert.mock.calls[0][0].update).not.toHaveProperty(
      "companyName",
    );
    expect(tx.company.update.mock.calls[0][0].data).toMatchObject({
      measurementUnitsEnabled: true,
    });
    expect(response.measurementUnitsEnabled).toBe(true);
  });

  it("persists inventory feature flags from tolerant boolean payloads", async () => {
    const tx = {
      company: {
        findUnique: jest.fn().mockResolvedValue({
          name: "FullPOS Cloud",
          measurementUnitsEnabled: false,
          multiWarehouseEnabled: false,
        }),
        update: jest.fn().mockResolvedValue({}),
      },
      appConfig: {
        upsert: jest.fn().mockResolvedValue({
          companyName: "FullPOS Cloud",
          rnc: "",
          phone: "",
          phonePreferential: "",
          address: "",
          description: "",
          instagramUrl: "",
          facebookUrl: "",
          websiteUrl: "",
          gpsLocationUrl: "",
          businessHours: "",
          bankAccounts: [],
          legalRepresentativeName: "",
          legalRepresentativeCedula: "",
          legalRepresentativeRole: "",
          legalRepresentativeNationality: "",
          legalRepresentativeCivilStatus: "",
          logoBase64: null,
          openAiApiKey: null,
          openAiModel: "gpt-4o-mini",
          evolutionApiBaseUrl: "",
          evolutionApiInstanceName: "",
          evolutionApiApiKey: null,
          whatsappWebhookEnabled: false,
          adminAuthorizationPinHash: null,
        }),
      },
      warehouse: {
        findUnique: jest.fn().mockResolvedValue({ id: "warehouse-default" }),
        findFirst: jest.fn(),
        create: jest.fn(),
      },
      terminal: {
        findUnique: jest.fn().mockResolvedValue({
          id: "terminal-default",
          defaultWarehouseId: "warehouse-default",
          isDefault: true,
          isActive: true,
        }),
        findFirst: jest.fn(),
        create: jest.fn(),
        update: jest.fn(),
      },
      product: {
        findMany: jest.fn().mockResolvedValue([]),
      },
      warehouseStock: {
        findFirst: jest.fn(),
        create: jest.fn(),
        findMany: jest.fn().mockResolvedValue([]),
        count: jest.fn().mockResolvedValue(0),
      },
      inventoryZeroConfigState: {
        findUnique: jest.fn().mockResolvedValue(null),
        upsert: jest.fn(),
        update: jest.fn(),
      },
    };
    const prisma = {
      $transaction: jest.fn((callback) => callback(tx)),
    };
    const service = buildService(prisma);

    const response = await service.updateSettings(
      { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
      { measurementUnitsEnabled: "true", multiWarehouseEnabled: 1 },
    );

    expect(tx.company.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: "company-a" },
        data: expect.objectContaining({
          measurementUnitsEnabled: true,
          multiWarehouseEnabled: true,
        }),
      }),
    );
    expect(response.measurementUnitsEnabled).toBe(true);
    expect(response.multiWarehouseEnabled).toBe(true);
  });

  it("blocks disabling measurement units when an ACTIVE measured product exists", async () => {
    const { tx, prisma } = buildDisableGuardTx({ id: "product-yard-active" });
    const service = buildService(prisma);

    await expect(
      service.updateSettings(
        { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
        { measurementUnitsEnabled: false },
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(tx.product.findFirst).toHaveBeenCalledWith({
      where: {
        companyId: "company-a",
        archivedAt: null,
        unitOfMeasureId: { not: "UNIT" },
      },
      select: { id: true },
    });
    expect(tx.company.update).not.toHaveBeenCalled();
  });

  it("allows disabling when only ARCHIVED measured products exist (ARCHIVED POUND + ACTIVE UNIT)", async () => {
    // El filtro a nivel de BD (archivedAt: null) excluye los productos
    // archivados: aunque el tenant tenga un POUND archivado, findFirst no lo ve.
    const { tx, prisma } = buildDisableGuardTx(null);
    const service = buildService(prisma);

    const response = await service.updateSettings(
      { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
      { measurementUnitsEnabled: false },
    );

    expect(tx.product.findFirst).toHaveBeenCalledWith({
      where: {
        companyId: "company-a",
        archivedAt: null,
        unitOfMeasureId: { not: "UNIT" },
      },
      select: { id: true },
    });
    expect(tx.company.update).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: "company-a" },
        data: expect.objectContaining({ measurementUnitsEnabled: false }),
      }),
    );
    expect(response.measurementUnitsEnabled).toBe(false);
    // El producto archivado no se toca: conserva su UoM histórico.
    expect(tx.product.update).toBeUndefined();
    expect(tx.product.updateMany).toBeUndefined();
  });

  it("allows disabling with several ARCHIVED measured products and only ACTIVE UNIT products", async () => {
    // Archived POUND + YARD + METER no bloquean; solo cuentan los ACTIVOS UNIT.
    const { tx, prisma } = buildDisableGuardTx(null);
    const service = buildService(prisma);

    const response = await service.updateSettings(
      { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
      { measurementUnitsEnabled: false },
    );

    expect(response.measurementUnitsEnabled).toBe(false);
    expect(tx.product.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          companyId: "company-a",
          archivedAt: null,
        }),
      }),
    );
    expect(tx.company.update).toHaveBeenCalledTimes(1);
  });

  it("blocks disabling when an ACTIVE YARD product exists even if an ARCHIVED POUND also exists", async () => {
    const { tx, prisma } = buildDisableGuardTx({ id: "product-yard-active" });
    const service = buildService(prisma);

    await expect(
      service.updateSettings(
        { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
        { measurementUnitsEnabled: false },
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(tx.product.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          companyId: "company-a",
          archivedAt: null,
          unitOfMeasureId: { not: "UNIT" },
        }),
      }),
    );
    expect(tx.company.update).not.toHaveBeenCalled();
  });

  it("allows disabling when there are no products at all", async () => {
    const { tx, prisma } = buildDisableGuardTx(null);
    const service = buildService(prisma);

    const response = await service.updateSettings(
      { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
      { measurementUnitsEnabled: false },
    );

    expect(response.measurementUnitsEnabled).toBe(false);
    expect(tx.product.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          companyId: "company-a",
          archivedAt: null,
          unitOfMeasureId: { not: "UNIT" },
        }),
      }),
    );
  });

  it("keeps the disable guard strictly company-scoped (tenant isolation)", async () => {
    // Un producto medido de OTRA empresa nunca puede bloquear: la consulta se
    // acota SIEMPRE al companyId de la sesión.
    const { tx, prisma } = buildDisableGuardTx(null);
    const service = buildService(prisma);

    const response = await service.updateSettings(
      { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
      { measurementUnitsEnabled: false },
    );

    expect(response.measurementUnitsEnabled).toBe(false);
    expect(tx.product.findFirst).toHaveBeenCalledTimes(1);
    expect(tx.product.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ companyId: "company-a" }),
      }),
    );
  });

  it("does not run the disable guard when enabling measurement units", async () => {
    const tx = {
      company: {
        findUnique: jest.fn().mockResolvedValue({
          name: "FullPOS Cloud",
          measurementUnitsEnabled: false,
          multiWarehouseEnabled: false,
        }),
        update: jest.fn().mockResolvedValue({}),
      },
      product: {
        findFirst: jest.fn(),
      },
      appConfig: {
        upsert: jest.fn().mockResolvedValue({
          ...baseConfig(),
          measurementUnitsEnabled: true,
        }),
      },
    };
    const prisma = {
      $transaction: jest.fn((callback) => callback(tx)),
    };
    const service = buildService(prisma);

    const response = await service.updateSettings(
      { id: "admin-a", role: Role.ADMIN, companyId: "company-a" },
      { measurementUnitsEnabled: true },
    );

    expect(tx.product.findFirst).not.toHaveBeenCalled();
    expect(tx.company.update).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ measurementUnitsEnabled: true }),
      }),
    );
    expect(response.measurementUnitsEnabled).toBe(true);
  });

  it("defaults multiWarehouseEnabled to false when loading company settings", async () => {
    const prisma = {
      company: {
        findUnique: jest.fn().mockResolvedValue({
          name: "FullPOS Cloud",
          measurementUnitsEnabled: false,
          multiWarehouseEnabled: false,
        }),
      },
      appConfig: {
        upsert: jest.fn().mockResolvedValue({
          companyName: "FullPOS Cloud",
          rnc: "",
          phone: "",
          phonePreferential: "",
          address: "",
          description: "",
          instagramUrl: "",
          facebookUrl: "",
          websiteUrl: "",
          gpsLocationUrl: "",
          businessHours: "",
          bankAccounts: [],
          legalRepresentativeName: "",
          legalRepresentativeCedula: "",
          legalRepresentativeRole: "",
          legalRepresentativeNationality: "",
          legalRepresentativeCivilStatus: "",
          logoBase64: null,
          openAiApiKey: null,
          openAiModel: "gpt-4o-mini",
          evolutionApiBaseUrl: "",
          evolutionApiInstanceName: "",
          evolutionApiApiKey: null,
          whatsappWebhookEnabled: false,
          adminAuthorizationPinHash: null,
        }),
        update: jest.fn(),
      },
    };
    const service = buildService(prisma);

    const response = await service.getSettings({
      id: "admin-a",
      role: Role.ADMIN,
      companyId: "company-a",
    });

    expect(response.multiWarehouseEnabled).toBe(false);
  });

  it("issues tenant-bound admin PIN authorization for the requested scope only", async () => {
    const signAsync = jest.fn().mockResolvedValue("scoped-token");
    const prisma = {
      appConfig: {
        findUnique: jest.fn().mockResolvedValue({
          adminAuthorizationPinHash: await bcrypt.hash("1234", 4),
        }),
      },
    };
    const service = new SettingsService(
      prisma as any,
      { signAsync } as any,
      { emitCompany: jest.fn() } as any,
      {
        resolveForCompany: jest.fn(),
      } as any,
      {
        getCompanyFiscalSettings: jest.fn(),
        updateFiscalSettings: jest.fn(),
      } as any,
    );

    const result = await service.verifyAdminPin(
      { id: "cashier-a", role: Role.CAJERO, companyId: "company-a" },
      "1234",
      "addStock",
    );

    expect(signAsync).toHaveBeenCalledWith(
      {
        sub: "cashier-a",
        companyId: "company-a",
        tokenType: "admin-authorization",
        permissions: ["addStock"],
      },
      { expiresIn: 600 },
    );
    expect(result).toMatchObject({
      ok: true,
      adminAuthorizationToken: "scoped-token",
      permissions: ["addStock"],
    });
  });

  it("rejects admin PIN verification without a safe scope", async () => {
    const prisma = {
      appConfig: {
        findUnique: jest.fn(),
      },
    };
    const service = buildService(prisma);

    await expect(
      service.verifyAdminPin(
        { id: "cashier-a", role: Role.CAJERO, companyId: "company-a" },
        "1234",
        "",
      ),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.appConfig.findUnique).not.toHaveBeenCalled();
  });
});
