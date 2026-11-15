import 'package:flutter/material.dart';

enum ProvidedAction {
  refresh,
  add,
  download,
  close,
  delete,
  edit,
  search,
  reload,
  filter,
  order,
  pdf,
  supplier,
  send,
  category,
  calendar,
  analytics,
  profit,
}

/// Originales transparentes entregados por el usuario, teñidos por el tema.
class ProvidedActionIcon extends StatelessWidget {
  const ProvidedActionIcon(
    this.action, {
    super.key,
    this.size = 20,
    this.color,
  });
  final ProvidedAction action;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/image/action_${action.name}.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    color: color ?? IconTheme.of(context).color,
    colorBlendMode: BlendMode.srcIn,
    excludeFromSemantics: true,
  );
}
