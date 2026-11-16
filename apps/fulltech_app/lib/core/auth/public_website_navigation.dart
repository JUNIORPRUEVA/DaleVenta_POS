import 'public_website_navigation_stub.dart'
    if (dart.library.js_interop) 'public_website_navigation_web.dart'
    as platform;

/// Full-document navigation is required to leave Flutter and load Astro.
void returnToPublicWebsite() => platform.returnToPublicWebsite();
