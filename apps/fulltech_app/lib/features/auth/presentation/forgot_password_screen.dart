import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:validators/validators.dart' as validators;

import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/routing/routes.dart';
import '../../../core/utils/app_feedback.dart';
import '../../../core/widgets/primary_button.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _confirmationVisible = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _confirmationVisible = false;
    });
    try {
      await ref
          .read(authRepositoryProvider)
          .requestPasswordReset(_emailCtrl.text);
      if (!mounted) return;
      setState(() => _confirmationVisible = true);
    } on ApiException catch (error) {
      if (!mounted) return;
      await AppFeedback.showError(
        context,
        error.message,
        scope: 'ForgotPasswordScreen',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthRecoveryScaffold(
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _RecoveryHeader(
              title: 'Recuperar contraseña',
              subtitle: 'Ingresa el correo de la cuenta empresarial.',
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
                prefixIcon: Icon(Icons.alternate_email_rounded),
              ),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) {
                if (!_loading) _submit();
              },
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return 'Ingresa tu correo';
                if (!validators.isEmail(text)) return 'Correo inválido';
                return null;
              },
            ),
            if (_confirmationVisible) ...[
              const SizedBox(height: 14),
              const _ConfirmationBox(
                title: 'Revisa tu correo',
                message:
                    'Si tu cuenta permite recuperación, te enviamos un enlace para crear una nueva contraseña.',
              ),
            ],
            const SizedBox(height: 18),
            PrimaryButton(
              label: 'Enviar instrucciones',
              loading: _loading,
              onPressed: _submit,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loading ? null : () => context.go(Routes.login),
              child: const Text('Volver al inicio de sesión'),
            ),
          ],
        ),
      ),
    );
  }
}

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.token});

  final String token;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _completed = false;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .resetPassword(token: widget.token, password: _passwordCtrl.text);
      final auth = ref.read(authStateProvider);
      if (auth.isAuthenticated || auth.hasSessionHint) {
        await ref.read(authStateProvider.notifier).logout();
      }
      if (!mounted) return;
      setState(() => _completed = true);
    } on ApiException catch (error) {
      if (!mounted) return;
      await AppFeedback.showError(
        context,
        error.message,
        scope: 'ResetPasswordScreen',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final missingToken = widget.token.trim().isEmpty;

    return _AuthRecoveryScaffold(
      child: _completed
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _RecoveryHeader(
                  title: 'Contraseña actualizada',
                  subtitle: 'Contraseña actualizada correctamente',
                ),
                const SizedBox(height: 18),
                PrimaryButton(
                  label: 'Volver a iniciar sesión',
                  onPressed: () => context.go(Routes.login),
                ),
              ],
            )
          : Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _RecoveryHeader(
                    title: 'Nueva contraseña',
                    subtitle: 'Confirma los datos antes de guardar.',
                  ),
                  if (missingToken) ...[
                    const SizedBox(height: 14),
                    const _ConfirmationBox(
                      title: 'Enlace inválido',
                      message:
                          'El enlace no contiene un token válido. Solicita un nuevo enlace de recuperación.',
                    ),
                  ],
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Nueva contraseña',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword
                            ? 'Mostrar contraseña'
                            : 'Ocultar contraseña',
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) {
                      final text = value ?? '';
                      if (text.isEmpty) return 'Ingresa una contraseña';
                      if (text.length < 8) return 'Mínimo 8 caracteres';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmCtrl,
                    obscureText: _obscureConfirm,
                    decoration: InputDecoration(
                      labelText: 'Confirmar contraseña',
                      prefixIcon: const Icon(Icons.lock_reset_rounded),
                      suffixIcon: IconButton(
                        tooltip: _obscureConfirm
                            ? 'Mostrar contraseña'
                            : 'Ocultar contraseña',
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                        icon: Icon(
                          _obscureConfirm
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if ((value ?? '').isEmpty) {
                        return 'Confirma tu contraseña';
                      }
                      if (value != _passwordCtrl.text) {
                        return 'Las contraseñas no coinciden';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) {
                      if (!_loading && !missingToken) _submit();
                    },
                  ),
                  const SizedBox(height: 18),
                  PrimaryButton(
                    label: 'Guardar nueva contraseña',
                    loading: _loading,
                    onPressed: missingToken ? null : _submit,
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loading ? null : () => context.go(Routes.login),
                    child: const Text('Volver al inicio de sesión'),
                  ),
                ],
              ),
            ),
    );
  }
}

class _AuthRecoveryScaffold extends StatelessWidget {
  const _AuthRecoveryScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final horizontalPadding = size.width < 420 ? 16.0 : 24.0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A3D91), Color(0xFF1273D3)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                24,
                horizontalPadding,
                24 + viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Card(
                  color: Colors.white,
                  elevation: 10,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Colors.black87, width: 1.2),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(size.width < 420 ? 20 : 24),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecoveryHeader extends StatelessWidget {
  const _RecoveryHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(color: Colors.black87)),
      ],
    );
  }
}

class _ConfirmationBox extends StatelessWidget {
  const _ConfirmationBox({this.title, required this.message});

  final String? title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE1E8F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((title ?? '').trim().isNotEmpty) ...[
            Text(
              title!,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: const Color(0xFF172033),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF52667C),
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
