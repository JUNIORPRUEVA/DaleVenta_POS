import { BackupManifest } from "./backup.types";

export type BackupArchiveEntry = {
  name: string;
  bytes: Buffer;
};

export type ParsedBackupArchive = {
  manifest: BackupManifest;
  entries: Map<string, Buffer>;
  moduleRecords: Map<string, unknown[]>;
};

export class BackupArchiveReader {
  parse(archive: Buffer): ParsedBackupArchive {
    const entries = new Map<string, Buffer>();
    for (const entry of this.readStoreZip(archive)) {
      entries.set(entry.name, entry.bytes);
    }

    const manifestBytes = entries.get("manifest.json");
    if (!manifestBytes) {
      throw new Error("manifest.json missing");
    }

    const manifest = JSON.parse(manifestBytes.toString("utf8")) as BackupManifest;
    const moduleRecords = new Map<string, unknown[]>();
    for (const moduleName of manifest.modules ?? []) {
      const bytes = entries.get(`data/${moduleName}.json`);
      if (!bytes) throw new Error(`data/${moduleName}.json missing`);
      const parsed = JSON.parse(bytes.toString("utf8"));
      if (!Array.isArray(parsed)) throw new Error(`data/${moduleName}.json is not an array`);
      moduleRecords.set(moduleName, parsed);
    }

    return { manifest, entries, moduleRecords };
  }

  private readStoreZip(archive: Buffer): BackupArchiveEntry[] {
    const entries: BackupArchiveEntry[] = [];
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
    if (!entries.length) throw new Error("No ZIP entries found");
    return entries;
  }
}
