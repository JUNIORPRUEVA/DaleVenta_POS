import 'package:flutter/material.dart';

import '../license_trial_ended_screen.dart';

/// VISTA PREVIA (sólo desarrollo) de la pantalla de **demo finalizada**.
///
/// `flutter run -d windows -t lib/features/plans/presentation/screens/preview/license_trial_ended_preview.dart`
///
/// Datos ficticios: no es una licencia real. Arriba hay dos botones para ver la
/// tarjeta con la fecha del servidor y sin ella (el caso en el que la API no
/// manda fecha y la pantalla no debe inventarla).
void main() => runApp(const _PreviewApp());

class _PreviewApp extends StatefulWidget {
  const _PreviewApp();

  @override
  State<_PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<_PreviewApp> {
  bool _withDate = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: const Color(0xFF1D4ED8)),
      home: Stack(
        children: [
          const _FakePos(),
          LicenseTrialEndedScreen(
            companyName: 'Comercial Demo SRL',
            endedAt: _withDate ? DateTime(2026, 11, 15) : null,
            trialDays: 7,
            onSeePlans: () {},
            onSupport: () {},
          ),
          Positioned(
            top: 8,
            left: 8,
            child: Row(
              children: [
                _chip('Con fecha', true),
                const SizedBox(width: 8),
                _chip('Sin fecha', false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, bool withDate) {
    final selected = _withDate == withDate;
    return Material(
      color: selected ? const Color(0xFF1D4ED8) : Colors.white,
      child: InkWell(
        onTap: () => setState(() => _withDate = withDate),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : const Color(0xFF16307A),
            ),
          ),
        ),
      ),
    );
  }
}

/// POS de mentira detrás, para comprobar que el desenfoque se ve.
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
            child: const Text(
              'Punto de venta · Fondo de ejemplo',
              style: TextStyle(fontSize: 13),
            ),
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
                    color: index.isEven
                        ? const Color(0xFFDCE7F5)
                        : const Color(0xFFE8EEF7),
                    alignment: Alignment.center,
                    child: Text(
                      'Producto ${index + 1}',
                      style: const TextStyle(fontSize: 12),
                    ),
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
