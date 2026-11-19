import 'package:flutter/material.dart';

import '../widgets/license_notice_card.dart';

/// PANTALLA DE **DEMO FINALIZADA** (se acabaron los días de prueba).
///
/// Es el final del camino de un cliente nuevo: la demo se abre sola al crear la
/// empresa (7 días) y, cuando vence, el punto de venta queda en pausa hasta que
/// elija un plan de pago.
///
/// Mismo patrón visual que la vencida y la suspendida —capa con el POS
/// desenfocado y tarjeta ancha en dos columnas—, pero aquí solo hay **una
/// decisión**: ver los planes. No se muestra importe porque todavía no hay plan
/// elegido y, por tanto, el servidor no tiene nada que cobrar; inventar una
/// cifra sería mentir al cliente.
class LicenseTrialEndedScreen extends StatelessWidget {
  const LicenseTrialEndedScreen({
    super.key,
    required this.companyName,
    this.endedAt,
    this.trialDays = 7,
    required this.onSeePlans,
    this.onSupport,
  });

  final String companyName;

  /// Fecha en la que terminó la prueba, tal como la envía el servidor. Si no
  /// llega, la tarjeta **no** inventa una fecha.
  final DateTime? endedAt;

  /// Días que duró la prueba (7 por defecto, como la crea la plataforma).
  final int trialDays;

  final VoidCallback onSeePlans;

  /// Canal de ayuda. Si no se pasa, no se ofrece: no se inventan canales.
  final VoidCallback? onSupport;

  /// Días completos transcurridos desde el final de la prueba.
  int get _daysSince {
    final ended = endedAt;
    if (ended == null) return 0;
    final now = DateTime.now();
    final end = DateTime(ended.year, ended.month, ended.day);
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(end).inDays;
    return days < 0 ? 0 : days;
  }

  String get _detail {
    final ended = endedAt;
    if (ended == null) return 'Tu periodo de prueba ya terminó.';
    final days = _daysSince;
    if (days <= 0) return 'El ${noticeDate(ended)}';
    return 'El ${noticeDate(ended)} · hace $days día${days == 1 ? '' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Tu demo de $trialDays días terminó',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 19,
            height: 1.25,
            fontWeight: FontWeight.w700,
            color: NoticeColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _detail,
          style: const TextStyle(fontSize: 12.5, color: NoticeColors.muted),
        ),
        const SizedBox(height: 20),
        const Text(
          'PARA SEGUIR VENDIENDO',
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
            color: NoticeColors.muted,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Elige el plan que mejor se acomode a tu negocio. Verás el monto '
          'exacto de cada plan antes de pagar.',
          style: TextStyle(
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: NoticeColors.ink,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Mientras no elijas uno, el punto de venta queda en pausa.',
          style: TextStyle(
            fontSize: 12,
            color: NoticeColors.muted,
            height: 1.35,
          ),
        ),
      ],
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        NoticePrimaryButton(
          label: 'VER PLANES',
          onPressed: onSeePlans,
        ),
        if (onSupport != null) ...[
          const SizedBox(height: 2),
          TextButton(
            onPressed: onSupport,
            style: TextButton.styleFrom(
              foregroundColor: NoticeColors.blueDeep,
              minimumSize: const Size(0, 36),
              padding: EdgeInsets.zero,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('¿Necesitas ayuda? Habla con soporte'),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          '$companyName · Tus ventas, inventario y clientes siguen guardados.',
          style: const TextStyle(
            fontSize: 11,
            color: NoticeColors.muted,
            height: 1.4,
          ),
        ),
      ],
    );

    return LicenseNoticeLayer(
      child: LicenseNoticeCard(
        eyebrow: 'DEMO FINALIZADA',
        icon: Icons.hourglass_disabled_rounded,
        companyName: companyName,
        left: left,
        right: right,
      ),
    );
  }
}
