# Formularios POS cuadrados — validación local

Trabajo sobre `C:\t\fp-credit-20261126`, sin despliegue ni modificación de
producción. Se conserva la plantilla térmica aprobada.

## Cambios

- `SquarePosDialog` limita el estilo a editar/eliminar ticket, descuentos,
  cobro y movimientos IN/OUT. No cambia globalmente otros formularios.
- Tarjetas, campos, segmentos RD$/%, métodos de pago y acciones cuadrados;
  controles44px con densidad estándar, colores y tipografía existentes.
- Editar ticket conserva ancho completo del campo. Eliminar utiliza el PNG
  de papelera existente, sin alterar confirmación, borrado ni permisos.
- Cobro no permite cambiar el tipo de factura. Conserva, como campo final,
  el modo seleccionado en el detalle; continúan las validaciones de E31,
  receptor, numeración y resultado del cobro. Se oculta también la fila de
  comprobante del resumen móvil. El selector del detalle permanece visible.
- Entrada/salida conserva sus importes, validadores, motivos y callbacks.

## Comprobaciones

`pos-square-final-tests.log`:62 pruebas correctas de facturación, selector
fiscal, eliminación de borradores, controles móviles, footer y caja.
Tras normalizar la densidad y acotar los segmentos:20 pruebas afectadas
correctas en `pos-square-final-sizing-tests.log` (solapadas, no se suman).
Las pruebas se ejecutaron con API loopback14627 y FULLPOS_UAT_BUILD.

Casos nuevos: ingreso/salida en390/1280px, controles44px, rechazo de monto0
y devolución de monto/motivo válidos desde el formulario sin ejecutar API
financiera. El descuento general verifica tarjeta/campo/botón cuadrado,
altura de segmentos y cancelación; el cobro verifica ausencia del selector
interno y preservación de la selección del detalle al cancelar.

`pos-square-verified-analyze.log`: análisis de ocho archivos sin incidencias.
Se revisaron capturas reales de widgets Android/iOS y escritorio en
`.uat/pos-square-ui`; las variantes móviles son pruebas de widgets, no una
afirmación de ejecución física en iPhone/Android.

Los primeros intentos detectaron expectativas antiguas del selector en cobro,
un dato equivocado del nuevo test y un arnés sin shell para el footer. Se
corrigieron las pruebas conforme al flujo real. En la revisión visual se
detectó además que ButtonStyle.merge conserva valores del primer estilo y
que la densidad compacta reducía los bordes de los campos: se corrigió el
estilo local y se añadió una comprobación de tamaño/forma. Los primeros logs
se conservan; no se redujeron validaciones de negocio para superar pruebas.

App Windows recompilada en frío contra la API local, con el mismo almacén
UAT, en `pos-square-final-windows-app.log`. La revisión nativa se limita a
abrir/cancelar formularios; no se confirma ninguna venta, movimiento o borrado.

Validación nativa final: se observaron Editar ticket y Eliminar ticket con
contornos cuadrados, entrada de nombre a todo el ancho, acciones44px e icono
de papelera cargado correctamente. Se cancelaron sin guardar ni eliminar;
el borrador conserva Ticket1, un artículo, total2500 y stock visible40.
Capturas `native-rename.jpg` y `native-delete.jpg` en `.uat/pos-square-ui`.
La normalización final de densidad y el tamaño explícito de los segmentos
pasaron las20 pruebas afectadas; el análisis actualizado de ocho archivos
está limpio en `pos-square-final-analysis.log`. Se deja la app local abierta.

## Esquinas suavizadas a petición del usuario

Se centraliza radio1px en `SquarePosDialog.cornerRadius/corners` y se aplica
a los mismos formularios y controles, incluido el menú del ticket. No se
modifican otros bordes del POS. Alturas44px y lógica conservadas.
20 pruebas afectadas correctas en `pos-radius1-tests.log`; análisis de seis
archivos sin incidencias en `pos-radius1-analyze.log`. La app se recompila
en frío contra14627 en `pos-radius1-windows-app.log`. El formulario de caja
estaba vacío y se canceló antes del reinicio; se conserva el borrador.
