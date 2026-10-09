import { Transform, Type } from "class-transformer";
import { IsIn, IsInt, IsString, Matches, Min } from "class-validator";

export const publicAppUpdatePlatforms = ["windows", "android", "ios"] as const;
export const publicAppUpdateChannels = ["stable", "beta"] as const;

export type PublicAppUpdatePlatform = (typeof publicAppUpdatePlatforms)[number];
export type PublicAppUpdateChannel = (typeof publicAppUpdateChannels)[number];

const normalizeToken = (value: unknown) =>
  typeof value === "string" ? value.trim().toLowerCase() : value;

export class CheckAppUpdateQueryDto {
  @Transform(({ value }) => normalizeToken(value))
  @IsIn(publicAppUpdatePlatforms)
  platform!: PublicAppUpdatePlatform;

  @Transform(({ value }) => normalizeToken(value))
  @IsIn(publicAppUpdateChannels)
  channel!: PublicAppUpdateChannel;

  @Transform(({ value }) => (typeof value === "string" ? value.trim() : value))
  @IsString()
  @Matches(/^[0-9A-Za-z.+_-]{1,32}$/)
  version!: string;

  @Type(() => Number)
  @IsInt()
  @Min(0)
  build!: number;
}
