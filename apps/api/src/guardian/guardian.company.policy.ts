/**
 * FASE 7 — Política de activación de APPYRA Guardian por empresa.
 *
 * Regla única y explícita: una empresa solo está instrumentada si
 * `companies.guardian_enabled = true`. El valor por defecto es `false`, así que
 * ni las empresas existentes ni las nuevas envían telemetría, consumen IA ni
 * generan alertas hasta que un administrador de plataforma lo active.
 *
 * Se aplica en TODOS los caminos de entrada para que una credencial válida no
 * pueda saltarse la desactivación de la empresa:
 *   - ingesta por sesión (`/guardian/incidents`)
 *   - ingesta por credencial de máquina (`/guardian/machine/incidents`)
 *   - autenticación de la credencial (`GuardianMachineService.authenticate`)
 *   - canje de códigos de enrolamiento
 *   - diagnóstico IA y planificación de alertas
 *   - panel administrativo de la empresa
 */

/** Motivo estable para rechazos/saltos por política de empresa. */
export const GUARDIAN_COMPANY_DISABLED = 'COMPANY_GUARDIAN_DISABLED';

/** Lector mínimo necesario (facilita pruebas sin Prisma real). */
export type GuardianCompanyPolicyReader = {
  company: {
    findUnique(args: {
      where: { id: string };
      select: { guardianEnabled: true };
    }): Promise<{ guardianEnabled: boolean } | null>;
  };
};

/**
 * `true` solo si la empresa existe y tiene Guardian activado.
 *
 * Fail-closed: una empresa inexistente, un id vacío o un error de lectura se
 * tratan como deshabilitados. Nunca lanza.
 */
export async function isGuardianEnabledForCompany(
  prisma: GuardianCompanyPolicyReader,
  companyId: string | null | undefined,
): Promise<boolean> {
  const id = String(companyId ?? '').trim();
  if (!id) return false;
  try {
    const company = await prisma.company.findUnique({
      where: { id },
      select: { guardianEnabled: true },
    });
    return company?.guardianEnabled === true;
  } catch {
    // Un fallo de lectura no puede habilitar telemetría por accidente.
    return false;
  }
}
