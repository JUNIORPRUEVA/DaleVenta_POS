# Integración de ambos chats — 27/11/2026

Base consultada: `origin/production-main` = `ebc9486a6bba430efb929fe5ed5b5fe335b5cda7`
(PR #57). Rama nueva: `agent/integracion-final-caja-guardian-20261127`.
Worktree exclusivo: `C:/t/fp-integracion-final-20261127`.

## Matriz de procedencia y conservación

| Trabajo | Fuente conservada | Commit integrado | Estado |
| --- | --- | --- | --- |
| Registro web, handoff y arranque release | `4ec703de23691f7e640249ba8fa0fcc83d6f75ec` | `35b8061` | Incluido íntegro |
| Logo y cierre fiscal en PDF/HTML/RAW; retirada de previews | `84a3c23e556a2bbf7bdace6cd2a348cdc09508e7` | `631bd32` | Incluido íntegro |
| Comprobación de caja previa al cobro y recuperación segura del ticket | `fe7948b`, rama `agent/cobro-turno-recuperacion-20261127` | `6dfbabe` | 13 archivos, incluidos tests y auditoría |
| Guardian predeterminado por empresa, sin sobreescribir desactivaciones | `5ff678d`, rama `agent/guardian-empresas-20261127` | `2e4a545` | 11 archivos, incluida migración y tests |
| Crédito/abonos, actualizador y Guardian del trabajo anterior | PR #57, base `ebc9486a6` | Ya presentes en la base | No se reemplazan por árboles antiguos |
| CRM: Guardian móvil y detalle por negocio | `582acba` | PR propio de APPYRA CRM | Conservado e integrado allí |
| CRM: respuesta por voz con entrega protegida | `6e22c0f` | PR propio de APPYRA CRM | Inclusión confirmada por el propietario |
| APPYRA IA: síntesis y voz por agente | `3d108d1`, `219ea70` | PR propio de APPYRA IA | Dependencia de la voz CRM |

Los cherry-picks usan `-x`: el mensaje conserva el SHA original. Las ramas y los
worktrees fuente permanecen disponibles; no se reescribieron ni borraron commits.
Las incorporaciones a PRODUCT_SPEC/ARCHITECTURE conservan simultáneamente caja y
Guardian. No se hizo una copia de carpeta que pudiera reemplazar trabajo previo.

Esta integración contiene los 57 archivos distintos de los cuatro bloques FullPOS,
más este informe. Los manifiestos por archivo están en:

- `docs/SIGNUP_STARTUP_HANG_AUDIT_20261127.md`
- `docs/ECF_TICKET_LOGO_FOOTER_HOTFIX_20261127.md`
- `docs/audits/COBRO_TURNO_RECUPERACION_20261127.md`
- `docs/audits/GUARDIAN_EMPRESAS_DEFAULT_20261127.md`

Los cambios sin commit y capturas del checkout antiguo principal no se tocan ni
se atribuyen a esta integración. Su rama antigua no es el destino actualizado.
Los generados de Flutter, bases, `.env`, modelos y evidencias locales no se incluyen.

## Validaciones de la versión integrada

- `npm run api:build`: PASS.
- Backend general: 3,213 pruebas PASS; 614 omitidas por sus condiciones de ejecución.
- Migración/defaults Guardian en PostgreSQL propio de bucle local: 2 PASS.
- `flutter analyze --no-pub`: sin incidencias.
- Website: 25 pruebas PASS, check sin errores/advertencias (un hint heredado), build PASS.
- Regresión Flutter completa serial: iniciada sobre esta rama. El resultado final
  y los controles remotos se registran en el PR; no se sustituyen por resultados
  de los worktrees originales.
- Las evidencias previas de ambos autores se conservan en los informes de origen.
  La aceptación del arranque release original incluye 11 escenarios de navegador
  con API y PostgreSQL aislados. No se presenta como una segunda ejecución nueva.
- La impresión fiscal original comprobó PDF, QR y raster RAW; falta nueva revisión
  física del papel antes de afirmar validación de hardware de este hotfix.

## Restricciones de publicación

Se autorizaron commit, push y PR; no merge, deploy, releases, cambios de variables
productivas ni migraciones compartidas. La migración nueva de Guardian sigue
pendiente de aprobación separada y respaldo. El alcance actual de enrolamiento
productivo debe revisarse; el diagnóstico IA no se activa mediante este PR.

La voz de APPYRA no necesita migración Prisma nueva. Sus cambios se publican en
repositorios separados y conservan pendientes explícitos de imagen Linux,
revisión visual y recepción real en WhatsApp. No hay mensajes a clientes reales.

Abrir el PR como borrador permite ejecutar controles mientras concluye la batería
local; no equivale a GO para merge ni a autorización para producción.
