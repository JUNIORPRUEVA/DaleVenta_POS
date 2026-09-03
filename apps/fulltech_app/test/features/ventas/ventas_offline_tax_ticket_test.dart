import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:daleventa_pos/core/printing/models/ticket_data.dart';
import 'package:daleventa_pos/core/printing/models/ticket_layout_config.dart';
import 'package:daleventa_pos/core/printing/models/ticket_renderer.dart';
import 'package:daleventa_pos/features/warehouses/data/warehouse_repository.dart';
import 'package:daleventa_pos/modules/ventas/data/ventas_repository.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';

/// Regresión TICKET-ITBIS-REGRESSION-ROOTCAUSE-01:
/// la venta OFFLINE/optimista se imprime inmediatamente con un SaleModel
/// local. Ese modelo local debe conservar los valores fiscales autoritativos
/// (taxableBase/taxAmount) del carrito; de lo contrario el ticket impreso
/// pierde la fila ITBIS aunque la empresa tenga impuestos activos.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OfflineStore store;
  var databaseCounter = 0;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    databaseCounter += 1;
    store = OfflineStore.forTesting('offline_tax_ticket_$databaseCounter.db');
    await store.clearAll();
    final token = TokenStorage();
    await token.saveUserSnapshot(
      UserModel.fromJson({
        'id': 'user-1',
        'email': 'cashier@fulltech.test',
        'nombreCompleto': 'Cajero',
        'companyId': 'company-1',
      }),
    );
  });

  tearDown(() async {
    await store.closeForTesting();
  });

  VentasRepository buildRepository({required bool offlineSales}) {
    final dio = Dio()
      ..httpClientAdapter = _FakeAdapter((options) {
        if (options.path == '/sales') {
          if (offlineSales) {
            throw DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
            );
          }
          return _jsonResponse({
            'id': 'sale-remote-1',
            'userId': 'user-1',
            'userName': 'Cajero',
            'totalSold': 1180,
            'totalCost': 500,
            'totalProfit': 680,
            'commissionAmount': 0,
            'paymentMethod': 'cash',
            'paymentCashAmount': 850,
            'paymentTransferAmount': 0,
            'cashReceived': 1000,
            'changeAmount': 150,
            'taxableBase': 1000,
            'taxAmount': 180,
            'exemptAmount': 0,
            'fiscalTaxEnabled': true,
            'creditAmount': 0,
            'creditPaidAmount': 850,
            'creditBalance': 0,
            'creditStatus': 'none',
            'isDeleted': false,
            'items': <dynamic>[],
          });
        }
        if (options.path.startsWith('/clients')) {
          return _jsonResponse(<dynamic>[]);
        }
        if (options.path == '/warehouses/terminals') {
          return _jsonResponse(<dynamic>[]);
        }
        return _jsonResponse(<dynamic>[]);
      });
    return VentasRepository(
      dio,
      SyncQueueService(store),
      WarehouseRepository(dio),
    );
  }

  List<SaleDraftItem> items() => const [
        SaleDraftItem(
          productId: 'prod-1',
          name: 'ARTICULO GRAVADO',
          imageUrl: null,
          isExternal: false,
          qty: 1,
          priceSoldUnit: 1000,
          costUnitSnapshot: 500,
        ),
      ];

  test(
    'OFFLINE immediate print model keeps authoritative tax and prints ITBIS',
    () async {
      final repository = buildRepository(offlineSales: true);

      final sale = await repository.createSale(
        paymentMethod: 'cash',
        paymentCashAmount: 850,
        cashReceived: 1000,
        changeAmount: 150,
        expectedTotalSold: 1180,
        optimisticTaxableBase: 1000,
        optimisticTaxAmount: 180,
        optimisticExemptAmount: 0,
        optimisticDiscountAmount: 0,
        optimisticFiscalTaxEnabled: true,
        items: items(),
      );

      expect(sale, isNotNull);
      expect(sale!.taxAmount, 180,
          reason: 'el modelo local optimista debe conservar el ITBIS');
      expect(sale.taxableBase, 1000);
      expect(sale.fiscalTaxEnabled, isTrue);
      expect(sale.cashReceived, 1000);
      expect(sale.changeAmount, 150);

      final lines = TicketRenderer(
        layout: _taxLayout,
        company: _company,
      ).buildLines(TicketData.fromSale(sale));

      expect(
        lines.any((l) => l.contains('ITBIS') && l.contains('180.00')),
        isTrue,
        reason: 'el ticket impreso de la venta offline debe mostrar ITBIS',
      );
      expect(
        lines.any(
          (l) => l.contains('EFECTIVO RECIBIDO') && l.contains('1,000.00'),
        ),
        isTrue,
      );
      expect(
        lines.any((l) => l.contains('DEVUELTA') && l.contains('150.00')),
        isTrue,
      );
      expect(lines.every((l) => l.length <= 48), isTrue);
    },
  );

  test(
    'ONLINE payload never includes the optimistic/offline tax fields',
    () async {
      RequestOptions? captured;
      final dio = Dio()
        ..httpClientAdapter = _CaptureAdapter((options) {
          captured = options;
          if (options.path == '/warehouses/terminals') {
            return _jsonResponse(<dynamic>[]);
          }
          return _jsonResponse(<dynamic>[]);
        });
      final repository = VentasRepository(
        dio,
        SyncQueueService(store),
        WarehouseRepository(dio),
      );

      await repository.createSale(
        paymentMethod: 'cash',
        paymentCashAmount: 850,
        cashReceived: 1000,
        changeAmount: 150,
        expectedTotalSold: 1180,
        optimisticTaxableBase: 1000,
        optimisticTaxAmount: 180,
        optimisticFiscalTaxEnabled: true,
        items: items(),
      );

      final data = captured!.data as Map<String, dynamic>;
      expect(data.containsKey('taxableBase'), isFalse);
      expect(data.containsKey('taxAmount'), isFalse);
      expect(data.containsKey('optimisticTaxAmount'), isFalse);
      expect(data['cashReceived'], 1000);
      expect(data['changeAmount'], 150);
    },
  );
}

const _company = CompanyInfo(
  name: 'Fulltech, srl',
  rnc: '133080206',
  phone: '8295319442',
  address: 'Higuey Beller 9',
);

const _taxLayout = TicketLayoutConfig(
  paperWidthMm: 80,
  charsPerLine: 48,
  fontSize: 'normal',
  fontFamily: 'monospace',
  showLogo: true,
  logoSize: 80,
  showBusinessData: true,
  showItbis: true,
  showCashier: true,
  showClient: true,
  showPaymentMethod: true,
  showDiscounts: true,
  showCode: true,
  showDatetime: true,
  showSubtotalItbisTotal: true,
  footerMessage: 'Gracias por su preferencia!',
  warrantyPolicy: '',
  headerExtra: '',
  headerBusinessName: '',
  headerRnc: '',
  headerAddress: '',
  headerPhone: '',
  fontSizeLevel: 1,
  lineSpacingLevel: 1,
  sectionSpacingLevel: 1,
  headerAlignment: 'left',
  detailsAlignment: 'left',
  totalsAlignment: 'right',
  topMargin: 12,
  bottomMargin: 12,
  leftMargin: 4,
  rightMargin: 4,
  sectionSeparatorStyle: 'dashed',
);

ResponseBody _jsonResponse(dynamic body) {
  return ResponseBody.fromString(
    body == null ? '{}' : body is String ? body : _encode(body),
    200,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

String _encode(dynamic body) {
  final parts = <String>[];
  void walk(dynamic value) {
    if (value is Map) {
      parts.add(
        '{${value.entries.map((e) => '"${e.key}":${_literal(e.value)}').join(',')}}',
      );
    } else if (value is List) {
      parts.add('[${value.map((e) => _literal(e)).join(',')}]');
    } else {
      parts.add(_literal(value));
    }
  }

  walk(body);
  return parts.join();
}

String _literal(dynamic value) {
  if (value == null) return 'null';
  if (value is bool) return value.toString();
  if (value is num) return value.toString();
  return '"${value.toString().replaceAll('"', '\\"')}"';
}

typedef _AdapterHandler = ResponseBody Function(RequestOptions options);

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handler);
  final _AdapterHandler _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}

class _CaptureAdapter implements HttpClientAdapter {
  _CaptureAdapter(this._handler);
  final _AdapterHandler _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
