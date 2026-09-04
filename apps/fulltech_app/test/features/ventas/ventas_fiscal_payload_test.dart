import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/features/warehouses/data/warehouse_repository.dart';
import 'package:daleventa_pos/modules/ventas/data/ventas_repository.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';

void main() {
  late List<RequestOptions> captured;

  setUp(() {
    captured = <RequestOptions>[];
  });

  ResponseBody jsonResponse(dynamic body, [int status = 200]) {
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  Map<String, dynamic> clientJson() {
    return {
      'id': 'client-1',
      'nombre': 'Potatoes Dres, SRL',
      'telefono': '',
      'taxId': '133020253',
      'businessName': 'Potatoes Dres, SRL',
      'taxIdType': 'RNC',
    };
  }

  Map<String, dynamic> saleJson() {
    return {
      'id': 'sale-1',
      'userId': 'user-1',
      'totalSold': 118,
      'totalCost': 50,
      'totalProfit': 68,
      'commissionAmount': 0,
      'paymentMethod': 'cash',
      'paymentCashAmount': 118,
      'paymentTransferAmount': 0,
      'creditAmount': 0,
      'creditPaidAmount': 0,
      'creditBalance': 0,
      'creditStatus': '',
      'isDeleted': false,
      'items': <dynamic>[],
    };
  }

  VentasRepository buildRepository({bool inventoryEnabled = true}) {
    final dio = Dio()
      ..httpClientAdapter = _FakeHttpClientAdapter((options) async {
        captured.add(options);
        if (options.path.endsWith('/settings')) {
          return jsonResponse({'inventoryEnabled': inventoryEnabled});
        }
        if (options.path.startsWith('/clients')) {
          return jsonResponse(clientJson());
        }
        if (options.path == '/warehouses/terminals') {
          return jsonResponse(<dynamic>[]);
        }
        return jsonResponse(saleJson());
      });
    return VentasRepository(
      dio,
      SyncQueueService(OfflineStore.instance),
      WarehouseRepository(dio),
    );
  }

  test(
    'createSale fiscal payload includes customerId and fiscal fields but never saveFiscalCustomer',
    () async {
      final repository = buildRepository();

      await repository.createSale(
        customerId: 'client-1',
        fiscalVoucherType: 'b01',
        fiscalCustomerTaxId: '133020253',
        fiscalCustomerName: 'Potatoes Dres, SRL',
        paymentMethod: 'cash',
        paymentCashAmount: 118,
        expectedTotalSold: 118,
        items: const [
          SaleDraftItem(
            productId: 'prod-1',
            name: 'Papa',
            imageUrl: null,
            isExternal: false,
            qty: 2,
            priceSoldUnit: 50,
            costUnitSnapshot: 20,
          ),
        ],
      );

      final request = captured.firstWhere((item) => item.path == '/sales');
      expect(request.method, 'POST');
      expect(request.path, '/sales');
      final data = request.data as Map<String, dynamic>;
      expect(data['customerId'], 'client-1');
      expect(data['fiscalVoucherType'], 'B01');
      expect(data['fiscalCustomerTaxId'], '133020253');
      expect(data['fiscalCustomerName'], 'Potatoes Dres, SRL');
      expect(
        data.containsKey('saveFiscalCustomer'),
        isFalse,
        reason: 'El payload de venta NO debe contener saveFiscalCustomer.',
      );
      expect(data['items'], isA<List<dynamic>>());
      expect(
        (data['items'] as List).single,
        containsPair('inventoryTrackedSnapshot', true),
      );
    },
  );

  test(
    'createSale omits fiscal fields entirely when no fiscal data provided',
    () async {
      final repository = buildRepository();

      await repository.createSale(
        paymentMethod: 'cash',
        paymentCashAmount: 100,
        expectedTotalSold: 100,
        items: const [
          SaleDraftItem(
            productId: 'prod-1',
            name: 'Papa',
            imageUrl: null,
            isExternal: false,
            qty: 1,
            priceSoldUnit: 100,
            costUnitSnapshot: 40,
          ),
        ],
      );

      final data =
          captured.firstWhere((item) => item.path == '/sales').data
              as Map<String, dynamic>;
      expect(data.containsKey('fiscalVoucherType'), isFalse);
      expect(data.containsKey('fiscalCustomerTaxId'), isFalse);
      expect(data.containsKey('fiscalCustomerName'), isFalse);
      expect(data.containsKey('saveFiscalCustomer'), isFalse);
      expect(
        (data['items'] as List).single,
        containsPair('inventoryTrackedSnapshot', true),
      );
    },
  );

  test(
    'updateClientFiscal PATCHes the CLIENTES endpoint with taxId and nombre',
    () async {
      final repository = buildRepository();

      await repository.updateClientFiscal(
        id: 'client-1',
        taxId: '133020253',
        nombre: 'Potatoes Dres, SRL',
      );

      final request = captured.single;
      expect(request.method, 'PATCH');
      expect(request.path, '/clients/client-1');
      final data = request.data as Map<String, dynamic>;
      expect(data['taxId'], '133020253');
      expect(data['nombre'], 'Potatoes Dres, SRL');
    },
  );

  test(
    'createSale marks inventoryTrackedSnapshot false when company inventory is off',
    () async {
      final repository = buildRepository(inventoryEnabled: false);

      await repository.createSale(
        paymentMethod: 'cash',
        paymentCashAmount: 100,
        expectedTotalSold: 100,
        items: [
          SaleDraftItem(
            product: _product(trackInventory: true, stock: 0),
            productId: 'prod-1',
            name: 'PRUEBA SIN INVENTARIO',
            imageUrl: null,
            isExternal: false,
            qty: 1,
            priceSoldUnit: 100,
            costUnitSnapshot: 40,
          ),
        ],
      );

      expect(
        sentSaleItem(captured),
        containsPair('inventoryTrackedSnapshot', false),
      );
    },
  );

  test('createSale marks non-inventory product snapshot false', () async {
    final repository = buildRepository();

    await repository.createSale(
      paymentMethod: 'cash',
      paymentCashAmount: 100,
      expectedTotalSold: 100,
      items: [
        SaleDraftItem(
          product: _product(trackInventory: false, stock: 0),
          productId: 'prod-1',
          name: 'Producto sin inventario',
          imageUrl: null,
          isExternal: false,
          qty: 1,
          priceSoldUnit: 100,
          costUnitSnapshot: 40,
        ),
      ],
    );

    expect(
      sentSaleItem(captured),
      containsPair('inventoryTrackedSnapshot', false),
    );
  });

  test('createSale marks service snapshot false', () async {
    final repository = buildRepository();

    await repository.createSale(
      paymentMethod: 'cash',
      paymentCashAmount: 100,
      expectedTotalSold: 100,
      items: [
        SaleDraftItem(
          product: _product(itemType: 'SERVICE', trackInventory: true),
          productId: 'service-1',
          name: 'Servicio',
          imageUrl: null,
          isExternal: false,
          qty: 1,
          priceSoldUnit: 100,
          costUnitSnapshot: 40,
        ),
      ],
    );

    expect(
      sentSaleItem(captured),
      containsPair('inventoryTrackedSnapshot', false),
    );
  });

  test(
    'createSale keeps tracked product snapshot true when inventory is on',
    () async {
      final repository = buildRepository();

      await repository.createSale(
        paymentMethod: 'cash',
        paymentCashAmount: 100,
        expectedTotalSold: 100,
        items: [
          SaleDraftItem(
            product: _product(trackInventory: true, stock: 10),
            productId: 'prod-1',
            name: 'Producto tracked',
            imageUrl: null,
            isExternal: false,
            qty: 1,
            priceSoldUnit: 100,
            costUnitSnapshot: 40,
          ),
        ],
      );

      expect(
        sentSaleItem(captured),
        containsPair('inventoryTrackedSnapshot', true),
      );
    },
  );

  test(
    'createSale preserves historical tracked snapshot true during replay',
    () async {
      final repository = buildRepository(inventoryEnabled: false);

      await repository.createSale(
        paymentMethod: 'cash',
        paymentCashAmount: 100,
        expectedTotalSold: 100,
        items: [
          SaleDraftItem(
            product: _product(trackInventory: false, stock: 0),
            productId: 'prod-1',
            name: 'Venta historica',
            imageUrl: null,
            isExternal: false,
            qty: 1,
            priceSoldUnit: 100,
            costUnitSnapshot: 40,
            inventoryTrackedSnapshot: true,
          ),
        ],
      );

      expect(
        sentSaleItem(captured),
        containsPair('inventoryTrackedSnapshot', true),
      );
    },
  );
}

Map<String, dynamic> sentSaleItem(List<RequestOptions> captured) {
  final data =
      captured.firstWhere((item) => item.path == '/sales').data
          as Map<String, dynamic>;
  return ((data['items'] as List).single as Map).cast<String, dynamic>();
}

ProductModel _product({
  String itemType = 'PRODUCT',
  required bool trackInventory,
  double? stock,
}) {
  return ProductModel(
    id: itemType == 'SERVICE' ? 'service-1' : 'prod-1',
    nombre: itemType == 'SERVICE' ? 'Servicio' : 'Producto',
    precio: 100,
    costo: 40,
    stock: stock,
    itemType: itemType,
    trackInventory: trackInventory,
  );
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
