import 'dart:io';

import 'package:daleventa_pos/core/models/product_model.dart';
import 'package:daleventa_pos/modules/cotizaciones/ai/application/quotation_ai_controller.dart';
import 'package:daleventa_pos/modules/cotizaciones/ai/data/repositories/business_rules_repository.dart';
import 'package:daleventa_pos/modules/cotizaciones/ai/domain/models/quotation_context.dart';
import 'package:daleventa_pos/modules/cotizaciones/ai/domain/services/quotation_ai_service.dart';
import 'package:daleventa_pos/modules/cotizaciones/cotizaciones_screen.dart';
import 'package:daleventa_pos/modules/manual_interno/company_manual_models.dart';
import 'package:daleventa_pos/modules/manual_interno/company_manual_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresión de rendimiento de Facturación (POS con tickets).
///
/// Root cause auditada: `build()` de `CotizacionesScreen` observaba
/// `quotationAiControllerProvider`, y ese provider notifica en CADA
/// `setContext` (cada edición del carrito, cada cambio/eliminación de ticket,
/// cada carga de catálogo, cada selección de cliente). Con el banner de IA
/// apagado (`_shouldShowAiBanner` siempre false) eso significaba reconstruir
/// TODO el POS por un estado que no se pinta en ninguna parte.
///
/// La corrección es observar solo lo que el banner necesita
/// (`select((state) => _shouldShowAiBanner(state) ? state : null)`), de modo
/// que con el banner apagado el provider no provoque ninguna reconstrucción.
void main() {
  QuotationContext contextWith({required int lineCount}) {
    return QuotationContext(
      quotationId: null,
      module: 'cotizaciones',
      productType: 'General',
      productName: 'Producto 1',
      brand: null,
      quantity: lineCount.toDouble(),
      installationType: null,
      selectedPriceType: null,
      selectedUnitPrice: 100.0,
      selectedTotal: 100.0 * lineCount,
      minimumPrice: null,
      offerPrice: null,
      normalPrice: 100.0 * lineCount,
      components: const ['Producto 1'],
      notes: null,
      extraCharges: const [],
      currentDvrType: null,
      requiredDvrType: null,
      screenName: 'Cotización',
      items: List<QuotationContextItem>.generate(
        lineCount,
        (index) => QuotationContextItem(
          productId: 'product-$index',
          productName: 'Producto $index',
          category: 'General',
          qty: 1,
          unitPrice: 100,
          officialUnitPrice: 100,
          lineTotal: 100,
        ),
      ),
      metadata: const {},
    );
  }

  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        quotationAiServiceProvider.overrideWithValue(_NoopQuotationAiService()),
        businessRulesRepositoryProvider.overrideWithValue(
          BusinessRulesRepository(_FakeManualRepository()),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('suscripción al estado de IA en Facturación', () {
    test(
      'setContext SIEMPRE notifica (por eso el watch terminal costaba caro)',
      () async {
        final container = buildContainer();
        final controller = container.read(
          quotationAiControllerProvider.notifier,
        );

        var notifications = 0;
        container.listen(quotationAiControllerProvider, (previous, next) {
          notifications++;
        });

        await controller.setContext(
          contextWith(lineCount: 1),
          triggerAi: false,
        );
        notifications = 0;
        await controller.setContext(
          contextWith(lineCount: 2),
          triggerAi: false,
        );

        // El estado se reasigna sin comparar: un `setContext` con contexto
        // distinto SIEMPRE emite al menos una notificación.
        expect(notifications, greaterThanOrEqualTo(1));
      },
    );

    test(
      'con el banner apagado, el select del POS no notifica en ningún setContext',
      () async {
        final container = buildContainer();
        final controller = container.read(
          quotationAiControllerProvider.notifier,
        );

        // Mismo gate que usa `build()` en cotizaciones_screen.dart: con el
        // banner apagado el `select` colapsa a `null` y no propaga cambios.
        var rebuilds = 0;
        container.listen(
          quotationAiControllerProvider.select(
            (state) => billingAiBannerEnabledForTest() ? state : null,
          ),
          (previous, next) => rebuilds++,
        );

        await controller.setContext(
          contextWith(lineCount: 1),
          triggerAi: false,
        );
        await controller.setContext(
          contextWith(lineCount: 2),
          triggerAi: false,
        );
        await controller.setContext(
          contextWith(lineCount: 3),
          triggerAi: false,
        );

        expect(rebuilds, 0);
      },
    );

    test(
      'con el banner activo, el select vuelve a notificar (sin regresión)',
      () async {
        final container = buildContainer();
        final controller = container.read(
          quotationAiControllerProvider.notifier,
        );

        // Simula el banner reactivado: el mismo `select` sí propaga el estado.
        var notifications = 0;
        container.listen(
          quotationAiControllerProvider.select(
            (state) => activeBillingAiBannerForTest() ? state : null,
          ),
          (previous, next) => notifications++,
        );

        await controller.setContext(
          contextWith(lineCount: 1),
          triggerAi: false,
        );
        await controller.setContext(
          contextWith(lineCount: 2),
          triggerAi: false,
        );

        expect(notifications, greaterThan(0));
      },
    );
  });

  group('indexProductsById (contexto IA sin O(líneas × catálogo))', () {
    test('indexa por id y resuelve el producto oficial de cada línea', () {
      final products = [_product('a'), _product('b'), _product('c')];

      final index = indexProductsById(products);

      expect(index.keys.toSet(), {'a', 'b', 'c'});
      expect(index['b']!.nombre, 'Producto b');
    });

    test('catálogo vacío devuelve un índice vacío reutilizable', () {
      final index = indexProductsById(const []);
      expect(index, isEmpty);
      expect(index['missing'], isNull);
    });

    test(
      'ids ausentes no rompen la resolución (línea sin producto oficial)',
      () {
        final index = indexProductsById([_product('a')]);
        expect(index['no-existe'], isNull);
      },
    );
  });

  group('wiring de rendimiento en cotizaciones_screen.dart', () {
    final source = File(
      'lib/modules/cotizaciones/cotizaciones_screen.dart',
    ).readAsStringSync();

    test('el POS ya no se suscribe al estado de IA en cada notificación', () {
      // La suscripción terminal pasa por el `select` gateado por el banner.
      expect(source, contains('quotationAiControllerProvider.select('));
      expect(source, contains('_shouldShowAiBanner(state) ? state : null'));

      // El `watch` directo (que reconstruía todo el POS) ya no existe.
      expect(
        source,
        isNot(
          contains('final aiState = ref.watch(quotationAiControllerProvider);'),
        ),
      );
    });

    test('el banner está apagado mediante un interruptor explícito', () {
      expect(source, contains('static const bool _aiBannerEnabled = false;'));
      expect(source, contains('return _aiBannerEnabled;'));
    });

    test('el análisis remoto de IA no se dispara con el banner apagado', () {
      expect(
        source,
        contains('final effectiveTriggerAi = triggerAi && _aiBannerEnabled;'),
      );
      expect(source, contains('triggerAi: effectiveTriggerAi'));
    });

    test(
      'el contexto de IA usa el índice del catálogo, no un escaneo lineal',
      () {
        expect(
          source,
          contains('final officialById = indexProductsById(_productos);'),
        );
        expect(
          source,
          contains('final official = officialById[item.productId];'),
        );
      },
    );
  });

  group('post-venta: la UI no espera a la impresión', () {
    final source = File(
      'lib/modules/cotizaciones/cotizaciones_screen.dart',
    ).readAsStringSync();

    test("'Venta guardada' se muestra ANTES de imprimir", () {
      final successNotice = source.indexOf("title: 'Venta guardada'");
      final printCall = source.indexOf('.printSaleTicket(');
      final uiStep = source.indexOf("trace?.step('ui_updated');");

      expect(successNotice, greaterThanOrEqualTo(0));
      expect(printCall, greaterThanOrEqualTo(0));
      expect(
        successNotice,
        lessThan(printCall),
        reason: 'El aviso de venta guardada debe preceder a la impresión.',
      );
      expect(
        uiStep,
        lessThan(printCall),
        reason:
            'Las invalidaciones/limpieza del ticket preceden a la impresión.',
      );
    });

    test('el gate de caja NO se repite dentro de _finalizeCotizacion', () {
      final finalizeStart = source.indexOf(
        'Future<void> _finalizeCotizacion({_CheckoutResult? checkout}) async {',
      );
      final finalizeEnd = source.indexOf(
        'Future<CashGateState?> _cashStateWithAuthorizationFallback() async {',
      );
      expect(finalizeStart, greaterThanOrEqualTo(0));
      expect(finalizeEnd, greaterThan(finalizeStart));

      final finalizeBody = source.substring(finalizeStart, finalizeEnd);
      expect(
        finalizeBody,
        isNot(contains('_cashStateWithAuthorizationFallback()')),
        reason:
            '_openCheckoutDialog ya ejecutó el gate; repetirlo costaba un GET '
            'extra por cobro.',
      );
    });

    test(
      'el gate de caja sigue existiendo antes de abrir el diálogo de cobro',
      () {
        expect(
          source,
          contains(
            'final cashState = await _cashStateWithAuthorizationFallback();',
          ),
        );
      },
    );
  });
}

ProductModel _product(String id) {
  return ProductModel(
    id: id,
    nombre: 'Producto $id',
    precio: 100,
    costo: 50,
    stock: 10,
    itemType: 'PRODUCT',
    trackInventory: true,
  );
}

/// Réplica del interruptor `_aiBannerEnabled` de `CotizacionesScreen`
/// (apagado). Se pasa por función para que el analizador no pliegue la
/// condición y marque la rama opuesta como código muerto.
bool billingAiBannerEnabledForTest() => false;

/// Igual que el anterior pero con el banner ACTIVO, para comprobar que el
/// `select` sigue notificando si el banner se reactiva.
bool activeBillingAiBannerForTest() => true;

class _NoopQuotationAiService implements QuotationAiService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Repositorio de manual interno en memoria: evita que el controlador de IA
/// toque SQLite durante el test (no hay `ServicesBinding` inicializado).
class _FakeManualRepository implements CompanyManualRepository {
  @override
  Future<List<CompanyManualEntry>> listEntries({
    CompanyManualEntryKind? kind,
    CompanyManualAudience? audience,
    String? moduleKey,
    bool includeHidden = false,
  }) async => const <CompanyManualEntry>[];

  @override
  Future<CompanyManualEntry> getEntryById(String id) async =>
      throw UnimplementedError('No usado en este test');

  @override
  Future<List<CompanyManualEntry>> getCachedEntries({
    CompanyManualEntryKind? kind,
    CompanyManualAudience? audience,
    String? moduleKey,
    bool includeHidden = false,
  }) async => const <CompanyManualEntry>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
