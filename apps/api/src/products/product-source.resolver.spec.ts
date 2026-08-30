import { ServiceUnavailableException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { ProductSourceResolver } from "./product-source.resolver";

describe("ProductSourceResolver", () => {
  const companyId = "11111111-1111-1111-1111-111111111111";

  function buildResolver(
    company: Record<string, unknown> | null,
    config: Record<string, string> = {},
  ) {
    const prisma = {
      company: {
        findUnique: jest.fn().mockResolvedValue(company),
      },
    };
    const resolver = new ProductSourceResolver(
      prisma as never,
      {
        get: jest.fn((key: string) => config[key] ?? ""),
      } as unknown as ConfigService,
    );
    return { resolver, prisma };
  }

  it("prefers company-specific product source over legacy env", async () => {
    const { resolver } = buildResolver(
      { productSource: "LOCAL", fullposCompanyId: null },
      { PRODUCTS_SOURCE: "FULLPOS", FULLPOS_COMPANY_ID: "legacy-fullpos" },
    );

    await expect(resolver.resolveForCompany(companyId)).resolves.toMatchObject({
      companyId,
      source: "LOCAL",
      readOnly: false,
      fullposCompanyId: null,
      resolution: "company",
      supportsDecimalStock: true,
      supportsNativeUom: true,
    });
  });

  it("uses PRODUCTS_SOURCE as a controlled legacy fallback", async () => {
    const { resolver } = buildResolver(
      { productSource: null, fullposCompanyId: "company-fullpos" },
      { PRODUCTS_SOURCE: "FULLPOS" },
    );

    await expect(resolver.resolveForCompany(companyId)).resolves.toMatchObject({
      source: "FULLPOS",
      readOnly: true,
      fullposCompanyId: "company-fullpos",
      resolution: "legacy-env",
      supportsDecimalStock: false,
      supportsNativeUom: false,
    });
  });

  it("falls back to LOCAL when no company or legacy source exists", async () => {
    const { resolver } = buildResolver({
      productSource: null,
      fullposCompanyId: null,
    });

    await expect(resolver.resolveForCompany(companyId)).resolves.toMatchObject({
      source: "LOCAL",
      readOnly: false,
      resolution: "safe-default",
    });
  });

  it("rejects FULLPOS_DIRECT without a tenant provider mapping", async () => {
    const { resolver } = buildResolver(
      { productSource: "FULLPOS_DIRECT", fullposCompanyId: null },
      { PRODUCTS_SOURCE: "LOCAL" },
    );

    await expect(resolver.resolveForCompany(companyId)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });
});
