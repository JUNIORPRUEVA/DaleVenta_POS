import { IsString, Matches, MaxLength, MinLength } from 'class-validator';

export class SupportReplyDto {
  @IsString()
  @MinLength(1)
  @MaxLength(4000)
  message!: string;

  @IsString()
  @Matches(/^[\w-]{1,80}$/)
  requestId!: string;
}
