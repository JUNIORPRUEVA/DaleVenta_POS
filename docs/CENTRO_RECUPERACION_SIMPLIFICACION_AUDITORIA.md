# Centro de recuperación cambios y validación

Continuación vigente: [cierre entre usuarios](CENTRO_RECUPERACION_CIERRE_ENTRE_USUARIOS.md).
Ese informe sustituye los pendientes de publicación automática y aceptación
Android indicados más abajo. El resto de este documento conserva la fase previa.

Revisión local del 20 de noviembre de 2026. Rama
`agent/recovery-simple-ui-20261120`, worktree
`C:/src/fullpos-recovery-simple-ui-20261120`, base `840caadf` con los cambios
previos de recuperación conservados. Esta fase no publica ni despliega.

## Resultado por pantalla

| Estado solicitado | Resultado implementado |
| --- | --- |
| Sin pendientes | Solo icono de éxito y «Todo en orden». Se exige haber comprobado que no hay trabajo pendiente; una consulta fallida no se presenta como éxito. |
| Pendientes offline | Lista compacta con texto 12–13px, un control superior Sincronizar y envío automático al recuperar conexión. Sin menú de importación. |
| Cobro incierto | Inicialmente solo Verificar ahora. Dos consultas nuevas de solo lectura cuando la primera respuesta válida es NOT_FOUND; se respetan permisos, validaciones y Retry-After. |
| Registro encontrado o no encontrado | Una coincidencia exacta resuelve el aviso. Un resultado ausente válido muestra Eliminar pendiente y Hacer el cobro de nuevo, sustituyendo la verificación. Un fallo de transporte conserva la verificación y la evidencia. |
| Caja rechazada | Comprobar o Eliminar pendiente desde el detalle. La retirada es administrativa y auditada; no borra ni compensa dinero. |
| Por comprobar | Dos acciones equivalentes para el expediente interno. No existe una solicitud visible a otro administrador. |
| Dinero declarado | Comprobar registro o Retirar declaración. La API verifica el registro exacto o registra una retirada con motivo. Una declaración local por enviar ofrece sincronizar; un rechazo permanente puede archivarse conservando el contenido original. |
| Sin respuesta | Conserva el pendiente y permite verificar otra vez. No habilita cobrar nuevamente por una simple desconexión. |
| Finalizados | Sin trabajo pendiente muestra solo el estado de éxito. La evidencia permanece, sin duplicar archivos o tarjetas de historial en el flujo operativo. |
| Cajero | Mensaje de acceso de administrador; no carga las incidencias. Las consultas y decisiones administrativas también se protegen en backend. |

Se retiraron los menús de diagnóstico, historial, reporte e importación de este
flujo. Sus utilidades o registros históricos existentes no se borraron.
Los botones mantienen esquinas cuadradas y las tarjetas el ancho acotado.

## Continuidad y prevención de duplicados

La comparación exclusiva del carrito podía frenar dos ventas legítimas iguales.
Ahora el POS transmite el identificador persistido de su ticket. El repositorio
deriva la identidad del cobro de empresa, usuario, dispositivo y ticket; no
depende de los artículos o del precio. La reserva se conserva antes del POST.

Un ticket distinto puede vender el mismo contenido. El mismo ticket incierto
mantiene la identidad y sigue protegido tras reabrir SQLite. Las acciones
antiguas sin prueba de ticket conservan la protección anterior; no se cambian
sus claves ni se reenvían automáticamente. Para estas existe la preparación
administrativa de una venta nueva, después de comprobar el resultado.

La preparación restaura primero los tickets existentes, añade otro ticket
editable y conserva los anteriores. Copia artículos, cantidades, precios y
datos disponibles del cliente; no copia solicitud, pago, turno o número fiscal.
No pulsa Cobrar. El POS conserva sus validaciones fiscales, de licencia,
inventario, almacenamiento y caja.

Las retiradas manuales archivan el pendiente completo y conservan auditoría.
Una declaración local solo se puede retirar por esta vía si terminó en rechazo
permanente; nunca si está enviándose o tiene un resultado de red incierto.

## Fallo detectado por la prueba real y corregido

Después de comprobar un cobro, el motor guardaba una espera interna de un minuto.
Esa espera impedía la comprobación previa al ticket nuevo y bloqueaba su
preparación. Se distingue ahora esa espera interna de Retry-After del servidor.
La verificación manual puede superar la primera, nunca la segunda. Se añadieron
regresiones para espera local, espera del servidor y evidencia antigua sin esa
distinción. Windows verificó el recorrido corregido completo.

## Evidencia ejecutada

Las baterías que se solapan no se suman como pruebas únicas.

| Comprobación | Resultado y evidencia |
| --- | --- |
| Flutter: recuperación, cola, caja, cotizaciones, errores, durabilidad de ventas y ciclo de vida | **539 PASS, 3 omitidas opt-in**. `.uat/simple-final-regression.log`. |
| Última repetición focalizada de pantallas, verificación reforzada y declaración rechazada | **28 PASS**. `.uat/simple-last-regression.log`. Incluye el caso que distingue la espera interna de Retry-After. |
| Identidad del ticket y SQLite | **36 PASS** en su batería. `.uat/simple-ticket-identity-tests.log`. Dos tickets idénticos independientes pasan; el ticket original conserva su clave y no genera otro envío después de reabrir SQLite. |
| Backend: expediente y conciliación administrativa | **38 PASS, 3 suites**. `.uat/simple-backend-final.log`. Validan identidad, importe, usuario, turno, método, versión y permisos; conservan resultados inciertos. |
| HTTP real con API local y PostgreSQL aislado | **8 escenarios PASS**. `.uat/simple-http-final.log` y `.uat/recovery-simple/api-acceptance-1795215966945.json`: 401, registro ausente, versión incorrecta, retirada auditada, idempotencia, venta existente protegida, coincidencia conciliada y otra empresa rechazada. |
| Windows real con API local | **1 escenario integral PASS**. `.uat/simple-native-test-5.log`: primer botón, dos soluciones después de verificar y artículos visibles en un ticket nuevo editable. Ningún cobro ejecutado. |
| Persistencia antes/después | **PASS**. `.uat/simple-native-evidence/financial-check.json`: mismas 2 ventas y 3 movimientos, con identidades, importes, fechas, turnos y cierres sin cambios. El perfil de prueba conservó sus 47 incidencias anteriores y añadió una incidencia sintética del escenario; quedó pendiente y con auditoría. |
| Análisis Flutter | **Sin incidencias**. `.uat/simple-analyze-final.log`. |
| TypeScript del backend | Compilación con `tsconfig.build.json` PASS; `.uat/simple-api-build-final.log`. No se generó ni aplicó una migración en esta fase. |

Capturas nativas comprobadas en `.uat/simple-native-evidence/`:
`01-check-only.png`, `02-two-solutions.png` y
`03-editable-sales-ticket.png`. Las pruebas de pantalla también verifican
anchos 320, 390 y 1280px. La galería Flutter utiliza datos ficticios en memoria
y un adaptador que rechaza cualquier conexión HTTP.

Los intentos iniciales fallidos quedan en sus logs: se corrigieron definiciones
duplicadas de la copia previa, imports de prueba, la configuración del arnés y
la espera interna. No se relajó la restricción UAT: Windows sigue usando el
puerto local permitido 4004 mediante el puente IPv6. La previsualización ajena
en IPv4:4004 se conserva. La API nueva del laboratorio escucha en 4005 y usa
PostgreSQL aislado en 56560.

## Límites y pendientes de integración

- «Eliminar pendiente» retira una incidencia operativa; no destruye su historial
  ni elimina movimientos financieros. No se promete que cualquiera de los dos
  botones pueda forzar una solución cuando la evidencia contradice al operador.
- La entrega automática al administrador de incidencias locales no publicadas
  de otros usuarios o dispositivos sigue siendo una tarea de integración
  separada. Los expedientes ya publicados de la empresa sí se consultan. No se
  amplió el ámbito del usuario para reenviar operaciones ajenas.
- No se repitió aceptación nativa Android/iPhone en esta fase; la interfaz
  compartida pasó las pruebas de ancho y el recorrido nativo de Windows. No se
  presenta esto como validación física de iPhone o aceptación offline Web.
- La primera automatización Chrome quedó en carga; no se contabiliza como
  prueba aprobada. La evidencia funcional principal procede de Windows, API y
  bases reales, además de los widgets.
- La documentación de IA corresponde a esta revisión local. No debe anunciar
  estos cambios como publicados en producción.

**Veredicto:** GO para revisión local del diseño y del flujo validado en
Windows. NO-GO para una publicación general hasta integrar una versión única,
completar los pendientes de recepción entre usuarios y la aceptación de las
plataformas de destino. No hay commit, publicación ni despliegue automático.

## Guía entregable para la IA

`docs/IA_CENTRO_RECUPERACION_GUIA_CLIENTE.md` contiene los diez estados,
instrucciones de uso, interpretación de respuestas HTTP, ejemplos breves y
prohibiciones para evitar pérdida, duplicación o confirmación incierta.
