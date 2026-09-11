import 'package:flutter/foundation.dart';

/// Compile-time switch for internal diagnostic UI.
///
/// Diagnostic UI exposes technical information (raw exception text, endpoints,
/// stack traces, "copy report" actions). It MUST stay disabled for end users.
///
/// Because this is a `const`, release builds tree-shake the diagnostic widgets
/// and their strings, so no technical text is compiled into the customer app.
///
/// Authorized field diagnostics can enable it explicitly:
/// `flutter run --dart-define=FULLPOS_DIAGNOSTICS_UI=true`
const bool kAppDiagnosticsUiEnabled =
    kDebugMode || bool.fromEnvironment('FULLPOS_DIAGNOSTICS_UI');
