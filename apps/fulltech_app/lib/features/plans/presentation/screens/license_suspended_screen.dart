import 'package:flutter/material.dart';

import '../widgets/license_notice_card.dart';

/// PANTALLA DE **CUENTA SUSPENDIDA** (bloqueada).
///
/// Mismo patron visual que la de plan vencido: capa con el POS desenfocado y
/// una tarjeta ancha con el motivo y la salida. La diferencia esta en el
/// mensaje y en la accion:
///
/// - Si la suspension es por **falta de pago** (hay cuota vencida u orden
///   abierta) se ofrece pagar, con soporte como segunda opcion.
/// - Si es por **otra causa** (decision del equipo, incidencia...) solo se
///   ofrece hablar con soporte: pagar no arreglaria nada.
///
/// Como en la pantalla de vencida, aqui **no** se calcula nada: el importe y el
/// motivo llegan del servidor; si no llegan, no se inventan.
class LicenseSuspendedScreen extends StatelessWidget {
  const LicenseSuspendedScreen({
    super.key,
    required this.companyName,
    required this.owesMoney,
    this.amount,
    this.currency = 'DOP',
    this.blockedAt,
    this.reasonLabel,
    required this.onPay,
    required this.onSupport,
  });

  final String companyName;

  /// `true` cuando la suspension es por dinero (cuota vencida u orden abierta).
  final bool owesMoney;

  final num? amount;
  final String currency;
  final DateTime? blockedAt;

  /// Motivo tal como lo describe la plataforma, si aporta algo distinto de
  /// «falta de pago». Nunca se inventa uno.
  final String? reasonLabel;

  final VoidCallback onPay;
  final VoidCallback onSupport;

  @override
  Widget build(BuildContext context) {
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Tu cuenta está suspendida',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 19,
            height: 1.25,
            fontWeight: FontWeight.w700,
            color: NoticeColors.ink,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          blockedAt == null
              ? 'Mientras este suspendida no se puede vender ni facturar.'
              : 'Desde el ${noticeDate(blockedAt!)} no se puede vender ni facturar.',
          style: const TextStyle(fontSize: 12.5, color: NoticeColors.muted),
        ),
        const SizedBox(height: 20),
        const Text(
          'MOTIVO',
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
            color: NoticeColors.muted,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          owesMoney
              ? 'Falta de pago de tu plan.'
              : (reasonLabel?.trim().isNotEmpty == true
                    ? reasonLabel!.trim()
                    : 'Suspendimos el acceso durante una revision de tu cuenta.'),
          style: const TextStyle(
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: NoticeColors.ink,
          ),
        ),
        if (owesMoney && amount != null) ...[
          const SizedBox(height: 18),
          const Text(
            'IMPORTE A PAGAR',
            style: TextStyle(
              fontSize: 10.5,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: NoticeColors.muted,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              noticeMoney(amount!, currency),
              maxLines: 1,
              style: const TextStyle(
                fontSize: 26,
                height: 1.1,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                color: NoticeColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Un mes del plan actual. No se cobran meses adicionales.',
            style: TextStyle(fontSize: 12, color: NoticeColors.muted, height: 1.35),
          ),
        ],
        const SizedBox(height: 18),
        const Text(
          'Tus ventas, inventario y clientes siguen guardados.',
          style: TextStyle(fontSize: 12, color: NoticeColors.muted, height: 1.35),
        ),
      ],
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (owesMoney) ...[
          NoticePrimaryButton(
            label: 'REALIZAR PAGO',
            onPressed: onPay,
          ),
          const SizedBox(height: 10),
          NoticeSecondaryButton(
            label: 'HABLAR CON SOPORTE',
            onPressed: onSupport,
          ),
        ] else
          NoticePrimaryButton(
            label: 'HABLAR CON SOPORTE',
            onPressed: onSupport,
          ),
        const SizedBox(height: 14),
        Text(
          '$companyName · En cuanto se regularice, todo vuelve a la normalidad.',
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
        eyebrow: 'CUENTA SUSPENDIDA',
        icon: Icons.pause_circle_outline_rounded,
        companyName: companyName,
        left: left,
        right: right,
      ),
    );
  }
}
