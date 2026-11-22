import 'package:daleventa_pos/core/widgets/mobile_drawer_account_footer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'dart:io';
import 'dart:ui' as ui;

void main() {
  setUpAll(() async {
    final font = FontLoader('Manrope');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'));
    }
    await font.load();
  });
  testWidgets(
    'phone footer preserves callbacks and hides user management without permission',
    (tester) async {
      var profile = 0, users = 0, settings = 0, logout = 0;
      final capture = GlobalKey();
      for (final allowed in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomLeft,
                child: SizedBox(
                  width: 240,
                  child: RepaintBoundary(
                    key: capture,
                    child: MobileDrawerAccountFooter(
                      canManageUsers: allowed,
                      onProfile: () => profile++,
                      onUsers: () => users++,
                      onSettings: () => settings++,
                      onLogout: () => logout++,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final output = Platform.environment['FULLPOS_MOBILE_VISUAL_QA'];
        if (allowed && output != null) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          await tester.pumpAndSettle();
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(output).create(recursive: true);
            await File(
              '$output/drawer-footer-widget.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.text('Perfil'));
        await tester.tap(find.byTooltip('Configuración'));
        await tester.tap(find.byTooltip('Cerrar sesión'));
        expect(find.text('Usuario'), allowed ? findsOneWidget : findsNothing);
        if (allowed) {
          await tester.tap(find.text('Usuario'));
          expect(find.byTooltip('Administrar usuarios'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      }
      expect([profile, users, settings, logout], [2, 1, 2, 2]);
    },
  );
}
