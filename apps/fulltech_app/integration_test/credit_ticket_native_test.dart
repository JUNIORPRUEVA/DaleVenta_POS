import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/printing/models/company_info.dart';
import 'package:daleventa_pos/core/printing/unified_ticket_printer.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/core/utils/app_feedback.dart';
import 'package:daleventa_pos/core/widgets/pdf_preview_panel.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_model.dart';
import 'package:daleventa_pos/features/settings/data/printer_settings_repository.dart';
import 'package:daleventa_pos/features/warehouses/data/warehouse_repository.dart';
import 'package:daleventa_pos/modules/cash/cash_providers.dart';
import 'package:daleventa_pos/modules/ventas/data/ventas_repository.dart';
import 'package:daleventa_pos/modules/ventas/sales_credit_screen.dart';
import 'package:daleventa_pos/modules/ventas/sales_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Storage extends TokenStorage {
  _Storage(this.user);
  final UserModel user;
  @override
  Future<UserModel?> getUserSnapshot() async => user;
}

class _Auth extends AuthController {
  _Auth(super.ref, UserModel user) {
    state = AuthState(initialized: true, isAuthenticated: true, user: user);
  }
}

class _Cash extends ActiveCashSessionController {
  _Cash(super.ref);
  @override
  Future<void> refresh({bool silent = false}) async {
    state = const AsyncData(null);
  }
}

class _Company implements CompanyInfoRepository {
  @override
  Future<CompanyInfo> getCurrentCompanyInfo() async =>
      const CompanyInfo(name: 'FULLPOS PRUEBA DE CREDITO', address: 'SIN VALIDEZ FISCAL');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Printer implements PrinterSettingsRepository {
  @override
  Future<PrinterSettingsModel> getOrCreate() async =>
      const PrinterSettingsModel(
        showLogo: false,
        selectedPrinterName: String.fromEnvironment('CREDIT_PHYSICAL_PRINTER'),
        footerMessage: 'PRUEBA LOCAL - SIN VALIDEZ FISCAL',
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real Windows credit collection, settlement and original ticket PDF',
    (tester) async {
      expect(Platform.isWindows, isTrue);
      await initializeDateFormatting('es_DO');
      final directory = Directory(
        const String.fromEnvironment('CREDIT_TICKET_LAB_DIR'),
      );
      const physicalPrinter = String.fromEnvironment('CREDIT_PHYSICAL_PRINTER');
      final printSubmissions = <Map<String, dynamic>>[];
      final fixture =
          jsonDecode(
                await File(
                  '${directory.path}/native-fixture.json',
                ).readAsString(),
              )
              as Map;
      expect(fixture['base'], 'http://127.0.0.1:14627');
      SharedPreferences.setMockInitialValues({});
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final previous = await getDatabasesPath();
      final dbPath = '${directory.path}/native-local-data';
      await Directory(dbPath).create(recursive: true);
      await databaseFactory.setDatabasesPath(dbPath);
      final user = UserModel.fromJson(
        Map<String, dynamic>.from(fixture['user'] as Map),
      );
      final storage = _Storage(user);
      final dio = Dio(
        BaseOptions(
          baseUrl: fixture['base'] as String,
          headers: {'authorization': 'Bearer ${fixture['token']}'},
        ),
      );
      final queue = SyncQueueService(
        OfflineStore.instance,
        scopeResolver: () async =>
            OfflineSyncScope(companyId: user.companyId, userId: user.id),
      );
      final repo = VentasRepository(
        dio,
        queue,
        WarehouseRepository(dio),
        tokenStorage: storage,
        originCashSessionIdResolver: () async => fixture['sessionId'] as String,
      );
      var posts = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.method == 'POST' &&
                options.path.contains('credit-payments')) {
              posts++;
            }
            handler.next(options);
          },
        ),
      );
      final initial = await repo.getById(fixture['saleId'] as String);
      expect(initial.creditPaidAmount, 1000);
      expect(initial.creditBalance, 1500);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authStateProvider.overrideWith((ref) => _Auth(ref, user)),
            tokenStorageProvider.overrideWithValue(storage),
            dioProvider.overrideWithValue(dio),
            ventasRepositoryProvider.overrideWithValue(repo),
            companySettingsProvider.overrideWith(
              (ref) async => CompanySettings.empty(),
            ),
            activeCashSessionControllerProvider.overrideWith(
              (ref) => _Cash(ref),
            ),
            companyInfoRepositoryProvider.overrideWithValue(_Company()),
            printerSettingsRepositoryProvider.overrideWithValue(_Printer()),
          ],
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
              theme: AppTheme.light,
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              supportedLocales: const [Locale('es', 'DO')],
              home: const SalesCreditScreen(),
            ),
          ),
        ),
      );
      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 150 && finder.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(finder, findsWidgets);
        expect(tester.takeException(), isNull);
      }

      Future<void> capture(String name) async {
        await tester.pump(const Duration(milliseconds: 300));
        final image =
            await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${directory.path}/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
      }

      await waitFor(find.text('Cliente de credito'));
      // Native acceptance has its own synthetic company and original invoice.
      final rows = await repo.listCredits(includePaid: true);
      final target = rows.indexWhere((sale) => sale.id == initial.id);
      expect(target, greaterThanOrEqualTo(0));
      await tester.pump(const Duration(milliseconds: 400));
      await capture('windows-credit-before');
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(SalesCreditScreen)),
      );
      Future<void> printPhysical(SaleModel sale, String stage) async {
        if (physicalPrinter.isEmpty) return;
        await tester.runAsync(() async {
          final printer = scope.read(unifiedTicketPrinterProvider);
          final pdf = await printer.buildSaleTicketPdf(sale: sale);
          await File('${directory.path}/physical-$stage.pdf').writeAsBytes(pdf);
          // Same production print service and renderer; one copy, never a drawer pulse.
          final result = await printer.reprintSale(sale: sale, copies: 1);
          printSubmissions.add({
            'stage': stage, 'printer': physicalPrinter, 'saleId': sale.id,
            'paid': sale.creditPaidAmount, 'balance': sale.creditBalance,
            'submitted': result.success, 'message': result.message,
            'paperOutputVerified': false,
          });
          await File('${directory.path}/physical-print-submissions.json')
              .writeAsString(jsonEncode(printSubmissions));
          expect(result.success, isTrue, reason: result.message);
        });
      }
      await printPhysical(initial, 'initial');
      final abonar = find.text('Registrar abono');
      await waitFor(abonar);
      await tester.tap(abonar.first);
      final cashInput = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Efectivo',
      );
      await waitFor(cashInput);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(cashInput, '500');
      await tester.tap(find.text('Guardar').last);
      await waitFor(find.textContaining('PDF factura'));
      await waitFor(
        find.byWidgetPredicate(
          (widget) =>
              widget is PdfPanelActionButton &&
              widget.label == 'Guardar factura',
        ),
      );
      final renderedPage = find.descendant(
        of: find.byType(PdfPreviewStage),
        matching: find.byWidgetPredicate(
          (widget) => widget is RawImage && (widget.image?.height ?? 0) > 300,
        ),
      );
      await waitFor(renderedPage);
      await capture('windows-credit-ticket');
      var confirmed = await repo.getById(initial.id);
      expect(confirmed.creditPaidAmount, 1500);
      expect(confirmed.creditBalance, 1000);
      expect(posts, 1);
      final bytes = await scope
          .read(unifiedTicketPrinterProvider)
          .buildSaleInvoicePdf(sale: confirmed);
      await File(
        '${directory.path}/windows-real-invoice.pdf',
      ).writeAsBytes(bytes);
      // Close the actual preview via its close button, then settle in the
      // existing payment dialog. Printing is opt-in through CREDIT_PHYSICAL_PRINTER.
      Future<void> closePreview() async {
        await tester.tap(
          find.descendant(
            of: find.byType(PdfPreviewPanelHeader),
            matching: find.byType(IconButton),
          ),
        );
        for (
          var i = 0;
          i < 30 && find.byType(PdfPreviewPanelHeader).evaluate().isNotEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(PdfPreviewPanelHeader), findsNothing);
      }

      await closePreview();
      await printPhysical(confirmed, 'partial');
      if (find.text('Saldar').evaluate().isEmpty) {
        await tester.tap(find.byTooltip('Más acciones').last);
        await tester.pump(const Duration(milliseconds: 300));
      }
      await waitFor(find.text('Saldar'));
      await tester.tap(find.text('Saldar').first);
      await waitFor(find.text('Saldar crédito'));
      await tester.tap(find.text('Saldar').last);
      await waitFor(find.textContaining('PDF factura'));
      await waitFor(renderedPage);
      confirmed = await repo.getById(initial.id);
      expect(confirmed.creditBalance, 0);
      expect(confirmed.creditPaidAmount, 2500);
      expect(posts, 2);
      expect(confirmed.id, initial.id);
      expect(confirmed.totalSold, initial.totalSold);
      await capture('windows-credit-settled');
      await closePreview();
      await printPhysical(confirmed, 'settled');
      await File('${directory.path}/native-result.json').writeAsString(
        jsonEncode({
          'result': 'PASS',
          'saleId': initial.id,
          'posts': posts,
          'paid': confirmed.creditPaidAmount,
          'balance': confirmed.creditBalance,
          'physicalPrintJobsSubmitted': printSubmissions.length,
          'paperOutputVerified': false,
        }),
      );
      AppFeedback.clearToasts();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
      queue.dispose();
      dio.close(force: true);
      await OfflineStore.instance.closeForTesting();
      await databaseFactory.setDatabasesPath(previous);
    },
  );
}
