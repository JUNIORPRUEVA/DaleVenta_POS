# Soporte interno FullPOS → APPYRA CRM

Fecha: 2026-11-20. Implementación y comprobaciones exclusivamente locales.
Producción, fiscal, licencias, Prisma y credenciales productivas sin modificaciones.
Sin commit, push, merge ni despliegue de esta tarea.

## Problema y solución

HECHO: el acceso de atención humana del chat abría WhatsApp. El CRM ya dispone
de casos `incident`, hilos, estados, notificaciones internas y envío Web Push.
La integración anterior no registraba la solicitud del chat en esos casos.

La nueva herramienta determinista del backend reconoce solicitudes explícitas
de atención humana y reportes confirmados con descripción. Las consultas normales
siguen usando el motor IA existente. No se deja al modelo inventar un registro.
Se reutiliza la pantalla Soporte del CRM, sin crear otro agente o bandeja paralela.

1. El cliente escribe que desea atención humana, o confirma Reportar una avería.
2. FullPOS toma empresa y usuario del JWT, consulta el nombre de esa empresa y
   firma la solicitud al CRM. No toma la empresa de un campo enviado por Flutter.
3. CRM persiste un caso, hasta doce turnos recientes de contexto acotados y el
   mensaje, junto con su identidad externa. No vincula clientes por teléfono.
4. El equipo autorizado recibe una notificación interna idempotente. El caso
   conserva categoría Avería o Atención humana en su título y metadatos; su
   estado es Abierto, En curso, En espera, Resuelto o Cancelado.
5. FullPOS muestra la referencia devuelta por el CRM y un enlace Ver soporte.
   El seguimiento, respuestas y formularios permanecen dentro de la columna IA.
6. Una nota del CRM es interna por defecto. El equipo debe marcar expresamente
   que la respuesta será visible para el cliente en FullPOS. La marca se limpia
   después de enviar. El cliente puede responder desde ese mismo hilo.

El envío inicial del cliente no significa que el equipo ya atiende el caso.
La recepción de mensajes de tipo customer conserva Abierto hasta una acción
real del equipo. Las preguntas de proveedor fiscal conservan su barrera y ahora
indican cómo pedir soporte por texto, sin apuntar a un botón retirado.

## Contrato y seguridad

- CRM: POST `/api/integrations/fullpos/support`, acciones open/read/reply.
- FullPOS: POST `/ai/chat`, GET `/ai/support/:ticketId` y
  POST `/ai/support/:ticketId/messages`, protegidos por los guards existentes.
- HMAC SHA-256 con fecha, método, ruta y cuerpo; comparación constante y ventana
  de sesenta segundos. Credencial dedicada solo entre servidores.
- La consulta/respuesta exige coincidencia de empresa y usuario de origen;
  un id de caso ajeno no concede acceso. La clave no viaja en Flutter.
- Peticiones repetidas conservan caso y mensaje. Una petición inicial con la
  misma identidad y otro contenido se rechaza. Cerrar el caso no permite que
  un replay lo vuelva a crear. Los reintentos recuperan escrituras parciales.
- Solo mensajes explícitamente visibles salen al cliente. No salen notas,
  resoluciones internas, metadatos, identificadores internos de autores ni el
  contexto técnico utilizado por el equipo. No se confirma éxito sin recibo.
- El conector no sigue redirecciones y requiere HTTPS, excepto localhost para
  pruebas. Sin configuración o ante un fallo, informa que no pudo confirmar.
- Se conservan las tablas y contratos anteriores. No requiere migración nueva.

## Configuración pendiente antes de publicar

No se ha preparado ni verificado esta configuración en producción:

| Servicio | Variable necesaria |
| --- | --- |
| Backend FullPOS | `APPYRA_CRM_SUPPORT_URL` |
| Backend FullPOS y backend CRM | `FULLPOS_SUPPORT_SHARED_SECRET` |

El secreto debe ser nuevo, dedicado, igual en ambos servidores, de al menos
32 caracteres y guardado por un canal seguro. No reutilizar tokens administrativos,
WhatsApp, fiscal o licencia. No escribirlo en este informe ni en el repositorio.
La URL debe apuntar al CRM propio con TLS válido. El endpoint usa una ruta fija.
Una futura publicación debe revisar primero el backend CRM, después el backend
FullPOS y su PWA. APPYRA IA no necesita otro agente para esta herramienta.

## Worktrees y archivos de esta tarea

FullPOS: `C:/src/fullpos-ultimos-ajustes-ia`, rama
`agent/ultimos-ajustes-de-la-ia`. Se conservaron las ediciones anteriores.

Backend, bajo `apps/api/src/ai-assistant/`:

- `fullpos-support.client.ts` y `fullpos-support.client.spec.ts`.
- `dto/support-reply.dto.ts`.
- `ai-assistant.controller.ts`, `ai-assistant.module.ts`, `ai-assistant.service.ts`.
- `fiscal-provider.policy.ts` (solo orientación hacia soporte).

Flutter, bajo `apps/fulltech_app/lib/core/ai_assistant/`:

- `application/ai_assistant_controller.dart`.
- `data/datasources/ai_assistant_datasource.dart`.
- `domain/models/ai_assistant_message.dart`, `domain/models/ai_support_case.dart`.
- `domain/services/ai_assistant_service.dart`.
- `presentation/widgets/ai_assistant_sheet.dart`, `ai_support_case_link.dart`.

Pruebas FullPOS:

- `apps/fulltech_app/test/core/ai_assistant/ai_support_case_link_test.dart`.
- `apps/fulltech_app/test/core/ai_assistant/ai_assistant_sheet_composer_test.dart`.
- Referencias visuales `goldens/assistant_1280.png`, `assistant_390.png` y sus
  equivalentes propios de Linux, dentro de esa carpeta de pruebas.

CRM: worktree separado `C:/src/appyra-crm-fullpos-support-20261120`, rama
`agent/fullpos-support-bridge-20261120`, creado desde `6ec945c`. No se editó el
worktree original de CRM, que tiene otros trabajos de cobros/licencias pendientes.

- `backend/server/fullpos-support.mjs`, `backend/tests/fullpos-support.test.js`.
- `backend/server/crm-server.mjs`.
- `backend/server/ops/tickets.mjs`, `messages.mjs`, `routes.mjs`.
- `app/lib/data/crm_repository.dart`.
- `app/lib/features/soporte/soporte_screen.dart`, `support_case.dart`.
- `app/test/soporte_screen_test.dart`.
- `app/test/goldens/fullpos_support_visibility.png`.

## Validaciones ejecutadas

| Comando / comprobación | Resultado observado |
| --- | --- |
| `npm run api:build` desde FullPOS, mediante lanzador del laboratorio | PASS, Prisma generate y TypeScript; sin migraciones |
| `npx tsc -p apps/api/tsconfig.build.json --noEmit` | PASS |
| `npm --workspace apps/api test -- --testPathPatterns=ai-assistant` | 57 pruebas PASS |
| `flutter analyze --no-pub lib/core/ai_assistant test/core/ai_assistant` | PASS, cero incidencias |
| `flutter test --no-pub test/core/ai_assistant` | 51 PASS en Windows |
| Mismo conjunto en contenedor Flutter 3.41.6, sin red, con referencias Linux | 51 PASS |
| `flutter build web --release --no-pub` con defines UAT locales | PASS; avisos preexistentes del ensayo Wasm, compilación JavaScript correcta |
| CRM `npm test -- --run tests/fullpos-support.test.js tests/ops-tickets.test.js tests/ops-notifications.test.js tests/ops-support-cases.test.js` | 40 PASS |
| CRM `flutter test --no-pub test/soporte_screen_test.dart test/soporte_http_test.dart` | 13 PASS antes del nuevo test de visibilidad |
| CRM `flutter test --no-pub test/soporte_screen_test.dart --update-goldens` | 10 PASS, incluyendo nueva visibilidad y reinicio a nota interna |
| CRM `flutter analyze --no-pub lib/features/soporte` | PASS |
| CRM análisis incluyendo `lib/data/crm_repository.dart` | 6 info preexistentes de estilo, sin errores ni warnings; diff no modifica esas líneas |
| CRM `flutter build windows --debug --no-pub` con destino local | PASS, ejecutable local generado |
| CRM `npm audit --omit=dev --json` | 0 vulnerabilidades de producción |
| `git diff --check` en las áreas modificadas | PASS |

Prueba funcional real local: inicio JWT de dos empresas ficticias, backend FullPOS,
PostgreSQL aislado, HTTP firmado hacia CRM, SQLite aislado, bandeja de soporte,
notificación persistida, respuesta visible, bloqueo de otra empresa, notas internas
ocultas y reintento sin duplicación. Evidencia: `soporte-crm/e2e.json`.

Prueba real de navegador a 1280 y 390 px: crea el caso desde el chat, recibe una
respuesta enviada por API del CRM y la visualiza en la columna. Una sola ventana,
sin WhatsApp y sin errores JavaScript. Evidencia: `soporte-crm/visual.json` y PNG.
La captura de la pantalla CRM es una prueba de widget con datos ficticios,
no una sesión autenticada nativa ni una captura de producción.

Fallos detectados y corregidos: el primer test de bandeja usaba una propiedad
incorrecta; la comprobación geométrica trataba un borde coincidente como fuera;
se corrigió un estado En curso prematuro y una notificación duplicada al responder.
El primer intento Linux usó rutas de caché incorrectas; se repitió sin red con
las rutas propias correctas y pasó. CRM no configura plataforma web; no se añadió
esa plataforma, se compiló Windows y se verificó el widget existente.

## Pendientes y límites

- CONCURRENT WRITER RISK: apareció `databaseUrl: ''` en la prueba nueva de CRM
  sin poder atribuir esa edición. Es un endurecimiento útil para evitar un destino
  heredado, pero se detuvieron las escrituras CRM y se pidió aclarar su escritor.
- No se ha ejecutado el puente del CRM sobre PostgreSQL; la integración real de
  CRM ensayada aquí utiliza SQLite. FullPOS sí utilizó PostgreSQL local real.
- Falta revisión nativa autenticada del CRM. Se abrió el ejecutable local y se
  observó su acceso. La habilidad computer-use prohíbe automatizar los diálogos
  de autenticación (`docs/guidance.md`: “Do not automate user authentication dialogs”).
- Web Push está desactivado en el laboratorio: se verificó la notificación interna
  persistida, no la entrega a un dispositivo. No se envió WhatsApp, correo o SMS.
- El seguimiento se actualiza cada ocho segundos mientras el hilo está abierto;
  no se implementó una notificación de sistema del cliente con el chat cerrado.
- El enlace al caso vive en la conversación local actual del chat. No se añadió
  una bandeja histórica de casos del cliente ni sincronización de casos antiguos
  guardados exclusivamente en APPYRA IA antes de este puente.
- Las incidencias de npm ci inicial corresponden a dependencias de desarrollo;
  no se cambiaron paquetes ni lockfile para ampliar este alcance.

Estado: NO-GO para producción/publicación. El circuito local principal pasó;
faltan resolver la concurrencia, revisar/integrar los dos árboles, preparar la
configuración dedicada, revisar la sesión CRM y autorizar la publicación.
