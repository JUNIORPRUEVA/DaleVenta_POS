# Mayoreo y listas de precios

## Estado de fase 1

El modulo queda desactivado por defecto con `Company.wholesalePriceListsEnabled = false`.
Cuando esta desactivado, ventas y cotizaciones conservan el comportamiento clasico:
el backend acepta el precio de linea existente y no recalcula automaticamente por lista.

## UAT aislado

- API: `http://127.0.0.1:4001`
- PostgreSQL: `127.0.0.1:56549/fullpos_mayoreo_uat`
- Contenedor: `fullpos_mayoreo_uat_postgres`
- Scripts: `scripts/isolated-uat/`

Antes de migrar o probar, ejecutar:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\isolated-uat\status.ps1
```

## Modelo

- `price_lists`: listas por empresa.
- `price_list_product_rules`: regla por producto/lista, con precio fijo o descuento porcentual.
- `price_list_quantity_tiers`: escalas por cantidad sobre una regla.
- `clients.default_price_list_id`: lista predeterminada del cliente.
- `sales`, `sale_items`, `cotizaciones`, `cotizacion_items`: snapshots de lista/regla aplicada.

## Endpoints iniciales

- `GET /price-lists`
- `POST /price-lists`
- `PATCH /price-lists/:id`
- `POST /price-lists/:id/rules`
- `PATCH /price-lists/clients/:clientId`
- `POST /price-lists/resolve-line`

Los endpoints administrativos requieren rol `ADMIN` o `ASISTENTE` y permiso `managePriceLists`.
La resolucion de precio exige tenant valido y nunca consulta productos, clientes ni listas de otra empresa.

## Pendiente despues de fase 1

- Pantalla Flutter completa para administrar listas, reglas y asignaciones de clientes.
- Integracion visual en POS/cotizaciones para seleccionar lista manualmente y aplicar el resultado de `resolve-line`.
- Pruebas funcionales end-to-end de venta/cotizacion con una lista activa.

## Fase 3 - contrato operativo

### POS

- Con `wholesalePriceListsEnabled = false`, el POS no muestra selector mayorista ni llama a `resolve-line`.
- Con Mayoreo activo, el POS muestra un selector compacto en el panel de cobro.
- La opcion predeterminada conserva el comportamiento "precio general / lista del cliente".
- Seleccionar manualmente una lista requiere autorizacion `selectManualPriceList` o autorizacion administrativa temporal.
- El POS bloquea el cobro mientras hay un recalculo mayorista pendiente.
- Las respuestas tardias de recalculos anteriores se descartan mediante un contador local de solicitud.
- La venta envia `priceListId` y `priceListManualOverride` solo cuando hay seleccion manual.
- El backend vuelve a validar empresa, lista activa, permisos, precio final y snapshots.

### Offline pendiente

Mayoreo todavia no debe declararse funcional offline. Para resolver precios sin red se necesita sincronizar:

- `priceListId`, nombre, estado activo, prioridad y version/fecha de actualizacion.
- Reglas por producto: producto, modo, cantidad minima, precio fijo, descuento porcentual.
- Escalas por cantidad con orden estable.
- Lista predeterminada del cliente.
- Snapshot de venta/cotizacion: lista, regla, modo, precio original, precio aplicado y fecha.
- Regla de invalidacion cuando la lista cambia mientras hay carritos abiertos.
- Idempotencia para ventas confirmadas offline: nunca recalcular ventas ya confirmadas al sincronizar.

Mientras ese contrato no exista en el worktree Offline, el POS tradicional no debe introducir llamadas obligatorias cuando Mayoreo esta apagado y Mayoreo con lista no debe prometer venta offline completa.

### Alanube pendiente

Mayoreo no reemplaza el motor fiscal. El contrato hacia facturacion electronica debe usar los importes finales ya persistidos por ventas/cotizaciones:

- precio unitario final,
- descuento de linea,
- base imponible,
- ITBIS,
- monto exento,
- total de linea,
- snapshots comerciales de lista/regla solo como metadatos auditable, no como fuente fiscal.

Alanube debe consumir los totales fiscales existentes y no recalcular precios mayoristas.

### Windows UAT

El build Windows UAT de Mayoreo queda separado de la instalacion normal cuando
se genera exclusivamente con:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build\build_windows_uat_release.ps1
```

Ese script:

- fuerza `FULLPOS_WINDOWS_CHANNEL=uat-mayoreo`,
- compila `fullpos_cloud_uat_mayoreo.exe`,
- inyecta `FULLPOS_UAT_BUILD=true`,
- exige `API_BASE_URL`/`APP_BASE_URL` explicitos,
- rechaza hosts productivos o compartidos conocidos,
- usa por defecto `http://127.0.0.1:4001`.

Identidad esperada del build UAT:

- ejecutable: `fullpos_cloud_uat_mayoreo.exe`,
- titulo: `FullPOS Cloud UAT - Mayoreo`,
- clase de ventana: `FULLPOS_UAT_MAYOREO_WIN32_WINDOW`,
- mutex: `Local\\DaleVentasPOSUATMayoreoSingleInstance`,
- raiz instalada: `%ProgramFiles%\\DaleVentas POS UAT Mayoreo`,
- override opcional: `DALEVENTAS_POS_UAT_MAYOREO_ROOT`,
- actualizaciones/logs: `%LOCALAPPDATA%\\DaleVentas POS UAT Mayoreo`,
- instalador Inno: compilar `installer/setup.iss` con `MyAppUatMayoreo`
  para usar `AppId`, carpeta, accesos directos y nombre de setup separados.

El build UAT no importa bases SQLite heredadas de la instalacion normal.
La primera apertura sigue requiriendo validar antes que el backend local UAT y
la base `fullpos_mayoreo_uat` esten levantados y que no haya URLs productivas.

## Fase 5 - cierre UAT funcional

### Estado verificado

- Repositorio: `C:\Users\pc\DEV\PROYECTOS\PRODUCTOS\FULLPOS-MAYOREO`.
- Rama: `feature/mayoreo`.
- Backend UAT: `http://127.0.0.1:4001`.
- PostgreSQL UAT: `127.0.0.1:56549/fullpos_mayoreo_uat`.
- Base UAT verificada con `scripts\isolated-uat\verify.ps1`.
- Migraciones UAT: `npx prisma migrate status` reporto schema al dia.
- Windows UAT: `fullpos_cloud_uat_mayoreo.exe` abre como proceso separado y
  muestra titulo `FullPOS Cloud UAT - Mayoreo`.
- Storage de primera ejecucion usado para prueba:
  `.uat-windows-storage\mayoreo`, con SQLite separado de la instalacion normal.

### Prueba HTTP UAT

Ejecutar con la API UAT activa:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\isolated-uat\test-mayoreo.ps1
```

La prueba crea datos sinteticos UAT y valida:

- Mayoreo apagado por defecto.
- Mayoreo apagado no aplica reglas.
- Activacion por empresa.
- Lista activa/inactiva.
- Precio fijo.
- Precio por escala de cantidad.
- Descuento porcentual por escala.
- Cliente con lista predeterminada.
- Rechazo de acceso cruzado entre empresas.
- Venta POS real con sesion de caja y snapshots de lista/regla.
- Rechazo de manipulacion de precio enviada desde cliente.
- Cotizacion real con snapshots de lista/regla.
- Rechazo de seleccion manual para vendedor sin permiso.

### Compatibilidad Offline y Alanube

- Offline: Mayoreo permanece compatible cuando esta apagado. La venta offline
  completa con listas requiere contrato posterior con el frente OFFLINE para
  sincronizar listas, reglas, escalas, lista default del cliente e
  invalidacion de carritos. No se debe prometer venta offline mayorista hasta
  integrar ese contrato.
- Alanube: Mayoreo no cambia el motor fiscal. Ventas/cotizaciones persisten los
  importes fiscales finales y snapshots comerciales; Alanube debe consumir los
  totales fiscales existentes, no recalcular precios mayoristas.

### Prueba manual Windows UAT

Con backend UAT activo, abrir sin instalar:

```powershell
.\scripts\isolated-uat\start-windows.ps1
```

El lanzador comprueba el ejecutable y la API local e inicia Mayoreo con su
carpeta `.uat-windows-storage\mayoreo`. No requiere cambiar variables persistentes
del usuario ni usar Program Files para los datos de esta prueba. Comprobacion
sin abrir otra ventana: `start-windows.ps1 -CheckOnly`.

Apertura equivalente explicita:

```powershell
$env:DALEVENTAS_POS_UAT_MAYOREO_ROOT = "$PWD\.uat-windows-storage\mayoreo"
Start-Process .\apps\fulltech_app\build\windows\x64\runner\Release\fullpos_cloud_uat_mayoreo.exe `
  -WorkingDirectory .\apps\fulltech_app\build\windows\x64\runner\Release
```

Validar manualmente:

- La ventana se titula `FullPOS Cloud UAT - Mayoreo`.
- No se cierra si `fullpos_cloud.exe` normal ya esta abierto.
- Login contra `http://127.0.0.1:4001`.
- Menu muestra Listas de precios solo con flag y permisos.
- POS y Cotizaciones aplican los precios de la prueba HTTP.
- No se crean ni modifican bases SQLite en `DaleVentas POS` normal.

## Fase 6 - verificacion del 18 de octubre de 2026

### Donde se configura

1. En Facturacion, abrir el menu superior **FullPOS > Empresa**.
2. En **Mayoreo**, activar **Listas de precios** y pulsar **Guardar empresa**.
3. Abrir el menu lateral **Inventario > Listas precios** (puede requerir desplazarse).
4. **Nueva lista** crea una lista. El lapiz **Editar lista** cambia nombre y descripcion.
5. Seleccionar una lista y **Elegir producto**. La busqueda consulta el servidor y permite cargar mas paginas.
6. Elegir **Precio fijo** o **Descuento**, indicar **Desde** y agregar las escalas necesarias; **Guardar regla** persiste los cambios.
7. **Cantidad > Probar** consulta el precio resuelto por el backend.
8. En el formulario del cliente, **Lista de precios** establece su lista predeterminada.

El interruptor de cada lista activa/desactiva su uso. Los permisos administrativos
siguen siendo `managePriceLists`; elegir otra lista en el carrito requiere
`selectManualPriceList` o la autorizacion existente. No se modificaron esos controles.

**Precio general / cliente** elimina la seleccion manual y aplica la lista del
cliente. Para consultar el precio general se necesita un cliente sin lista o
quitar el cliente del ticket. No significa ignorar la lista predeterminada.

### Defectos encontrados y cambios

- Reproducido en Windows: cambiar Mayorista a Distribuidor conservaba los precios
  del cliente anterior. Las rutas de seleccionar, editar y quitar cliente del
  editor compartido ahora invocan el recalculo existente.
- Guardar/cobrar y cambiar de ticket comprueban el recalculo pendiente.
- El recalculo captura sus lineas y contexto al iniciar, descarta resultados
  superados y restaura carrito, cliente, lista y datos fiscales ante un fallo.
- La eliminacion de lineas por cantidad, boton o atajo inicia un nuevo recalculo
  para invalidar respuestas pendientes que todavia incluyan la linea retirada.
- La venta del editor compartido envia el contexto de lista manual al backend.
- El borrador conserva la lista manual por ticket. Los borradores anteriores
  siguen leyendo ese campo como nulo.
- La administracion incorpora edicion visible de listas, precarga de reglas y
  escalas existentes, busqueda paginada, validacion y regreso a Facturacion.
- El script de compilacion reutiliza, si esta libre, la letra registrada en
  CMake para evitar el conflicto entre las rutas temporales X: e Y:.

### Evidencia de pruebas

| Comprobacion | Resultado observado |
| --- | --- |
| Backend general, `npm --workspace apps/api test` | 75 suites / 743 pruebas aprobadas; 8 omitidas |
| `npm run api:build` | PASS tras liberar la DLL usada por el proceso UAT |
| Flutter general, `flutter test --no-pub` | 1270 aprobadas / 1 omitida |
| Administracion de listas, prueba de widgets | 8 aprobadas tras agregar creacion y regreso |
| Regresion final de Cotizaciones y Listas, `flutter test --no-pub test/modules/cotizaciones test/features/price_lists` | 125 aprobadas tras conectar la eliminacion de lineas al recalculo |
| `flutter analyze --no-pub` | PASS en la revision final, incluido el boton de regreso |
| Compilacion Windows UAT, `build_windows_uat_release.ps1 -SkipPubGet` | PASS en la revision final; no se genero instalador de produccion |
| HTTP `scripts/isolated-uat/test-mayoreo.ps1` ampliado | PASS: limites, override persistido, snapshots historicos y flag apagado con reglas existentes |
| Windows: Mayorista, Cable 5 / Router 4 | 70 / 300 por unidad; importe 1550 |
| Windows: Distribuidor, mismas cantidades | 85 / 220 por unidad; importe 1305 |
| Windows: quitar cliente y override | 100 / 300 por unidad; importe 1700 |
| Windows: fallo controlado de backend | Restauro sin cliente y precios generales; reintento posterior a Distribuidor correcto |
| Windows: Mayoreo apagado | Oculto selector; ticket nuevo Cable 1 a 100 |
| Windows: activacion/configuracion | Menu Empresa y acceso Inventario > Listas precios comprobados; flag GUI restaurado a activo |
| SQLite UAT | Integridad `ok`; apertura controlada sin el aviso, con carpeta UAT explicita |
| Windows: lista manual por ticket | Cliente Distribuidor con override Mayorista: 70 / 300, total 1550; se conserva al cambiar a Ticket 3 y regresar |
| Windows: reapertura | Proceso UAT reiniciado; se restauran 3 tickets y el override Mayorista del Distribuidor, total 1550; sin aviso SQLite |
| Windows: cobro autorizado desde interfaz | Venta `129d4c2e-c000-48c1-b1f7-fe920d644571`, total 1550, PAID, efectivo 1550, cambio 0, override Mayorista persistido; Cable 5 a 70 y Router 4 a 300 |
| Windows: historial y tickets tras cobro | Una venta visible por 1550 en Ventas recientes; ticket cobrado retirado y quedan los dos tickets restantes |
| Windows: impresion tras cobro | Aviso Factura guardada sin imprimir / No hay impresora seleccionada; no se certifica impresion fisica |
| Windows: bloqueo durante recalculo | Demora temporal de 30 s mediante lock de tabla en PostgreSQL UAT; al pulsar Cobrar muestra Calculando precios y no abre el cobro; venta total sigue siendo una |
| Windows: cantidad durante recalculo | Cambio a Cable 2 mientras calculaba; resultado final 80 por unidad y total 160; no demuestra por si solo respuestas desordenadas |
| Windows: cotizacion desde interfaz | Cotizacion `e8c93481-35a3-4a9c-ac7e-59fe43ae1ab0`, cliente Distribuidor, override Mayorista, Cable 2 a 80, total 160; persistencia comprobada por SQL de solo lectura |
| Windows: regreso de administracion | Boton atras de Listas de precios vuelve a Facturacion y conserva los tickets |
| Windows: lista predeterminada del cliente | Agregar cliente > Editar muestra el campo Lista de precios con Distribuidor Descuento seleccionado; se cerro sin guardar cambios |

La prueba de creacion de listas por escritura nativa no quedo confirmada: la
herramienta de Windows no introdujo texto. La creacion esta comprobada por
widgets y HTTP. No confundir estas evidencias con confirmacion manual del usuario.

### Cierre de regresion asincrona del editor

Se agrego `test/features/price_lists/billing_wholesale_async_test.dart`. Monta
la pantalla real de Facturacion con el tema y fuentes de la app, repositorios
controlados y almacenamiento de prueba en memoria; ejecuta los callbacks de
los botones reales. No es una prueba nativa de Windows.

- PASS: cantidad 2 y luego 3; resuelve primero la respuesta nueva a 70 y luego
  la antigua a 90. El total permanece en 210; no vuelve a 180.
- PASS: quitar la linea durante el calculo; completar la respuesta anterior
  no vuelve a incorporar el producto.
- PASS: bajar la cantidad hasta cero con dos calculos pendientes; resolverlos
  posteriormente conserva el carrito vacio.
- PASS: sesion expirada al resolver precio. El ensayo usa repositorio,
  interceptor y controlador de autenticacion reales con HTTP 401 simulado y
  sin refresh token. Verifica sesion cerrada, llamada a clearTokens y carrito
  del tenant anterior vacio.
- El fallo inicial se aislo en el montaje del ensayo: la espera de un
  Completer creado con el reloj simulado dentro de runAsync no dejaba terminar
  la comprobacion. La instrumentacion mostro que el evento se habia procesado
  y la sesion ya estaba cerrada. Se precargan las futuras de telemetria fuera
  del reloj simulado y se deja terminar Dio en la cola real antes de comprobar
  el estado. No hubo cambios de autenticacion en el producto ni se debilitaron
  sus controles. El usuario autorizo expresamente continuar tras el limite de
  tres intentos de AGENTS.md §13.

Comandos del ultimo cierre:

```text
flutter test --no-pub test/features/price_lists/billing_wholesale_async_test.dart
4 PASS; exit 0, tras corregir el montaje asincrono. La ejecucion anterior
3 PASS / 1 FAIL queda superada por esta corrida completa, sin skips.

flutter test --no-pub test/features/price_lists/billing_wholesale_async_test.dart --name 'late older|removing a line|decreasing quantity'
3 PASS; exit 0. Esta ejecucion acotada no sustituye el fallo de la suite completa.

flutter analyze --no-pub
PASS: No issues found. Se retiro un import innecesario detectado en la primera ejecucion.
```

Los cuatro casos asincronos estan aprobados. La regresion general de cierre
tambien esta aprobada. La sesion UAT del usuario no se cerro ni se modifico
para este ensayo. Estado de Mayoreo online en UAT: GO. Este estado no implica
despliegue ni autorizacion de produccion, impresion fisica o soporte mayorista
offline completo.

Revalidacion de cierre:

- Flutter completo: `flutter test --no-pub`, exit 0; 1276 pruebas aprobadas y
  1 omitida. Los cuatro casos nuevos pasan dentro de esta ejecucion general.
  La omision existente corresponde a un ensayo condicionado a otra URL UAT;
  el contrato HTTP mayorista se comprobo contra la API local aislada.
- Analisis final: `flutter analyze --no-pub`, PASS, sin incidencias.
- Backend completo: `npm --workspace apps/api test`, exit 0; 75 suites y
  743 pruebas aprobadas, 1 suite / 8 pruebas omitidas por la configuracion
  existente.
- HTTP aislado: `scripts/isolated-uat/test-mayoreo.ps1`, PASS de nuevo.
  Venta sintetica `d2f232c2-8386-403a-9a29-7347f4e1eba5`, cotizacion
  `9d21febf-98ce-45e4-b9ee-292c829766b2`; se usaron empresas nuevas de prueba
  y no se altero la empresa GUI original.
- Apertura repetible: `scripts/isolated-uat/start-windows.ps1 -CheckOnly` y
  `scripts/isolated-uat/start-windows.ps1`, PASS. El lanzador restaura la variable
  de su proceso despues de abrir la app. Ventana UAT y API local activas.
- Diff: `git diff --check`, PASS. Se restauraron solo las tres imagenes de
  settings-notifications-visual-evidence regeneradas por los tests, que estaban
  limpias antes de ejecutarlos. No se alteraron los cambios previos de terceros.
La cotizacion sin cliente fue rechazada por `customerPhone should not be empty`;
con el cliente de prueba y su telefono se guardo correctamente. Es una observacion
del contrato de cotizaciones; no se cambio esa validacion.
El lock temporal termino con ROLLBACK y se verificaron cero locks exclusivos
restantes sobre reglas. No se modificaron datos con esa demora controlada.
La revision automatica rechazo la apertura final
con `blocked by policy`; una apertura posterior fue aceptada y permitio continuar
las pruebas con la carpeta UAT explicita.
Las ventas mayoristas offline completas y la integracion cruzada con Alanube
siguen fuera de este cierre UAT. Produccion permanece NO-GO sin su revision y
autorizacion propias.

### Correccion: cantidad digitada en el editor de linea

Reporte del usuario: al abrir una linea con doble clic y escribir 15 en
Cantidad, el precio mayorista seguia anterior hasta pulsar - y + en el carrito.
La ruta `_openLineEditor` guardaba cantidad y descuento, pero no invocaba el
recalculo que usan los botones del carrito.

Se conecta el recalculo existente al confirmar una cantidad distinta. Editar
solo el descuento, sin cambiar la cantidad, conserva el comportamiento manual.
No se cambia el contrato del backend ni se agregan reglas comerciales.

Prueba de regresion antes del arreglo: esperaba consulta con cantidad 15,
pero no se realizaba ninguna (`Expected: [15], Actual: []`). Despues del arreglo:

- `billing_wholesale_async_test.dart`: 6 PASS, incluidos cantidad digitada y
  descuento manual sin cambio de cantidad.
- `flutter test --no-pub test/modules/cotizaciones test/features/price_lists`:
  131 PASS.
- `flutter analyze --no-pub`: PASS, sin incidencias.
- `scripts/build/build_windows_uat_release.ps1 -SkipPubGet`: PASS; ejecutable
  corregido recompilado y abierto mediante el lanzador aislado.
- Windows nativo: editor de Router, lista Distribuidor. Cantidad digitada 3 y
  Enter: precio 250, total 750. Cantidad digitada 15 y Enter: precio 100, total
  1500, sin pulsar los botones de cantidad. La consulta SQL de solo lectura
  confirmo las reglas actuales del usuario: base 250, escalas 4 a 220, 5 a 200
  y 15 a 100. No se modificaron esas reglas. La ventana queda abierta con 15.
- `git diff --check`: PASS. Estado de esta correccion: GO en Windows UAT.
