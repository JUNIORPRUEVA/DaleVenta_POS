import 'package:flutter/material.dart';
import '../utils/native_phone_layout.dart';

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
    usesNativePhoneLayout(context) &&
      {ProvidedAction.search, ProvidedAction.filter, ProvidedAction.refresh, ProvidedAction.reload}.contains(action)
      ? 'assets/image/mobile_navigation/${action == ProvidedAction.reload ? 'refresh' : action.name}.png'
      : 'assets/image/action_${action.name}.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    color: color ?? IconTheme.of(context).color,
    colorBlendMode: BlendMode.srcIn,
    excludeFromSemantics: true,
  );
}
