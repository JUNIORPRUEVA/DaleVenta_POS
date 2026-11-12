// Punto de entrada SOLO para verificación visual de la pantalla REAL de
// facturación (`CotizacionesScreen`) sin backend ni credenciales.
//
// `lib/main.dart` no lo importa, así que no entra en el build de producción.
// Reproduce el arnés que ya usa `test/features/price_lists/
// billing_wholesale_async_test.dart` (los mismos overrides mínimos), añade una
// cotización con un producto y activa e-CF para ver el selector en su sitio.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/auth_session_events.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/realtime/operations_realtime_service.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/price_lists/data/price_lists_repository.dart';
import 'package:daleventa_pos/modules/clientes/application/clientes_controller.dart';
import 'package:daleventa_pos/modules/clientes/cliente_model.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizacion_models.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizaciones_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _productId = '11111111-1111-4111-8111-111111111111';

void main() {
  runApp(const _BillingPreviewApp());
}

class _BillingPreviewApp extends StatelessWidget {
  const _BillingPreviewApp();

  @override
  Widget build(BuildContext context) {
    final dio = Dio(BaseOptions(baseUrl: 'https://preview.invalid'));
    dio.httpClientAdapter = _CatalogResponses();
    final storage = _MemoryStorage();

    return ProviderScope(
      overrides: [
        dioProvider.overrideWithValue(dio),
        tokenStorageProvider.overrideWithValue(storage),
        authSessionEventsProvider.overrideWith((_) => AuthSessionEvents()),
        authStateProvider.overrideWith(_PreviewAuth.new),
        companySettingsProvider.overrideWith(
          (_) async => CompanySettings.empty().copyWith(
            ecfEnabled: true,
            inventoryEnabled: true,
          ),
        ),
        priceListsRepositoryProvider.overrideWithValue(_NoPriceLists(dio)),
        ecfCapabilitiesProvider.overrideWith((_) async => _capabilities),
        operationsRealtimeServiceProvider.overrideWith(
          (ref) => OperationsRealtimeService(TokenStorage()),
        ),
        clientesControllerProvider.overrideWith(_PreviewClientes.new),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        builder: (context, child) {
          // La ventana del navegador de VS Code no llega a 1440 px de ancho y
          // las variantes de escritorio (panel lateral del formulario, panel de
          // cliente) dependen de ese ancho. Se simula el lienzo real y se
          // escala para que quepa: solo afecta a esta vista previa.
          return FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: 1440,
              height: 900,
              child: MediaQuery(
                data: const MediaQueryData(
                  size: Size(1440, 900),
                  devicePixelRatio: 1,
                ),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          );
        },
        home: CotizacionesScreen(
          initialQuotation: _sampleQuotation,
          returnSavedQuotation: true,
        ),
      ),
    );
  }
}

final _sampleQuotation = CotizacionModel(
  id: '',
  createdAt: DateTime(2026, 11, 10),
  customerId: null,
  customerName: 'Sin cliente',
  customerPhone: '',
  note: '',
  includeItbis: true,
  itbisRate: 18,
  items: const [
    CotizacionItem(
      productId: _productId,
      nombre: 'Cable de prueba',
      imageUrl: null,
      unitPrice: 900,
      originalUnitPrice: 900,
      qty: 1,
    ),
  ],
);

/// La empresa factura electrónicamente y tiene E31/E32 con numeración, más la
/// excepción «Normal» habilitada.
final _capabilities = EcfCapabilities(
  enabled: true,
  environment: 'SANDBOX',
  certificationStatus: 'PRODUCTION_READY',
  productionEnabled: false,
  allowedTypes: const ['E31', 'E32'],
  emissionPathAvailable: false,
  allowSalesWithoutEcf: true,
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

class _MemoryStorage extends TokenStorage {
  @override
  Future<UserModel?> getUserSnapshot() async => null;
  @override
  Future<String?> getAccessToken() async => 'preview-token';
  @override
  Future<String?> getRefreshToken() async => null;
  @override
  Future<void> clearTokens() async {}
}

class _PreviewAuth extends AuthController {
  _PreviewAuth(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: 'preview-user',
        email: 'preview@example.test',
        nombreCompleto: 'Vista Previa',
        telefono: '',
        role: 'ADMIN',
        companyId: 'preview-company',
      ),
    );
  }
}

class _NoPriceLists extends PriceListsRepository {
  _NoPriceLists(super.dio);
  @override
  Future<List<PriceListModel>> fetchPriceLists() async => const [];
}

/// Guarda el cliente en memoria para poder ver el formulario, el aviso de
/// «Cliente creado» y el carrito con el cliente, sin backend.
class _PreviewClientes extends ClientesController {
  _PreviewClientes(super.ref);

  @override
  Future<void> load({String? search}) async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<ClienteModel> saveCliente({
    required String nombre,
    required String telefono,
    String? direccion,
    String? locationUrl,
    String? correo,
    String? taxId,
    String? businessName,
    String? taxIdType,
    String? id,
  }) async {
    state = state.copyWith(saving: true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    state = state.copyWith(saving: false);
    return ClienteModel(
      id: 'preview-${DateTime.now().millisecondsSinceEpoch}',
      ownerId: 'preview-owner',
      nombre: nombre.trim(),
      telefono: telefono.trim(),
      direccion: (direccion ?? '').trim().isEmpty ? null : direccion?.trim(),
      taxId: (taxId ?? '').trim().isEmpty ? null : taxId?.trim(),
    );
  }
}

/// Catálogo de un solo producto para que la pantalla tenga algo que mostrar.
class _CatalogResponses implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions request,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    return ResponseBody.fromString(
      jsonEncode({
        'items': [
          {
            'id': _productId,
            'nombre': 'Cable de prueba',
            'precio': 900,
            'costo': 400,
            'categoria': 'Prueba',
            'trackInventory': false,
          },
        ],
        'total': 1,
        'page': 1,
        'hasMore': false,
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
