import { Injectable } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import * as fs from "node:fs/promises";
import * as path from "node:path";
import { R2Service } from "../storage/r2.service";
import { BackupTypeName } from "./backup.types";

@Injectable()
export class BackupStorageService {
  constructor(
    private readonly r2: R2Service,
    private readonly config: ConfigService,
  ) {}

  buildStorageKey(params: { companyId: string; backupId: string; type: BackupTypeName }) {
    const companyId = params.companyId.trim();
    const backupId = params.backupId.trim();
    if (!/^[0-9a-fA-F-]{36}$/.test(companyId)) {
      throw new Error("Invalid company id for backup storage key");
    }
    if (!/^[0-9a-fA-F-]{36}$/.test(backupId)) {
      throw new Error("Invalid backup id for backup storage key");
    }
    const typeFolder = params.type.toLowerCase();
    return `${this.backupStoragePrefix()}/companies/${companyId}/${typeFolder}/${backupId}.dvbackup`;
  }

  backupStoragePrefix() {
    const raw = (this.config.get<string>("BACKUP_STORAGE_PREFIX") ?? "backups").trim();
    const clean = raw
      .replace(/\\/g, "/")
      .replace(/^\/+|\/+$/g, "")
      .replace(/\/+/g, "/");
    if (!clean || clean.includes("..")) {
      throw new Error("Invalid backup storage prefix");
    }
    if (!/^[-a-zA-Z0-9_./]+$/.test(clean)) {
      throw new Error("Invalid backup storage prefix");
    }
    return clean;
  }

  async putCanonicalBackup(objectKey: string, archive: Buffer) {
    if (this.storageDriver() === "local") {
      const filePath = this.localObjectPath(objectKey);
      await fs.mkdir(path.dirname(filePath), { recursive: true });
      await fs.writeFile(filePath, archive);
      return;
    }
    await this.r2.putObject({
      objectKey,
      body: archive,
      contentType: "application/vnd.daleventas.backup+zip",
    });
  }

  async getCanonicalBackup(objectKey: string) {
    if (this.storageDriver() === "local") {
      return fs.readFile(this.localObjectPath(objectKey));
    }
    const result = await this.r2.getObject(objectKey);
    return result.body;
  }

  async deleteCanonicalBackup(objectKey: string) {
    if (this.storageDriver() === "local") {
      await fs.rm(this.localObjectPath(objectKey), { force: true });
      return;
    }
    await this.r2.deleteObject(objectKey);
  }

  private storageDriver() {
    const raw = (
      this.config.get<string>("BACKUP_STORAGE_DRIVER") ??
      this.config.get<string>("BACKUP_STORAGE_MODE") ??
      "r2"
    )
      .trim()
      .toLowerCase();
    if (raw === "local" || raw === "file" || raw === "filesystem") return "local";
    return "r2";
  }

  private localObjectPath(objectKey: string) {
    const normalizedKey = objectKey.replace(/\\/g, "/").replace(/^\/+/, "");
    if (!normalizedKey || normalizedKey.includes("..")) {
      throw new Error("Invalid local backup object key");
    }

    const root = path.resolve(
      this.config.get<string>("BACKUP_STORAGE_LOCAL_DIR") ?? "/app/backups",
    );
    const filePath = path.resolve(root, normalizedKey);
    if (filePath !== root && !filePath.startsWith(root + path.sep)) {
      throw new Error("Invalid local backup object key");
    }
    return filePath;
  }
}
