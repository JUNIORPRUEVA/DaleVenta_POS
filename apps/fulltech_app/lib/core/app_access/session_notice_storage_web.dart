import 'package:web/web.dart' as web;

bool readSessionNotice(String key) {
  try {
    return web.window.sessionStorage.getItem(key) == '1';
  } catch (_) {
    return false;
  }
}

void writeSessionNotice(String key) {
  try {
    web.window.sessionStorage.setItem(key, '1');
  } catch (_) {
    // The shared provider still remembers dismissal when storage is blocked.
  }
}
