import {
  BadRequestException,
  ConflictException,
  HttpException,
  HttpStatus,
  Injectable,
  Logger,
  NotFoundException,
} from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import {
  AppReleaseChannel,
  AppReleasePlatform,
  AppReleaseStatus,
  Prisma,
} from "@prisma/client";
import { PrismaService } from "../prisma/prisma.service";
import { AppUpdateManifestDto } from "./dto/app-update-manifest.dto";
import {
  CheckAppUpdateQueryDto,
  PublicAppUpdateChannel,
  PublicAppUpdatePlatform,
} from "./dto/check-app-update-query.dto";
import {
  AppReleaseListQueryDto,
  CreateAppReleaseDto,
  PublicAppReleaseStatus,
  UpdateAppReleaseDto,
} from "./dto/app-release-admin.dto";

type AppReleaseForManifest = {
  version: string;
  buildNumber: number;
  fileName: string;
  fileSize: bigint | number;
  sha256: string;
  downloadUrl: string;
  mandatory: boolean;
  minimumSupportedBuild: number | null;
  releaseNotes: Prisma.JsonValue;
  publishedAt: Date | null;
};

type AppReleaseForAdmin = {
  id: string;
  platform: AppReleasePlatform;
  channel: AppReleaseChannel;
  version: string;
  buildNumber: number;
  status: AppReleaseStatus;
  mandatory: boolean;
  minimumSupportedBuild: number | null;
  fileName: string;
  fileSize: bigint | number;
  sha256: string;
  downloadUrl: string;
  releaseNotes: Prisma.JsonValue;
  publishedAt: Date | null;
  revokedAt: Date | null;
  commitSha: string | null;
  signed: boolean;
  createdAt: Date;
  updatedAt: Date;
};

type NormalizedAppReleaseInput = {
  platform: AppReleasePlatform;
  channel: AppReleaseChannel;
  version: string;
  buildNumber: number;
  mandatory: boolean;
  minimumSupportedBuild: number | null;
  fileName: string;
  fileSize: bigint;
  sha256: string;
  downloadUrl: string;
  releaseNotes: Prisma.InputJsonValue;
  commitSha: string | null;
  signed: boolean;
  status: AppReleaseStatus;
};

const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX_REQUESTS = 60;
const SHA256_HEX = /^[a-f0-9]{64}$/i;
const SAFE_FILE_NAME = /^[A-Za-z0-9][A-Za-z0-9._+ -]{0,254}$/;

@Injectable()
export class AppUpdatesService {
  private readonly logger = new Logger(AppUpdatesService.name);
  private readonly rateLimitBuckets = new Map<string, { count: number; resetAt: number }>();

  constructor(
    private readonly prisma: PrismaService,
    private readonly config: ConfigService,
  ) {}

  async createRelease(dto: CreateAppReleaseDto) {
    const data = this.toCreateData(dto);
    this.validateReleaseMetadata(data, { requireSigned: false });
    await this.ensureBuildIsUnique(data.platform, data.channel, data.buildNumber);

    const release = await this.prisma.appRelease.create({ data });
    this.logger.log(
      `app_release_created id=${release.id} platform=${release.platform} channel=${release.channel} build=${release.buildNumber}`,
    );
    return this.toAdminDto(release);
  }

  async listReleases(query: AppReleaseListQueryDto) {
    const where: Prisma.AppReleaseWhereInput = {};
    if (query.platform) where.platform = this.toPlatform(query.platform);
    if (query.channel) where.channel = this.toChannel(query.channel);
    if (query.status) where.status = this.toStatus(query.status);

    const releases = await this.prisma.appRelease.findMany({
      where,
      orderBy: [{ platform: "asc" }, { channel: "asc" }, { buildNumber: "desc" }],
    });
    return releases.map((release) => this.toAdminDto(release));
  }

  async getRelease(id: string) {
    const release = await this.prisma.appRelease.findUnique({ where: { id } });
    if (!release) throw new NotFoundException("Release de actualización no encontrado.");
    return this.toAdminDto(release);
  }

  async updateRelease(id: string, dto: UpdateAppReleaseDto) {
    const current = await this.prisma.appRelease.findUnique({ where: { id } });
    if (!current) throw new NotFoundException("Release de actualización no encontrado.");
    if (current.status !== AppReleaseStatus.DRAFT) {
      throw new BadRequestException("Solo se pueden editar releases en estado DRAFT.");
    }

    const merged = this.mergeRelease(current, dto);
    this.validateReleaseMetadata(merged, { requireSigned: false });
    await this.ensureBuildIsUnique(merged.platform, merged.channel, merged.buildNumber, id);

    const release = await this.prisma.appRelease.update({
      where: { id },
      data: this.toUpdateData(dto),
    });
    this.logger.log(
      `app_release_updated id=${release.id} platform=${release.platform} channel=${release.channel} build=${release.buildNumber}`,
    );
    return this.toAdminDto(release);
  }

  async publishRelease(id: string) {
    const release = await this.prisma.$transaction(async (tx) => {
      const current = await tx.appRelease.findUnique({ where: { id } });
      if (!current) throw new NotFoundException("Release de actualización no encontrado.");
      if (current.status === AppReleaseStatus.PUBLISHED) {
        throw new BadRequestException("El release ya fue publicado.");
      }
      if (current.status === AppReleaseStatus.REVOKED) {
        throw new BadRequestException("Un release revocado no puede publicarse.");
      }

      this.validateReleaseMetadata(current, {
        requireSigned: this.requiresSignedReleases(),
      });

      const result = await tx.appRelease.updateMany({
        where: { id, status: AppReleaseStatus.DRAFT },
        data: {
          status: AppReleaseStatus.PUBLISHED,
          publishedAt: new Date(),
          revokedAt: null,
        },
      });
      if (result.count !== 1) {
        throw new ConflictException("El release cambió de estado durante la publicación.");
      }

      return tx.appRelease.findUniqueOrThrow({ where: { id } });
    });

    this.logger.log(
      `app_release_published id=${release.id} platform=${release.platform} channel=${release.channel} build=${release.buildNumber}`,
    );
    return this.toAdminDto(release);
  }

  async revokeRelease(id: string) {
    const release = await this.prisma.$transaction(async (tx) => {
      const current = await tx.appRelease.findUnique({ where: { id } });
      if (!current) throw new NotFoundException("Release de actualización no encontrado.");
      if (current.status === AppReleaseStatus.DRAFT) {
        throw new BadRequestException("Un release DRAFT no puede revocarse.");
      }
      if (current.status === AppReleaseStatus.REVOKED) {
        throw new BadRequestException("El release ya fue revocado.");
      }

      const result = await tx.appRelease.updateMany({
        where: { id, status: AppReleaseStatus.PUBLISHED },
        data: {
          status: AppReleaseStatus.REVOKED,
          revokedAt: new Date(),
        },
      });
      if (result.count !== 1) {
        throw new ConflictException("El release cambió de estado durante la revocación.");
      }

      return tx.appRelease.findUniqueOrThrow({ where: { id } });
    });

    this.logger.log(
      `app_release_revoked id=${release.id} platform=${release.platform} channel=${release.channel} build=${release.buildNumber}`,
    );
    return this.toAdminDto(release);
  }

  async check(
    query: CheckAppUpdateQueryDto,
    clientKey = "unknown",
  ): Promise<AppUpdateManifestDto> {
    this.consumeRateLimit(clientKey);

    const platform = this.toPlatform(query.platform);
    const channel = this.toChannel(query.channel);

    const releases = await this.prisma.appRelease.findMany({
      where: {
        platform,
        channel,
        status: AppReleaseStatus.PUBLISHED,
      },
      orderBy: { buildNumber: "desc" },
      select: {
        version: true,
        buildNumber: true,
        fileName: true,
        fileSize: true,
        sha256: true,
        downloadUrl: true,
        mandatory: true,
        minimumSupportedBuild: true,
        releaseNotes: true,
        publishedAt: true,
      },
    });

    const selected = releases.find(
      (release) => release.buildNumber > query.build && this.isUsableRelease(release),
    );

    if (!selected) {
      this.logResult(query, null, false);
      return { updateAvailable: false };
    }

    this.logResult(query, selected.buildNumber, true);
    return {
      updateAvailable: true,
      version: selected.version,
      buildNumber: selected.buildNumber,
      fileName: selected.fileName,
      fileSize: Number(selected.fileSize),
      sha256: selected.sha256,
      downloadUrl: selected.downloadUrl,
      mandatory: selected.mandatory,
      minimumSupportedBuild: selected.minimumSupportedBuild,
      releaseNotes: Array.isArray(selected.releaseNotes) ? selected.releaseNotes : [],
      publishedAt: selected.publishedAt!.toISOString(),
    };
  }

  private consumeRateLimit(key: string) {
    const now = Date.now();
    const bucket = this.rateLimitBuckets.get(key);

    if (!bucket || bucket.resetAt <= now) {
      this.rateLimitBuckets.set(key, { count: 1, resetAt: now + RATE_LIMIT_WINDOW_MS });
      this.pruneRateLimitBuckets(now);
      return;
    }

    bucket.count += 1;
    if (bucket.count > RATE_LIMIT_MAX_REQUESTS) {
      throw new HttpException(
        "Demasiadas consultas de actualización.",
        HttpStatus.TOO_MANY_REQUESTS,
      );
    }
  }

  private pruneRateLimitBuckets(now: number) {
    if (this.rateLimitBuckets.size < 1000) return;
    for (const [key, bucket] of this.rateLimitBuckets) {
      if (bucket.resetAt <= now) this.rateLimitBuckets.delete(key);
    }
  }

  private isUsableRelease(release: AppReleaseForManifest) {
    const fileSize =
      typeof release.fileSize === "bigint" ? Number(release.fileSize) : release.fileSize;

    const valid =
      release.downloadUrl.trim().startsWith("https://") &&
      SHA256_HEX.test(release.sha256) &&
      Number.isSafeInteger(fileSize) &&
      fileSize > 0 &&
      release.fileName.trim().length > 0 &&
      release.publishedAt !== null;

    if (!valid) {
      this.logger.error(
        `app_update_release_unusable build=${release.buildNumber} shaValid=${SHA256_HEX.test(
          release.sha256,
        )} https=${release.downloadUrl.trim().startsWith("https://")} fileSize=${String(
          release.fileSize,
        )} fileNamePresent=${release.fileName.trim().length > 0} publishedAtPresent=${
          release.publishedAt !== null
        }`,
      );
    }

    return valid;
  }

  private toPlatform(platform: PublicAppUpdatePlatform) {
    const map: Record<PublicAppUpdatePlatform, AppReleasePlatform> = {
      windows: AppReleasePlatform.WINDOWS,
      android: AppReleasePlatform.ANDROID,
      ios: AppReleasePlatform.IOS,
    };
    return map[platform];
  }

  private toChannel(channel: PublicAppUpdateChannel) {
    const map: Record<PublicAppUpdateChannel, AppReleaseChannel> = {
      stable: AppReleaseChannel.STABLE,
      beta: AppReleaseChannel.BETA,
    };
    return map[channel];
  }

  private toStatus(status: PublicAppReleaseStatus) {
    const map: Record<PublicAppReleaseStatus, AppReleaseStatus> = {
      draft: AppReleaseStatus.DRAFT,
      published: AppReleaseStatus.PUBLISHED,
      revoked: AppReleaseStatus.REVOKED,
    };
    return map[status];
  }

  private toPublicPlatform(platform: AppReleasePlatform): PublicAppUpdatePlatform {
    const map: Record<AppReleasePlatform, PublicAppUpdatePlatform> = {
      WINDOWS: "windows",
      ANDROID: "android",
      IOS: "ios",
    };
    return map[platform];
  }

  private toPublicChannel(channel: AppReleaseChannel): PublicAppUpdateChannel {
    const map: Record<AppReleaseChannel, PublicAppUpdateChannel> = {
      STABLE: "stable",
      BETA: "beta",
    };
    return map[channel];
  }

  private toPublicStatus(status: AppReleaseStatus): PublicAppReleaseStatus {
    const map: Record<AppReleaseStatus, PublicAppReleaseStatus> = {
      DRAFT: "draft",
      PUBLISHED: "published",
      REVOKED: "revoked",
    };
    return map[status];
  }

  private toCreateData(dto: CreateAppReleaseDto): NormalizedAppReleaseInput {
    return {
      platform: this.toPlatform(dto.platform),
      channel: this.toChannel(dto.channel),
      version: dto.version,
      buildNumber: dto.buildNumber,
      mandatory: dto.mandatory ?? false,
      minimumSupportedBuild: dto.minimumSupportedBuild ?? null,
      fileName: dto.fileName,
      fileSize: BigInt(dto.fileSize),
      sha256: dto.sha256,
      downloadUrl: dto.downloadUrl,
      releaseNotes: (dto.releaseNotes ?? []) as Prisma.InputJsonValue,
      commitSha: dto.commitSha || null,
      signed: dto.signed ?? false,
      status: AppReleaseStatus.DRAFT,
    };
  }

  private toUpdateData(dto: UpdateAppReleaseDto): Prisma.AppReleaseUpdateInput {
    const data: Prisma.AppReleaseUpdateInput = {};
    if (dto.platform !== undefined) data.platform = this.toPlatform(dto.platform);
    if (dto.channel !== undefined) data.channel = this.toChannel(dto.channel);
    if (dto.version !== undefined) data.version = dto.version;
    if (dto.buildNumber !== undefined) data.buildNumber = dto.buildNumber;
    if (dto.mandatory !== undefined) data.mandatory = dto.mandatory;
    if (dto.minimumSupportedBuild !== undefined) {
      data.minimumSupportedBuild = dto.minimumSupportedBuild;
    }
    if (dto.fileName !== undefined) data.fileName = dto.fileName;
    if (dto.fileSize !== undefined) data.fileSize = BigInt(dto.fileSize);
    if (dto.sha256 !== undefined) data.sha256 = dto.sha256;
    if (dto.downloadUrl !== undefined) data.downloadUrl = dto.downloadUrl;
    if (dto.releaseNotes !== undefined) data.releaseNotes = dto.releaseNotes as Prisma.InputJsonValue;
    if (dto.commitSha !== undefined) data.commitSha = dto.commitSha || null;
    if (dto.signed !== undefined) data.signed = dto.signed;
    return data;
  }

  private mergeRelease(current: AppReleaseForAdmin, dto: UpdateAppReleaseDto) {
    return {
      ...current,
      platform: dto.platform ? this.toPlatform(dto.platform) : current.platform,
      channel: dto.channel ? this.toChannel(dto.channel) : current.channel,
      version: dto.version ?? current.version,
      buildNumber: dto.buildNumber ?? current.buildNumber,
      mandatory: dto.mandatory ?? current.mandatory,
      minimumSupportedBuild:
        dto.minimumSupportedBuild === undefined
          ? current.minimumSupportedBuild
          : dto.minimumSupportedBuild,
      fileName: dto.fileName ?? current.fileName,
      fileSize: dto.fileSize === undefined ? current.fileSize : BigInt(dto.fileSize),
      sha256: dto.sha256 ?? current.sha256,
      downloadUrl: dto.downloadUrl ?? current.downloadUrl,
      releaseNotes: dto.releaseNotes ?? current.releaseNotes,
      commitSha: dto.commitSha === undefined ? current.commitSha : dto.commitSha || null,
      signed: dto.signed ?? current.signed,
    };
  }

  private async ensureBuildIsUnique(
    platform: AppReleasePlatform,
    channel: AppReleaseChannel,
    buildNumber: number,
    exceptId?: string,
  ) {
    const existing = await this.prisma.appRelease.findFirst({
      where: {
        platform,
        channel,
        buildNumber,
        ...(exceptId ? { id: { not: exceptId } } : {}),
      },
      select: { id: true },
    });
    if (existing) {
      throw new ConflictException("Ya existe un release para ese platform/channel/build.");
    }
  }

  private validateReleaseMetadata(
    release: {
      buildNumber: number;
      fileSize: bigint | number;
      sha256: string;
      downloadUrl: string;
      fileName: string;
      version: string;
      commitSha?: string | null;
      signed: boolean;
    },
    options: { requireSigned: boolean },
  ) {
    const fileSize =
      typeof release.fileSize === "bigint" ? Number(release.fileSize) : release.fileSize;

    if (!Number.isInteger(release.buildNumber) || release.buildNumber <= 0) {
      throw new BadRequestException("buildNumber debe ser entero y mayor que cero.");
    }
    if (!Number.isSafeInteger(fileSize) || fileSize <= 0) {
      throw new BadRequestException("fileSize debe ser entero y mayor que cero.");
    }
    if (!SHA256_HEX.test(release.sha256)) {
      throw new BadRequestException("sha256 debe tener 64 caracteres hexadecimales.");
    }
    if (!this.isHttpsUrl(release.downloadUrl)) {
      throw new BadRequestException("downloadUrl debe ser HTTPS.");
    }
    if (!this.isSafeFileName(release.fileName)) {
      throw new BadRequestException("fileName no es seguro.");
    }
    if (!/^[0-9A-Za-z.+_-]{1,32}$/.test(release.version.trim())) {
      throw new BadRequestException("version no es válida.");
    }
    if (release.commitSha && !/^[a-fA-F0-9]{7,64}$/.test(release.commitSha)) {
      throw new BadRequestException("commitSha no es válido.");
    }
    if (options.requireSigned && !release.signed) {
      throw new BadRequestException("La política actual exige releases firmados.");
    }
  }

  private isHttpsUrl(value: string) {
    try {
      const parsed = new URL(value);
      return parsed.protocol === "https:";
    } catch {
      return false;
    }
  }

  private isSafeFileName(value: string) {
    const fileName = value.trim();
    return (
      SAFE_FILE_NAME.test(fileName) &&
      !fileName.includes("..") &&
      !fileName.includes("/") &&
      !fileName.includes("\\") &&
      !/^[A-Za-z]:/.test(fileName)
    );
  }

  private requiresSignedReleases() {
    const raw = this.config.get<string>("REQUIRE_SIGNED_APP_RELEASES");
    if (raw !== undefined && raw.trim().length > 0) {
      return ["1", "true", "yes", "on"].includes(raw.trim().toLowerCase());
    }
    return (this.config.get<string>("NODE_ENV") ?? process.env.NODE_ENV ?? "")
      .trim()
      .toLowerCase() === "production";
  }

  private toAdminDto(release: AppReleaseForAdmin) {
    return {
      id: release.id,
      platform: this.toPublicPlatform(release.platform),
      channel: this.toPublicChannel(release.channel),
      version: release.version,
      buildNumber: release.buildNumber,
      status: this.toPublicStatus(release.status),
      mandatory: release.mandatory,
      minimumSupportedBuild: release.minimumSupportedBuild,
      fileName: release.fileName,
      fileSize: Number(release.fileSize),
      sha256: release.sha256,
      downloadUrl: release.downloadUrl,
      releaseNotes: Array.isArray(release.releaseNotes) ? release.releaseNotes : [],
      publishedAt: release.publishedAt?.toISOString() ?? null,
      revokedAt: release.revokedAt?.toISOString() ?? null,
      commitSha: release.commitSha,
      signed: release.signed,
      createdAt: release.createdAt.toISOString(),
      updatedAt: release.updatedAt.toISOString(),
    };
  }

  private logResult(
    query: CheckAppUpdateQueryDto,
    selectedBuild: number | null,
    updateAvailable: boolean,
  ) {
    this.logger.log(
      `app_update_check platform=${query.platform} channel=${query.channel} currentBuild=${query.build} selectedBuild=${
        selectedBuild ?? "none"
      } result=${updateAvailable ? "update" : "none"}`,
    );
  }
}
