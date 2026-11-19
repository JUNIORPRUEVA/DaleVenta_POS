import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/api_exception.dart';
import 'plan_ui.dart';

/// Acciones comunes de la seccion Planes: bloquear doble clic, avisar del error
/// del servidor y confirmar con dialogos rectos.
mixin PlansActionMixin<W extends ConsumerStatefulWidget> on ConsumerState<W> {
  bool busy = false;

  void snack(String message, {bool isError = false}) {
    if (!mounted) return;
    showPlansToast(context, message, isError: isError);
  }

  Future<T?> run<T>(Future<T> Function() action) async {
    if (busy) return null;
    setState(() => busy = true);
    try {
      return await action();
    } on ApiException catch (error) {
      snack(error.message, isError: true);
      return null;
    } catch (_) {
      snack('No se pudo completar la operacion.', isError: true);
      return null;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirm({
    required String title,
    required String message,
    required String accept,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: const RoundedRectangleBorder(),
        title: Text(title),
        content: Text(message),
        actions: [
          SquareButton(
            label: 'Volver',
            variant: SquareVariant.ghost,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          SquareButton(
            label: accept,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return result == true;
  }
}
