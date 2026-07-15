import 'dart:io';

Future<bool> openUrlWithOs(Uri uri) async {
  if (!Platform.isWindows) return false;

  try {
    final url = uri.toString();

    // Most reliable on Windows: uses the default browser without cmd parsing.
    final e = await Process.run('explorer.exe', [url], runInShell: true);
    if (e.exitCode == 0) return true;

    // Preferred: avoids cmd parsing issues with '&' in query strings.
    final r = await Process.run('rundll32', [
      'url.dll,FileProtocolHandler',
      url,
    ], runInShell: true);
    if (r.exitCode == 0) return true;

    // Fallback: cmd start with proper quoting.
    // Escape '&' because cmd treats it as a command separator.
    final cmdUrl = url.replaceAll('&', '^&');
    final result = await Process.run('cmd', [
      '/c',
      'start',
      '""',
      cmdUrl,
    ], runInShell: true);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}
