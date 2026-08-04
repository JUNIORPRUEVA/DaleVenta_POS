import 'package:intl/intl.dart';

class ReceiptTextUtils {
  static final NumberFormat _moneyFormat = NumberFormat('#,##0.00', 'en_US');

  static String money(double value) => 'RD\$ ${_moneyFormat.format(value)}';

  static String qty(double value) {
    if (value == value.truncateToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  static String center(String value, int width) {
    final text = _clean(value);
    if (text.length >= width) return text;
    final left = ((width - text.length) / 2).floor();
    return '${' ' * left}$text';
  }

  static String leftRight(String left, String right, int width) {
    final l = _clean(left);
    final r = _clean(right);
    if (l.length + r.length + 1 > width) {
      final maxLeft = (width - r.length - 1).clamp(0, width);
      return '${truncate(l, maxLeft)} $r';
    }
    return '$l${' ' * (width - l.length - r.length)}$r';
  }

  static String truncate(String value, int width) {
    final text = _clean(value);
    if (text.length <= width) return text;
    if (width <= 1) return text.substring(0, width.clamp(0, text.length));
    return text.substring(0, width - 1);
  }

  static List<String> wrap(String value, int width) {
    final text = _clean(value);
    if (text.isEmpty) return const [''];
    final words = text.split(RegExp(r'\s+'));
    final lines = <String>[];
    var line = '';
    for (final word in words) {
      if (line.isEmpty) {
        line = word;
      } else if ('$line $word'.length <= width) {
        line = '$line $word';
      } else {
        lines.add(line);
        line = word;
      }
      while (line.length > width) {
        lines.add(line.substring(0, width));
        line = line.substring(width);
      }
    }
    if (line.isNotEmpty) lines.add(line);
    return lines;
  }

  static String separator(int width, String style) {
    final char = switch (style) {
      'double' => '=',
      'dotted' => '.',
      'dashed' => '-',
      _ => '-',
    };
    return char * width;
  }

  static String right(String value, int width) {
    final text = _clean(value);
    if (text.length >= width) return truncate(text, width);
    return '${' ' * (width - text.length)}$text';
  }

  static String align(String value, int width, String alignment) {
    final text = _clean(value);
    if (text.length >= width) return truncate(text, width);
    switch (alignment) {
      case 'right':
        return right(text, width);
      case 'center':
        return center(text, width);
      default:
        return text;
    }
  }

  static String _clean(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
