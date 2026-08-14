import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';

import '../../../core/printing/mobile_print_service.dart';
import '../../../core/printing/models/models.dart';
import '../../../core/printing/printing_platform_resolver.dart';
import '../../../core/printing/simplified_ticket_preview_widget.dart';
import '../../../core/printing/unified_ticket_printer.dart';
import '../data/mobile_printer_settings_model.dart';
import '../data/mobile_printer_settings_repository.dart';
import '../data/printer_settings_model.dart';
import '../data/printer_settings_repository.dart';

class PrinterSettingsPage extends ConsumerWidget {
  const PrinterSettingsPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(printingPlatformResolverProvider).capabilities;
    if (platform.isMobile) {
      return MobilePrinterSettingsView(embedded: embedded);
    }
    return WindowsPrinterSettingsView(embedded: embedded);
  }
}

class WindowsPrinterSettingsView extends ConsumerStatefulWidget {
  const WindowsPrinterSettingsView({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<WindowsPrinterSettingsView> createState() =>
      _WindowsPrinterSettingsViewState();
}

class _WindowsPrinterSettingsViewState
    extends ConsumerState<WindowsPrinterSettingsView> {
  PrinterSettingsModel? _settings;
  List<Printer> _printers = const [];
  String _preview = '';
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  Timer? _saveDebounce;

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final settings = await ref
          .read(printerSettingsRepositoryProvider)
          .getOrCreate();
      final printers = await ref
          .read(unifiedTicketPrinterProvider)
          .getAvailablePrinters();
      final preview = await ref
          .read(unifiedTicketPrinterProvider)
          .generatePreviewText();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _printers = printers;
        _preview = preview;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(PrinterSettingsModel settings) async {
    _saveDebounce?.cancel();
    setState(() {
      _settings = settings;
      _saving = true;
    });
    await ref.read(printerSettingsRepositoryProvider).updateSettings(settings);
    ref.invalidate(printerSettingsProvider);
    final preview = await ref
        .read(unifiedTicketPrinterProvider)
        .generatePreviewText();
    if (!mounted) return;
    setState(() {
      _preview = preview;
      _saving = false;
    });
  }

  void _queueSave(PrinterSettingsModel settings) {
    setState(() => _settings = settings);
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      unawaited(_save(settings));
    });
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    final result = await ref
        .read(unifiedTicketPrinterProvider)
        .printTestTicket();
    if (!mounted) return;
    setState(() => _testing = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Future<void> _ruler() async {
    setState(() => _testing = true);
    final result = await ref
        .read(unifiedTicketPrinterProvider)
        .printWidthRulerTest();
    if (!mounted) return;
    setState(() => _testing = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  Widget _switch({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(title)),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _body() {
    final settings = _settings;
    if (_loading || settings == null) {
      return const Center(child: Text('Sincronizando impresoras...'));
    }

    final printerNames = _printers.map((p) => p.name).toSet().toList()..sort();
    final selectedName = settings.selectedPrinterName;
    final selectedExists =
        selectedName == null ||
        selectedName.isEmpty ||
        printerNames.contains(selectedName);

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 760;
        final form = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Impresora y ticket',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
                TextButton.icon(
                  onPressed: _settings == null ? null : () => _save(_settings!),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Guardar ahora'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: selectedExists ? selectedName : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Impresora',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: '',
                        child: Text('Usar dialogo del sistema'),
                      ),
                      ...printerNames.map(
                        (name) => DropdownMenuItem<String>(
                          value: name,
                          child: Text(name),
                        ),
                      ),
                    ],
                    onChanged: (value) => _save(
                      settings.copyWith(
                        selectedPrinterName: (value ?? '').trim().isEmpty
                            ? null
                            : value,
                        clearPrinter: (value ?? '').trim().isEmpty,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Actualizar impresoras',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            if (!selectedExists) ...[
              const SizedBox(height: 8),
              Text(
                'La impresora guardada no aparece en el sistema: $selectedName',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 14),
            const Text(
              'Impresora',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 58, label: Text('58 mm')),
                ButtonSegment(value: 80, label: Text('80 mm')),
              ],
              selected: {settings.paperWidthMm},
              onSelectionChanged: (value) {
                final width = value.first;
                _save(
                  settings.copyWith(
                    paperWidthMm: width,
                    charsPerLine: width == 58 ? 32 : 48,
                  ),
                );
              },
            ),
            const SizedBox(height: 14),
            const Text(
              'Logo y negocio',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            _switch(
              title: 'Mostrar logo',
              value: settings.showLogo,
              onChanged: (value) => _save(settings.copyWith(showLogo: value)),
            ),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 40, label: Text('Pequeño')),
                ButtonSegment(value: 70, label: Text('Normal')),
                ButtonSegment(value: 100, label: Text('Grande')),
              ],
              selected: {settings.logoSize},
              onSelectionChanged: (value) =>
                  _save(settings.copyWith(logoSize: value.first)),
            ),
            _switch(
              title: 'Mostrar datos del negocio',
              value: settings.showBusinessData,
              onChanged: (value) =>
                  _save(settings.copyWith(showBusinessData: value)),
            ),
            const SizedBox(height: 14),
            const Text(
              'Tamaño del texto',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: settings.copies.toString(),
                    decoration: const InputDecoration(
                      labelText: 'Copias',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onFieldSubmitted: (value) {
                      final copies = int.tryParse(value) ?? settings.copies;
                      _save(settings.copyWith(copies: copies.clamp(1, 5)));
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: settings.fontSize,
                    decoration: const InputDecoration(
                      labelText: 'Texto',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'small', child: Text('Pequeno')),
                      DropdownMenuItem(value: 'normal', child: Text('Normal')),
                      DropdownMenuItem(value: 'large', child: Text('Grande')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        _save(settings.copyWith(fontSize: value));
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _switch(
              title: 'Auto-imprimir al cobrar',
              value: settings.autoPrintOnPayment,
              onChanged: (value) =>
                  _save(settings.copyWith(autoPrintOnPayment: value)),
            ),
            const SizedBox(height: 8),
            const Text(
              'Formato del ticket',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'compact', label: Text('Compacto')),
                ButtonSegment(value: 'detailed', label: Text('Detallado')),
              ],
              selected: {
                settings.showClient &&
                        settings.showCashier &&
                        settings.showPaymentMethod &&
                        settings.showSubtotalItbisTotal
                    ? 'detailed'
                    : 'compact',
              },
              onSelectionChanged: (value) {
                final detailed = value.first == 'detailed';
                _save(
                  settings.copyWith(
                    showClient: detailed,
                    showCashier: detailed,
                    showPaymentMethod: detailed,
                    showSubtotalItbisTotal: detailed,
                    showDiscounts: detailed,
                    showElectronicInvoiceReference: detailed,
                    showCode: detailed,
                    showDatetime: detailed,
                    showItbis: detailed,
                  ),
                );
              },
            ),
            _switch(
              title: 'Mostrar cliente',
              value: settings.showClient,
              onChanged: (value) => _save(settings.copyWith(showClient: value)),
            ),
            _switch(
              title: 'Mostrar cajero',
              value: settings.showCashier,
              onChanged: (value) =>
                  _save(settings.copyWith(showCashier: value)),
            ),
            _switch(
              title: 'Mostrar metodo de pago',
              value: settings.showPaymentMethod,
              onChanged: (value) =>
                  _save(settings.copyWith(showPaymentMethod: value)),
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: settings.headerExtra,
              decoration: const InputDecoration(
                labelText: 'Encabezado adicional',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              onChanged: (value) =>
                  _queueSave(settings.copyWith(headerExtra: value)),
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: settings.footerMessage,
              decoration: const InputDecoration(
                labelText: 'Mensaje final',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
              onChanged: (value) =>
                  _queueSave(settings.copyWith(footerMessage: value)),
            ),
            const SizedBox(height: 10),
            TextFormField(
              initialValue: settings.warrantyPolicy,
              decoration: const InputDecoration(
                labelText: 'Política de garantía',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
              onChanged: (value) =>
                  _queueSave(settings.copyWith(warrantyPolicy: value)),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print_outlined),
                  label: const Text('Ticket de prueba'),
                ),
                OutlinedButton.icon(
                  onPressed: _testing ? null : _ruler,
                  icon: const Icon(Icons.straighten_outlined),
                  label: const Text('Regla de ancho'),
                ),
              ],
            ),
            if (_saving) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        );

        final preview = SimplifiedTicketPreviewWidget(
          text: _preview,
          paperWidthMm: settings.paperWidthMm,
        );

        if (narrow) {
          return SingleChildScrollView(
            child: Column(
              children: [form, const SizedBox(height: 20), preview],
            ),
          );
        }
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: form),
              const SizedBox(width: 24),
              SizedBox(width: 360, child: preview),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Material(color: Colors.transparent, child: _body());
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Impresora y tickets')),
      body: Padding(padding: const EdgeInsets.all(16), child: _body()),
    );
  }
}

class MobilePrinterSettingsView extends ConsumerStatefulWidget {
  const MobilePrinterSettingsView({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<MobilePrinterSettingsView> createState() =>
      _MobilePrinterSettingsViewState();
}

class _MobilePrinterSettingsViewState
    extends ConsumerState<MobilePrinterSettingsView> {
  final _ip = TextEditingController();
  final _port = TextEditingController();
  final _name = TextEditingController();
  final _footer = TextEditingController();
  List<BluetoothInfo> _bluetoothPrinters = const [];
  bool _busy = false;
  bool _showAllBluetoothDevices = false;

  @override
  void dispose() {
    _ip.dispose();
    _port.dispose();
    _name.dispose();
    _footer.dispose();
    super.dispose();
  }

  void _syncControllers(MobilePrinterSettingsModel settings) {
    if (_ip.text != settings.networkIp) _ip.text = settings.networkIp;
    final port = settings.networkPort.toString();
    if (_port.text != port) _port.text = port;
    if (_name.text != settings.printerName) _name.text = settings.printerName;
    if (_footer.text != settings.footerMessage) {
      _footer.text = settings.footerMessage;
    }
  }

  Future<void> _save(MobilePrinterSettingsModel settings) async {
    await ref.read(mobilePrinterSettingsRepositoryProvider).update(settings);
    ref.invalidate(mobilePrinterSettingsProvider);
  }

  Future<void> _run(Future<MobilePrintServiceResult> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await action();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
      ref.invalidate(mobilePrinterSettingsProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo completar la acción: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testPrint() async {
    await _run(() async {
      final settings = await ref
          .read(mobilePrinterSettingsRepositoryProvider)
          .getOrCreate();
      final company = await ref
          .read(companyInfoRepositoryProvider)
          .getCurrentCompanyInfo();
      final windowsSettings = await ref
          .read(printerSettingsRepositoryProvider)
          .getOrCreate();
      final layout = TicketLayoutConfig.fromPrinterSettings(
        windowsSettings.copyWith(
          paperWidthMm: settings.paperWidthMm,
          charsPerLine: settings.charsPerLine,
          footerMessage: settings.footerMessage,
        ),
      );
      final builder = TicketBuilder(layout: layout, company: company);
      final ticket = TicketData.demo();
      final pdf = await builder.buildPdf(ticket);
      return ref
          .read(mobilePrintServiceProvider)
          .printRaw(
            lines: builder.buildLines(ticket),
            pdfBytes: pdf,
            documentName: 'Ticket de prueba',
          );
    });
  }

  Future<void> _testNetwork(MobilePrinterSettingsModel settings) {
    return _run(
      () =>
          ref.read(mobilePrintServiceProvider).testNetworkConnection(settings),
    );
  }

  String _statusText(MobilePrinterConnectionStatus status) {
    return switch (status) {
      MobilePrinterConnectionStatus.notConfigured => 'No configurada',
      MobilePrinterConnectionStatus.searching => 'Buscando',
      MobilePrinterConnectionStatus.connecting => 'Conectando',
      MobilePrinterConnectionStatus.connected => 'Conectada',
      MobilePrinterConnectionStatus.disconnected => 'Desconectada',
      MobilePrinterConnectionStatus.permissionRequired => 'Permiso requerido',
      MobilePrinterConnectionStatus.unavailable => 'No disponible',
      MobilePrinterConnectionStatus.error => 'Error',
    };
  }

  String _connectionLabel(MobilePrinterConnectionType type) {
    return switch (type) {
      MobilePrinterConnectionType.network => 'Network/LAN',
      MobilePrinterConnectionType.bluetooth => 'Bluetooth',
      MobilePrinterConnectionType.systemPrinter => 'Sistema',
      MobilePrinterConnectionType.pdfOnly => 'PDF',
    };
  }

  Future<void> _scanBluetooth() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final service = ref.read(mobilePrintServiceProvider);
      final permission = await service.ensureBluetoothPermissions();
      if (!permission.success) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(permission.message)));
        return;
      }
      final printers = await service.discoverBluetoothPrinters();
      if (!mounted) return;
      setState(() {
        _bluetoothPrinters = MobilePrintService.sortBluetoothPrinters(printers);
        _showAllBluetoothDevices = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            printers.isEmpty
                ? 'No hay impresoras emparejadas. Empareja la PT-210 con PIN 0000 en Bluetooth de Android.'
                : 'Encontré ${printers.length} dispositivo(s). Te muestro primero las impresoras probables.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo buscar impresoras: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _autoConnectBluetooth(MobilePrinterSettingsModel settings) {
    return _run(() async {
      final service = ref.read(mobilePrintServiceProvider);
      final result = await service.autoConnectBluetoothPrinter(settings);
      final printers = await service.discoverBluetoothPrinters();
      if (mounted) {
        setState(() {
          _bluetoothPrinters = printers;
          _showAllBluetoothDevices = false;
        });
      }
      return result;
    });
  }

  Future<void> _selectBluetoothPrinter(
    MobilePrinterSettingsModel settings,
    BluetoothInfo printer,
  ) async {
    if (_busy) return;
    final selected = settings.copyWith(
      connectionType: MobilePrinterConnectionType.bluetooth,
      printerName: printer.name.trim().isEmpty
          ? 'Impresora Bluetooth'
          : printer.name.trim(),
      bluetoothAddress: printer.macAdress.trim(),
      paperWidthMm:
          printer.name.toLowerCase().contains('pt-210') ||
              printer.name.toLowerCase().contains('pt210') ||
              printer.name.toLowerCase().contains('58')
          ? 58
          : settings.paperWidthMm,
      lastStatus: MobilePrinterConnectionStatus.disconnected,
      clearLastError: true,
    );
    setState(() => _busy = true);
    try {
      await ref
          .read(mobilePrinterSettingsRepositoryProvider)
          .update(
            selected.copyWith(
              lastStatus: MobilePrinterConnectionStatus.connecting,
            ),
          );
      final result = await ref
          .read(mobilePrintServiceProvider)
          .testBluetoothConnection(selected);
      if (!result.success) {
        await ref
            .read(mobilePrinterSettingsRepositoryProvider)
            .update(
              settings.copyWith(
                lastStatus: MobilePrinterConnectionStatus.error,
                lastError: result.message,
              ),
            );
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(result.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _section({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDDE7EF)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF607080), fontSize: 12),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _switch({
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 13)),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _content(MobilePrinterSettingsModel settings) {
    _syncControllers(settings);
    final lastConnected = settings.lastSuccessfulConnectionMs == null
        ? 'Nunca'
        : DateTime.fromMillisecondsSinceEpoch(
            settings.lastSuccessfulConnectionMs!,
          ).toString().split('.').first;
    final isNetwork =
        settings.connectionType == MobilePrinterConnectionType.network;
    final isBluetooth =
        settings.connectionType == MobilePrinterConnectionType.bluetooth;
    final likelyBluetoothPrinters = _bluetoothPrinters
        .where(MobilePrintService.isLikelyBluetoothPrinter)
        .toList(growable: false);
    final visibleBluetoothPrinters = _showAllBluetoothDevices
        ? _bluetoothPrinters
        : likelyBluetoothPrinters;
    final hiddenBluetoothDevices =
        _bluetoothPrinters.length - visibleBluetoothPrinters.length;

    Widget contentColumn() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _section(
            title: 'Estado',
            children: [
              _infoRow(
                'Impresión',
                settings.printingEnabled ? 'Activada' : 'Desactivada',
              ),
              _infoRow(
                'Impresora',
                settings.printerName.trim().isEmpty
                    ? 'Sin seleccionar'
                    : settings.printerName.trim(),
              ),
              _infoRow('Conexión', _connectionLabel(settings.connectionType)),
              _infoRow('Estado', _statusText(settings.lastStatus)),
              _infoRow('Última conexión', lastConnected),
              if ((settings.lastError ?? '').trim().isNotEmpty)
                Text(
                  settings.lastError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          _section(
            title: 'Tipo de conexión',
            children: [
              DropdownButtonFormField<MobilePrinterConnectionType>(
                initialValue: settings.connectionType,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Método',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: MobilePrinterConnectionType.bluetooth,
                    child: Text('Bluetooth ESC/POS'),
                  ),
                  DropdownMenuItem(
                    value: MobilePrinterConnectionType.network,
                    child: Text('LAN ESC/POS'),
                  ),
                  DropdownMenuItem(
                    value: MobilePrinterConnectionType.systemPrinter,
                    child: Text('Sistema / AirPrint'),
                  ),
                  DropdownMenuItem(
                    value: MobilePrinterConnectionType.pdfOnly,
                    child: Text('Solo PDF'),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _save(settings.copyWith(connectionType: value));
                },
              ),
              const SizedBox(height: 8),
              const Text(
                'Bluetooth directo funciona en Android con impresoras ESC/POS emparejadas como PT-210. En iOS usa AirPrint/sistema o PDF.',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
            ],
          ),
          if (isBluetooth)
            _section(
              title: 'Bluetooth rápido',
              children: [
                _infoRow(
                  'Seleccionada',
                  settings.bluetoothAddress.trim().isEmpty
                      ? 'Ninguna'
                      : '${settings.printerName} ${settings.bluetoothAddress}',
                ),
                const Text(
                  'Enciende la impresora y toca Conectar. Si Android pide PIN para PT-210 usa 0000. La app prioriza PT-210, impresoras térmicas, POS, 58 mm y ESC/POS.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _autoConnectBluetooth(settings),
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.bluetooth_connected_rounded),
                        label: const Text('Conectar automáticamente'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _scanBluetooth,
                              icon: const Icon(Icons.bluetooth_searching),
                              label: const Text('Buscar'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _run(
                                      () => ref
                                          .read(mobilePrintServiceProvider)
                                          .testBluetoothConnection(settings),
                                    ),
                              icon: const Icon(Icons.bluetooth_connected),
                              label: const Text('Probar conexión'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _save(
                                settings.copyWith(
                                  printerName: '',
                                  bluetoothAddress: '',
                                  lastStatus: MobilePrinterConnectionStatus
                                      .notConfigured,
                                  clearLastError: true,
                                ),
                              ),
                        icon: const Icon(Icons.link_off_outlined),
                        label: const Text('Olvidar'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_bluetoothPrinters.isEmpty)
                  const Text(
                    'No hay resultados cargados. Toca Conectar o Buscar.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  )
                else if (visibleBluetoothPrinters.isEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'No vi una impresora térmica clara en los dispositivos emparejados.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _showAllBluetoothDevices = true),
                        icon: const Icon(Icons.list_rounded),
                        label: const Text('Ver todos los dispositivos'),
                      ),
                    ],
                  )
                else
                  ...visibleBluetoothPrinters.map((printer) {
                    final selected =
                        printer.macAdress == settings.bluetoothAddress;
                    final score = MobilePrintService.bluetoothPrinterScore(
                      printer,
                    );
                    final name = printer.name.trim().isEmpty
                        ? 'Impresora Bluetooth'
                        : printer.name;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _busy
                            ? null
                            : () => _selectBluetoothPrinter(settings, printer),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Icon(
                                selected
                                    ? Icons.check_circle
                                    : Icons.bluetooth,
                                color: selected
                                    ? const Color(0xFF0B5CFF)
                                    : null,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(name, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${printer.macAdress} · compatibilidad $score',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (selected)
                                const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Text(
                                    'Lista',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                if (!_showAllBluetoothDevices && hiddenBluetoothDevices > 0)
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _showAllBluetoothDevices = true),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: Text(
                      'Ver $hiddenBluetoothDevices dispositivo(s) más',
                    ),
                  ),
              ],
            ),
          if (isNetwork)
            _section(
              title: 'Network/LAN',
              children: [
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Nombre opcional',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (value) =>
                      _save(settings.copyWith(printerName: value)),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _ip,
                  decoration: const InputDecoration(
                    labelText: 'IP de impresora',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onSubmitted: (value) =>
                      _save(settings.copyWith(networkIp: value.trim())),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _port,
                        decoration: const InputDecoration(
                          labelText: 'Puerto',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onSubmitted: (value) => _save(
                          settings.copyWith(
                            networkPort:
                                int.tryParse(value) ?? settings.networkPort,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          labelText: 'Timeout',
                          border: const OutlineInputBorder(),
                          hintText: '${settings.timeoutSeconds}s',
                        ),
                        keyboardType: TextInputType.number,
                        onSubmitted: (value) => _save(
                          settings.copyWith(
                            timeoutSeconds:
                                int.tryParse(value) ?? settings.timeoutSeconds,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _testNetwork(
                              settings.copyWith(
                                printerName: _name.text.trim(),
                                networkIp: _ip.text.trim(),
                                networkPort: int.tryParse(_port.text) ?? 9100,
                              ),
                            ),
                      icon: const Icon(Icons.cable_outlined),
                      label: const Text('Probar conexión'),
                    ),
                    TextButton.icon(
                      onPressed: () => _save(
                        settings.copyWith(
                          printerName: '',
                          networkIp: '',
                          networkPort: 9100,
                          lastStatus:
                              MobilePrinterConnectionStatus.notConfigured,
                          clearLastError: true,
                        ),
                      ),
                      icon: const Icon(Icons.clear_outlined),
                      label: const Text('Limpiar'),
                    ),
                  ],
                ),
              ],
            ),
          _section(
            title: 'Preferencias',
            children: [
              _switch(
                title: 'Habilitar impresión',
                value: settings.printingEnabled,
                onChanged: (value) =>
                    _save(settings.copyWith(printingEnabled: value)),
              ),
              _switch(
                title: 'Auto-imprimir facturas',
                value: settings.autoPrintInvoices,
                onChanged: (value) =>
                    _save(settings.copyWith(autoPrintInvoices: value)),
              ),
              _switch(
                title: 'Auto-imprimir cierre de turno',
                value: settings.autoPrintShiftClosing,
                onChanged: (value) =>
                    _save(settings.copyWith(autoPrintShiftClosing: value)),
              ),
              _switch(
                title: 'Preguntar antes de imprimir',
                value: settings.askBeforePrinting,
                onChanged: (value) =>
                    _save(settings.copyWith(askBeforePrinting: value)),
              ),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 58, label: Text('58 mm')),
                  ButtonSegment(value: 80, label: Text('80 mm')),
                ],
                selected: {settings.paperWidthMm},
                onSelectionChanged: (value) =>
                    _save(settings.copyWith(paperWidthMm: value.first)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _footer,
                decoration: const InputDecoration(
                  labelText: 'Mensaje final',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
                onSubmitted: (value) =>
                    _save(settings.copyWith(footerMessage: value)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: settings.copies.toString(),
                      decoration: const InputDecoration(
                        labelText: 'Copias',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onFieldSubmitted: (value) => _save(
                        settings.copyWith(
                          copies: int.tryParse(value) ?? settings.copies,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: settings.encoding,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Encoding',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'latin1',
                          child: Text('Latin-1'),
                        ),
                        DropdownMenuItem(value: 'cp437', child: Text('CP437')),
                        DropdownMenuItem(value: 'utf8', child: Text('UTF-8')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        _save(settings.copyWith(encoding: value));
                      },
                    ),
                  ),
                ],
              ),
              _switch(
                title: 'Cortar papel',
                value: settings.cutPaper,
                onChanged: (value) => _save(settings.copyWith(cutPaper: value)),
              ),
              _switch(
                title: 'Abrir gaveta',
                value: settings.openCashDrawer,
                onChanged: (value) =>
                    _save(settings.copyWith(openCashDrawer: value)),
              ),
            ],
          ),
          FilledButton.icon(
            onPressed: _busy ? null : _testPrint,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_outlined),
            label: const Text('Ticket de prueba'),
          ),
          SizedBox(height: 24 + MediaQuery.of(context).viewPadding.bottom),
        ],
      );
    }

    if (widget.embedded) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final content = Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: contentColumn(),
          );
          if (!constraints.hasBoundedHeight) return content;
          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: content,
          );
        },
      );
    }

    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              12,
              12,
              12,
              12 + MediaQuery.of(context).viewPadding.bottom,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: contentColumn(),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(mobilePrinterSettingsProvider);
    final body = settings.when(
      data: _content,
      loading: () => const Center(child: Text('Sincronizando impresora...')),
      error: (error, _) => Center(child: Text('No se pudo cargar: $error')),
    );
    if (widget.embedded) {
      return Material(color: Colors.transparent, child: body);
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF6FAFD),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B5CFF),
        foregroundColor: Colors.white,
        title: const Text('Impresora'),
      ),
      body: body,
    );
  }
}
