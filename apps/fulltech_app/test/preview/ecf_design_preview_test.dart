import 'dart:io';
import 'dart:ui' as ui;

import 'package:daleventa_pos/core/widgets/compact_square_switch.dart';
import 'package:daleventa_pos/features/account/account_menu_screens.dart';
import 'package:daleventa_pos/features/ecf/ui/flow/ecf_preparation_step.dart';
import 'package:daleventa_pos/features/ecf/ui/flow/ecf_welcome_step.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ecf_design_preview.dart';
import 'ecf_design_gallery.dart';

final _capture = GlobalKey();

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(key: _capture, child: const EcfDesignPreview()),
  );
  await tester.pumpAndSettle();
}

Finder _moduleSwitch() => find.byKey(
  const ValueKey(
    'company_setting_switch_Activar módulo de facturación electrónica',
  ),
);

Future<void> _screenshot(WidgetTester tester, String name) async {
  final output = Platform.environment['FULLPOS_DESIGN_QA_OUTPUT'];
  if (output == null) return;
  final boundary =
      _capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final picture = await boundary.toImage();
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    await Directory(output).create(recursive: true);
    await File('$output/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    dotenv.testLoad(fileInput: 'APP_ENV=uat\nAPI_BASE_URL=http://127.0.0.1:9');
    final fonts = FontLoader('Manrope');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts.addFont(
        rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'),
      );
    }
    await fonts.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final width in [390.0, 1280.0]) {
    testWidgets('galería completa con datos locales a $width', (tester) async {
      await _pump(tester, Size(width, 1000));
      await tester.tap(find.text('4–19. Otras pantallas'));
      await tester.pumpAndSettle();
      expect(find.byType(EcfDesignGallery), findsOneWidget);
      for (final scene in FiscalPreviewScene.values) {
        final selector = tester.widget<DropdownButton<FiscalPreviewScene>>(
          find.byKey(const ValueKey('fiscal_gallery_scene')),
        );
        expect(selector.value, scene);
        await _screenshot(
          tester,
          'galeria-${scene.index + 4}-${width.toInt()}',
        );
        expect(tester.takeException(), isNull, reason: scene.label);
        if (scene != FiscalPreviewScene.values.last) {
          await tester.tap(find.byTooltip('Pantalla siguiente'));
          await tester.pumpAndSettle();
        }
      }
    });
  }

  testWidgets('configuración19 cabe en escritorio compacto con su acción E34 visible', (tester) async {
    await _pump(tester, const Size(1280, 760));
    await tester.tap(find.text('4–19. Otras pantallas'));
    await tester.pumpAndSettle();
    for (var index = 0; index < FiscalPreviewScene.values.length - 1; index++) {
      await tester.tap(find.byTooltip('Pantalla siguiente'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Nota de crédito').hitTestable(), findsOneWidget);
    expect(find.text('Rangos de numeración').hitTestable(), findsOneWidget);
    await _screenshot(tester, 'configuracion19-escritorio-compacto');
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('preview real navegable y sin desbordamiento a $width', (
      tester,
    ) async {
      await _pump(tester, Size(width, 900));
      expect(find.byType(AccountCompanySettingsScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('company_logo_upload')).hitTestable(),
        findsOneWidget,
      );
      await tester.ensureVisible(_moduleSwitch());
      await tester.pumpAndSettle();
      await _screenshot(tester, 'empresa-${width.toInt()}');
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('2. Entrada al módulo'));
      await tester.pumpAndSettle();
      expect(find.byType(EcfWelcomeStep), findsOneWidget);
      await _screenshot(tester, 'entrada-${width.toInt()}');
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Comenzar'));
      await tester.tap(find.text('Comenzar'));
      await tester.pumpAndSettle();
      expect(find.byType(EcfPreparationStep), findsOneWidget);
      await _screenshot(tester, 'preparacion-${width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('preparación tiene acceso directo y vuelve a la bienvenida', (
    tester,
  ) async {
    await _pump(tester, const Size(1280, 800));
    await tester.tap(find.text('3. Preparación'));
    await tester.pumpAndSettle();
    expect(find.byType(EcfPreparationStep), findsOneWidget);
    expect(find.text('Postulación electrónica'), findsOneWidget);
    expect(find.textContaining('DOSA'), findsNothing);
    expect(find.textContaining('Pago único de US\$150'), findsOneWidget);
    expect(find.text('Consultar por WhatsApp').hitTestable(), findsOneWidget);
    expect(find.text('Iniciar postulación').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Iniciar postulación'));
    await tester.pumpAndSettle();
    expect(
      find.text('No se pudo registrar la intención de certificación.'),
      findsOneWidget,
    );
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(EcfWelcomeStep), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bienvenida compacta mantiene texto y acción visibles', (
    tester,
  ) async {
    await _pump(tester, const Size(1280, 760));
    await tester.tap(find.text('2. Entrada al módulo'));
    await tester.pumpAndSettle();
    expect(find.text('Comenzar').hitTestable(), findsOneWidget);
    expect(find.text('Abrir portal de la DGII').hitTestable(), findsOneWidget);
    expect(find.text('Vídeo no disponible'), findsNothing);
    await _screenshot(tester, 'entrada-escritorio-compacta');
    expect(tester.takeException(), isNull);
  });

  testWidgets('notifica al shell tras dibujar la vista, una sola vez', (
    tester,
  ) async {
    var completions = 0;
    await tester.pumpWidget(
      EcfDesignPreview(
        onStartupComplete: () {
          expect(find.text('Vista previa · datos ficticios'), findsOneWidget);
          completions++;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(completions, 1);
    await tester.tap(find.text('2. Entrada al módulo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reiniciar vista'));
    await tester.pumpAndSettle();
    expect(completions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'solo seis datos visibles y Ver más conserva lo editado al ocultarlo',
    (tester) async {
      await _pump(tester, const Size(1280, 900));
      expect(find.byType(TextField), findsNWidgets(6));
      expect(find.text('RNC (opcional)'), findsOneWidget);
      expect(find.text('Representante legal · opcional'), findsOneWidget);
      expect(find.text('Activación de módulos'), findsOneWidget);
      final disclosure = find.byKey(const ValueKey('company_more_details'));
      final name = find.byKey(const ValueKey('company_field_Nombre comercial'));
      expect(
        tester.getTopLeft(disclosure).dy,
        lessThan(tester.getTopLeft(name).dy),
      );
      final email = find.byKey(
        const ValueKey('company_field_Correo de facturación electrónica'),
      );
      expect(email, findsNothing);
      await tester.tap(disclosure);
      await tester.pumpAndSettle();
      await tester.ensureVisible(email);
      await tester.enterText(email, 'revision@example.test');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(disclosure);
      await tester.pumpAndSettle();
      await tester.tap(disclosure);
      await tester.pumpAndSettle();
      expect(email, findsNothing);
      await tester.tap(disclosure);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(email).controller!.text,
        'revision@example.test',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('la configuración de escritorio cabe sin desplazar la pantalla', (
    tester,
  ) async {
    await _pump(tester, const Size(1264, 681));
    final save = find.text('Guardar empresa');
    expect(save.hitTestable(), findsOneWidget);
    expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(681));
    expect(
      find.byKey(const ValueKey('company_more_details')).hitTestable(),
      findsOneWidget,
    );
    await _screenshot(tester, 'empresa-escritorio-compacta');
    expect(tester.takeException(), isNull);
  });

  for (final device in ['Android · 390', 'iPhone · 390']) {
    testWidgets(
      'preview en $device conserva los datos principales a la vista',
      (tester) async {
        await _pump(tester, const Size(1280, 960));
        await tester.tap(
          find.byWidgetPredicate((widget) => widget is DropdownButton).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(device).last);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('company_more_details')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find
              .byKey(const ValueKey('company_field_Nombre comercial'))
              .hitTestable(),
          findsOneWidget,
        );
        expect(find.text('Guardar empresa').hitTestable(), findsOneWidget);
        expect(find.text('Empresa'), findsOneWidget);
        expect(find.byTooltip('Sincronizar'), findsOneWidget);
        expect(find.byType(OutlinedButton), findsNothing);
        await _screenshot(
          tester,
          device.startsWith('Android') ? 'empresa-android' : 'empresa-iphone',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'los cambios son de la demo y reiniciar recupera su estado inicial',
    (tester) async {
      await _pump(tester, const Size(1280, 900));
      await tester.ensureVisible(_moduleSwitch());
      await tester.pumpAndSettle();
      await tester.tap(_moduleSwitch());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Desactivar'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CompactSquareSwitch>(_moduleSwitch()).value,
        isFalse,
      );
      expect(find.text('Vender sin comprobante'), findsNothing);

      await tester.tap(find.text('Reiniciar vista'));
      await tester.pumpAndSettle();
      expect(tester.widget<CompactSquareSwitch>(_moduleSwitch()).value, isTrue);
      expect(find.text('Vender sin comprobante'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
