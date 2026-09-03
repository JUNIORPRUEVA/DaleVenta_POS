import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/settings/data/mobile_printer_settings_model.dart';
import '../../../features/settings/data/mobile_printer_settings_repository.dart';
import '../../../features/settings/data/printer_settings_repository.dart';
import '../../../modules/ventas/sales_models.dart';
import '../mobile_print_service.dart';
import '../printing_platform_resolver.dart';
import '../raw_printer_transport.dart';
import '../windows_raw_printer_transport_stub.dart'
    if (dart.library.io) '../windows_raw_printer_transport.dart';
import 'cash_drawer_command.dart';

/// Servicio centralizado de caja registradora.
///
/// La caja registradora física se controla a través de la impresora térmica
/// compatible (puerto RJ11/RJ12) enviando únicamente el comando ESC/POS
/// `ESC p` (pulso de apertura). Este servicio es el ÚNICO punto que emite
/// comandos de caja en toda la app: ninguna pantalla/venta escribe bytes de
/// cajón directamente.
///
/// Responsabilidades:
/// - `testOpenDrawer()`: botón "Probar apertura de caja" (solo pulso, sin
///   imprimir ticket).
/// - `openDrawerAfterEligibleSalePrint(...)`: apertura automática tras una
///   impresión elegible (venta en efectivo nueva), SIEMPRE después de que el
///   ticket llegó a su punto de éxito. Las reimpresiones NO abren la caja.
///
/// El aislamiento de fallos es crítico: un error al abrir la caja NUNCA puede
/// invalidar una venta ya completada ni alterar el resultado de impresión.
final cashDrawerServiceProvider = Provider<CashDrawerService>((ref) {
  return CashDrawerService(ref);
});

/// Resultado de una operación de caja registradora.
class CashDrawerResult {
  const CashDrawerResult({
    required this.success,
    this.skipped = false,
    this.unsupported = false,
    required this.title,
    required this.message,
  });

  /// `true` solo cuando el pulso fue despachado correctamente al transporte.
  final bool success;

  /// `true` cuando el pulso NO se intentó a propósito (regla/contexto):
  /// apertura automática desactivada, venta sin efectivo, reimpresión,
  /// plataforma que gestiona la caja por otro mecanismo.
  final bool skipped;

  /// `true` cuando la plataforma/impresora actual no puede emitir el pulso.
  final bool unsupported;

  /// Título corto para la notificación (nunca un error técnico en bruto).
  final String title;

  /// Mensaje amigable para la notificación (nunca un error técnico en bruto).
  final String message;

  /// `true` = se intentó el pulso pero falló. El llamador debe mostrar una
  /// advertencia de hardware NO bloqueante; jamás revertir la venta.
  bool get shouldWarn => !success && !skipped && !unsupported;

  const CashDrawerResult.success({
    this.title = 'Orden enviada',
    this.message = 'Se envió la orden para abrir la caja registradora.',
  }) : success = true,
       skipped = false,
       unsupported = false;

  const CashDrawerResult.skipped({this.title = '', this.message = ''})
    : success = false,
      skipped = true,
      unsupported = false;

  const CashDrawerResult.unsupported({
    this.title = 'No disponible',
    this.message =
        'Esta plataforma o impresora no puede abrir la caja registradora.',
  }) : success = false,
       skipped = false,
       unsupported = true;

  const CashDrawerResult.failure({
    required this.title,
    required this.message,
  }) : success = false,
       skipped = false,
       unsupported = false;
}

/// Transporte RAW de Windows NO disponible fuera de Windows. Evita abrir
/// `winspool.drv`/`kernel32.dll` por FFI en plataformas donde no existen
/// (Android/iOS/web).
class _UnavailableWindowsRawTransport implements RawPrinterTransport {
  const _UnavailableWindowsRawTransport();

  @override
  Future<RawPrintResult> printRaw({
    required String printerName,
    required Uint8List bytes,
    String documentName = 'FullPOS ESC/POS Ticket',
    int copies = 1,
  }) {
    throw const RawPrinterException(
      'La impresión RAW de Windows solo está disponible en Windows.',
    );
  }
}

class CashDrawerService {
  CashDrawerService(
    this._ref, {
    RawPrinterTransport? windowsRawPrinterTransport,
    Duration kickTimeout = const Duration(seconds: 8),
  }) : _windowsRaw =
           windowsRawPrinterTransport ?? _defaultWindowsRawTransport(),
       _kickTimeout = kickTimeout;

  final Ref _ref;
  final RawPrinterTransport _windowsRaw;
  final Duration _kickTimeout;

  static RawPrinterTransport _defaultWindowsRawTransport() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      return WindowsRawPrinterTransport();
    }
    return const _UnavailableWindowsRawTransport();
  }

  PrintingPlatformResolver get _platformResolver =>
      _ref.read(printingPlatformResolverProvider);

  // ---------------------------------------------------------------------
  // Botón "Probar apertura de caja"
  // ---------------------------------------------------------------------

  /// Envía SOLO el pulso de apertura con la impresora térmica configurada.
  /// No imprime ningún ticket.
  Future<CashDrawerResult> testOpenDrawer() async {
    final platform = _platformResolver.platform;
    switch (platform) {
      case PrintingPlatform.windows:
        final settings = await _ref
            .read(printerSettingsRepositoryProvider)
            .getOrCreate();
        final printer = (settings.selectedPrinterName ?? '').trim();
        if (printer.isEmpty) {
          return const CashDrawerResult.failure(
            title: 'Configura una impresora',
            message:
                'Selecciona primero la impresora térmica que controla la caja registradora.',
          );
        }
        return _kickWindows(printer);
      case PrintingPlatform.android:
      case PrintingPlatform.ios:
        return _testOpenDrawerMobile();
      case PrintingPlatform.web:
      case PrintingPlatform.other:
        return const CashDrawerResult.unsupported(
          title: 'No disponible en el navegador',
          message:
              'Desde el navegador no se puede abrir la caja registradora directamente. Usa la app de escritorio (Windows) o la app móvil con una impresora térmica Bluetooth o LAN.',
        );
    }
  }

  Future<CashDrawerResult> _testOpenDrawerMobile() async {
    final mobile = await _ref
        .read(mobilePrinterSettingsRepositoryProvider)
        .getOrCreate();
    final connection = mobile.connectionType;
    if (connection == MobilePrinterConnectionType.bluetooth ||
        connection == MobilePrinterConnectionType.network) {
      final result = await _ref
          .read(mobilePrintServiceProvider)
          .sendDrawerPulse();
      if (result.success) {
        return const CashDrawerResult.success();
      }
      return CashDrawerResult.failure(
        title: 'No se pudo abrir',
        message: _friendlyMobileMessage(result.message),
      );
    }
    return const CashDrawerResult.unsupported(
      title: 'Configura una impresora',
      message:
          'Para abrir la caja registradora selecciona una impresora térmica Bluetooth o LAN en Impresora y tickets.',
    );
  }

  // ---------------------------------------------------------------------
  // Apertura automática tras impresión elegible
  // ---------------------------------------------------------------------

  /// Decide si se abre la caja después de una impresión de venta elegible.
  ///
  /// Reglas (documentadas en `docs/PRODUCT_SPEC.md`):
  /// - Las reimpresiones (`isCopy: true`) NUNCA abren la caja.
  /// - Escritorio/Windows: solo si `autoOpenCashDrawer` está activo y la venta
  ///   involucra efectivo (`paymentCashAmount > 0` o método `cash`/`mixed`).
  /// - Móvil (Android/iOS): la apertura automática se gobierna por el
  ///   interruptor móvil "Abrir gaveta" (`openCashDrawer`), que inyecta el
  ///   pulso en la impresión ESC/POS. Aquí se devuelve `skipped` para no
  ///   emitir un segundo pulso duplicado.
  /// - Web/otro: sin apertura automática.
  ///
  /// Este método NUNCA lanza: ante cualquier fallo devuelve un resultado para
  /// que la venta ya completada siga intacta.
  Future<CashDrawerResult> openDrawerAfterEligibleSalePrint({
    required SaleModel sale,
    bool isCopy = false,
  }) async {
    if (isCopy) {
      return const CashDrawerResult.skipped(
        message:
            'No se abre la caja registradora al reimprimir un documento histórico.',
      );
    }
    final platform = _platformResolver.platform;
    switch (platform) {
      case PrintingPlatform.windows:
        final settings = await _ref
            .read(printerSettingsRepositoryProvider)
            .getOrCreate();
        if (!settings.autoOpenCashDrawer) {
          return const CashDrawerResult.skipped(
            message: 'Apertura automática de caja desactivada.',
          );
        }
        if (!_saleInvolvesCash(sale)) {
          return const CashDrawerResult.skipped(
            message:
                'La venta no involucró efectivo; la caja no se abre automáticamente.',
          );
        }
        final printer = (settings.selectedPrinterName ?? '').trim();
        if (printer.isEmpty) {
          debugPrint(
            '[CASH DRAWER] auto-open omitido: no hay impresora térmica configurada.',
          );
          return const CashDrawerResult.skipped(
            message: 'No hay impresora térmica configurada.',
          );
        }
        final kick = await _kickWindows(printer);
        // `_kickWindows` solo devuelve éxito o fallo (nunca skipped/unsupported),
        // así que un fallo aquí es siempre una advertencia accionable.
        if (!kick.success) {
          return const CashDrawerResult.failure(
            title: 'Caja registradora',
            message:
                'La venta se completó, pero no fue posible abrir la caja registradora automáticamente.',
          );
        }
        return kick;
      case PrintingPlatform.android:
      case PrintingPlatform.ios:
        return const CashDrawerResult.skipped(
          title: 'Móvil',
          message:
              'En móvil la apertura automática se controla con "Abrir gaveta" en Impresora y tickets.',
        );
      case PrintingPlatform.web:
      case PrintingPlatform.other:
        return const CashDrawerResult.skipped(
          message: 'Plataforma sin apertura automática de caja.',
        );
    }
  }

  bool _saleInvolvesCash(SaleModel sale) {
    final method = sale.paymentMethod.trim().toLowerCase();
    return sale.paymentCashAmount > 0 || method == 'cash' || method == 'mixed';
  }

  // ---------------------------------------------------------------------
  // Transporte
  // ---------------------------------------------------------------------

  /// Envía el pulso de caja por el transporte RAW de Windows (WinSpool).
  Future<CashDrawerResult> _kickWindows(String printerName) async {
    try {
      await _windowsRaw
          .printRaw(
            printerName: printerName,
            bytes: CashDrawerCommand.pulseBytes(),
            documentName: 'FullPOS apertura de caja',
            copies: 1,
          )
          .timeout(_kickTimeout);
      debugPrint('[CASH DRAWER] pulso enviado a "$printerName".');
      return const CashDrawerResult.success();
    } on TimeoutException {
      debugPrint('[CASH DRAWER] timeout abriendo la caja en "$printerName".');
      return const CashDrawerResult.failure(
        title: 'No se pudo abrir',
        message:
            'La impresora tardó demasiado en responder. Verifica que esté encendida y conectada.',
      );
    } catch (error, stackTrace) {
      // El detalle técnico queda solo en logs internos; el cliente nunca ve
      // RawPrinterException / bytes / pila de impresora.
      debugPrint('[CASH DRAWER] error abriendo la caja: $error');
      debugPrint(stackTrace.toString());
      return const CashDrawerResult.failure(
        title: 'No se pudo abrir',
        message:
            'No fue posible abrir la caja registradora. Verifica que la impresora térmica esté encendida y que la caja esté conectada a su puerto.',
      );
    }
  }

  /// Limpia posibles prefijos técnicos de mensajes móviles para que el
  /// cliente nunca vea un error en bruto (Exception / driver / bytes).
  String _friendlyMobileMessage(String message) {
    final cleaned = message
        .replaceAll(RegExp(r'^(Fallo|Fallo imprimiendo por [^:]+): '), '')
        .replaceAll('Exception: ', '')
        .trim();
    if (cleaned.isEmpty) {
      return 'No fue posible abrir la caja registradora. Revisa la impresora térmica.';
    }
    return cleaned;
  }
}
