# Registro web detenido en «Iniciando…» — auditoría y corrección

Fecha: 27 de noviembre de 2026.
Base: `ebc9486a6` (production-main integrado, PR #57).
Rama: `agent/signup-startup-hang-20261127`.
Worktree privado: `C:\t\fp-signup-startup-20261127`.

## Resultado y causa reproducida

HECHO: la cuenta se crea antes de navegar a Flutter. La captura del usuario
corresponde al cargador HTML anterior al primer frame, no al formulario.

HECHO: con el backend real local, PostgreSQL aislado y Flutter **release**, el
formulario creó la cuenta y el arranque falló antes del canje del ticket. La
consola registró:

> Unsupported operation: String.fromEnvironment can only be used as a const constructor

El origen está en `GuardianConfig.fromEnvironment()`: varias llamadas a
`String.fromEnvironment` e `int.fromEnvironment` se ejecutaban sin `const`.
Guardian se activa por defecto en release; en debug se omite esa rama. La VM
aceptó incluso la prueba nativa con Guardian habilitado, mientras dart2js release
falló. Compilar o ejecutar solamente pruebas nativas no reproducía el defecto.

La corrección convierte esas cinco lecturas en constantes de compilación.
**No desactiva Guardian** ni cambia sus permisos, muestreo, enrolamiento o reglas
del servidor. La reproducción prueba el defecto del código publicado auditado;
no se consultaron las credenciales ni los registros privados de la cuenta real.

## Correcciones complementarias del recorrido

1. Se elimina realmente `handoff` de la dirección. Antes,
   `Uri.replace(queryParameters: null)` conservaba la consulta original cuando
   el ticket era el único parámetro. Se conservan otros parámetros y fragmentos.
2. El canje consume la identidad actual devuelta por el servidor, sin otro
   `/users/me` antes de `runApp`. Comprueba usuario, empresa, access y refresh y
   su coincidencia antes de guardar; el bootstrap verifica la copia persistida
   mediante otra instancia del almacenamiento. La validación posterior normal
   de la sesión permanece activa.
3. El canje no adjunta la identidad anterior ni intenta refrescar/repetir un
   ticket rechazado. Su plazo de 25 segundos cancela también el transporte;
   una respuesta tardía no puede guardar credenciales.
4. La limpieza previa a guardar la nueva identidad se espera directamente;
   no se deja una limpieza vencida ejecutándose detrás de la nueva sesión.
5. Preferencias no críticas: carga del límite de avisos con plazo de 2 segundos;
   lectura del guard de ámbito con plazo de 6 segundos, antes de mutaciones.
   No se aplica un timeout externo a una limpieza que pueda acabar tarde.
6. Las solicitudes del sitio para alta, comprobación, renovación y emisión del
   ticket tienen límites de 20 segundos. Alta/renovación/ticket incluyen la
   lectura del cuerpo. Una alta incierta por timeout ofrece iniciar sesión y
   deshabilita repetir el botón; no afirma falsamente que hubo éxito.
7. El cargador HTML ofrece acceso recuperable ante errores de script, motor o
   arranque; si no llega el primer frame, lo ofrece a los 45 segundos. No recarga
   automáticamente, no vuelve a crear la cuenta y no borra cachés/ventas.
   Si llega tarde un frame válido, la app puede continuar.
8. Se capturan fallos de inicialización/runApp del motor. Se conserva el límite
   del visor PDF y la protección del handoff frente a una actualización PWA.
9. Se incluye Roboto Regular local como fallback del motor, evitando su descarga
   obligatoria de Google durante la inicialización. La tipografía Manrope del
   producto se conserva. Fuente copiada del Flutter SDK 3.41.6 y licencia Apache
   2.0 incluida. SHA-256 de la fuente:
   `79e851404657dac2106b3d22ad256d47824a9a5765458edb72c9102a45816d95`.
   Esta era una dependencia adicional; no fue la causa principal reproducida.
10. Diagnóstico de etapa de arranque con códigos fijos, sin URL, correo, token
    ni contenido de excepciones en la variable expuesta por el shell.

## Validación ejecutada

| Comprobación | Resultado |
| --- | --- |
| Flutter auth + startup + frecuencia de avisos | 102 pruebas PASS |
| Flutter Guardian | 57 pruebas PASS |
| Configuración con `GUARDIAN_ENABLED=true` explícito | 1 prueba PASS; incluida también en las 57, no sumar |
| Sitio, bootstrap, sesión y carrera con actualización PWA | 25 pruebas PASS |
| Análisis Dart de los archivos modificados y nuevos | Sin incidencias |
| `npm run check` en website | 0 errores/advertencias; 1 hint previo por `event.returnValue` |
| `npm run build` en website | PASS |
| Flutter web release local, motor y fuentes locales | PASS |
| Navegador Chromium headless + Astro/Flutter compilados + API Nest real + PostgreSQL local | 11 escenarios PASS |
| Revisión de diff y `git diff --check` | PASS |

Prueba funcional: `website/tests/signup-startup-browser.mjs`. El navegador usó
contextos nuevos, bloqueó destinos externos y se conectó exclusivamente al sitio
`127.0.0.1:14974`, API `127.0.0.1:14973` y PostgreSQL `127.0.0.1:14975`.
Contenedor creado para esta tarea: `fullpos_signup_startup_20261127`.
Se aplicó el esquema al PostgreSQL **nuevo y vacío**, sin seeds comerciales.
No se reutilizó ni modificó la base de otra sesión.

Los 11 escenarios comprobados fueron:

1. Formulario completo, doble clic en Finalizar, una sola alta, sesión durable,
   coincidencia con `/auth/me`, carga de empresa y bienvenida visible.
   Tiempo desde Finalizar hasta bienvenida/captura: **4.935 s** en este equipo.
2. Recarga de la app conserva el usuario sin repetir el ticket.
3. Otro handoff sustituye conjuntamente empresa y usuario anteriores.
4. Ticket inválido/expirado: acceso recuperable y sin sesión parcial.
5. HTTP 503 durante el canje: sin reintento automático.
6. Solicitud retenida durante más de 25 segundos: recuperación, una tentativa.
7. Escrituras del navegador bloqueadas: no entra con sesión sólo en memoria.
8. Bootstrap 404: recuperación visible.
9. Motor CanvasKit 404: recuperación visible.
10. Descarga del bootstrap detenida: plazo del shell probado con reloj del
    navegador, recuperación visible.
11. Comparación de datos persistidos antes/después: exactamente dos usuarios,
    empresas y membresías; ningún duplicado ni operación financiera.

Datos de la ejecución release final:

| Dato | Antes | Después |
| --- | ---: | ---: |
| Usuarios | 7 | 9 |
| Empresas | 7 | 9 |
| Membresías | 7 | 9 |
| Correos duplicados | 0 | 0 |
| Tickets emitidos | 9 | 13 |
| Tickets consumidos | 2 | 4 |
| Ventas | 0 | 0 |
| Movimientos de caja | 0 | 0 |

Las filas previas pertenecen a las reproducciones fallidas/debug de esta misma
tarea; se conservaron. No se eliminó ninguna cuenta para obtener los resultados.

## Evidencia local

En `.uat/signup-startup/` (ignorado por Git):

- `reproduced-release-guardian-failure.json` y `.png`: fallo antes de corregir
  Guardian, con etapa y excepción del release.
- `browser-results.json`: escenarios y comparación de datos persistidos.
- `browser-diagnostics.json`: diagnóstico de la última ejecución.
- `01-registration-entry.png`: bienvenida real sobre Facturación.
- `recovery-*.png`, `startup-*.png`: recuperaciones de los escenarios negativos.

Logs locales de pruebas: `apps/fulltech_app/test-signup-regression.log`,
`test-signup-guardian.log`, `build-signup-web.log`; esquema/API en
`.uat/signup-migrations.log` y `.uat/signup-api.log`.

Para repetir el navegador se requiere el API aislado indicado y ambos builds;
la variable `PLAYWRIGHT_MODULE` admite la entrada de una instalación local de
Playwright. El script comprueba datos del contenedor local nombrado, no acepta
una URL de producción. El build de aceptación usado mantiene los defaults
release de Guardian y especifica `FULLPOS_UAT_BUILD=true`, las URLs locales y
`--no-web-resources-cdn`. El perfil `FULLPOS_UAT_PROFILE` no se alteró: su lista
de puertos sigue intacta.

## Límites y entrega

- **GO para integrar esta corrección:** causa release reproducida y eliminada;
  bienvenida real, aislamiento y recuperación comprobados.
- **No desplegado.** Falta integrar/revisar el commit y publicar el frontend web
  por el procedimiento habitual. No hace falta una migración de producción ni
  un cambio del backend para esta corrección.
- No se crearon cuentas ni se hicieron operaciones financieras en producción.
- La prueba del navegador emitió un `InvalidStateError` de la transición nativa
  entre documentos Astro/Flutter; ocurrió también en los casos exitosos, no
  bloqueó el flujo y queda fuera de este arreglo. No se ocultó en la evidencia.
- No se afirma un tiempo garantizado para todas las conexiones ni ausencia
  absoluta de fallos; los plazos y recuperación cubren los escenarios probados.
- La corrección anterior de logo/QR e-CF está en otra rama/commit
  (`agent/ecf-ticket-logo-footer-20261127`, `84a3c23e5`); no debe olvidarse al
  integrar los trabajos del chat. El trabajo de voces de APPYRA sigue pausado.
