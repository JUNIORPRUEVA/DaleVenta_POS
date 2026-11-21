# 16 — Rediseño de la pantalla «Catálogo de planes»

Fecha: 2026-11-19
Alcance: **solo la pantalla de catálogo** (`PlansCatalogScreen`). No cambia
lógica, precios, permisos ni llamadas al servidor.

## Qué pedía el cliente

- Menos azul.
- Que no se vea «tan cuadrado».
- Más fino y elegante.
- El mínimo texto posible.
- Que en teléfono también quede bien.

## Qué se cambió

### 1. Tarjetas (`plan_card.dart`)

| Antes | Ahora |
| --- | --- |
| Borde recto de 1 px azul en el plan recomendado | Tarjeta blanca con radio 18 y borde fino gris; el recomendado lleva borde grafito y sombra suave |
| Franja azul «MÁS ELEGIDO» a todo el ancho | Etiqueta pequeña «Más elegido» en la esquina |
| «FULLPOS» + nombre en mayúsculas | Solo el nombre del plan |
| Frase descriptiva por plan (`planSummary`) | Eliminada |
| 6 funciones con checks y texto a 12.5 | 6 en escritorio y 4 en teléfono, texto más contenido |
| Botón recto azul «Cambiar plan a este» | Botón redondeado «Elegir plan»: grafito en el recomendado, contorno gris en el resto y gris plano «Tu plan» en el actual |
| 4 columnas con separación 14 | 4 / 2 / 1 columnas con separación 18 y huecos reservados (un solo plan no se estira a todo el ancho) |

Los tonos nuevos viven en una clase privada `_Ink` dentro de `plan_card.dart`
(grafito `#111827`, texto `#5A6572`, líneas `#E8ECF1`, check `#0F9D6E`). **No**
se tocaron `AppColors` ni el botón `SquareButton`, que siguen usando las demás
pantallas.

### 2. Encabezado (`plans_catalog_screen.dart`)

- Se quita el rótulo «CATALOGO» y el párrafo de tres líneas.
- Queda el título y **una** línea: «Cambia cuando quieras. Tus datos no se tocan.»
- En el camino de mejora: «Sube de plan» + «Planes superiores a Pro.»
- En el plan máximo: «Ya estás en el último plan» y el panel de soporte, ahora
  también con tarjeta redondeada y botón redondeado.

## Verificación

| Comprobación | Resultado |
| --- | --- |
| `flutter analyze lib/features/plans` | Sin problemas |
| `flutter test test/features/plans/plans_sections_test.dart` | 12/12 en verde |
| Captura 1280 × 800 (catálogo) | Revisada |
| Captura 390 × 844 (catálogo) | Revisada |
| Solo planes superiores (`?superiores=1`) 1280 × 800 | Revisada: la tarjeta conserva su ancho |
| Panel «último plan» | Cubierto por pruebas (sin excepción de layout); **no verificado visualmente** |

Capturas: `docs/design-research/2026-11-19/2-catalogo-pc.png`,
`2-catalogo-movil.png`, `2b-catalogo-superiores-pc.png` y
`2b-catalogo-superiores-movil.png`. Se ven en el visor
`docs/design-research/2026-11-19/revision-pantallas.html` con el conmutador
PC / Móvil.

## Lo que **no** se tocó

- Lógica de compra, prorrateo, `orderQuoteProvider` ni el paso a pago.
- `AppColors`, `SquareButton`, `PlansPanel` ni las otras tres pantallas
  (plan actual, transferencia, historial), que siguen con el estilo recto.
- La barra superior azul del teléfono: es el color de marca global
  (`CustomAppBar`), no del catálogo.

## Pendiente de decisión del cliente

1. ¿«Elegir plan» es suficientemente claro o prefiere «Cambiar a este plan»?
2. ¿Se echa en falta alguna frase por plan (para quién es cada uno)?
3. Si le gusta este estilo, el siguiente paso es aplicarlo a las otras tres
   pantallas para que la sección quede coherente.

## Actualización verificada — 21/11/2026

Esta sección sustituye las decisiones visuales anteriores que entren en
conflicto con la solicitud actual del propietario. Trabajo aislado en
`C:/t/fppl-7e92-20261120`, rama `agent/product-lifecycle-private-20261120`.
El commit visual anterior quedó en `57b4e095`. No se publicó ni se modificó
producción. Precios, prorrateos, reglas de activación y permisos comerciales
siguen siendo responsabilidad del backend existente.

### Fallos reproducidos y corregidos

1. El botón de comprobante dependía de una cotización recién consultada:
   fallaba si esa consulta daba error o cambiaba el crédito. Ahora una orden
   pendiente válida conserva su importe y permite adjuntar el comprobante.
2. Reabrir una orden de varios meses restablecía el selector a un mes. Se
   conserva el período guardado salvo elección expresa del cliente.
3. «Confirmar pago» solo emitía un mensaje local. Se eliminó: después de
   subir se muestra «Comprobante recibido» y el acceso al estado real del pago.
   La interfaz distingue recepción, disponibilidad del plan y pago verificado.
4. El selector de archivos quedaba fuera de la protección contra doble clic.
   Selección, lectura y envío ahora comparten el estado ocupado y el manejo de
   errores. Cancelar el selector no envía nada; se valida archivo vacío y 8 MB.
5. El historial del servidor omitía los metadatos del comprobante ya guardado.
   Se devuelven identificador, MIME, tamaño y fecha; nunca la ruta privada ni OCR.
6. Una orden vencida aceptaba archivos antes de actualizar el historial. Se
   comprueba su vencimiento antes del procesamiento y dentro de la transacción.
7. Tres creaciones simultáneas podían producir dos órdenes. La creación y
   reutilización se serializan por empresa mediante bloqueo transaccional.
8. Cancelar mientras se recibía un comprobante podía sobrescribir el estado.
   La cancelación bloquea la fila y vuelve a comprobar sus datos; devuelve
   conflicto si ya se recibió el archivo. No se elimina la evidencia.
9. Un fallo al cargar pagos podía parecer ausencia de órdenes o suscripción
   al día. Se muestran error y reintento; no se afirma un estado sin comprobar.
10. El historial afirmaba que revisión equivalía a licencia activa. El texto
    ahora explica que recibir un comprobante no confirma todavía el pago.

Tras una respuesta incierta se vuelve a consultar el historial; no se anuncia
recepción sin validar la respuesta. La subida exige identidad de orden,
identificador de evidencia, estado reconocido y bandera de activación explícita.
Los identificadores de las rutas privadas tienen validación UUID y conservan
autenticación, permisos y aislamiento por empresa.

### Catálogo y avisos

- Ancho máximo del catálogo: 1.440 px; cuatro columnas desde 1.180 px de
  espacio disponible, dos desde 660 y una en teléfono.
- En escritorio aumentan tipografía, precio y espacio interior. El plan
  actual ofrece «Renovar plan» habilitado. Botones cuadrados de 46 px.
- Se mantiene la tipografía compacta del teléfono. El enlace al historial
  conserva contraste blanco sobre el appbar azul del móvil.
- Los avisos usan `AppFeedback`: párrafo compacto arriba a la derecha,
  con el filtrado de identificadores y el ciclo de vida compartidos.

### Verificación y límites

| Verificación | Resultado |
| --- | --- |
| Flutter, sección Planes | 69 pruebas pasan |
| Análisis estático de Planes y pruebas nuevas | Sin incidencias |
| Backend, órdenes/evidencias/planes/renovación | 115 pruebas pasan |
| Integración de dominio en PostgreSQL aislado | 19 pruebas pasan |
| HTTP real con multipart y comprobación SQL | 7 grupos de escenarios pasan |
| Windows nativo, orden de tres meses y PDF real con cotización fallida | Subida única, recepción e historial comprobados |
| SQL independiente después de Windows | Una evidencia, tres meses, EVIDENCE_RECEIVED, activación NONE y licencia TRIAL sin cambios |
| Vista previa Flutter Web | Catálogo, pago e historial en 1.920, 1.280 y 390 px; nueve capturas, sin peticiones API ni desbordamiento horizontal |
| Compilación API, Windows y vista previa Web | Correcta |

Los escenarios HTTP incluyen aislamiento entre empresas, ausencia de sesión,
firma falsa, duplicados, vencimiento, descarga privada con bytes originales y
la carrera real entre cancelación y subida. Windows utiliza bytes de un PDF
sintético mediante HTTP real; solo se automatiza la elección del archivo en
el selector del sistema operativo. Se comprueba también que la cola offline
no cambia. La API privada escucha en 4018 y usa exclusivamente la base
`fullpos_plans_payment_20261121` en PostgreSQL local 56562; el puerto 4004 y
las otras sesiones se conservaron. La suite de dominio usa otra base exclusiva
`appyra_license_e2e`, puerto local 56701.

Las pruebas de dominio simulan resultados OCR y activación en su fixture;
no acreditan conciliación bancaria externa. En las pruebas HTTP/Windows no
se habilitó activación de prueba, OCR externo ni envíos reales. No se hizo
una transferencia bancaria, operación financiera real, migración o seed de
producción. Android/iPhone físicos no se probaron en este cambio.

**Resultado:** correcciones verificadas localmente y listas para revisión.
**NO-GO de publicación automática:** una publicación y la validación bancaria
real requieren su proceso independiente. No se afirma ausencia absoluta de
riesgos ni se cambia la política financiera para lograr pruebas verdes.

### Evidencia y reproducción

Evidencia local ignorada por Git: `.uat/plans-payment/`.
`plans-reproduced.log` está en `.uat/product-lifecycle/` y conserva los tres
fallos iniciales de Flutter. `http-reproduced.log`, `expired-reproduced.log`,
`concurrent-reproduced.log` y `cancel-reproduced.log` conservan los fallos HTTP.
`http-verified.log`, `http-result.json`, `flutter-tests-final.log`,
`analyze-final.log`, `backend-tests-final.log`, `domain-integration.log`,
`windows-functional.log`, `native-result.json`, `native-sql-result.json` y
`design-evidence/` contienen los resultados finales. No versionar credenciales
sintéticas, archivos privados, perfiles del navegador ni datos locales.

Scripts reproducibles: `scripts/uat/plans-payment-lab.cjs` (init/serve),
`plans-payment-http.cjs`, `plans-payment-verify-native.cjs`,
`plans-payment-design.cjs` y `preview-plans-payment.cjs`. Prueba nativa:
`apps/fulltech_app/integration_test/plans_payment_native_test.dart`.
La vista previa en `http://127.0.0.1:4495/#/planes/catalogo` contiene datos
ficticios, rechaza todas las llamadas API y simula escrituras en memoria.
No se transmite el archivo elegido ni se activa una licencia desde la vista
previa. Esa simulación pertenece al entrypoint de diseño, no al arranque real.

## Cierre del flujo FullPOS → puente → APPYRA CRM — 21/11/2026

Solicitud posterior del propietario: tarjetas más altas, sin esquinas
redondeadas; verificar registros nuevos, administración y transferencias en CRM.
Las tarjetas tienen altura mínima de 520 px en escritorio y 320 px en móvil,
esquinas y etiqueta rectas, con los botones alineados al pie. Se revisaron las
nueve capturas de catálogo, pago e historial en 1920, 1280 y 390 px.

### Defectos reproducidos y resultado

- El listado de Pagos del puente respondía 501. Ahora proyecta las órdenes
  reales de FullPOS, con filtros, paginación y estados pendientes/confirmados.
  No consulta la tabla histórica de otro producto ni concede pagos por leerla.
- El catálogo del CRM consultaba otro catálogo comercial. Ahora consume el
  catálogo público de FullPOS, incluidos precios, cupos, funciones y versión.
  Ese endpoint devuelve únicamente planes activos; no se editan precios aquí.
- La ficha del puente omitía la versión de concurrencia y el comando de
  edición omitía el actor humano. Se conservan versión y actor de la sesión;
  identidad del servicio, permisos, versión, idempotencia y auditoría siguen
  siendo obligatorios en FullPOS.
- «Pagado» enviaba un comando incompleto y su acción no estaba en la lista de
  auditoría permitida. Se corrigen ambos contratos. Flutter persiste en su
  almacén privado el UUID, versión y decisión antes de enviarlos. Un corte o
  reinicio conserva el mismo comando; no cambia a una decisión opuesta mientras
  el resultado sea incierto. Se agregan los métodos del repositorio que faltaban.
- Confirmar una orden recibida sin activación provisional podía marcarla
  confirmada sin aplicar sus meses. Ahora se aplica el plan con el motor de
  activación existente, dentro de la misma transacción que orden y auditoría.
  Si ya hubo activación provisional, se consolida sin volver a aplicar meses.
  Una orden sin comprobante o ya finalizada rechaza una decisión nueva; repetir
  el UUID y cuerpo originales devuelve el resultado idempotente.
- La cola de avisos no tenía colección declarada: el almacén real rechazaba
  sus escrituras. Se agrega colección e índices únicos, sin borrar registros.
  La clave del aviso incorpora orden y evidencia completas. El mensaje utiliza
  los diez datos persistidos, no nombres de campos incompatibles ni importes
  cero para datos ausentes. Sin análisis no se anuncia «válido».
- Los barridos y la pantalla revisaban solo las primeras licencias. Se añade
  una consulta global paginada de órdenes con comprobante. El barrido limitado
  conserva su posición para continuar; la pantalla consulta todas las páginas.
  Un fallo parcial no se presenta como ausencia de pagos.
- PDF se trataba como imagen tanto en Flutter como en la cabecera del aviso.
  El CRM descarga el PDF por su sesión y ofrece abrirlo como documento. Los
  avisos PDF requieren una plantilla aprobada con cabecera DOCUMENT; las fotos
  usan IMAGE. Ambas conservan diez parámetros de texto. No se publica el archivo.
- La descarga del puente valida además la correspondencia entre empresa,
  orden y evidencia. Una combinación incorrecta responde 404, y sin sesión
  el CRM responde 401.
- Cada comprobante genera también una notificación interna para los
  administradores activos, con clave idempotente por destinatario. La campana
  funciona sin Meta. El barrido se programa por defecto cada 60 segundos cuando
  licencias y el scheduler están habilitados; cero lo desactiva explícitamente.

### Pruebas del candidato aplicado

| Comprobación | Evidencia |
| --- | --- |
| FullPOS Flutter | 69 pruebas de Planes pasan; análisis sin incidencias |
| Backend FullPOS | 147 pruebas pasan en 16 suites, incluidas integración real de licencias, pagos y preservación fiscal |
| Backend CRM | 51 pruebas pasan en cinco archivos |
| Flutter CRM | 20 pruebas pasan, incluidas recuperación de decisión incierta, paginación y pantallas |
| Windows CRM con HTTP real | PDF privado → confirmación explícita → pago confirmado en listado y SQL |
| Flujo entre los tres servicios | 12 grupos de escenarios pasan; cero errores en el resultado final |

El escenario real registra una empresa sintética en FullPOS y la encuentra en
**Licencias del CRM**; compara catálogo, cupos y precios; guarda un PDF real,
lo consulta en Pagos y lo descarga como administrador; rechaza una empresa
incorrecta; persiste un solo aviso y una sola notificación interna tras dos
barridos; prueba el envío de PDF y diez campos mediante transporte grabador;
edita una licencia y confirma tres meses. También rechaza una decisión sobre
un pago ya finalizado o sin archivo y demuestra que rechazar otro comprobante
no recorta el período pagado anterior.

Windows abre las pantallas reales del CRM, solicita el PDF a través del puente
y confirma una segunda orden desde Flutter usando el almacén seguro. La
comprobación independiente de PostgreSQL prueba que esa renovación empieza al
terminar el período pagado y suma exactamente tres meses, una sola vez.
Se mantienen seis avisos de estilo del analizador en código anterior del
repositorio CRM; no hay errores de compilación ni incidencias nuevas de análisis.

Se reutilizaron únicamente binarios nativos locales que coincidían con los
hashes exigidos por sus paquetes: SQLite SHA-256 y mpv MD5. No se alteraron esas
dependencias ni sus comprobaciones de integridad. La selección temporal de la
fuente local de SQLite se retiró del pubspec al terminar las pruebas. El destino
de instalación del build CRM se limitó a su runner privado, no Program Files.

### Archivos originales, evidencia y límites de publicación

Los worktrees originales de CRM y del puente contenían trabajo ajeno sin commit.
Se copiaron sus fuentes a `C:/t/crm-plans-20261121` y
`C:/t/bridge-plans-20261121`, sin sus entornos, credenciales ni datos. Se conservó
ese trabajo y se comprobó que las fuentes originales no habían cambiado.
Después de validar, se aplicó el delta de 16 archivos a sus proyectos originales
y se verificó por SHA-256 normalizado que coincide con el candidato probado:

- CRM: `C:/Users/pc/DEV/PROYECTOS/INTERNO/APPYRA_CRM`.
- Puente: `C:/Users/pc/DEV/PROYECTOS/PRODUCTOS/CARPETA FULLPOS/FULLTECHPOS_BAKEND_LICENCIA`.
- FullPOS: `C:/t/fppl-7e92-20261120`.

`scripts/uat/plans-crm-flow.cjs --windows` reproduce el recorrido HTTP y Windows
con PostgreSQL local 56562 y API privada 4019. Cada ejecución crea bases nuevas
para CRM y credenciales del puente; las empresas y los archivos son sintéticos.
No elimina las bases anteriores. La suite de dominio usa exclusivamente las
bases de fixture explícitas en el PostgreSQL local 56701.
La evidencia está en `.uat/plans-crm/result.json`, `native-result.json`,
`windows.log`, `crm-windows-*.png` y `source-manifest.json`; los respaldos previos
al delta están en `source-before/`. Las pruebas complementarias están en
`.uat/plans-payment/crm-verified.log`, `crm-all-domain-tests.log`,
`square-tests.log`, `square-analyze.log` y `square-design-check.log`.
Los archivos privados de prueba y las credenciales no se versionan.

**GO local del recorrido probado. NO-GO de publicación automática.** No se
desplegaron servicios, cambiaron variables productivas ni realizaron pagos
reales. El transporte de WhatsApp se grabó en pruebas; no acredita entrega real
por Meta. Para envío real hacen falta el número del administrador, credenciales
vigentes, el interruptor de envío y plantillas aprobadas: la existente
`licencia_comprobante_soporte` con cabecera IMAGE y la plantilla PDF configurada
por `LICENSE_EVIDENCE_DOCUMENT_TEMPLATE` (por defecto
`licencia_comprobante_soporte_pdf`) con cabecera DOCUMENT, idioma español y diez
parámetros. Sin aprobación el aviso permanece pendiente y el pago queda visible
en el CRM. Debe configurarse un único emisor de avisos para evitar que CRM y el
notificador previo de FullPOS envíen el mismo suceso por separado.
El registro aparece por consulta autoritativa en Licencias; no se crea una ficha
de contacto WhatsApp inventando identidad o teléfono a partir de una empresa.

## Verificación final de administración manual — 21/11/2026

Se amplió la comprobación a los botones reales de **Licencias** del CRM,
no únicamente a peticiones HTTP o a una compilación. Se reprodujeron y corrigieron
cuatro defectos adicionales:

1. La ficha exponía `version`, pero el workspace y el diálogo buscaban
   `updatedAt`; podían ocultar los controles o enviar una versión vacía. El
   puente conserva ambos nombres compatibles y el diálogo acepta cualquiera.
   Las capacidades de escritura ahora consultan también el interruptor real del
   backend FullPOS, además del permiso de la credencial del puente.
2. Editar cupos configurados de una empresa con catálogo no cambiaba sus cupos
   efectivos. El comando versionado convierte el total solicitado en extras
   sobre el mismo plan. Se preservan la tarifa, vigencia, clave y demás
   concesiones. Repetirlo no suma extras de nuevo; bajar del paquete contratado
   o del uso real se rechaza. No se reviven concesiones vencidas implícitamente.
   El editor incluye usuarios, productos, almacenes y funciones adicionales.
   Lo incluido en el plan aparece marcado y no se retira desde la concesión.
3. La activación inicial mediante el motor de planes podía dejar la clave nula;
   una suspensión posterior quedaba sin reactivación. Las activaciones
   autorizadas generan la clave únicamente si falta, con el generador y formato
   existentes compartidos. Renovar y reactivar conservan las claves anteriores.
   No se añadieron activaciones gratuitas ni se omitió la verificación del pago.
4. La pestaña de actividad recibía un listado de auditoría donde esperaba el
   informe estructurado de actividad de FullPOS. El puente consulta el endpoint
   real de actividad y verifica empresa/autoridad. La ficha conserva por separado
   una auditoría saneada de acción, motivo y fecha, sin claves ni payload interno.

**Recorrido Windows/HTTP/SQL:** una cuenta sintética contrata Básico; el
administrador confirma su comprobante en Cobros; desde la pantalla real de
Licencias aumenta el total a **2 usuarios, 125 productos y 2 almacenes**, concede
Mayoreo y Varios almacenes, suspende, reactiva, retira Mayoreo y revoca. FullPOS
confirma por su propia API el cupo efectivo de 125 productos. La suspensión
invalida el acceso probado y la reactivación permite un nuevo inicio de sesión,
sin ampliar fechas. Revocar limpia la clave y bloquea el acceso; una reactivación
posterior sin clave/período válido se rechaza. PostgreSQL conserva el producto,
el usuario, el pago confirmado y los registros de auditoría de todas las acciones.
Los interruptores fiscales y de operación existentes no cambian al conceder
una función comercial. Tampoco se modificó el catálogo compartido de precios.

Verificación complementaria: **149 pruebas del backend FullPOS en 16 suites**,
incluida preservación fiscal y las regresiones de cupos/clave; **31 pruebas
Flutter de administración y recuperación de decisiones**; análisis de los
archivos nuevos y del diálogo sin incidencias. La compilación de Windows y la
prueba nativa forman parte del recorrido real, con evidencia independiente SQL.

Evidencia de esta ampliación: `.uat/plans-admin/flow.log`, `windows.log`,
`native-result.json`, `domain-tests.log`, `types.log` y `admin-*.png`.
El resultado agregado queda en `.uat/plans-crm/result.json`.
Se reproduce con `node scripts/uat/plans-crm-flow.cjs --admin-windows`, usando
exclusivamente las empresas, archivos, credenciales y bases locales sintéticas.
Las fuentes originales de CRM/puente se respaldan y verifican antes de aplicar
el delta; no se modifica el trabajo simultáneo de otras sesiones.

**Significado de las acciones:** activar/renovar se realiza confirmando el pago
en Cobros; reactivar recupera un período pagado vigente; «Eliminar licencia»
revoca la licencia y conserva la empresa y su historial. Editar ajusta la
concesión del negocio concreto, no los planes de todos los clientes. Conceder
facturación electrónica no configura ni habilita por sí solo la emisión fiscal.
Se mantiene el GO local del recorrido probado y el NO-GO de publicación
automática; no se cambió producción ni se realizaron operaciones financieras reales.
