# GUARDIAN AI — Fase 6: readiness de producción y auditoría de integración

Fecha: 2026-10-28 · Worktree: `C:/src/fullpos-guardian-telemetry-uat` · Rama:
`agent/guardian-telemetry-phase1` · **Sin despliegue, sin merge, sin avisos a clientes.**

Base verificada: la aceptación E2E real (Fase 5B) pasó —
Windows UAT → Guardian API → PostgreSQL → DeepSeek `DONE` → WhatsApp `DELIVERED`.

---

## 1. Estado de Git (HECHO)

| Elemento | Valor |
| --- | --- |
| Worktree | `C:/src/fullpos-guardian-telemetry-uat` (aislado) |
| Rama | `agent/guardian-telemetry-phase1` |
| Base del worktree | `6b3e38ed` (2026-10-12) |
| `production-main` **local** | `6b3e38ed` (ref obsoleta) |
| `origin/production-main` | **`a02b2448`** (2026-10-28, «instalador 1.0.6-148») |
| Divergencia | **39 commits**, **291 archivos** nuevos en producción desde la base |
| Cambios del worktree | 70 entradas → agrupadas en **4 commits limpios** |
| Archivos tocados por ambos lados | **9** (ver bloqueador B1) |
| Versión de la app | worktree `1.0.6+140` · producción `1.0.6+148` |

**Consecuencia:** la línea de producción avanzó 16 días mientras el worktree se
desarrollaba. La integración **no** es un fast-forward: requiere rama de
integración, resolución de 9 archivos y regresión completa.

## 2. Matriz de readiness

| # | Área | Estado | Evidencia |
| --- | --- | --- | --- |
| 1 | Auditoría de cambios Fase 1–5 | **PASS** | 70 archivos inventariados y agrupados en 4 commits |
| 2 | Inventario de componentes afectados | **PASS** | API (29 archivos), Prisma (3), Flutter (18), Windows (9), Android (1), docs (6) |
| 3 | Comparación con la rama de producción | **FAIL** | 39 commits / 291 archivos por delante; 9 solapamientos (B1) |
| 4a | Aislamiento multi-tenant en consultas Guardian | **PASS** | `companyId` siempre del JWT o de la credencial de máquina, nunca del body; `company.deleteMany` en pruebas por slug propio |
| 4b | Autenticación de incidentes | **PASS** | `/guardian/machine/incidents` con `GuardianMachineGuard`; sesión JWT en `/guardian/incidents`; plataforma con token |
| 4c | Enrolamiento de instalación | **PASS** | Código de un solo uso (`maxUses`), `expiresAt` obligatorio, `revokedAt`, hash SHA-256 (el claro nunca se guarda) |
| 4d | Revocación y expiración de credenciales | **PASS** | `authenticate()` rechaza `!enabled`, `revokedAt` y `expiresAt <= now` (probado en `guardian.machine.service.spec.ts`) |
| 5 | Opt-in estricto **por empresa** | **PARCIAL** | Desactivado por defecto (global) y invisible sin enrolar, pero **no existe interruptor por empresa** (B2) |
| 6a | Fallo de Guardian no interrumpe el POS | **PASS** | `GuardianCaptureRegistry.capture()` nunca lanza; `void this.persist(...).catch()` (no bloquea la respuesta) |
| 6b | Fallo de Guardian no interrumpe la app | **PASS** | `unawaited(...)` en `main.dart` y en el reportero; timeouts 10/20 s; sin `await` en el flujo de venta |
| 6c | OFFLINE SAFE 48H intacto | **PASS** | No se tocan reglas offline; cola Guardian en `guardian_outbox.db` separada de `fulltech_offline.db` |
| 7a | Presupuesto de tokens por empresa | **PASS** | Se comprueba **antes** de llamar al proveedor (`isCompanyBudgetExhausted`) |
| 7b | Presupuesto global de tokens | **FAIL** | `GUARDIAN_AI_TOKENS_GLOBAL_DAY/MONTH` existen en UAT pero **ningún código los lee** (B3) |
| 7c | Errores y timeouts del proveedor | **PASS** | 429/5xx/timeout reintentan con backoff; salida inválida/truncada/esquema → terminal, sin recobro |
| 7d | Sanitización de datos | **PASS** | Bloque de datos no confiables, `sanitizeUntrustedText`, `redactText` en app, metadatos de error sin contenido |
| 8 | Política de WhatsApp | **PASS** | 1 destinatario administrativo, `dedupeKey` único, `MAX_ATTEMPTS=6`, backoff 1m/5m/15m/1h/3h, escalado solo si hay canal de respaldo, `ALREADY_SENT` si ya hay `providerMessageId` |
| 9 | Sondas de prueba fuera de producción | **PASS** | Todo detrás de `--dart-define` con default `false`; sin host UAT en `lib/`; credencial de enrolamiento solo por entorno/archivo |
| 10 | Compatibilidad del updater de Windows | **PARCIAL** | Cambio aditivo y `BINARY_NAME` parametrizado, pero **conflicto semántico** con el modo UAT de producción (B1) |
| 11 | Android / iOS | **PASS** | Android: firma release opcional con fallo explícito en tareas release (fail-closed). iOS: sin cambios |
| 12 | Pruebas de regresión | **PASS con 1 desvío explicado** | ver §3 |
| 13 | Commits limpios e integración preparada | **PASS** | 4 commits; merge **no** ejecutado |
| 14 | Procedimiento de despliegue y rollback | **PASS** | §5 |

## 3. Evidencia de pruebas (HECHO)

| Batería | Resultado |
| --- | --- |
| Backend unitarias | **1028 / 1028 PASS** (102 suites) |
| Backend PostgreSQL (BD UAT real) | **82 / 83** — único fallo: `notifications.claim` «500 filas exactamente una vez» (479 recibidas) |
| Flutter analyze | **`No issues found`** |
| Flutter test | **1298 PASS**, 1 skip |
| Build API (`tsc`) | exit 0 |

**Sobre el único fallo:** se repitió la suite y falló de nuevo; después se
escalaron a 0 las réplicas del API **y** de los workers (consumidores reales de
`notification_outbox`) y la misma suite pasó **4 / 4, con 500/500 filas**.
Conclusión: **interferencia del entorno de pruebas, no un defecto del producto**
ni de Guardian: el `NotificationsDispatcher` (existente antes de la Fase 1)
compite por la misma cola. Registrado como B4.

## 4. Bloqueadores y severidad

| ID | Severidad | Descripción | Acción propuesta |
| --- | --- | --- | --- |
| **B1** | **Alta — bloquea el merge** | 9 archivos tocados en ambos lados. `schema.prisma` (374 líneas de producción nuevas) y `windows/runner/main.cpp` (producción resolvió el modo UAT con la variable `FULLPOS_UAT_MODE`; el worktree lo resolvió parametrizando título/mutex por CMake). No son aditivos entre sí. | Rama de integración desde `origin/production-main`; conservar el modo UAT de producción y quedarse solo con la parametrización de `BINARY_NAME`; re-ejecutar toda la regresión |
| **B2** | **Alta — bloquea el opt-in tal como se pidió** | No existe `Company.guardianEnabled`. El opt-in real es por **máquina enrolada** y la desactivación exige revocar credenciales. | Decidir política (opt-in = enrolamiento, documentado) **o** añadir `Company.guardianEnabled Boolean @default(false)` en una fase corta |
| **B3** | Media | `GUARDIAN_AI_TOKENS_GLOBAL_DAY` / `_GLOBAL_MONTH` están configuradas en UAT pero **no se leen**: dan falsa sensación de tope global. | Implementar el tope global o retirar las variables de la configuración |
| **B4** | Media (tooling) | Las suites `*.pg.integration-spec.ts` comparten BD y colas con los servicios vivos: resultados dependientes del azar. | Ejecutar la regresión con los servicios a 0 o sobre una BD efímera por corrida |
| **B5** | Baja (docs) | `AGENTS.md:36,175` y `.vscode/tasks.json:69` invocan `scripts/release/build_windows_release.ps1`, que **no existe** (los reales son `prepare_windows_release.ps1`, `publish_windows_release.ps1`, `audit_windows_release_storage.ps1`). | Corregir la referencia documental |

## 5. Commits creados (ninguno fusionado)

```
86f09c70 feat(guardian): machine credential and enrollment code schema
05dafde6 feat(guardian): backend capture, machine auth and diagnosis pipeline
096621bc feat(app): Guardian agent, build identity parameterization and optional Android signing
docs(guardian): …            # documentación de fases 1–6
```

Plan de integración (no ejecutado):

1. `git fetch origin` y `git worktree add C:/src/fullpos-guardian-integration origin/production-main`.
2. `git branch agent/guardian-integration`; `git merge --no-ff agent/guardian-telemetry-phase1`.
3. Resolver B1 archivo por archivo (§4), `prisma validate`, `api:build`.
4. Regresión completa con los servicios UAT a 0 (B4).
5. Revisión de diff final y aprobación explícita antes de fusionar a `production-main`.

## 6. Base de datos: compatibilidad y rollback

- Las dos migraciones son **aditivas** (`CREATE TYPE`, `CREATE TABLE`, índices y
  relaciones nuevas) y están fechadas **después** de la última de producción
  (`20261014153000_offline_operation_payload_hash`). No alteran tablas existentes.
- `prisma migrate deploy` aplica en orden cronológico; no requiere ventana
  especial ni reescritura de datos.
- **Rollback de esquema:** las tablas Guardian son independientes; revertir el
  despliegue de la aplicación no obliga a borrarlas. Si hiciera falta,
  `DROP TABLE guardian_*` es seguro porque ninguna otra tabla las referencia.
- **Rollback de aplicación:** volver a la imagen anterior deja las tablas
  Guardian sin uso (código apagado por `GUARDIAN_ENABLED=false`).

## 7. Updater e instalador de Windows

- El updater ya apunta a `${BINARY_NAME}` (mismo arreglo aplicado por producción).
- El build de producción debe mantener `FULLPOS_BINARY_NAME=fullpos_cloud`,
  `APP_PRODUCT`/`APP_COMPANY` y el mutex de producción: **la identidad del
  ejecutable no cambia** para el cliente.
- La actualización sigue siendo **por manifiesto de versión** (`/api/app-updates/check`),
  no forzada: ningún cliente tiene que actualizar para que Guardian funcione.
- `_reportUpdaterFailure` solo añade observabilidad; no altera la decisión de
  actualizar.

## 8. Procedimiento de opt-in por empresa

1. Operador crea un código de enrolamiento para la empresa (`maxUses`, `expiresAt`).
2. Instalación de la empresa ejecuta el enrolamiento una vez; recibe `gmk_…`
   (guardada en el almacén seguro del equipo).
3. Esa empresa pasa a enviar telemetría por `/guardian/machine/incidents`.
4. Para **desactivar**: `guardian_machine_credentials.revoked_at = now()` (efecto
   inmediato en `authenticate()`), y opcionalmente `GUARDIAN_INGEST_ENABLED=false`.
5. Empresas sin código ni credencial: no envían nada y no ven ninguna interfaz.

## 9. Configuración recomendada del primer piloto

```
GUARDIAN_ENABLED=true
GUARDIAN_INGEST_ENABLED=true
GUARDIAN_DIAGNOSIS_ENABLED=true
GUARDIAN_ALERTS_ENABLED=false          # activar tras validar el piloto
GUARDIAN_AI_PROVIDER=deepseek
GUARDIAN_AI_MODEL=deepseek-flash
GUARDIAN_AI_MAX_TOKENS=1600
GUARDIAN_AI_TIMEOUT_MS=15000
GUARDIAN_AI_TOKENS_PER_COMPANY_DAY=50000
GUARDIAN_ALERT_DIAGNOSIS_WAIT_SECONDS=90
GUARDIAN_SAMPLE_SEV34=0.25
```

Clientes: build con `GUARDIAN_ENABLED=true` y `GUARDIAN_USE_MACHINE_API=true`,
**sin** `GUARDIAN_SELFTEST` ni credenciales embebidas.

## 10. Veredicto

**NO-GO** para fusionar o desplegar en producción en el estado actual (B1 y B2
abiertos). **GO** para iniciar la integración en rama aparte y resolver B1,
seguido de la regresión indicada, sin desplegar.
