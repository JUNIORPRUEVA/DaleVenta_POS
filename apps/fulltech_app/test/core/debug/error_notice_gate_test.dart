import 'package:daleventa_pos/core/debug/app_error_reporter.dart';
import 'package:daleventa_pos/core/debug/error_notice_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Frecuencia de los avisos de error **recuperables**.
///
/// Reglas verificadas (incidente del actualizador en Windows):
/// - un aviso por categoría y día local,
/// - el cierre se respeta durante el resto del día aunque se reinicie la app,
/// - persistencia independiente de `UpdatePersistence`,
/// - nunca un bucle si la preferencia no se puede guardar,
/// - los `fatal` no se limitan jamás.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const updaterTitle = 'No pudimos comprobar las actualizaciones.';
  const updaterMessage = 'Puedes seguir utilizando FullPOS normalmente.';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ErrorNoticeGate.instance.resetForTest();
    AppErrorReporter.instance.resetForTesting();
  });

  tearDown(() {
    ErrorNoticeGate.instance.resetForTest();
    AppErrorReporter.instance.resetForTesting();
  });

  void recordUpdaterFailure({
    AppErrorSeverity severity = AppErrorSeverity.warning,
    String? noticeCategory = 'updater',
    String? dedupeKey,
  }) {
    AppErrorReporter.instance.record(
      StateError('updater persistence failed'),
      StackTrace.current,
      context: 'actualizacion:CHECK_ERROR',
      title: updaterTitle,
      userMessage: updaterMessage,
      severity: severity,
      noticeCategory: noticeCategory,
      dedupeKey: dedupeKey,
    );
  }

  String dayKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  group('ErrorNoticeGate', () {
    test('permite el primer aviso del día y lo bloquea después', () async {
      await ErrorNoticeGate.instance.load();

      expect(ErrorNoticeGate.instance.shouldShow('updater'), isTrue);
      ErrorNoticeGate.instance.markShown('updater');
      expect(ErrorNoticeGate.instance.shouldShow('updater'), isFalse);
    });

    test('el cierre sobrevive al reinicio de la aplicación', () async {
      await ErrorNoticeGate.instance.load();
      ErrorNoticeGate.instance.markShown('updater');

      // Reinicio: se descarta el estado en memoria y se vuelve a leer el disco.
      ErrorNoticeGate.instance.resetForTest();
      await ErrorNoticeGate.instance.load();

      expect(
        ErrorNoticeGate.instance.shouldShow('updater'),
        isFalse,
        reason: 'Cerrar el aviso debe respetarse durante el resto del día.',
      );
    });

    test('vuelve a avisar al día siguiente si el problema persiste', () async {
      final yesterday = dayKey(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'error_notice_last_shown.updater': yesterday,
      });
      ErrorNoticeGate.instance.resetForTest();

      await ErrorNoticeGate.instance.load();

      expect(ErrorNoticeGate.instance.shouldShow('updater'), isTrue);
    });

    test('cada categoría tiene su propio límite', () async {
      await ErrorNoticeGate.instance.load();
      ErrorNoticeGate.instance.markShown('updater');

      expect(ErrorNoticeGate.instance.shouldShow('updater'), isFalse);
      expect(ErrorNoticeGate.instance.shouldShow('sync'), isTrue);
    });

    test('si la preferencia no se puede guardar no lanza ni entra en bucle', () {
      // Sin `load()` no hay `SharedPreferences`: el límite sigue actuando en
      // memoria y `markShown` no puede lanzar (no hay reintento ni aviso extra).
      expect(ErrorNoticeGate.instance.shouldShow('updater'), isTrue);
      ErrorNoticeGate.instance.markShown('updater');
      ErrorNoticeGate.instance.markShown('updater');

      expect(ErrorNoticeGate.instance.shouldShow('updater'), isFalse);
    });
  });

  group('AppErrorReporter — límite diario de avisos recuperables', () {
    test('el primer fallo recuperable avisa con texto de negocio', () async {
      await ErrorNoticeGate.instance.load();
      recordUpdaterFailure();

      final details = AppErrorReporter.instance.lastError.value;
      expect(details, isNotNull);
      expect(details!.title, updaterTitle);
      expect(details.userMessage, updaterMessage);
      expect(details.severity, AppErrorSeverity.warning);
      expect(details.userMessage, isNot(contains('DALEVENTAS_POS_ROOT')));
      expect(details.userMessage, isNot(contains('StateError')));
    });

    test('los fallos repetidos del mismo día no vuelven a interrumpir', () async {
      await ErrorNoticeGate.instance.load();
      recordUpdaterFailure();
      AppErrorReporter.instance.clear();

      recordUpdaterFailure();
      recordUpdaterFailure();

      expect(
        AppErrorReporter.instance.lastError.value,
        isNull,
        reason: 'Un aviso por categoría y día: nada más que interrumpa.',
      );
      // ...pero el incidente sigue quedando registrado para diagnóstico.
      final recorded = AppErrorReporter.instance.history.first;
      expect(recorded.silent, isTrue);
      expect(recorded.technicalDetails, isNull);
      expect(recorded.message, contains('updater persistence failed'));
    });

    test('vuelve a avisar al día siguiente', () async {
      final yesterday = dayKey(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      SharedPreferences.setMockInitialValues(<String, Object>{
        'error_notice_last_shown.updater': yesterday,
      });
      ErrorNoticeGate.instance.resetForTest();
      await ErrorNoticeGate.instance.load();

      recordUpdaterFailure();

      expect(AppErrorReporter.instance.lastError.value, isNotNull);
    });

    test('un error crítico no se limita nunca', () async {
      await ErrorNoticeGate.instance.load();
      recordUpdaterFailure();
      AppErrorReporter.instance.clear();

      recordUpdaterFailure(severity: AppErrorSeverity.fatal);

      expect(
        AppErrorReporter.instance.lastError.value,
        isNotNull,
        reason: 'Los errores que exigen intervención inmediata siempre avisan.',
      );
    });

    test('sin categoría no se aplica ningún límite', () async {
      await ErrorNoticeGate.instance.load();
      recordUpdaterFailure(noticeCategory: null);
      AppErrorReporter.instance.clear();

      recordUpdaterFailure(noticeCategory: null);

      expect(AppErrorReporter.instance.lastError.value, isNotNull);
    });

    test('un aviso sin problema no deja rastro visible', () async {
      await ErrorNoticeGate.instance.load();

      expect(AppErrorReporter.instance.lastError.value, isNull);
      expect(AppErrorReporter.instance.history, isEmpty);
      expect(ErrorNoticeGate.instance.shouldShow('updater'), isTrue);
    });
  });
}
