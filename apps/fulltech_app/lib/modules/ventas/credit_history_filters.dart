import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/time/business_time.dart';
import '../../core/widgets/history_filter_panel.dart';
import 'sales_models.dart';

class CreditHistoryFilters {
  const CreditHistoryFilters({
    this.from,
    this.to,
    this.cashier,
    this.status = 0,
  });
  final DateTime? from, to;
  final String? cashier;
  final int status;
  bool matches(SaleModel sale) {
    if (status == 1 && sale.creditBalance <= .009) return false;
    if (status == 2 && sale.creditBalance > .009) return false;
    if (cashier != null && (sale.userName ?? sale.userId) != cashier) {
      return false;
    }
    if (from != null || to != null) {
      if (sale.saleDate == null) return false;
      final date = toBusinessTime(sale.saleDate!);
      final day = DateTime(date.year, date.month, date.day);
      if (from != null && day.isBefore(from!)) return false;
      if (to != null && day.isAfter(to!)) return false;
    }
    return true;
  }
}

class CreditHistoryFilterPanel extends StatefulWidget {
  const CreditHistoryFilterPanel({
    super.key,
    required this.initial,
    required this.cashiers,
  });
  final CreditHistoryFilters initial;
  final List<String> cashiers;
  @override
  State<CreditHistoryFilterPanel> createState() =>
      _CreditHistoryFilterPanelState();
}

class _CreditHistoryFilterPanelState extends State<CreditHistoryFilterPanel> {
  late DateTime? from = widget.initial.from, to = widget.initial.to;
  late String? cashier = widget.initial.cashier;
  late int status = widget.initial.status;
  int quick = 2;
  Widget section(String title) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Text(
      title,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
    ),
  );
  Future<void> pick(bool start) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: (start ? from : to) ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 2),
      locale: const Locale('es', 'DO'),
    );
    if (date == null || !mounted) return;
    setState(() {
      quick = 2;
      if (start) {
        from = date;
        if (to != null && to!.isBefore(date)) to = date;
      } else {
        to = date;
        if (from != null && from!.isAfter(date)) from = date;
      }
    });
  }

  @override
  Widget build(BuildContext context) => HistoryFilterPanel(
    title: 'Filtros de créditos',
    subtitle: 'Rango, estado y cajero · créditos cargados',
    onApply: () => Navigator.pop(
      context,
      CreditHistoryFilters(
        from: from,
        to: to,
        cashier: cashier,
        status: status,
      ),
    ),
    children: [
      section('Intervalo de fecha'),
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('Hoy')),
          ButtonSegment(value: 1, label: Text('Ayer')),
          ButtonSegment(value: 2, label: Text('Rango', maxLines: 1)),
        ],
        selected: {quick},
        onSelectionChanged: (values) => setState(() {
          quick = values.first;
          if (quick != 2) {
            final now = DateTime.now();
            from = DateTime(
              now.year,
              now.month,
              now.day,
            ).subtract(Duration(days: quick));
            to = from;
          }
        }),
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
          textStyle: WidgetStatePropertyAll(
            Theme.of(context).textTheme.labelMedium!.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(child: dateButton('Desde', from, () => pick(true))),
          const SizedBox(width: 8),
          Expanded(child: dateButton('Hasta', to, () => pick(false))),
        ],
      ),
      section('Estado'),
      DropdownButtonFormField<int>(
        key: ValueKey('credit-status-$status'),
        initialValue: status,
        decoration: historyFilterInputDecoration('Estado'),
        items: const [
          DropdownMenuItem(value: 0, child: Text('Todos los créditos')),
          DropdownMenuItem(value: 1, child: Text('Pendientes')),
          DropdownMenuItem(value: 2, child: Text('Saldados')),
        ],
        onChanged: (value) => setState(() => status = value ?? 0),
      ),
      section('Cajero'),
      DropdownButtonFormField<String>(
        key: ValueKey('credit-cashier-$cashier'),
        initialValue: cashier ?? '',
        isExpanded: true,
        decoration: historyFilterInputDecoration('Cajero'),
        items: [
          const DropdownMenuItem(value: '', child: Text('Todos los cajeros')),
          for (final name in widget.cashiers)
            DropdownMenuItem(
              value: name,
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (value) =>
            setState(() => cashier = value == '' ? null : value),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => setState(() {
            from = null;
            to = null;
            cashier = null;
            status = 0;
            quick = 2;
          }),
          child: const Text('Limpiar filtros'),
        ),
      ),
    ],
  );
  Widget dateButton(String label, DateTime? date, VoidCallback onTap) =>
      OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          backgroundColor: const Color(0xFFF0F5FA),
          padding: const EdgeInsets.all(10),
          minimumSize: const Size(0, 58),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 11)),
                  Text(
                    date == null
                        ? 'Sin límite'
                        : DateFormat('dd/MM/yyyy').format(date),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.calendar_month, size: 16),
          ],
        ),
      );
}
