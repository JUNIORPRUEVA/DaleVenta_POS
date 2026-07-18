import {
  IsBase64,
  IsOptional,
  IsString,
  IsUUID,
  MaxLength,
} from "class-validator";

export class CreateCotizacionPdfShareLinkDto {
  @IsUUID()
  quotationId!: string;

  @IsBase64()
  pdfBase64!: string;

  @IsOptional()
  @IsString()
  @MaxLength(180)
  fileName?: string;
}
