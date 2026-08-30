import { ConfigService } from "@nestjs/config";
import { ProductsService } from "./products.service";

describe("ProductsService tenant isolation (multiempresa)", () => {
  function buildService(
    findMany: jest.Mock,
    options: {
      config?: Record<string, string>;
      catalogProducts?: { findAll?: jest.Mock };
    } = {},
  ) {
    const prisma = {
      product: { findMany },
    };
    const service = new ProductsService(
      prisma as never,
      (options.catalogProducts ?? {}) as never,
      {
        get: jest.fn((key: string) => options.config?.[key] ?? ""),
      } as unknown as ConfigService,
      {
        assertCanCreateProduct: jest.fn().mockResolvedValue(undefined),
      } as never,
    );
    return { service, prisma };
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

  it("respects PRODUCTS_SOURCE=FULLPOS instead of reading the empty local Product table", async () => {
    const findMany = jest.fn();
    const catalogFindAll = jest.fn().mockResolvedValue({
      items: [{ id: "external-1", nombre: "Producto externo" }],
    });
    const { service } = buildService(findMany, {
      config: { PRODUCTS_SOURCE: "FULLPOS" },
      catalogProducts: { findAll: catalogFindAll },
    });

    const result = await service.findAll({
      id: "user-a",
      role: "ADMIN",
      companyId: companyA,
    } as never);

    expect(catalogFindAll).toHaveBeenCalledTimes(1);
    expect(findMany).not.toHaveBeenCalled();
    expect(result).toEqual([{ id: "external-1", nombre: "Producto externo" }]);
    expect(service.getSource()).toBe("FULLPOS");
    expect(service.isReadOnly()).toBe(true);
  });
});
