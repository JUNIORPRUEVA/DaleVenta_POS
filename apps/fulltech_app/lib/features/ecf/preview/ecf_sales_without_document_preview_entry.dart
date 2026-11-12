// Vista previa SOLO para revisar cómo queda la facturación electrónica en
// Configuración: un único interruptor para el módulo y, **dentro** de él, la
// opción de facturar sin comprobante electrónico.
//
// No la importa `lib/main.dart`, así que no entra en el build de producción.
//
//   flutter run -d web-server --web-port=4800 \
//     -t lib/features/ecf/preview/ecf_sales_without_document_preview_entry.dart
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_config_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const _PreviewApp());
}

/// Aviso de ejemplo. En producción lo envía el servidor
/// (`capabilities.salesWithoutEcfWarning`) y coincide con
/// `ECF_WITHOUT_DOCUMENT_WARNING` del backend.
const String _sampleWarning =
    'Permite cerrar ventas sin comprobante electrónico ante la DGII. Cada uso '
    'queda registrado con el usuario, la fecha y el motivo, y permanece en el '
    'historial. La empresa decide cuándo aplicarla y asume la responsabilidad '
    'de ese uso; FullPOS conserva el registro disponible para auditoría.';

EcfCapabilities _capabilities({required bool allow}) => EcfCapabilities(
  enabled: true,
  environment: 'SANDBOX',
  certificationStatus: 'PRODUCTION_READY',
  productionEnabled: false,
  allowedTypes: const ['E31', 'E32'],
  emissionPathAvailable: false,
  allowSalesWithoutEcf: allow,
  salesWithoutEcfWarning: _sampleWarning,
  documentTypes: const [
    EcfDocumentTypeCapability(
      documentType: 'E31',
      contractStatus: 'ACTIVE',
      contractAllowsEmission: true,
      allowedForCompany: true,
      allocatable: true,
    ),
    EcfDocumentTypeCapability(
      documentType: 'E32',
      contractStatus: 'ACTIVE',
      contractAllowsEmission: true,
      allowedForCompany: true,
      allocatable: true,
    ),
  ],
);

class _PreviewApp extends StatelessWidget {
  const _PreviewApp();

  @override
  Widget build(BuildContext context) {
    final dio = Dio(BaseOptions(baseUrl: 'https://preview.invalid'));
    return ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        ecfRepositoryProvider.overrideWithValue(_PreviewEcfRepository(dio)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const _PreviewHome(),
      ),
    );
  }
}

class _PreviewEcfRepository extends EcfRepository {
  _PreviewEcfRepository(super.dio);

  @override
  Future<void> updateAllowSalesWithoutEcf({required bool allow}) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
}

class _PreviewHome extends StatefulWidget {
  const _PreviewHome();

  @override
  State<_PreviewHome> createState() => _PreviewHomeState();
}

class _PreviewHomeState extends State<_PreviewHome> {
  /// Interruptor del módulo (en la app real lo guarda `companySettings`).
  bool _moduleOn = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      body: Center(
        child: SizedBox(
          width: 760,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            children: [
              const Text(
                'Configuración · Empresa',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.25,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Una sola tarjeta fiscal: el módulo y, dentro, la excepción.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE8EEF5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Impuestos y e-CF',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ModuleRow(
                      value: _moduleOn,
                      onChanged: (value) => setState(() => _moduleOn = value),
                    ),
                    if (_moduleOn) ...[
                      const SizedBox(height: 10),
                      // Exactamente el widget real, en su variante anidada:
                      // sin tarjeta propia y sangrado bajo la línea del módulo.
                      EcfSalesWithoutDocumentSection(
                        capabilities: _capsOn,
                        canManage: true,
                        embedded: true,
                        nested: true,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _moduleOn
                    ? 'Con la facturación electrónica encendida, la excepción '
                          'aparece dentro de la misma tarjeta, sangrada.'
                    : 'Con la facturación electrónica apagada no se muestra '
                          'ninguna opción extra: no hay nada que exceptuar.',
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final EcfCapabilities _capsOn = _capabilities(allow: true);

class _ModuleRow extends StatelessWidget {
  const _ModuleRow({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Utilizar factura electrónica',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Al activarla aparece el módulo en el menú lateral. Por sí sola '
                'no emite comprobantes ni contacta al proveedor.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
