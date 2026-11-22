import 'package:daleventa_pos/core/widgets/mobile_action_icon.dart';
import 'package:daleventa_pos/core/widgets/mobile_presentation_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
  ]) {
    testWidgets('options icon and menu preserve platform scope: $platform', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const originalShape = RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            popupMenuTheme: const PopupMenuThemeData(shape: originalShape),
          ),
          home: MobilePresentationTheme(
            child: Scaffold(
              body: PopupMenuButton<String>(
                icon: const MobileActionIcon(Icons.more_vert_rounded),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Editar')),
                ],
              ),
            ),
          ),
        ),
      );
      final phone = platform != TargetPlatform.windows;
      expect(
        find.image(const AssetImage('assets/image/mobile_navigation/more.png')),
        phone ? findsOneWidget : findsNothing,
      );
      expect(
        find.byIcon(Icons.more_vert_rounded),
        phone ? findsNothing : findsOneWidget,
      );
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      final context = tester.element(find.text('Editar'));
      expect(
        Theme.of(context).popupMenuTheme.shape,
        phone ? const RoundedRectangleBorder() : originalShape,
      );
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant({platform}));
  }
}
