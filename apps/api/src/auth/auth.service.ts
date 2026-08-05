import {
  BadRequestException,
  ConflictException,
  Injectable,
  UnauthorizedException,
} from "@nestjs/common";
import { JwtService } from "@nestjs/jwt";
import { randomUUID, createHash } from "node:crypto";
import * as fs from "node:fs/promises";
import { resolve, join, relative, isAbsolute } from "node:path";
import { PrismaService } from "../prisma/prisma.service";
import { R2Service } from "../storage/r2.service";
import {
  CompanyMemberRole,
  CompanyMemberStatus,
  Prisma,
  Role,
} from "@prisma/client";
import * as bcrypt from "bcryptjs";
import { ConfigService } from "@nestjs/config";
import { JwtUser } from "./jwt-user.type";
import { LicenseService } from "../license/license.service";

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly r2: R2Service,
    private readonly licenses: LicenseService,
  ) {}

  async login(identifier: string, password: string) {
    const normalizedIdentifier = identifier.trim().toLowerCase();
    const user = await this.findUserForLogin(normalizedIdentifier);
    if (!user) throw new UnauthorizedException("Invalid credentials");
    if (user.blocked === true) throw new UnauthorizedException("User blocked");

    const ok = await bcrypt.compare(password, user.passwordHash);
    if (!ok) throw new UnauthorizedException("Invalid credentials");

    const session = this.resolveCompanySession(user);
    await this.licenses.assertCompanyCanUseApp(session.activeCompany?.id ?? user.companyId);
    const sessionRecord = await this.createAuthSession(user.id, session.activeCompany?.id ?? user.companyId ?? null);
    const accessToken = await this.jwt.signAsync({
      sub: user.id,
      companyId: session.activeCompany?.id ?? user.companyId,
      email: user.email,
      role: session.legacyRole,
      memberRole: session.activeMembership?.role ?? null,
      sessionId: sessionRecord.sessionId,
      tokenType: "access",
    });

    const refreshToken = await this.signRefreshToken(user.id, sessionRecord.sessionId);
    await this.storeRefreshHash(sessionRecord.sessionId, refreshToken);

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
    const sessionId = (payload.sessionId ?? "").trim();
    if (!sessionId) throw new UnauthorizedException("Invalid refresh token");
    const existingSession = await this.prisma.authSession.findFirst({
      where: {
        id: sessionId,
        userId: user.id,
        revokedAt: null,
        expiresAt: { gt: new Date() },
      },
      select: { id: true, refreshTokenHash: true, tokenFamily: true },
    });
    if (!existingSession) throw new UnauthorizedException("Invalid refresh token");
    if (existingSession.refreshTokenHash !== this.hashRefreshToken(refreshToken)) {
      await this.prisma.authSession.updateMany({
        where: { tokenFamily: existingSession.tokenFamily, revokedAt: null },
        data: { revokedAt: new Date(), revocationReason: "refresh_replay_detected" },
      });
      throw new UnauthorizedException("Invalid refresh token");
    }

    const session = this.resolveCompanySession(user);
    await this.licenses.assertCompanyCanUseApp(session.activeCompany?.id ?? user.companyId);
    const nextSessionRecord = await this.rotateAuthSession(existingSession.id);
    const accessToken = await this.jwt.signAsync({
      sub: user.id,
      companyId: session.activeCompany?.id ?? user.companyId,
      email: user.email,
      role: session.legacyRole,
      memberRole: session.activeMembership?.role ?? null,
      sessionId: nextSessionRecord.sessionId,
      tokenType: "access",
    });

    const newRefreshToken = await this.signRefreshToken(user.id, nextSessionRecord.sessionId);
    await this.storeRefreshHash(nextSessionRecord.sessionId, newRefreshToken);

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

  async deletionPreview(userId: string, activeCompanyId?: string | null) {
    const user = await this.findAccountDeletionUser(userId);
    if (!user) throw new UnauthorizedException("No autorizado");

    const memberships = user.companyMemberships.filter(
      (membership) => membership.status === CompanyMemberStatus.ACTIVE,
    );
    const activeMembership =
      memberships.find((membership) => membership.companyId === activeCompanyId) ??
      memberships.find((membership) => membership.companyId === user.companyId) ??
      memberships[0] ??
      null;

    if (!activeMembership) {
      return {
        mode: "personal_account",
        memberships: 0,
        activeCompanyId: null,
        activeCompanyRole: null,
        isOnlyOwner: false,
        companyWillBeDeleted: false,
        requiresCompanyConfirmationPhrase: false,
        blockingOwnedCompanies: 0,
        affectedDataCategories: ["personal profile", "sessions"],
      };
    }

    const ownerCount = await this.prisma.companyMember.count({
      where: {
        companyId: activeMembership.companyId,
        role: CompanyMemberRole.OWNER,
        status: CompanyMemberStatus.ACTIVE,
      },
    });
    const isOnlyOwner =
      activeMembership.role === CompanyMemberRole.OWNER && ownerCount <= 1;

    const blockingOwnedCompanies = await this.countSoleOwnedCompanies(user.id);

    return {
      mode: isOnlyOwner ? "company_and_personal_account" : "personal_account",
      memberships: memberships.length,
      activeCompanyId: activeMembership.companyId,
      activeCompanyRole: activeMembership.role,
      isOnlyOwner,
      companyWillBeDeleted: isOnlyOwner,
      requiresCompanyConfirmationPhrase: isOnlyOwner,
      blockingOwnedCompanies,
      affectedDataCategories: isOnlyOwner
        ? [
            "company settings",
            "products",
            "clients",
            "sales",
            "purchases",
            "cash",
            "payroll",
            "documents",
            "uploads metadata",
          ]
        : ["personal profile", "company memberships", "sessions"],
    };
  }

  async deleteAccount(
    userId: string,
    activeCompanyId: string | null | undefined,
    dto: {
      password?: unknown;
      confirmationPhrase?: unknown;
      idempotencyKey?: unknown;
    },
  ) {
    const password = typeof dto.password === "string" ? dto.password : "";
    if (!password) throw new BadRequestException("La contrasena es obligatoria");

    const user = await this.findAccountDeletionUser(userId);
    if (!user) throw new UnauthorizedException("No autorizado");

    const passwordOk = await bcrypt.compare(password, user.passwordHash);
    if (!passwordOk) throw new UnauthorizedException("Credenciales invalidas");

    const memberships = user.companyMemberships.filter(
      (membership) => membership.status === CompanyMemberStatus.ACTIVE,
    );
    const activeMembership =
      memberships.find((membership) => membership.companyId === activeCompanyId) ??
      memberships.find((membership) => membership.companyId === user.companyId) ??
      memberships[0] ??
      null;

    const soleOwnedCompanyIds = await this.findSoleOwnedCompanyIds(user.id);
    const activeCompanyIsSoleOwned =
      !!activeMembership &&
      soleOwnedCompanyIds.includes(activeMembership.companyId);

    if (soleOwnedCompanyIds.length > (activeCompanyIsSoleOwned ? 1 : 0)) {
      throw new ConflictException(
        "Transfiere o elimina primero las otras empresas donde eres el unico propietario",
      );
    }

    if (activeCompanyIsSoleOwned) {
      const phrase =
        typeof dto.confirmationPhrase === "string"
          ? dto.confirmationPhrase.trim()
          : "";
      if (phrase !== "DELETE MY COMPANY") {
        throw new BadRequestException(
          "Debes confirmar escribiendo DELETE MY COMPANY",
        );
      }
    }

    const deletionReceiptId = `del_${Date.now()}_${Math.random()
      .toString(36)
      .slice(2, 10)}`;

    await this.prisma.$transaction(async (tx) => {
      if (activeCompanyIsSoleOwned && activeMembership) {
        await this.cleanupCompanyStorage(activeMembership.companyId);
        await this.deleteCompanyOwnedRows(tx, activeMembership.companyId);
        await tx.authSession.updateMany({
          where: { companyId: activeMembership.companyId, revokedAt: null },
          data: { revokedAt: new Date(), revocationReason: "company_deleted" },
        });
        await tx.companyMember.deleteMany({
          where: { companyId: activeMembership.companyId },
        });
        await tx.company.delete({ where: { id: activeMembership.companyId } });
      }

      await tx.companyMember.updateMany({
        where: { userId: user.id },
        data: { status: CompanyMemberStatus.REMOVED },
      });

      await tx.authSession.updateMany({
        where: { userId: user.id, revokedAt: null },
        data: { revokedAt: new Date(), revocationReason: "account_deleted" },
      });

      await tx.user.update({
        where: { id: user.id },
        data: {
          blocked: true,
          companyId: null,
          email: `deleted-${user.id}@deleted.local`,
          nombreCompleto: "Usuario eliminado",
          telefono: "eliminado",
          numeroFlota: null,
          telefonoFamiliar: null,
          cedula: null,
          fotoCedulaUrl: null,
          fotoLicenciaUrl: null,
          fotoPersonalUrl: null,
          workContractSignatureUrl: null,
          userPermissions: Prisma.DbNull,
        },
      });
    });

    return {
      ok: true,
      deletionReceiptId,
      companyDeleted: activeCompanyIsSoleOwned,
    };
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
          licenseStatus: "TRIAL",
          trialStartedAt: new Date(),
          trialEndsAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
          maxUsers: 2,
          maxProducts: 500,
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

  private async signRefreshToken(userId: string, sessionId: string) {
    return this.jwt.signAsync(
      { sub: userId, sessionId, tokenType: "refresh" },
      { expiresIn: this.refreshExpiresIn() as any },
    );
  }

  private refreshExpiresAt() {
    const raw = this.refreshExpiresIn().trim();
    const match = raw.match(/^(\d+)([smhd])$/i);
    if (!match) return new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
    const amount = Number(match[1]);
    const unit = match[2].toLowerCase();
    const multiplier =
      unit === "s" ? 1000 :
      unit === "m" ? 60 * 1000 :
      unit === "h" ? 60 * 60 * 1000 :
      24 * 60 * 60 * 1000;
    return new Date(Date.now() + amount * multiplier);
  }

  private hashRefreshToken(token: string) {
    return createHash("sha256").update(token).digest("hex");
  }

  private async createAuthSession(userId: string, companyId: string | null) {
    const row = await this.prisma.authSession.create({
      data: {
        userId,
        companyId,
        tokenFamily: randomUUID(),
        refreshTokenHash: "pending",
        expiresAt: this.refreshExpiresAt(),
      },
      select: { id: true },
    });
    return { sessionId: row.id };
  }

  private async storeRefreshHash(sessionId: string, refreshToken: string) {
    await this.prisma.authSession.update({
      where: { id: sessionId },
      data: { refreshTokenHash: this.hashRefreshToken(refreshToken) },
      select: { id: true },
    });
  }

  private async rotateAuthSession(sessionId: string) {
    const current = await this.prisma.authSession.findUnique({
      where: { id: sessionId },
      select: { userId: true, companyId: true, tokenFamily: true },
    });
    if (!current) throw new UnauthorizedException("Invalid refresh token");
    await this.prisma.authSession.update({
      where: { id: sessionId },
      data: { revokedAt: new Date(), revocationReason: "refresh_rotated", lastUsedAt: new Date() },
      select: { id: true },
    });
    const next = await this.prisma.authSession.create({
      data: {
        userId: current.userId,
        companyId: current.companyId,
        tokenFamily: current.tokenFamily,
        refreshTokenHash: "pending",
        expiresAt: this.refreshExpiresAt(),
      },
      select: { id: true },
    });
    return { sessionId: next.id };
  }

  private async countSoleOwnedCompanies(userId: string) {
    return (await this.findSoleOwnedCompanyIds(userId)).length;
  }

  private async findSoleOwnedCompanyIds(userId: string) {
    const ownerMemberships = await this.prisma.companyMember.findMany({
      where: {
        userId,
        role: CompanyMemberRole.OWNER,
        status: CompanyMemberStatus.ACTIVE,
      },
      select: { companyId: true },
    });

    const soleOwned: string[] = [];
    for (const membership of ownerMemberships) {
      const ownerCount = await this.prisma.companyMember.count({
        where: {
          companyId: membership.companyId,
          role: CompanyMemberRole.OWNER,
          status: CompanyMemberStatus.ACTIVE,
        },
      });
      if (ownerCount <= 1) soleOwned.push(membership.companyId);
    }
    return soleOwned;
  }

  private async deleteCompanyOwnedRows(
    tx: Prisma.TransactionClient,
    companyId: string,
  ) {
    const rows = await tx.$queryRaw<Array<{ table_name: string }>>(Prisma.sql`
      SELECT table_name
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND column_name = 'company_id'
        AND table_name NOT IN ('companies', 'company_members', 'users')
      ORDER BY table_name ASC
    `);

    for (const row of rows) {
      const tableName = row.table_name;
      if (!/^[a-zA-Z0-9_]+$/.test(tableName)) {
        throw new Error(`Unsafe table name discovered: ${tableName}`);
      }
      await tx.$executeRawUnsafe(
        `DELETE FROM "${tableName}" WHERE company_id = $1`,
        companyId,
      );
    }
  }

  private async cleanupCompanyStorage(companyId: string) {
    await this.r2.deleteAllCompanyObjects(companyId);
    await this.deleteLocalCompanyUploads(companyId);
  }

  private async deleteLocalCompanyUploads(companyId: string) {
    const uploadRoot = this.resolveUploadDir();
    const companiesRoot = resolve(uploadRoot, "companies");
    const companyRoot = resolve(companiesRoot, companyId);
    const pathFromCompaniesRoot = relative(companiesRoot, companyRoot);
    if (pathFromCompaniesRoot.startsWith("..") || isAbsolute(pathFromCompaniesRoot)) {
      throw new Error("Unsafe company upload path");
    }

    try {
      await fs.rm(companyRoot, { recursive: true, force: true });
    } catch (error) {
      throw new Error(`No se pudo eliminar storage local de empresa: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  private resolveUploadDir(): string {
    const fromEnv = (this.config.get<string>("UPLOAD_DIR") ?? process.env.UPLOAD_DIR ?? "").trim();
    const volumeDir = "/uploads";
    return fromEnv || volumeDir || join(process.cwd(), "uploads");
  }

  private async findAccountDeletionUser(userId: string) {
    return this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        passwordHash: true,
        companyId: true,
        companyMemberships: {
          select: {
            id: true,
            companyId: true,
            role: true,
            status: true,
          },
        },
      },
    });
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
