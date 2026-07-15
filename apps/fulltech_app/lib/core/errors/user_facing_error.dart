import 'api_exception.dart';

class UserFacingError {
  const UserFacingError({
    required this.title,
    required this.message,
    required this.helpText,
    required this.autoRetry,
  });

  final String title;
  final String message;
  final String helpText;
  final bool autoRetry;

  factory UserFacingError.from(Object error) {
    if (error is ApiException) {
      switch (error.type) {
        case ApiErrorType.timeout:
        case ApiErrorType.noInternet:
        case ApiErrorType.dns:
        case ApiErrorType.tls:
        case ApiErrorType.network:
          return const UserFacingError(
            title: 'Estamos reconectando el servicio',
            message:
                'Tuvimos una interrupción temporal de conexión. No te preocupes, estamos intentando restablecerla.',
            helpText:
                'Si tarda unos segundos, mantente en esta pantalla. También puedes reintentar manualmente.',
            autoRetry: true,
          );
        case ApiErrorType.server:
          return const UserFacingError(
            title: 'El servicio está procesando tu solicitud',
            message:
                'La plataforma tuvo una respuesta inesperada del servidor. Vamos a intentar nuevamente automáticamente.',
            helpText:
                'Tu información se mantiene segura. Si persiste, intenta nuevamente en un momento.',
            autoRetry: true,
          );
        case ApiErrorType.unauthorized:
        case ApiErrorType.forbidden:
          return const UserFacingError(
            title: 'Acceso no disponible',
            message: 'No tienes permisos para esta acción en este momento.',
            helpText:
                'Si consideras que esto es un error, contacta a un administrador.',
            autoRetry: false,
          );
        case ApiErrorType.badRequest:
        case ApiErrorType.notFound:
        case ApiErrorType.conflict:
          return const UserFacingError(
            title: 'No se pudo completar la operación',
            message:
                'Recibimos una respuesta inválida para esta consulta específica.',
            helpText: 'Revisa los filtros aplicados y vuelve a intentar.',
            autoRetry: false,
          );
        case ApiErrorType.parse:
        case ApiErrorType.config:
        case ApiErrorType.cancelled:
        case ApiErrorType.unknown:
          return const UserFacingError(
            title: 'Estamos validando la información',
            message: 'No pudimos completar esta carga en este momento.',
            helpText: 'Puedes intentar nuevamente en unos segundos.',
            autoRetry: false,
          );
      }
    }

    return const UserFacingError(
      title: 'Estamos validando la información',
      message: 'No pudimos completar esta carga en este momento.',
      helpText: 'Puedes intentar nuevamente en unos segundos.',
      autoRetry: false,
    );
  }
}
