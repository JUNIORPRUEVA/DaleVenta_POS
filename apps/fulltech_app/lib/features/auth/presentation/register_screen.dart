import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/routing/route_access.dart';
import '../../../core/routing/routes.dart';
import '../../../core/utils/app_feedback.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ownerName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _businessName = TextEditingController();
  final _password = TextEditingController();
  _RegisterNoticeData? _notice;
  bool _obscurePassword = true;
  bool _acceptedTerms = true;

  @override
  void initState() {
    super.initState();
    _ownerName.addListener(_clearNoticeOnInput);
    _email.addListener(_clearNoticeOnInput);
    _phone.addListener(_clearNoticeOnInput);
    _businessName.addListener(_clearNoticeOnInput);
    _password.addListener(_clearNoticeOnInput);
  }

  @override
  void dispose() {
    _ownerName.removeListener(_clearNoticeOnInput);
    _email.removeListener(_clearNoticeOnInput);
    _phone.removeListener(_clearNoticeOnInput);
    _businessName.removeListener(_clearNoticeOnInput);
    _password.removeListener(_clearNoticeOnInput);
    _ownerName.dispose();
    _email.dispose();
    _phone.dispose();
    _businessName.dispose();
    _password.dispose();
    super.dispose();
  }

  void _clearNoticeOnInput() {
    if (_notice == null || !mounted) return;
    setState(() => _notice = null);
  }

  _RegisterNoticeData _buildErrorNotice(ApiException error) {
    if (error.displayCode == 'CREATED_SESSION_INCOMPLETE') {
      return _RegisterNoticeData(
        title: 'Negocio creado',
        message: error.message,
        helpText:
            'Para evitar duplicar la cuenta, usa Ya tengo cuenta e inicia sesión con estos mismos datos.',
      );
    }

    switch (error.type) {
      case ApiErrorType.badRequest:
        return _RegisterNoticeData(
          title: 'Revisa los datos',
          message: error.message,
          helpText:
              'Corrige la información marcada y vuelve a presionar Crear mi negocio.',
        );
      case ApiErrorType.conflict:
        return _RegisterNoticeData(
          title: 'Cuenta existente',
          message: error.message,
          helpText:
              'Ese correo o negocio ya puede estar registrado. Intenta iniciar sesión o usa otro correo.',
        );
      case ApiErrorType.noInternet:
        return _RegisterNoticeData(
          title: 'Sin conexión',
          message: error.message,
          helpText:
              'Conecta la PC a internet y vuelve a intentar cuando la señal esté estable.',
        );
      case ApiErrorType.dns:
        return _RegisterNoticeData(
          title: 'Servicio no encontrado',
          message: error.message,
          helpText:
              'Prueba cambiar de red o reiniciar el internet antes de intentar otra vez.',
        );
      case ApiErrorType.tls:
        return _RegisterNoticeData(
          title: 'Conexión segura rechazada',
          message: error.message,
          helpText:
              'Verifica la fecha y hora de la PC. Si usas antivirus o red empresarial, puede estar bloqueando la conexión.',
        );
      case ApiErrorType.network:
        return _RegisterNoticeData(
          title: 'Conexión interrumpida',
          message: error.message,
          helpText:
              'Espera unos segundos y vuelve a intentar. Si continúa, prueba otra red.',
        );
      case ApiErrorType.timeout:
        return _RegisterNoticeData(
          title: 'Tiempo de espera agotado',
          message: error.message,
          helpText:
              'La creación tardó demasiado. Revisa tu conexión y vuelve a intentar.',
        );
      case ApiErrorType.config:
        return _RegisterNoticeData(
          title: 'App no configurada',
          message: error.message,
          helpText:
              'Instala la versión más reciente o contacta a soporte para validar la instalación.',
        );
      case ApiErrorType.server:
        return _RegisterNoticeData(
          title: 'Servicio no disponible',
          message: error.message,
          helpText:
              'El servicio tuvo un problema temporal. Intenta nuevamente en un momento.',
        );
      case ApiErrorType.unauthorized:
      case ApiErrorType.forbidden:
      case ApiErrorType.notFound:
      case ApiErrorType.parse:
      case ApiErrorType.cancelled:
      case ApiErrorType.unknown:
        return _RegisterNoticeData(
          title: 'No se pudo crear',
          message: error.message,
          helpText:
              'Revisa los datos ingresados o vuelve a intentar en unos segundos.',
        );
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_acceptedTerms) {
      await AppFeedback.showError(
        context,
        'Debes aceptar los términos para crear tu negocio.',
        scope: 'RegisterScreen',
      );
      return;
    }

    FocusScope.of(context).unfocus();
    final fullName = _ownerName.text.trim();
    final parts = fullName.split(RegExp(r'\s+'));
    final firstName = parts.isEmpty ? fullName : parts.first;
    final lastName = parts.length > 1 ? parts.skip(1).join(' ') : '';
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    final businessName = _businessName.text.trim();

    final payload = {
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'password': _password.text,
      'confirmPassword': _password.text,
      'commercialName': businessName,
      'legalName': businessName,
      'businessPhone': phone,
      'businessEmail': email,
      'country': 'República Dominicana',
      'businessType': 'Comercio',
      'currency': 'DOP',
      'timezone': 'America/Santo_Domingo',
      'locale': 'es-DO',
    };

    try {
      if (mounted) setState(() => _notice = null);
      await ref.read(authStateProvider.notifier).registerBusiness(payload);
      if (!mounted) return;
      context.go(
        RouteAccess.defaultHomeForRole(
          ref.read(authStateProvider).user?.appRole ?? AppRole.admin,
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      final notice = _buildErrorNotice(error);
      setState(() => _notice = notice);
      await AppFeedback.showError(
        context,
        '${notice.title}. ${notice.message}',
        scope: 'RegisterScreen',
      );
    }
  }

  void _closeToLogin() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.go(Routes.login);
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authStateProvider).loading;
    final compact = MediaQuery.sizeOf(context).width < 720;

    return Scaffold(
      backgroundColor: const Color(0xFF0F5ED7),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 18 : 28,
                vertical: compact ? 22 : 34,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - (compact ? 44 : 68),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Form(
                      key: _formKey,
                      child: Container(
                        padding: EdgeInsets.all(compact ? 22 : 28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.55),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x3305253F),
                              blurRadius: 28,
                              offset: Offset(0, 16),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Header(onBack: loading ? null : _closeToLogin),
                            const SizedBox(height: 22),
                            _Field(
                              controller: _businessName,
                              label: 'Nombre del negocio',
                              icon: Icons.storefront_rounded,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 12),
                            _Field(
                              controller: _ownerName,
                              label: 'Persona responsable',
                              icon: Icons.person_outline_rounded,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 12),
                            _Field(
                              controller: _email,
                              label: 'Correo corporativo',
                              icon: Icons.alternate_email_rounded,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              validator: _emailValidator,
                            ),
                            const SizedBox(height: 12),
                            _Field(
                              controller: _phone,
                              label: 'WhatsApp',
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 12),
                            _PasswordField(
                              controller: _password,
                              obscure: _obscurePassword,
                              onToggle: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                            const SizedBox(height: 10),
                            CheckboxListTile(
                              value: _acceptedTerms,
                              onChanged: loading
                                  ? null
                                  : (value) => setState(
                                      () => _acceptedTerms = value ?? false,
                                    ),
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Acepto crear mi empresa y usar FullPOS Cloud de forma responsable.',
                                style: TextStyle(
                                  color: Color(0xFF52667C),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            if (_notice != null) ...[
                              const SizedBox(height: 10),
                              _RegisterNoticeCard(data: _notice!),
                            ],
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 52,
                              child: FilledButton.icon(
                                onPressed: loading ? null : _submit,
                                icon: loading
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.arrow_forward_rounded),
                                label: Text(
                                  loading
                                      ? 'Creando negocio...'
                                      : 'Crear mi negocio',
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF147A8E),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Center(
                              child: TextButton(
                                onPressed: loading ? null : _closeToLogin,
                                child: const Text('Ya tengo cuenta'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String? _emailValidator(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Ingresa tu correo';
    if (!text.contains('@') || !text.contains('.')) {
      return 'Ingresa un correo válido';
    }
    return null;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF1FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.storefront_rounded,
            color: Color(0xFF1957E6),
            size: 25,
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Crear empresa',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                  height: 1.08,
                ),
              ),
              SizedBox(height: 5),
              Text(
                '5 dias gratis. Plan basico: 2 usuarios y 100 productos.',
                style: TextStyle(
                  color: Color(0xFF52667C),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Volver',
          onPressed: onBack,
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}

class _RegisterNoticeData {
  const _RegisterNoticeData({
    required this.title,
    required this.message,
    required this.helpText,
  });

  final String title;
  final String message;
  final String helpText;
}

class _RegisterNoticeCard extends StatelessWidget {
  const _RegisterNoticeCard({required this.data});

  final _RegisterNoticeData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: colorScheme.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data.message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  data.helpText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onErrorContainer.withValues(alpha: 0.86),
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

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.textInputAction,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      validator:
          validator ??
          (value) {
            if ((value ?? '').trim().isEmpty) return 'Campo obligatorio';
            return null;
          },
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.obscure,
    required this.onToggle,
  });

  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        labelText: 'Contraseña',
        prefixIcon: const Icon(Icons.lock_outline_rounded),
        suffixIcon: IconButton(
          tooltip: 'Mostrar u ocultar contraseña',
          onPressed: onToggle,
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
      ),
      validator: (value) {
        final text = value ?? '';
        if (text.isEmpty) return 'Ingresa una contraseña';
        if (text.length < 8) return 'Mínimo 8 caracteres';
        return null;
      },
      onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
    );
  }
}
