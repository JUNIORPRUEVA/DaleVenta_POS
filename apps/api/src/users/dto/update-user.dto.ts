import { Role } from '@prisma/client';
import { IsArray, IsBoolean, IsDateString, IsEmail, IsEnum, IsInt, IsObject, IsOptional, IsString, Matches, MinLength } from 'class-validator';

export class UpdateUserDto {
  @IsOptional()
  @IsEmail()
  email?: string;

  @IsOptional()
  @IsString()
  @MinLength(8)
  password?: string;

  @IsOptional()
  @IsString()
  nombreCompleto?: string;

  @IsOptional()
  @IsString()
  telefono?: string;

  @IsOptional()
  @IsString()
  @Matches(/^\d+$/, { message: 'numeroFlota debe ser numérico' })
  numeroFlota?: string;

  @IsOptional()
  @IsString()
  telefonoFamiliar?: string;

  @IsOptional()
  @IsString()
  cedula?: string;

  @IsOptional()
  @IsString()
  fotoCedulaUrl?: string;

  @IsOptional()
  @IsString()
  fotoLicenciaUrl?: string;

  @IsOptional()
  @IsString()
  fotoPersonalUrl?: string;

  @IsOptional()
  @IsInt()
  edad?: number;

  @IsOptional()
  @IsDateString()
  fechaIngreso?: string;

  @IsOptional()
  @IsDateString()
  fechaNacimiento?: string;

  @IsOptional()
  @IsString()
  cuentaNominaPreferencial?: string;

  @IsOptional()
  @IsString()
  workContractJobTitle?: string;

  @IsOptional()
  @IsString()
  workContractSalary?: string;

  @IsOptional()
  @IsString()
  workContractPaymentFrequency?: string;

  @IsOptional()
  @IsString()
  workContractPaymentMethod?: string;

  @IsOptional()
  @IsString()
  workContractWorkSchedule?: string;

  @IsOptional()
  @IsString()
  workContractWorkLocation?: string;

  @IsOptional()
  @IsObject()
  workContractClauseOverrides?: Record<string, string>;

  @IsOptional()
  @IsString()
  workContractCustomClauses?: string;

  @IsOptional()
  @IsDateString()
  workContractStartDate?: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  habilidades?: string[];

  @IsOptional()
  @IsObject()
  userPermissions?: Record<string, boolean>;

  @IsOptional()
  @IsBoolean()
  tieneHijos?: boolean;

  @IsOptional()
  @IsBoolean()
  estaCasado?: boolean;

  @IsOptional()
  @IsBoolean()
  casaPropia?: boolean;

  @IsOptional()
  @IsBoolean()
  vehiculo?: boolean;

  @IsOptional()
  @IsBoolean()
  licenciaConducir?: boolean;

  @IsOptional()
  @IsEnum(Role)
  role?: Role;

  @IsOptional()
  @IsBoolean()
  blocked?: boolean;
}
