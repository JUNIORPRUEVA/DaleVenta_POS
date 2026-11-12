import 'assistant_models.dart';

/// Constructor de mensajes del Asistente FullPOS.
///
/// Funciones puras (sin BuildContext, sin red) para poder probarlas con tests
/// unitarios y para que el mismo texto se pueda copiar al portapapeles, previsualizar
/// o enviar por WhatsApp.
///
/// Reglas de privacidad aplicadas al construir el mensaje:
/// - Nunca se incluyen contraseñas, PIN, tokens, claves ni `.env`.
/// - Nunca se incluyen datos de clientes ni importes de ventas.
/// - Solo se agrega la empresa cuando está disponible (nombre comercial público).
class AssistantMessageBuilder {
  const AssistantMessageBuilder._();

  static const String _header = '*SOPORTE FULLPOS CLOUD*';

  /// Mensaje de «Contactar por WhatsApp».
  static String greeting() => 'Hola, necesito asistencia con FullPOS Cloud.';

  /// Mensaje de «Reportar avería».
  static String fault({
    required AssistantSupportModule module,
    required String description,
    String? extra,
    String? companyName,
    String? platformLabel,
    String? appVersion,
  }) {
    return _compose(
      kind: AssistantRequestKind.fault,
      moduleLabel: module.label,
      title: null,
      description: description,
      extra: extra,
      companyName: companyName,
      platformLabel: platformLabel,
      appVersion: appVersion,
    );
  }

  /// Mensaje de «Sugerir mejora».
  static String suggestion({
    required String title,
    required String description,
    String? companyName,
    String? platformLabel,
    String? appVersion,
  }) {
    return _compose(
      kind: AssistantRequestKind.suggestion,
      moduleLabel: null,
      title: title,
      description: description,
      extra: null,
      companyName: companyName,
      platformLabel: platformLabel,
      appVersion: appVersion,
    );
  }

  static String _compose({
    required AssistantRequestKind kind,
    String? moduleLabel,
    String? title,
    required String description,
    String? extra,
    String? companyName,
    String? platformLabel,
    String? appVersion,
  }) {
    final lines = <String>[
      _header,
      'Tipo: ${assistantRequestKindLabel(kind)}',
      if (_clean(companyName).isNotEmpty) 'Empresa: ${_clean(companyName)}',
      if (_clean(moduleLabel).isNotEmpty) 'Módulo: ${_clean(moduleLabel)}',
      if (_clean(title).isNotEmpty) 'Título: ${_clean(title)}',
      'Descripción: ${_clean(description)}',
      if (_clean(extra).isNotEmpty) 'Información adicional: ${_clean(extra)}',
      if (_clean(platformLabel).isNotEmpty)
        'Plataforma: ${_clean(platformLabel)}',
      if (_clean(appVersion).isNotEmpty) 'Versión: ${_clean(appVersion)}',
    ];
    return lines.join('\n');
  }

  /// Normaliza espacios y saltos de línea consecutivos sin recortar el contenido.
  static String _clean(String? value) {
    if (value == null) return '';
    return value
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
