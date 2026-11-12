import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/company/company_settings_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/assistant_models.dart';
import 'views/assistant_fault_form_view.dart';
import 'views/assistant_help_view.dart';
import 'views/assistant_home_view.dart';
import 'views/assistant_suggestion_form_view.dart';
import 'widgets/assistant_widgets.dart';

/// Secciones internas del asistente (navegación local, sin rutas nuevas).
enum AssistantSection { home, fault, suggestion, courses }

/// Panel lateral derecho del Asistente FullPOS.
///
/// Es una operación **puramente visual**: `showGeneralDialog` no cambia la ruta
/// activa, no reconstruye el `State` de la pantalla de ventas ni toca carrito,
/// caja, turno, licencia o sesión. Tampoco hace llamadas de red al abrirse.
///
/// El ancho es amplio a propósito para cubrir visualmente la columna de detalle
/// de ventas del POS y que el asistente se perciba como un módulo del sistema.
class AssistantPanel extends ConsumerStatefulWidget {
  const AssistantPanel({super.key});

  /// Abre el panel pegado al borde derecho con ancho responsive.
  ///
  /// - < 700 px lógicos: ancho completo (móvil, tablet estrecha y portátiles con
  ///   escalado alto de Windows) para no dejar franjas laterales.
  /// - Escritorio: 480–620 px (o el 42 % del ancho si es mayor).
  static Future<void> open(BuildContext context) {
    return showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: 'Asistente FullPOS',
      barrierColor: Colors.black.withValues(alpha: 0.22),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final size = MediaQuery.sizeOf(dialogContext);
        final width = size.width < 700
            ? size.width
            : (size.width * 0.42).clamp(480.0, 620.0);
        return Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: width,
            height: double.infinity,
            child: const AssistantPanel(),
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
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  @override
  ConsumerState<AssistantPanel> createState() => _AssistantPanelState();
}

class _AssistantPanelState extends ConsumerState<AssistantPanel> {
  AssistantSection _section = AssistantSection.home;
  String? _appVersion;
  String _coursesQuery = '';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      final version = info.version.trim();
      final build = info.buildNumber.trim();
      setState(() {
        _appVersion = version.isEmpty
            ? null
            : (build.isEmpty ? version : '$version+$build');
      });
    } catch (_) {
      // Sin versión disponible el mensaje simplemente omite ese campo.
    }
  }

  String get _title {
    switch (_section) {
      case AssistantSection.home:
        return 'Asistente FullPOS';
      case AssistantSection.fault:
        return 'Reportar avería';
      case AssistantSection.suggestion:
        return 'Sugerir mejora';
      case AssistantSection.courses:
        return 'Cursos sobre el programa';
    }
  }

  String get _subtitle {
    switch (_section) {
      case AssistantSection.home:
        return 'Soporte y ayuda inteligente';
      case AssistantSection.fault:
        return 'Enviar un problema a soporte';
      case AssistantSection.suggestion:
        return 'Enviar una idea a soporte';
      case AssistantSection.courses:
        return 'Guías, recursos y formación';
    }
  }

  void _goTo(AssistantSection section, {String? query}) {
    setState(() {
      _section = section;
      if (query != null) _coursesQuery = query;
    });
  }

  @override
  Widget build(BuildContext context) {
    final companyName = ref
        .watch(companySettingsProvider)
        .valueOrNull
        ?.companyName
        .trim();
    final contextData = AssistantMessageContext(
      companyName: (companyName ?? '').trim().isEmpty ? null : companyName,
      platformLabel: assistantPlatformLabel(),
      appVersion: _appVersion,
    );

    return Material(
      key: const Key('assistant-panel-root'),
      color: const Color(0xFFF7FAFF),
      child: Container(
        height: double.infinity,
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
              color: Color(0x1F0F172A),
              blurRadius: 20,
              offset: Offset(-6, 0),
            ),
          ],
        ),
        child: SafeArea(
          left: false,
          child: Column(
            children: [
              _PanelHeader(
                title: _title,
                subtitle: _subtitle,
                showBack: _section != AssistantSection.home,
                onBack: () => _goTo(AssistantSection.home),
                onClose: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: switch (_section) {
                  AssistantSection.home => AssistantHomeView(
                    onOpenFault: () => _goTo(AssistantSection.fault),
                    onOpenSuggestion: () => _goTo(AssistantSection.suggestion),
                    onOpenCourses: ({String? query}) =>
                        _goTo(AssistantSection.courses, query: query ?? ''),
                  ),
                  AssistantSection.fault => AssistantFaultFormView(
                    contextData: contextData,
                  ),
                  AssistantSection.suggestion => AssistantSuggestionFormView(
                    contextData: contextData,
                  ),
                  AssistantSection.courses => AssistantCoursesView(
                    initialQuery: _coursesQuery,
                  ),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.title,
    required this.subtitle,
    required this.showBack,
    required this.onBack,
    required this.onClose,
  });

  final String title;
  final String subtitle;
  final bool showBack;
  final VoidCallback onBack;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 6, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE6EFFF), Color(0xFFF4F8FF), Colors.white],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (showBack)
            IconButton(
              tooltip: 'Volver',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              color: AppColors.textSecondary,
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
            )
          else
            Container(
              margin: const EdgeInsets.only(left: 2),
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: const Color(0xFFD7E5FF)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14102A3A),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: const AssistantIcon(size: 20, color: AppColors.secondary),
            ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Cerrar',
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded, size: 19),
            color: AppColors.textSecondary,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
