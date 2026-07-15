import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DateRangePickerField extends StatelessWidget {
  final DateTimeRange? value;
  final ValueChanged<DateTimeRange?> onChanged;
  final String label;

  const DateRangePickerField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Rango',
  });

  String _format(DateTime d) => DateFormat('dd/MM/yyyy').format(d);

  @override
  Widget build(BuildContext context) {
    final text = value == null
        ? 'Seleccionar'
        : '${_format(value!.start)} → ${_format(value!.end)}';

    return OutlinedButton.icon(
      onPressed: () async {
        final now = DateTime.now();
        final initial =
            value ??
            DateTimeRange(
              start: DateTime(now.year, now.month, now.day),
              end: DateTime(now.year, now.month, now.day),
            );
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(now.year - 2),
          lastDate: DateTime(now.year + 2),
          initialDateRange: initial,
        );
        onChanged(picked);
      },
      icon: const Icon(Icons.date_range),
      label: Text('$label: $text'),
    );
  }
}
