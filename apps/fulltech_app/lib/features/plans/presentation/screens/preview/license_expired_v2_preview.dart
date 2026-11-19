import 'package:flutter/material.dart';

import '../license_expired_screen_v2.dart';

/// VISTA PREVIA (sólo desarrollo) del plan vencido — diseño definitivo.
///
/// `flutter run -d windows -t lib/features/plans/presentation/screens/preview/license_expired_v2_preview.dart`
///
/// Datos ficticios a la vista: no son una licencia real.
void main() => runApp(const _PreviewApp());

/// Fondo simulado para que se vea el desenfoque de la tarjeta.
class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF1D4ED8)),
      home: Stack(
        children: [
          const _FakePos(),
          LicenseExpiredScreen(
            companyName: 'Comercial Demo SRL',
            planName: 'Empresa',
            expiredAt: DateTime(2026, 11, 10),
            daysExpired: 7,
            amount: 5000,
            pendingEvidenceReference: 'FP-2026-000123',
            pendingEvidenceStatus: 'en revisión',
            onPay: () {},
            onUpgrade: () {},
          ),
        ],
      ),
    );
  }
}

/// POS de mentira detrás, para comprobar que el blur se ve.
class _FakePos extends StatelessWidget {
  const _FakePos();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEFF3F9),
      child: Column(
        children: [
          Container(
            height: 44,
            color: Colors.white,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Text('Punto de venta · Fondo de ejemplo', style: TextStyle(fontSize: 13)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: List.generate(
                  12,
                  (index) => Container(
                    width: 150,
                    height: 110,
                    color: index.isEven ? const Color(0xFFDCE7F5) : const Color(0xFFE8EEF7),
                    alignment: Alignment.center,
                    child: Text('Producto ${index + 1}', style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
