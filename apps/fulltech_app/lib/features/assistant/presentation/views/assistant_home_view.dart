import 'package:flutter/material.dart';

import '../../../../core/support/support_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/assistant_whatsapp_service.dart';
import '../../domain/assistant_message_builder.dart';
import '../widgets/assistant_widgets.dart';

/// Pantalla de inicio del Asistente FullPOS.
///
/// Concentra las cuatro acciones reales del asistente (WhatsApp, avería,
/// sugerencia y cursos) más accesos directos a las guías. Todo el contenido es
/// local: no hay llamadas de red ni funciones de IA implementadas todavía.
class AssistantHomeView extends StatelessWidget {
  const AssistantHomeView({
    super.key,
    required this.onOpenFault,
    required this.onOpenSuggestion,
    required this.onOpenCourses,
  });

  final VoidCallback onOpenFault;
  final VoidCallback onOpenSuggestion;

  /// Abre la sección de cursos, opcionalmente con una búsqueda precargada.
  final void Function({String? query}) onOpenCourses;

  /// Temas más consultados (contenido verificado de la app).
  static const List<({String label, String query, IconData icon})> _topics = [
    (
      label: 'Cómo registrar una venta',
      query: 'venta',
      icon: Icons.point_of_sale_outlined,
    ),
    (
      label: 'Cómo abrir y cerrar caja',
      query: 'caja',
      icon: Icons.account_balance_wallet_outlined,
    ),
    (
      label: 'Cómo crear usuarios y permisos',
      query: 'usuario',
      icon: Icons.manage_accounts_outlined,
    ),
    (
      label: 'Cómo ajustar la impresora',
      query: 'impresora',
      icon: Icons.print_outlined,
    ),
  ];

  /// Recursos disponibles (guías reales de la app).
  static const List<({String label, String query, IconData icon})> _resources =
      [
        (
          label: 'Guía de ventas',
          query: 'venta',
          icon: Icons.receipt_long_outlined,
        ),
        (label: 'Guía de caja', query: 'caja', icon: Icons.payments_outlined),
        (
          label: 'Guía de inventario',
          query: 'inventario',
          icon: Icons.inventory_2_outlined,
        ),
        (
          label: 'Guía de compras',
          query: 'compra',
          icon: Icons.local_shipping_outlined,
        ),
      ];

  static String _greetingForHour(int hour) {
    if (hour < 12) return 'Buenos días';
    if (hour < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  @override
  Widget build(BuildContext context) {
    final greeting = _greetingForHour(DateTime.now().hour);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: [
        _Hero(
          greeting: greeting,
          onSearch: (query) {
            onOpenCourses(query: query);
          },
        ),
        const SizedBox(height: 16),
        const AssistantSectionLabel('Accesos rápidos'),
        _WhatsAppTile(),
        const SizedBox(height: 8),
        AssistantActionTile(
          icon: Icons.build_outlined,
          title: 'Reportar avería',
          subtitle: 'Cuéntanos qué falla y lo revisamos contigo.',
          onTap: onOpenFault,
        ),
        const SizedBox(height: 8),
        AssistantActionTile(
          icon: Icons.lightbulb_outline_rounded,
          title: 'Sugerir mejora',
          subtitle: 'Propón una idea para mejorar el sistema.',
          onTap: onOpenSuggestion,
        ),
        const SizedBox(height: 8),
        AssistantActionTile(
          icon: Icons.school_outlined,
          title: 'Cursos sobre el programa',
          subtitle: 'Consulta guías, recursos y cursos de uso de FullPOS.',
          onTap: () => onOpenCourses(),
          iconWidget: const AssistantIcon(size: 19, color: AppColors.secondary),
        ),
        const SizedBox(height: 18),
        const AssistantSectionLabel('Recursos'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final resource in _resources)
              AssistantPill(
                label: resource.label,
                icon: resource.icon,
                onTap: () => onOpenCourses(query: resource.query),
              ),
          ],
        ),
        const SizedBox(height: 18),
        const AssistantSectionLabel('Lo más consultado'),
        AssistantCard(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _topics.length; i++) ...[
                if (i > 0)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFEFF4F9),
                  ),
                _TopicRow(
                  label: _topics[i].label,
                  icon: _topics[i].icon,
                  onTap: () => onOpenCourses(query: _topics[i].query),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _SupportFooter(),
      ],
    );
  }
}

/// Bloque superior del asistente: icono, saludo y buscador.
class _Hero extends StatelessWidget {
  const _Hero({required this.greeting, required this.onSearch});

  final String greeting;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFDCEAFF), Color(0xFFEDF3FB), Colors.white],
          stops: [0.0, 0.48, 1.0],
        ),
        border: Border.all(color: const Color(0xFFDCE8FA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: const Color(0xFFD7E5FF)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14102A3A),
                      blurRadius: 10,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: const AssistantIcon(
                  size: 25,
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$greeting,',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 1),
                    const Text(
                      '¿Cómo podemos ayudarte hoy?',
                      maxLines: 2,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15.5,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AssistantSearchField(
            hintText: 'Buscar ayuda, cursos o funciones…',
            onSubmitted: onSearch,
          ),
        ],
      ),
    );
  }
}

/// Acción de WhatsApp con estado de resultado local (sin SnackBar).
class _WhatsAppTile extends StatefulWidget {
  const _WhatsAppTile();

  @override
  State<_WhatsAppTile> createState() => _WhatsAppTileState();
}

class _WhatsAppTileState extends State<_WhatsAppTile> {
  String? _notice;
  bool _isError = false;
  bool _busy = false;

  Future<void> _contactSupport() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _notice = null;
    });
    final result = await AssistantWhatsAppService.send(
      AssistantMessageBuilder.greeting(),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _isError = false;
      _notice = result.opened
          ? 'Abriendo WhatsApp con el mensaje listo para enviar.'
          : 'No se pudo abrir WhatsApp. El mensaje se copió al portapapeles.';
      _isError = !result.opened;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AssistantActionTile(
          icon: Icons.chat_outlined,
          title: 'Escribir vía WhatsApp',
          subtitle: 'Comunícate con soporte FullPOS.',
          onTap: _contactSupport,
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: AssistantInlineNotice(message: _notice!, isError: _isError),
          ),
      ],
    );
  }
}

/// Fila de tema consultado dentro de la tarjeta "Lo más consultado".
class _TopicRow extends StatelessWidget {
  const _TopicRow({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: onTap,
      hoverColor: const Color(0xFFF3F8FF),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 15, color: AppColors.textSecondary),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 14,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// Pie discreto con el teléfono de soporte oficial.
class _SupportFooter extends StatelessWidget {
  const _SupportFooter();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.verified_user_outlined,
          size: 13,
          color: AppColors.textMuted,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'Soporte oficial FullPOS · ${SupportConfig.phoneDisplay}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}
