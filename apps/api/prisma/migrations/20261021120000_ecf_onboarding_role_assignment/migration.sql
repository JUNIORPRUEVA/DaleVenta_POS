-- Etapa V del instructivo de certificación de Alanube (ticket 4490):
-- asignación de roles en la Oficina Virtual de la DGII.
--
-- Por qué existe este paso: el documento es explícito en que, si la delegación
-- de roles no se completa, la DGII rechaza los comprobantes indicando que el
-- proceso está incompleto. Era el único tramo del procedimiento sin paso propio.
--
-- Compatibilidad: es un valor NUEVO de enum. No renombra ni elimina nada, por lo
-- que los expedientes existentes siguen siendo válidos; simplemente no tendrán
-- fila para esta etapa hasta la próxima lectura, que la creará con su estado
-- inicial (`ensureDefaultSteps` / `ensureSteps` son idempotentes).
--
-- Nota PostgreSQL: `ADD VALUE` puede ejecutarse dentro de la transacción de
-- Prisma en PostgreSQL >= 12 siempre que el valor no se use en la misma
-- transacción. Esta migración no lo usa.

ALTER TYPE "ecf_onboarding_step_key" ADD VALUE IF NOT EXISTS 'ROLE_ASSIGNMENT';
