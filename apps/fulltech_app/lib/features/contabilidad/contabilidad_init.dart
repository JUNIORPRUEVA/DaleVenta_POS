import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Llama esto en main() antes de runApp para evitar LocaleDataException.
Future<void>? _contabilidadLocaleFuture;

Future<void> ensureContabilidadLocale({String? locale}) {
  _contabilidadLocaleFuture ??= _initializeContabilidadLocale(locale);
  return _contabilidadLocaleFuture!;
}

Future<void> _initializeContabilidadLocale(String? locale) async {
  final candidates = <String>{..._localeCandidates(locale), 'es_DO', 'es'};
  Intl.defaultLocale = _preferredLocale(candidates);

  for (final candidate in candidates) {
    try {
      await initializeDateFormatting(candidate);
    } on Object {
      // Browser/headless environments may report non-Intl locales such as
      // "C" or "C.UTF-8". Ignore them and keep the supported fallbacks.
    }
  }
}

Iterable<String> _localeCandidates(String? rawLocale) sync* {
  final normalized = (rawLocale ?? '').trim().replaceAll('-', '_');
  if (!_isSupportedLocaleShape(normalized)) return;

  yield normalized;

  final separator = normalized.indexOf('_');
  if (separator > 0) {
    final languageCode = normalized.substring(0, separator).trim();
    if (_isSupportedLocaleShape(languageCode)) {
      yield languageCode;
    }
  }
}

bool _isSupportedLocaleShape(String value) {
  return RegExp(r'^[A-Za-z]{2,3}(_[A-Za-z]{2})?$').hasMatch(value);
}

String _preferredLocale(Set<String> candidates) {
  for (final candidate in candidates) {
    if (candidate.toLowerCase() == 'es_do') return candidate;
  }

  for (final candidate in candidates) {
    if (candidate.toLowerCase().startsWith('es')) return candidate;
  }

  return 'es_DO';
}
