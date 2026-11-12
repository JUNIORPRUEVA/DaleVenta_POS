import '../../support/platform_goldens.dart';

import 'package:daleventa_pos/core/ai_assistant/application/ai_assistant_controller.dart';
import 'package:daleventa_pos/core/ai_assistant/data/datasources/ai_assistant_datasource.dart';
import 'package:daleventa_pos/core/ai_assistant/data/voice_note_recorder.dart';
import 'package:daleventa_pos/core/ai_assistant/domain/models/ai_chat_context.dart';
import 'package:daleventa_pos/core/ai_assistant/domain/services/ai_assistant_service.dart';
import 'package:daleventa_pos/core/ai_assistant/presentation/widgets/ai_assistant_sheet.dart';
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

  Future<void> pumpSheet(WidgetTester tester) async {
    final datasource = _FakeDataSource();
    final controller = AiAssistantController(AiAssistantService(datasource));
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
  }

  testWidgets('ofrece texto, adjuntar archivo y nota de voz', (tester) async {
    await pumpSheet(tester);

    expect(find.byType(TextField), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
    expect(
      find.bySemanticsLabel('Adjuntar documento, foto, video o audio'),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Grabar nota de voz'), findsOneWidget);
    expect(find.text('Escribe tu pregunta…'), findsOneWidget);
  });

  testWidgets('envía el texto desde el compositor integrado', (tester) async {
    await pumpSheet(tester);
    await tester.enterText(find.byType(TextField), 'Cómo usar esta pantalla');
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Cómo usar esta pantalla'), findsOneWidget);
    expect(find.text('respuesta de prueba'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
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
        find.byIcon(Icons.add_rounded),
        find.byIcon(Icons.mic_none_rounded),
        find.byIcon(Icons.arrow_upward_rounded),
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
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
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

  @override
  Future<Map<String, dynamic>> chat({
    required AiChatContext context,
    required String message,
    required List<Map<String, dynamic>> history,
    String? conversationId,
    String? clientMessageId,
    String? mediaJobId,
  }) async {
    return <String, dynamic>{
      'content': 'respuesta de prueba',
      'denied': false,
      'citations': <Map<String, dynamic>>[],
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
