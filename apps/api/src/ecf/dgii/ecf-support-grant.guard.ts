import {
  CanActivate,
  ExecutionContext,
  Injectable,
} from "@nestjs/common";
import type { Request } from "express";
import { EcfSupportGrantService } from "./ecf-support-grant.service";
import type { EcfSupportScope } from "./ecf-support-grant.policy";

/**
 * Autorización de ASISTENCIA sobre el expediente de una empresa.
 *
 * Se ejecuta DESPUÉS de `PlatformStaffGuard`: ser staff no basta. Este guard
 * exige además una concesión vigente de la empresa dueña del expediente.
 *
 * Alcance por ruta (deliberadamente explícito, no por defecto):
 *  - lecturas del expediente y sus requisitos      → VIEW_DOSSIER
 *  - revisión de requisitos, evidencia y descargas → REVIEW_EVIDENCE
 *  - mutaciones del expediente                     → REQUEST_CORRECTION
 *
 * Las rutas sin `companyId` (`me`, bandeja agregada) no pasan por aquí: no
 * exponen el contenido de un expediente concreto.
 *
 * Nota fiscal: esta concesión NO autoriza fabricar evidencia oficial. Las
 * reglas de transición y de registro oficial siguen aplicándose después.
 */
@Injectable()
export class EcfSupportGrantGuard implements CanActivate {
  constructor(private readonly grants: EcfSupportGrantService) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const request = context.switchToHttp().getRequest<Request>();
    const raw = (request.params as Record<string, unknown> | undefined)
      ?.companyId;
    const companyId = typeof raw === "string" ? raw.trim() : "";
    if (!companyId) return true;

    const scope = this.scopeFor(request);
    const actor = (request.user as { id?: string } | undefined)?.id ?? null;
    await this.grants.assertStaffAccess(companyId, scope, actor);
    return true;
  }

  private scopeFor(request: Request): EcfSupportScope {
    const route = `${(request.route as { path?: string } | undefined)?.path ?? request.path ?? ""}`;
    const isEvidenceRoute = /\/evidence\/|\/documents\//.test(route);
    const isRequirementRoute = /\/requirements\//.test(route);

    if (request.method === "GET") {
      // Una descarga de documento es evidencia: no basta con ver el expediente.
      return isEvidenceRoute ? "REVIEW_EVIDENCE" : "VIEW_DOSSIER";
    }
    if (isEvidenceRoute || isRequirementRoute) return "REVIEW_EVIDENCE";
    return "REQUEST_CORRECTION";
  }
}
