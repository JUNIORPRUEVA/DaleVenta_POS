/// Removes the one-use ticket without retaining it in browser history.
String sessionHandoffCleanPath(Uri base) {
  final kept = Map<String, String>.from(base.queryParameters)..remove('handoff');
  // Uri.replace(queryParameters: null) RETAINS the original query. Explicitly
  // clear it when the ticket was the only parameter, so updates/reloads cannot
  // replay an already consumed ticket.
  final cleaned = kept.isEmpty
      ? base.replace(query: '')
      : base.replace(queryParameters: kept);
  return '${cleaned.path}${cleaned.query.isEmpty ? '' : '?${cleaned.query}'}'
      '${cleaned.hasFragment ? '#${cleaned.fragment}' : ''}';
}

/// A one-use ticket must never be retried after an uncertain exchange. Keep
/// partial or previous identities out of the app if preparation fails.
Future<bool> completeSessionHandoff({
  required void Function() stripTicket,
  required Future<void> Function() clearSession,
  required Future<void> Function() exchange,
  required Future<bool> Function() sessionIsStored,
}) async {
  stripTicket();
  try {
    await clearSession();
    await exchange();
    if (!await sessionIsStored()) throw StateError('Session was not stored');
    return true;
  } catch (_) {
    try { await clearSession(); } catch (_) { /* Still return to public login. */ }
    return false;
  }
}
