import 'package:daleventa_pos/core/widgets/custom_app_bar.dart';
import 'package:daleventa_pos/features/user/users_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../preview/mobile_refinement_preview.dart';

Future<void> pumpUsers(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  dotenv.testLoad(fileInput: 'APP_ENV=uat\nAPI_BASE_URL=http://127.0.0.1:9');
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: mobilePreviewOverrides(),
      child: const MobileRefinementPreview(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'native user header is concise; Windows narrow window keeps its controls',
    (tester) async {
      await pumpUsers(tester);
      final bar = tester.widget<CustomAppBar>(find.byType(CustomAppBar));
      final phone = defaultTargetPlatform != TargetPlatform.windows;
      expect(bar.title, phone ? 'Usuario' : 'Usuarios y permisos');
      expect(bar.showDepartmentLabel, !phone);
      if (phone) {
        expect(bar.trailing, isNull);
        expect(bar.actions, hasLength(2));
        expect(find.byTooltip('PIN de administrador'), findsOneWidget);
        expect(find.byTooltip('Buscar'), findsNothing);
      } else {
        expect(bar.trailing, isNotNull);
        expect(find.byTooltip('Buscar'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.windows,
    }),
  );

  testWidgets(
    'mobile Permissions opens the chosen user editor directly',
    (tester) async {
      await pumpUsers(tester);
      await tester.tap(find.byTooltip('Acciones').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Permisos').last);
      await tester.pumpAndSettle();
      final editor = tester.widget<UserPermissionsScreen>(
        find.byType(UserPermissionsScreen),
      );
      expect(editor.userId, previewCashier.id);
      expect(editor.embedded, isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'mobile creation dialog is square and can cancel without creating user',
    (tester) async {
      await pumpUsers(tester);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.text('Nuevo usuario'), findsOneWidget);
      final create = find.widgetWithText(FilledButton, 'Crear usuario');
      final shape =
          tester.widget<FilledButton>(create).style!.shape!.resolve({})!
              as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.zero);
      await tester.enterText(find.byType(TextField).first, 'Usuario de prueba');
      await tester.tap(find.text('Cancelar'));
      await tester.pump(const Duration(milliseconds: 30));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Configuración').first);
      await tester.pumpAndSettle();
      expect(find.text('Nuevo usuario'), findsNothing);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}
