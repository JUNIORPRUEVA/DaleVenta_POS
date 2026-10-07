import { Injectable, InternalServerErrorException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { promises as fs } from "node:fs";
import path from "node:path";
import { R2Service } from "../storage/r2.service";

@Injectable()
export class AppReleaseStorageService {
  constructor(
    private readonly config: ConfigService,
    private readonly r2: R2Service,
  ) {}

  provider() {
    return this.localRoot() ? "local" : "r2";
  }

  async deleteObject(storageKey: string) {
    const root = this.localRoot();
    if (!root) {
      return this.r2.deleteObject(storageKey);
    }

    const target = path.resolve(root, storageKey);
    const normalizedRoot = path.resolve(root);
    if (target !== normalizedRoot && target.startsWith(`${normalizedRoot}${path.sep}`)) {
      await fs.unlink(target);
      return { ok: true };
    }

    throw new InternalServerErrorException("Release storage key escapes configured local root.");
  }

  private localRoot() {
    const mode = (this.config.get<string>("FULLPOS_RELEASE_STORAGE_MODE") ?? "").trim().toLowerCase();
    const root = (this.config.get<string>("FULLPOS_RELEASE_STORAGE_ROOT") ?? "").trim();
    return mode === "local" && root ? root : "";
  }
}
