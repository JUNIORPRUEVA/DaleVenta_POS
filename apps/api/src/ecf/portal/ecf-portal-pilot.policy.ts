/**
 * Politica del piloto de certificacion del portal e-CF.
 *
 * Existe para que exista UNA sola definicion de "esta empresa esta incluida en
 * el piloto". La consumen dos sitios distintos:
 *
 *  - el portal (`EcfCertificationPortalService`), que emite tickets y sesiones;
 *  - la configuracion de empresa (`SettingsService`), que decide si el menu
 *    muestra la entrada del modulo sin encender la emision.
 *
 * Duplicar la lectura del entorno en ambos lados permitiria que la interfaz
 * ofreciera una entrada que el backend rechaza (o al reves), asi que la regla
 * vive aqui y solo aqui.
 *
 * Cerrada por defecto: sin la variable de entorno configurada, ninguna empresa
 * esta incluida.
 */

/** Variable de entorno con los `companyId` autorizados para el piloto. */
export const PORTAL_PILOT_COMPANIES_ENV = "ECF_PORTAL_PILOT_COMPANY_IDS";

/** Lista de empresas del piloto. Acepta comas y espacios; ignora vacios. */
export function parsePilotCompanyIds(raw: string | undefined | null): string[] {
  return `${raw ?? ""}`
    .split(/[\s,;]+/)
    .map((value) => value.trim().toLowerCase())
    .filter((value) => value.length > 0);
}

/**
 * `true` solo si [companyId] figura en la lista del piloto.
 *
 * La comparacion es en minusculas y sin espacios en los extremos: los `uuid`
 * pueden venir con mayusculas desde una peticion, pero la comparacion no debe
 * depender de ello.
 */
export function isEcfPortalPilotCompany(
  companyId: string | null | undefined,
  raw: string | undefined | null = process.env[PORTAL_PILOT_COMPANIES_ENV],
): boolean {
  const candidate = `${companyId ?? ""}`.trim().toLowerCase();
  if (!candidate) return false;
  return parsePilotCompanyIds(raw).includes(candidate);
}
