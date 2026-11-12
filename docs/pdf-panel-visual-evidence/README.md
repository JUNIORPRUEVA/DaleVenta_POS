# Vista previa de PDF en panel lateral y botón «Compartir» (2026-11-11)

## Problema 1 — la vista previa salía como cuadro centrado

El PDF de cotización y el de factura se abrían en un `Dialog` centrado con ancho fijo
(58 % con `clamp(760, 1120)` en cotizaciones y 980 px en ventas), dejando el resto de la
pantalla sin usar y tapando el POS.

## Problema 2 — «Compartir» no compartía

**Causa raíz (HECHO, verificada en el código del complemento, no supuesta):**
todo el botón llamaba a `Printing.sharePdf(...)`. En Windows esa función **no abre ninguna hoja
de compartir**:

1. Escribe el PDF en `%TEMP%`.
2. Llama a `ShellExecuteEx` con el verbo `open`.

Es decir: al pulsar «Compartir» se abría el **visor de PDF del sistema** (Edge/Acrobat) encima de
FullPOS. Eso explica el «mucho movimiento» y el «algo raro». El complemento además informa
`canShare: true` en Windows, así que la interfaz creía que compartir estaba soportado.

Evidencia:

- `printing-5.14.3/windows/print_job.cpp` → `PrintJob::sharePdf(...)`:
  `GetTempPath` + `basic_ofstream` + `ShellExecuteEx(verb "open")`.
- `printing-5.14.3/windows/print_job.cpp` → `printingInfo()` devuelve `{"canShare", true}`.

## Cambios

| Cambio | Archivo |
| --- | --- |
| Panel lateral izquierdo, alto completo, mitad del ancho, borde derecho cuadrado | `lib/core/widgets/pdf_preview_panel.dart` |
| Compartir con la hoja del sistema (`share_plus`) | `lib/core/utils/pdf_share.dart` |
| Nombre legible del archivo («Cotización de Juan Pérez.pdf») | `lib/core/utils/pdf_document_file_name.dart` |
| Cotización (POS) abre al instante, acciones flotantes y descarga | `lib/modules/cotizaciones/cotizaciones_screen.dart` |
| Cotización (historial) igual | `lib/modules/cotizaciones/cotizaciones_historial_screen.dart` |
| Nombre del PDF de cotización | `lib/modules/cotizaciones/utils/cotizacion_pdf_service.dart` |
| Menú de PDF con variante circular para flotar | `lib/core/widgets/pdf_action_menu.dart` |
| Factura en Mis ventas / TPV / Crédito | `lib/modules/ventas/mis_ventas_screen.dart`, `sales_credit_screen.dart`, `tpv_sales_history_screen.dart` |
| Iconos profesionales del panel | `assets/image/pdf-compartir.png`, `assets/image/pdf-descargar.png` |

## Detalles de la segunda iteración

- **Apertura inmediata**: el PDF se construye en un `Future` que arranca *antes* de abrir el panel;
  la columna aparece al instante y muestra «Preparando el documento…» hasta que está listo.
- **Sin scroll**: la hoja se dibuja dentro de un `AspectRatio` A4 que se ajusta al espacio
  disponible (`pageLayoutMode: single`, sin barra ni cabeza de scroll).
- **Borde derecho cuadrado**: la superficie ya no lleva `BorderRadius`.
- **Cabecera estrecha** de 38 px, sin línea divisoria.
- **Dos iconos flotantes** (compartir y descargar) sobre la esquina superior derecha del documento.
- **Descarga directa** en `Descargas` con el nombre del cliente, y aviso en el propio panel.
- Un toque en una zona vacía del panel ya no lo cierra (el `ModalBarrier` no recibe el toque).

## Evidencia visual (Windows UAT)

| Captura | Qué muestra |
| --- | --- |
| `01-pos-antes.png` | POS de partida |
| `02-panel-izquierdo-cotizacion.png` | Primera versión del panel (con pie y radio) |
| `03-compartir-hoja-windows.png` | Tras pulsar «Compartir»: hoja de compartir de Windows, **no** el visor de PDF |
| `04-panel-cuadrado-sin-scroll.png` | Panel definitivo: borde derecho cuadrado, cabecera estrecha sin línea, dos iconos flotantes y la hoja A4 completa sin scroll |
| `05-descarga-con-nombre-cliente.png` | Aviso «Cotización guardada en Descargas como «Cotización COT-17944521.pdf»» con el panel abierto |

Archivo real generado y comprobado en disco:
`C:\Users\pc\Downloads\Cotización COT-17944521.pdf` (2.105.872 bytes, 22:55).

## Observación del entorno (no es un fallo de FullPOS)

En este equipo el panel de Windows muestra «Try that again · We couldn't show you all the ways you
could share». Es el mensaje del propio Windows cuando no encuentra destinos de compartir para una
aplicación de escritorio sin empaquetar; FullPOS ya no abre ninguna ventana externa.
