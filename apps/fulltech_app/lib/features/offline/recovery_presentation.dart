import '../../core/errors/api_exception.dart';
import '../../core/errors/user_safe_error_text.dart';
import '../../core/offline/pending_sync_action.dart';

/// Presentation only: never decides whether an operation may be resent.
String recoveryOperationLabel(String type) => switch (type) {
  'cash.open' => 'Apertura de caja',
  'cash.close' => 'Cierre de caja',
  'cash.movement' => 'Movimiento de caja',
  'sales.create' => 'Venta offline',
  'sales.return' => 'Devolución',
  _ => 'Operación pendiente',
};

String recoveryActionMessage(PendingSyncAction action) {
  if (action.status == 'review_resolved') {
    return action.payload['recoveryReviewStatus'] == 'RESOLVED_REGISTERED'
        ? 'Registro comprobado. Evidencia conservada.'
        : 'Revisión finalizada. Evidencia conservada.';
  }
  if (action.status == 'auth_blocked') {
    return 'Inicia sesión con la cuenta original.';
  }
  if (action.status == 'syncing') return 'Enviando. No vuelvas a registrarla.';
  if (action.isAutomaticallyRetryable) {
    return action.status == 'error'
        ? 'Se reintentará automáticamente. No la repitas.'
        : 'Guardada. Se enviará cuando haya conexión.';
  }
  if (action.error ==
      'La sincronización encontró un problema. Tus datos permanecen guardados en este dispositivo.') {
    return 'Operación guardada. Comprueba su registro.';
  }
  return userSafeErrorMessage(
    ApiException(action.error ?? ''),
    fallback: 'El encargado debe revisar esta operación. No la repitas.',
  );
}

String recoveryReviewStatus(Object? value) => switch (value) {
  'RESOLVED_REGISTERED' => 'Registro comprobado',
  'RESOLVED_NOT_PERFORMED' => 'No realizada · decisión del encargado',
  'REVIEWING' => 'En revisión',
  _ => 'Pendiente de revisión',
};

String recoveryMoment(DateTime instant) {
  final local = instant.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
}
