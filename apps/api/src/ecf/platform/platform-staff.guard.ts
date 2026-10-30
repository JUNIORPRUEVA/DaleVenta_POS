import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";

/**
 * Identidad de PLATAFORMA (personal de Fulltech).
 *
 * Por qué existe este guard y no un permiso más:
 *
 * `RolesGuard` concede TODO a cualquier `Role.ADMIN`
 * (`if (role === Role.ADMIN) return true`). Por tanto un permiso nuevo del tipo
 * `reviewEcfDgiiApplications` lo tendría automáticamente el administrador de
 * cada empresa cliente, y una ruta multiempresa quedaría expuesta entre
 * inquilinos. Para evitarlo, estas rutas **no** usan `RolesGuard`: usan su
 * propio guard, que no mira roles de empresa.
 *
 * La lista de personal vive en `ECF_PLATFORM_STAFF_USER_IDS` (UUIDs separados
 * por comas). Es un arranque deliberadamente conservador:
 *
 * - **Fail-closed**: si la variable falta o está vacía, nadie es personal.
 * - **No auto-asignable**: un ADMIN de una empresa no puede añadirse; requiere
 *   cambiar la configuración del despliegue.
 * - **Sin migración**: no altera el modelo de datos ni el guard existente.
 *
 * Cuando exista una tabla de personal, este guard es el único punto a cambiar.
 */
export const PLATFORM_STAFF_ENV = "ECF_PLATFORM_STAFF_USER_IDS";

/** Normaliza la lista: trim, minúsculas, sin vacíos, sin duplicados. */
export function parsePlatformStaffIds(
  raw: string | undefined | null,
): Set<string> {
  return new Set(
    (raw ?? "")
      .split(",")
      .map((value) => value.trim().toLowerCase())
      .filter((value) => value.length > 0),
  );
}

@Injectable()
export class PlatformStaffGuard implements CanActivate {
  constructor(private readonly config: ConfigService) {}

  canActivate(context: ExecutionContext): boolean {
    const request = context.switchToHttp().getRequest();
    const user = request.user as { id?: string } | undefined;
    if (!user?.id) {
      throw new ForbiddenException("PLATFORM_STAFF_REQUIRED");
    }
    const staff = parsePlatformStaffIds(this.config.get<string>(PLATFORM_STAFF_ENV));
    if (!staff.has(user.id.trim().toLowerCase())) {
      throw new ForbiddenException("PLATFORM_STAFF_REQUIRED");
    }
    return true;
  }
}
