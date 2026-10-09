import { BackupExtractor } from "./backup-extractor";

describe("BackupExtractor pagination", () => {
  it("extracts direct modules in id pages", async () => {
    const extractor = new BackupExtractor();
    const productSpec = extractor.moduleSpecs.find((spec) => spec.name === "products");
    const findMany = jest
      .fn()
      .mockResolvedValueOnce(Array.from({ length: 1000 }, (_, index) => ({
        id: `product-${String(index).padStart(4, "0")}`,
        companyId: "company-a",
      })))
      .mockResolvedValueOnce([{ id: "product-1000", companyId: "company-a" }]);

    const records = await productSpec!.extract({ product: { findMany } } as never, "company-a");

    expect(records).toHaveLength(1001);
    expect(findMany).toHaveBeenCalledTimes(2);
    expect(findMany).toHaveBeenNthCalledWith(1, {
      where: { companyId: "company-a" },
      orderBy: { id: "asc" },
      take: 1000,
    });
    expect(findMany).toHaveBeenNthCalledWith(2, {
      where: {
        AND: [
          { companyId: "company-a" },
          { id: { gt: "product-0999" } },
        ],
      },
      orderBy: { id: "asc" },
      take: 1000,
    });
  });

  it("extracts indirect sale items in id pages without dropping tenant scope", async () => {
    const extractor = new BackupExtractor();
    const saleItemsSpec = extractor.moduleSpecs.find((spec) => spec.name === "sale_items");
    const findMany = jest
      .fn()
      .mockResolvedValueOnce(Array.from({ length: 1000 }, (_, index) => ({
        id: `item-${String(index).padStart(4, "0")}`,
      })))
      .mockResolvedValueOnce([]);

    await saleItemsSpec!.extract({ saleItem: { findMany } } as never, "company-a");

    expect(findMany).toHaveBeenNthCalledWith(1, {
      where: { sale: { companyId: "company-a" } },
      orderBy: { id: "asc" },
      take: 1000,
    });
    expect(findMany).toHaveBeenNthCalledWith(2, {
      where: {
        AND: [
          { sale: { companyId: "company-a" } },
          { id: { gt: "item-0999" } },
        ],
      },
      orderBy: { id: "asc" },
      take: 1000,
    });
  });
});
