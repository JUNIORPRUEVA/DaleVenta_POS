import { BackupArchiveBuilder, sha256Hex, stableJson } from "./backup-archive.builder";
import { BackupValidator } from "./backup-validator";
import {
  BACKUP_FORMAT_VERSION,
  BACKUP_MINIMUM_COMPATIBLE_VERSION,
  BACKUP_PRODUCT,
  BackupManifest,
  BackupModulePayload,
} from "./backup.types";

describe("BackupValidator", () => {
  const builder = new BackupArchiveBuilder();
  const validator = new BackupValidator();

  function archiveFor(companyId: string) {
    const records = [{ id: "product-a", companyId, name: "Monitor" }];
    const module: BackupModulePayload = {
      name: "products",
      fileName: "data/products.json",
      records,
      recordCount: records.length,
      checksum: sha256Hex(Buffer.from(stableJson(records), "utf8")),
    };
    const manifest: BackupManifest = {
      backupFormatVersion: BACKUP_FORMAT_VERSION,
      backupId: "11111111-1111-4111-8111-111111111111",
      product: BACKUP_PRODUCT,
      environment: "test",
      createdAt: "2026-09-06T00:00:00.000Z",
      appVersion: null,
      backendVersion: "test",
      minimumCompatibleVersion: BACKUP_MINIMUM_COMPATIBLE_VERSION,
      companyId,
      companyNameSnapshot: "FULLTECH",
      backupType: "MANUAL",
      backupStatus: "COMPLETE",
      modules: ["products"],
      recordCounts: { products: 1 },
      checksums: { products: module.checksum },
    };
    return builder.build(manifest, [module]).archive;
  }

  it("accepts a complete canonical archive for the authenticated company", () => {
    const archive = archiveFor("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa");

    const result = validator.validateCanonicalArchive(
      archive,
      "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    );

    expect(result.status).toBe("VALID");
    expect(result.format).toBe("CANONICAL");
  });

  it("rejects cross-tenant archives", () => {
    const archive = archiveFor("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa");

    const result = validator.validateCanonicalArchive(
      archive,
      "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    );

    expect(result.status).toBe("INVALID");
    expect(result.errors).toContain("companyId mismatch");
  });

  it("detects payload tampering through module checksums", () => {
    const archive = Buffer.from(archiveFor("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"));
    const needle = Buffer.from("Monitor", "utf8");
    const index = archive.indexOf(needle);
    archive.write("MONITOR", index, "utf8");

    const result = validator.validateCanonicalArchive(
      archive,
      "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    );

    expect(result.status).toBe("INVALID");
    expect(result.errors).toContain("products checksum mismatch");
  });
});
