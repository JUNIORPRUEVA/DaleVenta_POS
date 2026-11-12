import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../assistant_panel.dart';

/// Icono oficial del Asistente FullPOS.
///
/// Asset local (PNG 512×512, trazo negro sobre fondo transparente) teñido con
/// [BlendMode.srcIn] para adaptarse al color del contexto. Si el asset faltara
/// en tiempo de ejecución, cae a un icono Material equivalente.
const String assistantIconAsset = 'assets/image/asistente-soporte.png';

class AssistantIcon extends StatelessWidget {
  const AssistantIcon({super.key, this.size = 24, this.color = Colors.white});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assistantIconAsset,
      width: size,
      height: size,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Asistente FullPOS',
      errorBuilder: (_, __, ___) =>
          Icon(Icons.headset_mic_rounded, size: size, color: color),
    );
  }
}

/// Botón flotante del Asistente FullPOS.
///
/// Única entrada del asistente en escritorio (sustituye al acceso anterior, sin
/// duplicar). Se posiciona en la esquina inferior izquierda del área útil del POS
/// desde `cotizaciones_screen.dart`.
///
/// Animación puntual: pulso de escala al aparecer y al pasar el cursor. Sin
/// bucle, sin cambiar la posición y omitida con «movimiento reducido».
class AssistantFab extends StatefulWidget {
  const AssistantFab({super.key, this.size = 52});

  /// Diámetro visual del botón.
  final double size;

  @override
  State<AssistantFab> createState() => _AssistantFabState();
}

class _AssistantFabState extends State<AssistantFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1,
        end: 1.05,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 45,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.05,
        end: 1,
      ).chain(CurveTween(curve: Curves.easeInOutCubic)),
      weight: 55,
    ),
  ]).animate(_pulse);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playOnce());
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _playOnce() {
    if (!mounted) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    if (_pulse.isAnimating) return;
    _pulse.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _playOnce(),
      child: Semantics(
        button: true,
        label: 'Asistente FullPOS',
        child: Tooltip(
          message: 'Asistente FullPOS',
          child: ScaleTransition(
            scale: _scale,
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Material(
                color: AppColors.secondary,
                shape: const CircleBorder(),
                elevation: 3,
                shadowColor: const Color(0x33102A3A),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => AssistantPanel.open(context),
                  hoverColor: Colors.white.withValues(alpha: 0.12),
                  focusColor: Colors.white.withValues(alpha: 0.16),
                  splashColor: Colors.white.withValues(alpha: 0.10),
                  child: Center(
                    child: AssistantIcon(
                      size: widget.size * 0.52,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fila compacta del menú principal del asistente.
class AssistantActionTile extends StatelessWidget {
  const AssistantActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon = Icons.chevron_right_rounded,
    this.accent = AppColors.secondary,
    this.iconWidget,
  });

  /// Se usa cuando no se pasa [iconWidget].
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color accent;

  /// Permite sustituir el glifo por un asset (icono oficial del asistente).
  final Widget? iconWidget;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: const Color(0xFFF3F8FF),
        focusColor: AppColors.secondarySoft,
        child: Container(
          padding: const EdgeInsets.fromLTRB(11, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.secondarySoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFDCE8FF)),
                ),
                child: iconWidget ?? Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: 11),
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
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Etiqueta de sección del panel (fina, sin ruido visual).
class AssistantSectionLabel extends StatelessWidget {
  const AssistantSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Campo de búsqueda del asistente.
///
/// Es funcional: filtra el contenido local disponible (guías y recursos). Queda
/// preparado para incluir respuestas asistidas en una fase posterior sin cambiar
/// la interfaz.
class AssistantSearchField extends StatefulWidget {
  const AssistantSearchField({
    super.key,
    required this.hintText,
    this.initialQuery = '',
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  });

  final String hintText;
  final String initialQuery;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;

  @override
  State<AssistantSearchField> createState() => _AssistantSearchFieldState();
}

class _AssistantSearchFieldState extends State<AssistantSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialQuery,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD7E3F4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F102A3A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _controller,
        autofocus: widget.autofocus,
        textInputAction: TextInputAction.search,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: widget.hintText,
          hintStyle: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
          prefixIcon: const Icon(
            Icons.search_rounded,
            size: 18,
            color: AppColors.secondary,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 38,
            minHeight: 38,
          ),
          suffixIcon: hasText
              ? IconButton(
                  tooltip: 'Limpiar búsqueda',
                  onPressed: () {
                    _controller.clear();
                    setState(() {});
                    widget.onChanged?.call('');
                    widget.onSubmitted?.call('');
                  },
                  icon: const Icon(Icons.close_rounded, size: 16),
                  color: AppColors.textMuted,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onChanged: (value) {
          setState(() {});
          widget.onChanged?.call(value);
        },
        onSubmitted: widget.onSubmitted,
      ),
    );
  }
}

/// Chip compacto para recursos y temas sugeridos.
class AssistantPill extends StatelessWidget {
  const AssistantPill({
    super.key,
    required this.label,
    required this.onTap,
    this.icon = Icons.article_outlined,
  });

  final String label;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        hoverColor: const Color(0xFFF3F8FF),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: AppColors.secondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Contenedor blanco compacto usado por formularios y bloques de ayuda.
class AssistantCard extends StatelessWidget {
  const AssistantCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(12, 11, 12, 12),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

/// Etiqueta pequeña sobre un campo o sección.
class AssistantFieldLabel extends StatelessWidget {
  const AssistantFieldLabel(this.text, {super.key, this.required = false});

  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text.rich(
        TextSpan(
          text: text,
          children: [
            if (required)
              const TextSpan(
                text: ' *',
                style: TextStyle(color: AppColors.error),
              ),
          ],
        ),
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

/// Aviso discreto dentro del panel (no usa SnackBar para no quedar tras el modal).
class AssistantInlineNotice extends StatelessWidget {
  const AssistantInlineNotice({
    super.key,
    required this.message,
    this.isError = false,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final accent = isError ? AppColors.error : const Color(0xFF047857);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isError ? AppColors.errorSoft : const Color(0xFFE9F8F1),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: isError ? AppColors.errorBorder : const Color(0xFFB7E7D3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            size: 15,
            color: accent,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: accent,
                fontSize: 11.5,
                height: 1.25,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Previsualización de solo lectura del mensaje antes de enviarlo.
class AssistantMessagePreview extends StatelessWidget {
  const AssistantMessagePreview({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: SelectableText(
        message,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 11.5,
          height: 1.35,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

/// Estilo del botón principal del asistente.
ButtonStyle assistantPrimaryButtonStyle() {
  return FilledButton.styleFrom(
    backgroundColor: AppColors.secondary,
    foregroundColor: Colors.white,
    disabledBackgroundColor: const Color(0xFFCBD5E1),
    disabledForegroundColor: Colors.white,
    minimumSize: const Size(0, 38),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: const TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w900,
      letterSpacing: 0,
    ),
  );
}

/// Estilo del botón secundario del asistente.
ButtonStyle assistantSecondaryButtonStyle() {
  return OutlinedButton.styleFrom(
    foregroundColor: AppColors.secondary,
    side: const BorderSide(color: Color(0xFF9DB9F8)),
    minimumSize: const Size(0, 38),
    padding: const EdgeInsets.symmetric(horizontal: 12),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: const TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
    ),
  );
}

/// Decoración compartida de los campos del asistente.
InputDecoration assistantFieldDecoration({String? hint, String? errorText}) {
  return InputDecoration(
    hintText: hint,
    errorText: errorText,
    isDense: true,
    filled: true,
    fillColor: AppColors.surfaceSubtle,
    hintStyle: const TextStyle(
      color: AppColors.textMuted,
      fontSize: 12,
      fontWeight: FontWeight.w500,
    ),
    errorStyle: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
    contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
    counterStyle: const TextStyle(fontSize: 10, color: AppColors.textMuted),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.secondary, width: 1.3),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.border),
    ),
  );
}
