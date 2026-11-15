import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/product_config.dart';
import 'app_feedback.dart';

/// Account creation has a single public entry point, outside the native apps.
Future<void> openWebRegistration(BuildContext context) async {
  final uri = Uri.parse(ProductConfig.productionRegistrationUrl);
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    // Offer a usable alternative when the OS has no browser available.
  }
  var copied = false;
  try {
    await Clipboard.setData(ClipboardData(text: uri.toString()));
    copied = true;
  } catch (_) {
    // The URL remains readable even when clipboard access is unavailable.
  }
  if (!context.mounted) return;
  AppFeedback.showPersistentNotification(
    context,
    AppFeedbackNotification(
      title: 'Abre el registro en tu navegador',
      body: copied
          ? 'Copiamos el enlace para crear tu cuenta. Pégalo en la barra de direcciones.'
          : ProductConfig.productionRegistrationUrl,
      compact: true,
      paragraph: true,
    ),
    scope: 'WebRegistration',
  );
}
