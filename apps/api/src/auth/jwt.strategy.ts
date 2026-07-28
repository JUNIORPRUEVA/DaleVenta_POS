import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ConfigService } from '@nestjs/config';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { PrismaService } from '../prisma/prisma.service';
import { JwtUser } from './jwt-user.type';
import { CompanyMemberRole, CompanyMemberStatus, Prisma, Role } from '@prisma/client';
import { normalizeJwtSecret } from './jwt.util';

type JwtLookupUser = {
  id: string;
  email: string;
  role: Role | string;
  blocked: boolean;
  companyId: string | null;
  companyMemberships?: Array<{
    id: string;
    companyId: string;
    role: CompanyMemberRole;
    status: CompanyMemberStatus;
  }>;
};

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(
    private readonly config: ConfigService,
    private readonly prisma: PrismaService
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: normalizeJwtSecret(config.get<string>('JWT_SECRET')) ?? 'change-me'
    });
  }

  async validate(payload: JwtUser) {
    // Bloquea tokens de refresh usados como Bearer token
    if (payload.tokenType === 'refresh') {
      throw new UnauthorizedException('Invalid token');
    }
    const user = await this.findUserForJwt(payload.sub);
    if (!user || user.blocked === true) throw new UnauthorizedException('User blocked');
    const membership = this.resolveActiveMembership(user, payload.companyId);
    const companyId = membership?.companyId ?? user.companyId ?? null;
    const role = membership ? this.mapMemberRoleToLegacyRole(membership.role) : user.role;
    return { id: user.id, email: user.email, role, memberRole: membership?.role ?? null, companyId };
  }

  private mapMemberRoleToLegacyRole(role?: CompanyMemberRole | string | null): Role {
    switch (`${role ?? ''}`.toUpperCase()) {
      case CompanyMemberRole.OWNER:
      case CompanyMemberRole.ADMIN:
      case CompanyMemberRole.MANAGER:
      case CompanyMemberRole.ACCOUNTANT:
      case CompanyMemberRole.WAREHOUSE:
        return Role.ADMIN;
      case CompanyMemberRole.CASHIER:
        return Role.CAJERO;
      case CompanyMemberRole.SELLER:
        return Role.VENDEDOR;
      default:
        return Role.CAJERO;
    }
  }

  private resolveActiveMembership(
    user: JwtLookupUser | null,
    requestedCompanyId?: string | null,
  ) {
    const memberships = user?.companyMemberships ?? [];
    if (!memberships.length) return null;
    return (
      memberships.find((membership) => membership.companyId === requestedCompanyId) ??
      memberships.find((membership) => membership.companyId === user?.companyId) ??
      memberships[0]
    );
  }

  private isMissingUserTable(error: unknown) {
    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      return error.code === 'P2021';
    }

    if (typeof error === 'object' && error !== null) {
      const value = error as { code?: unknown; message?: unknown };
      const code = typeof value.code === 'string' ? value.code : '';
      const message = typeof value.message === 'string' ? value.message : '';
      return code === 'P2021' || message.includes('does not exist in the current database');
    }

    return false;
  }

  private isMissingBlockedColumn(error: unknown) {
    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      return error.code === 'P2022' && error.meta?.column_name === 'blocked';
    }

    if (typeof error === 'object' && error !== null) {
      const value = error as { code?: unknown; message?: unknown };
      const code = typeof value.code === 'string' ? value.code : '';
      const message = typeof value.message === 'string' ? value.message : '';
      return (
        code === 'P2022' &&
        (message.includes('blocked') ||
          message.toLowerCase().includes('column') && message.toLowerCase().includes('blocked'))
      );
    }

    return false;
  }

  private async findUserForJwt(userId: string) {
    try {
      return await this.prisma.user.findUnique({
        where: { id: userId },
        select: {
          id: true,
          email: true,
          role: true,
          blocked: true,
          companyId: true,
          companyMemberships: {
            where: { status: CompanyMemberStatus.ACTIVE },
            select: { id: true, companyId: true, role: true, status: true },
          },
        },
      });
    } catch (error) {
      if (this.isMissingBlockedColumn(error)) {
        const row = await this.prisma.user.findUnique({
          where: { id: userId },
          select: {
            id: true,
            email: true,
            role: true,
            companyId: true,
            companyMemberships: {
              where: { status: CompanyMemberStatus.ACTIVE },
              select: { id: true, companyId: true, role: true, status: true },
            },
          },
        });
        if (!row) return null;
        return { ...row, blocked: false };
      }

      if (!this.isMissingUserTable(error)) throw error;

      const rows = await this.prisma.$queryRaw<
        Array<{ id: string; email: string; role: string; companyId: string | null }>
      >(Prisma.sql`
        SELECT id, email, role, NULL AS "companyId"
        FROM users
        WHERE id::text = ${userId}
        LIMIT 1
      `);

      const row = rows[0];
      if (!row) return null;
      return {
        id: row.id,
        email: row.email,
        role: row.role,
        companyId: row.companyId,
        blocked: false,
      };
    }
  }
}
