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
