-- Acción de auditoría para la declaración de numeración autorizada por la DGII.
-- Aditiva: solo agrega un valor al enum existente. No toca filas ni tipos.
ALTER TYPE "EcfAuditAction" ADD VALUE IF NOT EXISTS 'DGII_AUTHORIZED_SEQUENCES_DECLARED';
