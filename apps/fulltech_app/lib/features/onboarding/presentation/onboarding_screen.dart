import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/company/company_settings_repository.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../catalogo/data/catalog_repository.dart';
import '../data/onboarding_repository.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _rnc = TextEditingController();
  final _productName = TextEditingController();
  final _productPrice = TextEditingController(text: '100');

  OnboardingStateModel? _state;
  bool _loading = true;
  bool _saving = false;
  int _step = 0;
  bool _taxEnabled = false;
  bool _ncfEnabled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _address.dispose();
    _rnc.dispose();
    _productName.dispose();
    _productPrice.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final state = await ref.read(onboardingRepositoryProvider).getState();
      if (!mounted) return;
      _hydrate(state);
      setState(() {
        _state = state;
        _step = state.shouldShowWelcome ? 0 : _firstPendingStep(state);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _errorText(error);
        _loading = false;
      });
    }
  }

  void _hydrate(OnboardingStateModel state) {
    _name.text = state.company.commercialName;
    _phone.text = state.company.phone;
    _address.text = state.company.address;
    _rnc.text = state.company.rnc;
    _taxEnabled = state.company.taxEnabled;
    _ncfEnabled = state.company.ncfEnabled;
  }

  int _firstPendingStep(OnboardingStateModel state) {
    const keys = ['company', 'billing', 'product', 'ready'];
    final index = keys.indexWhere((key) => state.steps[key] == 'PENDING');
    return index < 0 ? 4 : index + 1;
  }

  Future<void> _start() async {
    await _run(() async {
      final state = await ref.read(onboardingRepositoryProvider).start();
      _hydrate(state);
      setState(() {
        _state = state;
        _step = 1;
      });
    });
  }

  Future<void> _skipAll() async {
    await _run(() async {
      await ref.read(onboardingRepositoryProvider).skipAll();
      await _finishToApp(refreshUser: true);
    });
  }

  Future<void> _skipStep() async {
    final stepKey = _stepKey;
    if (stepKey == null) return;
    await _run(() async {
      final completeFlow = stepKey == 'ready';
      final state = await ref
          .read(onboardingRepositoryProvider)
          .setStep(stepKey, 'SKIPPED', completeFlow: completeFlow);
      setState(() {
        _state = state;
        _step = completeFlow ? 5 : (_step + 1).clamp(1, 4);
      });
      if (completeFlow) await _finishToApp(refreshUser: true);
    });
  }

  Future<void> _saveCurrentStep() async {
    final stepKey = _stepKey;
    if (stepKey == null) return;
    await _run(() async {
      if (stepKey == 'company') {
        await _saveCompany();
      } else if (stepKey == 'billing') {
        await _saveBilling();
      } else if (stepKey == 'product') {
        await _saveProductIfNeeded();
      }
      final completeFlow = stepKey == 'ready';
      final state = await ref
          .read(onboardingRepositoryProvider)
          .setStep(stepKey, 'COMPLETED', completeFlow: completeFlow);
      setState(() {
        _state = state;
        _step = completeFlow ? 5 : (_step + 1).clamp(1, 4);
      });
      if (completeFlow) await _finishToApp(refreshUser: true);
    });
  }

  Future<void> _saveCompany() async {
    final repo = ref.read(companySettingsRepositoryProvider);
    final current = await repo.getSettings();
    final name = _name.text.trim();
    if (name.isNotEmpty && name != current.companyName.trim()) {
      await repo.saveCompanyNameOrQueue(name);
    }
    await repo.saveSettingsOrQueue(
      current.copyWith(
        rnc: _rnc.text.trim(),
        phone: _phone.text.trim(),
        address: _address.text.trim(),
      ),
    );
    ref.invalidate(companySettingsProvider);
  }

  Future<void> _saveBilling() async {
    final repo = ref.read(companySettingsRepositoryProvider);
    final current = await repo.getSettings();
    await repo.saveSettingsOrQueue(
      current.copyWith(taxEnabled: _taxEnabled, ncfEnabled: _ncfEnabled),
    );
    ref.invalidate(companySettingsProvider);
  }

  Future<void> _saveProductIfNeeded() async {
    if ((_state?.productCount ?? 0) > 0) return;
    final name = _productName.text.trim();
    if (name.isEmpty) return;
    final price = double.tryParse(_productPrice.text.trim()) ?? 0;
    await ref
        .read(catalogRepositoryProvider)
        .createProduct(
          nombre: name,
          precio: price <= 0 ? 1 : price,
          costo: 0,
          stock: 0,
          categoria: 'General',
          operationId: 'onboarding-${DateTime.now().microsecondsSinceEpoch}',
          skipLoader: true,
        );
  }

  Future<void> _finishToApp({bool refreshUser = false}) async {
    if (refreshUser) {
      await ref.read(authStateProvider.notifier).refreshCurrentUser();
    }
    if (!mounted) return;
    context.go(Routes.cotizaciones);
  }

  Future<void> _startTutorial() async {
    await _run(() async {
      await ref.read(onboardingRepositoryProvider).setTutorial('STARTED');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => const _TutorialDialog(),
      );
      await ref.read(onboardingRepositoryProvider).setTutorial('COMPLETED');
      await _finishToApp(refreshUser: true);
    });
  }

  Future<void> _skipTutorial() async {
    await _run(() async {
      await ref.read(onboardingRepositoryProvider).setTutorial('SKIPPED');
      await _finishToApp(refreshUser: true);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _errorText(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? get _stepKey {
    return switch (_step) {
      1 => 'company',
      2 => 'billing',
      3 => 'product',
      4 => 'ready',
      _ => null,
    };
  }

  String _errorText(Object error) {
    if (error is ApiException) return error.message;
    return 'No se pudo guardar. Intenta nuevamente.';
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 840;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isWide ? 1040 : 560),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildContent(isWide),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(bool isWide) {
    if (_error != null && _state == null) {
      return _OnboardingShell(
        step: _step,
        child: _StateMessage(
          title: 'No pudimos cargar la preparacion',
          message: _error!,
          actionLabel: 'Reintentar',
          onAction: _load,
        ),
      );
    }

    return _OnboardingShell(
      step: _step,
      error: _error,
      side: isWide ? _SidePanel(state: _state) : null,
      footer: _step == 0 || _step == 5
          ? null
          : _StepActions(
              step: _step,
              saving: _saving,
              onBack: _step > 1 ? () => setState(() => _step--) : null,
              onSkip: _skipStep,
              onContinue: _saveCurrentStep,
            ),
      child: switch (_step) {
        0 => _WelcomeStep(
          trialEndsAt: _state?.trialEndsAt,
          saving: _saving,
          onStart: _start,
          onSkip: _skipAll,
        ),
        1 => _CompanyStep(
          name: _name,
          phone: _phone,
          address: _address,
          rnc: _rnc,
        ),
        2 => _BillingStep(
          taxEnabled: _taxEnabled,
          ncfEnabled: _ncfEnabled,
          onTaxChanged: (value) => setState(() => _taxEnabled = value),
          onNcfChanged: (value) => setState(() => _ncfEnabled = value),
        ),
        3 => _ProductStep(
          alreadyHasProduct: (_state?.productCount ?? 0) > 0,
          productName: _productName,
          productPrice: _productPrice,
        ),
        4 => const _ReadyStep(),
        _ => _TutorialOffer(onStart: _startTutorial, onSkip: _skipTutorial),
      },
    );
  }
}

class _OnboardingShell extends StatelessWidget {
  const _OnboardingShell({
    required this.step,
    required this.child,
    this.side,
    this.footer,
    this.error,
  });

  final int step;
  final Widget child;
  final Widget? side;
  final Widget? footer;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(step: step),
          const SizedBox(height: 18),
          if (error != null) ...[
            _ErrorBanner(message: error!),
            const SizedBox(height: 12),
          ],
          child,
          if (footer != null) ...[const SizedBox(height: 18), footer!],
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 840 && side != null;
        return SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: side!,
                          ),
                        ),
                        SizedBox(width: 520, child: content),
                      ],
                    )
                  : content,
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final progress = step <= 0 ? 0.08 : (step.clamp(1, 4) / 4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.storefront, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'FullPOS Cloud',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            Text(
              step <= 0 || step > 4 ? '' : '$step de 4',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: progress.toDouble(),
            minHeight: 5,
            color: AppColors.primary,
            backgroundColor: AppColors.surfaceMuted,
          ),
        ),
      ],
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({
    required this.trialEndsAt,
    required this.saving,
    required this.onStart,
    required this.onSkip,
  });

  final DateTime? trialEndsAt;
  final bool saving;
  final VoidCallback onStart;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepTitle(
          title: 'Tu cuenta está lista',
          text:
              'Vamos a preparar FullPOS Cloud para que puedas vender, organizar productos y configurar lo esencial sin complicarte.',
        ),
        if (trialEndsAt != null) ...[
          const SizedBox(height: 10),
          _InfoPill(text: 'Prueba activa hasta ${_dateText(trialEndsAt!)}'),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: saving ? null : onStart,
          child: const Text('Comenzar configuración'),
        ),
        TextButton(
          onPressed: saving ? null : onSkip,
          child: const Text('Omitir configuración'),
        ),
      ],
    );
  }
}

class _CompanyStep extends StatelessWidget {
  const _CompanyStep({
    required this.name,
    required this.phone,
    required this.address,
    required this.rnc,
  });

  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController address;
  final TextEditingController rnc;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepTitle(
          title: 'Datos de tu negocio',
          text:
              'Confirma la información básica que aparecerá en documentos y tickets.',
        ),
        _Field(
          controller: name,
          label: 'Nombre del negocio',
          textInputAction: TextInputAction.next,
        ),
        _Field(
          controller: phone,
          label: 'Teléfono',
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
        ),
        _Field(
          controller: address,
          label: 'Dirección',
          textInputAction: TextInputAction.next,
        ),
        _Field(
          controller: rnc,
          label: 'RNC',
          keyboardType: TextInputType.number,
        ),
      ],
    );
  }
}

class _BillingStep extends StatelessWidget {
  const _BillingStep({
    required this.taxEnabled,
    required this.ncfEnabled,
    required this.onTaxChanged,
    required this.onNcfChanged,
  });

  final bool taxEnabled;
  final bool ncfEnabled;
  final ValueChanged<bool> onTaxChanged;
  final ValueChanged<bool> onNcfChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepTitle(
          title: 'Facturación',
          text:
              'Activa solo lo que uses hoy. Puedes cambiarlo luego desde Configuración.',
        ),
        _SwitchTile(
          title: 'Manejo impuestos',
          subtitle: 'Permite trabajar con ITBIS según tus reglas actuales.',
          value: taxEnabled,
          onChanged: onTaxChanged,
        ),
        _SwitchTile(
          title: 'Utilizo comprobantes fiscales',
          subtitle:
              'No configura secuencias automáticamente; solo habilita el flujo.',
          value: ncfEnabled,
          onChanged: onNcfChanged,
        ),
      ],
    );
  }
}

class _ProductStep extends StatelessWidget {
  const _ProductStep({
    required this.alreadyHasProduct,
    required this.productName,
    required this.productPrice,
  });

  final bool alreadyHasProduct;
  final TextEditingController productName;
  final TextEditingController productPrice;

  @override
  Widget build(BuildContext context) {
    if (alreadyHasProduct) {
      return const _StateMessage(
        title: 'Ya tienes productos',
        message: 'Detectamos productos en tu catálogo. Este paso está listo.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepTitle(
          title: 'Tu primer producto',
          text:
              'Agrega un producto simple para empezar a vender. Luego podrás completar inventario, imágenes y categorías.',
        ),
        _Field(
          controller: productName,
          label: 'Producto',
          textInputAction: TextInputAction.next,
        ),
        _Field(
          controller: productPrice,
          label: 'Precio de venta',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      ],
    );
  }
}

class _ReadyStep extends StatelessWidget {
  const _ReadyStep();

  @override
  Widget build(BuildContext context) {
    return const _StepTitle(
      title: 'Listo para vender',
      text:
          'Ya puedes entrar al sistema. Si aún no agregaste productos, FullPOS seguirá funcionando y podrás completar el catálogo después.',
    );
  }
}

class _TutorialOffer extends StatelessWidget {
  const _TutorialOffer({required this.onStart, required this.onSkip});

  final VoidCallback onStart;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepTitle(
          title: '¿Primera vez usando FullPOS?',
          text:
              'Te mostramos en menos de un minuto dónde están las áreas principales.',
        ),
        FilledButton(onPressed: onStart, child: const Text('Ver recorrido')),
        TextButton(onPressed: onSkip, child: const Text('Ahora no')),
      ],
    );
  }
}

class _StepActions extends StatelessWidget {
  const _StepActions({
    required this.step,
    required this.saving,
    required this.onBack,
    required this.onSkip,
    required this.onContinue,
  });

  final int step;
  final bool saving;
  final VoidCallback? onBack;
  final VoidCallback onSkip;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: saving ? null : onContinue,
          child: Text(step == 4 ? 'Ir al sistema' : 'Guardar y continuar'),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: saving ? null : onSkip,
          child: const Text('Omitir por ahora'),
        ),
        if (onBack != null)
          TextButton(
            onPressed: saving ? null : onBack,
            child: const Text('Atrás'),
          ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(16),
        color: AppColors.surfaceAlt,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 25,
            height: 1.08,
            fontWeight: FontWeight.w900,
            color: AppColors.primaryDark,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          text,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({required this.state});

  final OnboardingStateModel? state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Prepara tu negocio sin perder ritmo',
            style: TextStyle(
              fontSize: 34,
              height: 1.06,
              fontWeight: FontWeight.w900,
              color: AppColors.primaryDark,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '${state?.reviewedSteps ?? 0} de 4 pasos revisados',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.successSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.successBorder),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.success,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorSoft,
        border: Border.all(color: AppColors.errorBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: AppColors.error,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepTitle(title: title, text: message),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 18),
          FilledButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    );
  }
}

class _TutorialDialog extends StatefulWidget {
  const _TutorialDialog();

  @override
  State<_TutorialDialog> createState() => _TutorialDialogState();
}

class _TutorialDialogState extends State<_TutorialDialog> {
  int _index = 0;

  static const _items = [
    (
      'Navegación',
      'Desde el menú puedes acceder a ventas, productos, caja y reportes.',
    ),
    (
      'Productos y venta',
      'Busca o agrega productos antes de preparar una venta.',
    ),
    ('Cobrar', 'Cuando todo esté listo, completa la operación desde Cobrar.'),
  ];

  @override
  Widget build(BuildContext context) {
    final item = _items[_index];
    final last = _index == _items.length - 1;
    return AlertDialog(
      title: Text('${_index + 1}/3 - ${item.$1}'),
      content: Text(item.$2),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Omitir tutorial'),
        ),
        FilledButton(
          onPressed: () {
            if (last) {
              Navigator.pop(context);
            } else {
              setState(() => _index++);
            }
          },
          child: Text(last ? 'Entendido' : 'Siguiente'),
        ),
      ],
    );
  }
}

String _dateText(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}
