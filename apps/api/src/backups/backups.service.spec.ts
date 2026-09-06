import { ConfigService } from "@nestjs/config";
import { BackupStatus, BackupType, CompanyStatus, Role } from "@prisma/client";
import { BackupsService } from "./backups.service";
import { BackupStorageService } from "./backup-storage.service";
import { BackupManifest } from "./backup.types";
import { BackupArchiveBuilder, sha256Hex, stableJson } from "./backup-archive.builder";

describe("BackupsService", () => {
  const companyA = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const companyB = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
  const userA = { id: "11111111-1111-4111-8111-111111111111", role: Role.ADMIN, companyId: companyA };

  function row(overrides: Partial<Record<string, unknown>> = {}) {
    return {
      id: overrides.id ?? "33333333-3333-4333-8333-333333333333",
      companyId: overrides.companyId ?? companyA,
      createdByUserId: overrides.createdByUserId ?? userA.id,
      type: overrides.type ?? BackupType.MANUAL,
      status: overrides.status ?? BackupStatus.COMPLETE,
      formatVersion: 2,
      storageKey: overrides.storageKey ?? `backups/companies/${companyA}/manual/33333333-3333-4333-8333-333333333333.dvbackup`,
      sizeBytes: BigInt(overrides.sizeBytes as number | undefined ?? 100),
      checksum: "sha",
      companyNameSnapshot: "FULLTECH",
      failureReason: null,
      createdAt: overrides.createdAt ?? new Date("2026-09-06T00:00:00.000Z"),
      validatedAt: new Date("2026-09-06T00:00:01.000Z"),
      deletedAt: null,
    };
  }

  function serviceWith() {
    const prisma = {
      company: {
        findUnique: jest.fn().mockResolvedValue({
          id: companyA,
          name: "FULLTECH",
          status: CompanyStatus.ACTIVE,
        }),
      },
      companyLicenseAuditLog: { create: jest.fn().mockResolvedValue({}) },
      backupRecord: {
        create: jest.fn().mockImplementation(({ data }) => Promise.resolve(row(data))),
        update: jest.fn().mockImplementation(({ data, where }) =>
          Promise.resolve(row({ id: where.id, ...data })),
        ),
        findMany: jest.fn().mockResolvedValue([]),
        findFirst: jest.fn().mockResolvedValue(null),
      },
      $transaction: jest.fn((callback) => callback({})),
    };
    const storage = {
      buildStorageKey: jest.fn().mockImplementation(({ companyId, backupId, type }) =>
        `backups/uat/companies/${companyId}/${String(type).toLowerCase()}/${backupId}.dvbackup`,
      ),
      putCanonicalBackup: jest.fn().mockResolvedValue(undefined),
      getCanonicalBackup: jest.fn(),
      deleteCanonicalBackup: jest.fn().mockResolvedValue(undefined),
    } as unknown as jest.Mocked<BackupStorageService>;
    const service = new BackupsService(
      prisma as never,
      storage,
      { get: jest.fn().mockReturnValue("test") } as unknown as ConfigService,
    );
    const moduleRecords = [{ id: "product-a", companyId: companyA, name: "Same name" }];
    const moduleChecksum = sha256Hex(Buffer.from(stableJson(moduleRecords), "utf8"));
    const manifest: BackupManifest = {
      backupFormatVersion: 2,
      backupId: "placeholder",
      product: "DaleVentas POS / FullPOS Cloud",
      environment: "test",
      createdAt: "2026-09-06T00:00:00.000Z",
      appVersion: null,
      backendVersion: "test",
      minimumCompatibleVersion: "1.0.5",
      companyId: companyA,
      companyNameSnapshot: "FULLTECH",
      backupType: "MANUAL",
      backupStatus: "COMPLETE",
      modules: ["products"],
      recordCounts: { products: 1 },
      checksums: { products: moduleChecksum },
    };
    const extract = jest.fn().mockResolvedValue({
      manifest,
      modules: [{
        name: "products",
        fileName: "data/products.json",
        records: moduleRecords,
        recordCount: 1,
        checksum: moduleChecksum,
      }],
    });
    (service as unknown as { extractor: { extract: jest.Mock } }).extractor = { extract };
    return { service, prisma, storage, extract };
  }

  it("creates backup only for the authenticated tenant and stores canonical metadata", async () => {
    const { service, prisma, storage, extract } = serviceWith();

    const result = await service.createManual(userA);

    expect(result.companyId).toBe(companyA);
    expect(extract).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({
      companyId: companyA,
      type: "MANUAL",
    }));
    expect(storage.buildStorageKey).toHaveBeenCalledWith(expect.objectContaining({
      companyId: companyA,
      type: "MANUAL",
    }));
    expect(storage.putCanonicalBackup).toHaveBeenCalledWith(
      expect.stringContaining(`/companies/${companyA}/manual/`),
      expect.any(Buffer),
    );
    expect(prisma.backupRecord.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        companyId: companyA,
        createdByUserId: userA.id,
        type: "MANUAL",
      }),
    });
  });

  it("lists only backup metadata for the authenticated company", async () => {
    const { service, prisma } = serviceWith();
    prisma.backupRecord.findMany.mockResolvedValue([row({ companyId: companyA })]);

    await service.list(userA);

    expect(prisma.backupRecord.findMany).toHaveBeenCalledWith(expect.objectContaining({
      where: { companyId: companyA, deletedAt: null },
    }));
  });

  it("retention deletes only old complete automatic backups returned for one company", async () => {
    const { service, prisma, storage } = serviceWith();
    const rows = Array.from({ length: 17 }, (_, index) =>
      row({
        id: `33333333-3333-4333-8333-3333333333${String(index).padStart(2, "0")}`,
        companyId: companyA,
        type: BackupType.AUTOMATIC,
        createdAt: new Date(Date.UTC(2026, 8, 20 - index)),
        storageKey: `backups/companies/${companyA}/automatic/${index}.dvbackup`,
      }),
    );
    prisma.backupRecord.findMany.mockResolvedValue(rows);

    const result = await service.applyRetention(companyA);

    expect(result).toEqual({ kept: 15, deleted: 2 });
    expect(prisma.backupRecord.findMany).toHaveBeenCalledWith(expect.objectContaining({
      where: {
        companyId: companyA,
        type: BackupType.AUTOMATIC,
        status: BackupStatus.COMPLETE,
        deletedAt: null,
      },
    }));
    expect(storage.deleteCanonicalBackup).toHaveBeenCalledTimes(2);
    expect(storage.deleteCanonicalBackup).not.toHaveBeenCalledWith(
      expect.stringContaining(companyB),
    );
  });

  it("does not run retention when backup creation fails", async () => {
    const { service, storage } = serviceWith();
    storage.putCanonicalBackup = jest.fn().mockRejectedValue(new Error("R2 down")) as never;
    const retention = jest.spyOn(service, "applyRetention");

    await expect(service.createAutomaticForCompany(companyA)).rejects.toThrow("R2 down");

    expect(retention).not.toHaveBeenCalled();
  });

  it("validates an uploaded canonical archive without storing it", async () => {
    const { service, storage } = serviceWith();
    const archive = canonicalArchive(companyA);

    const result = await service.validateUploadedArchive(userA, archive);

    expect(result.status).toBe("VALID");
    expect(result.manifest?.companyId).toBe(companyA);
    expect(storage.putCanonicalBackup).not.toHaveBeenCalled();
  });

  it("imports a canonical archive only for the authenticated company", async () => {
    const { service, prisma, storage } = serviceWith();
    const archive = canonicalArchive(companyA);

    const result = await service.importCanonicalArchive(userA, archive);

    expect(result.companyId).toBe(companyA);
    expect(result.backupId).toBe("33333333-3333-4333-8333-333333333333");
    expect(storage.putCanonicalBackup).toHaveBeenCalledWith(
      expect.stringContaining(`/companies/${companyA}/manual/`),
      archive,
    );
    expect(prisma.backupRecord.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        id: "33333333-3333-4333-8333-333333333333",
        companyId: companyA,
        type: BackupType.MANUAL,
        status: BackupStatus.COMPLETE,
      }),
    });
  });

  it("rejects importing another company's archive before storage", async () => {
    const { service, storage } = serviceWith();

    await expect(
      service.importCanonicalArchive(userA, canonicalArchive(companyB)),
    ).rejects.toThrow("Backup canonico invalido");

    expect(storage.putCanonicalBackup).not.toHaveBeenCalled();
  });
});

function canonicalArchive(companyId: string) {
  const records = [{ id: "product-a", companyId, nombre: "Backup product" }];
  const manifest: BackupManifest = {
    backupFormatVersion: 2,
    backupId: "33333333-3333-4333-8333-333333333333",
    product: "DaleVentas POS / FullPOS Cloud",
    environment: "test",
    createdAt: "2026-09-06T00:00:00.000Z",
    appVersion: null,
    backendVersion: "test",
    minimumCompatibleVersion: "1.0.5",
    companyId,
    companyNameSnapshot: companyId.endsWith("bbbbbbbbbbbb") ? "Tenant B" : "Tenant A",
    backupType: "MANUAL",
    backupStatus: "COMPLETE",
    modules: ["products"],
    recordCounts: { products: records.length },
    checksums: { products: sha256Hex(Buffer.from(stableJson(records), "utf8")) },
  };
  return new BackupArchiveBuilder().build(manifest, [
    {
      name: "products",
      fileName: "data/products.json",
      records,
      recordCount: records.length,
      checksum: manifest.checksums.products,
    },
  ]).archive as Buffer;
}
