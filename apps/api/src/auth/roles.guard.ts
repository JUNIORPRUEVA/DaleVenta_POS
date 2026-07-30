import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Reflector } from '@nestjs/core';
import { ROLES_KEY } from './roles.decorator';
import { Role } from '@prisma/client';
import jwt from 'jsonwebtoken';
import { normalizeJwtSecret } from './jwt.util';

@Injectable()
export class RolesGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly config: ConfigService,
  ) {}

  private readonly roleAliases: Record<string, Role> = {
    ADMINISTRADOR: Role.ADMIN,
    CASHIER: Role.CAJERO,
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
    const user = request.user as
      | { id?: string; role?: Role | string; companyId?: string | null }
      | undefined;
    const role = this.normalizeRole(user?.role);
    if (!role) {
      throw new ForbiddenException('Missing role');
    }
    if (role === Role.ADMIN) {
      return true;
    }
    if (this.hasValidAdminAuthorization(request, user)) {
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

  private hasValidAdminAuthorization(
    request: { headers?: Record<string, unknown> },
    user?: { id?: string; companyId?: string | null },
  ) {
    const raw = request.headers?.['x-admin-authorization'];
    const token = Array.isArray(raw) ? raw[0] : raw;
    if (!user?.id || !user.companyId || typeof token !== 'string' || !token) {
      return false;
    }
    try {
      const secret = normalizeJwtSecret(this.config.get<string>('JWT_SECRET')) ?? 'change-me';
      const payload = jwt.verify(token, secret) as {
        sub?: string;
        companyId?: string;
        tokenType?: string;
      };
      return (
        payload.tokenType === 'admin-authorization' &&
        payload.sub === user.id &&
        payload.companyId === user.companyId
      );
    } catch {
      return false;
    }
  }
}
