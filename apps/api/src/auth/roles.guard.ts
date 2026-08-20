import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { Reflector } from "@nestjs/core";
import { PERMISSIONS_KEY, ROLES_KEY } from "./roles.decorator";
import { CompanyMemberStatus, Role } from "@prisma/client";
import jwt from "jsonwebtoken";
import { normalizeJwtSecret } from "./jwt.util";
import { PrismaService } from "../prisma/prisma.service";

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly config: ConfigService,
    private readonly prisma: PrismaService,
  ) {}

  private readonly roleAliases: Record<string, Role> = {
    ADMINISTRADOR: Role.ADMIN,
    CASHIER: Role.CAJERO,
    ASSISTANT: Role.ASISTENTE,
    ASSISTENTE: Role.ASISTENTE,
  };

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const requiredRoles = this.reflector.getAllAndOverride<Role[]>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    const requiredPermissions = this.reflector.getAllAndOverride<string[]>(
      PERMISSIONS_KEY,
      [context.getHandler(), context.getClass()],
    );
    const request = context.switchToHttp().getRequest();
    const user = request.user as
      | {
          id?: string;
          role?: Role | string;
          companyId?: string | null;
          adminAuthorized?: boolean;
          authorizedPermissions?: string[];
        }
      | undefined;
    const adminAuthorized = this.hasValidAdminAuthorization(request, user);
    if (adminAuthorized) {
      this.markAdminAuthorization(request, user);
    }

    if (
      (!requiredRoles || requiredRoles.length === 0) &&
      (!requiredPermissions || requiredPermissions.length === 0)
    ) {
      return true;
    }

    const role = this.normalizeRole(user?.role);
    if (!role) {
      throw new ForbiddenException("Missing role");
    }
    if (role === Role.ADMIN) {
      return true;
    }
    if (adminAuthorized) {
      return true;
    }
    if (requiredPermissions?.length) {
      const granted = await this.hasAnyUserPermission(user, requiredPermissions);
      if (granted) {
        this.markPermissionAuthorization(user, requiredPermissions);
        return true;
      }
    }
    if (!requiredRoles || requiredRoles.length === 0) {
      throw new ForbiddenException("No tienes permiso para esta acción.");
    }
    if (
      !requiredRoles.some(
        (requiredRole) => this.normalizeRole(requiredRole) === role,
      )
    ) {
      throw new ForbiddenException("No tienes permiso para esta acción.");
    }
    return true;
  }

  private normalizeRole(role?: Role | string | null): Role | null {
    const normalized = `${role ?? ""}`.trim().toUpperCase();
    if (!normalized) return null;
    if (normalized in this.roleAliases) {
      return this.roleAliases[normalized];
    }
    return normalized as Role;
  }

  private async hasAnyUserPermission(
    user: { id?: string; companyId?: string | null } | undefined,
    permissions: string[],
  ) {
    if (!user?.id || !user.companyId) return false;
    const requested = permissions
      .map((permission) => permission.trim())
      .filter((permission) => permission.length > 0);
    if (requested.length === 0) return false;

    const row = await this.prisma.user.findFirst({
      where: {
        id: user.id,
        OR: [
          { companyId: user.companyId },
          {
            companyMemberships: {
              some: {
                companyId: user.companyId,
                status: CompanyMemberStatus.ACTIVE,
              },
            },
          },
        ],
      },
      select: { userPermissions: true },
    });

    const map = this.normalizeBooleanMap(row?.userPermissions);
    return requested.some((permission) => map[permission] === true);
  }

  private normalizeBooleanMap(value: unknown) {
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      return {} as Record<string, boolean>;
    }

    const output: Record<string, boolean> = {};
    for (const [rawKey, rawValue] of Object.entries(
      value as Record<string, unknown>,
    )) {
      const key = rawKey.trim();
      if (!key) continue;
      if (typeof rawValue === "boolean") {
        output[key] = rawValue;
      }
    }
    return output;
  }

  private hasValidAdminAuthorization(
    request: { headers?: Record<string, unknown> },
    user?: { id?: string; companyId?: string | null },
  ) {
    const raw = request.headers?.["x-admin-authorization"];
    const token = Array.isArray(raw) ? raw[0] : raw;
    if (!user?.id || !user.companyId || typeof token !== "string" || !token) {
      return false;
    }
    try {
      const secret =
        normalizeJwtSecret(this.config.get<string>("JWT_SECRET")) ??
        "change-me";
      const payload = jwt.verify(token, secret) as {
        sub?: string;
        companyId?: string;
        tokenType?: string;
      };
      return (
        payload.tokenType === "admin-authorization" &&
        payload.sub === user.id &&
        payload.companyId === user.companyId
      );
    } catch {
      return false;
    }
  }

  private markAdminAuthorization(
    request: Record<string, unknown>,
    user?: { adminAuthorized?: boolean },
  ) {
    if (user) user.adminAuthorized = true;
    request.adminAuthorized = true;
  }

  private markPermissionAuthorization(
    user:
      | { authorizedPermissions?: string[] }
      | undefined,
    permissions: string[],
  ) {
    if (!user) return;
    const current = new Set(user.authorizedPermissions ?? []);
    for (const permission of permissions) {
      const clean = permission.trim();
      if (clean) current.add(clean);
    }
    user.authorizedPermissions = [...current];
  }
}
