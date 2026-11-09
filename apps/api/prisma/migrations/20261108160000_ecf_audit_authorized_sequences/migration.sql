-- Acción de auditoría para la declaración de numeración autorizada por la DGII.
-- Aditiva: solo agrega un valor al enum existente. No toca filas ni tipos.
-- OJO: el tipo en PostgreSQL se llama `ecf_audit_action` (nombre físico del
-- `@@map` del modelo Prisma), no `EcfAuditAction`.
ALTER TYPE "ecf_audit_action" ADD VALUE IF NOT EXISTS 'DGII_AUTHORIZED_SEQUENCES_DECLARED';
