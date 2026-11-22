import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/pagination/paged_result.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/core/widgets/provided_action_icon.dart';
import 'package:daleventa_pos/core/widgets/pdf_preview_panel.dart';
import 'package:daleventa_pos/modules/compras/compras_screen.dart';
import 'package:daleventa_pos/modules/compras/data/purchases_repository.dart';
import 'package:daleventa_pos/modules/compras/purchase_models.dart';
import 'package:daleventa_pos/core/utils/app_feedback.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../support/platform_goldens.dart';

const _supplier = SupplierModel(
  id: 'supplier',
  commercialName: 'Distribuidora de equipos',
  contactName: 'Contacto de prueba',
  phone: '8090000000',
  totalPurchased: 12500,
  ordersCount: 4,
);
final _product = ProductModel(
  id: 'p1',
  nombre: 'Adaptador profesional con nombre largo para revisar alineación',
  codigo: 'AD-01',
  categoria: 'Accesorios',
  precio: 2500,
  costo: 1300,
  stock: 10,
);
final _order = PurchaseOrderModel.fromJson({
  'id': 'o1',
  'orderNumber': 'OC-2026-001',
  'status': 'DRAFT',
  'supplier': {'id': 'supplier', 'commercialName': _supplier.commercialName},
  'subtotal': 2600,
  'total': 2600,
  'items': [
    {
      'id': 'i1',
      'productNameSnapshot': 'Adaptador profesional',
      'quantity': 2,
      'unitCost': 1300,
      'subtotal': 2600,
      'pendingQuantity': 2,
      'receivedQuantity': 0,
    },
  ],
});
final _invoice = PurchaseInvoiceModel(
  id: 'invoice',
  supplier: _supplier,
  invoiceNumber: 'FC-2026-003',
  amount: 2600,
  invoiceDate: DateTime(2026, 11, 1),
  fileName: 'factura.pdf',
  fileUrl: '',
  mimeType: 'application/octet-stream',
  fileSize: 1024,
);

class _Repository extends PurchasesRepository {
  _Repository({this.emptySuppliers = false}) : super(Dio());
  final bool emptySuppliers;
  int uploads = 0;
  @override
  Future<PurchaseInvoiceModel> uploadInvoice({
    required PlatformFile file,
    required String supplierId,
    String? purchaseOrderId,
    String? invoiceNumber,
    String? invoiceDate,
    double? amount,
    String? notes,
  }) async {
    expect(file.bytes, isNotEmpty);
    expect(supplierId, _supplier.id);
    uploads++;
    return _invoice;
  }

  @override
  Future<List<SupplierModel>> cachedSuppliers() async => [];
  @override
  Future<List<PurchaseOrderModel>> cachedOrders() async => [];
  @override
  Future<List<PurchaseRecommendationModel>> cachedRecommendations() async => [];
  @override
  Future<List<PurchaseInvoiceModel>> cachedInvoices() async => [];
  @override
  Future<List<SupplierModel>> listSuppliers({String? query}) async =>
      emptySuppliers ? [] : [_supplier];
  @override
  Future<PagedResult<PurchaseOrderModel>> listOrdersPage({
    String? query,
    String? status,
    String? supplierId,
    required int page,
    required int limit,
  }) async => PagedResult(
    items: [_order],
    page: 1,
    limit: 50,
    hasMore: false,
    total: 1,
  );
  @override
  Future<List<PurchaseRecommendationModel>> recommendations() async => [
    PurchaseRecommendationModel(
      product: _product,
      stock: 10,
      minStock: 20,
      alreadyOrdered: 2,
      suggestedQuantity: 8,
      reason: 'Stock bajo',
    ),
  ];
  @override
  Future<List<PurchaseInvoiceModel>> listInvoices({
    String? supplierId,
    String? query,
    String? purchaseOrderId,
  }) async => [_invoice];
}

class _Auth extends AuthController {
  _Auth(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: 'test',
        email: 'test@test.local',
        nombreCompleto: 'Usuario',
        telefono: '',
        role: 'ADMIN',
        companyId: 'visual-test',
      ),
    );
  }
}

Future<void> _pump(
  WidgetTester tester,
  String section,
  Size size, {
  _Repository? repository,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (request, handler) {
        handler.resolve(
          Response(
            requestOptions: request,
            data: request.path.endsWith('/categories')
                ? {
                    'items': [
                      {'name': 'Accesorios', 'count': 1},
                    ],
                  }
                : {
                    'items': [_product.toJson()],
                    'page': 1,
                    'limit': 50,
                    'total': 1,
                    'hasMore': false,
                  },
          ),
        );
      },
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith((ref) => _Auth(ref)),
        companySettingsProvider.overrideWith(
          (ref) async => CompanySettings.empty(),
        ),
        purchasesRepositoryProvider.overrideWith(
          (ref) => repository ?? _Repository(),
        ),
        dioProvider.overrideWithValue(dio),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(size.width == 1024 ? 1.15 : 1),
          ),
          child: child!,
        ),
        home: ComprasScreen(initialMobileTab: section),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final context = tester.element(find.byType(ComprasScreen));
    for (final action in ProvidedAction.values) {
      await precacheImage(
        AssetImage('assets/image/action_${action.name}.png'),
        context,
      );
    }
    for (final name in ['back', 'search', 'filter', 'refresh', 'more']) {
      await precacheImage(
        AssetImage('assets/image/mobile_navigation/$name.png'),
        context,
      );
    }
  });
  await tester.pumpAndSettle();
}

class _InvoicePicker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    expect(withData, isTrue);
    return FilePickerResult([
      PlatformFile(
        name: 'factura.pdf',
        size: 4,
        bytes: Uint8List.fromList([37, 80, 68, 70]),
      ),
    ]);
  }
}

void main() {
  testWidgets('PDF de compra reutiliza el panel izquierdo a todo el alto', (
    tester,
  ) async {
    await _pump(tester, 'orders', const Size(1600, 900));
    await tester.runAsync(() async {
      await tester.tap(find.byTooltip('PDF').first);
    });
    final panel = find.byType(PdfPreviewPanelSurface);
    for (var attempt = 0; attempt < 40 && panel.evaluate().isEmpty; attempt++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      });
      await tester.pump();
    }
    // El visor nativo conserva su indicador en widget tests; completar solo
    // la transición del panel sin esperar al rasterizador de plataforma.
    await tester.pump(const Duration(milliseconds: 400));
    expect(panel, findsOneWidget);
    final rect = tester.getRect(panel);
    expect(rect.left, 0);
    expect(rect.top, 0);
    expect(rect.width, 800);
    expect(rect.height, 900);
    expect(find.byType(PdfPreviewStage), findsOneWidget);
    expect(find.text('PDF orden de compra · OC-2026-001'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();
    expect(panel, findsNothing);
    expect(find.textContaining('OC-2026-001'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  tearDown(AppFeedback.clearToasts);
  testWidgets('Compras ofrece regresar y conserva el switch en el encabezado', (
    tester,
  ) async {
    await _pump(tester, 'new', const Size(1024, 600));
    expect(find.byTooltip('Regresar'), findsOneWidget);
    expect(find.byTooltip('Abrir menú'), findsNothing);
    expect(
      tester.getCenter(find.byType(Switch)).dy,
      closeTo(tester.getCenter(find.text('Orden de compra')).dy, 10),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Suplidores vacío permite abrir y cancelar Nuevo suplidor', (
    tester,
  ) async {
    await _pump(
      tester,
      'suppliers',
      const Size(1024, 600),
      repository: _Repository(emptySuppliers: true),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Nuevo suplidor'));
    await tester.pumpAndSettle();
    expect(find.text('Crear suplidor'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('No hay suplidores.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Por comprar guarda el producto sugerido en el borrador y avisa arriba',
    (tester) async {
      await _pump(tester, 'recommendations', const Size(1024, 600));
      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Producto agregado a Nueva compra.', findRichText: true),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      final saved = (await SharedPreferences.getInstance()).getKeys().where(
        (key) => key.contains('purchase'),
      );
      expect(saved, isNotEmpty);
      final storage = await SharedPreferences.getInstance();
      expect(
        saved.map((key) => storage.get(key)).join(),
        contains('Adaptador profesional'),
      );
      final toast = tester.getRect(
        find.byKey(const ValueKey('app_feedback_toast_Compras')),
      );
      expect(toast.top, lessThan(160));
      expect(toast.right, greaterThan(1000));
      AppFeedback.clearToasts();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'Subir factura valida sin cerrar y envía el archivo seleccionado',
    (tester) async {
      final repository = _Repository();
      final previous = FilePicker.platform;
      FilePicker.platform = _InvoicePicker();
      addTearDown(() => FilePicker.platform = previous);
      await _pump(
        tester,
        'invoices',
        const Size(1024, 600),
        repository: repository,
      );
      await tester.tap(find.byTooltip('Subir factura'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar factura'));
      await tester.pumpAndSettle();
      expect(find.text('Subir factura de compra'), findsOneWidget);
      expect(repository.uploads, 0);
      await tester.tap(find.text('Seleccionar archivo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar factura'));
      await tester.pumpAndSettle();
      expect(repository.uploads, 1);
      expect(
        find.textContaining('Factura de compra guardada.', findRichText: true),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      AppFeedback.clearToasts();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('las acciones de órdenes siguen disponibles en el menú', (
    tester,
  ) async {
    await _pump(tester, 'orders', const Size(1024, 600));
    await tester.tap(find.byTooltip('Acciones de la orden'));
    await tester.pumpAndSettle();
    for (final action in ['Aprobar', 'Enviar', 'Duplicar', 'Eliminar']) {
      expect(find.text(action), findsOneWidget);
    }
    expect(find.text('Registrar recepción'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('opciones adicionales accesibles en 11 pulgadas', (tester) async {
    await _pump(tester, 'new', const Size(1024, 600));
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.widgetWithText(TextField, 'Descuento'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  setUpAll(() async {
    FilePicker.platform = _InvoicePicker();
    final font = FontLoader('Manrope');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final size in [
    const Size(390, 844),
    const Size(1024, 600),
    const Size(1920, 1080),
  ]) {
    for (final section in [
      'new',
      'orders',
      'suppliers',
      'invoices',
      'recommendations',
    ]) {
      testWidgets('compras $section en $size', (tester) async {
        await _pump(tester, section, size);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
            platformGolden(
              'goldens/purchases_${section}_${size.width.toInt()}.png',
            ),
          ),
        );
        if (section == 'orders' && size.width >= 980) {
          await tester.tap(find.textContaining('OC-2026-001').first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              platformGolden(
                'goldens/purchase_detail_${size.width.toInt()}.png',
              ),
            ),
          );
        }
        if (section == 'suppliers') {
          await tester.tap(find.text(_supplier.commercialName).first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              platformGolden(
                'goldens/supplier_detail_${size.width.toInt()}.png',
              ),
            ),
          );
          if (size.width < 980) {
            tester.state<NavigatorState>(find.byType(Navigator).first).pop();
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byTooltip('Nuevo suplidor').first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              platformGolden('goldens/supplier_form_${size.width.toInt()}.png'),
            ),
          );
        }
        if (section == 'new') {
          await tester.tap(find.byTooltip('Filtros').first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              platformGolden(
                'goldens/purchase_filters_${size.width.toInt()}.png',
              ),
            ),
          );
          await tester.tap(find.byTooltip('Cerrar').first);
          await tester.pumpAndSettle();
          await tester.tap(
            size.width < 700
                ? find.byTooltip('Producto externo')
                : find.text('Nuevo producto'),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              platformGolden(
                'goldens/external_product_${size.width.toInt()}.png',
              ),
            ),
          );
          await tester.tap(find.text('Cancelar'));
          await tester.pumpAndSettle();
        }
        if (section == 'invoices') {
          await tester.tap(find.byTooltip('Subir factura').first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              platformGolden(
                'goldens/purchase_invoice_form_${size.width.toInt()}.png',
              ),
            ),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
