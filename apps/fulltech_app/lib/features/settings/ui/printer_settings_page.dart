import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../core/printing/simplified_ticket_preview_widget.dart';
import '../../../core/printing/unified_ticket_printer.dart';
import '../data/printer_settings_model.dart';
import '../data/printer_settings_repository.dart';

class PrinterSettingsPage extends ConsumerStatefulWidget {
  const PrinterSettingsPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  ConsumerState<PrinterSettingsPage> createState() =>
      _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends ConsumerState<PrinterSettingsPage> {
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
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
    );
  }

  Widget _body() {
    final settings = _settings;
    if (_loading || settings == null) {
      return const Center(child: CircularProgressIndicator());
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
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: form),
            const SizedBox(width: 24),
            SizedBox(width: 360, child: preview),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _body();
    return Scaffold(
      appBar: AppBar(title: const Text('Impresora y tickets')),
      body: Padding(padding: const EdgeInsets.all(16), child: _body()),
    );
  }
}
