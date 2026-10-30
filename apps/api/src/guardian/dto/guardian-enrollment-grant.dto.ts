import { IsIn, IsOptional, IsString, Matches, MaxLength } from 'class-validator';
import { GUARDIAN_ENROLLMENT_PLATFORMS } from './guardian-enrollment.dto';

/**
 * Petición de autorización de auto-enrolamiento.
 *
 * La empresa **no** se acepta en el cuerpo: se toma de la sesión autenticada.
 * Cualquier propiedad extra la rechaza el `ValidationPipe` global
 * (`forbidNonWhitelisted`).
 */
export class GuardianEnrollmentGrantDto {
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
