# Registro web y acceso automático — 2026-11-20

Commit de recuperación solicitado: `d5986236`, guardado localmente sin push ni
despliegue. Las capturas ajenas de configuración se excluyeron del commit.
Corrección web en `C:/src/fp-signup-20261120`, rama
`agent/signup-auto-entry-20261120`; todavía no publicada.

## Hallazgos y corrección

La web crea cuenta y empresa, pide un ticket de un solo uso y abre Flutter en
`/home`. Flutter retira el ticket de la URL, lo canjea y guarda la sesión.

Se reprodujo una carrera: una actualización PWA podía activar el worker,
limpiar recursos y preparar una recarga antes de terminar ese acceso. Las dos
regresiones fallaron antes del cambio. Ahora la actualización espera al primer
frame, después del canje y guardado, y continúa disponible tras el arranque.

El fallo de canje se ignoraba y el arranque podía volver a la portada o conservar
una identidad anterior. Ahora se descarta primero la sesión local anterior,
se comprueba el usuario/empresa/token guardado y, si falla, se limpia la sesión
parcial y se abre `/login?access=retry` con una explicación. No se inicia Flutter
con media sesión, no se repite el alta ni se reintenta un ticket consumido.
La ruta sin ticket de Windows, Android e iPhone permanece igual.

Se consultaron únicamente HTML/JS públicos de producción mediante GET. Su shell
contiene la actualización automática sin esta espera. Esto confirma el defecto
y su compatibilidad con el síntoma, pero no demuestra la causa exacta del intento
del usuario sin su traza. No se consultaron cuentas privadas ni se creó una
cuenta en producción. No se cambiaron permisos, licencias, fiscalidad o inventario.

## Validación

- **16 pruebas del sitio PASS**, incluidas dos regresiones de actualización.
  `.uat/signup/race-before.log`, `race-after.log`, `website-tests.log`.
- **22 pruebas Flutter PASS**: acceso, bootstrap, navegación y canje correcto,
  vencido, red fallida, escritura parcial y limpieza fallida.
  `apps/fulltech_app/signup-auth-tests.log`.
- Análisis Dart sin incidencias. Astro check: cero errores, cero advertencias y
  un hint. Astro y Flutter Web compilaron para JavaScript.
- Chrome real, servidor local 4490, API local 4005 y PostgreSQL aislado 56560:
  registro completo y entrada directa a ventas con la empresa nueva, sin volver
  a escribir credenciales. Se observó también el aviso del ticket inválido.
- SQL/HTTP: **una cuenta, empresa coincidente, un ticket consumido, un canje
  correcto, cero POST de login manual, cero ventas y cero movimientos**. El
  ticket inválido recibió 401 sin repetir el alta.
  `.uat/signup/database-evidence.json`, `http-statuses.jsonl`.

Los logs HTTP guardan solo método, ruta sin query y estado; nunca contraseñas,
tokens ni tickets. Los datos sintéticos se conservaron. Se cerró la previsualización
propia después de comprobarla; no se detuvo ningún servidor ajeno.

**GO local.** La web publicada conserva su versión hasta una integración y un
despliegue autorizados. Las pruebas no implican que producción esté corregida.
