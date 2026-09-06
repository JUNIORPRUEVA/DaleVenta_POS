import {
  BACKUP_FORMAT_VERSION,
  BACKUP_PRODUCT,
  BackupManifest,
  BackupValidationResult,
} from "./backup.types";
import { sha256Hex } from "./backup-archive.builder";

type ZipEntry = { name: string; bytes: Buffer };

export class BackupValidator {
  validateCanonicalArchive(archive: Buffer, expectedCompanyId?: string): BackupValidationResult {
    const errors: string[] = [];
    const warnings: string[] = [];
    let entries: ZipEntry[];
    try {
      entries = this.readStoreZip(archive);
    } catch (error) {
      return {
        status: "INVALID",
        format: "INVALID",
        errors: [error instanceof Error ? error.message : "Archive unreadable"],
        warnings,
        manifest: null,
      };
    }

    const manifestEntry = entries.find((entry) => entry.name === "manifest.json");
    if (!manifestEntry) {
      return {
        status: "INVALID",
        format: "LEGACY",
        errors: ["manifest.json missing"],
        warnings,
        manifest: null,
      };
    }

    let manifest: BackupManifest;
    try {
      manifest = JSON.parse(manifestEntry.bytes.toString("utf8")) as BackupManifest;
    } catch {
      return {
        status: "INVALID",
        format: "INVALID",
        errors: ["manifest.json unreadable"],
        warnings,
        manifest: null,
      };
    }

    if (manifest.product !== BACKUP_PRODUCT) errors.push("product identity mismatch");
    if (manifest.backupFormatVersion !== BACKUP_FORMAT_VERSION) errors.push("unsupported format version");
    if (!manifest.backupId) errors.push("backupId missing");
    if (!manifest.companyId) errors.push("companyId missing");
    if (expectedCompanyId && manifest.companyId !== expectedCompanyId) errors.push("companyId mismatch");
    if (manifest.backupStatus !== "COMPLETE") errors.push("backup is not COMPLETE");
    if (!Array.isArray(manifest.modules) || manifest.modules.length === 0) errors.push("modules missing");

    const entryMap = new Map(entries.map((entry) => [entry.name, entry.bytes]));
    for (const moduleName of manifest.modules ?? []) {
      const fileName = `data/${moduleName}.json`;
      const payload = entryMap.get(fileName);
      if (!payload) {
        errors.push(`${fileName} missing`);
        continue;
      }
      try {
        const parsed = JSON.parse(payload.toString("utf8"));
        if (!Array.isArray(parsed)) errors.push(`${fileName} is not an array`);
        if ((manifest.recordCounts?.[moduleName] ?? -1) !== parsed.length) {
          errors.push(`${moduleName} record count mismatch`);
        }
      } catch {
        errors.push(`${fileName} unreadable`);
      }
      const checksum = manifest.checksums?.[moduleName];
      if (!checksum || checksum !== sha256Hex(payload)) {
        errors.push(`${moduleName} checksum mismatch`);
      }
    }

    return {
      status: errors.length ? "INVALID" : warnings.length ? "VALID_WITH_WARNINGS" : "VALID",
      format: manifest.product === BACKUP_PRODUCT ? "CANONICAL" : "LEGACY",
      errors,
      warnings,
      manifest,
    };
  }

  private readStoreZip(archive: Buffer): ZipEntry[] {
    const entries: ZipEntry[] = [];
    let offset = 0;
    while (offset + 4 <= archive.length && archive.readUInt32LE(offset) === 0x04034b50) {
      if (offset + 30 > archive.length) throw new Error("ZIP local header truncated");
      const method = archive.readUInt16LE(offset + 8);
      const compressedSize = archive.readUInt32LE(offset + 18);
      const fileNameLength = archive.readUInt16LE(offset + 26);
      const extraLength = archive.readUInt16LE(offset + 28);
      if (method !== 0) throw new Error("Only store ZIP entries are supported");
      const nameStart = offset + 30;
      const dataStart = nameStart + fileNameLength + extraLength;
      const dataEnd = dataStart + compressedSize;
      if (dataEnd > archive.length) throw new Error("ZIP payload truncated");
      const name = archive.subarray(nameStart, nameStart + fileNameLength).toString("utf8");
      if (!name || name.startsWith("/") || name.includes("..") || name.includes("\\")) {
        throw new Error("Unsafe ZIP entry name");
      }
      entries.push({ name, bytes: archive.subarray(dataStart, dataEnd) });
      offset = dataEnd;
    }
    if (entries.length === 0) throw new Error("No ZIP entries found");
    return entries;
  }
}
