import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

/// Panel lateral de vista previa de PDF (cotizaciones y facturas).
///
/// El documento se muestra en una columna pegada al borde izquierdo, con el
/// alto completo de la ventana y la mitad del ancho en escritorio, ajustado a
/// la pantalla y **sin scroll**.
///
/// Es una operación **puramente visual**: `showGeneralDialog` no cambia la ruta
/// activa ni reconstruye el estado de la pantalla que lo abre.

/// Proporción del ancho de la ventana que ocupa el panel en escritorio.
const double kPdfPreviewPanelWidthRatio = 0.5;

/// Ancho mínimo legible del panel en escritorio.
///
/// Por debajo de este ancho el documento queda demasiado estrecho para leerlo,
/// así que se respeta el mínimo aunque supere ligeramente la mitad del ancho.
const double kPdfPreviewPanelMinWidth = 520;

/// Por debajo de este ancho de ventana el panel ocupa todo el ancho disponible
/// (móvil y tablet estrecha), porque media pantalla no es usable.
const double kPdfPreviewPanelFullWidthBelow = 720;

/// Alto de la cabecera del panel, deliberadamente estrecha.
const double kPdfPreviewPanelHeaderHeight = 38;

/// Proporción de una hoja A4 vertical (210 × 297 mm).
const double kA4PageAspectRatio = 210 / 297;

/// Iconos profesionales de las acciones del panel.
abstract final class PdfPanelIcons {
  static const String share = 'assets/image/pdf-compartir.png';
  static const String download = 'assets/image/pdf-descargar.png';
}

/// Ancho del panel para un tamaño de ventana dado.
double pdfPreviewPanelWidthFor(Size size) {
  if (size.width < kPdfPreviewPanelFullWidthBelow) return size.width;
  return (size.width * kPdfPreviewPanelWidthRatio).clamp(
    kPdfPreviewPanelMinWidth,
    size.width,
  );
}

/// Abre la vista previa en el panel lateral izquierdo.
///
/// El contenido ([builder]) se construye dentro de la ruta del panel, así que
/// `Navigator.pop(context)` desde ahí cierra la vista previa.
Future<T?> showPdfPreviewPanel<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  String barrierLabel = 'Vista previa del PDF',
}) {
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    barrierColor: const Color(0x990B1720),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final size = MediaQuery.sizeOf(dialogContext);
      return Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: pdfPreviewPanelWidthFor(size),
          height: double.infinity,
          child: PdfPreviewPanelSurface(child: Builder(builder: builder)),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

/// Superficie blanca del panel: pegada al borde izquierdo, a todo el alto y con
/// el borde derecho **cuadrado** (sin radio).
class PdfPreviewPanelSurface extends StatelessWidget {
  const PdfPreviewPanelSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // `GestureDetector` opaco: un toque en una zona vacía del panel (márgenes
    // de la hoja, huecos de la cabecera) no debe atravesar hasta la barrera
    // modal y cerrar la vista previa sin querer.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Material(
        color: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 16,
        shadowColor: const Color(0x33000000),
        clipBehavior: Clip.hardEdge,
        child: child,
      ),
    );
  }
}

/// Cabecera estrecha del panel: título a la izquierda y cierre a la derecha.
///
/// No lleva línea divisoria: el documento y las acciones flotan debajo.
class PdfPreviewPanelHeader extends StatelessWidget {
  const PdfPreviewPanelHeader({
    super.key,
    required this.title,
    this.onClose,
    this.leadingIcon = Icons.picture_as_pdf_outlined,
  });

  final String title;
  final VoidCallback? onClose;
  final IconData leadingIcon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kPdfPreviewPanelHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 2, 0),
        child: Row(
          children: [
            Icon(leadingIcon, size: 16, color: const Color(0xFF4B5563)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                  color: Color(0xFF1F2937),
                ),
              ),
            ),
            IconButton(
              onPressed: onClose,
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: const Color(0xFF4B5563),
                semanticLabel: 'Cerrar la vista previa',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botón circular flotante del panel, con icono de imagen.
class PdfPanelActionButton extends StatelessWidget {
  const PdfPanelActionButton({
    super.key,
    required this.iconAsset,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String iconAsset;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: Material(
        color: Colors.white,
        elevation: 3,
        shadowColor: const Color(0x33000000),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? onPressed : null,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Opacity(
                      opacity: enabled ? 1 : 0.45,
                      child: Image.asset(
                        iconAsset,
                        width: 18,
                        height: 18,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Área del documento: la hoja se ajusta al espacio disponible, **sin scroll**,
/// y las acciones flotan encima en la esquina superior derecha.
class PdfPreviewStage extends StatefulWidget {
  const PdfPreviewStage({
    super.key,
    required this.bytes,
    this.aspectRatio = kA4PageAspectRatio,
    this.actions = const <Widget>[],
    this.errorMessage,
  });

  /// Documento listo para mostrar; `null` mientras se prepara.
  final Uint8List? bytes;
  final double aspectRatio;
  final List<Widget> actions;

  /// Error de preparación del documento, si lo hubo.
  final String? errorMessage;

  @override
  State<PdfPreviewStage> createState() => _PdfPreviewStageState();
}

class _PdfPreviewStageState extends State<PdfPreviewStage> {
  String? _renderError;

  @override
  void didUpdateWidget(covariant PdfPreviewStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) _renderError = null;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE8EEF5),
      child: Stack(
        children: [
          Positioned.fill(child: _body()),
          if (widget.actions.isNotEmpty)
            Positioned(
              top: 10,
              right: 10,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < widget.actions.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    widget.actions[i],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    final documentBytes = widget.bytes;
    final errorMessage = widget.errorMessage ?? _renderError;
    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            errorMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFFB42318),
            ),
          ),
        ),
      );
    }
    if (documentBytes == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            SizedBox(height: 12),
            Text(
              'Preparando el documento…',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF4B5563),
              ),
            ),
          ],
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: AspectRatio(
          aspectRatio: widget.aspectRatio,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: SfPdfViewer.memory(
              documentBytes,
              canShowScrollHead: false,
              canShowScrollStatus: false,
              canShowPaginationDialog: false,
              enableTextSelection: false,
              pageLayoutMode: PdfPageLayoutMode.single,
              onDocumentLoadFailed: (details) {
                debugPrintStack(label: 'PDF_PREVIEW_LOAD_FAILED: ${details.error}');
                if (mounted) {
                  setState(() => _renderError =
                      'No se pudo mostrar el PDF. Puedes guardarlo en descargas.');
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}
