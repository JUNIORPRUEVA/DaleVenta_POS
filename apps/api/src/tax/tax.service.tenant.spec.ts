import { TaxService } from "./tax.service";
import { TaxCalculationService } from "./tax-calculation.service";
import { Prisma } from "@prisma/client";

describe("TaxService tenant isolation (multiempresa)", () => {
  const companyA = "11111111-1111-1111-1111-111111111111";
  const companyB = "22222222-2222-4222-8222-222222222222";

  function buildService(taxFindMany: jest.Mock) {
    const prisma = {
      tax: {
        findMany: taxFindMany,
        findFirst: jest.fn().mockResolvedValue({
          id: "t-1",
          companyId: companyA,
          name: "ITBIS",
          rate: 0.18,
          isActive: true,
          isDefault: true,
        }),
      },
      company: {
        findUnique: jest.fn().mockResolvedValue({
          id: companyA,
          taxEnabled: true,
          defaultTaxId: "t-1",
          defaultTaxRate: 0.18,
          pricesIncludeTax: false,
          ncfEnabled: false,
        }),
      },
    };
    const calculator = {} as TaxCalculationService;
    const service = new TaxService(prisma as never, calculator);
    return { service };
  }

  it("lists taxes scoped strictly to the authenticated company", async () => {
    const taxFindMany = jest.fn().mockResolvedValue([]);
    const { service } = buildService(taxFindMany);

    await service.listTaxes({
      id: "user-a",
      role: "ADMIN",
      companyId: companyA,
    } as never);

    expect(taxFindMany).toHaveBeenCalledWith({
      where: { companyId: companyA },
      orderBy: [{ isDefault: "desc" }, { name: "asc" }],
    });
  });

  it("never applies a global/other-company cache to a different tenant", async () => {
    const taxFindMany = jest
      .fn()
      .mockImplementation((args: { where: { companyId: string } }) => {
        return Promise.resolve(
          args.where.companyId === companyA
            ? [
                {
                  id: "tA",
                  companyId: companyA,
                  name: "ITBIS A",
                  rate: 0.18,
                  isActive: true,
                  isDefault: true,
                },
              ]
            : [
                {
                  id: "tB",
                  companyId: companyB,
                  name: "ITBIS B",
                  rate: 0.16,
                  isActive: true,
                  isDefault: true,
                },
              ],
        );
      });
    const { service } = buildService(taxFindMany);

    const forA = await service.listTaxes({
      id: "user-a",
      role: "ADMIN",
      companyId: companyA,
    } as never);
    const forB = await service.listTaxes({
      id: "user-b",
      role: "ADMIN",
      companyId: companyB,
    } as never);

    expect(forA[0].companyId).toBe(companyA);
    expect(forB[0].companyId).toBe(companyB);
    expect(taxFindMany).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({ where: { companyId: companyA } }),
    );
    expect(taxFindMany).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({ where: { companyId: companyB } }),
    );
  });

  it("recovers a stale defaultTaxId during settings replay without crossing tenants", async () => {
    const tx = {
      tax: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce(null)
          .mockResolvedValueOnce(null),
        create: jest.fn().mockResolvedValue({
          id: "tax-recovered",
          companyId: companyA,
          name: "ITBIS",
          rate: new Prisma.Decimal(0.18),
          isActive: true,
          isDefault: true,
        }),
        updateMany: jest.fn().mockResolvedValue({ count: 0 }),
        update: jest.fn().mockResolvedValue({
          id: "tax-recovered",
          companyId: companyA,
          name: "ITBIS",
          rate: new Prisma.Decimal(0.18),
          isActive: true,
          isDefault: true,
        }),
      },
      company: {
        update: jest.fn().mockResolvedValue({
          id: companyA,
          taxEnabled: true,
          defaultTaxId: "tax-recovered",
          defaultTaxRate: new Prisma.Decimal(0.18),
          pricesIncludeTax: true,
          ncfEnabled: true,
        }),
      },
    };
    const prisma = {
      $transaction: jest.fn((callback) => callback(tx)),
    };
    const service = new TaxService(
      prisma as never,
      {} as TaxCalculationService,
    );

    const result = await service.updateFiscalSettings(
      { id: "admin-a", role: "ADMIN", companyId: companyA } as never,
      {
        taxEnabled: true,
        defaultTaxId: "stale-local-tax-id",
        defaultTaxRate: 0.18,
        pricesIncludeTax: true,
        ncfEnabled: true,
      },
    );

    expect(tx.tax.findFirst).toHaveBeenNthCalledWith(1, {
      where: { id: "stale-local-tax-id", companyId: companyA, isActive: true },
    });
    expect(tx.tax.findFirst).toHaveBeenNthCalledWith(2, {
      where: { companyId: companyA, name: "ITBIS" },
    });
    expect(tx.tax.create).toHaveBeenCalledWith({
      data: {
        companyId: companyA,
        name: "ITBIS",
        rate: new Prisma.Decimal(0.18),
        isActive: true,
        isDefault: true,
      },
    });
    expect(tx.company.update).toHaveBeenCalledWith({
      where: { id: companyA },
      data: {
        taxEnabled: true,
        defaultTaxId: "tax-recovered",
        defaultTaxRate: new Prisma.Decimal(0.18),
        pricesIncludeTax: true,
        ncfEnabled: true,
      },
      select: expect.objectContaining({ defaultTaxId: true }),
    });
    expect(result.defaultTaxId).toBe("tax-recovered");
  });

  it("uses a valid existing defaultTaxId without creating a replay tax", async () => {
    const tx = {
      tax: {
        findFirst: jest.fn().mockResolvedValue({
          id: "tax-existing",
          companyId: companyA,
          name: "ITBIS",
          rate: new Prisma.Decimal(0.18),
          isActive: true,
          isDefault: false,
        }),
        create: jest.fn(),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
        update: jest.fn().mockResolvedValue({
          id: "tax-existing",
          companyId: companyA,
          name: "ITBIS",
          rate: new Prisma.Decimal(0.18),
          isActive: true,
          isDefault: true,
        }),
      },
      company: {
        update: jest.fn().mockResolvedValue({
          id: companyA,
          taxEnabled: true,
          defaultTaxId: "tax-existing",
          defaultTaxRate: new Prisma.Decimal(0.18),
          pricesIncludeTax: true,
          ncfEnabled: true,
        }),
      },
    };
    const service = new TaxService(
      { $transaction: jest.fn((callback) => callback(tx)) } as never,
      {} as TaxCalculationService,
    );

    await service.updateFiscalSettings(
      { id: "admin-a", role: "ADMIN", companyId: companyA } as never,
      {
        taxEnabled: true,
        defaultTaxId: "tax-existing",
        defaultTaxRate: 0.16,
        pricesIncludeTax: true,
        ncfEnabled: true,
      },
    );

    expect(tx.tax.findFirst).toHaveBeenCalledWith({
      where: { id: "tax-existing", companyId: companyA, isActive: true },
    });
    expect(tx.tax.create).not.toHaveBeenCalled();
    expect(tx.company.update).toHaveBeenCalledWith({
      where: { id: companyA },
      data: {
        taxEnabled: true,
        defaultTaxId: "tax-existing",
        defaultTaxRate: new Prisma.Decimal(0.18),
        pricesIncludeTax: true,
        ncfEnabled: true,
      },
      select: expect.objectContaining({ defaultTaxId: true }),
    });
  });

  it("reuses the same-company ITBIS row on repeated stale settings replay", async () => {
    const recoveredTax = {
      id: "tax-recovered",
      companyId: companyA,
      name: "ITBIS",
      rate: new Prisma.Decimal(0.18),
      isActive: true,
      isDefault: true,
    };
    const tx = {
      tax: {
        findFirst: jest
          .fn()
          .mockResolvedValueOnce(null)
          .mockResolvedValueOnce(recoveredTax)
          .mockResolvedValueOnce(null)
          .mockResolvedValueOnce(recoveredTax),
        create: jest.fn(),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
        update: jest.fn().mockResolvedValue(recoveredTax),
      },
      company: {
        update: jest.fn().mockResolvedValue({
          id: companyA,
          taxEnabled: true,
          defaultTaxId: recoveredTax.id,
          defaultTaxRate: recoveredTax.rate,
          pricesIncludeTax: true,
          ncfEnabled: true,
        }),
      },
    };
    const service = new TaxService(
      { $transaction: jest.fn((callback) => callback(tx)) } as never,
      {} as TaxCalculationService,
    );
    const input = {
      taxEnabled: true,
      defaultTaxId: "stale-local-tax-id",
      defaultTaxRate: 0.18,
      pricesIncludeTax: true,
      ncfEnabled: true,
    };

    await service.updateFiscalSettings(
      { id: "admin-a", role: "ADMIN", companyId: companyA } as never,
      input,
    );
    await service.updateFiscalSettings(
      { id: "admin-a", role: "ADMIN", companyId: companyA } as never,
      input,
    );

    expect(tx.tax.findFirst).toHaveBeenNthCalledWith(2, {
      where: { companyId: companyA, name: "ITBIS" },
    });
    expect(tx.tax.findFirst).toHaveBeenNthCalledWith(4, {
      where: { companyId: companyA, name: "ITBIS" },
    });
    expect(tx.tax.create).not.toHaveBeenCalled();
    expect(tx.company.update).toHaveBeenCalledTimes(2);
  });
});
