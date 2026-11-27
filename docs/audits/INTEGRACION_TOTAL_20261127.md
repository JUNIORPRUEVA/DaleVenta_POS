# Integración total de los trabajos de ambos chats

Fecha: 27/11/2026. Base remota verificada por `ls-remote`:
`production-main` = `afa566eb383adb4c0e9f3cffe97c733fd36e2391` (PR56).
No se sustituyó por main, cuyo propósito y HEAD son distintos.

Worktree propio: `C:/t/fp-total-20261127`.
Rama: `agent/integracion-total-fullpos-20261127`.
No hubo merge remoto, deploy, release ni modificación de producción.

## Matriz de conservación

| Tema | Fuente | Estado en la integración | Verificación / límite |
|---|---|---|---|
| Web, registro y entrada automática | `a4ebdf1e`, `8f36da76`, PR53 | Antecesores del destino, conservados | 16 pruebas web y build Astro aprobados; regresión Flutter en ejecución |
| Recuperación y sincronización | `d5986236`, `61d5d5aa` | Antecesores conservados | Suite Flutter completa; no se reparan ni borran colas de clientes |
| Acceso local seguro | `21a539a2`, `db93ce18` recuperado históricamente | Ya presente por PR56 | Conserva límites y el pendiente móvil histórico; no prometer QA físico nuevo |
| Productos, ciclo de vida y visuales | `c4bfd1d5` | Ya integrado | Suite general, sin alterar restricciones por empresa |
| Planes / catálogo / pagos | `0c16a76a`, `37f19ced` | Ya integrado por consolidaciones y PR56 | Regresión API/Flutter; no asignar planes a empresas reales |
| RNC y presentación fiscal | `e4e2f826` | Ya integrado en PR56 | 17 pruebas PostgreSQL de preparación/rollback aprobadas; sin emisión externa |
| Updater Windows y barreras operativas | `d265d084` → `0a87e92e` | Nuevo, completo y en orden | Pruebas Flutter sobre Windows; laboratorio nativo anterior documentado |
| Crédito, abonos, contabilidad, tickets/PDF y POS | `96b561c7` → `9e0ded51` | Nuevo, completo y en orden | Backend y suite Flutter; papel restaurado mantiene aceptación física pendiente |
| Guardian backend/cliente | `179a82b3` → `11651af4` | Nuevo, completo y en orden | 100 pruebas PostgreSQL Guardian en DB nueva aprobadas; requiere activación separada |
| CRM: planes/pagos | `ced7fd0` | Patch-equivalent en master; no reaplicar | 2674 backend y 433 Flutter aprobadas sobre master + Guardian |
| CRM: Guardian | `5f23972` → `76db563` | Integrado sobre master `3651996` | PR7; conserva chat, adjuntos, corrector y recuperación |
| CRM: multimedia/sesión/redacción | `b02fcd6`, `50b1d0f`, `d198d87`, `3aacc05` | Antecesores de la nueva rama CRM | No sobrescribir su servidor/repositorio/shell con archivos antiguos |
| Puente comercial | `0ea6d3f`, `dd80d7f` | Integración local contra main `afa4230` | 95 pruebas aprobadas; push bloqueado por historial privado, sin eludir controles |
| IA: Biblioteca/Memoria/Chats móvil | Cambios locales de `ai-memory-20261127` → `99ba7bd` | Integrados en rama propia contra main `8ee0458` | PR5; 993 unitarias y 21 HTTP/PG aprobadas; feature apagada por defecto |

La comparación `git range-diff e4e2f826..179a82b3 afa566eb..11651af4` devuelve
tres correspondencias `=`. Antes de ajustes de estilo/documentación, el árbol
integrado coincidía exactamente con `179a82b3`; API y website siguen idénticos.
Los ajustes posteriores sólo añaden llaves a ocho if de Guardian para superar
el análisis Flutter; no cambian condiciones ni reglas.

## Validación integrada y separación de evidencia

- Dependencias independientes instaladas en los cuatro worktrees.
- API FullPOS compilada; Flutter analyze sin incidencias tras preparar un `.env`
  local sin credenciales y corregir ocho infos de estilo del código entregado.
- API general: 3245 aprobadas y 580 omitidas, según sus opt-in y destinos requeridos.
  Las omitidas no se cuentan como validadas. Las suites PostgreSQL explícitas se
  ejecutan separadas de la suite general para evitar contaminar colas entre ensayos.
- Guardian PostgreSQL: 100 aprobadas, incluidos lector sin escritura y reparación.
- Notificaciones PostgreSQL: 4 aprobadas en base distinta.
- Preparación fiscal/venta atómica PostgreSQL: 17 aprobadas, sin conexión externa.
- Website: 16 pruebas y build de 14 páginas aprobados.
- Suite Flutter completa y build web: pendientes de terminar al redactar este punto;
  consultar el cierre de ejecución añadido antes del PR.
- CRM: 2674 backend / 433 Flutter, con 3 / 5 omitidas. Windows Debug compilado.
  El análisis muestra 54 infos de estilo preexistentes y cero errores/warnings;
  no se presenta la salida no exitosa de analyze como PASS.
- IA: typecheck/lint/build y 993 unitarias / 21 HTTP con PostgreSQL aprobadas sobre
  la copia integrada. Inferencia simulada para verificar contexto y aislamiento.
- Puente: 95 aprobadas; contrato HTTP CRM/puente actualizado: 10 comprobaciones
  con autoridad final simulada, sin DB real en ese arnés.

Primeros intentos fallidos se conservan en `.uat`: ausencia del asset `.env`,
puerto de fixture fuera de la allowlist y colas reutilizadas entre suites. No se
relajó la allowlist: se crearon contenedores nuevos en puertos permitidos; Guardian
y notificaciones se probaron en bases separadas. No se cambió código financiero
o fiscal para superar pruebas.

El arnés histórico CRM/IA/licencias con HTTP y PostgreSQL todavía monta el almacén
genérico, mientras el CRM actual exige autoridad DALEVENTAS. Alcanzó migraciones,
restauración, identidad y runtime IA, pero falló en la lectura de licencias. El
recorrido completo entre los cuatro sistemas no se declara cerrado.

## Publicación y dependencias

- FullPOS: PR contra production-main; backend y PWA posteriormente. Windows/iOS/
  Android son artefactos separados. No se genera instalador ni se activa Codemagic.
- CRM: [PR7](https://github.com/JUNIORPRUEVA/appyra-crm/pull/7) contra master.
- IA: [PR5](https://github.com/JUNIORPRUEVA/appyra-ai/pull/5) contra main, en borrador.
- Puente: rama local `agent/integracion-total-puente-20261127`; NO-GO para push.
  El hook histórico detecta una clave privada antigua y un respaldo grande. La
  cabeza elimina la clave, pero no se autoriza saltar el hook ni reescribir historia.

No hay migración nueva de FullPOS en estos tres commits. Las migraciones 054/055
del puente y las dos nuevas de memoria IA requieren inventario del destino,
respaldo y autorización separada antes de cualquier ejecución compartida.

## Activación productiva y rollback

No se leyó ni cambió la configuración del servidor. No se construyeron o publicaron
imágenes nuevas; el catálogo de imágenes locales no prueba qué digest está activo.
Antes del futuro deploy debe registrarse la imagen/digest vigente de cada servicio
y su fuente EasyPanel. Servicios afectados: FullPOS API/PWA, CRM backend/app,
puente de licencias e IA API/Academia. No dar instrucciones de desplegar una imagen
sin verificar su commit y la configuración que corresponde a cada servicio.

Guardian necesita volumen privado persistente y permisos, empresa/enrolamiento
autorizados, opt-out respetado, switches, worker/watchdog, proxy IA y canal/
destinatario/plantilla. Requiere aviso real autorizado y recepción confirmada.
Los mensajes a receptores locales y el estado ACCEPTED no certifican entrega real.

Rollback: conservar y restaurar las imágenes previas verificadas y la configuración
revisada por servicio; apagar capacidades nuevas mediante sus switches si procede.
No usar una restauración general de DB para revertir cambios visuales o de código.
No borrar rangos fiscales, contadores, pagos, colas ni documentos históricos.

Estado provisional: integración preservada y PR de revisión; **NO-GO para merge
o despliegue global** mientras haya controles/recorridos críticos pendientes y el
puente siga bloqueado. GO local de una suite no autoriza activación productiva.
