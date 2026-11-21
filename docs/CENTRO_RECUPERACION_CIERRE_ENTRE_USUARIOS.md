# Recuperación entre usuarios: cierre local — 2026-11-20

Continúa la simplificación de las diez pantallas. El pendiente de publicación
automática indicado en el informe anterior queda sustituido por este resultado.
No equivale a una publicación en producción.

## Cambios

- El arranque, la reconexión y el temporizador existente publican automáticamente
  resúmenes de incidencias bloqueadas del usuario autenticado. No publican ventas
  nuevas, no reenvían cobros y no requieren botones ni pantallas adicionales.
- Se utiliza el endpoint administrativo idempotente existente. La publicación
  está permitida al usuario de origen; la lectura empresarial, comprobación y
  decisión siguen reservadas al administrador.
- Los intentos inciertos se representan con su identidad original de venta.
  Solo se transmiten campos permitidos, nunca credenciales ni el ticket completo.
- El origen vuelve a consultar el mismo expediente y recibe la decisión del
  administrador. Conserva la fila completa, el importe y la referencia original.
- Los checkpoints son persistentes y distintos por empresa/usuario. Las
  respuestas 400/403/409/422 no generan reintentos automáticos del mismo resumen;
  no bloquean la publicación de otras incidencias válidas. 401, red y 5xx esperan;
  429 respeta Retry-After incluso al recrear el publicador. Los lotes son de 25.
- Una respuesta tardía no puede recrear una fila eliminada por otro flujo ni
  sobrescribir una evidencia que cambió: SQLite actualiza comparando propietario,
  estado, fecha y contenido originales. Un checkpoint de consulta ilegible puede
  reconstruirse sin tocar los datos financieros.
- La copia empresarial de un cobro local no añade otra tarjeta. Al retirar el
  pendiente se confirma primero la decisión empresarial y después se completa
  el archivo local; una respuesta incierta no autoriza ese cierre.

## Verificación

- **63 pruebas focalizadas PASS:** publicador, repositorio, pantalla, cambio de
  propietario y motor de recuperación. Incluyen duplicados visuales y rechazo
  del archivo local cuando la decisión empresarial no está confirmada.
  `apps/fulltech_app/courier-final-tests-2.log`.
- **Análisis focalizado sin incidencias:**
  `apps/fulltech_app/courier-final-analyze-2.log`.
- **Android nativo PASS**, emulador aislado 5556, API local 4005 mediante reverse
  4004 y PostgreSQL aislado 56560: desconexión, reconexión, publicación del cajero,
  permisos ADMIN, otra empresa rechazada, decisión administrativa, reapertura de
  SQLite y recepción de la decisión. Original conservado, un solo evento de
  publicación y uno de decisión. Repetición final con el APK actualizado:
  `.uat/courier/android-1795218319381082.json`.
- **Windows nativo PASS** del mismo recorrido, con perfil separado, API real y
  SQLite: `.uat/courier/windows-1795218225753713.json` y
  `apps/fulltech_app/courier-windows-acceptance.log`.
- **Datos financieros sin cambios:** comparación completa antes/después de las
  12 ventas y 32 movimientos sintéticos existentes, incluidos IDs, importes,
  identidad de solicitud, turno y fecha original de movimientos.
  `.uat/courier/financial-check.json`. No se ejecutaron cobros.

Los intentos de compilación fallidos de Windows se conservan: descarga lenta de
SQLite y límite de 260 caracteres de MSBuild. Se reutilizó el archivo de SQLite
de la compilación local previa, verificando la copia SHA-256, y se configuró el
build con un alias corto `C:/fprc`. No se editaron dependencias ni se relajó una
protección de seguridad. Otro intento se cerró por la instancia UAT anterior
abierta; se detuvo exclusivamente esa aplicación de laboratorio y la aceptación
posterior pasó. La copia de trabajo está en
`C:/Users/pc/.codex/worktrees/fullpos-recovery-courier-20261120`, rama
`agent/recovery-courier-20261120`; se aisló por otra escritura simultánea en la
copia anterior.

## Límites que permanecen

Los datos exclusivamente locales solo pueden publicarse cuando el equipo de
origen esté conectado y autenticado con el usuario que los guardó. No se emplean
credenciales de otro usuario ni se promete acceso remoto a un equipo apagado.
La consulta normal de un expediente publicado tarda hasta aproximadamente cinco
minutos, además de cualquier espera exigida por el servidor.

No hay validación física iPhone en este equipo Windows. La prueba Android es en
emulador y no sustituye la aceptación física. No se habilitó offline en Web.
La versión integrada y su matriz final de aceptación siguen siendo requisito
para publicación. No hay commit, despliegue ni cambios de producción.

Se dejó `flutter run -d windows` ejecutando la aplicación actualizada con una
copia separada del perfil UAT; se observó la pantalla de ventas abierta. La API
local devuelve 404 para el manual interno opcional del asistente, ya ausente en
el laboratorio anterior; no se modificó ese módulo ajeno a recuperación.

**Veredicto:** GO de revisión local del flujo validado en Windows y Android
emulado; NO-GO de publicación general hasta la integración y aceptación de las
plataformas de destino. Las pruebas no constituyen una garantía de cero errores.
