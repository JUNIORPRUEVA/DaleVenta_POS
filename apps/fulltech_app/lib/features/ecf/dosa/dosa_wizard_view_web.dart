import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'dosa_assistant_config.dart';
import 'dosa_assistant_events.dart';

/// Web/PWA: se monta el Web Component oficial `<dosa-cert-wizard>`.
bool get dosaWizardSupported => true;

int _viewSeq = 0;

/// Monta `<dosa-cert-wizard>` y reenvía sus eventos al llamador.
///
/// Reglas:
/// * El script se carga UNA vez y solo desde `config.scriptUrl`, que la
///   configuración ya validó como origen oficial https.
/// * Solo se aplican los atributos que `componentAttributes` devuelve, es decir,
///   los que el propio componente observa.
/// * Los eventos solo se reenvían si están en la lista blanca; el llamador
///   decidirá si recarga estado, y nunca podrá escribir estado fiscal
///   (`mayMutateFiscalState` es siempre `false`).
Widget buildDosaWizardView({
  required DosaAssistantConfig config,
  required void Function(DosaAssistantEvent) onEvent,
  required double height,
  Key? key,
}) {
  final viewType = 'dosa-cert-wizard-${_viewSeq++}';
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    _ensureScriptLoaded(config.scriptUrl);

    final element = web.document.createElement('dosa-cert-wizard');
    for (final entry in config.componentAttributes.entries) {
      element.setAttribute(entry.key, entry.value);
    }
    final styled = element as web.HTMLElement;
    styled.style.display = 'block';
    styled.style.width = '100%';

    for (final type in DosaAssistantConfig.allowedEvents) {
      element.addEventListener(type, _listener(type, onEvent));
    }
    return element;
  });

  return SizedBox(
    height: height,
    child: HtmlElementView(viewType: viewType, key: key),
  );
}

/// Listener por tipo de evento. `cert:resize` lo gestiona el propio componente
/// para ajustar el iframe, así que aquí se ignora.
JSFunction _listener(String type, void Function(DosaAssistantEvent) onEvent) {
  void handler(web.Event event) {
    if (type == 'cert:resize') return;
    final detail = (event as web.CustomEvent).detail;
    final raw = detail?.dartify();
    final payload = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final parsed = parseDosaAssistantEvent(type: type, payload: payload);
    if (parsed != null) onEvent(parsed);
  }

  return handler.toJS;
}

void _ensureScriptLoaded(String scriptUrl) {
  if (web.document.querySelector('script[data-dosa-cert="1"]') != null) return;
  final script = web.document.createElement('script') as web.HTMLScriptElement;
  script.src = scriptUrl;
  script.setAttribute('data-dosa-cert', '1');
  web.document.head?.append(script);
}
