import {
  BadRequestException,
  ConflictException,
  Injectable,
  UnauthorizedException,
} from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";
import { PrismaService } from "../prisma/prisma.service";
import {
  CompanyMemberRole,
  CompanyMemberStatus,
  Prisma,
  Role,
} from "@prisma/client";
import * as bcrypt from "bcryptjs";
import { ConfigService } from "@nestjs/config";
import { JwtUser } from "./jwt-user.type";

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
  ) {}

  async login(identifier: string, password: string) {
    const normalizedIdentifier = identifier.trim().toLowerCase();
    const user = await this.findUserForLogin(normalizedIdentifier);
    if (!user) throw new UnauthorizedException("Invalid credentials");
    if (user.blocked === true) throw new UnauthorizedException("User blocked");

    const ok = await bcrypt.compare(password, user.passwordHash);
    if (!ok) throw new UnauthorizedException("Invalid credentials");

    const session = this.resolveCompanySession(user);
    const accessToken = await this.jwt.signAsync({
      sub: user.id,
      companyId: session.activeCompany?.id ?? user.companyId,
      email: user.email,
      role: session.legacyRole,
      memberRole: session.activeMembership?.role ?? null,
      tokenType: "access",
    });

    const refreshToken = await this.signRefreshToken(user.id);

    return {
      accessToken,
      refreshToken,
      user: this.toAuthUser(user, session),
      companies: session.companies,
      activeCompany: session.activeCompany,
      activeMembership: session.activeMembership,
      requiresCompanyCreation: session.companies.length === 0,
      requiresCompanySelection:
        session.companies.length > 1 && !session.activeCompany,
      requiresOnboarding: session.activeCompany?.onboardingCompleted === false,
    };
  }

  async refresh(refreshToken: string) {
    let payload: JwtUser;

    try {
      payload = await this.jwt.verifyAsync<JwtUser>(refreshToken);
    } catch {
      throw new UnauthorizedException("Invalid refresh token");
    }

    if (payload.tokenType !== "refresh") {
      throw new UnauthorizedException("Invalid refresh token");
    }

    const user = await this.findUserForRefresh(payload.sub);
    if (!user || user.blocked === true)
      throw new UnauthorizedException("User blocked");

    const session = this.resolveCompanySession(user);
    const accessToken = await this.jwt.signAsync({
      sub: user.id,
      companyId: session.activeCompany?.id ?? user.companyId,
      email: user.email,
      role: session.legacyRole,
      memberRole: session.activeMembership?.role ?? null,
      tokenType: "access",
    });

    const newRefreshToken = await this.signRefreshToken(user.id);

    return {
      accessToken,
      refreshToken: newRefreshToken,
      user: this.toAuthUser(user, session),
      companies: session.companies,
      activeCompany: session.activeCompany,
      activeMembership: session.activeMembership,
      requiresCompanyCreation: session.companies.length === 0,
      requiresCompanySelection:
        session.companies.length > 1 && !session.activeCompany,
      requiresOnboarding: session.activeCompany?.onboardingCompleted === false,
    };
  }

  async me(userId: string) {
    const user = await this.findUserForMe(userId);
    if (!user) throw new UnauthorizedException("No autorizado");
    return user;
  }

  async registerBusiness(dto: {
    firstName?: string;
    lastName?: string;
    email?: string;
    phone?: string;
    password?: string;
    confirmPassword?: string;
    commercialName?: string;
    legalName?: string;
    taxId?: string;
    businessPhone?: string;
    businessEmail?: string;
    country?: string;
    province?: string;
    city?: string;
    address?: string;
    currency?: string;
    timezone?: string;
    locale?: string;
    businessType?: string;
  }) {
    const email = (dto.email ?? "").trim().toLowerCase();
    const password = dto.password ?? "";
    const confirmPassword = dto.confirmPassword ?? "";
    const firstName = (dto.firstName ?? "").trim();
    const lastName = (dto.lastName ?? "").trim();
    const phone = (dto.phone ?? "").trim();
    const commercialName = (dto.commercialName ?? "").trim();

    if (!firstName) throw new BadRequestException("El nombre es obligatorio");
    if (!email || !email.includes("@"))
      throw new BadRequestException("Correo invalido");
    if (!phone) throw new BadRequestException("El telefono es obligatorio");
    if (password.length < 8)
      throw new BadRequestException(
        "La contrasena debe tener al menos 8 caracteres",
      );
    if (password !== confirmPassword)
      throw new BadRequestException("Las contrasenas no coinciden");
    if (!commercialName)
      throw new BadRequestException("El nombre comercial es obligatorio");

    const existingUser = await this.prisma.user.findUnique({
      where: { email },
      select: { id: true },
    });
    if (existingUser)
      throw new ConflictException("Ya existe una cuenta con este correo");

    const baseSlug = this.slugify(commercialName);
    const passwordHash = await bcrypt.hash(password, 10);
    const fullName = `${firstName} ${lastName}`.trim();
    await this.prisma.$transaction(async (tx) => {
      const company = await tx.company.create({
        data: {
          name: commercialName,
          slug: await this.nextCompanySlug(tx, baseSlug),
          status: "ACTIVE",
          plan: "STANDARD",
          maxUsers: 1000,
        },
      });

      const user = await tx.user.create({
        data: {
          companyId: company.id,
          email,
          passwordHash,
          nombreCompleto: fullName,
          telefono: phone,
          edad: 0,
          role: Role.ADMIN,
          blocked: false,
          tieneHijos: false,
          estaCasado: false,
          casaPropia: false,
          vehiculo: false,
          licenciaConducir: false,
        },
      });

      await tx.companyMember.create({
        data: {
          userId: user.id,
          companyId: company.id,
          role: CompanyMemberRole.OWNER,
          status: CompanyMemberStatus.ACTIVE,
          joinedAt: new Date(),
        },
      });

      await tx.appConfig.create({
        data: {
          id: `company_${company.id}`,
          companyId: company.id,
          companyName: commercialName,
          rnc: (dto.taxId ?? "").trim(),
          phone: (dto.businessPhone ?? phone).trim(),
          address: [dto.address, dto.city, dto.province, dto.country]
            .map((value) => (value ?? "").trim())
            .filter(Boolean)
            .join(", "),
          description: (dto.businessType ?? "").trim(),
          websiteUrl: "",
          businessHours: "",
        },
      });

      return { company, user };
    });

    return this.login(email, password);
  }

  private refreshExpiresIn() {
    return this.config.get<string>("JWT_REFRESH_EXPIRES_IN") ?? "30d";
  }

  private async signRefreshToken(userId: string) {
    return this.jwt.signAsync(
      { sub: userId, tokenType: "refresh" },
      { expiresIn: this.refreshExpiresIn() },
    );
  }

  private slugify(value: string) {
    const slug = value
      .normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 48);
    return slug || `empresa-${Date.now()}`;
  }

  private async nextCompanySlug(
    tx: Prisma.TransactionClient,
    baseSlug: string,
  ) {
    let candidate = baseSlug;
    for (let i = 2; i < 1000; i += 1) {
      const existing = await tx.company.findUnique({
        where: { slug: candidate },
        select: { id: true },
      });
      if (!existing) return candidate;
      candidate = `${baseSlug}-${i}`;
    }
    return `${baseSlug}-${Date.now()}`;
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

  private resolveCompanySession(user: {
    id: string;
    role: Role | string;
    companyId?: string | null;
    company?: { id: string; name: string; slug: string } | null;
    companyMemberships?: Array<{
      id: string;
      role: CompanyMemberRole;
      status: CompanyMemberStatus;
      company: {
        id: string;
        name: string;
        slug: string;
        status: string;
        plan: string;
        maxUsers: number;
      };
    }>;
  }) {
    const memberships = (user.companyMemberships ?? []).filter(
      (membership) => membership.status === CompanyMemberStatus.ACTIVE,
    );
    const activeMembership =
      memberships.find(
        (membership) => membership.company.id === user.companyId,
      ) ??
      memberships[0] ??
      null;
    const activeCompany = activeMembership
      ? {
          id: activeMembership.company.id,
          name: activeMembership.company.name,
          slug: activeMembership.company.slug,
          status: activeMembership.company.status,
          plan: activeMembership.company.plan,
          onboardingCompleted: true,
        }
      : user.company
        ? {
            id: user.company.id,
            name: user.company.name,
            slug: user.company.slug,
            status: "ACTIVE",
            plan: "STANDARD",
            onboardingCompleted: true,
          }
        : null;
    const companies = memberships.map((membership) => ({
      id: membership.company.id,
      name: membership.company.name,
      slug: membership.company.slug,
      role: membership.role,
      status: membership.status,
      logoUrl: null,
      onboardingCompleted: true,
    }));

    return {
      companies,
      activeCompany,
      activeMembership: activeMembership
        ? {
            id: activeMembership.id,
            role: activeMembership.role,
            status: activeMembership.status,
            companyId: activeMembership.company.id,
          }
        : null,
      legacyRole: activeMembership
        ? this.mapMemberRoleToLegacyRole(activeMembership.role)
        : (user.role as Role),
    };
  }

  private toAuthUser(
    user: {
      id: string;
      email: string;
      role: Role | string;
      companyId?: string | null;
      company?: { id: string; name: string; slug: string } | null;
    },
    session = this.resolveCompanySession(user),
  ) {
    return {
      id: user.id,
      email: user.email,
      role: session.legacyRole,
      companyRole: session.activeMembership?.role ?? null,
      companyId: session.activeCompany?.id ?? user.companyId ?? null,
      company: session.activeCompany,
    };
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

  private async findUserForLogin(email: string) {
    try {
      return await this.prisma.user.findUnique({
        where: { email },
        select: {
          id: true,
          email: true,
          passwordHash: true,
          role: true,
          blocked: true,
          companyId: true,
          company: {
            select: { id: true, name: true, slug: true },
          },
          companyMemberships: {
            where: { status: CompanyMemberStatus.ACTIVE },
            include: {
              company: {
                select: {
                  id: true,
                  name: true,
                  slug: true,
                  status: true,
                  plan: true,
                  maxUsers: true,
                },
              },
            },
            orderBy: { joinedAt: "asc" },
          },
        },
      });
    } catch (error) {
      if (this.isMissingBlockedColumn(error)) {
        const row = await this.prisma.user.findUnique({
          where: { email },
          select: {
            id: true,
            email: true,
            passwordHash: true,
            role: true,
            companyId: true,
          },
        });
        if (!row) return null;
        return {
          ...row,
          blocked: false,
        };
      }

      if (!this.isMissingUserTable(error)) throw error;

      const rows = await this.prisma.$queryRaw<
        Array<{
          id: string;
          email: string;
          passwordHash: string;
          role: string;
          blocked: boolean | null;
          companyId: string | null;
        }>
      >(Prisma.sql`
        SELECT id, email, "passwordHash", role, COALESCE(blocked, false) AS blocked, NULL AS "companyId"
        FROM users
        WHERE email = ${email}
        LIMIT 1
      `);

      const row = rows[0];
      if (!row) return null;
      return {
        id: row.id,
        email: row.email,
        passwordHash: row.passwordHash,
        role: row.role,
        blocked: row.blocked ?? false,
        companyId: row.companyId,
        company: null,
      };
    }
  }

  private async findUserForMe(userId: string) {
    try {
      return await this.prisma.user.findUnique({
        where: { id: userId },
        select: {
          id: true,
          email: true,
          role: true,
          companyId: true,
          company: {
            select: { id: true, name: true, slug: true },
          },
          companyMemberships: {
            where: { status: CompanyMemberStatus.ACTIVE },
            include: {
              company: {
                select: {
                  id: true,
                  name: true,
                  slug: true,
                  status: true,
                  plan: true,
                  maxUsers: true,
                },
              },
            },
            orderBy: { joinedAt: "asc" },
          },
        },
      });
    } catch (error) {
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
        company: null,
      };
    }
  }

  private async findUserForRefresh(userId: string) {
    try {
      return await this.prisma.user.findUnique({
        where: { id: userId },
        select: {
          id: true,
          email: true,
          role: true,
          blocked: true,
          companyId: true,
          company: {
            select: { id: true, name: true, slug: true },
          },
          companyMemberships: {
            where: { status: CompanyMemberStatus.ACTIVE },
            include: {
              company: {
                select: {
                  id: true,
                  name: true,
                  slug: true,
                  status: true,
                  plan: true,
                  maxUsers: true,
                },
              },
            },
            orderBy: { joinedAt: "asc" },
          },
        },
      });
    } catch (error) {
      if (this.isMissingBlockedColumn(error)) {
        const row = await this.prisma.user.findUnique({
          where: { id: userId },
          select: { id: true, email: true, role: true, companyId: true },
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
        role: row.role as any,
        companyId: row.companyId,
        company: null,
        blocked: false,
      };
    }
  }
}
