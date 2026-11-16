import 'package:web/web.dart' as web;

void returnToPublicWebsite() {
  // Astro's session is separate from Flutter token storage and must also end.
  try {
    web.window.sessionStorage.removeItem('fullpos.site.session.v1');
  } catch (_) {
    // Browser storage restrictions must not prevent leaving the signed-out app.
  }
  web.window.location.replace('/');
}
