import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// `true` mientras Flutter está ejecutando la fase de build de widgets
/// (`SchedulerPhase.persistentCallbacks`).
bool isFlutterBuildPhase() =>
    SchedulerBinding.instance.schedulerPhase ==
    SchedulerPhase.persistentCallbacks;

/// Ejecuta [action] de inmediato, salvo que la app esté en fase de build: en
/// ese caso la difiere al final del frame actual (post-frame).
///
/// Motivo (defecto reproducido en Account Settings / AppDrawer):
///
/// - El framework invoca callbacks durante el build. En particular,
///   `RouteObserver.subscribe()` — llamado desde `didChangeDependencies()` —
///   ejecuta `RouteAware.didPush()` de forma **sincrónica** y dentro de la fase
///   de build.
/// - Riverpod resuelve un provider invalidado de forma sincrónica en el primer
///   `ref.watch`/`ref.read` (`ProviderElementBase.readSelf` → `flush`) y
///   notifica a TODOS sus listeners en ese mismo instante.
/// - Si esa invalidación ocurre durante el build, el primer `ref.watch` que lea
///   el provider lo reconstruye y marca como "necesita build" a widgets que no
///   son descendientes del widget que está leyendo → Flutter lanza
///   `setState() or markNeedsBuild() called during build`.
///
/// Por eso ningún efecto que mute estado de Riverpod debe ejecutarse en fase de
/// build: se difiere al final del frame, donde el árbol ya está consistente.
void runOutsideBuildPhase(VoidCallback action) {
  if (isFlutterBuildPhase()) {
    WidgetsBinding.instance.addPostFrameCallback((_) => action());
    return;
  }
  action();
}
