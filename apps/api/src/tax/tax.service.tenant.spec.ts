import { TaxService } from "./tax.service";
import { TaxCalculationService } from "./tax-calculation.service";

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
                { id: "tA", companyId: companyA, name: "ITBIS A", rate: 0.18, isActive: true, isDefault: true },
              ]
            : [
                { id: "tB", companyId: companyB, name: "ITBIS B", rate: 0.16, isActive: true, isDefault: true },
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
});
