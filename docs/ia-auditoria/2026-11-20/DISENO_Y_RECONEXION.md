# Cierre local de diseño y reconexión — 20 de noviembre de 2026

## Resultado

**GO para revisión local del diseño. NO-GO para publicación productiva hasta la
revisión y autorización del propietario y sus controles de publicación.**
El bloqueo del reintento descrito en [OPENAI.md](OPENAI.md) queda resuelto para el
flujo real de la interfaz. Se conservan sus ensayos fallidos como historial.

Se trabajó únicamente en `C:/src/fullpos-ultimos-ajustes-ia`, rama
`agent/ultimos-ajustes-de-la-ia`. El trabajo previo de este árbol y de APPYRA se
conserva; no se editó el worktree del otro agente. Sin push, merge, despliegue,
reinicios productivos, migraciones ni cambios fiscales o de licencias.

## Cambios solicitados

- **Panel y mensajes:** superficies del tema, burbujas más sobrias, sin sombra por
  mensaje, títulos discretos, contraste legible y saludo más breve. Se mantienen
  texto completo, énfasis, adjuntos, referencias reales de averías y avisos.
- **Escritura y botones:** compositor delimitado y agrupado, controles compactos
  con radios consistentes, etiquetas accesibles sin repetición y acciones de
  ayuda con colores neutros. Se mantienen adjuntos y grabación de voz.
- **Acceso a IA:** reducción mínima de cuatro píxeles: compacto 64→60 y normal
  72→68. El área accesible sigue siendo mayor de 48 píxeles; acción y etiqueta se
  conservaron. La posición móvil se centra con el nuevo tamaño.
- **Fuentes:** se retiraron los chips visuales azules. No se eliminaron las citas
  del contrato ni del estado; una prueba y la consulta real verifican que siguen
  llegando. No se altera la fundamentación del modelo para ocultarlas.
- **Reconexión:** el aviso ofrece `Reintentar`. Recupera el texto original y su
  identificador sin obligar a escribirlo de nuevo, sin duplicar la burbuja y sin
  reintentos automáticos. Cambiar módulo descarta la petición pendiente; cambiar
  el adjunto impide reutilizar un identificador que pertenecía a otro archivo.

## Archivos de esta continuación

| Archivo en FullPOS | Finalidad |
| --- | --- |
| `apps/fulltech_app/lib/core/ai_assistant/application/ai_assistant_controller.dart` | Reintento explícito, identidad y deduplicación visual; saludo |
| `apps/fulltech_app/lib/core/ai_assistant/presentation/widgets/ai_assistant_sheet.dart` | Estilo, compositor, fuentes ocultas y acción de reintento |
| `apps/fulltech_app/lib/core/ai_assistant/presentation/widgets/ai_assistant_dock_button.dart` | Tamaño y sombra del acceso |
| `apps/fulltech_app/lib/core/ai_assistant/presentation/widgets/global_ai_assistant_entry_point.dart` | Centrado móvil |
| `apps/fulltech_app/test/core/ai_assistant/ai_assistant_controller_test.dart` | Texto/ID, adjunto distinto, módulo distinto y mensaje único |
| `apps/fulltech_app/test/core/ai_assistant/ai_assistant_sheet_composer_test.dart` | Citas conservadas sin chips, reintento desde el botón y tamaño accesible |
| `apps/fulltech_app/test/core/ai_assistant/goldens/assistant_{1280,390,button,dock}.png` | Cuatro referencias Windows revisadas |
| `apps/fulltech_app/test/core/ai_assistant/goldens/linux/assistant_{1280,390,button,dock}.png` | Cuatro referencias producidas y verificadas en Linux |
| `docs/EXECUTION_STATE.md`, informes y evidencias de esta carpeta | Continuidad y pruebas |

La lista es incremental respecto al trabajo previo del mismo árbol; no atribuye
de nuevo los cambios anteriores de backend, aislamiento o recuperación.

## Verificaciones ejecutadas

```text
flutter test test/core/ai_assistant
39 PASS en Windows

flutter analyze
PASS, sin incidencias, 5,8 s

flutter build web --release --dart-define=FULLPOS_UAT_PROFILE=true --dart-define=FULLPOS_UAT_BUILD=true --dart-define=APP_ENV=uat --dart-define=API_BASE_URL=http://127.0.0.1:4004/api --dart-define=APP_BASE_URL=http://127.0.0.1:4004
PASS, 136,4 s

flutter test test/core/ai_assistant test/core/api/api_offline_circuit_breaker_test.dart test/core/auth
81 PASS, 16 s

flutter test --no-pub test/core/ai_assistant/ai_assistant_sheet_composer_test.dart --update-goldens
PASS en contenedor Linux Flutter 3.41.6; 13 pruebas

flutter test --no-pub test/core/ai_assistant
39 PASS en Linux, comparando las referencias nuevas, sin actualizarlas

node <laboratorio privado>/ia_polish_browser.cjs
PASS, escritorio 1280×900, interfaces y llamadas reales

node <laboratorio privado>/ia_polish_browser.cjs --mobile
PASS, viewport 390×844, interfaces y llamadas reales

node <laboratorio privado>/ia_polish_pg.cjs
PASS, consulta de sólo lectura a PostgreSQL local

git diff --check
PASS
```

La copia Linux se creó sin archivos de entorno originales, con URL ficticia
local y sin credenciales. El contenedor temporal sólo accedió a esa copia.
Las referencias Linux se generaron en Linux, sin copiar las de Windows ni
desactivar comparaciones. Los contenedores de otros proyectos no se tocaron.

### Prueba real y fallo simulado, claramente separados

Flutter, FullPOS API, APPYRA y PostgreSQL se ejecutaron realmente en el laboratorio.
Las respuestas iniciales usaron **OpenAI Astra externo**, con contenido completo
de cotizaciones y citas recibidas; se comprobó que sus chips no aparecían.

Playwright interceptó la siguiente petición, la envió al backend real con
`route.fetch()`, obtuvo su respuesta y **simuló perderla antes de entregarla al
cliente**. La app mostró un solo aviso. Después de respetar la pausa existente
de 12 s del circuito de red, se pulsó `Reintentar` desde la interfaz.

En escritorio y móvil se comprobaron: mismo texto, mismo `clientMessageId`,
misma respuesta y conversación, cero reintentos automáticos, una sola burbuja
del usuario y compositor operativo tras recibir la respuesta. PostgreSQL
confirma **un solo turno**, y cero coincidencias al filtrar por la otra empresa.
No es una desconexión física ni una prueba con datos productivos.

## Evidencias inspeccionadas

- [Escritorio, respuesta sin fuentes](diseno-reconexion/escritorio.png).
- [Móvil, aviso con reintento](diseno-reconexion/movil-sin-conexion.png).
- [Móvil, respuesta recuperada](diseno-reconexion/movil-recuperado.png).
- [Escritorio, comprobaciones](diseno-reconexion/escritorio-resultados.json).
- [Móvil, comprobaciones](diseno-reconexion/movil-resultados.json).
- [Un turno persistido y aislamiento](diseno-reconexion/postgresql.json).

### Fallos detectados durante la validación y corregidos

- Las referencias visuales anteriores fallaron con el diseño solicitado. Se
  revisaron las imágenes y se actualizaron en sus plataformas respectivas.
  El control de píxeles y las aserciones de layout se conservaron.
- Una etiqueta accesible dejó de aparecer al retirar su duplicado; se declaró
  una sola etiqueta y acción Semantics explícita, y las pruebas pasan.
- El análisis exigió llaves en una condición nueva; se corrigió y repitió.
- El primer ejecutor esperaba HTTP 200. El POST real responde HTTP 201; se
  comprobó éxito HTTP con `ok()` sin cambiar el contrato del backend.
- Linux sin red no pudo descargar el binario SQLite que su hook solicita al
  compilar. La preparación manual de caché no bastó. Se permitió su descarga
  en el contenedor de pruebas, sin credenciales ni configuración productiva;
  las pruebas usan sus datasources simuladas. No se cambió SQLite, el lock,
  Prisma ni la base de datos para obtener un resultado favorable.
- Las capturas de recuperación esperan que termine el estado ocupado antes
  de tomarse; una respuesta HTTP por sí sola no demuestra el estado visual.

## Límites y siguiente paso

El diseño se puede revisar en `http://127.0.0.1:4004/__local_demo`, sólo en esta
máquina. No hay publicación ni cambios de configuración productiva. Se mantiene
la configuración local de Astra y su tope comercial; la activación productiva
requiere revisión propia del proveedor, asignación y transporte descritos en
[OPENAI.md](OPENAI.md). No se probó el bucle opcional de herramientas de Astra.

Las pruebas móviles son de Flutter web a 390 píxeles, no pruebas físicas iOS o
Android. Las conversaciones medidas no garantizan que el modelo nunca falle ni
que conozca todos los procedimientos posibles. El inventario de 597 omisiones
y los límites de cobertura permanecen en el informe inicial. No hay verificaciones
nuevas de GitHub Actions porque no se autorizó ni ejecutó un push.
