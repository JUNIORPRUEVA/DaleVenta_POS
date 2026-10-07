import { HttpException, HttpStatus, Injectable, Logger } from "@nestjs/common";
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

const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX_REQUESTS = 60;
const SHA256_HEX = /^[a-f0-9]{64}$/i;

@Injectable()
export class AppUpdatesService {
  private readonly logger = new Logger(AppUpdatesService.name);
  private readonly rateLimitBuckets = new Map<string, { count: number; resetAt: number }>();

  constructor(private readonly prisma: PrismaService) {}

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
