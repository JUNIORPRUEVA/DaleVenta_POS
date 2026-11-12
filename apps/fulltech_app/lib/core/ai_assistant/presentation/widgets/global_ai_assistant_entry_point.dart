import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart' hide GestureDetector;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/auth_provider.dart';
import '../../../routing/app_router.dart';
import '../../../widgets/app_navigation.dart';
import '../../application/ai_assistant_controller.dart';
import '../../domain/models/ai_chat_context.dart';
import '../ai_chat_context_resolver.dart';
import 'ai_assistant_dock_button.dart';
import 'ai_assistant_sheet.dart';

class GlobalAiAssistantEntryPoint extends ConsumerWidget {
  const GlobalAiAssistantEntryPoint({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    if (!auth.isAuthenticated) return child;

    final hiddenByScreen = ref.watch(hideGlobalAiAssistantEntryPointProvider);
    if (hiddenByScreen) return child;

    final router = ref.watch(routerProvider);
    final location = _safeLocation(context, router);
    if (_shouldHideEntryPoint(location)) return child;

    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    return Stack(
      children: [
        child,
        if (!isDesktop)
          Positioned(
            right: 14,
            // En layouts compactos el carrito ocupa el pie de la pantalla: el
            // botón del asistente se ancla al centro vertical del borde derecho
            // para no superponerse a Cobrar, Cotizar ni a las líneas del
            // carrito. Posición derivada del viewport, sin coordenadas fijas.
            top: (MediaQuery.sizeOf(context).height * 0.5 - 32)
                .clamp(70.0, double.infinity)
                .toDouble(),
            child: Builder(
              builder: (innerContext) {
                final assistantContext = _buildAssistantContext(innerContext);

                final viewInsets = MediaQuery.viewInsetsOf(innerContext);
                final viewPadding = MediaQuery.viewPaddingOf(innerContext);
                final extraBottom = viewInsets.bottom > 0
                    ? viewInsets.bottom
                    : viewPadding.bottom;

                return AnimatedPadding(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.only(bottom: extraBottom),
                  child: AiAssistantDockButton(
                    compact: true,
                    onPressed: () =>
                        _openAssistant(innerContext, ref, assistantContext),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  bool _shouldHideEntryPoint(String location) {
    final candidates = _routeCandidates(location);
    return candidates.isEmpty;
  }

  Iterable<String> _routeCandidates(String location) sync* {
    final normalized = location.trim().toLowerCase();
    if (normalized.isNotEmpty) yield normalized;

    final uri = Uri.tryParse(location.trim());
    if (uri == null) return;

    final path = uri.path.trim().toLowerCase();
    if (path.isNotEmpty) yield path;

    final fragment = uri.fragment.trim().toLowerCase();
    if (fragment.isNotEmpty) {
      yield fragment.startsWith('/') ? fragment : '/$fragment';
    }

    final fragmentUri = Uri.tryParse(fragment);
    final fragmentPath = fragmentUri?.path.trim().toLowerCase() ?? '';
    if (fragmentPath.isNotEmpty) yield fragmentPath;
  }

  AiChatContext _buildAssistantContext(BuildContext context) {
    final location = safeCurrentLocation(context);
    return buildAiChatContextFromLocation(location);
  }

  String _safeLocation(BuildContext context, GoRouter router) {
    final fromRouter = router.routeInformationProvider.value.uri.toString();
    if (fromRouter.trim().isNotEmpty) return fromRouter;
    return safeCurrentLocation(context);
  }

  void _openAssistant(
    BuildContext context,
    WidgetRef ref,
    AiChatContext assistantContext,
  ) {
    final controller = ref.read(aiAssistantControllerProvider.notifier);
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    controller.setContext(assistantContext);

    if (isDesktop) {
      showDesktopPanel(context, ref);
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const GlobalAiChatSheet(),
    );
  }

  /// Abre el panel lateral del asistente en escritorio.
  ///
  /// **Se monta como ruta, no como hijo del `Stack` de este entry point.** Este widget
  /// envuelve al `MaterialApp` y queda **por encima del `Navigator`**, así que cualquier
  /// cosa que pinte aquí no hereda ningún `Overlay`. Con el panel dentro del `Stack`, el
  /// campo de texto fallaba con «No Overlay widget found»: no se podía mover el cursor,
  /// seleccionar texto ni mostrar tooltips. Al abrirlo con `showGeneralDialog` la ruta
  /// vive dentro del `Navigator` y hereda su `Overlay`, igual que el panel de detalle de
  /// ventas (`registrar_venta_screen.dart`).
  static Future<void> showDesktopPanel(BuildContext context, WidgetRef ref) {
    ref.read(desktopAiAssistantPanelOpenProvider.notifier).state = true;
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar FullPOS IA',
      // El velo lo pinta el propio panel para poder aplicar desenfoque real.
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, _, __) {
        // Mismo ancho que la columna de detalle de ventas (29 % acotado 420–560).
        final width = MediaQuery.sizeOf(dialogContext).width;
        final panelWidth = (width * 0.29).clamp(420.0, 560.0).toDouble();
        return Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                child: ModalBarrier(
                  color: Colors.black.withValues(alpha: 0.12),
                  dismissible: true,
                  semanticsLabel: 'Cerrar FullPOS IA',
                  onDismiss: () => Navigator.of(dialogContext).maybePop(),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: panelWidth,
                height: double.infinity,
                child: Material(
                  type: MaterialType.transparency,
                  child: GlobalAiChatSheet(
                    panelWidth: panelWidth,
                    onClose: () => Navigator.of(dialogContext).maybePop(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    ).whenComplete(() {
      ref.read(desktopAiAssistantPanelOpenProvider.notifier).state = false;
    });
  }
}
