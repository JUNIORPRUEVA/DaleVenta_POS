import { ConfigService } from "@nestjs/config";
import { BackupStatus, BackupType, Role } from "@prisma/client";
import { BackupArchiveBuilder, sha256Hex, stableJson } from "./backup-archive.builder";
import { BackupStorageService } from "./backup-storage.service";
import { BACKUP_FORMAT_VERSION, BACKUP_PRODUCT, BackupManifest } from "./backup.types";
import { BackupsRestoreService } from "./backups-restore.service";
import { BackupsService } from "./backups.service";
import { RESTORE_MODULE_SPECS } from "./backup-restore.registry";

describe("BackupsRestoreService", () => {
  const companyA = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const companyB = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
  const backupId = "33333333-3333-4333-8333-333333333333";
  const userA = { id: "11111111-1111-4111-8111-111111111111", role: Role.ADMIN, companyId: companyA };

  function archive(overrides: Partial<BackupManifest> = {}) {
    const records = [{ id: "product-a", companyId: companyA, nombre: "Restored" }];
    const manifest: BackupManifest = {
      backupFormatVersion: BACKUP_FORMAT_VERSION,
      backupId,
      product: BACKUP_PRODUCT,
      environment: "test",
      createdAt: "2026-09-06T00:00:00.000Z",
      appVersion: null,
      backendVersion: "test",
      minimumCompatibleVersion: "1.0.5",
      companyId: companyA,
      companyNameSnapshot: "Tenant A",
      backupType: "MANUAL",
      backupStatus: "COMPLETE",
      modules: ["products"],
      recordCounts: { products: records.length },
      checksums: { products: sha256Hex(Buffer.from(stableJson(records), "utf8")) },
      ...overrides,
    };
    return new BackupArchiveBuilder().build(manifest, [
      {
        name: "products",
        fileName: "data/products.json",
        records,
        recordCount: records.length,
        checksum: manifest.checksums.products,
      },
    ]).archive;
  }

  function makeDelegate(name: string, calls: string[], count = 0) {
    return {
      deleteMany: jest.fn(async () => calls.push(`${name}.deleteMany`)),
      createMany: jest.fn(async ({ data }) => calls.push(`${name}.createMany:${data.length}`)),
      count: jest.fn(async () => (name === "product" ? 1 : count)),
    };
  }

  function tx(calls: string[]) {
    const base: Record<string, unknown> = {
      $executeRaw: jest.fn(async () => undefined),
    };
    for (const spec of RESTORE_MODULE_SPECS) {
      if (spec.delegateName) base[spec.delegateName] = makeDelegate(spec.delegateName, calls);
    }
    return base;
  }

  function serviceWith(options: {
    rowCompanyId?: string;
    status?: BackupStatus;
    storedChecksum?: string | null;
    archiveBuffer?: Buffer;
    preRestoreFails?: boolean;
    failureInjection?: string;
  } = {}) {
    const archiveBuffer = options.archiveBuffer ?? archive();
    const calls: string[] = [];
    const prisma = {
      backupRecord: {
        findFirst: jest.fn(async () => ({
          id: backupId,
          companyId: options.rowCompanyId ?? companyA,
          status: options.status ?? BackupStatus.COMPLETE,
          type: BackupType.MANUAL,
          storageKey: "backups/companies/a/manual/backup.dvbackup",
          checksum: options.storedChecksum === undefined ? sha256Hex(archiveBuffer) : options.storedChecksum,
        })),
      },
      companyLicenseAuditLog: { create: jest.fn(async () => ({})) },
      $transaction: jest.fn((callback) => callback(tx(calls))),
    };
    const backups = {
      validateArchive: jest.fn(() => ({
        status: "VALID",
        format: "CANONICAL",
        errors: [],
        warnings: [],
        manifest: {},
      })),
      createPreRestoreSafety: jest.fn(async () => {
        if (options.preRestoreFails) throw new Error("pre restore down");
        return { backupId: "44444444-4444-4444-8444-444444444444" };
      }),
    };
    const storage = {
      getCanonicalBackup: jest.fn(async () => archiveBuffer),
      buildStorageKey: jest.fn(() => "backups/companies/a/pre_restore_safety/pre.dvbackup"),
    };
    const config = {
      get: jest.fn((key: string) => {
        if (key === "APP_ENV") return "uat";
        if (key === "BACKUP_RESTORE_ENABLED") return "true";
        if (key === "BACKUP_RESTORE_FAILURE_INJECTION") return options.failureInjection;
        return undefined;
      }),
    };
    const service = new BackupsRestoreService(
      prisma as never,
      backups as unknown as BackupsService,
      storage as unknown as BackupStorageService,
      config as unknown as ConfigService,
    );
    return { service, prisma, backups, storage, calls };
  }

  it("restores an owned complete canonical backup inside a transaction", async () => {
    const { service, prisma, backups, calls } = serviceWith();

    const result = await service.restore(userA, backupId);

    expect(result.ok).toBe(true);
    expect(result.companyId).toBe(companyA);
    expect(result.preRestoreBackupId).toBe("44444444-4444-4444-8444-444444444444");
    expect(backups.createPreRestoreSafety).toHaveBeenCalledWith(userA);
    expect(prisma.$transaction).toHaveBeenCalled();
    expect(calls).toContain("product.createMany:1");
  });

  it("normalizes serialized Prisma decimals before createMany", async () => {
    const { service } = serviceWith();
    const input = (service as unknown as {
      toPrismaCreateInput(value: unknown): Record<string, unknown>;
    }).toPrismaCreateInput({ rate: { d: [1800000], e: -1, s: 1 } });

    expect(input.rate).toBe("0.1800000");
  });

  it("blocks non-admin restore", async () => {
    const { service } = serviceWith();

    await expect(
      service.restore({ ...userA, role: Role.CAJERO }, backupId),
    ).rejects.toThrow("Solo administradores");
  });

  it("blocks restore when feature gate is not explicitly enabled", async () => {
    const { service, backups } = serviceWith();
    (service as unknown as { config: { get: jest.Mock } }).config.get.mockImplementation(
      (key: string) => {
        if (key === "APP_ENV") return "uat";
        if (key === "BACKUP_RESTORE_ENABLED") return "false";
        return undefined;
      },
    );

    await expect(service.restore(userA, backupId)).rejects.toThrow(
      "Restore de backups deshabilitado",
    );
    expect(backups.createPreRestoreSafety).not.toHaveBeenCalled();
  });

  it("blocks cross-tenant backup records before restore starts", async () => {
    const { service, backups } = serviceWith({ rowCompanyId: companyB });

    await expect(service.restore(userA, backupId)).rejects.toThrow("no pertenece");
    expect(backups.createPreRestoreSafety).not.toHaveBeenCalled();
  });

  it("blocks stored checksum mismatch", async () => {
    const { service, backups } = serviceWith({ storedChecksum: "bad" });

    await expect(service.restore(userA, backupId)).rejects.toThrow("checksum");
    expect(backups.createPreRestoreSafety).not.toHaveBeenCalled();
  });

  it("blocks FAILED backup records", async () => {
    const { service, backups } = serviceWith({ status: BackupStatus.FAILED });

    await expect(service.restore(userA, backupId)).rejects.toThrow("Solo backups COMPLETE");
    expect(backups.createPreRestoreSafety).not.toHaveBeenCalled();
  });

  it("blocks unsupported manifest versions", async () => {
    const badArchive = archive({ backupFormatVersion: 999 });
    const { service, backups } = serviceWith({
      archiveBuffer: badArchive,
      storedChecksum: sha256Hex(badArchive),
    });

    await expect(service.restore(userA, backupId)).rejects.toThrow("Version");
    expect(backups.createPreRestoreSafety).not.toHaveBeenCalled();
  });

  it("does not start restore when pre-restore backup fails", async () => {
    const { service, prisma } = serviceWith({ preRestoreFails: true });

    await expect(service.restore(userA, backupId)).rejects.toThrow("pre restore down");
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it("rolls back transaction when UAT-only failure injection trips after delete", async () => {
    const { service, prisma } = serviceWith({ failureInjection: "after_delete" });

    await expect(service.restore(userA, backupId)).rejects.toThrow("Injected restore failure");
    expect(prisma.$transaction).toHaveBeenCalled();
  });
});
