# Fullpos Cloud — auditoría e-CF Alanube fases 61–70

Fecha: 2026-10-14. Worktree FULLPOS-ECF-ALANUBE, rama feature/ecf-alanube,
HEAD sin cambios: `6b3e38ed57bc53f9a55e66cf2eccf315afffd3f1`.

## Resultado y fases

GO para el bloque local validado de idempotencia/UAT y endurecimiento.
NO-GO para declarar integración fiscal completa o realizar primera emisión.
66 permanece PARTIAL; no se oculta ni se convierte en PASS.

| Fase | Estado | Evidencia / límite |
| --- | --- | --- |
| 61 | PASS | Clave anterior incluía fingerprint; índice unique por fingerprint impedía operaciones independientes idénticas. Sin clientRequestId y carrera find/create sin recuperación. Solo tests llamaban preparación. |
| 62 | PASS | Identidad v2 por empresa/tipo/origen+UUID, o request UUID manual explícito. Mismo contenido retorna fila; distinto contenido genera ConflictException. Unique operacional preservado, P2002 resuelto fuera de transacción. |
| 63 | PASS | Backup validado, auditoría sin conflictos, migración versionada aplicada únicamente UAT. Sin reset/db push ni modificación de migraciones anteriores. |
| 64 | PASS | 12 pruebas PostgreSQL: diez casos solicitados y dos ensayos de migración heredada. Datos sintéticos del test limpiados. Reinicio probado mediante recreación cliente/servicio; no crash de proceso ni llamada real. |
| 65 | PASS | Fuentes oficiales públicas investigadas; snapshots OpenAPI incrustados recuperados y hashes registrados. Sin credenciales. |
| 66 | PARTIAL | Registry por evidencia, required presence por tipo y mapper con rutas faltantes; no conformidad completa request/response ni mapper oficial final. Nada se marca listo para emisión. |
| 67 | PASS | POST bloqueado incluso invocación directa, guard no acepta partial, reintentos fiscales bloqueados, timeouts acotados, respuesta por streaming limitada, UNKNOWN_RESULT persistido con CAS e historial. Sender/worker/conciliación siguen desconectados. |
| 68 | PASS | Solicitud técnica creada, no enviada. |
| 69 | PASS | Jest local, PostgreSQL, build completo, Prisma validate/status, tsc, auditoría de patrones secretos, diff y regresión backend aprobados. Omisiones explicitadas abajo. |
| 70 | PASS | Este informe, master context, next steps y plan de primera emisión actualizados. |

## Identidad y compatibilidad

Formato fuente: `ecf:v2:<company UUID>:<E31/E32/E34>:SOURCE:<sourceType>:<source UUID>`.
Sin origen: `ecf:v2:<company UUID>:<tipo>:REQUEST:<clientRequestId UUID>`.
UUID se normaliza a minúscula; no se trunca fingerprint para construir identidad.
No se permite omitir identidad ni mezclar origen y requestId ambiguamente.
El tipo fiscal forma parte de la operación: distintos tipos son operaciones
distintas. El caller interno debe derivar companyId del contexto autenticado;
no se añadió endpoint que acepte companyId del cliente.

La migración reescribe claves heredadas de documentos e intentos juntos, bajo
transacción y bloqueo, conserva unique(companyId,idempotencyKey) y reemplaza
unique fingerprint por índice no único. No elimina documentos/historial.
Las operaciones heredadas sin origen pueden retomarse con clientRequestId igual
al UUID del documento. Aborta si hay orígenes duplicados, claves desconocidas o
intentos con empresa/clave incoherentes. No hace fusiones ni reparación silenciosa.
Rollback del esquema no es automático: volver a unique fingerprint requeriría
auditar duplicados legítimos. No restaurar backup sobre datos posteriores.

## UAT, backup y migración

- Contenedor observado: fullpos_alanube_uat_postgres.
- Publicación observada: 127.0.0.1:56550 → 5432; PostgreSQL 16.15.
- current_database(): fullpos_alanube_uat.
- Auditoría previa: documentos, intentos e historial e-CF = 0; colisiones de
  origen = 0; intentos con identidad divergente = 0.
- Backup anterior a escrituras:
  `artifacts/uat-backups/ecf_before_phase63_20261014.dump`, 582256 bytes.
- SHA-256: `0C899ED8EB69007F6CA612DED19DB1D40C28872E23C3027DF77D8C3466C84BE0`.
- pg_restore --list y lectura completa a /dev/null PASS; no se realizó una
  restauración de recuperación a otra base.
- Aplicada: `20261014160000_ecf_stable_operation_identity`.
- migrate status posterior: 32 migraciones, esquema actualizado.
- Después de fixtures: cero documentos e-CF, cero compañías ecf-61-70-*.
  Los fixtures se borran únicamente por UUID aleatorios y prefijo del test.
- Ensayos de claves heredadas/conflicto: tablas TEMP que sombrean tablas
  públicas dentro de una conexión propia. Sin reejecutar migración sobre public.

## Validaciones ejecutadas

```text
npm --workspace apps/api test -- --testPathPatterns=src/ecf
PASS: 26 suites, 99 pruebas; suite PostgreSQL opt-in omitida (12 casos).

./scripts/isolated-uat/test-ecf-postgres.ps1
PASS: 1 suite, 12 pruebas PostgreSQL, incluidas carreras de 8 preparaciones.

npm --workspace apps/api test
PASS: 100 suites / 838 pruebas; 2 suites / 18 pruebas omitidas en ese run.
Ese run tenía 10 casos PostgreSQL opt-in; se ejecutaron aparte los 12 finales.
No se declara que las otras 8 pruebas opt-in ajenas hayan pasado.

npm run api:build
PASS final: prisma generate v5.22.0 y tsc.

npm --workspace apps/api exec -- tsc -p tsconfig.build.json
PASS separado.

npx prisma validate
PASS, desde apps/api, entorno aislado importado por _common.ps1.

npx prisma migrate status
PASS posterior, base aislada actualizada.

npx prisma migrate deploy
PASS, solo local UAT tras backup y auditoría.

git diff --check
PASS. Aviso LF/CRLF de schema no es fallo de whitespace.

./scripts/isolated-uat/download-alanube-public-contracts.ps1
PASS: tres snapshots públicos OpenAPI 3.0.3 con SHA-256.

git diff -- apps/api/src/sales apps/api/src/tax apps/api/src/cash apps/api/src/inventory apps/fulltech_app
Vacío; no cambios a estos módulos.

Auditoría Python final de patrones secretos sobre 96 archivos e-CF/scripts/docs
0 archivos señalados. Busca claves privadas, JWT y URLs PostgreSQL con clave.
No abre .env, DPAPI ni FULLTECH.txt; no sustituye auditoría integral de secretos.
```

Checks fallidos iniciales, preservados como evidencia:

- api:build inicial: EPERM al renombrar query_engine-windows.dll.node. La
  inspección de módulos de procesos Node no identificó un propietario; no se
  afirma causa exacta. Regeneración/build posterior PASS sin matar procesos ni
  borrar DLL. Evitar generación Prisma concurrente con tests/procesos usuarios.
- Primera selección `test -- ecf` fue absorbida por argumentos variádicos de
  Jest y ejecutó suites ajenas; 73 PASS y auth.password-reset FAIL por
  PrismaClient indefinido. Selección corregida con --testPathPatterns=src/ecf.
  Regresión completa posterior PASS, sin editar auth.
- Un test nuevo de timeout detectó clasificación errónea por instanceof Error
  entre realms. Se corrigió usando AbortSignal.aborted; timeout y suite PASS.
- Primera invocación de test:integration acumulaba patrones y omitió una suite
  ajena; wrapper final usa test con patrón explícito, una suite exacta PASS.

## Archivos de esta sesión

Los archivos e-CF ya eran mayormente untracked antes de esta sesión. Git no
puede atribuir todo ese directorio a este bloque. Lista exacta del trabajo actual:

```text
apps/api/prisma/schema.prisma (solo unique fingerprint → index)
apps/api/prisma/migrations/20261014160000_ecf_stable_operation_identity/migration.sql (nuevo)
apps/api/src/ecf/documents/ecf-document-idempotency.service.ts
apps/api/src/ecf/documents/ecf-document-idempotency.service.spec.ts
apps/api/src/ecf/documents/ecf-document-postgres.integration-spec.ts (nuevo)
apps/api/src/ecf/alanube/alanube-official-required-fields.ts (nuevo)
apps/api/src/ecf/alanube/alanube-official-required-fields.spec.ts (nuevo)
apps/api/src/ecf/alanube/alanube-safe-http.client.ts
apps/api/src/ecf/alanube/alanube-safe-http.client.spec.ts
apps/api/src/ecf/alanube/alanube-real-http.transport.ts
apps/api/src/ecf/alanube/alanube-real-http.transport.spec.ts
apps/api/src/ecf/alanube/alanube-retry.policy.ts
apps/api/src/ecf/alanube/alanube-retry.policy.spec.ts
apps/api/src/ecf/alanube/alanube-response-interpreter.ts
apps/api/src/ecf/alanube/alanube-response-interpreter.spec.ts
apps/api/src/ecf/ecf-contract-registry.ts
apps/api/src/ecf/ecf-pre-emission.guard.ts
apps/api/src/ecf/ecf-pre-emission.guard.spec.ts
apps/api/src/ecf/fiscal-core/alanube-dom.contract.ts
apps/api/src/ecf/fiscal-core/alanube-dom.mapper.ts
scripts/isolated-uat/test-ecf-postgres.ps1 (nuevo)
scripts/isolated-uat/download-alanube-public-contracts.ps1 (nuevo)
docs/ECF_ALANUBE_MASTER_CONTEXT.md (nuevo)
docs/ECF_ALANUBE_NEXT_STEPS.md (nuevo)
docs/ECF_ALANUBE_CONTRACT_RESEARCH_PHASE65.md (nuevo)
docs/ECF_ALANUBE_TECHNICAL_INFORMATION_REQUEST.md (nuevo)
docs/ECF_ALANUBE_PHASES_61_70_FINAL_AUDIT.md (nuevo)
docs/ECF_ALANUBE_FIRST_SANDBOX_ISSUANCE_PLAN.md
```

Artefactos ignorados: backup descrito y tres snapshots de schemas en
artifacts/alanube-public-contracts. No se alteró .gitignore, AGENTS.md, app.module,
uat-safety ni migraciones anteriores en esta sesión; sus cambios locales previos
se conservaron. Ningún archivo nuevo fue agregado al índice Git.

## Contratos, bloqueos y próxima acción

Ver ECF_ALANUBE_CONTRACT_RESEARCH_PHASE65.md para enlaces oficiales, hashes y
clasificaciones. Schemas públicos recuperados no equivalen a integración lista.
Hay metadatos fiscales que el modelo/mapper local no captura aún; no se asignan
secuencias por defecto ni se fabrican valores. Validar required no sustituye
tipos, enums, condiciones, referencias, límites monetarios ni aceptación fiscal.

Pendiente: completar DTO/mapper y conformidad integral local con esos schemas;
confirmar variantes de respuesta y garantías DOM; resolver preguntas de
TECHNICAL_INFORMATION_REQUEST sobre idempotencia, consultas sin id tras timeout,
webhook/firma/replay, rate limits, reseller, activación y numeración Sandbox.
La solicitud está preparada y NO fue enviada. El sender futuro debe tener
revisión separada, autorización y barreras persistentes antes de activarse.

Alanube: autenticación solo histórica fase31; cero llamadas autenticadas nuevas.
DGII: sin acceso ni certificación verificada de clientes.
Emisión: cero documentos enviados; bloqueada en todas las rutas de envío actuales.
Producción: sin conexión ni modificación. POS tradicional/Flutter/offline: intactos.
Git: misma rama/HEAD, todos los cambios locales preservados, sin commit, push,
merge, reset, clean, stash, rebase ni deploy.

Herramientas: terminal PowerShell, git local, lectura/búsqueda, apply_patch,
Docker/psql/pg_dump/pg_restore, Jest, Prisma, TypeScript, Python y consulta web
pública. No Context7 disponible, Figma, Playwright, Vision ni subagentes usados.
Sin cambios UI; no corresponde validación visual ni hardware.

## Dictamen

**NO-GO para integración/emisión fiscal completa**: fase66 PARTIAL y garantías
externas pendientes. **GO del bloque local validado**: identidad, migración UAT,
pruebas, seguridad inerte y documentación. No quedan checks ejecutados fallando;
sí queda trabajo contractual explícito. No autoriza producción ni emisión.
