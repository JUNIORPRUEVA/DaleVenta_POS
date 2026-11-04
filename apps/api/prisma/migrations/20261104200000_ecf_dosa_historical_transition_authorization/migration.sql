-- Autorización explícita para transicionar un expediente histórico
-- reconciliado (por ejemplo, el Intento 1 de FULLTECH SRL).
--
-- Migración ADITIVA: solo agrega un valor al enum de auditoría. No modifica
-- filas, no elimina historial y no crea autorizaciones por sí sola.
ALTER TYPE "ecf_audit_action" ADD VALUE IF NOT EXISTS 'INTENT_HISTORICAL_TRANSITION_AUTHORIZED';
