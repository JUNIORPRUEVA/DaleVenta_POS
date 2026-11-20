import 'package:flutter/material.dart';

import '../../../../core/errors/api_exception.dart';
import '../../../../core/license/license_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/plans_repository.dart';

/// Piezas visuales compartidas por las pantallas de la seccion Planes.
///
/// Regla de diseno: **todo recto**. Ningun boton, tarjeta ni chip lleva radio.

enum SquareVariant { primary, outline, ghost }

/// Boton rectangular, sin radio.
class SquareButton extends StatelessWidget {
  const SquareButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = SquareVariant.primary,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final SquareVariant variant;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    final Color? border;
    switch (variant) {
      case SquareVariant.primary:
        background = AppColors.primary;
        foreground = Colors.white;
        border = null;
        break;
      case SquareVariant.outline:
        background = AppColors.surface;
        foreground = AppColors.primary;
        border = AppColors.primary;
        break;
      case SquareVariant.ghost:
        background = Colors.transparent;
        foreground = AppColors.textSecondary;
        border = AppColors.border;
        break;
    }
    final disabled = onPressed == null;
    return SizedBox(
      height: 46,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: disabled ? AppColors.surfaceSubtle : background,
          foregroundColor: disabled ? AppColors.textMuted : foreground,
          shape: const RoundedRectangleBorder(),
          // El borde va en el propio boton: si se pinta detras, el fondo
          // opaco lo tapa y el contorno desaparece.
          side: border == null
              ? BorderSide.none
              : BorderSide(color: disabled ? AppColors.border : border),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17),
              const SizedBox(width: 8),
            ],
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
          ],
        ),
      ),
    );
  }
}

class PlansChip extends StatelessWidget {
  const PlansChip({
    super.key,
    required this.label,
    required this.background,
    required this.border,
    required this.color,
  });

  final String label;
  final Color background;
  final Color border;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      constraints: const BoxConstraints(maxWidth: 230),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class PlansEyebrow extends StatelessWidget {
  const PlansEyebrow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.3,
        color: AppColors.textMuted,
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PlansEyebrow(eyebrow),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Tarjeta recta con borde fino, la base de todas las secciones.
class PlansPanel extends StatelessWidget {
  const PlansPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.alt = false,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool alt;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: alt ? AppColors.surfaceAlt : AppColors.surface,
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class LoadingBlock extends StatelessWidget {
  const LoadingBlock({super.key, required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
        ),
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      ),
    );
  }
}

class ErrorBlock extends StatelessWidget {
  const ErrorBlock({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.errorSoft,
        border: Border.all(color: AppColors.errorBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: 160,
              child: SquareButton(
                label: 'Reintentar',
                variant: SquareVariant.outline,
                onPressed: onRetry,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tonos, formato y textos
// ---------------------------------------------------------------------------

class Tone {
  const Tone({
    required this.label,
    required this.background,
    required this.border,
    required this.color,
  });

  final String label;
  final Color background;
  final Color border;
  final Color color;
}

Tone licenseTone(LicenseStatusModel license) {
  final status = license.status.toUpperCase();
  if (!license.isUsable) {
    return const Tone(
      label: 'Vencida',
      background: AppColors.errorSoft,
      border: AppColors.errorBorder,
      color: AppColors.error,
    );
  }
  if (status == 'TRIAL') {
    return const Tone(
      label: 'Prueba gratis',
      background: AppColors.warningSoft,
      border: AppColors.warningBorder,
      color: AppColors.warning,
    );
  }
  return const Tone(
    label: 'Activa',
    background: AppColors.successSoft,
    border: AppColors.successBorder,
    color: AppColors.success,
  );
}

Tone orderTone(String status) {
  switch (status) {
    case 'SETTLED':
      return const Tone(
        label: 'Pagada',
        background: AppColors.successSoft,
        border: AppColors.successBorder,
        color: AppColors.success,
      );
    case 'UNCONFIRMED':
    case 'EVIDENCE_RECEIVED':
      return const Tone(
        label: 'En revision',
        background: AppColors.warningSoft,
        border: AppColors.warningBorder,
        color: AppColors.warning,
      );
    case 'REJECTED':
      return const Tone(
        label: 'Rechazada',
        background: AppColors.errorSoft,
        border: AppColors.errorBorder,
        color: AppColors.error,
      );
    case 'CANCELLED':
    case 'EXPIRED':
      return const Tone(
        label: 'Cerrada',
        background: AppColors.surfaceSubtle,
        border: AppColors.border,
        color: AppColors.textMuted,
      );
    default:
      return const Tone(
        label: 'Pendiente',
        background: AppColors.primarySoft,
        border: AppColors.secondaryBorder,
        color: AppColors.primaryDark,
      );
  }
}

String money(double value, String currency) {
  final fixed = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (match) => '${match[1]},',
  );
  final prefix = currency.toUpperCase() == 'DOP' ? 'RD\$' : '$currency ';
  return '$prefix$whole${parts.length > 1 ? '.${parts[1]}' : ''}';
}

String shortDate(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month/${local.year}';
}

String planSummary(String code) {
  switch (code.toLowerCase()) {
    case 'basico':
      return 'Para empezar a vender sin complicarte.';
    case 'negocio':
      return 'El equilibrio entre precio y capacidad.';
    case 'pro':
      return 'Para operaciones con mas movimiento.';
    case 'empresa':
      return 'Capacidad maxima y acompanamiento.';
    default:
      return '';
  }
}

/// Nombre del plan que se pinta en el encabezado: primero el catalogo y, si
/// aun no cargo, el codigo tal cual. Nunca la etiqueta heredada STANDARD.
String? currentPlanName(
  LicenseStatusModel? license,
  List<PlanOffer> catalog,
) {
  if (license == null) return null;
  final code = license.planCode?.trim().toLowerCase();
  if (code == null || code.isEmpty) return license.planLabel;
  for (final plan in catalog) {
    if (plan.code.toLowerCase() == code) return plan.name;
  }
  return '${code[0].toUpperCase()}${code.substring(1)}';
}

/// Texto para el cliente a partir del error de una peticion.
///
/// Un mensaje tecnico del servidor (`Cannot GET /license/orders/quote…`, una
/// excepcion de red, un HTML de error) **no** se le enseña a un cliente: se
/// deja el rastro en el registro y se muestra algo entendible. Un mensaje de
/// negocio del servidor (por ejemplo «La orden ya existe») si se muestra tal
/// cual, porque explica que hacer.
String errorText(Object error) {
  if (error is ApiException) {
    final message = error.message.trim();
    if (!_isTechnicalMessage(message)) return message;
    if (message != _lastTechnicalMessage) {
      _lastTechnicalMessage = message;
      debugPrint('[plans] error tecnico del servidor: $message');
    }
  }
  return 'No se pudo completar la operacion. Intenta de nuevo en un momento.';
}

/// Ultimo mensaje tecnico registrado: `errorText` se evalua en cada `build` y
/// sin esto el registro se llenaba de la misma linea.
String? _lastTechnicalMessage;

bool _isTechnicalMessage(String message) {
  if (message.isEmpty) return true;
  final lower = message.toLowerCase();
  return lower.startsWith('cannot ') ||
      lower.startsWith('<') ||
      lower.contains('dioexception') ||
      lower.contains('socketexception') ||
      lower.contains('connection refused') ||
      lower.contains('invalid statuscode') ||
      lower.contains('xmlhttprequest');
}

/// Orden abierta (la primera que encuentra).
LicenseOrder? openOrderOf(List<LicenseOrder> orders) {
  for (final order in orders) {
    if (order.isOpen) return order;
  }
  return null;
}

/// Aviso flotante, elegante, en la esquina superior derecha.
///
/// Sustituye a la barra oscura de `SnackBar`: el mensaje se lee como un
/// parrafo corto, con tipografia suave y sin tapar el contenido de trabajo.
void showPlansToast(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  var removed = false;
  late OverlayEntry entry;
  void remove() {
    if (removed) return;
    removed = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => Positioned(
      top: 16,
      right: 16,
      child: _PlansToast(
        message: message,
        isError: isError,
        onClose: remove,
      ),
    ),
  );
  overlay.insert(entry);
  Future<void>.delayed(const Duration(seconds: 5), remove);
}

class _PlansToast extends StatelessWidget {
  const _PlansToast({
    required this.message,
    required this.isError,
    required this.onClose,
  });

  final String message;
  final bool isError;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final accent = isError ? AppColors.error : const Color(0xFF15803D);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, -8 * (1 - value)),
          child: child,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: accent.withValues(alpha: 0.35)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1F0F172A),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                size: 18,
                color: accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Cerrar aviso',
                onPressed: onClose,
                icon: const Icon(Icons.close_rounded, size: 16),
                color: AppColors.textMuted,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
