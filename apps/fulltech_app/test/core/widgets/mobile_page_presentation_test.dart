import 'package:daleventa_pos/core/widgets/mobile_action_icon.dart';
import 'package:daleventa_pos/core/widgets/mobile_page_app_bar.dart';
import 'package:daleventa_pos/core/widgets/mobile_presentation_theme.dart';
import 'package:daleventa_pos/core/widgets/fulltech_global_background.dart';
import 'package:daleventa_pos/core/auth/app_role.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'native phone background omits decorative role text',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        const MaterialApp(
          home: Stack(
            children: [FulltechGlobalBackground(role: AppRole.admin)],
          ),
        ),
      );
      final text = find.descendant(
        of: find.byType(FulltechGlobalBackground),
        matching: find.byType(Text),
      );
      expect(
        text,
        defaultTargetPlatform == TargetPlatform.windows
            ? findsWidgets
            : findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
    }),
  );
  testWidgets(
    'common icons and appbar remain native-only and preserve callbacks',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var back = 0, refresh = 0;
      final original = AppBar(
        title: const Text('Módulo'),
        leading: BackButton(onPressed: () => back++),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => refresh++,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MobilePresentationTheme(
            child: Scaffold(
              appBar: MobilePageAppBar(appBar: original),
              body: const Row(
                children: [
                  MobileActionIcon(Icons.search_rounded, size: 20),
                  MobileActionIcon(Icons.filter_alt_outlined, size: 20),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final native = defaultTargetPlatform != TargetPlatform.windows;
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      if (native) {
        expect(find.byType(BackButton), findsNothing);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Image &&
                widget.image is AssetImage &&
                (widget.image as AssetImage).assetName.endsWith('/back.png'),
          ),
          findsOneWidget,
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.decoration is BoxDecoration &&
                (widget.decoration as BoxDecoration).gradient ==
                    phoneAppBarGradient,
          ),
          findsOneWidget,
        );
        await tester.tap(find.byTooltip('Regresar'));
      } else {
        expect(identical(bar, original), isTrue);
        expect(find.byIcon(Icons.search_rounded), findsOneWidget);
        await tester.tap(find.byType(BackButton));
      }
      await tester.tap(find.byTooltip('Actualizar'));
      expect([back, refresh], [1, 1]);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
    }),
  );
}
