import { ConfigService } from "@nestjs/config";
import * as fs from "node:fs/promises";
import * as os from "node:os";
import * as path from "node:path";
import { BackupStorageService } from "./backup-storage.service";

describe("BackupStorageService", () => {
  it("uses a configurable isolated backup prefix", () => {
    const service = new BackupStorageService(
      {} as never,
      { get: jest.fn().mockReturnValue("backups/uat/") } as unknown as ConfigService,
    );

    expect(
      service.buildStorageKey({
        companyId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        backupId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        type: "MANUAL",
      }),
    ).toBe(
      "backups/uat/companies/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/manual/bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.dvbackup",
    );
  });

  it("rejects unsafe backup prefixes", () => {
    const service = new BackupStorageService(
      {} as never,
      { get: jest.fn().mockReturnValue("../backups") } as unknown as ConfigService,
    );

    expect(() =>
      service.buildStorageKey({
        companyId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        backupId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        type: "MANUAL",
      }),
    ).toThrow("Invalid backup storage prefix");
  });

  it("supports opt-in local storage for isolated UAT volumes", async () => {
    const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "daleventas-backups-"));
    const service = new BackupStorageService(
      {
        putObject: jest.fn(),
        getObject: jest.fn(),
        deleteObject: jest.fn(),
      } as never,
      {
        get: jest.fn((key: string) => {
          if (key === "BACKUP_STORAGE_DRIVER") return "local";
          if (key === "BACKUP_STORAGE_LOCAL_DIR") return tempDir;
          if (key === "BACKUP_STORAGE_PREFIX") return "backups/uat";
          return undefined;
        }),
      } as unknown as ConfigService,
    );
    const objectKey = service.buildStorageKey({
      companyId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
      backupId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
      type: "MANUAL",
    });

    await service.putCanonicalBackup(objectKey, Buffer.from("canonical"));
    await expect(service.getCanonicalBackup(objectKey)).resolves.toEqual(Buffer.from("canonical"));
    await service.deleteCanonicalBackup(objectKey);
    await expect(service.getCanonicalBackup(objectKey)).rejects.toThrow();
  });
});
