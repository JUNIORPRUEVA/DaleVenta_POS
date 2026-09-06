import {
  ConflictException,
  ForbiddenException,
  Injectable,
  Logger,
  NotFoundException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { BackupStatus, BackupType, Role } from "@prisma/client";
import { sha256Hex } from "./backup-archive.builder";
import { BackupArchiveReader } from "./backup-archive.reader";
import { BackupStorageService } from "./backup-storage.service";
import { BACKUP_FORMAT_VERSION, BACKUP_PRODUCT } from "./backup.types";
import { BackupsService } from "./backups.service";
import { RESTORE_MODULE_SPECS, validateRestorePayload } from "./backup-restore.registry";
import { requireTenant, TenantUser } from "../auth/tenant-context";
import { PrismaService } from "../prisma/prisma.service";

type BackupRecordRow = {
  id: string;
  companyId: string;
  status: BackupStatus;
  type: BackupType;
  storageKey: string;
  checksum: string | null;
};

const restoreLocks = new Set<string>();

@Injectable()
export class BackupsRestoreService {
  private readonly logger = new Logger(BackupsRestoreService.name);
  private readonly reader = new BackupArchiveReader();

  constructor(
    private readonly prisma: PrismaService,
    private readonly backups: BackupsService,
    private readonly storage: BackupStorageService,
    private readonly config: ConfigService,
  ) {}

  async restore(user: TenantUser, backupId: string) {
    const startedAt = Date.now();
    const companyId = requireTenant(user);
    this.assertRestoreEnabled();
    this.assertRestorePermission(user);
    if (restoreLocks.has(companyId)) {
      throw new ConflictException("Ya existe un restore en proceso para esta empresa.");
    }

    restoreLocks.add(companyId);
    let preRestoreBackupId: string | null = null;
    try {
      const backup = await this.findOwnedCompleteBackup(companyId, backupId);
      const archive = await this.storage.getCanonicalBackup(backup.storageKey);
      this.assertStoredChecksum(backup, archive);
      const parsed = this.reader.parse(archive);
      const validation = this.backups.validateArchive(archive, companyId);
      if (validation.status === "INVALID") {
        throw new ConflictException("Backup canonico invalido.");
      }
      this.assertManifestEligible(parsed.manifest, backup, companyId);
      validateRestorePayload(RESTORE_MODULE_SPECS, parsed.moduleRecords, companyId);

      await this.audit("RESTORE_STARTED", {
        companyId,
        userId: user.id,
        backupId,
        preRestoreBackupId: null,
        status: "STARTED",
      });

      const preRestore = await this.backups.createPreRestoreSafety(user);
      preRestoreBackupId = preRestore.backupId;
      const preRestoreArchive = await this.storage.getCanonicalBackup(
        this.storage.buildStorageKey({
          companyId,
          backupId: preRestore.backupId,
          type: "PRE_RESTORE_SAFETY",
        }),
      );
      const preValidation = this.backups.validateArchive(preRestoreArchive, companyId);
      if (preValidation.status === "INVALID") {
        throw new ConflictException("Pre-restore backup invalido.");
      }
      await this.audit("PRE_RESTORE_BACKUP_CREATED", {
        companyId,
        userId: user.id,
        backupId,
        preRestoreBackupId,
        status: "COMPLETE",
      });

      const restoreStart = Date.now();
      await this.prisma.$transaction(
        async (tx) => {
          await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtext(${companyId}))`;
          await this.deleteRestorableTenantRows(tx, companyId);
          this.maybeInjectFailure("after_delete");
          await this.insertRestoredRows(tx, parsed.moduleRecords);
          await this.verifyRestoredCounts(tx, companyId, parsed.moduleRecords);
        },
        { timeout: this.restoreTimeoutMs(), maxWait: this.restoreMaxWaitMs() },
      );

      const totalMs = Date.now() - startedAt;
      await this.audit("RESTORE_COMPLETED", {
        companyId,
        userId: user.id,
        backupId,
        preRestoreBackupId,
        status: "COMPLETED",
      });
      return {
        ok: true,
        backupId,
        preRestoreBackupId,
        companyId,
        restoredModules: RESTORE_MODULE_SPECS.filter((spec) => spec.strategy === "replace").map(
          (spec) => spec.name,
        ),
        timings: {
          totalMs,
          restoreTransactionMs: Date.now() - restoreStart,
        },
      };
    } catch (error) {
      await this.audit("RESTORE_FAILED", {
        companyId,
        userId: user.id,
        backupId,
        preRestoreBackupId,
        status: "FAILED",
      });
      await this.audit("RESTORE_ROLLED_BACK", {
        companyId,
        userId: user.id,
        backupId,
        preRestoreBackupId,
        status: "ROLLED_BACK",
      });
      this.logger.warn(
        `Restore failed companyId=${companyId} backupId=${backupId}: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
      throw error;
    } finally {
      restoreLocks.delete(companyId);
    }
  }

  private async findOwnedCompleteBackup(companyId: string, backupId: string) {
    const row = (await (this.prisma as never as {
      backupRecord: { findFirst(args: unknown): Promise<BackupRecordRow | null> };
    }).backupRecord.findFirst({
      where: { id: backupId, companyId, deletedAt: null },
      select: {
        id: true,
        companyId: true,
        status: true,
        type: true,
        storageKey: true,
        checksum: true,
      },
    })) as BackupRecordRow | null;
    if (!row) throw new NotFoundException("Backup no encontrado.");
    if (row.status !== BackupStatus.COMPLETE) {
      throw new ConflictException("Solo backups COMPLETE pueden restaurarse.");
    }
    return row;
  }

  private assertStoredChecksum(row: BackupRecordRow, archive: Buffer) {
    if (row.checksum && row.checksum !== sha256Hex(archive)) {
      throw new ConflictException("El checksum almacenado no coincide con el archivo.");
    }
  }

  private assertManifestEligible(
    manifest: { [key: string]: unknown },
    row: BackupRecordRow,
    companyId: string,
  ) {
    if (manifest.product !== BACKUP_PRODUCT) throw new ConflictException("Producto de backup no soportado.");
    if (manifest.backupFormatVersion !== BACKUP_FORMAT_VERSION) {
      throw new ConflictException("Version de backup no soportada.");
    }
    if (manifest.backupStatus !== "COMPLETE") throw new ConflictException("Backup no esta COMPLETE.");
    if (manifest.companyId !== companyId || row.companyId !== companyId) {
      throw new ForbiddenException("El backup no pertenece a esta empresa.");
    }
    if (manifest.backupId !== row.id) {
      throw new ConflictException("El manifest no coincide con el backup solicitado.");
    }
  }

  private assertRestorePermission(user: TenantUser) {
    if (user.role !== Role.ADMIN && user.role !== "ADMIN") {
      throw new ForbiddenException("Solo administradores pueden restaurar backups.");
    }
  }

  private assertRestoreEnabled() {
    const raw = (this.config.get<string>("BACKUP_RESTORE_ENABLED") ?? "false")
      .trim()
      .toLowerCase();
    if (["1", "true", "yes", "on", "enabled"].includes(raw)) return;
    throw new ForbiddenException("Restore de backups deshabilitado por configuracion.");
  }

  private async deleteRestorableTenantRows(tx: Record<string, unknown>, companyId: string) {
    const specs = RESTORE_MODULE_SPECS.filter((spec) => spec.strategy === "replace")
      .slice()
      .sort((a, b) => a.deleteOrder - b.deleteOrder);
    for (const spec of specs) {
      if (!spec.delegateName || !spec.deleteWhere) continue;
      const delegate = tx[spec.delegateName] as { deleteMany(args: unknown): Promise<unknown> };
      await delegate.deleteMany({ where: spec.deleteWhere(companyId) });
    }
  }

  private async insertRestoredRows(tx: Record<string, unknown>, moduleRecords: Map<string, unknown[]>) {
    const specs = RESTORE_MODULE_SPECS.filter((spec) => spec.strategy === "replace")
      .slice()
      .sort((a, b) => a.restoreOrder - b.restoreOrder);
    for (const spec of specs) {
      if (!spec.delegateName) continue;
      const records = moduleRecords.get(spec.name) ?? [];
      if (!records.length) continue;
      const delegate = tx[spec.delegateName] as { createMany(args: unknown): Promise<unknown> };
      await delegate.createMany({ data: records.map((record) => this.toPrismaCreateInput(record)) });
    }
  }

  private async verifyRestoredCounts(
    tx: Record<string, unknown>,
    companyId: string,
    moduleRecords: Map<string, unknown[]>,
  ) {
    for (const spec of RESTORE_MODULE_SPECS.filter((item) => item.strategy === "replace")) {
      if (!spec.delegateName || !spec.deleteWhere) continue;
      const expected = moduleRecords.get(spec.name)?.length ?? 0;
      const delegate = tx[spec.delegateName] as { count(args: unknown): Promise<number> };
      const actual = await delegate.count({ where: spec.deleteWhere(companyId) });
      if (actual !== expected) {
        throw new Error(`${spec.name} restore count mismatch: expected ${expected}, got ${actual}`);
      }
    }
  }

  private maybeInjectFailure(point: string) {
    const appEnv = (this.config.get<string>("APP_ENV") ?? "").toLowerCase();
    const nodeEnv = (this.config.get<string>("NODE_ENV") ?? "").toLowerCase();
    const injection = (this.config.get<string>("BACKUP_RESTORE_FAILURE_INJECTION") ?? "").toLowerCase();
    if (nodeEnv === "production" && appEnv !== "uat") return;
    if (injection === point) {
      throw new Error(`Injected restore failure at ${point}`);
    }
  }

  private toPrismaCreateInput(value: unknown): unknown {
    if (Array.isArray(value)) return value.map((item) => this.toPrismaCreateInput(item));
    if (this.isSerializedDecimal(value)) return this.serializedDecimalToString(value);
    if (value && typeof value === "object") {
      const output: Record<string, unknown> = {};
      for (const [key, item] of Object.entries(value)) {
        output[key] = this.toPrismaCreateInput(item);
      }
      return output;
    }
    return value;
  }

  private isSerializedDecimal(value: unknown): value is { d: number[]; e: number; s: number } {
    if (!value || typeof value !== "object" || Array.isArray(value)) return false;
    const candidate = value as { d?: unknown; e?: unknown; s?: unknown };
    return (
      Array.isArray(candidate.d) &&
      candidate.d.every((item) => typeof item === "number") &&
      typeof candidate.e === "number" &&
      typeof candidate.s === "number" &&
      Object.keys(candidate).every((key) => key === "d" || key === "e" || key === "s")
    );
  }

  private serializedDecimalToString(value: { d: number[]; e: number; s: number }) {
    const digits = value.d
      .map((chunk, index) => (index === 0 ? String(chunk) : String(chunk).padStart(7, "0")))
      .join("")
      .replace(/^0+(?=\d)/, "");
    const point = value.e + 1;
    const signed = value.s < 0 ? "-" : "";
    if (point <= 0) return `${signed}0.${"0".repeat(Math.abs(point))}${digits}`;
    if (point >= digits.length) return `${signed}${digits}${"0".repeat(point - digits.length)}`;
    return `${signed}${digits.slice(0, point)}.${digits.slice(point)}`;
  }

  private restoreTimeoutMs() {
    return Number(this.config.get<string>("BACKUP_RESTORE_TRANSACTION_TIMEOUT_MS") ?? 60000);
  }

  private restoreMaxWaitMs() {
    return Number(this.config.get<string>("BACKUP_RESTORE_TRANSACTION_MAX_WAIT_MS") ?? 10000);
  }

  private async audit(
    action: string,
    params: {
      companyId: string;
      userId: string | null;
      backupId: string;
      preRestoreBackupId: string | null;
      status: string;
    },
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
            preRestoreBackupId: params.preRestoreBackupId,
            status: params.status,
          },
        },
      });
    } catch (error) {
      this.logger.warn(
        `Restore audit failed action=${action} backupId=${params.backupId}: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }
}
