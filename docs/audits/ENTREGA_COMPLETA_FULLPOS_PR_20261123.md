# FullPOS — consolidación para PR, 23/11/2026

## Alcance solicitado

El propietario autorizó publicar una rama y abrir un PR borrador hacia
`production-main` que conserve el trabajo pendiente de esta conversación y la
entrega anterior. No autorizó merge, deploy, migración compartida ni cambios
productivos. CRM se publica separadamente en su PR propio hacia `master`.

## Inventario de procedencia

| Grupo | Procedencia | Tratamiento |
|---|---|---|
| Consolidación anterior: planes, IA, recuperación, productos, diseño y móvil | PR53 / `61d5d5aa` | Ya es ancestro de la base remota; no se reaplica |
| Refinamiento móvil y preparación iOS | PR54 / `c70701e0` | Ya incluido en base |
| Corrección de subida iOS | PR55 / `7a3a3541` | Base remota verificada |
| Contrato de soporte interno | `20c880d3`, `2f1432b6` | Incluido completo en el candidato |
| Administración de contacto, plan, días y acceso desde CRM | `37f19ced` | Incluido completo; migración de contacto obligatoria antes del backend nuevo |
| Acceso local seguro nativo | `db93ce18`, worktree fp-offline-login-20261122 | Copia íntegra de código/pruebas; conserva informe y límites pendientes |
| RNC corregible antes de postular y textos fiscales para el cliente | 17 archivos pendientes del worktree fp-ecf-rnc-20261122 | Snapshot incorporado sin modificar ni limpiar el worktree fuente |

Se comprobó con `git merge-base --is-ancestor` que los 17 checkpoints conocidos
están preservados: `61d5d5aa`, `c70701e0`, `7a3a3541`, `6b0f8c68`,
`840caadf`, `d5986236`, `a4ebdf1e`, `c4bfd1d5`, `5545d07c`, `30e030db`,
`57b4e095`, `20709dc3`, `24f6d771`, `759bf50c`, `2388fe94`, `20c880d3`,
`2f1432b6`. La lista deriva del inventario anterior, no presume una auditoría
nueva de todas las ramas experimentales del equipo.

Los cambios offline coincidieron con el código original al compararlos contra
`db93ce18` en auth/offline/login. El único conflicto de incorporación fue
`docs/EXECUTION_STATE.md`; se conservaron ambas secciones, sin quitar sus límites.
Los cambios RNC se copiaron mediante parche binario más sus tres archivos nuevos.
Los worktrees fuentes y sus ramas permanecen intactos. No se incluyen entornos
reales, datos, builds ni generados Windows que sólo cambiaron fin de línea.

## Validación y límites de la nueva incorporación

Se ejecuta análisis Flutter y regresión conjunta auth/offline/routing/e-CF;
los resultados finales se registran en el PR. Build web de QA con URL loopback;
no es un artefacto para producción. El backend administrativo conserva las
30 pruebas focales PostgreSQL/HTTP, build y regresión de licencias registrados
en `CRM_CONTROL_PUBLICACION_20261123.md`.

**NO-GO para merge y despliegue general mientras los puntos críticos sigan
pendientes.** El commit offline original documenta un fallo no resuelto al
recuperar el perfil después del reinicio/reinstalación del emulador Android.
No se ha ejecutado la comprobación nativa iPhone/Keychain. Windows tiene evidencia
previa de persistencia entre procesos, no una garantía sobre todos los equipos.
Incluir el trabajo en un PR borrador permite revisarlo sin perderlo; no convierte
las pruebas pendientes en aprobadas.

Las modificaciones fiscales conservan estado/códigos persistidos, credenciales,
numeraciones y autorizaciones; los textos de aceptación sólo anuncian aceptación
DGII con resultado registrado, correlación y código observado compatible.
La corrección de datos se ofrece antes de iniciar postulación; no cambia la
identidad de un expediente registrado mediante un bypass.

## Entregas independientes

CRM: PR `https://github.com/JUNIORPRUEVA/appyra-crm/pull/1`, borrador.
Incluye los 29 commits sobre master observados al publicar: administración,
cobros, soporte, notificaciones, evidencias y ancestros. No basta con desplegar
FullPOS para actualizar el cliente CRM Windows: requiere su distribución propia.

Puente: `e723b8a`, preservado en copia saneada con push bloqueado. No se fuerza
publicación ni se fusiona con la historia original. Su imagen privada y el canal
de soporte productivo son dependencias separadas pendientes.
