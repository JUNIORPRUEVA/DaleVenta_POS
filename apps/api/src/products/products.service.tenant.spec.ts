import { ConfigService } from "@nestjs/config";
import { ProductsService } from "./products.service";

describe("ProductsService tenant isolation (multiempresa)", () => {
  function buildService(
    findMany: jest.Mock,
    options: {
      config?: Record<string, string>;
      catalogProducts?: { findAll?: jest.Mock };
      resolveSource?: jest.Mock;
    } = {},
  ) {
    const prisma = {
      product: { findMany },
    };
    const resolveSource =
      options.resolveSource ??
      jest.fn(async (companyId: string) => ({
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
      }));
    const service = new ProductsService(
      prisma as never,
      (options.catalogProducts ?? {}) as never,
      { resolveForCompany: resolveSource } as never,
      {
        get: jest.fn((key: string) => options.config?.[key] ?? ""),
      } as unknown as ConfigService,
      {
        assertCanCreateProduct: jest.fn().mockResolvedValue(undefined),
      } as never,
    );
    return { service, prisma, resolveSource };
  }

  const companyA = "11111111-1111-1111-1111-111111111111";
  const companyB = "22222222-2222-4222-8222-222222222222";

  it("list all products scoped strictly to the authenticated company", async () => {
    const findMany = jest.fn().mockResolvedValue([
      {
        id: "p-1",
        companyId: companyA,
        nombre: "Producto A",
        codigo: "A-1",
        categoria: "General",
        costo: 10,
        precio: 20,
        stock: 5,
        taxTreatment: "INHERIT",
        taxRate: null,
        taxPriceMode: null,
        imagen: null,
        imageKey: null,
        imageUpdatedAt: null,
      },
    ]);
    const { service } = buildService(findMany);

    const result = await service.findAll({
      id: "user-a",
      role: "ADMIN",
      companyId: companyA,
    } as never);

    // La consulta SIEMPRE filtra por la empresa del usuario autenticado.
    expect(findMany).toHaveBeenCalledWith({
      where: { companyId: companyA },
      orderBy: { nombre: "asc" },
      select: expect.any(Object),
    });
    expect(result).toHaveLength(1);
    expect(result[0].id).toBe("p-1");
  });

  it("does NOT reuse the where filter across companies (A nunca ve B)", async () => {
    const findMany = jest
      .fn()
      .mockImplementation((args: { where: { companyId: string } }) => {
        return Promise.resolve(
          args.where.companyId === companyA
            ? [
                {
                  id: "pA",
                  companyId: companyA,
                  nombre: "Producto de A",
                  codigo: "A",
                  categoria: "General",
                  costo: 1,
                  precio: 2,
                  stock: 3,
                  taxTreatment: "INHERIT",
                  taxRate: null,
                  taxPriceMode: null,
                  imagen: null,
                  imageKey: null,
                  imageUpdatedAt: null,
                },
              ]
            : [
                {
                  id: "pB",
                  companyId: companyB,
                  nombre: "Producto de B",
                  codigo: "B",
                  categoria: "General",
                  costo: 1,
                  precio: 2,
                  stock: 3,
                  taxTreatment: "INHERIT",
                  taxRate: null,
                  taxPriceMode: null,
                  imagen: null,
                  imageKey: null,
                  imageUpdatedAt: null,
                },
              ],
        );
      });
    const { service } = buildService(findMany);

    const forA = await service.findAll({
      id: "user-a",
      role: "ADMIN",
      companyId: companyA,
    } as never);
    const forB = await service.findAll({
      id: "user-b",
      role: "ADMIN",
      companyId: companyB,
    } as never);

    expect(forA[0].id).toBe("pA");
    expect(forB[0].id).toBe("pB");
    expect(findMany).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({ where: { companyId: companyA } }),
    );
    expect(findMany).toHaveBeenNthCalledWith(
      2,
      expect.objectContaining({ where: { companyId: companyB } }),
    );
  });

  it("uses an explicit SELECT that excludes unused heavy columns", async () => {
    const findMany = jest.fn().mockResolvedValue([]);
    const { service } = buildService(findMany);
    await service.findAll({
      id: "user-a",
      role: "ADMIN",
      companyId: companyA,
    } as never);

    const select = (findMany.mock.calls[0][0] as { select: Record<string, boolean> })
      .select;
    // Campos que SÍ deben incluirse (consumidos por los clientes).
    for (const field of [
      "id",
      "companyId",
      "nombre",
      "codigo",
      "categoria",
      "costo",
      "precio",
      "stock",
      "taxTreatment",
      "taxRate",
      "taxPriceMode",
      "imagen",
      "imageKey",
      "imageUpdatedAt",
    ]) {
      expect(select[field]).toBe(true);
    }
    // Columnas pesadas que ningún cliente POS consume: no deben leerse.
    expect(select.imageStorageProvider).toBeUndefined();
    expect(select.imageMimeType).toBeUndefined();
    expect(select.imageOriginalFileName).toBeUndefined();
  });

  it("falls back to the legacy product select when production has not received UoM columns yet", async () => {
    const schemaMismatch = {
      code: "P2022",
      message: 'The column `Product.unitOfMeasureId` does not exist',
    };
    const findMany = jest
      .fn()
      .mockRejectedValueOnce(schemaMismatch)
      .mockResolvedValueOnce([
        {
          id: "legacy-product",
          companyId: companyA,
          nombre: "Producto legacy",
          codigo: "LEG-1",
          categoria: "General",
          costo: 10,
          precio: 20,
          stock: 5,
          taxTreatment: "INHERIT",
          taxRate: null,
          taxPriceMode: null,
          imagen: null,
          imageKey: null,
          imageUpdatedAt: null,
        },
      ]);
    const { service } = buildService(findMany);

    const result = await service.findAll({
      id: "user-a",
      role: "ADMIN",
      companyId: companyA,
    } as never);

    expect(findMany).toHaveBeenCalledTimes(2);
    expect(findMany.mock.calls[0][0].select.unitOfMeasureId).toBe(true);
    expect(findMany.mock.calls[1][0].select.unitOfMeasureId).toBeUndefined();
    expect(findMany.mock.calls[1][0].select.unitOfMeasure).toBeUndefined();
    expect(result[0]).toMatchObject({
      id: "legacy-product",
      unitOfMeasureId: "UNIT",
      unitOfMeasure: expect.objectContaining({ code: "UNIT", precision: 0 }),
    });
  });

  it("uses the company product source to read FULLPOS instead of the empty local Product table", async () => {
    const findMany = jest.fn();
    const catalogFindAll = jest.fn().mockResolvedValue({
      items: [{ id: "external-1", nombre: "Producto externo" }],
    });
    const resolveSource = jest.fn(async (companyId: string) => ({
      companyId,
      source: "FULLPOS",
      readOnly: true,
      fullposCompanyId: "fullpos-company-a",
      supportsDecimalStock: false,
      supportsNativeUom: false,
      supportsProductCreate: false,
      supportsProductEdit: false,
      supportsStockAdjustment: false,
      resolution: "company",
    }));
    const { service } = buildService(findMany, {
      catalogProducts: { findAll: catalogFindAll },
      resolveSource,
    });

    const result = await service.findAll({
      id: "user-a",
      role: "ADMIN",
      companyId: companyA,
    } as never);

    expect(resolveSource).toHaveBeenCalledWith(companyA);
    expect(catalogFindAll).toHaveBeenCalledWith({
      companyId: companyA,
      source: "FULLPOS",
      fullposCompanyId: "fullpos-company-a",
    });
    expect(findMany).not.toHaveBeenCalled();
    expect(result).toEqual([{ id: "external-1", nombre: "Producto externo" }]);
    await expect(
      service.getSource({
        id: "user-a",
        role: "ADMIN",
        companyId: companyA,
      } as never),
    ).resolves.toBe("FULLPOS");
    await expect(
      service.isReadOnly({
        id: "user-a",
        role: "ADMIN",
        companyId: companyA,
      } as never),
    ).resolves.toBe(true);
  });

  it("keeps LOCAL and FULLPOS companies isolated in the same process", async () => {
    const findMany = jest.fn().mockResolvedValue([
      {
        id: "local-a",
        companyId: companyA,
        nombre: "Local A",
        codigo: "A",
        categoria: "General",
        costo: 1,
        precio: 2,
        stock: 3,
        taxTreatment: "INHERIT",
        taxRate: null,
        taxPriceMode: null,
        imagen: null,
        imageKey: null,
        imageUpdatedAt: null,
      },
    ]);
    const catalogFindAll = jest.fn().mockResolvedValue({
      items: [{ id: "external-b", nombre: "FullPOS B" }],
    });
    const resolveSource = jest.fn(async (companyId: string) =>
      companyId === companyA
        ? {
            companyId,
            source: "LOCAL",
            readOnly: false,
            fullposCompanyId: null,
            supportsDecimalStock: true,
            supportsNativeUom: true,
            supportsProductCreate: true,
            supportsProductEdit: true,
            supportsStockAdjustment: true,
            resolution: "company",
          }
        : {
            companyId,
            source: "FULLPOS",
            readOnly: true,
            fullposCompanyId: "fullpos-company-b",
            supportsDecimalStock: false,
            supportsNativeUom: false,
            supportsProductCreate: false,
            supportsProductEdit: false,
            supportsStockAdjustment: false,
            resolution: "company",
          },
    );
    const { service } = buildService(findMany, {
      catalogProducts: { findAll: catalogFindAll },
      resolveSource,
    });

    const local = await service.findAll({
      id: "user-a",
      role: "ADMIN",
      companyId: companyA,
    } as never);
    const external = await service.findAll({
      id: "user-b",
      role: "ADMIN",
      companyId: companyB,
    } as never);

    expect(local[0].id).toBe("local-a");
    expect(external[0].id).toBe("external-b");
    expect(findMany).toHaveBeenCalledTimes(1);
    expect(findMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { companyId: companyA } }),
    );
    expect(catalogFindAll).toHaveBeenCalledWith({
      companyId: companyB,
      source: "FULLPOS",
      fullposCompanyId: "fullpos-company-b",
    });
  });

  it("does not collapse same external sourceProductId across companies", async () => {
    const findMany = jest.fn();
    const catalogFindAll = jest
      .fn()
      .mockResolvedValueOnce({ items: [{ id: "same-1", nombre: "A" }] })
      .mockResolvedValueOnce({ items: [{ id: "same-1", nombre: "B" }] });
    const resolveSource = jest.fn(async (companyId: string) => ({
      companyId,
      source: "FULLPOS",
      readOnly: true,
      fullposCompanyId:
        companyId === companyA ? "fullpos-company-a" : "fullpos-company-b",
      supportsDecimalStock: false,
      supportsNativeUom: false,
      supportsProductCreate: false,
      supportsProductEdit: false,
      supportsStockAdjustment: false,
      resolution: "company",
    }));
    const { service } = buildService(findMany, {
      catalogProducts: { findAll: catalogFindAll },
      resolveSource,
    });

    await service.findAll({ id: "a", role: "ADMIN", companyId: companyA } as never);
    await service.findAll({ id: "b", role: "ADMIN", companyId: companyB } as never);

    expect(catalogFindAll).toHaveBeenNthCalledWith(1, {
      companyId: companyA,
      source: "FULLPOS",
      fullposCompanyId: "fullpos-company-a",
    });
    expect(catalogFindAll).toHaveBeenNthCalledWith(2, {
      companyId: companyB,
      source: "FULLPOS",
      fullposCompanyId: "fullpos-company-b",
    });
  });

  it("propagates provider failures instead of returning an empty product list", async () => {
    const providerError = new Error("provider unavailable");
    const findMany = jest.fn();
    const catalogFindAll = jest.fn().mockRejectedValue(providerError);
    const resolveSource = jest.fn(async (companyId: string) => ({
      companyId,
      source: "FULLPOS",
      readOnly: true,
      fullposCompanyId: "fullpos-company-a",
      supportsDecimalStock: false,
      supportsNativeUom: false,
      supportsProductCreate: false,
      supportsProductEdit: false,
      supportsStockAdjustment: false,
      resolution: "company",
    }));
    const { service } = buildService(findMany, {
      catalogProducts: { findAll: catalogFindAll },
      resolveSource,
    });

    await expect(
      service.findAll({ id: "a", role: "ADMIN", companyId: companyA } as never),
    ).rejects.toThrow("provider unavailable");
    expect(findMany).not.toHaveBeenCalled();
  });
});
