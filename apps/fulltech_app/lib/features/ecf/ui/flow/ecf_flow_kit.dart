import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Piezas visuales compartidas por las pantallas del recorrido e-CF.
///
/// Todas usan los tokens de `AppColors`: el módulo no introduce una paleta
/// paralela. La unidad es la **sección**: una sola superficie blanca con borde
/// suave. No se anidan tarjetas dentro de tarjetas, porque eso es exactamente el
/// ruido visual que este recorrido debe evitar.

const double ecfRadius = 14;

/// Superficie base: blanca, borde suave, sin sombra.
class EcfSurface extends StatelessWidget {
  const EcfSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppColors.surface,
        borderRadius: BorderRadius.circular(ecfRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

/// Sección con encabezado compacto y contenido.
///
/// El encabezado es una línea (título + acción opcional) y, si hace falta, una
/// segunda línea corta de apoyo. Nunca un bloque de ayuda extenso.
class EcfSection extends StatelessWidget {
  const EcfSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.icon,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 16),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EcfSurface(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 17, color: AppColors.primary),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 12,
                height: 1.35,
                color: AppColors.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Tono semántico de una fila de estado.
enum EcfTone { done, current, pending, warning }

({Color fg, Color bg, Color border, IconData icon}) ecfToneStyle(EcfTone tone) {
  return switch (tone) {
    EcfTone.done => (
      fg: AppColors.success,
      bg: AppColors.successSoft,
      border: AppColors.successBorder,
      icon: Icons.check_circle_rounded,
    ),
    EcfTone.current => (
      fg: AppColors.primary,
      bg: AppColors.primarySoft,
      border: AppColors.secondaryBorder,
      icon: Icons.adjust_rounded,
    ),
    EcfTone.pending => (
      fg: AppColors.textMuted,
      bg: AppColors.surfaceSubtle,
      border: AppColors.border,
      icon: Icons.radio_button_unchecked,
    ),
    EcfTone.warning => (
      fg: AppColors.warning,
      bg: AppColors.warningSoft,
      border: AppColors.warningBorder,
      icon: Icons.error_outline_rounded,
    ),
  };
}

/// Fila de resumen: icono de estado, título breve y detalle a la derecha.
class EcfSummaryRow extends StatelessWidget {
  const EcfSummaryRow({
    super.key,
    required this.label,
    required this.value,
    required this.tone,
    this.onTap,
  });

  final String label;
  final String value;
  final EcfTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = ecfToneStyle(tone);
    final row = Row(
      children: [
        Icon(style.icon, size: 16, color: style.fg),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: style.fg == AppColors.warning
                ? AppColors.warning
                : AppColors.textSecondary,
          ),
        ),
        if (onTap != null) ...[
          const SizedBox(width: 2),
          const Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: AppColors.textMuted,
          ),
        ],
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: onTap == null
          ? row
          : InkWell(
              mouseCursor: SystemMouseCursors.click,
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: row,
            ),
    );
  }
}

/// Par etiqueta/valor para los datos que FullPOS ya conoce.
class EcfField extends StatelessWidget {
  const EcfField({
    super.key,
    required this.label,
    required this.value,
    this.missingLabel = 'Sin completar',
  });

  final String label;
  final String? value;
  final String missingLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = (value ?? '').trim();
    final missing = text.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              letterSpacing: 0.2,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            missing ? missingLabel : text,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13.5,
              fontWeight: missing ? FontWeight.w400 : FontWeight.w600,
              color: missing ? AppColors.textMuted : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Insignia compacta (modo de prueba, avisos de una línea).
class EcfBadge extends StatelessWidget {
  const EcfBadge({
    super.key,
    required this.label,
    this.tone = EcfTone.warning,
    this.icon = Icons.science_outlined,
  });

  final String label;
  final EcfTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final style = ecfToneStyle(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: style.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: style.fg),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: style.fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Aviso en una sola frase, con tono.
class EcfInlineNote extends StatelessWidget {
  const EcfInlineNote({
    super.key,
    required this.text,
    this.tone = EcfTone.pending,
    this.icon = Icons.info_outline_rounded,
  });

  final String text;
  final EcfTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final style = ecfToneStyle(tone);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: style.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: style.fg),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: tone == EcfTone.warning
                    ? const Color(0xFF92400E)
                    : AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Título de paso: una línea grande y una frase de apoyo. Sin encabezados que
/// gasten media pantalla.
class EcfStepTitle extends StatelessWidget {
  const EcfStepTitle({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            height: 1.2,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Botón principal del paso. Uno solo por pantalla.
class EcfPrimaryAction extends StatelessWidget {
  const EcfPrimaryAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    this.helper,
    this.buttonKey,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;
  final String? helper;
  final Key? buttonKey;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: buttonKey,
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
        ),
        icon: busy
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon ?? Icons.arrow_forward_rounded, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
    if (helper == null) return button;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        button,
        const SizedBox(height: 6),
        Text(
          helper!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            height: 1.3,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}
