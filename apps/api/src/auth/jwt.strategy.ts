import { Injectable, UnauthorizedException } from "@nestjs/common";
import { PassportStrategy } from "@nestjs/passport";
import { ConfigService } from "@nestjs/config";
import { ExtractJwt, Strategy } from "passport-jwt";
import { PrismaService } from "../prisma/prisma.service";
import { JwtUser } from "./jwt-user.type";
import {
  CompanyMemberRole,
  CompanyMemberStatus,
  Prisma,
  Role,
} from "@prisma/client";
import { normalizeJwtSecret } from "./jwt.util";
import { LicenseService } from "../license/license.service";

type JwtLookupUser = {
  id: string;
  email: string;
  role: Role | string;
  blocked: boolean;
  companyId: string | null;
  userPermissions?: unknown;
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
    private readonly prisma: PrismaService,
    private readonly licenses: LicenseService,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey:
        normalizeJwtSecret(config.get<string>("JWT_SECRET")) ?? "change-me",
    });
  }

  async validate(payload: JwtUser) {
    // Bloquea tokens de refresh usados como Bearer token
    if (payload.tokenType === "refresh") {
      throw new UnauthorizedException("Invalid token");
    }
    const user = await this.findUserForJwt(payload.sub);
    if (!user || user.blocked === true) {
      throw new UnauthorizedException({
        code: "USER_BLOCKED",
        message: "User blocked",
      });
    }
    const sessionCompanyId = await this.assertActiveSession(payload);
    const membership = this.resolveActiveMembership(user, payload.companyId);
    const companyId =
      membership?.companyId ??
      payload.companyId ??
      sessionCompanyId ??
      user.companyId ??
      null;
    const licenseAccess = await this.licenses.getLicenseAccess(companyId);
    const role = membership
      ? this.mapMemberRoleToLegacyRole(membership.role)
      : this.normalizeLegacyRole(user.role);
    return {
      id: user.id,
      email: user.email,
      role,
      memberRole: membership?.role ?? null,
      companyId,
      sessionId: payload.sessionId ?? null,
      userPermissions: user.userPermissions ?? {},
      /** FULL | RESTRICTED | BLOCKED. Lo usa el interceptor de acceso. */
      licenseAccess: {
        level: licenseAccess.level,
        reason: licenseAccess.reason,
        daysRemaining: licenseAccess.daysRemaining,
        periodEndsAt: licenseAccess.periodEndsAt,
      },
    };
  }

  private async assertActiveSession(payload: JwtUser) {
    const sessionId = (payload.sessionId ?? "").trim();
    if (!sessionId) {
      throw new UnauthorizedException("Invalid session");
    }

    const session = await this.prisma.authSession.findFirst({
      where: {
        id: sessionId,
        userId: payload.sub,
        revokedAt: null,
        expiresAt: { gt: new Date() },
      },
      select: {
        id: true,
        company: {
          select: {
            id: true,
            status: true,
            licenseStatus: true,
            trialEndsAt: true,
            licenseExpiresAt: true,
          },
        },
      },
    });
    if (!session) throw new UnauthorizedException("Invalid session");
    // Una licencia vencida **o una cuenta suspendida** no se rechazan aqui: el
    // cliente entra y `LicenseAccessInterceptor` limita las rutas con el nivel
    // que calcula `resolveLicenseAccess`. Si se devolviera 401, la app no podria
    // ni pintar la pantalla de cuenta suspendida ni dejar pagar desde ella.
    // Lo que si importa es que la sesion siga viva (arriba) y que el usuario no
    // este bloqueado (abajo).
    return session.company?.id ?? null;
  }

  private mapMemberRoleToLegacyRole(
    role?: CompanyMemberRole | string | null,
  ): Role {
    switch (`${role ?? ""}`.toUpperCase()) {
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

  private normalizeLegacyRole(role: Role | string): Role {
    return Object.values(Role).includes(role as Role)
      ? (role as Role)
      : Role.CAJERO;
  }

  private resolveActiveMembership(
    user: JwtLookupUser | null,
    requestedCompanyId?: string | null,
  ) {
    const memberships = user?.companyMemberships ?? [];
    if (!memberships.length) return null;
    return (
      memberships.find(
        (membership) => membership.companyId === requestedCompanyId,
      ) ??
      memberships.find(
        (membership) => membership.companyId === user?.companyId,
      ) ??
      memberships[0]
    );
  }

  private isMissingUserTable(error: unknown) {
    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      return error.code === "P2021";
    }

    if (typeof error === "object" && error !== null) {
      const value = error as { code?: unknown; message?: unknown };
      const code = typeof value.code === "string" ? value.code : "";
      const message = typeof value.message === "string" ? value.message : "";
      return (
        code === "P2021" ||
        message.includes("does not exist in the current database")
      );
    }

    return false;
  }

  private isMissingBlockedColumn(error: unknown) {
    if (error instanceof Prisma.PrismaClientKnownRequestError) {
      return error.code === "P2022" && error.meta?.column_name === "blocked";
    }

    if (typeof error === "object" && error !== null) {
      const value = error as { code?: unknown; message?: unknown };
      const code = typeof value.code === "string" ? value.code : "";
      const message = typeof value.message === "string" ? value.message : "";
      return (
        code === "P2022" &&
        (message.includes("blocked") ||
          (message.toLowerCase().includes("column") &&
            message.toLowerCase().includes("blocked")))
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
          userPermissions: true,
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
            userPermissions: true,
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
        Array<{
          id: string;
          email: string;
          role: string;
          companyId: string | null;
        }>
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
        userPermissions: {},
        blocked: false,
      };
    }
  }
}
