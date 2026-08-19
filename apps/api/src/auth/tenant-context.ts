import { ForbiddenException, UnauthorizedException } from '@nestjs/common';
import { Role } from '@prisma/client';

export type TenantUser = {
  id: string;
  role: Role | string;
  companyId?: string | null;
  adminAuthorized?: boolean;
  authorizedScopes?: string[];
  authorizedPermissions?: string[];
};

export function requireTenant(user: TenantUser | null | undefined): string {
  if (!user?.id) {
    throw new UnauthorizedException('Usuario no autenticado');
  }

  const companyId = user.companyId?.trim();
  if (!companyId) {
    throw new ForbiddenException('Usuario sin empresa asignada');
  }

  return companyId;
}

export function isAdminLike(user: TenantUser) {
  return user.role === Role.ADMIN || user.role === Role.ASISTENTE;
}

export function hasDelegatedScope(
  user: TenantUser,
  ...requiredScopes: string[]
) {
  const granted = new Set(
    (user.authorizedScopes ?? [])
      .map((scope) => scope.trim())
      .filter(Boolean),
  );
  return requiredScopes.some((scope) => granted.has(scope));
}

export function isAdminLikeForScope(
  user: TenantUser,
  ...requiredScopes: string[]
) {
  return isAdminLike(user) || hasDelegatedScope(user, ...requiredScopes);
}
