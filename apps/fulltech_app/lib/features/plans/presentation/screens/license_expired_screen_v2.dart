import 'package:flutter/material.dart';

import '../widgets/license_notice_card.dart';

/// PANTALLA ÚNICA DE PLAN VENCIDO (diseño definitivo).
///
/// Aparece sobre el POS con el fondo desenfocado. Muestra el plan vencido, la
/// fecha y el importe pendiente, y solo dos acciones: pagar (transferencia) o
/// mejorar de plan. No da acceso a módulos y no calcula importes.
///
/// Es la misma pantalla para el estado VENCIDO; la demo finalizada se trabaja
/// aparte y no usa este widget.
class LicenseExpiredScreen extends StatelessWidget {
  const LicenseExpiredScreen({
    super.key,
    required this.companyName,
    required this.planName,
    required this.expiredAt,
    this.amount,
    this.currency = 'DOP',
    this.daysExpired,
    this.pendingEvidenceReference,
    this.pendingEvidenceStatus,
    required this.onPay,
    required this.onUpgrade,
  });

  final String companyName;
  final String planName;
  final DateTime expiredAt;

  /// Importe pendiente tal como lo calcula el servidor. `null` cuando todavia
  /// no hay plan ni orden: la tarjeta **no** inventa una cifra.
  final num? amount;
  final String currency;
  final int? daysExpired;
  final String? pendingEvidenceReference;
  final String? pendingEvidenceStatus;
  final VoidCallback onPay;
  final VoidCallback onUpgrade;

  static const _ink = NoticeColors.ink;
  static const _muted = NoticeColors.muted;
  static const _blueWash = NoticeColors.blueWash;
  static const _blueDeep = NoticeColors.blueDeep;

  String _date(DateTime value) => noticeDate(value);

  String _money(num value) => noticeMoney(value, currency);

  @override
  Widget build(BuildContext context) {
    // Se pinta como capa encima de la pantalla de trabajo (el POS), no como
    // ruta aparte: el desenfoque tiene que comerse lo que hay detras.
    return LicenseNoticeLayer(child: _sheet(context));
  }

  Widget _sheet(BuildContext context) {
    final days = daysExpired ?? 0;
    final detail = days > 0
        ? 'El ${_date(expiredAt)} · hace $days día${days == 1 ? '' : 's'}'
        : 'El ${_date(expiredAt)}';

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Tu plan $planName venció',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 19, height: 1.25, fontWeight: FontWeight.w700, color: _ink),
        ),
        const SizedBox(height: 4),
        Text(detail, style: const TextStyle(fontSize: 12.5, color: _muted)),
        const SizedBox(height: 20),
        const Text(
          'IMPORTE A PAGAR',
          style: TextStyle(fontSize: 10.5, letterSpacing: 1.1, fontWeight: FontWeight.w700, color: _muted),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            amount == null ? '—' : _money(amount!),
            maxLines: 1,
            style: TextStyle(
              // Discreto a proposito: es un dato, no el titular de la pantalla.
              fontSize: 26,
              height: 1.1,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: amount == null ? _muted : _ink,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          amount == null
              ? 'Importe pendiente del plan actual'
              : 'Un mes del plan actual. No se cobran meses adicionales.',
          style: const TextStyle(fontSize: 12, color: _muted, height: 1.35),
        ),
      ],
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pendingEvidenceReference != null) ...[
          Container(
            color: _blueWash,
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Comprobante en revisión',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _blueDeep),
                ),
                const SizedBox(height: 3),
                Text(
                  'Ref. $pendingEvidenceReference'
                  '${pendingEvidenceStatus == null ? '' : ' · ${pendingEvidenceStatus!}'}. No hace falta subirlo otra vez.',
                  style: const TextStyle(fontSize: 12, color: _muted, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        SizedBox(
          height: 46,
          child: FilledButton(
            onPressed: onPay,
            style: FilledButton.styleFrom(
              backgroundColor: NoticeColors.blue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: 0.4),
            ),
            child: const Text('REALIZAR PAGO'),
          ),
        ),
        const SizedBox(height: 10),
        NoticeSecondaryButton(
          label: 'MEJORAR MI PLAN',
          onPressed: onUpgrade,
        ),
        const SizedBox(height: 14),
        Text(
          '$companyName · Tus ventas, inventario y clientes siguen guardados.',
          style: const TextStyle(fontSize: 11, color: _muted, height: 1.4),
        ),
      ],
    );

    return LicenseNoticeCard(
      eyebrow: 'PLAN VENCIDO',
      icon: Icons.lock_clock_rounded,
      companyName: companyName,
      left: left,
      right: right,
    );
  }
}
