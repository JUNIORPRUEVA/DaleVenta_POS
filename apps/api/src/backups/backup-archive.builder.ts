import { createHash } from "node:crypto";
import {
  BackupArchiveBuildResult,
  BackupManifest,
  BackupModulePayload,
} from "./backup.types";

type ZipEntry = {
  name: string;
  bytes: Buffer;
  crc32: number;
  offset: number;
};

const crcTable = (() => {
  const table = new Uint32Array(256);
  for (let i = 0; i < 256; i += 1) {
    let c = i;
    for (let k = 0; k < 8; k += 1) {
      c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    }
    table[i] = c >>> 0;
  }
  return table;
})();

export function sha256Hex(bytes: Buffer | string) {
  return createHash("sha256").update(bytes).digest("hex");
}

export function stableJson(value: unknown) {
  return `${JSON.stringify(sortJson(value), null, 2)}\n`;
}

function sortJson(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortJson);
  if (value instanceof Date) return value.toISOString();
  if (typeof value === "bigint") return value.toString();
  if (value && typeof value === "object") {
    const output: Record<string, unknown> = {};
    for (const key of Object.keys(value as Record<string, unknown>).sort()) {
      output[key] = sortJson((value as Record<string, unknown>)[key]);
    }
    return output;
  }
  return value;
}

function crc32(bytes: Buffer) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc = crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

export class BackupArchiveBuilder {
  build(manifest: BackupManifest, modules: BackupModulePayload[]): BackupArchiveBuildResult {
    const files = new Map<string, Buffer>();
    files.set("manifest.json", Buffer.from(stableJson(manifest), "utf8"));
    for (const module of modules) {
      if (!/^data\/[a-z0-9_-]+\.json$/.test(module.fileName)) {
        throw new Error(`Nombre de modulo invalido: ${module.fileName}`);
      }
      files.set(module.fileName, Buffer.from(stableJson(module.records), "utf8"));
    }

    const archive = this.createStoreZip(files);
    return {
      archive,
      manifest,
      modules,
      archiveChecksum: sha256Hex(archive),
    };
  }

  private createStoreZip(files: Map<string, Buffer>) {
    const localParts: Buffer[] = [];
    const entries: ZipEntry[] = [];
    let offset = 0;

    for (const [name, bytes] of [...files.entries()].sort(([a], [b]) => a.localeCompare(b))) {
      const encodedName = Buffer.from(name, "utf8");
      const crc = crc32(bytes);
      const header = Buffer.alloc(30);
      header.writeUInt32LE(0x04034b50, 0);
      header.writeUInt16LE(20, 4);
      header.writeUInt16LE(0x0800, 6);
      header.writeUInt16LE(0, 8);
      header.writeUInt16LE(0, 10);
      header.writeUInt16LE(0, 12);
      header.writeUInt32LE(crc, 14);
      header.writeUInt32LE(bytes.length, 18);
      header.writeUInt32LE(bytes.length, 22);
      header.writeUInt16LE(encodedName.length, 26);
      header.writeUInt16LE(0, 28);
      localParts.push(header, encodedName, bytes);
      entries.push({ name, bytes, crc32: crc, offset });
      offset += header.length + encodedName.length + bytes.length;
    }

    const centralParts: Buffer[] = [];
    let centralSize = 0;
    for (const entry of entries) {
      const encodedName = Buffer.from(entry.name, "utf8");
      const header = Buffer.alloc(46);
      header.writeUInt32LE(0x02014b50, 0);
      header.writeUInt16LE(20, 4);
      header.writeUInt16LE(20, 6);
      header.writeUInt16LE(0x0800, 8);
      header.writeUInt16LE(0, 10);
      header.writeUInt16LE(0, 12);
      header.writeUInt16LE(0, 14);
      header.writeUInt32LE(entry.crc32, 16);
      header.writeUInt32LE(entry.bytes.length, 20);
      header.writeUInt32LE(entry.bytes.length, 24);
      header.writeUInt16LE(encodedName.length, 28);
      header.writeUInt16LE(0, 30);
      header.writeUInt16LE(0, 32);
      header.writeUInt16LE(0, 34);
      header.writeUInt16LE(0, 36);
      header.writeUInt32LE(0, 38);
      header.writeUInt32LE(entry.offset, 42);
      centralParts.push(header, encodedName);
      centralSize += header.length + encodedName.length;
    }

    const end = Buffer.alloc(22);
    end.writeUInt32LE(0x06054b50, 0);
    end.writeUInt16LE(0, 4);
    end.writeUInt16LE(0, 6);
    end.writeUInt16LE(entries.length, 8);
    end.writeUInt16LE(entries.length, 10);
    end.writeUInt32LE(centralSize, 12);
    end.writeUInt32LE(offset, 16);
    end.writeUInt16LE(0, 20);

    return Buffer.concat([...localParts, ...centralParts, end]);
  }
}
