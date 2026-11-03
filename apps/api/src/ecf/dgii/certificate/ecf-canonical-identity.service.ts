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

export type EcfIdentitySource = "APPLICATION_SNAPSHOT" | "FISCAL_CONFIG" | "NONE";

/** Campos canónicos que pueden faltar. Nunca se exponen sus valores. */
export type EcfMissingCanonicalField =
  | "company.rnc"
  | "representative.identification";

export type EcfCanonicalIdentity = {
  taxId: string | null;
  legalName: string | null;
  representativeName: string | null;
  representativeId: string | null;
  /** De dónde salieron los datos, para poder explicarlo en la interfaz. */
  source: EcfIdentitySource;
  /**
   * De dónde salió concretamente la cédula del representante. Se separa de
   * `source` porque el expediente y la configuración fiscal pueden aportar
   * campos distintos y el diagnóstico debe decir cuál se usó.
   */
  representativeIdSource: EcfIdentitySource;
  /** Qué falta del expediente para poder comparar identidades. */
  missing: EcfMissingCanonicalField[];
};

@Injectable()
export class EcfCanonicalIdentityService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Resuelve la identidad canónica combinando **campo por campo** dos fuentes
   * del backend, ambas acotadas por `companyId`:
   *
   *  1. `ecfDgiiApplicationSnapshot`: lo que el administrador envió en el
   *     expediente (empresa y representante).
   *  2. `AppConfig`: los datos fiscales ya registrados de la empresa, que
   *     incluyen el representante legal y **su cédula**
   *     (`legal_representative_cedula`).
   *
   * Por qué se combinan: los certificados tributarios dominicanos pueden estar
   * emitidos a la empresa **o a la persona** que la representa o que fue
   * delegada. Antes, cuando no había expediente enviado, solo se devolvía el
   * RNC y la cédula quedaba en `null`, así que un certificado legítimo a nombre
   * del representante se rechazaba por identidad. Combinar ambas fuentes no
   * relaja la comprobación: sigue exigiendo que el identificador coincida con
   * un dato registrado de ESA empresa.
   *
   * Lo que no se hace: no se completan datos inventados, no se consulta otra
   * empresa y no se acepta nada que venga del cliente.
   */
  async resolve(companyId: string): Promise<EcfCanonicalIdentity> {
    const [snapshot, config] = await Promise.all([
      this.prisma.ecfDgiiApplicationSnapshot.findFirst({
        where: { companyId },
        orderBy: { version: "desc" },
        select: { payload: true },
      }),
      this.prisma.appConfig.findFirst({
        where: { companyId },
        select: {
          rnc: true,
          companyName: true,
          legalRepresentativeName: true,
          legalRepresentativeCedula: true,
        },
      }),
    ]);

    const payload = asRecord(snapshot?.payload);
    const company = asRecord(payload?.company);
    const representative = asRecord(payload?.representative);

    const snapshotTaxId = text(company?.rnc);
    const snapshotLegalName = text(company?.legalName);
    const snapshotRepresentativeName = text(representative?.fullName);
    const snapshotRepresentativeId = text(representative?.identification);

    const configTaxId = text(config?.rnc);
    const configLegalName = text(config?.companyName);
    const configRepresentativeName = text(config?.legalRepresentativeName);
    const configRepresentativeId = text(config?.legalRepresentativeCedula);

    // Prioridad: lo enviado en el expediente manda; la configuración fiscal
    // rellena solo lo que el expediente no trae.
    const taxId = snapshotTaxId ?? configTaxId;
    const legalName = snapshotLegalName ?? configLegalName;
    const representativeName =
      snapshotRepresentativeName ?? configRepresentativeName;
    const representativeId =
      snapshotRepresentativeId ?? configRepresentativeId;

    const usedSnapshot = Boolean(
      snapshotTaxId ||
        snapshotLegalName ||
        snapshotRepresentativeName ||
        snapshotRepresentativeId,
    );
    const usedConfig = Boolean(
      configTaxId ||
        configLegalName ||
        configRepresentativeName ||
        configRepresentativeId,
    );

    const representativeIdSource: EcfIdentitySource = snapshotRepresentativeId
      ? "APPLICATION_SNAPSHOT"
      : configRepresentativeId
        ? "FISCAL_CONFIG"
        : "NONE";

    const missing: EcfMissingCanonicalField[] = [];
    if (!taxId) missing.push("company.rnc");
    if (!representativeId) missing.push("representative.identification");

    return {
      taxId,
      legalName,
      representativeName,
      representativeId,
      source: usedSnapshot
        ? "APPLICATION_SNAPSHOT"
        : usedConfig
          ? "FISCAL_CONFIG"
          : "NONE",
      representativeIdSource,
      missing,
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
