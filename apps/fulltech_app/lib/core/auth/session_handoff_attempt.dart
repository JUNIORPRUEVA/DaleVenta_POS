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
