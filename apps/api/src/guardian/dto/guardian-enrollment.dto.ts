import { IsIn, IsOptional, IsString, Matches, MaxLength, MinLength } from 'class-validator';

export const GUARDIAN_ENROLLMENT_PLATFORMS = [
  'windows',
  'android',
  'ios',
  'web',
  'macos',
  'linux',
] as const;

/**
 * Petición de enrolamiento de una instalación.
 *
 * No admite `companyId`: la empresa la determina el código canjeado. Cualquier
 * propiedad extra es rechazada por el `ValidationPipe` global
 * (`forbidNonWhitelisted`), igual que en la ingesta.
 */
export class GuardianEnrollmentDto {
  /** Código de un solo uso emitido por la plataforma. */
  @IsString()
  @MinLength(24)
  @MaxLength(200)
  code!: string;

  /** Identificador estable de la instalación (no sensible). */
  @IsString()
  @Matches(/^[A-Za-z0-9._:-]{6,120}$/, {
    message: 'installId debe ser un identificador estable (6-120, [A-Za-z0-9._:-])',
  })
  installId!: string;

  @IsOptional()
  @IsIn(GUARDIAN_ENROLLMENT_PLATFORMS as unknown as string[])
  platform?: string;

  @IsOptional()
  @IsString()
  @MaxLength(40)
  appVersion?: string;
}
