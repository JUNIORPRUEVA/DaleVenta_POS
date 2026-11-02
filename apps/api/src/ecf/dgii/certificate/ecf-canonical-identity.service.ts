import { Injectable } from "@nestjs/common";

import { PrismaService } from "../../../prisma/prisma.service";

/**
 * Datos CANÓNICOS del expediente fiscal de la empresa.
 *
 * Los toma el backend de lo que ya está registrado (snapshot del expediente y
 * configuración fiscal). Flutter nunca los envía: si el cliente pudiera
 * declararlos, la comprobación de identidad del certificado no valdría nada.
 *
 * No inventa datos: si no hay snapshot, devuelve `null` en cada campo y el
 * llamador debe tratar esa ausencia como «no comprobado», nunca como correcto.
 */

export type EcfCanonicalIdentity = {
  taxId: string | null;
  legalName: string | null;
  representativeName: string | null;
  representativeId: string | null;
  /** De dónde salieron los datos, para poder explicarlo en la interfaz. */
  source: "APPLICATION_SNAPSHOT" | "FISCAL_CONFIG" | "NONE";
};

@Injectable()
export class EcfCanonicalIdentityService {
  constructor(private readonly prisma: PrismaService) {}

  async resolve(companyId: string): Promise<EcfCanonicalIdentity> {
    const snapshot = await this.prisma.ecfDgiiApplicationSnapshot.findFirst({
      where: { companyId },
      orderBy: { version: "desc" },
      select: { payload: true },
    });

    const payload = asRecord(snapshot?.payload);
    const company = asRecord(payload?.company);
    const representative = asRecord(payload?.representative);

    const snapshotTaxId = text(company?.rnc);
    const legalName = text(company?.legalName);
    const representativeName = text(representative?.fullName);
    const representativeId = text(representative?.identification);

    if (snapshotTaxId || representativeId || legalName) {
      return {
        taxId: snapshotTaxId,
        legalName,
        representativeName,
        representativeId,
        source: "APPLICATION_SNAPSHOT",
      };
    }

    // Sin expediente enviado: se recurre al dato fiscal de la empresa, que es el
    // RNC con el que se emite. Nunca se completan cédula ni representante.
    const config = await this.prisma.appConfig.findFirst({
      where: { companyId },
      select: { rnc: true, companyName: true },
    });
    const configTaxId = text(config?.rnc);
    if (configTaxId) {
      return {
        taxId: configTaxId,
        legalName: text(config?.companyName),
        representativeName: null,
        representativeId: null,
        source: "FISCAL_CONFIG",
      };
    }

    return {
      taxId: null,
      legalName: null,
      representativeName: null,
      representativeId: null,
      source: "NONE",
    };
  }
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : null;
}

function text(value: unknown): string | null {
  const raw = typeof value === "string" ? value.trim() : "";
  return raw.length > 0 ? raw : null;
}
