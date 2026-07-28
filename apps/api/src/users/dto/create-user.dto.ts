import { Role } from '@prisma/client';
import { IsArray, IsBoolean, IsDateString, IsEmail, IsEnum, IsInt, IsObject, IsOptional, IsString, Matches, MinLength } from 'class-validator';

export class CreateUserDto {
  @IsEmail()
  email!: string;

  @IsString()
  @MinLength(8)
  password!: string;

  @IsString()
  nombreCompleto!: string;

  @IsString()
  telefono!: string;

  @IsString()
  @Matches(/^\d+$/, { message: 'numeroFlota debe ser numérico' })
  numeroFlota!: string;

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

  @IsInt()
  edad!: number;

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

  @IsEnum(Role)
  role!: Role;

  @IsOptional()
  @IsBoolean()
  blocked?: boolean;
}
