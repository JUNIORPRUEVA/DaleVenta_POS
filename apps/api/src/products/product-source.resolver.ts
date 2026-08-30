import {
  Injectable,
  Logger,
  ServiceUnavailableException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { Prisma } from "@prisma/client";
import { PrismaService } from "../prisma/prisma.service";

export type ProductSource = "LOCAL" | "FULLPOS" | "FULLPOS_DIRECT";

export type ProductSourceContext = {
  companyId: string;
  source: ProductSource;
  readOnly: boolean;
  fullposCompanyId: string | null;
  supportsDecimalStock: boolean;
  supportsNativeUom: boolean;
  supportsProductCreate: boolean;
  supportsProductEdit: boolean;
  supportsStockAdjustment: boolean;
  resolution: "company" | "legacy-env" | "safe-default";
};

@Injectable()
export class ProductSourceResolver {
  private readonly logger = new Logger(ProductSourceResolver.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  async resolveForCompany(companyId: string): Promise<ProductSourceContext> {
    const company = await this.readCompanySource(companyId);
    const companySource = this.normalizeSource(company?.productSource);
    const source = companySource ?? this.legacyDefaultSource();
    const resolution: ProductSourceContext["resolution"] = companySource
      ? "company"
      : this.hasLegacySource()
        ? "legacy-env"
        : "safe-default";
    const fullposCompanyId =
      this.clean(company?.fullposCompanyId) ?? this.legacyFullposCompanyId();

    if (source === "FULLPOS_DIRECT" && !fullposCompanyId) {
      throw new ServiceUnavailableException(
        "La empresa no tiene mapeo de compañía FULLPOS configurado.",
      );
    }

    return {
      companyId,
      source,
      readOnly: source !== "LOCAL",
      fullposCompanyId: source === "LOCAL" ? null : fullposCompanyId,
      supportsDecimalStock: source === "LOCAL",
      supportsNativeUom: source === "LOCAL",
      supportsProductCreate: source === "LOCAL",
      supportsProductEdit: source === "LOCAL",
      supportsStockAdjustment: source === "LOCAL",
      resolution,
    };
  }

  legacyDefaultSource(): ProductSource {
    const source = this.normalizeSource(this.config.get<string>("PRODUCTS_SOURCE"));
    if (source) return source;

    const raw = (this.config.get<string>("PRODUCTS_SOURCE") ?? "").trim();
    if (raw) {
      this.logger.warn(`PRODUCTS_SOURCE=${raw.toUpperCase()} inválido; usando LOCAL.`);
    }
    return "LOCAL";
  }

  private async readCompanySource(companyId: string) {
    try {
      return await this.prisma.company.findUnique({
        where: { id: companyId },
        select: {
          productSource: true,
          fullposCompanyId: true,
        } as any,
      });
    } catch (error) {
      if (this.isMissingColumn(error)) {
        this.logger.warn(
          "Columnas de product source no disponibles; usando fallback legado PRODUCTS_SOURCE.",
        );
        return null;
      }
      throw error;
    }
  }

  private normalizeSource(value: unknown): ProductSource | null {
    const source = String(value ?? "").trim().toUpperCase();
    if (
      source === "LOCAL" ||
      source === "FULLPOS" ||
      source === "FULLPOS_DIRECT"
    ) {
      return source;
    }
    return null;
  }

  private hasLegacySource() {
    return this.normalizeSource(this.config.get<string>("PRODUCTS_SOURCE")) != null;
  }

  private legacyFullposCompanyId() {
    return this.clean(
      this.config.get<string>("FULLPOS_COMPANY_ID") ??
        this.config.get<string>("FULLPOS_DIRECT_COMPANY_ID"),
    );
  }

  private clean(value: unknown) {
    const text = String(value ?? "").trim();
    return text.length > 0 ? text : null;
  }

  private isMissingColumn(error: unknown) {
    return (
      error instanceof Prisma.PrismaClientKnownRequestError &&
      error.code === "P2022"
    );
  }
}
