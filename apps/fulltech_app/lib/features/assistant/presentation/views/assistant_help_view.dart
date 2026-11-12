import 'package:flutter/material.dart';

import '../../../../core/support/support_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/assistant_whatsapp_service.dart';
import '../../domain/assistant_message_builder.dart';
import '../widgets/assistant_widgets.dart';

/// Contenido de una guía del asistente.
///
/// Solo recoge funciones que existen realmente en la app (módulos de ventas,
/// cotizaciones, caja, usuarios, inventario, compras e impresora). No incluye
/// capturas ni rutas inventadas.
class _CourseTopic {
  const _CourseTopic({
    required this.group,
    required this.title,
    required this.icon,
    required this.lines,
  });

  final String group;
  final String title;
  final IconData icon;
  final List<String> lines;

  bool matches(String query) {
    if (query.isEmpty) return true;
    if (title.toLowerCase().contains(query)) return true;
    return lines.any((line) => line.toLowerCase().contains(query));
  }
}

/// Sección «Cursos sobre el programa».
///
/// Es la evolución de la antigua ayuda: buscador funcional sobre contenido local
/// verificado, guías agrupadas por área y salida directa a soporte si no hay
/// resultados. Sin backend, sin IA y sin datos sensibles.
class AssistantCoursesView extends StatefulWidget {
  const AssistantCoursesView({super.key, this.initialQuery = ''});

  /// Búsqueda con la que se abre la sección (desde el buscador del inicio).
  final String initialQuery;

  @override
  State<AssistantCoursesView> createState() => _AssistantCoursesViewState();
}

class _AssistantCoursesViewState extends State<AssistantCoursesView> {
  static const List<_CourseTopic> _topics = [
    _CourseTopic(
      group: 'Ventas y facturación',
      title: 'Registrar una venta',
      icon: Icons.point_of_sale_outlined,
      lines: [
        'En Ventas eliges productos del catálogo o escribes una descripción libre.',
        'Selecciona el cliente (o consumidor final) y el comprobante a emitir.',
        'Al guardar, el ticket se imprime con el formato configurado y el inventario se actualiza.',
      ],
    ),
    _CourseTopic(
      group: 'Ventas y facturación',
      title: 'Cotizaciones',
      icon: Icons.description_outlined,
      lines: [
        'Las cotizaciones se crean y editan en el módulo Cotizaciones.',
        'Una cotización no mueve caja ni inventario hasta que se convierte en venta.',
        'Desde el detalle puedes reimprimir el ticket de una venta reciente.',
      ],
    ),
    _CourseTopic(
      group: 'Operación diaria',
      title: 'Caja y turnos',
      icon: Icons.account_balance_wallet_outlined,
      lines: [
        'Abre el turno al iniciar el día e ingresa el fondo de caja.',
        'Registra entradas y salidas de efectivo mientras el turno está abierto.',
        'Al cerrar, revisa el efectivo contado: el cierre queda guardado con sus totales.',
      ],
    ),
    _CourseTopic(
      group: 'Operación diaria',
      title: 'Usuarios y permisos',
      icon: Icons.manage_accounts_outlined,
      lines: [
        'Los usuarios se crean desde Configuración → Usuarios.',
        'Cada usuario tiene un rol y permisos: solo ve las secciones autorizadas.',
        'Los cambios de permisos se aplican cuando el usuario inicia sesión de nuevo.',
      ],
    ),
    _CourseTopic(
      group: 'Catálogo y compras',
      title: 'Inventario y productos',
      icon: Icons.inventory_2_outlined,
      lines: [
        'Los productos se crean desde el módulo Inventario con precio e impuesto.',
        'El stock se controla por almacén y se ajusta desde Inventario.',
        'Las compras a proveedores se registran desde el módulo Compras.',
      ],
    ),
    _CourseTopic(
      group: 'Equipos',
      title: 'Impresora y tickets',
      icon: Icons.print_outlined,
      lines: [
        'En Configuración → Impresora eliges la impresora, el ancho (58 mm u 80 mm) y el formato.',
        'Puedes imprimir un ticket de prueba y probar la apertura de caja.',
        'Si no hay impresora térmica disponible, el sistema usa el diálogo de impresión del sistema.',
      ],
    ),
  ];

  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );
  late String _query = widget.initialQuery.trim().toLowerCase();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == _query) return;
    setState(() => _query = normalized);
  }

  List<_CourseTopic> get _filtered =>
      _topics.where((topic) => topic.matches(_query)).toList(growable: false);

  /// Agrupa los resultados conservando el orden de declaración.
  Map<String, List<_CourseTopic>> _grouped(List<_CourseTopic> topics) {
    final grouped = <String, List<_CourseTopic>>{};
    for (final topic in topics) {
      grouped.putIfAbsent(topic.group, () => <_CourseTopic>[]).add(topic);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final grouped = _grouped(filtered);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      children: [
        TextField(
          controller: _controller,
          textInputAction: TextInputAction.search,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
          decoration:
              assistantFieldDecoration(
                hint: 'Buscar en guías y cursos…',
              ).copyWith(
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 17,
                  color: AppColors.textMuted,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 34,
                  minHeight: 34,
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar búsqueda',
                        onPressed: () {
                          _controller.clear();
                          _onQueryChanged('');
                        },
                        icon: const Icon(Icons.close_rounded, size: 15),
                        color: AppColors.textMuted,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 28,
                          height: 28,
                        ),
                      ),
              ),
          onChanged: _onQueryChanged,
          onSubmitted: _onQueryChanged,
        ),
        const SizedBox(height: 12),
        if (_query.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              filtered.isEmpty
                  ? 'Sin resultados para «${_controller.text.trim()}»'
                  : '${filtered.length} tema${filtered.length == 1 ? '' : 's'} para «${_controller.text.trim()}»',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        if (filtered.isEmpty)
          _EmptyResultCard(
            query: _controller.text.trim(),
            onClear: () {
              _controller.clear();
              _onQueryChanged('');
            },
          )
        else
          for (final entry in grouped.entries) ...[
            AssistantSectionLabel(entry.key),
            for (final topic in entry.value) ...[
              _CourseTopicTile(topic: topic),
              const SizedBox(height: 8),
            ],
            if (entry.key != grouped.keys.last) const SizedBox(height: 6),
          ],
        const SizedBox(height: 6),
        _CoursesFooter(),
      ],
    );
  }
}

/// Guía expandible dentro de la lista de cursos.
class _CourseTopicTile extends StatefulWidget {
  const _CourseTopicTile({required this.topic});

  final _CourseTopic topic;

  @override
  State<_CourseTopicTile> createState() => _CourseTopicTileState();
}

class _CourseTopicTileState extends State<_CourseTopicTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            mouseCursor: SystemMouseCursors.click,
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(8),
            hoverColor: const Color(0xFFF3F8FF),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(11, 10, 9, 10),
              child: Row(
                children: [
                  Icon(widget.topic.icon, size: 16, color: AppColors.secondary),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      widget.topic.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: const Icon(
                      Icons.expand_more_rounded,
                      size: 17,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 0, 11, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: Color(0xFFEFF4F9),
                  ),
                  const SizedBox(height: 9),
                  for (final line in widget.topic.lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Icon(
                              Icons.circle,
                              size: 4,
                              color: AppColors.secondary,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              line,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11.5,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Resultado vacío del buscador con salida directa a soporte.
class _EmptyResultCard extends StatelessWidget {
  const _EmptyResultCard({required this.query, required this.onClear});

  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return AssistantCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 16,
                color: AppColors.textSecondary,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No encontramos esa guía',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            query.isEmpty
                ? 'Prueba con otra palabra o escríbenos por WhatsApp.'
                : 'Prueba con otra palabra distinta de «$query» o escríbenos por WhatsApp.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              height: 1.35,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: onClear,
                style: assistantSecondaryButtonStyle(),
                child: const Text('Ver todos los temas'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bloque final: contacto directo si no hay respuesta en las guías.
class _CoursesFooter extends StatefulWidget {
  @override
  State<_CoursesFooter> createState() => _CoursesFooterState();
}

class _CoursesFooterState extends State<_CoursesFooter> {
  String? _notice;
  bool _isError = false;

  Future<void> _contactSupport() async {
    final result = await AssistantWhatsAppService.send(
      AssistantMessageBuilder.greeting(),
    );
    if (!mounted) return;
    setState(() {
      _isError = !result.opened;
      _notice = result.opened
          ? 'Abriendo WhatsApp con el mensaje listo para enviar.'
          : 'No se pudo abrir WhatsApp. El mensaje se copió al portapapeles.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AssistantCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '¿No encuentras la respuesta?',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Escríbenos a ${SupportConfig.phoneDisplay} y te ayudamos con tu caso.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11.5,
              height: 1.35,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _contactSupport,
              style: assistantPrimaryButtonStyle(),
              child: const Text('Contactar soporte'),
            ),
          ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 9),
              child: AssistantInlineNotice(
                message: _notice!,
                isError: _isError,
              ),
            ),
        ],
      ),
    );
  }
}
