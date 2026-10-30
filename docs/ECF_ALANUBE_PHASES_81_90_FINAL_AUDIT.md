# Fullpos Cloud — auditoría fases 81–90: integridad local E34

Fecha: 2026-10-14. Worktree FULLPOS-ECF-ALANUBE, feature/ecf-alanube.
HEAD conservado: 6b3e38ed57bc53f9a55e66cf2eccf315afffd3f1.
Hechos verificados en código/pruebas indicados abajo. Ninguna evidencia sintética
constituye aceptación real de Alanube/DGII.

| Fase | Estado | Implementación | Pruebas | Pendientes |
| --- | --- | --- | --- | --- |
| 81 | PASS | Auditoría real: FK original solo por id, e-NCF solo en mapper y resumen insuficiente. Relación compuesta tenant, snapshot y ledger diseñados. | Inspección y auditoría UAT inicial sin documentos ni relaciones cruzadas. | Ingestión oficial futura. |
| 82 | PASS local | EcfE34CreditService exige tenant autenticado, original E31/E32 aceptado, snapshot y log de evidencia, moneda/referencia/fecha consistentes. | Original válido, inexistente, otra empresa, sin evidencia, estados comerciales/invalidación y tipo incorrecto. | Autenticidad externa de la evidencia no demostrada por fixtures. |
| 83 | PASS local | Decimal; original, aplicado, reservado, desconocido, disponible, rechazado y cancelado separados. Solicitado proviene del total de la nota. | Cálculo exacto y precisión; no liberar UNKNOWN ni contar DRAFT como aplicado. | Política conservadora local, no certificación legal. |
| 84 | PASS local | Parciales, completas, acumuladas, reintentos y rechazo con evidencia; inmutabilidad. | Casos A–J cubiertos en UAT. | Conceptos/tasas y criterios legales completos. |
| 85 | PASS | Locks transaccionales ordenados, unique por nota, trigger de presupuesto y auditoría automática. | Carreras por servicio, ocho reintentos y dos inserts directos simultáneos: un ganador incompatible. | Orquestación de sender no autorizada. |
| 86 | PASS UAT | Dos migraciones compatibles y respaldadas; nullable snapshot sin backfill inventado. | Validate/status, ensayo SQL con rollback e integridad posterior. | No migradas a producción. |
| 87 | PARTIAL | Reutiliza mapper/Ajv y reglas oficiales disponibles; barrera E34 adicional incondicional. | Contratos E34 y notas/referencias inválidas cubiertos. | DGII integral, impuestos/conceptos del original, certificación y garantías externas. |
| 88 | PASS | 18 tests unitarios nuevos + 28 E34 PostgreSQL, además de regresiones existentes. | 180 e-CF; 40 PostgreSQL. | Evidencia externa real no ejecutada ni autorizada. |
| 89 | PASS local | Regresión, build/tsc, validate/status, secretos, tenant, estados e idempotencia. | 919 backend; smoke compilado; cero sobrepresupuestos/cruces detectados. | Drift histórico ajeno al bloque nuevo documentado. |
| 90 | PASS | Contexto, continuidad, matriz y plan actualizados. | Diff y evidencia técnica revisados. | Primera emisión NO-GO. |

## Relaciones e identificadores

Antes: originalDocumentId era FK global por id; payloadSummary solo incluía
hasReference, sin e-NCF/fecha/tipo original; no saldo monetario ni reserva.
No se encontraron call sites de emisión activos. Controller sigue ofreciendo
solo configuración/onboarding/status, con JWT/RolesGuard/permisos existentes.

Ahora: id interno UUID identifica fila; externalProviderId es identificador
del proveedor separado; externalDocumentNumber es referencia fiscal/e-NCF.
El snapshot debe coincidir con esa referencia, y el resumen de la nota con el
e-NCF/fecha/tipo del original. No se busca un original equiparando esos IDs.
Se preservó la identidad v2 de fases61–64 y su unique por operación/empresa.

FK original y reservas referencian (companyId,id). Unicidad de e-NCF por empresa
impide duplicar el presupuesto mediante dos filas con el mismo documento fiscal.
NULL permite coexistir borradores no numerados. Índice no asigna/reserva/consume
numeración; el servicio no llama NcfSequence ni a un proveedor.

## Evidencia y validación del original

fiscalSnapshot nullable conserva total, DOP, issueDate, issuerRnc, encf,
evidenceRef y evidenceHash. No deriva estos datos de pagos, CxC ni caja.
El estado debe ser DGII_ACCEPTED y debe existir log del mismo tenant/documento
con evidenciaRef/hash coincidentes. PROVIDER_ACCEPTED, HTTP y estados comerciales
no bastan. Solo E31/E32 originales en el subconjunto local soportado: no se
afirma que otros tipos estén legalmente prohibidos en todos los casos DGII.

El snapshot/e-NCF/provider ID quedan inmutables una vez fijada la evidencia.
La nota necesita referencia consistente, fecha no anterior, moneda compatible,
importe positivo canónico a centavos y estado local válido. Sin prueba, se bloquea.

**Límite de confianza:** ref/hash y log son evidencia persistida interna, no una
verificación automática de firma o de autenticidad DGII. No se creó un endpoint
que permita al cliente cargarlos. El ingestor autenticado, verificación del
artefacto/hash/firma y autorización de operadores siguen pendientes. Los tests
crean explícitamente estados/evidencias ficticios uat://synthetic-not-dgii/*.
Jamás se reportan como aceptación externa. La emisión E34 permanece bloqueada.

## Saldo y reservas

Cada nota tiene una única reserva monetaria vinculada al original y al tenant.
amount es el importe solicitado derivado del total del resumen interno de la
nota, no un saldo comercial. Disponible = total original − APPLIED − RESERVED
− UNKNOWN_RESULT. REJECTED y CANCELLED se informan separadamente y no consumen
saldo. DRAFT sin reserva no se cuenta; una nota no localmente validada no reserva.

Decimal de Prisma y utilidades existentes; sin float. La reserva rechaza
fracciones de centavo (1.005), negativos, cero y notación ambigua en vez de
redondear silenciosamente. Es una restricción local conservadora; no cambia
ROUND_HALF_UP del núcleo ni del POS ni inventa un requisito DGII general.

RESERVED→UNKNOWN_RESULT conserva importe indefinidamente. SUBMITTING/SEND_IN_PROGRESS
no libera por cancelación local; UNKNOWN no se cancela. APPLIED/REJECTED solo con
estado fiscal, snapshot y log coincidentes. APPLIED no es un estado inferido de
HTTP. Cancelación solo local previa al envío; estados finales no se revierten.
No TTL, reintento fiscal ni liberación automática por timeout/reinicio.

Notas aceptadas/enviadas vinculadas al original sin ledger bloquean el cálculo
en el servicio: E34_UNTRACKED_CREDITS_REQUIRE_REVIEW. No se inventa un backfill.
Por ahora saldo global no prueba límites por línea, tasa ni cantidades del
original: esos datos/reglas y su evidencia deben completarse antes de emitir.

## Concurrencia e historial

Prisma interactive transactions; documentos original/nota bloqueados con
SELECT FOR UPDATE en orden estable por UUID, siempre filtrados por companyId.
Después del lock se verifica evidencia y se recalcula disponibilidad. No se
confía en comprobaciones previas fuera de la transacción. La lectura preliminar
de una transición es por tenant/nota; identidad de reserva es inmutable y se
relee dentro de la transacción. No retry automático de POST ni de dinero.

Trigger PostgreSQL bloquea original y recalcula reservas/aplicados/desconocidos
para impedir exceso incluso mediante inserts directos. Constraints protegen
importe positivo, identidad única, relaciones tenant y self-reference. Historial
lo genera PostgreSQL en el mismo cambio de estado; actor de sesión local se
establece desde el usuario autenticado. Repetir estado no duplica eventos.

Reservas y eventos no se borran ni reescriben; payload/identidad de nota reservada
no pueden cambiar. Sin bypass de limpieza para tests. El módulo es interno, no
se añadieron rutas HTTP ni permisos nuevos. Antes de exponerlo o conectar sender
se requieren controles de autorización y coordinación de envío/reconciliación.

## Migraciones, backups y recuperación

Aplicadas SOLO a 127.0.0.1:56550/fullpos_alanube_uat,
contenedor fullpos_alanube_uat_postgres con binding exclusivo localhost.
Auditoría inicial: cero documentos e-CF y cero relaciones cruzadas/self-reference.

1. 20261014180000_ecf_e34_credit_integrity: snapshot nullable, FK compuesta,
   ledger/eventos y triggers de evidencia/presupuesto/inmutabilidad.
2. 20261014183000_ecf_fiscal_reference_uniqueness: evita dos filas del mismo
   e-NCF por tenant; aborta ante duplicados en lugar de fusionar/eliminar.

| Backup local ignorado (artifacts/uat-backups/) | Bytes | SHA-256 |
| --- | --- | --- |
| ecf_before_phase86_20261014.dump | 582346 | 5B52DD0AEA0642C8451DBC2D632128BBB986970E5ADEE4BBD274B121D2E4270D |
| ecf_before_reference_unique_20261014.dump | 601288 | 0AFD6BB401E4A5726E7CB789FB8BCC685B32E99DD42C2BAB6A9566246B9C1AB6 |
| ecf_before_final_e34_uat_20261014.dump | 621253 | 9858913CF4DF4765A2D2D117563ED9325C844EA95683FBEEB9EA9F79653E9CC7 |

Todos leídos íntegramente con pg_restore --file=/dev/null y hash verificado tras
copia. No se hizo restauración de recuperación a otra base.

Fallos propios declarados: primer migrate deploy falló por paréntesis CHECK
(42601); segundo por parsing de CASE dentro de función PL/pgSQL, mostrado como
transacción abortada en Prisma. Se comprobó rollback: columna/tabla ausentes y
cero documentos. Se diagnosticó con psql usando SQL versionado y COMMIT sustituido
por ROLLBACK; se corrigieron solo archivos aún no aplicados y se marcaron esos
intentos rolled-back mediante prisma migrate resolve en UAT. Ensayo completo
posterior ROLLBACK PASS; deploy final PASS. Ninguna migración aplicada fue editada.

La comparación migrate diff es diagnóstica, no se aplicó su SQL. Detectó defaults
UUID/updatedAt e índices ECF históricos, telemetry/app-release y tabla probe UAT
preexistentes. Se alinearon solo mapeos físicos/defaults de objetos NUEVOS con
PostgreSQL; no quedan diferencias de ecf_credit_* ni del índice fiscal nuevo.
Los defaults históricos ya constan en migraciones previas y no se refactorizaron.
No se afirma ausencia de drift global.

Recuperación: detener uso del módulo antes de restaurar; conservar respaldos y
restaurar a una UAT separada para verificar, no sobrescribir datos posteriores.
Ledger con auditoría existente no debe revertirse mediante DROP/DELETE o
desactivar triggers. No se ejecutó rollback destructivo ni db push/migrate reset.

## Pruebas y checks ejecutados

```text
npm --workspace apps/api test -- --testPathPatterns=src/ecf
PASS: 28 suites / 180 pruebas; 40 PostgreSQL omitidas aquí por opt-in.

./scripts/isolated-uat/test-ecf-postgres.ps1
PASS final: 2 suites / 40 pruebas reales PostgreSQL (12 anteriores + 28 E34).

npm --workspace apps/api test
PASS: 102 suites / 919 pruebas; 3 suites / 48 pruebas omitidas.
40 PostgreSQL se ejecutaron aparte; 8 opt-in ajenas no verificadas.

npm run api:build
PASS final: prisma generate 5.22.0 + tsc.

npm --workspace apps/api exec -- tsc -p tsconfig.build.json
PASS separado.

npx prisma validate
PASS en apps/api con entorno UAT verificado.

npx prisma migrate status
PASS: 34 migraciones, base actualizada.

npx prisma migrate deploy
PASS final, dos migraciones nuevas solo UAT, con fallos iniciales descritos.

npx prisma migrate resolve --rolled-back 20261014180000_ecf_e34_credit_integrity
Ejecutado dos veces solo UAT para registrar intentos SQL fallidos/rollback.

npx prisma migrate diff --from-schema-datamodel prisma/schema.prisma --to-schema-datasource prisma/schema.prisma --script
Ejecutado read-only: drift histórico documentado; nuevos objetos alineados.

node scripts/isolated-uat/prepare-alanube-contracts.cjs --check
PASS; hashes oficiales y generación/matriz coinciden. Schemas no alterados.

Smoke con node sobre apps/api/dist
PASS: saldo Decimal, rechazo de fracciones de centavo, tenant y bloqueo E34;
cero llamadas de red. No se inició API ni se realizó solicitud fiscal.

git diff --check
PASS; aviso LF/CRLF del schema sin error de whitespace.

Auditoría PostgreSQL final
0 originales con reservas/aplicados/desconocidos por encima del total.
0 reservas cruzadas de empresa.
```

Casos 1–20 requeridos cubiertos con fixtures; además: igual importe/diferente
operación, cancelación solo local, defensa SQL directa, legado no conciliado,
inmutabilidad/duplicado e-NCF, original E32/tipo excluido, submit no liberable,
concurrencia SQL directa y usuario/tenant ausente. Reinicio = recreación de
cliente/servicio con persistencia; no crash de proceso ni proveedor real.

Retención UAT al cierre: 6 empresas sintéticas ecf-81-90-*, 51 reservas y 78
eventos de tres ejecuciones E34. Permanecen deliberadamente para auditar garantías
append-only; no empresas/documentos reales ni alta en Alanube. No se deshabilitó
ningún trigger para limpiar pruebas ni se perdió información preexistente.

## Archivos modificados en 81–90

```text
apps/api/prisma/schema.prisma
apps/api/prisma/migrations/20261014180000_ecf_e34_credit_integrity/migration.sql (nuevo)
apps/api/prisma/migrations/20261014183000_ecf_fiscal_reference_uniqueness/migration.sql (nuevo)
apps/api/src/ecf/documents/ecf-document-idempotency.service.ts (resumen de referencia)
apps/api/src/ecf/documents/ecf-e34-integrity.policy.ts (nuevo)
apps/api/src/ecf/documents/ecf-e34-integrity.policy.spec.ts (nuevo)
apps/api/src/ecf/documents/ecf-e34-credit.service.ts (nuevo)
apps/api/src/ecf/documents/ecf-e34-postgres.integration-spec.ts (nuevo)
apps/api/src/ecf/ecf.module.ts
apps/api/src/ecf/ecf-pre-emission.guard.ts
apps/api/src/ecf/ecf-pre-emission.guard.spec.ts
scripts/isolated-uat/test-ecf-postgres.ps1
scripts/isolated-uat/prepare-alanube-contracts.cjs
docs/ECF_ALANUBE_CONTRACT_MATRIX_PHASES_71_74.md
docs/ECF_ALANUBE_MASTER_CONTEXT.md
docs/ECF_ALANUBE_NEXT_STEPS.md
docs/ECF_ALANUBE_FIRST_SANDBOX_ISSUANCE_PLAN.md
docs/ECF_ALANUBE_PHASES_81_90_FINAL_AUDIT.md (nuevo)
```

El directorio e-CF ya era untracked. No atribuir todos los cambios locales a este
bloque. AGENTS/.gitignore/app.module/uat-safety/dependencias y trabajo anterior
preservados. Los schemas generados se regeneraron con contenido idéntico; solo
la matriz añade estado de integridad. Sin nuevas dependencias.

## Contratos, pendientes y estado final

Fuentes públicas consultadas:
[Alanube E34](https://developer.alanube.co/reference/createcreditnotes),
[errores DOM](https://developer.alanube.co/reference/documents),
[PostgreSQL16 locks](https://www.postgresql.org/docs/16/explicit-locking.html),
[Prisma transacciones](https://www.prisma.io/docs/orm/fundamentals/transactions).
Snapshots OpenAPI DOM 3.0.3 fijados por hash conservados. No Context7 disponible;
se usó documentación oficial y Prisma 5.22/PostgreSQL reales. No consulta a DGII.

Pendiente: ingestión/verificación auténtica de evidencia, condiciones fiscales
DGII por tipo/concepto/tasa/plazo, certificados/activación, balances por línea e
impuesto, variantes de respuesta y garantías DOM de idempotencia/conciliación,
firma/replay webhook y rate limits. No se inventaron estas reglas.

Primero resolver esos contratos/evidencias y diseñar orquestación fiscal
transaccional autorizada; luego revisar cualquier sender futuro. No basta con
poner flags o contractStatus a true. E34 ahora se bloquea incondicionalmente en
preemisión hasta una revisión explícita. No se modificó mapper con campos nuevos
no documentados ni devoluciones comerciales.

Alanube: autenticación histórica fase31; cero llamadas autenticadas nuevas.
DGII: no contacto ni aceptación/certificación real demostrada.
Emisión: cero documentos enviados; POST/switches bloqueados; sin numeración.
Git: misma rama/HEAD, cambios locales preservados; sin commit/push/merge/reset/
clean/stash/rebase/deploy ni otros worktrees.
POS tradicional, Flutter, offline, inventario, caja, compras, cotizaciones,
licencias y NCF/ITBIS tradicionales sin cambios; taxEnabled/ncfEnabled intactos.
Producción sin acceso ni modificación. Solo UAT aislada con fixtures autorizados.

Herramientas: terminal/PowerShell, git, rg/lectura, apply_patch, Node/npm/Python,
Jest, Prisma/tsc, Docker/psql/pg_dump/pg_restore y web pública. Sin subagentes,
Figma, Playwright ni Vision; no UI/hardware modificados.

## Dictamen

Auditoría final de secretos: 110 archivos de código e-CF, scripts UAT,
documentación ECF y ambas migraciones revisados mediante patrones de claves
privadas, JWT y conexiones PostgreSQL con credenciales: 0 archivos señalados.
Es un escaneo por patrones, no una garantía exhaustiva. No se abrieron secretos.
Git diff --check PASS; rama y HEAD finales coinciden con el inicio.

Concurrencia, saldo, original multiempresa, parciales y acumuladas: PASS local/UAT.
Fase74 cerrada en integridad local; conformidad fiscal integral/fase66/87 PARTIAL.
**NO-GO para primera emisión Sandbox o producción.** El bloque local está
implementado y validado; ninguna prueba final ejecutada queda fallando.
