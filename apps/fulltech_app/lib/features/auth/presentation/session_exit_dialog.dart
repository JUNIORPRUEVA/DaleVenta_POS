import 'package:flutter/material.dart';

enum SessionExitAction { lock, logout }

Future<SessionExitAction?> showSessionExitDialog(
  BuildContext context,
) => showDialog<SessionExitAction>(
  context: context,
  builder: (dialog) => AlertDialog(
    title: const Text('Salir de FullPOS'),
    content: const Text(
      'Bloquear protege la pantalla y conserva el acceso local si este equipo ya está autorizado. '
      'Cerrar sesión lo elimina: necesitarás conexión para volver a entrar.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialog),
        child: const Text('Cancelar'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(dialog, SessionExitAction.logout),
        child: const Text('Cerrar sesión'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(dialog, SessionExitAction.lock),
        child: const Text('Bloquear equipo'),
      ),
    ],
  ),
);
