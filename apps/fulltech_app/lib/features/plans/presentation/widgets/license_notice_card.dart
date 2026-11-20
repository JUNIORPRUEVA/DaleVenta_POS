import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Colores de los avisos de licencia (vencida y suspendida).
///
/// Una sola paleta para que las dos pantallas se vean igual.
abstract final class NoticeColors {
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const line = Color(0xFFE4E7EC);
  static const blue = Color(0xFF1D4ED8);
  static const blueDeep = Color(0xFF16307A);
  static const blueLine = Color(0xFFBFD3F7);
  static const blueWash = Color(0xFFEFF4FF);
}

/// Capa a pantalla completa: fondo desenfocado y la tarjeta centrada.
///
/// Es la misma envoltura para la licencia vencida y la cuenta suspendida: el
/// POS sigue debajo y no se puede operar.
class LicenseNoticeLayer extends StatelessWidget {
  const LicenseNoticeLayer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
      child: ColoredBox(
        color: const Color(0x99E5EAF3),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Material(
                  type: MaterialType.transparency,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta ancha en dos columnas con la franja de rotulo de la marca.
class LicenseNoticeCard extends StatelessWidget {
  const LicenseNoticeCard({
    super.key,
    required this.eyebrow,
    required this.icon,
    required this.companyName,
    required this.left,
    required this.right,
  });

  final String eyebrow;
  final IconData icon;
  final String companyName;
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    // Dos columnas cuando hay sitio (escritorio) y una sola en telefono.
    final wide = MediaQuery.sizeOf(context).width >= 780;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: NoticeColors.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A0F172A),
            blurRadius: 40,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(height: 3, color: NoticeColors.blueDeep),
          Container(
            color: NoticeColors.blueWash,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 13),
            child: Row(
              children: [
                Icon(icon, size: 15, color: NoticeColors.blueDeep),
                const SizedBox(width: 8),
                Text(
                  eyebrow,
                  style: const TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w800,
                    color: NoticeColors.blueDeep,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    companyName,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: NoticeColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 30, 32, 28),
            child: wide
                ? IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 5, child: left),
                        const SizedBox(width: 36),
                        Container(width: 1, color: NoticeColors.line),
                        const SizedBox(width: 36),
                        Expanded(flex: 4, child: right),
                      ],
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [left, const SizedBox(height: 22), right],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Boton principal del aviso (cuadrado, azul solido).
class NoticePrimaryButton extends StatelessWidget {
  const NoticePrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: NoticeColors.blue,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          textStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Boton secundario del aviso (cuadrado, blanco con borde azul).
class NoticeSecondaryButton extends StatelessWidget {
  const NoticeSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: NoticeColors.blueDeep,
          backgroundColor: NoticeColors.blueWash,
          side: const BorderSide(color: NoticeColors.blueLine, width: 1.3),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          textStyle: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}

/// Importe con el mismo formato que el resto de la app (DOP se escribe RD$).
String noticeMoney(num value, String currency) {
  final fixed = value.toStringAsFixed(2);
  final parts = fixed.split('.');
  final whole = parts.first;
  final buffer = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buffer.write(',');
    buffer.write(whole[i]);
  }
  final prefix = currency.toUpperCase() == 'DOP' ? 'RD\$' : '$currency ';
  return '$prefix${buffer.toString()}.${parts.last}';
}

/// Fecha corta dd/mm/aaaa.
String noticeDate(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year}';
}
