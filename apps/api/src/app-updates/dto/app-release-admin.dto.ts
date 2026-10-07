import { Transform, Type } from "class-transformer";
import {
  IsArray,
  IsBoolean,
  IsIn,
  IsInt,
  IsOptional,
  IsString,
  Matches,
  Max,
  Min,
} from "class-validator";
import {
  publicAppUpdateChannels,
  publicAppUpdatePlatforms,
  PublicAppUpdateChannel,
  PublicAppUpdatePlatform,
} from "./check-app-update-query.dto";

export const publicAppReleaseStatuses = ["draft", "published", "revoked"] as const;
export type PublicAppReleaseStatus = (typeof publicAppReleaseStatuses)[number];

const normalizeToken = (value: unknown) =>
  typeof value === "string" ? value.trim().toLowerCase() : value;

const trimString = (value: unknown) =>
  typeof value === "string" ? value.trim() : value;

export class CreateAppReleaseDto {
  @Transform(({ value }) => normalizeToken(value))
  @IsIn(publicAppUpdatePlatforms)
  platform!: PublicAppUpdatePlatform;

  @Transform(({ value }) => normalizeToken(value))
  @IsIn(publicAppUpdateChannels)
  channel!: PublicAppUpdateChannel;

  @Transform(({ value }) => trimString(value))
  @IsString()
  @Matches(/^[0-9A-Za-z.+_-]{1,32}$/)
  version!: string;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  buildNumber!: number;

  @IsOptional()
  @IsBoolean()
  mandatory?: boolean;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  minimumSupportedBuild?: number | null;

  @Transform(({ value }) => trimString(value))
  @IsString()
  fileName!: string;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(Number.MAX_SAFE_INTEGER)
  fileSize!: number;

  @Transform(({ value }) => trimString(value))
  @IsString()
  @Matches(/^[a-fA-F0-9]{64}$/)
  sha256!: string;

  @Transform(({ value }) => trimString(value))
  @IsString()
  downloadUrl!: string;

  @IsOptional()
  @IsArray()
  releaseNotes?: unknown[];

  @IsOptional()
  @Transform(({ value }) => trimString(value))
  @IsString()
  @Matches(/^[a-fA-F0-9]{7,64}$/)
  commitSha?: string | null;

  @IsOptional()
  @IsBoolean()
  signed?: boolean;
}

export class UpdateAppReleaseDto {
  @IsOptional()
  @Transform(({ value }) => normalizeToken(value))
  @IsIn(publicAppUpdatePlatforms)
  platform?: PublicAppUpdatePlatform;

  @IsOptional()
  @Transform(({ value }) => normalizeToken(value))
  @IsIn(publicAppUpdateChannels)
  channel?: PublicAppUpdateChannel;

  @IsOptional()
  @Transform(({ value }) => trimString(value))
  @IsString()
  @Matches(/^[0-9A-Za-z.+_-]{1,32}$/)
  version?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  buildNumber?: number;

  @IsOptional()
  @IsBoolean()
  mandatory?: boolean;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  minimumSupportedBuild?: number | null;

  @IsOptional()
  @Transform(({ value }) => trimString(value))
  @IsString()
  fileName?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(Number.MAX_SAFE_INTEGER)
  fileSize?: number;

  @IsOptional()
  @Transform(({ value }) => trimString(value))
  @IsString()
  @Matches(/^[a-fA-F0-9]{64}$/)
  sha256?: string;

  @IsOptional()
  @Transform(({ value }) => trimString(value))
  @IsString()
  downloadUrl?: string;

  @IsOptional()
  @IsArray()
  releaseNotes?: unknown[];

  @IsOptional()
  @Transform(({ value }) => trimString(value))
  @IsString()
  @Matches(/^[a-fA-F0-9]{7,64}$/)
  commitSha?: string | null;

  @IsOptional()
  @IsBoolean()
  signed?: boolean;
}

export class AppReleaseListQueryDto {
  @IsOptional()
  @Transform(({ value }) => normalizeToken(value))
  @IsIn(publicAppUpdatePlatforms)
  platform?: PublicAppUpdatePlatform;

  @IsOptional()
  @Transform(({ value }) => normalizeToken(value))
  @IsIn(publicAppUpdateChannels)
  channel?: PublicAppUpdateChannel;

  @IsOptional()
  @Transform(({ value }) => normalizeToken(value))
  @IsIn(publicAppReleaseStatuses)
  status?: PublicAppReleaseStatus;
}
