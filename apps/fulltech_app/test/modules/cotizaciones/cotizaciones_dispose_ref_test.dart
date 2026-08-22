import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Proveedor trivial que simula `productTaxUiConfigProvider` (FutureProvider).
final _sampleProvider = FutureProvider<int>((ref) async => 42);

/// Widget que reproduce el patrón PELIGROSO original: un getter lee `ref`
/// (equivale a `_currentTaxConfig` → `ref.read(productTaxUiConfigProvider)`
/// en cotizaciones_screen.dart:1196) y `dispose()` lo invoca.
///
/// En flutter_riverpod, `Element.unmount()` marca el context como no mounted
/// ANTES de llamar a `state.dispose()`, por lo que leer `ref` en `dispose()`
/// lanza exactamente: StateError "Cannot use ref after the widget was disposed."
class _BuggyRefInDisposeWidget extends ConsumerStatefulWidget {
  const _BuggyRefInDisposeWidget();

  @override
  ConsumerState<_BuggyRefInDisposeWidget> createState() =>
      _BuggyRefInDisposeWidgetState();
}

class _BuggyRefInDisposeWidgetState extends ConsumerState<
    _BuggyRefInDisposeWidget> {
  int get _value => ref.read(_sampleProvider).valueOrNull ?? 0;

  @override
  void dispose() {
    // Leer el getter aquí dispara el StateError (bug real reportado).
    final _ = _value;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Widget con el PATRÓN CORREGIDO: el getter lee un campo cacheado (nunca
/// `ref`), refrescado en `initState` (ref.read) y en `build` (ref.watch).
/// Así `dispose()` y cualquier callback póstumo no tocan `ref`.
class _FixedCachedRefWidget extends ConsumerStatefulWidget {
  const _FixedCachedRefWidget();

  @override
  ConsumerState<_FixedCachedRefWidget> createState() =>
      _FixedCachedRefWidgetState();
}

class _FixedCachedRefWidgetState extends ConsumerState<_FixedCachedRefWidget> {
  int? _cache;

  @override
  void initState() {
    super.initState();
    _cache = ref.read(_sampleProvider).valueOrNull;
  }

  int get _value => _cache ?? 0;

  @override
  void dispose() {
    final _ = _value; // lee el campo, NO `ref` → seguro
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _cache = ref.watch(_sampleProvider).valueOrNull;
    return const SizedBox.shrink();
  }
}

/// Simula el debounce de realtime: un tick programa un Timer de 350 ms que
/// toca `ref`; `dispose()` cancela el timer (patrón correcto). Verifica que
/// desmontar antes de que el timer dispare NO lanza ninguna excepción.
class _DebounceWidget extends ConsumerStatefulWidget {
  const _DebounceWidget();

  @override
  ConsumerState<_DebounceWidget> createState() => _DebounceWidgetState();
}

class _DebounceWidgetState extends ConsumerState<_DebounceWidget> {
  Timer? _timer;

  void _onTick(int value) {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 350), () {
      if (mounted) {
        ref.read(_sampleProvider);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(_sampleProvider, (previous, AsyncValue<int> next) {
      final value = next.valueOrNull;
      if (value != null) _onTick(value);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(_sampleProvider);
    return const SizedBox.shrink();
  }
}

void main() {
  testWidgets(
    'leer `ref` en dispose lanza StateError (mecanismo del bug reportado)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(child: const _BuggyRefInDisposeWidget()),
      );
      await tester.pump();

      // Desmontar → dispose → getter lee ref → StateError.
      await tester.pumpWidget(const SizedBox.shrink());

      final exception = tester.takeException();
      expect(exception, isA<StateError>());
      expect(
        exception.toString(),
        contains('Cannot use "ref" after the widget was disposed'),
      );
    },
  );

  testWidgets(
    'patrón corregido (campo cacheado) NO lanza al desmontar',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(child: const _FixedCachedRefWidget()),
      );
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'desmontar antes de que el timer de debounce realtime dispare NO lanza',
    (tester) async {
      await tester.pumpWidget(ProviderScope(child: const _DebounceWidget()));
      // Espera a que el FutureProvider resuelva y dispare el listener (tick).
      await tester.pump(const Duration(milliseconds: 50));

      // Desmonta antes de que venza el timer de 350 ms.
      await tester.pumpWidget(const SizedBox.shrink());

      // Avanza más allá del timer: si no se canceló en dispose, dispararía y
      // tocaría ref con el widget desmontado.
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
    },
  );

  test(
    'regresión: _currentTaxConfig ya no lee ref en cotizaciones_screen.dart',
    () {
      final source = File(
        'lib/modules/cotizaciones/cotizaciones_screen.dart',
      ).readAsStringSync();

      // El getter fiscal debe leer la caché, nunca `ref`.
      final getterLine = source
          .split('\n')
          .firstWhere(
            (line) => line.contains('get _currentTaxConfig'),
            orElse: () => '',
          );
      expect(getterLine, contains('_taxConfigCache'));
      expect(getterLine, isNot(contains('ref.read')));
      // La caché se refresca en initState y en build.
      expect(source, contains('_taxConfigCache = ref.watch('));
    },
  );
}
