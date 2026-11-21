import { Transform } from 'class-transformer';
import { IsInt, IsString, IsUUID, MaxLength, Min, MinLength } from 'class-validator';

export class AnnulProductDto {
  @IsUUID() operationId!: string;
  @IsInt() @Min(0) expectedVersion!: number;
  @Transform(({value})=>typeof value==='string'?value.trim():value)
  @IsString() @MinLength(10) @MaxLength(500) reason!: string;
}
