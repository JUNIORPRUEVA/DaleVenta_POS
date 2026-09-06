import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/core/widgets/responsive_shell.dart';

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

class _BuggyRefInDisposeWidgetState
    extends ConsumerState<_BuggyRefInDisposeWidget> {
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

class _ShellFooterHost extends ConsumerWidget {
  const _ShellFooterHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(desktopShellFooterContentProvider);
    return child;
  }
}

class _BuildPhaseShellFooterPublisher extends ConsumerWidget {
  const _BuildPhaseShellFooterPublisher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(desktopShellFooterContentProvider.notifier);
    setDesktopShellFooterContent(
      notifier,
      DesktopShellFooterContent(
        route: '/cotizaciones',
        ownerId: 'test-owner',
        signature: 'stable',
        builder: (_) => const Text('footer'),
      ),
    );
    return const SizedBox.shrink();
  }
}

class _DisposeBeforeShellFooterFrameWidget extends ConsumerStatefulWidget {
  const _DisposeBeforeShellFooterFrameWidget();

  @override
  ConsumerState<_DisposeBeforeShellFooterFrameWidget> createState() =>
      _DisposeBeforeShellFooterFrameWidgetState();
}

class _DisposeBeforeShellFooterFrameWidgetState
    extends ConsumerState<_DisposeBeforeShellFooterFrameWidget> {
  @override
  void initState() {
    super.initState();
    final notifier = ref.read(desktopShellFooterContentProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setDesktopShellFooterContent(
        notifier,
        DesktopShellFooterContent(
          route: '/cotizaciones',
          ownerId: 'disposed-owner',
          signature: 'pending',
          builder: (_) => const Text('disposed footer'),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Reproduce el contrato corregido de Cotizaciones: el provider fiscal se
/// escucha desde ciclo de vida y la escritura al footer del shell ocurre
/// post-frame, nunca como efecto síncrono de build.
class _FixedTaxDrivenShellFooterWidget extends ConsumerStatefulWidget {
  const _FixedTaxDrivenShellFooterWidget();

  @override
  ConsumerState<_FixedTaxDrivenShellFooterWidget> createState() =>
      _FixedTaxDrivenShellFooterWidgetState();
}

class _FixedTaxDrivenShellFooterWidgetState
    extends ConsumerState<_FixedTaxDrivenShellFooterWidget> {
  int? _value;
  bool _publishScheduled = false;
  late final StateController<DesktopShellFooterContent?> _footerNotifier;

  @override
  void initState() {
    super.initState();
    _footerNotifier = ref.read(desktopShellFooterContentProvider.notifier);
    _value = ref.read(_sampleProvider).valueOrNull;
    ref.listenManual<AsyncValue<int>>(_sampleProvider, (previous, next) {
      final value = next.valueOrNull;
      if (value == null || value == _value) return;
      setState(() => _value = value);
      _scheduleFooterPublish();
    });
  }

  void _scheduleFooterPublish() {
    if (_publishScheduled) return;
    _publishScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _publishScheduled = false;
      if (!mounted) return;
      setDesktopShellFooterContent(
        _footerNotifier,
        DesktopShellFooterContent(
          route: '/cotizaciones',
          builder: (_) => Text('tax:${_value ?? 0}'),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleFooterPublish();
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

  testWidgets('patrón corregido (campo cacheado) NO lanza al desmontar', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(child: const _FixedCachedRefWidget()),
    );
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());

    expect(tester.takeException(), isNull);
  });

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
      // La caché fiscal se refresca por listener, nunca por watch en build.
      expect(
        source,
        contains('ref.listenManual<AsyncValue<ProductTaxUiConfig>>'),
      );
      expect(
        source,
        isNot(
          contains('_taxConfigCache = ref.watch(productTaxUiConfigProvider'),
        ),
      );
      expect(source, contains('_isCurrentTenantGeneration('));
      expect(source, contains('_publishDesktopShellFooter(ownerCompanyId:'));
      expect(source, contains('ownerId: _desktopShellFooterOwnerId'));
      expect(source, contains('setDesktopShellFooterContent('));
      expect(source, contains('clearDesktopShellFooterContent('));
      expect(source, contains('ownerId: _desktopShellFooterOwnerId'));
      expect(source, contains('_desktopShellFooterNotifier'));
      expect(source, contains('_persistEditorDraftSnapshot('));
    },
  );

  test('regresión: contrato shell/footer no difiere WidgetRef capturado', () {
    final shellSource = File(
      'lib/core/widgets/responsive_shell.dart',
    ).readAsStringSync();

    expect(
      shellSource,
      matches(
        RegExp(
          r'void\s+setDesktopShellFooterContent\s*\(\s*'
          r'StateController<DesktopShellFooterContent\?>\s+notifier,',
          multiLine: true,
        ),
      ),
    );
    expect(
      shellSource,
      contains('required StateController<DesktopShellFooterContent?> notifier'),
    );
    expect(
      shellSource,
      isNot(contains('void setDesktopShellFooterContent(\n  WidgetRef ref,')),
    );
    expect(
      shellSource,
      isNot(contains('required WidgetRef ref,\n  required String ownerId')),
    );
    expect(
      shellSource,
      contains(
        'final notifier = ref.read(adminAuthorizationProvider.notifier)',
      ),
    );
  });

  testWidgets(
    'contrato central del shell difiere publicaciones hechas durante build',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: _ShellFooterHost(child: _BuildPhaseShellFooterPublisher()),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      await tester.pump();
      expect(find.text('footer'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'footer pendiente no usa WidgetRef despues de navegar y desmontar',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: _ShellFooterHost(
              child: _DisposeBeforeShellFooterFrameWidget(),
            ),
          ),
        ),
      );

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(home: Text('Historial de cotizaciones')),
        ),
      );
      await tester.pump();

      final exception = tester.takeException();
      expect(exception, isNull);
      expect(find.text('Historial de cotizaciones'), findsOneWidget);
    },
  );

  testWidgets(
    'provider fiscal y footer desktop no marcan el shell durante build',
    (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: _ShellFooterHost(child: _FixedTaxDrivenShellFooterWidget()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final exception = tester.takeException();
      expect(exception, isNull);
    },
  );
}
