import '../../support/platform_goldens.dart';

import 'dart:convert';
import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:daleventa_pos/core/ai_assistant/application/ai_assistant_controller.dart';
import 'package:daleventa_pos/core/ai_assistant/data/datasources/ai_assistant_datasource.dart';
import 'package:daleventa_pos/core/ai_assistant/data/voice_note_recorder.dart';
import 'package:daleventa_pos/core/ai_assistant/domain/models/ai_chat_context.dart';
import 'package:daleventa_pos/core/ai_assistant/domain/services/ai_assistant_service.dart';
import 'package:daleventa_pos/core/ai_assistant/presentation/widgets/ai_assistant_sheet.dart';
import 'package:daleventa_pos/core/ai_assistant/presentation/widgets/ai_chat_panel_host.dart';
import 'package:daleventa_pos/core/ai_assistant/presentation/widgets/ai_chat_experience.dart';
import 'package:daleventa_pos/core/ai_assistant/presentation/widgets/ai_assistant_dock_button.dart';
import 'package:daleventa_pos/core/ai_assistant/presentation/widgets/global_ai_assistant_entry_point.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// El compositor del asistente debe ofrecer las cuatro formas de enviar algo:
/// texto, adjuntar (imagen, vídeo o documento) y nota de voz grabada.
void main() {
  late _FakeRecorder recorder;

  setUpAll(() async {
    final loader = FontLoader('Manrope');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(
        rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'),
      );
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  setUp(() => recorder = _FakeRecorder());

  Future<void> pumpSheet(
    WidgetTester tester, {
    _FakeDataSource? datasource,
  }) async {
    final controller = AiAssistantController(
      AiAssistantService(datasource ?? _FakeDataSource()),
    );
    controller.setContext(const AiChatContext(module: 'catalogo'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiAssistantControllerProvider.overrideWith((ref) => controller),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: Scaffold(body: GlobalAiChatSheet(recorder: recorder)),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await precacheImage(const AssetImage(AiAssistantDockButton.imageAsset),
        tester.element(find.byType(GlobalAiChatSheet)));
    });
    await tester.pump();
  }

  testWidgets('ofrece texto, adjuntar archivo y nota de voz', (tester) async {
    await pumpSheet(tester);

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
    expect(
      find.bySemanticsLabel('Adjuntar imagen o documento'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Grabar nota de voz'), findsOneWidget);
    expect(find.text('Escribe tu pregunta…'), findsOneWidget);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('el chat llena el área útil en $platform', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
      addTearDown(tester.view.reset);
      await pumpSheet(tester);
      final rect = tester.getRect(find.byType(AiChatPanelHost));
      expect(rect.top, closeTo(24, 1));
      expect(rect.bottom, closeTo(820, 1));
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant({platform}));
  }

  testWidgets('solo ofrece avería y presenta una bienvenida breve', (tester) async {
    await pumpSheet(tester);
    expect(find.text('Reportar una avería'), findsOneWidget);
    expect(find.text('Soporte humano'), findsNothing);
    expect(find.text('Explícame esta pantalla'), findsNothing);
    expect(find.text('Qué puedo hacer aquí'), findsNothing);
    expect(find.text('Normas del manual'), findsNothing);
    expect(find.byType(AiChatWelcome), findsOneWidget);
    expect(find.text('Habla con nuestro equipo'), findsNothing);
    expect(find.text('Contactar por WhatsApp'), findsNothing);
  });

  testWidgets('muestra escritura mientras espera y la retira al recibir respuesta', (tester) async {
    final source = _FakeDataSource()..pending = Completer<Map<String, dynamic>>();
    await tester.pumpWidget(ProviderScope(overrides: [
      aiAssistantDataSourceProvider.overrideWithValue(source),
      aiAssistantServiceProvider.overrideWith((ref) => AiAssistantService(source)),
    ], child: MaterialApp(theme: AppTheme.light,
      home: Scaffold(body: GlobalAiChatSheet(recorder: recorder)))));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Quiero hablar con una persona');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AiTypingBubble), findsOneWidget);
    expect(find.text('Contactar por WhatsApp'), findsNothing);
    source.pending!.complete({'content':'Puedo orientarte para contactar al equipo.', 'denied':false, 'citations':[]});
    await tester.pumpAndSettle();
    expect(find.byType(AiTypingBubble), findsNothing);
    expect(find.byType(AiChatWelcome), findsNothing);
    expect(find.text('Puedo orientarte para contactar al equipo.'), findsOneWidget);
  });

  testWidgets('solicita atención humana por chat sin abrir un canal externo', (tester) async {
    final source = _FakeDataSource();
    await tester.pumpWidget(ProviderScope(overrides: [
      aiAssistantDataSourceProvider.overrideWithValue(source),
      aiAssistantServiceProvider.overrideWith((ref) => AiAssistantService(source)),
    ], child: MaterialApp(theme: AppTheme.light,
      home: Scaffold(body: GlobalAiChatSheet(recorder: recorder)))));
    await tester.pump();
    expect(find.text('Contactar por WhatsApp'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Quiero hablar con soporte humano');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();
    expect(find.text('Quiero hablar con soporte humano'), findsOneWidget);
    expect(find.text('Contactar por WhatsApp'), findsNothing);
    expect(find.text('Habla con nuestro equipo'), findsNothing);
  });

  testWidgets('el formulario de avería permanece dentro de la columna de IA', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpSheet(tester);
    await tester.tap(find.text('Reportar una avería'));
    await tester.pumpAndSettle();
    final panel = tester.getRect(find.byType(AiChatPanelHost));
    final form = tester.getRect(find.byType(AlertDialog));
    expect(panel.width, lessThan(500));
    expect(form.left, greaterThanOrEqualTo(panel.left));
    expect(form.top, greaterThanOrEqualTo(panel.top));
    expect(form.right, lessThanOrEqualTo(panel.right));
    expect(form.bottom, lessThanOrEqualTo(panel.bottom));
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byTooltip('Cerrar asistente'), findsOneWidget);
  });

  testWidgets('el botón accesible ocupa sólo el botón y ejecuta su acción', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const Positioned.fill(child: Text('Pantalla de trabajo')),
              Positioned(
                right: 14,
                top: 100,
                child: AiAssistantDockButton(
                  compact: true,
                  onPressed: () => taps++,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final node = tester.getSemantics(find.byType(AiAssistantDockButton));
    expect(node.rect.size, const Size(60, 60));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    await tester.tap(find.byType(AiAssistantDockButton));
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('la avería requiere descripción útil y confirmación', (
    tester,
  ) async {
    await pumpSheet(tester);
    await tester.tap(find.text('Reportar una avería'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar avería'));
    await tester.pump();
    expect(
      find.text('Describe el problema con un poco más de detalle.'),
      findsOneWidget,
    );
    await tester.enterText(
      find.byType(TextFormField),
      'La factura se queda cargando al cobrar en efectivo',
    );
    await tester.tap(find.text('Registrar avería'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Quiero reportar una avería: La factura se queda cargando al cobrar en efectivo',
      ),
      findsOneWidget,
    );
  });

  testWidgets('envía el texto desde el compositor integrado', (tester) async {
    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), 'Cómo usar esta pantalla');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Cómo usar esta pantalla'), findsOneWidget);
    expect(find.text('respuesta de prueba'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets('oculta las fuentes visuales conservando las citas recibidas', (
    tester,
  ) async {
    final datasource = _FakeDataSource();
    datasource.citations.add({
      'id': 'guia-1',
      'title': 'Guía interna de prueba',
      'module': 'catalogo',
      'category': 'fullpos',
    });
    await pumpSheet(tester, datasource: datasource);
    await tester.enterText(find.byType(TextField), 'Consulta con fuentes');
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();
    expect(find.text('respuesta de prueba'), findsOneWidget);
    expect(find.text('Guía interna de prueba'), findsNothing);
    expect(find.byIcon(Icons.menu_book_rounded), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold)),
    );
    expect(
      container
          .read(aiAssistantControllerProvider)
          .messages
          .last
          .citations
          .single
          .title,
      'Guía interna de prueba',
    );
  });

  testWidgets(
    'recupera el envío desde Reintentar sin escribir ni duplicar el mensaje',
    (tester) async {
      final datasource = _FakeDataSource()..fail = true;
      await pumpSheet(tester, datasource: datasource);
      await tester.enterText(find.byType(TextField), 'Mi pregunta completa');
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Reintentar'), findsOneWidget);
      datasource.fail = false;
      await tester.tap(find.byTooltip('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Mi pregunta completa'), findsOneWidget);
      expect(find.text('respuesta de prueba'), findsOneWidget);
      expect(find.byTooltip('Reintentar'), findsNothing);
    },
  );

  testWidgets('el mensaje con imagen enseña la miniatura adjunta', (
    tester,
  ) async {
    await pumpSheet(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold)),
    );
    final controller = container.read(aiAssistantControllerProvider.notifier);
    // PNG 1×1 válido: lo único necesario es que `Image.memory` tenga algo que decodificar.
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );

    // 1) Con el archivo ya subido, el compositor enseña la vista previa antes de enviar.
    await controller.attachFile(
      filename: 'captura.png',
      bytes: png,
      mimeType: 'image/png',
    );
    await tester.pump();
    expect(
      find.bySemanticsLabel('Vista previa de captura.png'),
      findsOneWidget,
    );

    // 2) Al enviar, la imagen se queda en la burbuja del mensaje (no como texto «Adjunto: …»).
    await controller.sendMessage('mira esta pantalla');
    await tester.pump();
    expect(
      find.bySemanticsLabel('Imagen adjunta: captura.png'),
      findsOneWidget,
    );
    expect(find.textContaining('Adjunto:'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(1280, 800), const Size(390, 844)]) {
    testWidgets('compositor sin desbordamientos en $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpSheet(tester);
      await tester.pumpAndSettle();

      final composer = tester.getRect(
        find.byKey(const ValueKey('ai-assistant-composer')),
      );
      for (final finder in [
        find.byType(TextField),
        find.byIcon(Icons.image_outlined),
        find.byIcon(Icons.mic_none_rounded),
        find.byIcon(Icons.send_rounded),
      ]) {
        final rect = tester.getRect(finder);
        expect(composer.contains(rect.topLeft), isTrue);
        expect(composer.contains(rect.bottomRight), isTrue);
      }
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(GlobalAiChatSheet),
        matchesGoldenFile(
          platformGolden('goldens/assistant_${size.width.toInt()}.png'),
        ),
      );
    });
  }

  testWidgets('el panel se cierra fuera y mantiene el foco dentro', (
    tester,
  ) async {
    const recordChannel = MethodChannel('com.llfbandit.record/messages');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      recordChannel,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        recordChannel,
        null,
      ),
    );
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          aiAssistantControllerProvider.overrideWith(
            (_) => AiAssistantController(AiAssistantService(_FakeDataSource())),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: AiAssistantDockButton(
                  compact: true,
                  onPressed: () => GlobalAiAssistantEntryPoint.showDesktopPanel(
                    context,
                    ref,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(AiAssistantDockButton),
      matchesGoldenFile(platformGolden('goldens/assistant_button.png')),
    );
    await tester.tap(find.byType(AiAssistantDockButton));
    await tester.pumpAndSettle();
    expect(find.byType(GlobalAiChatSheet), findsOneWidget);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.byType(GlobalAiChatSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(Overlay).first,
      matchesGoldenFile(platformGolden('goldens/assistant_dock.png')),
    );

    await tester.tapAt(const Offset(100, 100));
    await tester.pumpAndSettle();
    expect(find.byType(GlobalAiChatSheet), findsNothing);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold)),
    );
    expect(container.read(desktopAiAssistantPanelOpenProvider), isFalse);
  });

  testWidgets('el compositor móvil sigue visible al abrir el teclado', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = FakeViewPadding(bottom: 300);
    addTearDown(tester.view.reset);
    await pumpSheet(tester);
    await tester.pumpAndSettle();
    final composer = tester.getRect(
      find.byKey(const ValueKey('ai-assistant-composer')),
    );
    expect(composer.bottom, lessThanOrEqualTo(544));
    await tester.enterText(
      find.byType(TextField),
      'Pregunta con teclado abierto',
    );
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(find.text('respuesta de prueba'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin permiso de micrófono avisa y no empieza a grabar', (
    tester,
  ) async {
    recorder = _FakeRecorder(permission: false);
    await pumpSheet(tester);

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();
    await tester.pump();

    expect(recorder.started, isFalse);
    expect(
      find.textContaining('No hay permiso para usar el micrófono'),
      findsOneWidget,
    );
    expect(find.textContaining('Grabando nota de voz'), findsNothing);
  });

  testWidgets('graba, muestra el cronómetro y permite cancelar', (
    tester,
  ) async {
    await pumpSheet(tester);

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();
    await tester.pump();

    expect(recorder.started, isTrue);
    expect(find.textContaining('Grabando nota de voz'), findsOneWidget);
    expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pump();
    await tester.pump();

    expect(recorder.cancelled, isTrue);
    expect(find.textContaining('Grabando nota de voz'), findsNothing);
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
  });
}

class _FakeRecorder implements VoiceNoteRecorderContract {
  _FakeRecorder({this.permission = true});

  final bool permission;
  bool started = false;
  bool cancelled = false;

  @override
  Duration get maxDuration => const Duration(minutes: 3);

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<String> startNew(DateTime at) async {
    started = true;
    return 'C:/tmp/nota-de-voz.m4a';
  }

  @override
  Future<String?> stop() async => 'C:/tmp/nota-de-voz.m4a';

  @override
  Future<void> cancel() async {
    cancelled = true;
  }

  @override
  Future<void> dispose() async {}
}

class _FakeDataSource extends AiAssistantDataSource {
  _FakeDataSource() : super(Dio());

  bool fail = false;
  Completer<Map<String, dynamic>>? pending;
  final List<Map<String, dynamic>> citations = [];

  @override
  Future<Map<String, dynamic>> chat({
    required AiChatContext context,
    required String message,
    required List<Map<String, dynamic>> history,
    String? conversationId,
    String? clientMessageId,
    String? mediaJobId,
  }) async {
    if (pending != null) return pending!.future;
    if (fail) throw StateError('Fallo de conexión simulado');
    return <String, dynamic>{
      'content': 'respuesta de prueba',
      'denied': false,
      'citations': citations,
      'conversationId': 'conv-1',
      'requiresHumanReview': false,
    };
  }

  @override
  Future<Map<String, dynamic>> uploadAttachment({
    required String filename,
    required List<int> bytes,
    required String mimeType,
  }) async {
    return <String, dynamic>{'mediaJobId': 'job-1'};
  }
}
