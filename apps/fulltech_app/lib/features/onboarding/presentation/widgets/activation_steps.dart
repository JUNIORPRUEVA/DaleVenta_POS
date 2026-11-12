import 'package:flutter/material.dart';

import '../../data/activation_models.dart';

/// Un apartado del asistente «Activa tu FullPOS».
///
/// El backend declara tareas sueltas (productos, venta, datos, impuestos, logo,
/// e-CF). El cliente las agrupa en cinco apartados para que el usuario lea el
/// plan completo de una vez, sin información repetida y sin sentir que la
/// facturación electrónica es obligatoria.
@immutable
class ActivationStepGroup {
  const ActivationStepGroup({
    required this.key,
    required this.number,
    required this.title,
    required this.summary,
    required this.icon,
    required this.tasks,
    this.optional = false,
    this.completionKey,
  });

  final String key;
  final int number;
  final String title;

  /// Una línea que explica para qué sirve el apartado.
  final String summary;
  final IconData icon;
  final List<ActivationTask> tasks;

  /// El apartado se puede dejar para después sin bloquear el uso del POS.
  final bool optional;

  /// Tarea que decide si el apartado está completado.
  ///
  /// «Datos de tu empresa» se da por hecho en cuanto los datos del negocio están
  /// guardados; el logo y los impuestos se recomiendan, pero no lo bloquean.
  final String? completionKey;

  bool get isDone {
    final key = completionKey;
    if (key == null) return tasks.every((task) => task.isDone);
    for (final task in tasks) {
      if (task.key == key) return task.isDone;
    }
    return tasks.every((task) => task.isDone);
  }

  bool get isPending {
    final key = completionKey;
    if (key == null) return tasks.any((task) => task.isPending);
    for (final task in tasks) {
      if (task.key == key) return task.isPending;
    }
    return tasks.any((task) => task.isPending);
  }

  int get doneCount => tasks.where((task) => task.isDone).length;

  ActivationStepGroup withNumber(int value) => ActivationStepGroup(
    key: key,
    number: value,
    title: title,
    summary: summary,
    icon: icon,
    tasks: tasks,
    optional: optional,
    completionKey: completionKey,
  );
}

/// Los cinco apartados, construidos a partir de las tareas reales.
///
/// `business`, `taxes` y `tickets` comparten un solo apartado porque describen
/// lo mismo: los datos y la identidad de la empresa.
List<ActivationStepGroup> activationStepGroups(ActivationState state) {
  final byKey = <String, ActivationTask>{
    for (final task in state.tasks) task.key: task,
  };
  List<ActivationTask> pick(List<String> keys) => <ActivationTask>[
    for (final key in keys)
      if (byKey[key] != null) byKey[key]!,
  ];

  final groups = <ActivationStepGroup>[
    ActivationStepGroup(
      key: 'account',
      number: 1,
      title: 'Crea tu cuenta',
      summary: 'Tu acceso ya está listo desde el primer inicio de sesión.',
      icon: Icons.person_outline_rounded,
      tasks: pick(const ['account']),
    ),
    ActivationStepGroup(
      key: 'products',
      number: 2,
      title: 'Registra tus productos',
      summary: 'Con tu catálogo cargado, cobrar una venta toma segundos.',
      icon: Icons.inventory_2_outlined,
      tasks: pick(const ['products']),
    ),
    ActivationStepGroup(
      key: 'firstSale',
      number: 3,
      title: 'Haz tu primera venta',
      summary: 'Abre la caja, cobra y entrega el comprobante al cliente.',
      icon: Icons.point_of_sale_outlined,
      tasks: pick(const ['firstSale']),
    ),
    ActivationStepGroup(
      key: 'company',
      number: 4,
      title: 'Completa los datos de tu empresa',
      summary:
          'Completa la información de tu empresa y sube tu logo para '
          'personalizar tus tickets y documentos.',
      icon: Icons.storefront_outlined,
      tasks: pick(const ['business', 'taxes', 'tickets']),
      // Basta con guardar los datos del negocio: el logo y los impuestos se
      // recomiendan, pero no bloquean el avance.
      completionKey: 'business',
    ),
    ActivationStepGroup(
      key: 'ecf',
      number: 5,
      title: 'Activa tu facturación electrónica',
      summary:
          'Solo si necesitas emitir comprobantes electrónicos ante la DGII.',
      icon: Icons.receipt_long_outlined,
      tasks: pick(const ['ecf']),
      optional: true,
    ),
  ];

  final kept = groups.where((group) => group.tasks.isNotEmpty).toList();
  return <ActivationStepGroup>[
    for (var i = 0; i < kept.length; i++) kept[i].withNumber(i + 1),
  ];
}

/// Apartados que aún tienen algo pendiente. Es el número que se anuncia en la
/// cabecera del panel y en el botón flotante.
int activationPendingSteps(ActivationState state) =>
    activationStepGroups(state).where((group) => group.isPending).length;

/// Etiqueta corta de cada parte del apartado «Datos de tu empresa».
String activationCompanyPartLabel(String taskKey) {
  switch (taskKey) {
    case 'business':
      return 'Datos del negocio';
    case 'taxes':
      return 'Impuestos';
    case 'tickets':
      return 'Logo y tickets';
    default:
      return '';
  }
}
