import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';

enum _LabPhase { welcome, billingOnly, company, done }

const bool _labDiagnosticsEnabled = bool.fromEnvironment(
  'FULLPOS_ONBOARDING_LAB_DIAGNOSTICS',
);

class OnboardingLabScreen extends StatefulWidget {
  const OnboardingLabScreen({super.key});

  @override
  State<OnboardingLabScreen> createState() => _OnboardingLabScreenState();
}

class _OnboardingLabScreenState extends State<OnboardingLabScreen> {
  _LabPhase _phase = _LabPhase.welcome;
  int _companyGuideStep = 0;
  bool _transitionInProgress = false;
  String? _activeTransition;
  int _transitionSequence = 0;

  void _logLabEvent(String event, {String? detail}) {
    if (!kDebugMode || !_labDiagnosticsEnabled) return;
    final now = DateTime.now().toIso8601String();
    debugPrint(
      '[onboarding_lab] $now event=$event '
      'phase=${_phase.name} step=$_companyGuideStep '
      'overlayCount=$_activeOverlayCount '
      'transition=${_activeTransition ?? 'none'}'
      '${detail == null ? '' : ' detail=$detail'}',
    );
  }

  int get _activeOverlayCount => switch (_phase) {
    _LabPhase.welcome || _LabPhase.company => 1,
    _LabPhase.billingOnly || _LabPhase.done => 0,
  };

  Future<void> _runTransition(String name, VoidCallback action) async {
    if (_transitionInProgress) {
      _logLabEvent(
        'transition_ignored',
        detail: 'requested=$name active=$_activeTransition',
      );
      return;
    }
    final sequence = ++_transitionSequence;
    final watch = Stopwatch()..start();
    setState(() {
      _transitionInProgress = true;
      _activeTransition = name;
    });
    _logLabEvent('transition_start', detail: 'name=$name seq=$sequence');
    try {
      if (!mounted) return;
      action();
      await WidgetsBinding.instance.endOfFrame;
    } finally {
      watch.stop();
      if (mounted) {
        setState(() {
          _transitionInProgress = false;
          _activeTransition = null;
        });
      }
      _logLabEvent(
        'transition_end',
        detail: 'name=$name seq=$sequence ms=${watch.elapsedMilliseconds}',
      );
    }
  }

  void _reset() {
    unawaited(
      _runTransition('reset', () {
        setState(() {
          _phase = _LabPhase.welcome;
          _companyGuideStep = 0;
        });
      }),
    );
  }

  void _back() {
    unawaited(
      _runTransition('back', () {
        setState(() {
          if (_phase == _LabPhase.company && _companyGuideStep > 0) {
            _companyGuideStep--;
            return;
          }
          _phase = switch (_phase) {
            _LabPhase.company => _LabPhase.welcome,
            _LabPhase.done => _LabPhase.company,
            _LabPhase.welcome || _LabPhase.billingOnly => _LabPhase.billingOnly,
          };
        });
      }),
    );
  }

  void _nextCompanyStep() {
    unawaited(
      _runTransition('company_next', () {
        if (_companyGuideStep >= 2) return;
        setState(() {
          _companyGuideStep++;
        });
      }),
    );
  }

  void _previousCompanyStep() {
    unawaited(
      _runTransition('company_previous', () {
        if (_companyGuideStep <= 0) return;
        setState(() => _companyGuideStep--);
      }),
    );
  }

  void _beginCompanyGuide() {
    unawaited(
      _runTransition('begin_company_guide', () {
        setState(() {
          _phase = _LabPhase.company;
          _companyGuideStep = 0;
        });
      }),
    );
  }

  void _skipWelcome() {
    unawaited(
      _runTransition('skip_welcome', () {
        setState(() => _phase = _LabPhase.billingOnly);
      }),
    );
  }

  void _finishCompanyGuide() {
    unawaited(
      _runTransition('finish_company_guide', () {
        setState(() => _phase = _LabPhase.done);
      }),
    );
  }

  void _reviewWelcome() {
    unawaited(
      _runTransition('review_welcome', () {
        setState(() => _phase = _LabPhase.welcome);
      }),
    );
  }

  void _exitLab() {
    unawaited(
      _runTransition('exit_lab', () {
        if (mounted) context.go(Routes.cotizaciones);
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _LabPhase.welcome => _LabBillingExperience(
        controls: _LabControls(
          onReset: _reset,
          onBack: _back,
          onExit: _exitLab,
        ),
        overlay: _WelcomeOverlay(
          onBegin: _beginCompanyGuide,
          onSkip: _skipWelcome,
        ),
      ),
      _LabPhase.billingOnly => _LabBillingExperience(
        controls: _LabControls(
          onReset: _reset,
          onBack: _back,
          onExit: _exitLab,
        ),
      ),
      _LabPhase.company => _LabCompanyExperience(
        controls: _LabControls(
          onReset: _reset,
          onBack: _back,
          onExit: _exitLab,
        ),
        step: _companyGuideStep,
        onPrevious: _companyGuideStep == 0 ? null : _previousCompanyStep,
        onNext: _nextCompanyStep,
        onSave: _finishCompanyGuide,
        onExit: _exitLab,
      ),
      _LabPhase.done => _LabPhaseDone(
        controls: _LabControls(
          onReset: _reset,
          onBack: _back,
          onExit: _exitLab,
        ),
        onReview: _reviewWelcome,
      ),
    };
  }
}

class _LabBillingExperience extends StatelessWidget {
  const _LabBillingExperience({required this.controls, this.overlay});

  final Widget controls;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: _LockedBillingBackground()),
        if (overlay != null)
          Positioned.fill(child: _BlurredOverlay(child: overlay!)),
        controls,
      ],
    );
  }
}

class _LockedBillingBackground extends StatelessWidget {
  const _LockedBillingBackground();

  @override
  Widget build(BuildContext context) {
    return const ExcludeSemantics(child: _BillingPreview());
  }
}

class _LockedCompanySettingsBackground extends StatelessWidget {
  const _LockedCompanySettingsBackground();

  @override
  Widget build(BuildContext context) {
    return const ExcludeSemantics(child: _CompanySettingsPreview());
  }
}

class _BlurredOverlay extends StatelessWidget {
  const _BlurredOverlay({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FocusScope(
      autofocus: true,
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
              child: ColoredBox(
                color: AppColors.primaryDark.withValues(alpha: 0.18),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 24,
                ),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeOverlay extends StatelessWidget {
  const _WelcomeOverlay({required this.onBegin, required this.onSkip});

  final VoidCallback onBegin;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0.96, end: 1),
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0, 1),
          child: Transform.scale(scale: value, child: child),
        );
      },
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          child: Container(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < 480 ? 22 : 28,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 34,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: AppColors.primary,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '¡Bienvenido a Fullpos Cloud!',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                    height: 1.08,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Gracias por elegirnos. Vamos a ayudarte a realizar la configuracion basica de tu negocio y dejar todo listo para que puedas hacer tu primera venta de prueba.',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.42,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 12),
                const _SubtleLine(
                  icon: Icons.tune_rounded,
                  text: 'Solo configuraremos lo que realmente necesitas.',
                ),
                const SizedBox(height: 18),
                const _CoachHint(
                  text:
                      'Pulsa aquí para iniciar la configuración guiada de tu negocio.',
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: onBegin,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Comenzar configuración'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onSkip,
                  child: const Text('Omitir por ahora'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LabCompanyExperience extends StatelessWidget {
  const _LabCompanyExperience({
    required this.controls,
    required this.step,
    required this.onNext,
    required this.onPrevious,
    required this.onSave,
    required this.onExit,
  });

  final Widget controls;
  final int step;
  final VoidCallback onNext;
  final VoidCallback? onPrevious;
  final VoidCallback onSave;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: _LockedCompanySettingsBackground()),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.primaryDark.withValues(alpha: 0.045),
              ),
            ),
          ),
        ),
        _SectionHighlight(step: step),
        _CompanyGuideOverlay(
          step: step,
          onNext: onNext,
          onPrevious: onPrevious,
          onSave: onSave,
          onExit: onExit,
        ),
        controls,
      ],
    );
  }
}

class _CompanyGuideOverlay extends StatelessWidget {
  const _CompanyGuideOverlay({
    required this.step,
    required this.onNext,
    required this.onPrevious,
    required this.onSave,
    required this.onExit,
  });

  final int step;
  final VoidCallback onNext;
  final VoidCallback? onPrevious;
  final VoidCallback onSave;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 720;
    final current = _CompanyGuideStepData.forStep(step);
    final cardTop = compact ? 112.0 : 126.0;
    return SafeArea(
      child: Stack(
        children: [
          Positioned(
            left: compact ? 16 : 24,
            right: compact ? 16 : null,
            top: cardTop,
            child: _GuideCard(
              stepLabel: current.stepLabel,
              title: current.title,
              text: current.text,
              bullets: current.bullets,
              primaryLabel: step >= 2 ? 'Guardar y continuar' : 'Siguiente',
              onPrimary: step >= 2 ? onSave : onNext,
              onPrevious: onPrevious,
              onSkip: onExit,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanyGuideStepData {
  const _CompanyGuideStepData({
    required this.stepLabel,
    required this.title,
    required this.text,
    required this.bullets,
  });

  final String stepLabel;
  final String title;
  final String text;
  final List<String> bullets;

  static _CompanyGuideStepData forStep(int step) {
    return switch (step) {
      0 => const _CompanyGuideStepData(
        stepLabel: 'Guía de empresa · 1 de 3',
        title: 'Configura tu empresa',
        text:
            'Revisa los datos principales de tu negocio y activa solamente las funciones que vas a utilizar.',
        bullets: [
          'Revisa los datos principales.',
          'Sube tu logo si deseas personalizar Fullpos.',
          'Activa únicamente las funciones que necesites.',
          'Podrás cambiar estas opciones más adelante.',
        ],
      ),
      1 => const _CompanyGuideStepData(
        stepLabel: 'Guía de empresa · 2 de 3',
        title: 'Impuestos y comprobantes',
        text:
            'Activa impuestos solo si tu negocio maneja ITBIS. Los comprobantes fiscales deben usarse únicamente si emites NCF.',
        bullets: [
          'No actives opciones fiscales que no usarás.',
          'Si impuestos está apagado, NCF no será necesario.',
        ],
      ),
      _ => const _CompanyGuideStepData(
        stepLabel: 'Guía de empresa · 3 de 3',
        title: 'Inventario y unidades',
        text:
            'Revisa si controlarás existencias, unidades de medida o almacenes. La idea es dejar activo solo lo que realmente utilizarás.',
        bullets: [
          'Inventario controla existencias al vender y comprar.',
          'Unidades permite libra, metro, kilogramo y otras medidas.',
          'Múltiples almacenes solo si manejas varias ubicaciones.',
        ],
      ),
    };
  }
}

class _SectionHighlight extends StatelessWidget {
  const _SectionHighlight({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 720;
    final top = switch (step) {
      0 => compact ? 205.0 : 245.0,
      1 => compact ? 275.0 : 325.0,
      _ => compact ? 360.0 : 430.0,
    };
    final height = switch (step) {
      0 => compact ? 175.0 : 172.0,
      1 => compact ? 125.0 : 122.0,
      _ => compact ? 215.0 : 204.0,
    };
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      left: compact ? 12 : 452,
      right: compact ? 12 : 492,
      top: top,
      height: height,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.55),
              width: 2,
            ),
            color: AppColors.primarySoft.withValues(alpha: 0.16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.12),
                blurRadius: 24,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({
    required this.stepLabel,
    required this.title,
    required this.text,
    required this.bullets,
    required this.primaryLabel,
    required this.onPrimary,
    required this.onPrevious,
    required this.onSkip,
  });

  final String stepLabel;
  final String title;
  final String text;
  final List<String> bullets;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback? onPrevious;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.secondaryBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.secondaryBorder),
                  ),
                  child: Text(
                    stepLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.north_west_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              for (final bullet in bullets) ...[
                _GuideBullet(text: bullet),
                const SizedBox(height: 6),
              ],
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: onPrimary,
                icon: Icon(
                  primaryLabel == 'Siguiente'
                      ? Icons.arrow_forward_rounded
                      : Icons.check_rounded,
                ),
                label: Text(primaryLabel),
              ),
              Row(
                children: [
                  if (onPrevious != null)
                    TextButton(
                      onPressed: onPrevious,
                      child: const Text('Atrás'),
                    ),
                  const Spacer(),
                  TextButton(onPressed: onSkip, child: const Text('Omitir')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuideBullet extends StatelessWidget {
  const _GuideBullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(top: 1),
          decoration: const BoxDecoration(
            color: AppColors.primarySoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_rounded,
            color: AppColors.primary,
            size: 13,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              height: 1.28,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _LabPhaseDone extends StatelessWidget {
  const _LabPhaseDone({required this.controls, required this.onReview});

  final Widget controls;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                margin: const EdgeInsets.all(18),
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.check_circle_outline_rounded,
                        color: AppColors.success,
                        size: 52,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Configuración de empresa simulada correctamente.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Esta fase termina aquí. No se guardó nada en la empresa real.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: onReview,
                        child: const Text('Revisar bienvenida otra vez'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          controls,
        ],
      ),
    );
  }
}

class _LabControls extends StatelessWidget {
  const _LabControls({
    required this.onReset,
    required this.onBack,
    required this.onExit,
  });

  final VoidCallback onReset;
  final VoidCallback onBack;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 520;
    return Positioned(
      right: compact ? 10 : 16,
      top: compact ? 10 : 16,
      child: SafeArea(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    'Laboratorio de configuración',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                _LabControlButton(
                  label: 'Reiniciar',
                  icon: Icons.restart_alt_rounded,
                  onPressed: onReset,
                ),
                _LabControlButton(
                  label: 'Volver',
                  icon: Icons.arrow_back_rounded,
                  onPressed: onBack,
                ),
                _LabControlButton(
                  label: 'Salir',
                  icon: Icons.close_rounded,
                  onPressed: onExit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BillingPreview extends StatelessWidget {
  const _BillingPreview();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Row(
          children: [
            if (!compact) const _PreviewNavRail(),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(compact ? 14 : 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _PreviewHeader(
                      title: 'Facturación',
                      subtitle: 'Prepara una venta de prueba',
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            flex: 3,
                            child: _PreviewPanel(
                              title: 'Productos',
                              child: GridView.count(
                                crossAxisCount: compact ? 2 : 3,
                                mainAxisSpacing: 10,
                                crossAxisSpacing: 10,
                                childAspectRatio: compact ? 1.35 : 1.5,
                                physics: const NeverScrollableScrollPhysics(),
                                children: const [
                                  _ProductPreviewTile(
                                    name: 'Café',
                                    price: 'RD\$ 120.00',
                                  ),
                                  _ProductPreviewTile(
                                    name: 'Agua',
                                    price: 'RD\$ 45.00',
                                  ),
                                  _ProductPreviewTile(
                                    name: 'Postre',
                                    price: 'RD\$ 180.00',
                                  ),
                                  _ProductPreviewTile(
                                    name: 'Servicio',
                                    price: 'RD\$ 250.00',
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (!compact) ...[
                            const SizedBox(width: 16),
                            const Expanded(
                              flex: 2,
                              child: _PreviewPanel(
                                title: 'Ticket',
                                child: _TicketPreview(),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompanySettingsPreview extends StatelessWidget {
  const _CompanySettingsPreview();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 760;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Row(
          children: [
            if (!compact) const _PreviewNavRail(),
            Expanded(
              child: ListView(
                padding: EdgeInsets.all(compact ? 14 : 22),
                children: const [
                  _PreviewHeader(
                    title: 'Empresa',
                    subtitle:
                        'Datos usados en facturas, cotizaciones, tickets y reportes.',
                  ),
                  SizedBox(height: 16),
                  _PreviewPanel(
                    title: 'Datos de empresa',
                    expandChild: false,
                    child: Column(
                      children: [
                        _SettingsPreviewRow(
                          label: 'Nombre comercial',
                          value: 'prueva 7',
                        ),
                        _SettingsPreviewRow(
                          label: 'Teléfono',
                          value: '809-000-0000',
                        ),
                        _SettingsPreviewRow(
                          label: 'Dirección',
                          value: 'Dirección de prueba',
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 14),
                  _PreviewPanel(
                    title: 'Funciones activas',
                    expandChild: false,
                    child: Column(
                      children: [
                        _SwitchPreviewRow(label: 'Impuestos', active: false),
                        _SwitchPreviewRow(
                          label: 'Comprobantes fiscales',
                          active: false,
                        ),
                        _SwitchPreviewRow(label: 'Inventario', active: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewNavRail extends StatelessWidget {
  const _PreviewNavRail();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      color: AppColors.primaryDark,
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: const Column(
        children: [
          Icon(Icons.storefront_rounded, color: Colors.white, size: 28),
          SizedBox(height: 28),
          _PreviewNavIcon(icon: Icons.point_of_sale_rounded, active: true),
          _PreviewNavIcon(icon: Icons.inventory_2_outlined),
          _PreviewNavIcon(icon: Icons.settings_outlined),
        ],
      ),
    );
  }
}

class _PreviewNavIcon extends StatelessWidget {
  const _PreviewNavIcon({required this.icon, this.active = false});

  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: active ? Colors.white.withValues(alpha: 0.18) : null,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.business_center, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
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

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({
    required this.title,
    required this.child,
    this.expandChild = true,
  });

  final String title;
  final Widget child;
  final bool expandChild;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          if (expandChild) Expanded(child: child) else child,
        ],
      ),
    );
  }
}

class _ProductPreviewTile extends StatelessWidget {
  const _ProductPreviewTile({required this.name, required this.price});

  final String name;
  final String price;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
          ),
          Text(
            price,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketPreview extends StatelessWidget {
  const _TicketPreview();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SettingsPreviewRow(label: 'Cliente', value: 'Sin cliente'),
        _SettingsPreviewRow(label: 'Subtotal', value: 'RD\$ 345.00'),
        _SettingsPreviewRow(label: 'ITBIS', value: 'RD\$ 0.00'),
        Spacer(),
        _SettingsPreviewRow(label: 'Total', value: 'RD\$ 345.00'),
      ],
    );
  }
}

class _SettingsPreviewRow extends StatelessWidget {
  const _SettingsPreviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _SwitchPreviewRow extends StatelessWidget {
  const _SwitchPreviewRow({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Icon(
            active ? Icons.toggle_on_rounded : Icons.toggle_off_outlined,
            color: active ? AppColors.success : AppColors.textMuted,
            size: 34,
          ),
        ],
      ),
    );
  }
}

class _LabControlButton extends StatelessWidget {
  const _LabControlButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        color: AppColors.primary,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      ),
    );
  }
}

class _SubtleLine extends StatelessWidget {
  const _SubtleLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachHint extends StatelessWidget {
  const _CoachHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) {
        final offset = 3 * (1 - value);
        return Transform.translate(offset: Offset(0, offset), child: child);
      },
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 310),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.secondaryBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.south_east_rounded,
                    color: AppColors.primary,
                    size: 17,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      text,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
