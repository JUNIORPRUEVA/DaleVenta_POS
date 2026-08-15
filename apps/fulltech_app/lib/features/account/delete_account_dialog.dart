import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_colors.dart';

Future<void> showDeleteAccountDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  AccountDeletionPreview preview;
  try {
    preview = await ref
        .read(authRepositoryProvider)
        .getAccountDeletionPreview();
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('No se pudo preparar la eliminacion: $error')),
    );
    return;
  }

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.58),
    builder: (_) => _DeleteAccountDangerDialog(preview: preview),
  );
}

class _DeleteAccountDangerDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDangerDialog({required this.preview});

  final AccountDeletionPreview preview;

  @override
  ConsumerState<_DeleteAccountDangerDialog> createState() =>
      _DeleteAccountDangerDialogState();
}

class _DeleteAccountDangerDialogState
    extends ConsumerState<_DeleteAccountDangerDialog> {
  final _password = TextEditingController();
  final _phrase = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _phrase.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      final result = await ref
          .read(authStateProvider.notifier)
          .deleteAccount(
            password: _password.text,
            confirmationPhrase: widget.preview.requiresCompanyConfirmationPhrase
                ? _phrase.text
                : null,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.companyDeleted
                ? 'Cuenta y empresa eliminadas. Recibo: ${result.deletionReceiptId}'
                : 'Cuenta eliminada. Recibo: ${result.deletionReceiptId}',
          ),
        ),
      );
      context.go(Routes.login);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final fullCompanyDeletion = preview.companyWillBeDeleted;
    final title = fullCompanyDeletion
        ? 'Eliminar empresa y cuenta'
        : 'Eliminar cuenta';
    final message = fullCompanyDeletion
        ? 'Eres el unico propietario activo. Esta accion eliminara la empresa activa, sus datos relacionados y bloqueara tu cuenta.'
        : 'Esta accion eliminara tu acceso, retirara tus membresias activas, revocara sesiones y bloqueara tu cuenta.';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 510),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Material(
            color: Colors.white,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: AppColors.error,
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PELIGRO',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Opcion peligrosa',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message,
                        style: const TextStyle(
                          color: Color(0xFF13243A),
                          fontSize: 13,
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1F1),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: const Color(0xFFFECACA)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: AppColors.error,
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'La app solo cerrara la sesion despues de que el backend confirme la eliminacion.',
                                style: TextStyle(
                                  color: Color(0xFF111827),
                                  fontSize: 12.5,
                                  height: 1.28,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _password,
                        obscureText: true,
                        enabled: !_submitting,
                        decoration: const InputDecoration(
                          labelText: 'Contrasena actual',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (preview.requiresCompanyConfirmationPhrase) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _phrase,
                          enabled: !_submitting,
                          decoration: const InputDecoration(
                            labelText: 'Escribe DELETE MY COMPANY',
                            prefixIcon: Icon(Icons.priority_high_rounded),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.error,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _submitting
                                ? null
                                : () => Navigator.of(context).pop(),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            onPressed: _submitting ? null : _submit,
                            icon: _submitting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.delete_forever_outlined),
                            label: Text(
                              _submitting
                                  ? 'Eliminando'
                                  : 'Eliminar definitivamente',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.error,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
