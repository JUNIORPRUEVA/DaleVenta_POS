import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
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

  static const MethodChannel _nativeBluetooth = MethodChannel(
    'com.daleventa.pos/native_bluetooth_printer',
  );

  final MobilePrinterSettingsRepository _settingsRepository;
  final MobileEscPosGenerator _escPos = const MobileEscPosGenerator();
  bool _printing = false;

  static int bluetoothPrinterScore(BluetoothInfo printer) {
    final name = printer.name.trim().toLowerCase();
    final mac = printer.macAdress.trim();
    var score = 0;
    if (name.contains('pt-210') || name.contains('pt210')) score += 80;
    if (name.startsWith('pt')) score += 35;
    if (name.startsWith('mpos')) score -= 18;

    const strongMatches = [
      'thermal',
      'printer',
      'impresora',
      'receipt',
      'esc',
      'rpp',
      'mtp',
      'zj-',
      'xp-',
      'gp-',
      '58',
      '80',
    ];
    const weakMatches = ['bt', 'ble', 'print', 'ticket', 'mini'];
    const nonPrinterMatches = [
      'phone',
      'samsung',
      'iphone',
      'watch',
      'buds',
      'audio',
      'headset',
      'speaker',
      'car',
      'tv',
      'mouse',
      'keyboard',
      'laptop',
    ];

    for (final item in strongMatches) {
      if (name.contains(item)) score += 12;
    }
    for (final item in weakMatches) {
      if (name.contains(item)) score += 4;
    }
    for (final item in nonPrinterMatches) {
      if (name.contains(item)) score -= 20;
    }
    if (mac.split(':').length == 6) score += 2;
    if (name.isEmpty) score -= 6;
    return score;
  }

  static bool isLikelyBluetoothPrinter(BluetoothInfo printer) {
    return bluetoothPrinterScore(printer) >= 8;
  }

  static List<BluetoothInfo> sortBluetoothPrinters(
    List<BluetoothInfo> printers,
  ) {
    final sorted = [...printers];
    sorted.sort((a, b) {
      final score = bluetoothPrinterScore(
        b,
      ).compareTo(bluetoothPrinterScore(a));
      if (score != 0) return score;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted;
  }

  Future<List<BluetoothInfo>> discoverBluetoothPrinters() async {
    if (!Platform.isAndroid) return const [];
    final permission = await ensureBluetoothPermissions();
    if (!permission.success) return const [];
    final enabled = await PrintBluetoothThermal.bluetoothEnabled;
    if (!enabled) return const [];
    final nativePrinters = await _nativePairedDevices();
    final pluginPrinters = await PrintBluetoothThermal.pairedBluetooths
        .timeout(
          const Duration(seconds: 4),
          onTimeout: () => const <BluetoothInfo>[],
        )
        .catchError((_) => const <BluetoothInfo>[]);
    return sortBluetoothPrinters(
      _mergeBluetoothPrinters([...nativePrinters, ...pluginPrinters]),
    );
  }

  Future<MobilePrintServiceResult> autoConnectBluetoothPrinter(
    MobilePrinterSettingsModel settings,
  ) async {
    return _autoConnectBluetoothPrinter(settings);
  }

  Future<MobilePrintServiceResult> _autoConnectBluetoothPrinter(
    MobilePrinterSettingsModel settings, {
    Set<String> ignoredAddresses = const {},
  }) async {
    if (!Platform.isAndroid) {
      return const MobilePrintServiceResult(
        success: false,
        message: 'Bluetooth directo solo está disponible en Android.',
      );
    }
    final permission = await ensureBluetoothPermissions();
    if (!permission.success) return permission;
    final enabled = await PrintBluetoothThermal.bluetoothEnabled;
    if (!enabled) {
      const message = 'Bluetooth está apagado. Enciéndelo para imprimir.';
      await _saveError(settings, message);
      return const MobilePrintServiceResult(success: false, message: message);
    }

    await _settingsRepository.update(
      settings.copyWith(
        connectionType: MobilePrinterConnectionType.bluetooth,
        lastStatus: MobilePrinterConnectionStatus.searching,
        clearLastError: true,
      ),
    );

    final savedAddress = settings.bluetoothAddress.trim();
    if (savedAddress.isNotEmpty &&
        !ignoredAddresses
            .map((item) => item.toLowerCase())
            .contains(savedAddress.toLowerCase())) {
      await _disconnectPluginBluetooth();
      final connected = await _nativeConnect(
        address: savedAddress,
        timeoutSeconds: settings.timeoutSeconds,
      );
      if (connected) {
        await _settingsRepository.update(
          settings.copyWith(
            connectionType: MobilePrinterConnectionType.bluetooth,
            lastStatus: MobilePrinterConnectionStatus.connected,
            lastSuccessfulConnectionMs: DateTime.now().millisecondsSinceEpoch,
            clearLastError: true,
          ),
        );
        return MobilePrintServiceResult(
          success: true,
          message:
              'Impresora conectada: ${settings.printerName.isEmpty ? savedAddress : settings.printerName}. Ya puedes imprimir.',
        );
      }
    }

    final paired = await discoverBluetoothPrinters();
    final normalizedIgnored = ignoredAddresses
        .map((item) => item.trim().toLowerCase())
        .where((item) => item.isNotEmpty)
        .toSet();
    final candidates = paired
        .where(isLikelyBluetoothPrinter)
        .where(
          (printer) => !normalizedIgnored.contains(
            printer.macAdress.trim().toLowerCase(),
          ),
        )
        .toList(growable: false);
    if (candidates.isEmpty) {
      const message =
          'No encontré una impresora térmica emparejada. En Android empareja la PT-210 con PIN 0000 y vuelve a tocar Conectar.';
      await _saveError(settings, message);
      return const MobilePrintServiceResult(success: false, message: message);
    }
    if (savedAddress.isNotEmpty) {
      final savedIndex = candidates.indexWhere(
        (printer) =>
            printer.macAdress.trim().toLowerCase() ==
            savedAddress.toLowerCase(),
      );
      if (savedIndex > 0) {
        final saved = candidates.removeAt(savedIndex);
        candidates.insert(0, saved);
      }
    }

    final timeout = Duration(seconds: settings.timeoutSeconds.clamp(3, 8));
    for (final printer in candidates) {
      final nextSettings = settings.copyWith(
        connectionType: MobilePrinterConnectionType.bluetooth,
        printerName: _printerDisplayName(printer),
        bluetoothAddress: printer.macAdress.trim(),
        paperWidthMm: _inferPaperWidthMm(printer, settings.paperWidthMm),
        lastStatus: MobilePrinterConnectionStatus.connecting,
        clearLastError: true,
      );
      await _settingsRepository.update(nextSettings);
      try {
        final connected = await PrintBluetoothThermal.connect(
          macPrinterAddress: printer.macAdress.trim(),
        ).timeout(timeout);
        final nativeConnected = connected
            ? true
            : await _nativeConnect(
                address: printer.macAdress.trim(),
                timeoutSeconds: settings.timeoutSeconds,
              );
        if (!nativeConnected) continue;
        await _settingsRepository.update(
          nextSettings.copyWith(
            lastStatus: MobilePrinterConnectionStatus.connected,
            lastSuccessfulConnectionMs: DateTime.now().millisecondsSinceEpoch,
            clearLastError: true,
          ),
        );
        return MobilePrintServiceResult(
          success: true,
          message:
              'Impresora conectada: ${_printerDisplayName(printer)}. Ya puedes imprimir.',
        );
      } catch (_) {
        continue;
      }
    }

    const message =
        'Encontré impresoras térmicas emparejadas, pero ninguna respondió. Enciende la impresora, acércala al teléfono y vuelve a intentar.';
    await _saveError(settings, message);
    return const MobilePrintServiceResult(success: false, message: message);
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
      await _disconnectPluginBluetooth();
      final nativeConnected = await _nativeConnect(
        address: settings.bluetoothAddress.trim(),
        timeoutSeconds: settings.timeoutSeconds,
      );
      final connected = nativeConnected
          ? true
          : await PrintBluetoothThermal.connect(
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
    Uint8List? logoBytes,
    bool printLogo = false,
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
        return _printBluetooth(
          lines: lines,
          settings: settings,
          logoBytes: logoBytes,
          printLogo: printLogo,
        );
      }

      if (!forceSystemPrint &&
          settings.connectionType == MobilePrinterConnectionType.network) {
        return _printNetwork(
          lines: lines,
          settings: settings,
          logoBytes: logoBytes,
          printLogo: printLogo,
        );
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
    Uint8List? logoBytes,
    bool printLogo = false,
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
      final bytes = _escPos.buildTicketBytes(
        lines: lines,
        settings: settings,
        logoBytes: logoBytes,
        printLogo: printLogo || settings.printLogo,
      );
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
    Uint8List? logoBytes,
    bool printLogo = false,
    bool allowAutoRecovery = true,
  }) async {
    var effectiveSettings = settings;
    if (effectiveSettings.bluetoothAddress.trim().isEmpty &&
        allowAutoRecovery) {
      final auto = await autoConnectBluetoothPrinter(effectiveSettings);
      if (!auto.success) return auto;
      effectiveSettings = await _settingsRepository.getOrCreate();
    }

    final validation = await _validateBluetoothSettings(effectiveSettings);
    if (validation != null) {
      await _saveError(effectiveSettings, validation);
      return MobilePrintServiceResult(success: false, message: validation);
    }
    try {
      await _settingsRepository.update(
        effectiveSettings.copyWith(
          lastStatus: MobilePrinterConnectionStatus.connecting,
          clearLastError: true,
        ),
      );
      final bytes = _escPos.buildTicketBytes(
        lines: lines,
        settings: effectiveSettings,
        logoBytes: logoBytes,
        printLogo: printLogo || effectiveSettings.printLogo,
      );
      await _disconnectPluginBluetooth();
      var nativeOk = await _nativeWrite(
        address: effectiveSettings.bluetoothAddress.trim(),
        bytes: bytes,
        timeoutSeconds: effectiveSettings.timeoutSeconds,
        forceReconnect: true,
      );
      var pluginConnected = false;
      if (!nativeOk) {
        await _disconnectPluginBluetooth();
        pluginConnected = await PrintBluetoothThermal.connectionStatus;
        if (!pluginConnected || effectiveSettings.autoReconnect) {
          pluginConnected = await PrintBluetoothThermal.connect(
            macPrinterAddress: effectiveSettings.bluetoothAddress.trim(),
          ).timeout(Duration(seconds: effectiveSettings.timeoutSeconds));
        }
      }
      if (!nativeOk && !pluginConnected) {
        if (allowAutoRecovery && effectiveSettings.autoReconnect) {
          final auto = await _autoConnectBluetoothPrinter(
            effectiveSettings,
            ignoredAddresses: {effectiveSettings.bluetoothAddress},
          );
          if (auto.success) {
            return _printBluetooth(
              lines: lines,
              settings: await _settingsRepository.getOrCreate(),
              logoBytes: logoBytes,
              printLogo: printLogo,
              allowAutoRecovery: false,
            );
          }
        }
        const message = 'No se pudo conectar a la impresora Bluetooth.';
        await _saveError(effectiveSettings, message);
        return const MobilePrintServiceResult(success: false, message: message);
      }

      if (!nativeOk) {
        final pluginOk = await PrintBluetoothThermal.writeBytes(
          bytes,
        ).timeout(Duration(seconds: effectiveSettings.timeoutSeconds));
        nativeOk = pluginOk;
      }
      if (!nativeOk) {
        if (allowAutoRecovery && effectiveSettings.autoReconnect) {
          final auto = await _autoConnectBluetoothPrinter(
            effectiveSettings,
            ignoredAddresses: {effectiveSettings.bluetoothAddress},
          );
          if (auto.success) {
            return _printBluetooth(
              lines: lines,
              settings: await _settingsRepository.getOrCreate(),
              logoBytes: logoBytes,
              printLogo: printLogo,
              allowAutoRecovery: false,
            );
          }
        }
        const message = 'La impresora Bluetooth no confirmó la impresión.';
        await _saveError(effectiveSettings, message);
        return const MobilePrintServiceResult(success: false, message: message);
      }

      await _settingsRepository.update(
        effectiveSettings.copyWith(
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
      if (allowAutoRecovery && effectiveSettings.autoReconnect) {
        final auto = await _autoConnectBluetoothPrinter(
          effectiveSettings,
          ignoredAddresses: {effectiveSettings.bluetoothAddress},
        );
        if (auto.success) {
          return _printBluetooth(
            lines: lines,
            settings: await _settingsRepository.getOrCreate(),
            logoBytes: logoBytes,
            printLogo: printLogo,
            allowAutoRecovery: false,
          );
        }
      }
      final message = 'Fallo imprimiendo por Bluetooth: $e';
      await _saveError(effectiveSettings, message);
      return MobilePrintServiceResult(success: false, message: message);
    }
  }

  Future<void> _disconnectPluginBluetooth() async {
    if (!Platform.isAndroid) return;
    try {
      await PrintBluetoothThermal.disconnect.timeout(
        const Duration(seconds: 2),
      );
    } catch (_) {
      // Best effort: some devices report an error when there is no active link.
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

  static String _printerDisplayName(BluetoothInfo printer) {
    final name = printer.name.trim();
    return name.isEmpty ? 'Impresora Bluetooth' : name;
  }

  static int _inferPaperWidthMm(BluetoothInfo printer, int fallback) {
    final name = printer.name.toLowerCase();
    if (name.contains('pt-210') || name.contains('pt210')) return 58;
    if (name.contains('58')) return 58;
    if (name.contains('80')) return 80;
    return fallback;
  }

  static Future<bool> _nativeConnect({
    required String address,
    required int timeoutSeconds,
  }) async {
    if (!Platform.isAndroid || address.trim().isEmpty) return false;
    try {
      return await _nativeBluetooth.invokeMethod<bool>('connect', {
            'address': address.trim(),
            'timeoutMs': timeoutSeconds.clamp(2, 15) * 1000,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _nativeWrite({
    required String address,
    required List<int> bytes,
    required int timeoutSeconds,
    bool forceReconnect = false,
  }) async {
    if (!Platform.isAndroid || address.trim().isEmpty || bytes.isEmpty) {
      return false;
    }
    try {
      return await _nativeBluetooth.invokeMethod<bool>('write', {
            'address': address.trim(),
            'bytes': Uint8List.fromList(bytes),
            'timeoutMs': timeoutSeconds.clamp(2, 15) * 1000,
            'forceReconnect': forceReconnect,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<List<BluetoothInfo>> _nativePairedDevices() async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw =
          await _nativeBluetooth.invokeMethod<List<dynamic>>('pairedDevices') ??
          const <dynamic>[];
      return raw
          .whereType<Map<dynamic, dynamic>>()
          .map(
            (item) => BluetoothInfo(
              name: item['name']?.toString() ?? '',
              macAdress: item['address']?.toString() ?? '',
            ),
          )
          .where((item) => item.macAdress.trim().isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  static List<BluetoothInfo> _mergeBluetoothPrinters(
    List<BluetoothInfo> printers,
  ) {
    final byAddress = <String, BluetoothInfo>{};
    for (final printer in printers) {
      final address = printer.macAdress.trim();
      if (address.isEmpty) continue;
      final key = address.toLowerCase();
      final previous = byAddress[key];
      if (previous == null ||
          (previous.name.trim().isEmpty && printer.name.trim().isNotEmpty)) {
        byAddress[key] = printer;
      }
    }
    return byAddress.values.toList(growable: false);
  }
}
