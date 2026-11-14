import 'dart:io';
import 'dart:ui' as ui;

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/core/utils/app_feedback.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_connection_guard.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_dosa_dispatch_models.dart';
import 'package:daleventa_pos/features/ecf/ecf_sale_fiscal.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_sale_history_panel.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:daleventa_pos/modules/ventas/data/ventas_repository.dart';
import 'package:daleventa_pos/modules/ventas/tpv_sales_history_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';

class _Auth extends AuthController {
  _Auth(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel.fromJson({
        'id': 'actor',
        'companyId': 'company',
        'role': 'ADMIN',
        'email': 'fixture@local.test',
      }),
    );
  }
}

class _Repository extends EcfRepository {
  _Repository() : super(Dio());
  int sends = 0;
  int recoveries = 0;
  EcfConnectionException? failure;
  EcfSaleFiscal value = const EcfSaleFiscal(
    saleId: 'sale',
    intent: 'E31',
    documents: [
      EcfSaleFiscalDocument(
        documentId: 'document',
        documentType: 'E31',
        status: 'LOCAL_VALIDATED',
        encf: 'E310000000001',
        environment: 'SANDBOX',
      ),
    ],
  );
  @override
  Future<Map<String, EcfSaleFiscal>> salesFiscal(List<String> ids) async => {
    'sale': value,
  };
  @override
  Future<EcfDosaDispatchOutcome> recoverDosa(String id) async {
    recoveries++;
    if (failure != null) throw failure!;
    return EcfDosaDispatchOutcome.fromJson({'ok': true, 'result': 'FISCAL_RESULT_RECORDED'});
  }
  @override
  Future<EcfDosaDispatchOutcome> dispatchDosa(String id) async {
    sends++;
    if (failure != null) throw failure!;
    return const EcfDosaDispatchOutcome(
      ok: true,
      code: null,
      blockingReasons: [],
      result: 'FISCAL_RESULT_RECORDED',
      correlated: true,
      encf: 'E310000000001',
      environment: 'test',
      httpStatus: 200,
      providerOutcome: 'ACCEPTED',
      safeCode: null,
      sequenceConsumed: true,
    );
  }
}

class _LocalHttp implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString(
    '{}',
    200,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
  @override
  void close({bool force = false}) {}
}

class _HistorySales implements VentasRepository {
  final rows = [
    SaleModel.fromJson({
      'id': 'sale',
      'userId': 'actor',
      'invoiceNumber': 1001,
      'totalSold': 118,
      'returnableAmount': 118,
      'canReturn': true,
      'fiscalVoucherType': 'E31',
      'customer': {'nombre': 'Cliente electrónico'},
      'saleDate': '2026-11-13T12:00:00Z',
      'items': [],
    }),
    SaleModel.fromJson({
      'id': 'normal',
      'userId': 'actor',
      'invoiceNumber': 1002,
      'totalSold': 100,
      'returnableAmount': 100,
      'canReturn': true,
      'customer': {'nombre': 'Cliente normal'},
      'saleDate': '2026-11-13T12:00:00Z',
      'items': [],
    }),
  ];
  @override
  Future<SalesPageResult> cachedInvoicesPage({
    required DateTime from,
    required DateTime to,
    String? customerId,
    bool includeDeleted = true,
    int page = 1,
    int limit = 50,
  }) async => SalesPageResult(
    items: rows,
    page: page,
    limit: limit,
    hasMore: false,
    nextPage: null,
  );
  @override
  Future<SalesPageResult> listInvoicesPage({
    required DateTime from,
    required DateTime to,
    String? customerId,
    bool includeDeleted = true,
    int page = 1,
    int limit = 50,
  }) => cachedInvoicesPage(from: from, to: to, page: page, limit: limit);
  @override
  Future<SalesSummaryModel> summary({
    required DateTime from,
    required DateTime to,
    String? userId,
    String? customerId,
  }) async => const SalesSummaryModel(
    totalSales: 2,
    totalSold: 218,
    totalCost: 0,
    totalProfit: 218,
    totalCommission: 0,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final capture = GlobalKey();
  setUpAll(() async {
    await initializeDateFormatting('es_DO');
    final font = FontLoader('Manrope');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(AppFeedback.clearToasts);
  Future<void> pump(
    WidgetTester tester,
    _Repository repo, {
    double width = 320,
    bool electronic = true,
  }) async {
    tester.view.physicalSize = Size(width, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sale = SaleModel.fromJson({
      'id': 'sale',
      'userId': 'actor',
      'totalSold': 118,
      'fiscalTaxEnabled': true,
      if (electronic) 'fiscalVoucherType': 'E31',
      'items': [],
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith((ref) => _Auth(ref)),
          ecfRepositoryProvider.overrideWithValue(repo),
        ],
        child: RepaintBoundary(
          key: capture,
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              appBar: AppBar(title: const Text('Historial de ventas')),
              body: Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                  width: width >= 900 ? width * .32 : width,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: EcfSaleHistoryPanel(sale: sale),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> export(WidgetTester tester, String name) async {
    final output = Platform.environment['FULLPOS_ECF_HISTORY_QA'];
    if (output == null) return;
    final boundary =
        capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final picture = await boundary.toImage();
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    });
  }

  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'fiscal history and discreet offline notice remain readable at $width',
      (tester) async {
        final repo = _Repository()..failure = EcfConnectionException();
        await pump(tester, repo, width: width);
        expect(find.text('E31 · E310000000001'), findsOneWidget);
        await export(tester, 'history-${width.toInt()}');
        await tester.tap(find.text('Emitir E31'));
        await tester.pumpAndSettle();
        expect(find.text('Sin conexión'), findsOneWidget);
        expect(find.byType(AlertDialog), findsNothing);
        final notice = tester.getRect(
          find.byKey(const ValueKey('app_feedback_toast_Sin conexión')),
        );
        expect(notice.right, lessThanOrEqualTo(width));
        expect(notice.top, lessThan(200));
        expect(tester.takeException(), isNull);
        await export(tester, 'offline-${width.toInt()}');
        await tester.pump(const Duration(seconds: 5));
        expect(find.text('Sin conexión'), findsNothing);
      },
    );
  }
  testWidgets(
    'an unconfirmed POST disables another emission until the status is read',
    (tester) async {
      final repo = _Repository()
        ..failure = EcfConnectionException(uncertain: true);
      await pump(tester, repo);
      await tester.tap(find.text('Emitir E31'));
      await tester.pumpAndSettle();
      expect(repo.sends, 1);
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Emitir E31'),
      );
      expect(button.onPressed, isNull);
      repo.value = const EcfSaleFiscal(
        saleId: 'sale',
        intent: 'E31',
        documents: [
          EcfSaleFiscalDocument(
            documentId: 'document',
            documentType: 'E31',
            status: 'DGII_ACCEPTED',
            encf: 'E310000000001',
            conditional: true,
          ),
        ],
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.byTooltip('Actualizar estado fiscal'));
      await tester.pumpAndSettle();
      expect(find.text('Emitir E31'), findsNothing);
      expect(find.text('Aceptado condicional'), findsOneWidget);
      expect(repo.sends, 1);
      await tester.pump(const Duration(seconds: 5));
    },
  );
  testWidgets('an uncertain verification requires refresh and never starts another emission', (tester) async {
    final repo = _Repository()
      ..failure = EcfConnectionException(uncertain: true)
      ..value = const EcfSaleFiscal(saleId: 'sale', intent: 'E31', documents: [
        EcfSaleFiscalDocument(documentId: 'document', documentType: 'E31', status: 'UNKNOWN_RESULT', encf: 'E310000000001'),
      ]);
    await pump(tester, repo);
    expect(find.text('Emitir E31'), findsNothing);
    await tester.tap(find.text('Verificar con DOSA'));
    await tester.pumpAndSettle();
    expect(repo.recoveries, 1);
    expect(repo.sends, 0);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Verificar con DOSA')).onPressed, isNull);
    await tester.pump(const Duration(seconds: 5));
    repo.value = const EcfSaleFiscal(saleId: 'sale', intent: 'E31', documents: [
      EcfSaleFiscalDocument(documentId: 'document', documentType: 'E31', status: 'DGII_ACCEPTED', encf: 'E310000000001'),
    ]);
    await tester.tap(find.byTooltip('Actualizar estado fiscal'));
    await tester.pumpAndSettle();
    expect(find.text('Verificar con DOSA'), findsNothing);
    expect(repo.recoveries, 1);
    expect(repo.sends, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a taxable ordinary sale does not acquire an electronic panel', (
    tester,
  ) async {
    final repo = _Repository()..value = const EcfSaleFiscal(saleId: 'sale');
    await pump(tester, repo, electronic: false);
    expect(find.text('Facturación electrónica'), findsNothing);
    expect(repo.sends, 0);
  });
  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'real sales history shows electronic and ordinary rows at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final repo = _Repository();
        final dio = Dio()..httpClientAdapter = _LocalHttp();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authStateProvider.overrideWith((ref) => _Auth(ref)),
              dioProvider.overrideWithValue(dio),
              companySettingsProvider.overrideWith(
                (ref) async => CompanySettings.empty(),
              ),
              ecfRepositoryProvider.overrideWithValue(repo),
              ventasRepositoryProvider.overrideWithValue(_HistorySales()),
            ],
            child: RepaintBoundary(
              key: capture,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light,
                home: const TpvSalesHistoryScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('E310000000001'), findsWidgets);
        expect(find.text('Cliente normal'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await export(tester, 'full-history-${width.toInt()}');
        if (width < 760) {
          await tester.tap(find.textContaining('E310000000001').first);
          await tester.pumpAndSettle();
          expect(find.text('Facturación electrónica'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await export(tester, 'full-history-detail-${width.toInt()}');
        }
      },
    );
  }
}
