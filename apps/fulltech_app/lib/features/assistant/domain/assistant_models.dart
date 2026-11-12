import 'package:flutter/foundation.dart';

/// Tipo de solicitud de soporte que el usuario puede preparar.
///
/// No crea tickets ni persiste nada: solo describe el mensaje que se enviará
/// por WhatsApp. La fase de tickets internos (backend) es posterior.
enum AssistantRequestKind { fault, suggestion }

/// Etiqueta legible del tipo de solicitud dentro del mensaje.
String assistantRequestKindLabel(AssistantRequestKind kind) {
  switch (kind) {
    case AssistantRequestKind.fault:
      return 'Avería';
    case AssistantRequestKind.suggestion:
      return 'Sugerencia de mejora';
  }
}

/// Módulos reales del sistema que el usuario puede elegir al reportar.
///
/// Las etiquetas coinciden con módulos que existen en la app (Ventas/Facturación,
/// Usuarios, Inventario, Caja, Compras, configuraciones). No se exponen
/// identificadores internos ni claves de base de datos.
enum AssistantSupportModule {
  billing,
  users,
  inventory,
  cash,
  purchases,
  printer,
  other,
}

extension AssistantSupportModuleLabel on AssistantSupportModule {
  String get label {
    switch (this) {
      case AssistantSupportModule.billing:
        return 'Ventas / Facturación';
      case AssistantSupportModule.users:
        return 'Usuarios y permisos';
      case AssistantSupportModule.inventory:
        return 'Inventario y productos';
      case AssistantSupportModule.cash:
        return 'Caja y turnos';
      case AssistantSupportModule.purchases:
        return 'Compras y proveedores';
      case AssistantSupportModule.printer:
        return 'Impresora y tickets';
      case AssistantSupportModule.other:
        return 'Otro / no estoy seguro';
    }
  }
}

/// Nombre de la plataforma en la que corre la app, para adjuntarlo al reporte.
///
/// Usa `defaultTargetPlatform` + `kIsWeb`; no depende de plugins ni de permisos.
String assistantPlatformLabel() {
  if (kIsWeb) return 'Web / PWA';
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
      return 'Windows';
    case TargetPlatform.android:
      return 'Android';
    case TargetPlatform.iOS:
      return 'iPhone / iPad';
    case TargetPlatform.macOS:
      return 'macOS';
    case TargetPlatform.linux:
      return 'Linux';
    case TargetPlatform.fuchsia:
      return 'Fuchsia';
  }
}

/// Datos de contexto que se adjuntan al mensaje (nunca datos sensibles).
class AssistantMessageContext {
  const AssistantMessageContext({
    this.companyName,
    this.platformLabel,
    this.appVersion,
  });

  final String? companyName;
  final String? platformLabel;
  final String? appVersion;
}
