-- Update payroll entry enum values to new business options
-- Rename existing values to preserve historical data

ALTER TYPE "PayrollEntryType" RENAME VALUE 'FALTA_DIA' TO 'AUSENCIA';
ALTER TYPE "PayrollEntryType" RENAME VALUE 'BONO' TO 'BONIFICACION';
ALTER TYPE "PayrollEntryType" RENAME VALUE 'COMISION' TO 'COMISION_VENTAS';

-- Add new values
ALTER TYPE "PayrollEntryType" ADD VALUE IF NOT EXISTS 'COMISION_SERVICIO';
ALTER TYPE "PayrollEntryType" ADD VALUE IF NOT EXISTS 'PAGO_COMBUSTIBLE';
