import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';

import '../../features/settings/data/mobile_printer_settings_model.dart';
import '../../features/settings/data/mobile_printer_settings_repository.dart';
import 'mobile_esc_pos_generator.dart';

final mobilePrintServiceProvider = Provider<MobilePrintService>((ref) {
  return MobilePrintService(ref.read(mobilePrinterSettingsRepositoryProvider));
});

class MobilePrintServiceResult {
  const MobilePrintServiceResult({
    required this.success,
    required this.message,
  });

  final bool success;
  final String message;
}

class MobilePrintService {
  MobilePrintService(this._settingsRepository);

  final MobilePrinterSettingsRepository _settingsRepository;
  final MobileEscPosGenerator _escPos = const MobileEscPosGenerator();
  bool _printing = false;

  Future<List<BluetoothInfo>> discoverBluetoothPrinters() async {
    if (!Platform.isAndroid) return const [];
    final permission = await ensureBluetoothPermissions();
    if (!permission.success) return const [];
    final enabled = await PrintBluetoothThermal.bluetoothEnabled;
    if (!enabled) return const [];
    return PrintBluetoothThermal.pairedBluetooths.timeout(
      const Duration(seconds: 10),
      onTimeout: () => const <BluetoothInfo>[],
    );
  }

  Future<MobilePrintServiceResult> ensureBluetoothPermissions() async {
    if (!Platform.isAndroid) {
      return const MobilePrintServiceResult(
        success: false,
        message: 'Bluetooth directo solo está disponible en Android.',
      );
    }
    try {
      final android = await DeviceInfoPlugin().androidInfo;
      final sdk = android.version.sdkInt;
      final permissions = sdk >= 31
          ? <Permission>[Permission.bluetoothScan, Permission.bluetoothConnect]
          : <Permission>[Permission.bluetooth, Permission.locationWhenInUse];

      for (final permission in permissions) {
        final status = await permission.request();
        if (!status.isGranted) {
          return const MobilePrintServiceResult(
            success: false,
            message:
                'Permiso Bluetooth denegado. Actívalo para buscar impresoras.',
          );
        }
      }

      final pluginGranted =
          await PrintBluetoothThermal.isPermissionBluetoothGranted;
      if (!pluginGranted) {
        return const MobilePrintServiceResult(
          success: false,
          message: 'Android no autorizó el uso de Bluetooth para imprimir.',
        );
      }
      return const MobilePrintServiceResult(
        success: true,
        message: 'Permisos Bluetooth listos.',
      );
    } catch (e) {
      return MobilePrintServiceResult(
        success: false,
        message: 'No se pudieron validar permisos Bluetooth: $e',
      );
    }
  }

  Future<MobilePrintServiceResult> testBluetoothConnection(
    MobilePrinterSettingsModel settings,
  ) async {
    final validation = await _validateBluetoothSettings(settings);
    if (validation != null) {
      await _saveError(settings, validation);
      return MobilePrintServiceResult(success: false, message: validation);
    }
    try {
      final connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: settings.bluetoothAddress.trim(),
      ).timeout(Duration(seconds: settings.timeoutSeconds));
      if (!connected) {
        const message = 'No se pudo conectar a la impresora Bluetooth.';
        await _saveError(settings, message);
        return const MobilePrintServiceResult(success: false, message: message);
      }
      await _settingsRepository.update(
        settings.copyWith(
          lastStatus: MobilePrinterConnectionStatus.connected,
          lastSuccessfulConnectionMs: DateTime.now().millisecondsSinceEpoch,
          clearLastError: true,
        ),
      );
      return const MobilePrintServiceResult(
        success: true,
        message: 'Bluetooth conectado correctamente.',
      );
    } catch (e) {
      final message = 'No se pudo conectar por Bluetooth: $e';
      await _saveError(settings, message);
      return MobilePrintServiceResult(success: false, message: message);
    }
  }

  Future<MobilePrintServiceResult> testNetworkConnection(
    MobilePrinterSettingsModel settings,
  ) async {
    final validation = validateNetworkSettings(settings);
    if (validation != null) {
      await _saveError(settings, validation);
      return MobilePrintServiceResult(success: false, message: validation);
    }

    Socket? socket;
    try {
      socket = await Socket.connect(
        settings.networkIp.trim(),
        settings.networkPort,
        timeout: Duration(seconds: settings.timeoutSeconds),
      );
      await socket.flush();
      await socket.close();
      await _settingsRepository.update(
        settings.copyWith(
          lastStatus: MobilePrinterConnectionStatus.connected,
          lastSuccessfulConnectionMs: DateTime.now().millisecondsSinceEpoch,
          clearLastError: true,
        ),
      );
      return const MobilePrintServiceResult(
        success: true,
        message: 'Conexión LAN correcta.',
      );
    } catch (e) {
      final message = 'No se pudo conectar a la impresora LAN: $e';
      await _saveError(settings, message);
      return MobilePrintServiceResult(success: false, message: message);
    } finally {
      socket?.destroy();
    }
  }

  Future<MobilePrintServiceResult> printRaw({
    required List<String> lines,
    required Uint8List pdfBytes,
    required String documentName,
    bool forceSystemPrint = false,
  }) async {
    if (_printing) {
      return const MobilePrintServiceResult(
        success: false,
        message: 'Ya hay una impresión en proceso.',
      );
    }
    _printing = true;
    try {
      final settings = await _settingsRepository.getOrCreate();
      if (!settings.printingEnabled) {
        return const MobilePrintServiceResult(
          success: true,
          message: 'Impresión desactivada.',
        );
      }

      if (!forceSystemPrint &&
          settings.connectionType == MobilePrinterConnectionType.bluetooth) {
        return _printBluetooth(lines: lines, settings: settings);
      }

      if (!forceSystemPrint &&
          settings.connectionType == MobilePrinterConnectionType.network) {
        return _printNetwork(lines: lines, settings: settings);
      }

      await Printing.layoutPdf(
        name: documentName,
        onLayout: (_) async => pdfBytes,
      );
      return const MobilePrintServiceResult(
        success: true,
        message: 'Se abrió la impresión del sistema.',
      );
    } catch (e) {
      return MobilePrintServiceResult(
        success: false,
        message: 'No se pudo imprimir en móvil: $e',
      );
    } finally {
      _printing = false;
    }
  }

  Future<MobilePrintServiceResult> sharePdf({
    required Uint8List pdfBytes,
    required String fileName,
  }) async {
    try {
      await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
      return const MobilePrintServiceResult(
        success: true,
        message: 'PDF compartido.',
      );
    } catch (e) {
      return MobilePrintServiceResult(
        success: false,
        message: 'No se pudo compartir el PDF: $e',
      );
    }
  }

  Future<MobilePrintServiceResult> _printNetwork({
    required List<String> lines,
    required MobilePrinterSettingsModel settings,
  }) async {
    final validation = validateNetworkSettings(settings);
    if (validation != null) {
      await _saveError(settings, validation);
      return MobilePrintServiceResult(success: false, message: validation);
    }

    Socket? socket;
    try {
      await _settingsRepository.update(
        settings.copyWith(
          lastStatus: MobilePrinterConnectionStatus.connecting,
          clearLastError: true,
        ),
      );
      socket = await Socket.connect(
        settings.networkIp.trim(),
        settings.networkPort,
        timeout: Duration(seconds: settings.timeoutSeconds),
      );
      final bytes = _escPos.buildTicketBytes(lines: lines, settings: settings);
      socket.add(bytes);
      await socket.flush().timeout(Duration(seconds: settings.timeoutSeconds));
      await socket.close();
      await _settingsRepository.update(
        settings.copyWith(
          lastStatus: MobilePrinterConnectionStatus.connected,
          lastSuccessfulConnectionMs: DateTime.now().millisecondsSinceEpoch,
          clearLastError: true,
        ),
      );
      return const MobilePrintServiceResult(
        success: true,
        message: 'Ticket enviado a impresora LAN.',
      );
    } catch (e) {
      final message = 'Fallo imprimiendo por LAN: $e';
      await _saveError(settings, message);
      return MobilePrintServiceResult(success: false, message: message);
    } finally {
      socket?.destroy();
    }
  }

  Future<MobilePrintServiceResult> _printBluetooth({
    required List<String> lines,
    required MobilePrinterSettingsModel settings,
  }) async {
    final validation = await _validateBluetoothSettings(settings);
    if (validation != null) {
      await _saveError(settings, validation);
      return MobilePrintServiceResult(success: false, message: validation);
    }
    try {
      await _settingsRepository.update(
        settings.copyWith(
          lastStatus: MobilePrinterConnectionStatus.connecting,
          clearLastError: true,
        ),
      );
      var connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected || settings.autoReconnect) {
        connected = await PrintBluetoothThermal.connect(
          macPrinterAddress: settings.bluetoothAddress.trim(),
        ).timeout(Duration(seconds: settings.timeoutSeconds));
      }
      if (!connected) {
        const message = 'No se pudo conectar a la impresora Bluetooth.';
        await _saveError(settings, message);
        return const MobilePrintServiceResult(success: false, message: message);
      }

      final bytes = _escPos.buildTicketBytes(lines: lines, settings: settings);
      final ok = await PrintBluetoothThermal.writeBytes(
        bytes,
      ).timeout(Duration(seconds: settings.timeoutSeconds));
      if (!ok) {
        const message = 'La impresora Bluetooth no confirmó la impresión.';
        await _saveError(settings, message);
        return const MobilePrintServiceResult(success: false, message: message);
      }

      await _settingsRepository.update(
        settings.copyWith(
          lastStatus: MobilePrinterConnectionStatus.connected,
          lastSuccessfulConnectionMs: DateTime.now().millisecondsSinceEpoch,
          clearLastError: true,
        ),
      );
      return const MobilePrintServiceResult(
        success: true,
        message: 'Ticket enviado por Bluetooth.',
      );
    } catch (e) {
      final message = 'Fallo imprimiendo por Bluetooth: $e';
      await _saveError(settings, message);
      return MobilePrintServiceResult(success: false, message: message);
    }
  }

  Future<String?> _validateBluetoothSettings(
    MobilePrinterSettingsModel settings,
  ) async {
    if (!Platform.isAndroid) {
      return 'Bluetooth térmico directo está soportado en Android. En iOS usa AirPrint/PDF.';
    }
    final permission = await ensureBluetoothPermissions();
    if (!permission.success) return permission.message;
    final enabled = await PrintBluetoothThermal.bluetoothEnabled;
    if (!enabled) return 'Bluetooth está apagado. Enciéndelo para imprimir.';
    if (settings.bluetoothAddress.trim().isEmpty) {
      return 'Selecciona una impresora Bluetooth emparejada.';
    }
    return null;
  }

  String? validateNetworkSettings(MobilePrinterSettingsModel settings) {
    final ip = settings.networkIp.trim();
    final ipv4 = RegExp(
      r'^(25[0-5]|2[0-4]\d|1?\d?\d)(\.(25[0-5]|2[0-4]\d|1?\d?\d)){3}$',
    );
    if (!ipv4.hasMatch(ip)) return 'Escribe una dirección IP válida.';
    if (settings.networkPort < 1 || settings.networkPort > 65535) {
      return 'El puerto debe estar entre 1 y 65535.';
    }
    return null;
  }

  Future<void> _saveError(MobilePrinterSettingsModel settings, String message) {
    return _settingsRepository.update(
      settings.copyWith(
        lastStatus: MobilePrinterConnectionStatus.error,
        lastError: message,
      ),
    );
  }
}
