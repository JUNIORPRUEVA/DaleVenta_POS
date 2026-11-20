import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Cuantas pantallas de **Planes** hay montadas ahora mismo.
///
/// Lo enciende `PlansShell` al abrirse y lo apaga al cerrarse. La capa de
/// licencia vencida se aparta mientras el contador sea mayor que cero, para que
/// el cliente pueda ver la pantalla de pago, generar la orden y subir el
/// comprobante, y **vuelve sola al salir** (sin depender de la ruta, de un
/// `Future` de navegacion ni de banderas que puedan quedarse encendidas).
final plansOpenCountProvider = StateProvider<int>((ref) => 0);
