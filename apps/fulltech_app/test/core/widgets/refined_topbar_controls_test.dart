import 'package:daleventa_pos/core/offline/offline_store.dart';
import 'package:daleventa_pos/core/offline/sync_queue_service.dart';
import 'package:daleventa_pos/core/offline/sync_status_menu_button.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/core/widgets/branded_menu_button.dart';
import 'package:daleventa_pos/core/widgets/preview/refined_topbar_preview.dart';
import 'package:daleventa_pos/core/widgets/refined_topbar_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _PreviewSyncQueue extends SyncQueueService {
  _PreviewSyncQueue() : super(OfflineStore.instance);

  void show(SyncQueueState value) => state = value;
}

void main() {
  setUpAll(() async {
    final font = FontLoader('Manrope');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'));
    }
    await font.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final width in [1280.0, 960.0, 900.0]) {
    testWidgets('AppBar alineado sin desbordamientos en $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: const RefinedTopbarPreview(),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          const AssetImage('assets/image/nuevologo.png'),
          tester.element(find.byType(RefinedTopbarPreview)),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight, 56);
      final turn = tester.getRect(find.byType(RefinedTurnChip));
      final sync = tester.getRect(find.byType(RefinedSyncIndicator));
      final company = tester.getRect(find.byType(RefinedCompanyLabel));
      expect(sync.size, const Size(40, 40));
      expect(sync.left - turn.right, 8);
      expect(company.left - sync.right, 8);
      expect(turn.center.dy, sync.center.dy);
      expect(company.center.dy, sync.center.dy);
      expect(find.byType(BrandedMenuButton), findsOneWidget);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(Scaffold),
        matchesGoldenFile('goldens/refined_topbar_${width.toInt()}.png'),
      );

      await tester.tap(find.text('Probar nombre largo'));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(RefinedCompanyLabel)).width,
        lessThanOrEqualTo(240),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Estado del turno'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mostrar turno cerrado'));
      await tester.pumpAndSettle();
      expect(find.text('Turno cerrado'), findsOneWidget);
    });
  }

  testWidgets(
    'el Sync real conserva pendientes, errores, procesamiento y menú',
    (tester) async {
      final queue = _PreviewSyncQueue();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [syncQueueServiceProvider.overrideWith((ref) => queue)],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: Center(child: SyncStatusMenuButton(iconOnly: true)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(RefinedSyncIndicator)),
        const Size(40, 40),
      );
      expect(find.text('Sync'), findsNothing);
      queue.show(const SyncQueueState(pendingCount: 3));
      await tester.pump();
      expect(find.text('3'), findsOneWidget);
      expect(
        find.byTooltip('Estado de sincronización: Pendiente'),
        findsOneWidget,
      );
      queue.show(const SyncQueueState(errorCount: 1));
      await tester.pump();
      expect(find.text('!'), findsOneWidget);
      expect(
        find.byTooltip('Estado de sincronización: Revisar'),
        findsOneWidget,
      );
      queue.show(const SyncQueueState(isProcessing: true));
      await tester.pump();
      final rotation = find.descendant(
        of: find.byType(RefinedSyncIndicator),
        matching: find.byType(RotationTransition),
      ).first;
      final before = tester.widget<RotationTransition>(rotation).turns.value;
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<RotationTransition>(rotation).turns.value,
        isNot(before),
      );
      queue.show(const SyncQueueState());
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SyncStatusMenuButton));
      await tester.pumpAndSettle();
      expect(find.text('Todo sincronizado'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('nombre largo y texto ampliado conservan todos los controles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: const RefinedTopbarPreview(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Probar nombre largo'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Cuenta y empresa'), findsOneWidget);
    expect(find.byTooltip('Estado del turno'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
