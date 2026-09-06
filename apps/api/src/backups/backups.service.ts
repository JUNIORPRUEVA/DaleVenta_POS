import {
  ConflictException,
  ForbiddenException,
  BadRequestException,
  Injectable,
  Logger,
  NotFoundException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { BackupStatus, BackupType, CompanyStatus, Role } from "@prisma/client";
import { randomUUID } from "node:crypto";
import { PrismaService } from "../prisma/prisma.service";
import { requireTenant, TenantUser } from "../auth/tenant-context";
import { BackupArchiveBuilder, sha256Hex } from "./backup-archive.builder";
import { BackupExtractor } from "./backup-extractor";
import { BackupStorageService } from "./backup-storage.service";
import { BackupValidator } from "./backup-validator";
import {
  AUTOMATIC_BACKUP_INTERVAL_DAYS,
  BACKUP_FORMAT_VERSION,
  BackupTypeName,
  MAX_AUTOMATIC_BACKUPS_PER_COMPANY,
} from "./backup.types";

type BackupRecordRow = {
  id: string;
  companyId: string;
  createdByUserId: string | null;
  type: BackupType;
  status: BackupStatus;
  formatVersion: number;
  storageKey: string;
  sizeBytes: bigint | number;
  checksum: string | null;
  companyNameSnapshot: string;
  failureReason: string | null;
  createdAt: Date;
  validatedAt: Date | null;
  deletedAt: Date | null;
};

@Injectable()
export class BackupsService {
  private readonly logger = new Logger(BackupsService.name);
  private readonly extractor = new BackupExtractor();
  private readonly archiveBuilder = new BackupArchiveBuilder();
  private readonly validator = new BackupValidator();

  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: BackupStorageService,
    private readonly config: ConfigService,
  ) {}

  async createManual(user: TenantUser) {
    this.assertBackupPermission(user);
    const companyId = requireTenant(user);
    return this.createForCompany({
      companyId,
      userId: user.id,
      type: "MANUAL",
    });
  }

  async createPreRestoreSafety(user: TenantUser) {
    this.assertBackupPermission(user);
    const companyId = requireTenant(user);
    return this.createForCompany({
      companyId,
      userId: user.id,
      type: "PRE_RESTORE_SAFETY",
    });
  }

  async createAutomaticForCompany(companyId: string) {
    return this.createForCompany({
      companyId,
      userId: null,
      type: "AUTOMATIC",
    });
  }

  async list(user: TenantUser) {
    const companyId = requireTenant(user);
    const rows = (await (this.prisma as never as {
      backupRecord: { findMany(args: unknown): Promise<BackupRecordRow[]> };
    }).backupRecord.findMany({
      where: { companyId, deletedAt: null },
      orderBy: { createdAt: "desc" },
      take: 100,
    })) as BackupRecordRow[];
    return rows.map((row) => this.toSafeMetadata(row));
  }

  async download(user: TenantUser, backupId: string) {
    const companyId = requireTenant(user);
    const row = await this.findOwnedBackup(companyId, backupId);
    if (row.status !== BackupStatus.COMPLETE) {
      throw new ConflictException("El backup no esta completo.");
    }
    const archive = await this.storage.getCanonicalBackup(row.storageKey);
    const validation = this.validator.validateCanonicalArchive(archive, companyId);
    if (validation.status === "INVALID") {
      throw new ConflictException("El backup almacenado no valida correctamente.");
    }
    await this.audit("BACKUP_DOWNLOADED", {
      companyId,
      userId: user.id,
      backupId,
      status: row.status,
    });
    return {
      fileName: `daleventas-${backupId}.dvbackup`,
      archive,
      metadata: this.toSafeMetadata(row),
    };
  }

  async validateUploadedArchive(user: TenantUser, archive?: Buffer) {
    this.assertBackupPermission(user);
    const companyId = requireTenant(user);
    const validation = this.validateImportArchive(archive, companyId);
    return {
      status: validation.status,
      format: validation.format,
      errors: validation.errors,
      warnings: validation.warnings,
      manifest: validation.manifest
        ? {
            backupId: validation.manifest.backupId,
            companyId: validation.manifest.companyId,
            companyNameSnapshot: validation.manifest.companyNameSnapshot,
            createdAt: validation.manifest.createdAt,
            backupType: validation.manifest.backupType,
            backupStatus: validation.manifest.backupStatus,
            modules: validation.manifest.modules,
            recordCounts: validation.manifest.recordCounts,
            formatVersion: validation.manifest.backupFormatVersion,
          }
        : null,
    };
  }

  async importCanonicalArchive(user: TenantUser, archive?: Buffer) {
    this.assertBackupPermission(user);
    const companyId = requireTenant(user);
    const validation = this.validateImportArchive(archive, companyId);
    if (validation.status === "INVALID" || !validation.manifest) {
      throw new BadRequestException({
        message: "Backup canonico invalido.",
        errors: validation.errors,
      });
    }
    const manifest = validation.manifest;
    const backupId = manifest.backupId;
    if (!/^[0-9a-fA-F-]{36}$/.test(backupId)) {
      throw new BadRequestException("backupId invalido.");
    }
    const storageKey = this.storage.buildStorageKey({
      companyId,
      backupId,
      type: "MANUAL",
    });
    const checksum = sha256Hex(archive!);
    const existing = await (this.prisma as never as {
      backupRecord: { findFirst(args: unknown): Promise<BackupRecordRow | null> };
    }).backupRecord.findFirst({
      where: { id: backupId, companyId, deletedAt: null },
    });
    if (existing) {
      if (existing.checksum !== checksum) {
        throw new ConflictException("Ya existe un backup con ese ID y otro checksum.");
      }
      return this.toSafeMetadata(existing);
    }

    await this.storage.putCanonicalBackup(storageKey, archive!);
    const row = (await (this.prisma as never as {
      backupRecord: { create(args: unknown): Promise<BackupRecordRow> };
    }).backupRecord.create({
      data: {
        id: backupId,
        companyId,
        createdByUserId: user.id,
        type: BackupType.MANUAL,
        status: BackupStatus.COMPLETE,
        formatVersion: manifest.backupFormatVersion,
        storageKey,
        sizeBytes: BigInt(archive!.length),
        checksum,
        companyNameSnapshot: manifest.companyNameSnapshot,
        validatedAt: new Date(),
      },
    })) as BackupRecordRow;
    await this.audit("BACKUP_IMPORTED", {
      companyId,
      userId: user.id,
      backupId,
      status: row.status,
    });
    return this.toSafeMetadata(row);
  }

  async deleteManual(user: TenantUser, backupId: string) {
    this.assertBackupPermission(user);
    const companyId = requireTenant(user);
    const row = await this.findOwnedBackup(companyId, backupId);
    if (row.type !== BackupType.MANUAL) {
      throw new ConflictException("Solo los backups manuales pueden eliminarse manualmente.");
    }
    await this.storage.deleteCanonicalBackup(row.storageKey);
    const deleted = (await (this.prisma as never as {
      backupRecord: { update(args: unknown): Promise<BackupRecordRow> };
    }).backupRecord.update({
      where: { id: row.id },
      data: { deletedAt: new Date() },
    })) as BackupRecordRow;
    await this.audit("BACKUP_DELETED", {
      companyId,
      userId: user.id,
      backupId,
      status: deleted.status,
    });
    return this.toSafeMetadata(deleted);
  }

  async runAutomaticBackups() {
    const cutoff = new Date(Date.now() - AUTOMATIC_BACKUP_INTERVAL_DAYS * 24 * 60 * 60 * 1000);
    const companies = await this.prisma.company.findMany({
      where: { status: CompanyStatus.ACTIVE },
      select: { id: true },
      orderBy: { id: "asc" },
    });
    for (const company of companies) {
      const latest = await (this.prisma as never as {
        backupRecord: { findFirst(args: unknown): Promise<BackupRecordRow | null> };
      }).backupRecord.findFirst({
        where: {
          companyId: company.id,
          type: BackupType.AUTOMATIC,
          status: BackupStatus.COMPLETE,
          deletedAt: null,
        },
        orderBy: { createdAt: "desc" },
      });
      if (latest && latest.createdAt > cutoff) continue;
      try {
        await this.createAutomaticForCompany(company.id);
      } catch (error) {
        this.logger.warn(
          `Automatic backup failed companyId=${company.id}: ${
            error instanceof Error ? error.message : String(error)
          }`,
        );
      }
    }
  }

  async applyRetention(companyId: string) {
    const rows = (await (this.prisma as never as {
      backupRecord: { findMany(args: unknown): Promise<BackupRecordRow[]> };
    }).backupRecord.findMany({
      where: {
        companyId,
        type: BackupType.AUTOMATIC,
        status: BackupStatus.COMPLETE,
        deletedAt: null,
      },
      orderBy: { createdAt: "desc" },
    })) as BackupRecordRow[];
    const stale = rows.slice(MAX_AUTOMATIC_BACKUPS_PER_COMPANY);
    for (const row of stale) {
      await this.storage.deleteCanonicalBackup(row.storageKey);
      await (this.prisma as never as {
        backupRecord: { update(args: unknown): Promise<BackupRecordRow> };
      }).backupRecord.update({
        where: { id: row.id },
        data: { deletedAt: new Date() },
      });
      await this.audit("RETENTION_DELETED", {
        companyId,
        userId: null,
        backupId: row.id,
        status: row.status,
      });
    }
    return { deleted: stale.length, kept: rows.length - stale.length };
  }

  auditInventory() {
    return this.extractor.auditInventory();
  }

  validateArchive(archive: Buffer, expectedCompanyId?: string) {
    return this.validator.validateCanonicalArchive(archive, expectedCompanyId);
  }

  private validateImportArchive(archive: Buffer | undefined, companyId: string) {
    if (!archive || archive.length === 0) {
      throw new BadRequestException("Archivo de backup requerido.");
    }
    return this.validator.validateCanonicalArchive(archive, companyId);
  }

  private async createForCompany(params: {
    companyId: string;
    userId: string | null;
    type: BackupTypeName;
  }) {
    const backupId = randomUUID();
    const createdAt = new Date();
    const company = await this.prisma.company.findUnique({
      where: { id: params.companyId },
      select: { id: true, name: true, status: true },
    });
    if (!company || company.status !== CompanyStatus.ACTIVE) {
      throw new ForbiddenException("Empresa no elegible para backup automatico.");
    }

    const storageKey = this.storage.buildStorageKey({
      companyId: params.companyId,
      backupId,
      type: params.type,
    });
    const pending = (await (this.prisma as never as {
      backupRecord: { create(args: unknown): Promise<BackupRecordRow> };
    }).backupRecord.create({
      data: {
        id: backupId,
        companyId: params.companyId,
        createdByUserId: params.userId,
        type: params.type,
        status: BackupStatus.PENDING,
        formatVersion: BACKUP_FORMAT_VERSION,
        storageKey,
        companyNameSnapshot: company.name,
      },
    })) as BackupRecordRow;

    try {
      const extracted = await this.prisma.$transaction(async (tx) =>
        this.extractor.extract(tx, {
          backupId,
          companyId: params.companyId,
          companyNameSnapshot: company.name,
          type: params.type,
          createdAt,
          environment: this.environmentName(),
          backendVersion: this.backendVersion(),
        }),
      );
      const built = this.archiveBuilder.build(extracted.manifest, extracted.modules);
      const validation = this.validator.validateCanonicalArchive(built.archive, params.companyId);
      if (validation.status === "INVALID") {
        throw new Error(`Backup validation failed: ${validation.errors.join("; ")}`);
      }

      await this.storage.putCanonicalBackup(storageKey, built.archive);
      const complete = (await (this.prisma as never as {
        backupRecord: { update(args: unknown): Promise<BackupRecordRow> };
      }).backupRecord.update({
        where: { id: pending.id },
        data: {
          status: BackupStatus.COMPLETE,
          sizeBytes: BigInt(built.archive.length),
          checksum: built.archiveChecksum,
          validatedAt: new Date(),
        },
      })) as BackupRecordRow;
      await this.audit("BACKUP_CREATED", {
        companyId: params.companyId,
        userId: params.userId,
        backupId,
        status: complete.status,
      });
      if (params.type === "AUTOMATIC") {
        await this.applyRetention(params.companyId);
      }
      return this.toSafeMetadata(complete);
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);
      const failed = (await (this.prisma as never as {
        backupRecord: { update(args: unknown): Promise<BackupRecordRow> };
      }).backupRecord.update({
        where: { id: pending.id },
        data: {
          status: BackupStatus.FAILED,
          failureReason: reason.slice(0, 2000),
        },
      })) as BackupRecordRow;
      await this.audit("BACKUP_FAILED", {
        companyId: params.companyId,
        userId: params.userId,
        backupId,
        status: failed.status,
      });
      throw error;
    }
  }

  private async findOwnedBackup(companyId: string, backupId: string) {
    const row = await (this.prisma as never as {
      backupRecord: { findFirst(args: unknown): Promise<BackupRecordRow | null> };
    }).backupRecord.findFirst({
      where: { id: backupId, companyId, deletedAt: null },
    });
    if (!row) throw new NotFoundException("Backup no encontrado.");
    return row;
  }

  private toSafeMetadata(row: BackupRecordRow) {
    return {
      backupId: row.id,
      companyId: row.companyId,
      type: row.type,
      status: row.status,
      createdAt: row.createdAt,
      validatedAt: row.validatedAt,
      size: Number(row.sizeBytes),
      checksum: row.checksum,
      formatVersion: row.formatVersion,
      companyNameSnapshot: row.companyNameSnapshot,
      failureReason: row.status === BackupStatus.FAILED ? row.failureReason : null,
    };
  }

  private assertBackupPermission(user: TenantUser) {
    if (!user?.id) throw new ForbiddenException("Usuario requerido.");
    if (user.role !== Role.ADMIN && user.role !== "ADMIN") {
      throw new ForbiddenException("Solo administradores pueden gestionar backups.");
    }
  }

  private environmentName() {
    return (
      this.config.get<string>("APP_ENV") ??
      this.config.get<string>("NODE_ENV") ??
      "unknown"
    );
  }

  private backendVersion() {
    return process.env.npm_package_version ?? null;
  }

  private async audit(
    action: string,
    params: { companyId: string; userId: string | null; backupId: string; status: string },
  ) {
    try {
      await this.prisma.companyLicenseAuditLog.create({
        data: {
          companyId: params.companyId,
          actorId: params.userId,
          action,
          reason: null,
          after: {
            backupId: params.backupId,
            status: params.status,
          },
        },
      });
    } catch (error) {
      this.logger.warn(
        `Backup audit failed action=${action} backupId=${params.backupId}: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }
}
