import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:validators/validators.dart' as validators;

import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/routing/route_access.dart';
import '../../../core/utils/app_feedback.dart';
import '../../../core/widgets/primary_button.dart';
import 'register_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  _LoginNoticeData? _notice;
  bool _rememberMe = false;
  bool _obscurePassword = true;

  static const _rememberEmailKey = 'remember_email';
  static const _rememberPasswordKey = 'remember_password';
  static const _rememberFlagKey = 'remember_flag';

  @override
  void initState() {
    super.initState();
    _emailCtrl.addListener(_clearNoticeOnInput);
    _passwordCtrl.addListener(_clearNoticeOnInput);
    _loadRememberedCredentials();
  }

  @override
  void dispose() {
    _emailCtrl.removeListener(_clearNoticeOnInput);
    _passwordCtrl.removeListener(_clearNoticeOnInput);
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _clearNoticeOnInput() {
    if (_notice == null || !_notice!.isError || !mounted) {
      return;
    }
    setState(() => _notice = null);
  }

  Future<void> _loadRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remembered = prefs.getBool(_rememberFlagKey) ?? false;
    final email = prefs.getString(_rememberEmailKey) ?? '';
    final password = prefs.getString(_rememberPasswordKey) ?? '';
    if (!mounted) return;
    setState(() {
      _rememberMe = remembered;
      if (remembered) {
        _emailCtrl.text = email;
        _passwordCtrl.text = password;
      }
    });
  }

  Future<void> _persistRememberedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setBool(_rememberFlagKey, true);
      await prefs.setString(_rememberEmailKey, _emailCtrl.text.trim());
      await prefs.setString(_rememberPasswordKey, _passwordCtrl.text);
    } else {
      await prefs.remove(_rememberFlagKey);
      await prefs.remove(_rememberEmailKey);
      await prefs.remove(_rememberPasswordKey);
    }
  }

  _LoginNoticeData _buildErrorNotice(ApiException error) {
    switch (error.type) {
      case ApiErrorType.unauthorized:
        return _LoginNoticeData.error(
          title: 'Datos de acceso incorrectos',
          message: error.message,
          helpText:
              'Revisa tu correo corporativo y tu contrasena antes de volver a intentar.',
        );
      case ApiErrorType.forbidden:
        return _LoginNoticeData.error(
          title: 'Acceso restringido',
          message: error.message,
          helpText:
              'Si tu acceso deberia estar activo, comunicate con administracion.',
        );
      case ApiErrorType.noInternet:
      case ApiErrorType.dns:
      case ApiErrorType.tls:
      case ApiErrorType.network:
      case ApiErrorType.timeout:
        return _LoginNoticeData.error(
          title: 'No se pudo conectar',
          message: error.message,
          helpText:
              'Verifica tu conexion a internet y vuelve a intentar en unos segundos.',
        );
      case ApiErrorType.config:
        return _LoginNoticeData.error(
          title: 'Configuracion pendiente',
          message: error.message,
          helpText:
              'La aplicacion necesita una configuracion valida del backend para continuar.',
        );
      case ApiErrorType.server:
        return _LoginNoticeData.error(
          title: 'Servidor no disponible',
          message: error.message,
          helpText:
              'El sistema esta respondiendo con un problema interno. Intenta nuevamente en un momento.',
        );
      case ApiErrorType.badRequest:
      case ApiErrorType.notFound:
      case ApiErrorType.conflict:
      case ApiErrorType.parse:
      case ApiErrorType.cancelled:
      case ApiErrorType.unknown:
        return _LoginNoticeData.error(
          title: 'No se pudo iniciar sesion',
          message: error.message,
          helpText:
              'Corrige los datos ingresados o vuelve a intentarlo en unos segundos.',
        );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => _notice = null);
    try {
      await ref
          .read(authStateProvider.notifier)
          .login(_emailCtrl.text, _passwordCtrl.text);
      await _persistRememberedCredentials();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go(
          RouteAccess.defaultHomeForRole(
            ref.read(authStateProvider).user?.appRole ?? AppRole.unknown,
          ),
        );
      });
      return;
    } on ApiException catch (e) {
      if (mounted) {
        final notice = _buildErrorNotice(e);
        setState(() => _notice = notice);
        await AppFeedback.showError(
          context,
          '${notice.title}. ${notice.message}',
          scope: 'LoginScreen',
        );
      }
    } catch (e) {
      if (mounted) {
        const notice = _LoginNoticeData.error(
          title: 'No se pudo iniciar sesion',
          message:
              'Ocurrio un error inesperado al validar tu acceso. Intenta nuevamente.',
          helpText:
              'Si el problema persiste, informa al area tecnica para revisar el sistema.',
        );
        setState(() => _notice = notice);
        await AppFeedback.showError(
          context,
          '${notice.title}. ${notice.message}',
          scope: 'LoginScreen',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authStateProvider).loading;
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final viewInsets = mediaQuery.viewInsets;
    final horizontalPadding = size.width < 420 ? 16.0 : 24.0;
    final cardWidth = size.width >= 900
        ? 420.0
        : (size.width - (horizontalPadding * 2)).clamp(288.0, 520.0);

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
                constraints: BoxConstraints(maxWidth: cardWidth),
                child: Card(
                  color: Colors.white,
                  elevation: 10,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Colors.black87, width: 1.2),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Bienvenido a DaleVenta POS',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(
                                      color: Colors.black87,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Inicia sesion para continuar.',
                                style: TextStyle(color: Colors.black87),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            controller: _emailCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Email corporativo',
                              prefixIcon: Icon(Icons.alternate_email),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) {
                              final value = v?.trim() ?? '';
                              if (value.isEmpty) return 'Ingresa tu email';
                              if (!validators.isEmail(value)) {
                                return 'Email invalido';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordCtrl,
                            decoration: InputDecoration(
                              labelText: 'Contrasena',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                tooltip: _obscurePassword
                                    ? 'Mostrar contrasena'
                                    : 'Ocultar contrasena',
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                              ),
                            ),
                            obscureText: _obscurePassword,
                            validator: (v) => (v == null || v.isEmpty)
                                ? 'Ingresa tu contrasena'
                                : null,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Switch(
                                value: _rememberMe,
                                onChanged: (value) {
                                  setState(() => _rememberMe = value);
                                },
                                activeThumbColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Recordar contrasena',
                                  style: TextStyle(
                                    color: Colors.black87,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_notice != null) ...[
                            const SizedBox(height: 12),
                            _LoginNoticeCard(data: _notice!),
                          ],
                          const SizedBox(height: 16),
                          PrimaryButton(
                            label: 'Iniciar sesion',
                            loading: loading,
                            onPressed: _submit,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: loading
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const RegisterScreen(),
                                    ),
                                  ),
                            icon: const Icon(Icons.storefront_rounded),
                            label: const Text('Crear mi negocio'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              foregroundColor: const Color(0xFF123A75),
                              side: const BorderSide(color: Color(0xFFCFE0FF)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: loading ? null : () {},
                            child: const Text('¿Olvidaste tu contraseña?'),
                          ),
                        ],
                      ),
                    ),
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

class _LoginNoticeData {
  const _LoginNoticeData({
    required this.title,
    required this.message,
    required this.helpText,
    required this.isError,
  });

  const _LoginNoticeData.error({
    required this.title,
    required this.message,
    required this.helpText,
  }) : isError = true;

  final String title;
  final String message;
  final String helpText;
  final bool isError;
}

class _LoginNoticeCard extends StatelessWidget {
  const _LoginNoticeCard({required this.data});

  final _LoginNoticeData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final backgroundColor = data.isError
        ? colorScheme.errorContainer
        : const Color(0xFFE8F7EE);
    final foregroundColor = data.isError
        ? colorScheme.onErrorContainer
        : const Color(0xFF155724);
    final accentColor = data.isError
        ? colorScheme.error
        : const Color(0xFF1F8F4D);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              data.isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: accentColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: foregroundColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data.message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foregroundColor,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  data.helpText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: foregroundColor.withValues(alpha: 0.86),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
