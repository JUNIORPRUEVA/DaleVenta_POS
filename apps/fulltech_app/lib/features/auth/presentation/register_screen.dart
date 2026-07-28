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
  final _pageController = PageController();
  int _step = 0;
  bool _acceptedTerms = false;
  bool _obscurePassword = true;

  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _commercialName = TextEditingController();
  final _legalName = TextEditingController();
  final _taxId = TextEditingController();
  final _businessPhone = TextEditingController();
  final _businessEmail = TextEditingController();
  final _country = TextEditingController(text: 'República Dominicana');
  final _province = TextEditingController();
  final _city = TextEditingController();
  final _address = TextEditingController();
  final _businessType = TextEditingController(text: 'Comercio');

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in [
      _firstName,
      _lastName,
      _email,
      _phone,
      _password,
      _confirmPassword,
      _commercialName,
      _legalName,
      _taxId,
      _businessPhone,
      _businessEmail,
      _country,
      _province,
      _city,
      _address,
      _businessType,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _goToStep(int value) {
    setState(() => _step = value);
    _pageController.animateToPage(
      value,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  bool _validateCurrentStep() {
    if (!(_formKey.currentState?.validate() ?? false)) return false;
    if (_step == 0 && !_acceptedTerms) {
      AppFeedback.showError(
        context,
        'Debes aceptar los términos para crear tu negocio.',
        scope: 'RegisterScreen',
      );
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (!_validateCurrentStep()) return;
    FocusScope.of(context).unfocus();
    final payload = {
      'firstName': _firstName.text.trim(),
      'lastName': _lastName.text.trim(),
      'email': _email.text.trim(),
      'phone': _phone.text.trim(),
      'password': _password.text,
      'confirmPassword': _confirmPassword.text,
      'commercialName': _commercialName.text.trim(),
      'legalName': _legalName.text.trim(),
      'taxId': _taxId.text.trim(),
      'businessPhone': _businessPhone.text.trim().isEmpty
          ? _phone.text.trim()
          : _businessPhone.text.trim(),
      'businessEmail': _businessEmail.text.trim().isEmpty
          ? _email.text.trim()
          : _businessEmail.text.trim(),
      'country': _country.text.trim(),
      'province': _province.text.trim(),
      'city': _city.text.trim(),
      'address': _address.text.trim(),
      'businessType': _businessType.text.trim(),
      'currency': 'DOP',
      'timezone': 'America/Santo_Domingo',
      'locale': 'es-DO',
    };

    try {
      await ref.read(authStateProvider.notifier).registerBusiness(payload);
      if (!mounted) return;
      context.go(
        RouteAccess.defaultHomeForRole(
          ref.read(authStateProvider).user?.appRole ?? AppRole.admin,
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      await AppFeedback.showError(
        context,
        error.message,
        scope: 'RegisterScreen',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authStateProvider).loading;
    final compact = MediaQuery.sizeOf(context).width < 820;

    return Scaffold(
      backgroundColor: const Color(0xFFEFF5F8),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final panelHeight = compact
                ? (constraints.maxHeight - 40).clamp(720.0, 920.0)
                : (constraints.maxHeight - 40).clamp(620.0, 780.0);

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: SizedBox(
                    height: panelHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFDDE7EE)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x140F172A),
                            blurRadius: 22,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: compact
                            ? _buildContent(context, loading, compact)
                            : Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: _buildBrandPanel()),
                                  SizedBox(
                                    width: 610,
                                    child: _buildContent(
                                      context,
                                      loading,
                                      compact,
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

  void _closeToLogin() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.go(Routes.login);
  }

  Widget _buildBrandPanel() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: const BoxDecoration(color: Color(0xFF0F5ED7)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24),
            ),
            child: const Icon(
              Icons.point_of_sale_rounded,
              color: Colors.white,
              size: 27,
            ),
          ),
          const Spacer(),
          const Text(
            'Crea tu negocio en DaleVenta POS',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Tu empresa queda aislada, con su propia información, usuarios, ventas, productos y archivos.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.84),
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool loading, bool compact) {
    return Padding(
      padding: EdgeInsets.all(compact ? 18 : 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Crear mi negocio',
                      style: TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _step == 0
                          ? 'Primero crea tu cuenta propietaria.'
                          : _step == 1
                          ? 'Ahora configura la empresa.'
                          : 'Revisa y confirma la creación.',
                      style: const TextStyle(
                        color: Color(0xFF52667C),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: loading ? null : _closeToLogin,
                child: const Text('Iniciar sesión'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _StepHeader(step: _step),
          const SizedBox(height: 18),
          SizedBox(
            height: compact ? 520 : 430,
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [_accountStep(), _businessStep(), _summaryStep()],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              if (_step > 0)
                OutlinedButton.icon(
                  onPressed: loading ? null : () => _goToStep(_step - 1),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Atrás'),
                ),
              const Spacer(),
              FilledButton.icon(
                onPressed: loading
                    ? null
                    : () {
                        if (!_validateCurrentStep()) return;
                        if (_step < 2) {
                          _goToStep(_step + 1);
                        } else {
                          _submit();
                        }
                      },
                icon: loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _step < 2
                            ? Icons.arrow_forward_rounded
                            : Icons.storefront_rounded,
                      ),
                label: Text(_step < 2 ? 'Continuar' : 'Crear mi negocio'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _accountStep() {
    return ListView(
      children: [
        _twoColumns([
          _field(
            _firstName,
            'Nombre',
            Icons.person_outline_rounded,
            stepIndex: 0,
          ),
          _field(
            _lastName,
            'Apellido',
            Icons.badge_outlined,
            stepIndex: 0,
            required: false,
          ),
        ]),
        _twoColumns([
          _field(
            _email,
            'Correo electrónico',
            Icons.alternate_email,
            stepIndex: 0,
            keyboardType: TextInputType.emailAddress,
            email: true,
          ),
          _field(
            _phone,
            'Teléfono',
            Icons.phone_outlined,
            stepIndex: 0,
            keyboardType: TextInputType.phone,
          ),
        ]),
        _twoColumns([
          _passwordField(_password, 'Contraseña'),
          _passwordField(
            _confirmPassword,
            'Confirmar contraseña',
            confirm: true,
          ),
        ]),
        CheckboxListTile(
          value: _acceptedTerms,
          onChanged: (value) => setState(() => _acceptedTerms = value ?? false),
          contentPadding: EdgeInsets.zero,
          title: const Text(
            'Acepto los términos, privacidad y uso responsable del sistema.',
          ),
          controlAffinity: ListTileControlAffinity.leading,
        ),
      ],
    );
  }

  Widget _businessStep() {
    return ListView(
      children: [
        _twoColumns([
          _field(
            _commercialName,
            'Nombre comercial',
            Icons.storefront,
            stepIndex: 1,
          ),
          _field(
            _legalName,
            'Razón social',
            Icons.apartment_rounded,
            stepIndex: 1,
            required: false,
          ),
        ]),
        _twoColumns([
          _field(
            _taxId,
            'RNC o identificación fiscal',
            Icons.numbers,
            stepIndex: 1,
            required: false,
          ),
          _field(
            _businessType,
            'Tipo de negocio',
            Icons.category_outlined,
            stepIndex: 1,
          ),
        ]),
        _twoColumns([
          _field(
            _businessPhone,
            'Teléfono del negocio',
            Icons.phone_outlined,
            stepIndex: 1,
            required: false,
          ),
          _field(
            _businessEmail,
            'Correo del negocio',
            Icons.mail_outline,
            stepIndex: 1,
            required: false,
            email: true,
          ),
        ]),
        _twoColumns([
          _field(_country, 'País', Icons.flag_outlined, stepIndex: 1),
          _field(
            _province,
            'Provincia',
            Icons.map_outlined,
            stepIndex: 1,
            required: false,
          ),
        ]),
        _twoColumns([
          _field(
            _city,
            'Ciudad',
            Icons.location_city_outlined,
            stepIndex: 1,
            required: false,
          ),
          _field(
            _address,
            'Dirección',
            Icons.location_on_outlined,
            stepIndex: 1,
            required: false,
          ),
        ]),
      ],
    );
  }

  Widget _summaryStep() {
    return ListView(
      children: [
        _SummaryTile(label: 'Propietario', value: _firstName.text.trim()),
        _SummaryTile(label: 'Correo', value: _email.text.trim()),
        _SummaryTile(label: 'Negocio', value: _commercialName.text.trim()),
        _SummaryTile(label: 'País', value: _country.text.trim()),
        const SizedBox(height: 12),
        const _InfoPanel(
          title: 'Se creará automáticamente',
          text:
              'Empresa, membresía OWNER, configuración inicial, moneda DOP, zona horaria de República Dominicana y acceso inmediato al sistema.',
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    required int stepIndex,
    bool required = true,
    bool email = false,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      validator: (value) {
        if (_step != stepIndex) return null;
        final text = (value ?? '').trim();
        if (required && text.isEmpty) return 'Campo obligatorio';
        if (email && text.isNotEmpty && !text.contains('@')) {
          return 'Correo inválido';
        }
        return null;
      },
      onChanged: (_) {
        if (_step == 2) setState(() {});
      },
    );
  }

  Widget _passwordField(
    TextEditingController controller,
    String label, {
    bool confirm = false,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: _obscurePassword,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: 'Mostrar u ocultar contraseña',
          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          icon: Icon(
            _obscurePassword
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
      validator: (value) {
        if (_step != 0) return null;
        final text = value ?? '';
        if (text.isEmpty) return 'Campo obligatorio';
        if (text.length < 8) return 'Mínimo 8 caracteres';
        if (confirm && text != _password.text) return 'No coincide';
        return null;
      },
    );
  }

  Widget _twoColumns(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            children: [
              for (final child in children)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: child,
                ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: children[0]),
            const SizedBox(width: 12),
            Expanded(child: children[1]),
          ],
        );
      },
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    const labels = ['Cuenta', 'Negocio', 'Listo'];
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          Expanded(
            child: Container(
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: i <= step
                    ? const Color(0xFFEAF1FF)
                    : const Color(0xFFF6F8FB),
                border: Border.all(
                  color: i <= step
                      ? const Color(0xFF9DB9F8)
                      : const Color(0xFFDDE7EE),
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                labels[i],
                style: TextStyle(
                  color: i <= step
                      ? const Color(0xFF1957E6)
                      : const Color(0xFF64748B),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          if (i < labels.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF52667C),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value.isEmpty ? 'Pendiente' : value,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFCFE0FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF123A75),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF52667C),
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
