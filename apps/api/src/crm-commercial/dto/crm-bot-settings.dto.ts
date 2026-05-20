import { IsArray, IsBoolean, IsNumber, IsOptional, IsString, MaxLength, Min, Max } from 'class-validator';

export class UpdateCrmBotSettingsDto {
  @IsOptional()
  @IsBoolean()
  botEnabled?: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(8000)
  botSystemPrompt?: string;

  @IsOptional()
  @IsString()
  @MaxLength(4000)
  businessContext?: string;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(60)
  autoReplyDelaySeconds?: number;

  @IsOptional()
  @IsNumber()
  @Min(0)
  @Max(1440)
  humanTakeoverMinutes?: number;

  @IsOptional()
  @IsString()
  @MaxLength(20)
  botDefaultStatus?: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  excludedNumbers?: string[];

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  allowedChannels?: string[];
}

export class BotPauseConversationDto {
  @IsOptional()
  @IsString()
  @MaxLength(500)
  reason?: string;
}

export class BotSuggestReplyDto {
  @IsOptional()
  @IsString()
  @MaxLength(4000)
  lastCustomerMessage?: string;
}
