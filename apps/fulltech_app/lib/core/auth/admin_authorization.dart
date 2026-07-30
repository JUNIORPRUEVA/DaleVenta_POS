import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../company/company_settings_repository.dart';
import '../theme/app_colors.dart';
import 'admin_authorization_session.dart';
import 'app_permissions.dart';
import 'app_role.dart';
import 'auth_provider.dart';

Future<bool> ensureAdminAuthorization(
  BuildContext context,
  WidgetRef ref, {
  AppPermission? permission,
  String reason = 'Autorizar acción administrativa',
}) async {
  final user = ref.read(authStateProvider).user;
  if (user == null) return false;
  if (user.appRole == AppRole.admin) return true;
  if (permission != null && hasUserPermission(user, permission)) return true;

  final controller = ref.read(adminAuthorizationProvider.notifier);
  if (controller.isAuthorized) return true;

  final granted = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _AdminAuthorizationDialog(reason: reason),
  );
  return granted == true;
}

bool hasPermissionOrAdminAuthorization(
  WidgetRef ref,
  AppPermission permission,
) {
  final user = ref.read(authStateProvider).user;
  if (user == null) return false;
  if (user.appRole == AppRole.admin) return true;
  if (hasUserPermission(user, permission)) return true;
  return ref.read(adminAuthorizationProvider.notifier).isAuthorized;
}

class _AdminAuthorizationDialog extends ConsumerStatefulWidget {
  const _AdminAuthorizationDialog({required this.reason});

  final String reason;

  @override
  ConsumerState<_AdminAuthorizationDialog> createState() =>
      _AdminAuthorizationDialogState();
}

class _AdminAuthorizationDialogState
    extends ConsumerState<_AdminAuthorizationDialog> {
  final _pin = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final value = _pin.text.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(value)) {
      setState(() => _error = 'Ingresa el PIN administrativo de 4 dígitos.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final duration = await ref
          .read(companySettingsRepositoryProvider)
          .verifyAdminAuthorizationPin(value);
      ref
          .read(adminAuthorizationProvider.notifier)
          .authorizeFor(duration.duration, duration.token);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Autorización administrativa',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF102235),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.reason,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF607187),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _pin,
                autofocus: true,
                obscureText: true,
                obscuringCharacter: '•',
                enableSuggestions: false,
                autocorrect: false,
                maxLength: 4,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                onSubmitted: (_) => _loading ? null : _verify(),
                decoration: InputDecoration(
                  counterText: '',
                  prefixIcon: const Icon(Icons.pin_outlined),
                  labelText: 'PIN de 4 dígitos',
                  errorText: _error,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _loading ? null : _verify,
                    icon: _loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_open_outlined),
                    label: Text(_loading ? 'Validando' : 'Autorizar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
