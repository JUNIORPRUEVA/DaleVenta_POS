import 'api_exception.dart';

/// Central classification for every user-visible incident.
///
/// The technical cause is classified once, and the presentation layer only
/// consumes the resulting human message. This keeps backend URLs, status
/// codes, stack traces, and library names out of the customer UI.
enum AppErrorKind {
  network,
  timeout,
  auth,
  permission,
  notFound,
  validation,
  conflict,
  server,
  media,
  printing,
  sync,
  unknown,
}

/// Human, non-technical description of an incident.
///
/// Rules:
/// - [title] and [message] are short, human, and free of technical details.
/// - [silent] incidents are recorded for diagnostics but never shown to the
///   user (for example a missing product thumbnail).
class UserFacingError {
  const UserFacingError({
    required this.title,
    required this.message,
    required this.helpText,
    required this.autoRetry,
    this.kind = AppErrorKind.unknown,
    this.silent = false,
    this.recoverable = true,
    this.retryable = false,
    this.actionLabel,
  });

  final String title;
  final String message;
  final String helpText;
  final bool autoRetry;
  final AppErrorKind kind;

  /// When true the incident must never produce a notification.
  final bool silent;

  /// When false the user cannot continue and needs a blocking resolution.
  final bool recoverable;

  /// When true the presenter may offer a "Reintentar" action.
  final bool retryable;

  /// Optional label for the retry action.
  final String? actionLabel;

  static const UserFacingError _network = UserFacingError(
    title: 'Sin conexión',
    message: 'No pudimos conectarnos al servidor. Revisa tu conexión.',
    helpText: 'Puedes reintentar cuando recuperes la señal.',
    autoRetry: true,
    kind: AppErrorKind.network,
    retryable: true,
  );

  static const UserFacingError _timeout = UserFacingError(
    title: 'El servidor tardó demasiado',
    message: 'No pudimos completar la operación a tiempo.',
    helpText: 'Inténtalo nuevamente en unos segundos.',
    autoRetry: true,
    kind: AppErrorKind.timeout,
    retryable: true,
  );

  static const UserFacingError _auth = UserFacingError(
    title: 'Sesión expirada',
    message: 'Tu sesión expiró. Inicia sesión nuevamente.',
    helpText: 'Vuelve a entrar para continuar donde estabas.',
    autoRetry: false,
    kind: AppErrorKind.auth,
    recoverable: false,
  );

  static const UserFacingError _permission = UserFacingError(
    title: 'Acción no permitida',
    message: 'No tienes permiso para realizar esta acción.',
    helpText: 'Solicita autorización a un administrador.',
    autoRetry: false,
    kind: AppErrorKind.permission,
  );

  static const UserFacingError _notFound = UserFacingError(
    title: 'Información no disponible',
    message: 'No encontramos la información solicitada.',
    helpText: 'Actualiza la pantalla e inténtalo nuevamente.',
    autoRetry: false,
    kind: AppErrorKind.notFound,
  );

  static const UserFacingError _validation = UserFacingError(
    title: 'Revisa la información',
    message: 'Algunos datos no son válidos para completar esta operación.',
    helpText: 'Corrige lo indicado e inténtalo nuevamente.',
    autoRetry: false,
    kind: AppErrorKind.validation,
  );

  static const UserFacingError _conflict = UserFacingError(
    title: 'La información cambió',
    message: 'Esta operación ya no es válida con los datos actuales.',
    helpText: 'Actualiza la pantalla y vuelve a intentarlo.',
    autoRetry: false,
    kind: AppErrorKind.conflict,
  );

  static const UserFacingError _server = UserFacingError(
    title: 'No pudimos completar la operación',
    message: 'Ocurrió un problema en el servidor. Inténtalo nuevamente.',
    helpText: 'Si persiste, inténtalo en unos minutos.',
    autoRetry: true,
    kind: AppErrorKind.server,
    retryable: true,
  );

  static const UserFacingError _media = UserFacingError(
    title: 'Imagen no disponible',
    message: 'No pudimos cargar esta imagen.',
    helpText: '',
    autoRetry: false,
    kind: AppErrorKind.media,
    silent: true,
  );

  static const UserFacingError _unknown = UserFacingError(
    title: 'No pudimos completar la operación',
    message: 'Inténtalo nuevamente en unos segundos.',
    helpText: 'Tu información se mantiene segura.',
    autoRetry: false,
    kind: AppErrorKind.unknown,
    retryable: true,
  );

  /// Maps a technical error into a safe, human-facing description.
  ///
  /// The technical cause is preserved in logs/diagnostics, never here.
  factory UserFacingError.from(Object error) {
    if (error is ApiException) {
      switch (error.type) {
        case ApiErrorType.noInternet:
        case ApiErrorType.dns:
        case ApiErrorType.network:
        case ApiErrorType.tls:
          return _network;
        case ApiErrorType.timeout:
          return _timeout;
        case ApiErrorType.unauthorized:
          return _auth;
        case ApiErrorType.forbidden:
          return _permission;
        case ApiErrorType.notFound:
          return _notFound;
        case ApiErrorType.badRequest:
          return _validation;
        case ApiErrorType.conflict:
          return _conflict;
        case ApiErrorType.server:
          return _server;
        case ApiErrorType.parse:
        case ApiErrorType.config:
        case ApiErrorType.cancelled:
        case ApiErrorType.unknown:
          return _unknown;
      }
    }

    return _unknown;
  }

  /// Media returned by the API (product photos, avatars, logos, evidence).
  static UserFacingError media() => _media;

  /// A printable document failed after the operation was already saved.
  static UserFacingError printing() => const UserFacingError(
    title: 'No se pudo imprimir el comprobante',
    message: 'La operación se guardó correctamente.',
    helpText: 'Puedes reintentar la impresión sin repetir la operación.',
    autoRetry: false,
    kind: AppErrorKind.printing,
    retryable: true,
  );

  /// Background synchronization issue. Never blocking.
  static UserFacingError sync() => const UserFacingError(
    title: 'Sincronización pendiente',
    message: 'Seguiremos intentando sincronizar en segundo plano.',
    helpText: 'Puedes continuar trabajando con normalidad.',
    autoRetry: true,
    kind: AppErrorKind.sync,
  );
}
