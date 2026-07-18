import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'external_launcher.dart';

Future<bool> _tryOpenUri(Uri uri) async {
  try {
    final can = await canLaunchUrl(uri);
    if (can) {
      return await launchUrl(uri, mode: _preferredLaunchMode());
    }
  } catch (_) {
    // Fall through.
  }

  try {
    return await openUrlWithOs(uri);
  } catch (_) {
    return false;
  }
}

String? _extractWhatsAppDigits(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'whatsapp') {
    final phone = (uri.queryParameters['phone'] ?? '').trim();
    return phone.isEmpty ? null : phone;
  }

  final host = uri.host.toLowerCase();
  if (host == 'wa.me') {
    final path = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first.trim();
    return path.isEmpty ? null : path;
  }

  if (host.contains('whatsapp.com')) {
    final phone = (uri.queryParameters['phone'] ?? '').trim();
    return phone.isEmpty ? null : phone;
  }

  return null;
}

LaunchMode _preferredLaunchMode() {
  if (kIsWeb) return LaunchMode.platformDefault;

  final platform = defaultTargetPlatform;
  final isDesktop =
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux ||
      platform == TargetPlatform.macOS;

  return isDesktop
      ? LaunchMode.externalApplication
      : LaunchMode.platformDefault;
}

Future<void> safeOpenUrl(
  BuildContext context,
  Uri uri, {
  String copiedMessage = 'Link copiado',
}) async {
  final opened = await _tryOpenUri(uri);

  if (opened) return;

  try {
    await Clipboard.setData(ClipboardData(text: uri.toString()));
  } catch (_) {
    // ignore
  }

  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(copiedMessage)));
}

Future<void> safeOpenWhatsApp(
  BuildContext context,
  Uri uri, {
  String copiedMessage = 'No se pudo abrir WhatsApp. Enlace copiado.',
}) async {
  final digits = _extractWhatsAppDigits(uri);
  if (digits != null && digits.isNotEmpty) {
    final text = (uri.queryParameters['text'] ?? '').trim();
    final appUri = Uri(
      scheme: 'whatsapp',
      host: 'send',
      queryParameters: {'phone': digits, if (text.isNotEmpty) 'text': text},
    );
    if (await _tryOpenUri(appUri)) {
      return;
    }

    final webUri = Uri.https('wa.me', '/$digits', {
      if (text.isNotEmpty) 'text': text,
    });
    if (await _tryOpenUri(webUri)) {
      return;
    }
  }

  if (!context.mounted) return;
  await safeOpenUrl(context, uri, copiedMessage: copiedMessage);
}
