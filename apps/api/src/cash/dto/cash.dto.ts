import { Type } from 'class-transformer';
import { IsIn, IsNumber, IsOptional, IsString, IsUUID, MaxLength, Min } from 'class-validator';

export class OpenCashSessionDto {
  @Type(() => Number)
  @IsNumber()
  @Min(0)
  openingAmount!: number;

  @IsOptional()
  @IsString()
  note?: string;

  @IsOptional()
  @IsUUID()
  terminalId?: string;

  @IsOptional()
  @IsString()
  deviceFingerprint?: string;

  /**
   * Identidad que el cliente asigna al turno que está abriendo.
   *
   * Un turno abierto OFFLINE existe sólo en el dispositivo hasta que se
   * sincroniza. Si el usuario lo cierra estando offline, el cierre debe
   * apuntar a ESA identidad y no a "el turno abierto actual" (que puede ser
   * otro). Enviar el `clientSessionId` hace que el turno abierto offline tenga
   * una identidad real (UUID) reutilizable por el cierre offline, y que un
   * replay de apertura sea idempotente (devuelve el mismo turno, nunca crea
   * otro). Es opcional para no romper clientes que no lo envían.
   */
  @IsOptional()
  @IsUUID()
  clientSessionId?: string;
}

export class CloseCashSessionDto {
  /**
   * Identidad del turno que se desea cerrar (el `shiftId` que estaba abierto
   * cuando el usuario inició el cierre).
   *
   * El backend SIEMPRE cierra exactamente esta sesión; jamás sustituye el id
   * por "el turno abierto actual" ni reutiliza el `closingAmount` contra otra
   * sesión. Si falta, se aplica la política legacy controlada
   * (`CASH_CLOSE_LEGACY_MODE`, por defecto rechazo controlado) para que un
   * replay offline antiguo no pueda cerrar un turno posterior.
   */
  @IsOptional()
  @IsString()
  @MaxLength(64)
  sessionId?: string;

  @Type(() => Number)
  @IsNumber()
  @Min(0)
  closingAmount!: number;

  @IsOptional()
  @IsString()
  note?: string;
}

export class CreateCashMovementDto {
  @IsIn(['IN', 'OUT'])
  type!: 'IN' | 'OUT';

  @Type(() => Number)
  @IsNumber()
  @Min(0.01)
  amount!: number;

  /**
   * Turno al que pertenece el movimiento. Un movimiento encolado offline debe
   * aplicarse al turno que lo originó, nunca a "el turno abierto actual".
   * Opcional por compatibilidad con clientes que aún no lo envían.
   */
  @IsOptional()
  @IsString()
  @MaxLength(64)
  sessionId?: string;

  @IsOptional()
  @IsString()
  reason?: string;

  @IsOptional()
  @IsIn(['expense', 'owner_draw', 'transfer'])
  movementType?: 'expense' | 'owner_draw' | 'transfer';

  @IsOptional()
  affectsProfit?: boolean;
}
