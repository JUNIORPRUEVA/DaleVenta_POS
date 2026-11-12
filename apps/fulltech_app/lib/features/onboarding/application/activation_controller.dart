import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../data/activation_models.dart';
import '../data/activation_repository.dart';

/// Estado del onboarding de activación «Activa tu FullPOS».
///
/// Se apoya en el backend como única fuente de verdad: cada mutación devuelve
/// el estado ya recalculado, de modo que el cliente nunca inventa progreso.
class ActivationController extends AsyncNotifier<ActivationState?> {
  @override
  Future<ActivationState?> build() async {
    final auth = ref.watch(authStateProvider);
    if (!auth.isAuthenticated) return null;
    return ref.read(activationRepositoryProvider).getState();
  }

  /// Vuelve a pedir el estado. Útil tras crear un producto o cerrar una venta.
  Future<void> refresh() async {
    final auth = ref.read(authStateProvider);
    if (!auth.isAuthenticated) {
      state = const AsyncValue.data(null);
      return;
    }
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(activationRepositoryProvider).getState(),
    );
  }

  Future<void> markWelcomeSeen() =>
      _mutate(() => ref.read(activationRepositoryProvider).markWelcomeSeen());

  Future<void> dismiss() =>
      _mutate(() => ref.read(activationRepositoryProvider).dismiss());

  Future<void> reopen() =>
      _mutate(() => ref.read(activationRepositoryProvider).reopen());

  Future<void> skipTask(String key) =>
      _mutate(() => ref.read(activationRepositoryProvider).skipTask(key));

  Future<void> restoreTask(String key) =>
      _mutate(() => ref.read(activationRepositoryProvider).restoreTask(key));

  Future<void> setTourStep(String key, int step) =>
      _mutate(() => ref.read(activationRepositoryProvider).setTourStep(key, step));

  /// Ejecuta una mutación y adopta el estado devuelto por el servidor.
  /// Los errores no rompen la pantalla: se conserva el estado anterior.
  Future<void> _mutate(Future<ActivationState> Function() action) async {
    final previous = state;
    try {
      final next = await action();
      state = AsyncValue.data(next);
    } catch (error, stack) {
      state = previous.hasValue
          ? AsyncValue.data(previous.value)
          : AsyncValue.error(error, stack);
    }
  }
}

final activationControllerProvider =
    AsyncNotifierProvider<ActivationController, ActivationState?>(
      ActivationController.new,
    );

/// Panel abierto/cerrado. Vive en memoria: el estado persistido solo decide si
/// se abre solo una vez tras el primer inicio de sesión.
final activationPanelOpenProvider = StateProvider<bool>((ref) => false);

/// Recorrido guiado activo (clave de tarea) o `null` si no hay ninguno.
final activationTourProvider = StateProvider<String?>((ref) => null);

/// Ruta desde la que el usuario abrió una pantalla usando el asistente.
///
/// El asistente se cierra para dejar trabajar y se reabre **solo** cuando el
/// usuario vuelve a esa misma ruta (p. ej. con «Regresar»), sin perder avance.
final activationReturnRouteProvider = StateProvider<String?>((ref) => null);

/// `true` cuando la navegación desde el asistente ya se completó.
///
/// Evita que el panel se reabra en el mismo instante en que se cierra: hasta
/// que la ruta de destino no esté activa, el retorno no se considera.
final activationReturnArmedProvider = StateProvider<bool>((ref) => false);
