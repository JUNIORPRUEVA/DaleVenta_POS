import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { ROLES_KEY } from './roles.decorator';
import { Role } from '@prisma/client';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private readonly reflector: Reflector) {}

  private readonly roleAliases: Record<string, Role> = {
    ADMINISTRADOR: Role.ADMIN,
    ASSISTANT: Role.ASISTENTE,
    ASSISTENTE: Role.ASISTENTE,
  };

  canActivate(context: ExecutionContext): boolean {
    const requiredRoles = this.reflector.getAllAndOverride<Role[]>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (!requiredRoles || requiredRoles.length === 0) {
      return true;
    }

    const request = context.switchToHttp().getRequest();
    const user = request.user as { role?: Role | string } | undefined;
    const role = this.normalizeRole(user?.role);
    if (!role) {
      throw new ForbiddenException('Missing role');
    }
    if (role === Role.ADMIN) {
      return true;
    }
    if (!requiredRoles.some((requiredRole) => this.normalizeRole(requiredRole) === role)) {
      throw new ForbiddenException('No tienes permisos para usar este endpoint.');
    }
    return true;
  }

  private normalizeRole(role?: Role | string | null): Role | null {
    const normalized = `${role ?? ''}`.trim().toUpperCase();
    if (!normalized) return null;
    if (normalized in this.roleAliases) {
      return this.roleAliases[normalized];
    }
    return normalized as Role;
  }
}
