import 'package:daleventa_pos/core/widgets/mobile_drawer_account_footer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'phone footer preserves callbacks and hides user management without permission',
    (tester) async {
      var profile = 0, users = 0, settings = 0, logout = 0;
      for (final allowed in [true, false]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomLeft,
                child: SizedBox(
                  width: 240,
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
        );
        await tester.tap(find.text('Perfil'));
        await tester.tap(find.byTooltip('Configuración'));
        await tester.tap(find.byTooltip('Cerrar sesión'));
        expect(find.text('Usuario'), allowed ? findsOneWidget : findsNothing);
        if (allowed) {
          await tester.tap(find.text('Usuario'));
          await tester.tap(find.byTooltip('Administrar usuarios'));
        }
        expect(tester.takeException(), isNull);
      }
      expect([profile, users, settings, logout], [2, 2, 2, 2]);
    },
  );
}
