import { IsIn, IsInt, IsNumber, IsObject, IsOptional, IsString, MaxLength, Min, MinLength } from 'class-validator';
export const REVIEW_ACTION_TYPES=['sales.create','cash.open','cash.close','cash.movement'] as const;
export class SubmitRecoveryReviewDto {
  @IsString() @MinLength(1) @MaxLength(300) sourceActionId!:string;
  @IsIn(REVIEW_ACTION_TYPES) actionType!:(typeof REVIEW_ACTION_TYPES)[number];
  @IsString() @MinLength(1) @MaxLength(200) operationId!:string;
  @IsOptional() @IsString() @MaxLength(128) originalSessionId?:string;
  @IsOptional() @IsNumber({allowNaN:false,allowInfinity:false,maxDecimalPlaces:2}) @Min(0) expectedAmount?:number;
  @IsObject() payloadSummary!:Record<string,unknown>;
}
export class RecoveryDecisionDto {
  @IsIn(['NOT_PERFORMED','ESCALATE']) decision!:'NOT_PERFORMED'|'ESCALATE';
  @IsInt() @Min(1) expectedVersion!:number;
  @IsString() @MinLength(10) @MaxLength(2000) note!:string;
  @IsOptional() @IsString() @MaxLength(500) evidenceReference?:string;
}
