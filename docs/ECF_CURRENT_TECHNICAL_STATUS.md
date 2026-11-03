# e-CF — Estado técnico actual (documento maestro)

Worktree `FULLPOS-ECF-ALANUBE`, rama `feature/ecf-alanube`. Fecha: **2026-10-18**.
Sin `commit`, sin `push`, sin `deploy`, sin emisión real. Producción y UAT
histórica intactas.

Este documento sustituye como **punto de entrada** a los informes de sesión
anteriores. No borra el histórico: lo resume y dice qué sigue siendo cierto.

## 1. Cómo leer este documento

| Marca | Significado |
| --- | --- |
| **IMPLEMENTADO** | El código existe y compila |
| **PROBADO** | Hay una prueba automatizada **ejecutada** que lo demuestra |
| **SIMULADO** | Funciona con transporte simulado, sin proveedor |
| **PENDIENTE INTERNO** | Lo podemos cerrar nosotros |
| **PENDIENTE EXTERNO** | Depende de Alanube o de la DGII |
| **REQUIERE AUTORIZACIÓN** | No se ejecuta sin permiso explícito |
| **NO IMPL.** | No implementado, por diseño o por bloqueo |

## 2. Evidencia ejecutada el 2026-10-18

| Comprobación | Comando | Resultado |
| --- | --- | --- |
| Compatibilidad POS legacy | `run-focused.ps1 -Pattern "legacy-pos-compatibility"` | **10/10 en verde** (6 previas + 4 nuevas) |
| Compilación backend | `npx tsc -p tsconfig.build.json --noEmit` | **exit 0** |
| Esquema Prisma | `npx prisma validate` | **válido** |
| Migraciones | `npx prisma migrate status` | **43 migraciones, al día** |
| Deriva de esquema | `prisma migrate diff` | **41 líneas**: 16 `DROP DEFAULT` + 1 índice único (preexistente) |
| Build Windows UAT | `flutter build windows --release` (perfil UAT) | **exit 0, 106.8 s** |
| Tráfico real de la UAT | `Get-NetTCPConnection` sobre el proceso | **0 conexiones a producción** |

Las suite completas de backend y Flutter **no** se reejecutaron en esta sesión;
la última medición registrada sigue siendo 65 suites / 747 pruebas e-CF y Flutter
1414 (2026-10-16). Se declara así en lugar de presentar cifras viejas como nuevas.

## 3. Hallazgo crítico de esta sesión

**La UAT Windows tal como se construía hablaba con producción.** El binario
compilado solo con `--dart-define=APP_ENV=uat` no aplica el perfil de seguridad y
`Env.apiBaseUrl` cae en `ProductConfig.productionApiBaseUrl`. Se detectó por el
tráfico real (32 conexiones a `31.97.99.70:443`) y por datos que no existían en la
base local.

Corregido recompilando con:

```text
--dart-define=FULLPOS_UAT_PROFILE=true
--dart-define=API_BASE_URL=http://127.0.0.1:4004
--dart-define=APP_BASE_URL=http://127.0.0.1:4004
```

Detalle completo y regla permanente en `ECF_UAT_PROFILE_BUILD_SAFETY.md`.

**Solución permanente (misma fecha):** el blindaje ya no depende de recordar un
flag. `lib/core/config/uat_network_guard.dart` se activa con
`FULLPOS_UAT_PROFILE=true` **o** `APP_ENV=uat`, valida host y puerto parseados,
rechaza hosts productivos y cualquier `*.easypanel.host`, y bloquea cada petición
antes de enviar credenciales. Además: sesión con prefijo `uat.`, base SQLite
`fulltech_offline_uat.db`, sin redirecciones en UAT, y script oficial
`scripts/build/build_windows_ecf_uat.ps1`. Pruebas: **15/15 en verde**.

**Corrección de una afirmación anterior:** «el `.env` empaquetado apunta a local»
**no** garantiza que la aplicación use ese valor.

## 4. Estado por capacidad

| # | Capacidad | Implementado | Probado | Veredicto |
| --- | --- | --- | --- | --- |
| 1 | Motor fiscal (decimal, tolerancia 1 céntimo) | Sí | Sí | **PROBADO** |
| 2 | E31 preparación y emisión simulada | Sí | Sí | **PROBADO / SIMULADO** |
| 3 | E32 consumo y ensayo de secuencia | Sí | Sí | **PROBADO / SIMULADO** |
| 4 | E34 notas de crédito y concurrencia | Sí | Sí (28 casos) | **PROBADO** |
| 5 | Persistencia inmutable (triggers) | Sí | Sí | **PROBADO** |
| 6 | Multiempresa y RBAC | Sí | Sí | **PROBADO** |
| 7 | Habilitación DGII (backend) | Sí | Sí (30) | **PROBADO** |
| 8 | Habilitación DGII (Flutter) | Sí | Widget | **IMPLEMENTADO** |
| 9 | Clasificación fiscal supervisada (F1) | Sí | Sí (30) | **PROBADO** |
| 10 | Contrato legacy / F3 | Sí | Sí (10) | **PROBADO** |
| 11 | Despacho simulado extremo a extremo | Sí | Sí | **PROBADO / SIMULADO** |
| 12 | Emisión real | **No** | No | **NO IMPL.** |
| 13 | Certificación DGII | No | No | **PENDIENTE EXTERNO** |
| 14 | UAT visual Windows del flujo F1 | Parcial | No | **PENDIENTE INTERNO** |

## 5. Pendientes internos (los podemos cerrar nosotros)

| # | Pendiente | Por qué importa | Estado |
| --- | --- | --- | --- |
| I1 | Recorrido visual del flujo F1 en Windows | Es la única evidencia gráfica que falta | Datos preparados; app abierta |
| I2 | Confirmar `FINANCIAL_LEGACY_COMPAT` en el entorno desplegado | Sin esto, el despliegue es NO-GO | **NO VERIFICADO** (sin acceso de solo lectura) |
| I3 | Decidir la deriva de Prisma (asumirla o tarea propia) | Riesgo de migración automática destructiva | **Documentada, no corregida** |
| I4 | Política de borrado de empresas con datos fiscales | Bloquea el borrado de cuenta | **Diseño listo**, requiere decisión |
| I5 | Organizar y commitear 114 cambios | Sin commit no hay release | Plan en `ECF_COMMIT_PLAN.md` |

## 6. Bloqueos externos (no los resuelve el código)

| # | Bloqueo | Quién lo desbloquea |
| --- | --- | --- |
| E1 | Autorización oficial de la DGII por empresa | Contribuyente + DGII |
| E2 | Contrato firmado de Alanube | Alanube / negocio |
| E3 | Discrepancia de esquema `GET` (`stampDate`, `signatureDate`, `trackId`) | Alanube |
| E4 | Contrato `PARTIAL_OFFICIAL` del E32 | Alanube |
| E5 | Firma del webhook de estado | Alanube |
| E6 | Plazos legales de retención fiscal | Asesoría legal |

## 7. Requiere autorización explícita (no ejecutado)

- Implementar el transporte real de emisión (`PRODUCTION_EMISSION_IMPLEMENTED = false`).
- Cualquier `POST` real a Alanube o consumo de e-NCF.
- Desplegar, migrar o reiniciar servicios productivos.
- Purgar o anonimizar datos fiscales.

## 8. Plan de despliegue futuro (NO ejecutado)

### 8.1 Compuertas independientes

| Compuerta | Alcance | Estado |
| --- | --- | --- |
| G-A | Backend compatible desplegado | Requiere I2 |
| G-B | Publicación de instalador | Requiere I5 |
| G-C | Actualización automática | Requiere I5 + firma |
| G-D | Activación de e-CF por empresa | Requiere E1 |
| G-E | Emisión fiscal real | Requiere E1 + E2 + E3 + autorización |

**No son la misma operación.** Aprobar una no aprueba las demás.

### 8.2 Matriz de compatibilidad exigible antes de desplegar

| Backend | Cliente | Resultado exigido |
| --- | --- | --- |
| Actual | Antiguo | Vende sin cambios |
| Candidato | Antiguo | Vende; cubierto por las 10 pruebas legacy |
| Actual | Nuevo | Vende |
| Candidato | Nuevo | Vende; cubierto |

### 8.3 Condiciones no negociables

1. e-CF desactivado por defecto en toda empresa existente.
2. Ningún cliente obligado a actualizar.
3. Ventas tradicionales intactas (verificado por pruebas).
4. Migraciones aditivas y reversibles.
5. Sin emisión real ni e-NCF.
6. Rollback técnico por componente.
7. Respaldo verificado antes de intervenir.
8. Monitoreo posterior definido.

## 9. GO / NO-GO por entorno

| Entorno | Veredicto | Motivo |
| --- | --- | --- |
| Backend UAT | **GO** | `tsc` 0, Prisma válido, 43 migraciones al día, legacy 10/10 |
| Flutter UAT | **GO** (con reserva) | `analyze` limpio en la última medición; sin cambios de UI en esta sesión |
| Windows UAT | **GO con reserva** | Build blindado verificado sin tráfico a producción; **recorrido visual pendiente** |
| Compatibilidad legacy | **GO** | 10 escenarios ejecutados |
| Integración Alanube | **NO-GO** | E2, E3, E4, E5 abiertos |
| Habilitación DGII | **GO técnico** / **NO-GO oficial** | Backend y UI listos; sin registro oficial |
| Emisión real | **NO-GO** | Desactivada por diseño |
| Producción | **NO-GO** | E1–E6 + I2 + I5 pendientes |

## 10. Siguiente acción exacta

1. Recorrer el flujo F1 en la app ya abierta (datos sintéticos preparados).
2. Confirmar `FINANCIAL_LEGACY_COMPAT` en el entorno desplegado (solo lectura).
3. Ejecutar el plan de commits de `ECF_COMMIT_PLAN.md` cuando se autorice.
