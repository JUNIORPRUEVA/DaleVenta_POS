// Presentation only: never changes persisted IDs, names or commercial codes.
final _internalIdentifiers = RegExp(
  r'\b(?:[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|[0-9a-fA-F]{24}|[0-9A-HJKMNP-TV-Z]{26}|c[a-z0-9]{20,31}|[a-z]{24,})\b',
);

String customerVisibleText(String value, {String fallback = ''}) {
  final text = value
      .replaceAll(_internalIdentifiers, '')
      .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
      .trim();
  return text.isEmpty ? fallback : text;
}
