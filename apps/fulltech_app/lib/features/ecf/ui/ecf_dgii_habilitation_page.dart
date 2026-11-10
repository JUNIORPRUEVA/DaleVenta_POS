import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/company/company_settings_model.dart';
import '../../../core/company/company_settings_repository.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_feedback.dart';
import '../../../core/widgets/responsive_shell.dart';
import '../data/ecf_certification_repository.dart';
import '../data/ecf_certificate_repository.dart';
import '../data/ecf_platform_repository.dart';
import '../data/ecf_repository.dart';
import '../dosa/dosa_assistant_section.dart';
import '../dosa/dosa_certification_diagnostic_section.dart';
import '../dosa/dosa_certification_intent_api.dart';
import '../domain/ecf_fiscal_readiness.dart';
import '../ecf_certificate_models.dart';
import '../ecf_certification_models.dart';
import '../ecf_models.dart';
import 'ecf_activation_page.dart';
import 'ecf_certificate_card.dart';
import 'ecf_dgii_application_wizard.dart';
import 'ecf_fiscal_data_page.dart';
import 'ecf_postulation_xml_card.dart';
import 'ecf_support_grant_card.dart';
import 'debug/ecf_debug_screen_selector.dart';
import 'flow/ecf_dosa_activation_status.dart';
import 'flow/ecf_sequence_range_section.dart';
import 'flow/ecf_dosa_tracking_step.dart';
import 'flow/ecf_flow_kit.dart';
import 'flow/ecf_flow_step.dart';
import 'flow/ecf_preparation_step.dart';
import 'flow/ecf_tracking_step.dart';
import 'flow/ecf_welcome_step.dart';

/// Habilitación DGII **por empresa**, dentro del módulo e-CF.
///
/// Reglas de la pantalla, alineadas con el backend:
///
///  * Separa de forma visible el **seguimiento interno** (lo que la empresa
///    gestiona) de la **autorización oficial de la DGII** (un hecho externo que
///    se registra con evidencia, no se concede desde aquí).
///  * **No** ofrece ningún botón para declarar la empresa aprobada. `APPROVED`
///    no aparece entre los estados seleccionables: el backend lo rechazaría sin
///    un registro oficial verificado.
///  * **No** emite nada. El estado de emisión que muestra es el que reporta la
///    compuerta del backend, que mantiene `realEmissionAuthorized` en `false`.
///  * Todos los datos provienen de la empresa autenticada: la aplicación nunca
///    envía un `companyId`.
class EcfDgiiHabilitationPage extends ConsumerStatefulWidget {
  const EcfDgiiHabilitationPage({super.key, this.adminView = false});

  /// Interfaz administrativa separada: diagnóstico, detalle técnico,
  /// evidencias y autorización histórica. Nunca forma parte del recorrido del
  /// cliente; se abre en su propia ruta y exige el permiso administrativo.
  final bool adminView;

  @override
  ConsumerState<EcfDgiiHabilitationPage> createState() =>
      _EcfDgiiHabilitationPageState();
}

class _EcfDgiiHabilitationPageState
    extends ConsumerState<EcfDgiiHabilitationPage> {
  bool _busy = false;
  EcfDebugScreen? _debugScreen;
  bool _applicationOpen = false;
  bool _fiscalOpen = false;
  bool _certificateOpen = false;
  bool _activationOpen = false;
  bool _submissionGuideOpen = false;

  /// Informe temporal para mostrar el resultado sin volver a cargar el archivo.
  ///
  /// El avance se decide con la respuesta persistida del backend. El informe
  /// temporal se invalida al cambiar archivo o contraseña.
  EcfCertificateReport? _verifiedCertificate;
  String? _verifiedCertificateFileName;
  bool _certificateRestarted = false;

  /// Paso del recorrido que se está mostrando.
  ///
  /// Mientras sea `null` se deduce del expediente real, así que al volver a la
  /// pantalla se entra en la etapa en la que está la empresa y nunca se reinicia
  /// el proceso. Solo cambia cuando la persona navega con los botones.
  EcfFlowStep? _step;

  final _wizardKey = GlobalKey<EcfDgiiApplicationWizardState>();
  String? _error;

  void _goToStep(EcfFlowStep step) {
    setState(() => _step = step);
  }

  void _navigateBack() {
    if (kDebugMode && _debugScreen != null) {
      setState(() => _debugScreen = null);
      return;
    }
    if (_applicationOpen) {
      _wizardKey.currentState?.goBack();
      return;
    }
    if (_activationOpen) {
      setState(() => _activationOpen = false);
      return;
    }
    if (_certificateOpen) {
      setState(() => _certificateOpen = false);
      return;
    }
    if (_fiscalOpen) {
      setState(() => _fiscalOpen = false);
      return;
    }
    final step = _step;
    if (step != null && step.index > 0) {
      setState(() => _step = EcfFlowStep.values[step.index - 1]);
      return;
    }
    context.go(Routes.configuracion);
  }

  bool get _canGoBack =>
      (kDebugMode && _debugScreen != null) ||
      _applicationOpen ||
      _activationOpen ||
      _certificateOpen ||
      _fiscalOpen ||
      (_step != null && _step != EcfFlowStep.welcome);

  /// Publica el acceso a «Ayuda y soporte» en la barra del shell.
  ///
  /// La pantalla no tiene barra propia: el icono vive en la del shell y solo se
  /// muestra mientras la ruta sea esta.
  @override
  void initState() {
    super.initState();
    ref.listenManual(
      authStateProvider.select((state) => (
        state.isAuthenticated,
        state.user?.id,
        state.user?.companyId,
      )),
      (previous, next) {
        if (previous == next || !mounted) return;
        // Todo lo que muestra esta pantalla pertenece a la empresa y a la
        // sesión: al cambiar de empresa se descarta para no enseñar el
        // expediente, la preparación ni el intento de la empresa anterior.
        ref.invalidate(ecfDgiiHabilitationProvider);
        ref.invalidate(ecfDgiiHistoryProvider);
        ref.invalidate(ecfPreparationProvider);
        ref.invalidate(ecfActivationProgressProvider);
        ref.invalidate(ecfSupportGrantsProvider);
        ref.invalidate(companySettingsProvider);
        ref.invalidate(dosaIntentStateProvider);
        setState(() {
          _step = null;
          _debugScreen = null;
          _fiscalOpen = false;
          _certificateOpen = false;
          _applicationOpen = false;
          _activationOpen = false;
          _verifiedCertificate = null;
          _verifiedCertificateFileName = null;
          _certificateRestarted = false;
        });
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref
          .read(desktopShellRouteActionsProvider.notifier)
          .state = DesktopShellRouteActions(
        route: Routes.ecf,
        onBack: _navigateBack,
        actions: [
          DesktopShellActionItem(
            icon: Icons.headset_mic_outlined,
            tooltip: 'Ayuda y soporte',
            onPressed: _openSupport,
          ),
          // Exclusivo de depuración. En release esta rama es constante y el
          // selector no se registra ni se puede habilitar por URL/dart-define.
          if (kDebugMode)
            DesktopShellActionItem(
              icon: Icons.visibility_outlined,
              tooltip: 'Ver pantallas (solo depuración)',
              label: 'Ver pantallas',
              onPressed: _showDebugScreens,
            ),
        ],
      );
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(ecfDgiiHabilitationProvider);
    ref.invalidate(companySettingsProvider);
    ref.invalidate(ecfDgiiHistoryProvider);
    ref.invalidate(ecfSupportGrantsProvider);
    try {
      await ref.read(ecfDgiiHabilitationProvider.future);
    } catch (_) {
      // Si el servidor sigue fallando, el propio estado del provider ya pinta la
      // tarjeta de error. Se captura aquí para que al reintentar no quede una
      // excepción asíncrona sin manejar.
    }
  }

  /// Ejecuta una mutación con protección contra doble pulsación y un error
  /// legible. Nunca lanza: la interfaz debe seguir usable tras un fallo.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      ref.invalidate(ecfDgiiHabilitationProvider);
      ref.invalidate(ecfDgiiHistoryProvider);
      await ref.read(ecfDgiiHabilitationProvider.future);
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'No se pudo completar la operación. Inténtalo de nuevo.';
      });
    }
  }

  Future<void> _advance(EcfDgiiHabilitationView view) async {
    final next = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Avanzar el seguimiento interno'),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Este estado es interno del proceso. No acredita autorización de '
              'la DGII ni habilita la emisión.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          if (view.allowedNextStates.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'No hay transiciones disponibles desde el estado actual.',
              ),
            ),
          for (final state in view.allowedNextStates)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(state),
              child: Text(EcfDgiiHabilitationView.labelForState(state)),
            ),
        ],
      ),
    );
    if (next == null) return;
    await _run(
      () => ref.read(ecfRepositoryProvider).updateDgiiHabilitation(state: next),
    );
  }

  Future<void> _editObservations(EcfDgiiHabilitationView view) async {
    final controller = TextEditingController(text: view.observations ?? '');
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Observaciones'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          maxLength: 2000,
          decoration: const InputDecoration(
            hintText: 'Notas internas del proceso de habilitación',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (saved == null) return;
    await _run(
      () => ref
          .read(ecfRepositoryProvider)
          .updateDgiiHabilitation(observations: saved),
    );
  }

  Future<void> _registerEvidence({bool receiptOnly = false}) async {
    final input = await showDialog<_EvidenceInput>(
      context: context,
      builder: (context) => _EvidenceDialog(receiptOnly: receiptOnly),
    );
    if (input == null) return;
    await _run(
      () => ref
          .read(ecfRepositoryProvider)
          .registerDgiiEvidence(
            source: input.source,
            kind: input.kind,
            storageRef: input.storageRef,
            description: input.description,
          ),
    );
  }

  Future<void> _recordAuthorization() async {
    final input = await showDialog<_AuthorizationInput>(
      context: context,
      builder: (context) => const _AuthorizationDialog(),
    );
    if (input == null) return;
    await _run(
      () => ref
          .read(ecfRepositoryProvider)
          .recordDgiiAuthorization(
            source: input.source,
            evidenceId: input.evidenceId,
            externalId: input.externalId,
          ),
    );
  }

  /// Revisión INTERNA de una evidencia.
  ///
  /// Se deja claro en el diálogo que revisar no autoriza nada: es una decisión
  /// de la empresa, no un acto de la DGII.
  Future<void> _reviewEvidence(EcfDgiiEvidenceView evidence) async {
    final input = await showDialog<_ReviewInput>(
      context: context,
      builder: (context) => _ReviewDialog(evidence: evidence),
    );
    if (input == null) return;
    await _run(
      () => ref
          .read(ecfRepositoryProvider)
          .reviewDgiiEvidence(
            evidenceId: evidence.id,
            decision: input.decision,
            note: input.note,
          ),
    );
  }

  Future<void> _revokeAuthorization() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Revocar la autorización registrada?'),
        content: const Text(
          'La empresa volverá a "Requiere corrección" y dejará de tener '
          'autorización registrada. La emisión real ya está bloqueada por su '
          'propia compuerta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revocar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => ref.read(ecfRepositoryProvider).revokeDgiiAuthorization());
  }

  /// Permisos de gestión, leídos fuera de `build` para el panel de soporte.
  bool _userCanManage() {
    final user = ref.read(authStateProvider).user;
    return hasUserPermission(user, AppPermission.manageEcfConfig) ||
        hasUserPermission(user, AppPermission.manageEcfOnboarding) ||
        hasUserPermission(user, AppPermission.manageEcfDgiiRequirements);
  }

  /// Ayuda y soporte. Abrir el panel NO concede acceso: la asistencia se pide
  /// dentro, y sigue exigiendo autorización explícita y vencimiento.
  Future<void> _openSupport() async {
    final canManage = _userCanManage();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _SupportSheet(canManage: canManage),
    );
  }

  Future<void> _showDebugScreens() async {
    if (!kDebugMode) return;
    final selected = await showModalBottomSheet<EcfDebugScreen>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 4, 8, 10),
                child: Text(
                  'Ver pantallas',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              for (final screen in EcfDebugScreen.values)
                ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.visibility_outlined,
                    size: 19,
                    color: AppColors.primary,
                  ),
                  title: Text(
                    screen.label,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: _debugScreen == screen
                      ? const Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: AppColors.primary,
                        )
                      : const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: AppColors.textMuted,
                        ),
                  onTap: () => Navigator.of(context).pop(screen),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: EcfInlineNote(
                  tone: EcfTone.pending,
                  icon: Icons.info_outline_rounded,
                  text:
                      'Solo depuración. Estas vistas usan datos en memoria y no ejecutan acciones del backend.',
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _debugScreen = selected);
  }

  Widget _buildDebugPreview(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: EcfDebugPreview(
          screen: _debugScreen!,
          onExit: () => setState(() => _debugScreen = null),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kDebugMode && _debugScreen != null) {
      return _buildDebugPreview(context);
    }
    final user = ref.watch(authStateProvider).user;
    // Cada acción se gatea con EL MISMO permiso que valida `RolesGuard` en el
    // backend. Mostrar un botón que el servidor va a rechazar es peor que no
    // mostrarlo; y los nombres coinciden, así que la bandera guardada en la base
    // y lo que se ve aquí no pueden discrepar.
    final canManage =
        hasUserPermission(user, AppPermission.manageEcfConfig) ||
        hasUserPermission(user, AppPermission.manageEcfOnboarding) ||
        hasUserPermission(user, AppPermission.manageEcfDgiiRequirements);
    final canRegisterEvidence =
        hasUserPermission(user, AppPermission.manageEcfOnboarding) ||
        hasUserPermission(user, AppPermission.registerEcfDgiiEvidence);
    final canReviewEvidence = hasUserPermission(
      user,
      AppPermission.reviewEcfDgiiEvidence,
    );
    final canRecordAuthorization = hasUserPermission(
      user,
      AppPermission.recordEcfDgiiOfficialVerification,
    );
    final canOnboard = hasUserPermission(
      user,
      AppPermission.manageEcfOnboarding,
    );
    // Permiso propio de la numeración: el backend lo exige con
    // `manageEcfSequences`, así que la sección se gatea con el mismo.
    final canManageSequences = hasUserPermission(
      user,
      AppPermission.manageEcfSequences,
    );
    // El diagnóstico y los registros técnicos son herramientas de soporte.
    final isPlatformStaff =
        ref.watch(ecfPlatformStaffProvider).valueOrNull == true;
    final habilitation = ref.watch(ecfDgiiHabilitationProvider);
    // El certificado lo gestiona DOSA cuando DOSA gobierna la certificación de
    // la empresa. Dos fuentes, ambas del backend, y basta con una:
    //
    //  * La configuración e-CF ya declara DOSA.
    //  * Existe un intento de certificación atribuido a DOSA (tras la
    //    reconciliación auditada), aunque la configuración conserve el valor
    //    anterior. Sin esto, una empresa reconciliada seguía viendo «Validar
    //    certificado» y nunca llegaba al asistente oficial.
    //
    // Sin intento NO se asume nada: el backend informa `DOSA` por defecto
    // cuando no hay expediente, y eso ocultaría la carga local del certificado
    // a una empresa que todavía no ha decidido su proveedor.
    final intentState = ref.watch(dosaIntentStateProvider).valueOrNull;
    final intentIsDosa =
        intentState != null &&
        intentState.sessionId != null &&
        intentState.provider == 'DOSA';
    final dosaOwnsCertificate =
        canOnboard &&
        (habilitation.valueOrNull?.provider == 'DOSA' || intentIsDosa);
    final settingsState = ref.watch(companySettingsProvider);
    final settings = settingsState.valueOrNull;

    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _navigateBack();
      },
      child: Scaffold(
        // Sin barra propia: la barra del shell ya muestra el título y el botón de
        // volver. Una segunda barra duplicaba el encabezado y añadía tres iconos
        // más a una pantalla que debe leerse de un vistazo.
        backgroundColor: Colors.transparent,
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: Center(
            child: ConstrainedBox(
              // En Windows y Web el contenido se centra con un ancho legible; en
              // móvil ocupa el ancho disponible.
              constraints: const BoxConstraints(maxWidth: 1120),
              // `SizedBox.expand` fija la altura disponible: dentro de un `Row`
              // con dos columnas, una lista sin altura acotada no se construiría.
              child: SizedBox.expand(
                child: habilitation.when(
                  loading: () => const _LoadingBody(),
                  error: (_, __) => _ErrorBody(onRetry: _refresh),
                  data: (view) => settingsState.isLoading
                      ? const _LoadingBody()
                      : settingsState.hasError || settings == null
                      ? _ErrorBody(onRetry: _refresh)
                      : LayoutBuilder(
                    builder: (context, constraints) {
                      final fiscalReady = fiscalDataReady(settings);
                      final contactEmailReady = isEcfContactEmailValid(
                        settings.ecfContactEmail,
                      );
                      final stage = _stageOf(
                        view.progress,
                        view.state,
                        fiscalReady: fiscalReady,
                      );
                      // La administración es un destino propio, no una capa
                      // encima del recorrido: al entrar por «Administrar» se
                      // abre aquí, sin reiniciar la bienvenida ni repetir
                      // Preparación y Postulación.
                      if (widget.adminView) {
                        return _adminScreen(
                          view,
                          stage: stage,
                          dosaPosted: intentIsDosa,
                          settings: settings,
                          hasContent:
                              canRegisterEvidence ||
                              canRecordAuthorization ||
                              isPlatformStaff,
                        );
                      }
                      // El paso se deduce del expediente real mientras la persona no
                      // navegue: al volver a la pantalla se entra en la etapa actual
                      // y nunca se reinicia la postulación.
                      var step =
                          _step ??
                          initialEcfFlowStep(
                            state: view.state,
                            hasResolvedRequirement:
                                view.progress.resolvedCount > 0 ||
                                view.progress.requirements.any(
                                  (item) => item.resolved,
                                ),
                            officialAuthorization: view.officialAuthorization,
                            fiscalReady: fiscalReady,
                            certificateValidated: _certificateReady(view),
                            dosaOwnsCertificate: dosaOwnsCertificate,
                            testsOrLater:
                                stage == _EcfStage.tests ||
                                stage == _EcfStage.activation,
                          );
                      // Si el expediente ya avanzó pero faltan datos, se vuelve a
                      // la única pantalla que puede resolverlos: Preparación.
                      if ((!fiscalReady || !contactEmailReady) &&
                          step == EcfFlowStep.tracking) {
                        step = EcfFlowStep.preparation;
                      }
                      final wide = constraints.maxWidth >= 900;
                      final preparation = ref.watch(ecfPreparationProvider);
                      final activation = ref.watch(
                        ecfActivationProgressProvider,
                      );

                      final Widget body;
                      // El expediente y la activación heredados solo se usan
                      // cuando DOSA no es el proveedor efectivo. Una empresa con
                      // DOSA no vuelve a ver formularios ni etapas duplicadas.
                      if (_applicationOpen && !dosaOwnsCertificate) {
                        body = Padding(
                          padding: const EdgeInsets.all(16),
                          child: EcfDgiiApplicationWizard(
                            key: _wizardKey,
                            embedded: true,
                            onClose: () => setState(() {
                              _applicationOpen = false;
                              _fiscalOpen = true;
                              _step = EcfFlowStep.preparation;
                            }),
                            onSubmitted: () => setState(() {
                              _applicationOpen = false;
                              _step = EcfFlowStep.tracking;
                            }),
                          ),
                        );
                      } else if (_activationOpen && !dosaOwnsCertificate) {
                        body = const Padding(
                          padding: EdgeInsets.all(16),
                          child: EcfActivationPage(embedded: true),
                        );
                      } else if (_certificateOpen && !dosaOwnsCertificate) {
                        body = Padding(
                          padding: const EdgeInsets.all(16),
                          child: EcfCertificateCard(
                            persistedValidation: _certificateRestarted
                                ? null
                                : view.certificateValidation,
                            onRestart: () async {
                              await ref
                                  .read(ecfCertificateRepositoryProvider)
                                  .restart();
                              if (mounted) {
                                setState(() => _certificateRestarted = true);
                              }
                            },
                            initialReport: _verifiedCertificate,
                            initialFileName: _verifiedCertificateFileName,
                            onVerified: (report, fileName) {
                              setState(() {
                                _verifiedCertificate = report;
                                _verifiedCertificateFileName = fileName;
                                _certificateRestarted = false;
                                _certificateOpen = false;
                              });
                              ref.invalidate(ecfDgiiHabilitationProvider);
                            },
                            onGateChanged: (gate) => setState(() {
                              if (!gate.ready) {
                                _verifiedCertificate = null;
                                _verifiedCertificateFileName = null;
                              }
                            }),
                          ),
                        );
                      } else if (_fiscalOpen) {
                        body = Padding(
                          padding: const EdgeInsets.all(16),
                          child: EcfFiscalDataContent(
                            compact: true,
                            onSaved: () => setState(() => _fiscalOpen = false),
                            onClose: fiscalReady
                                ? () => setState(() => _fiscalOpen = false)
                                : null,
                          ),
                        );
                      } else {
                        body = switch (step) {
                          EcfFlowStep.welcome => EcfWelcomeStep(
                            videoUrl: preparation.valueOrNull?.videoUrl ?? '',
                            wide: wide,
                            onStart: () =>
                                _goToStep(EcfFlowStep.preparation),
                          ),
                          EcfFlowStep.preparation => EcfPreparationStep(
                            settings: settings,
                            companyReady: fiscalReady,
                            contactEmailReady: contactEmailReady,
                            certificateReady: _certificateReady(view),
                            dosaOwnsCertificate: dosaOwnsCertificate,
                            dosaEntry:
                                dosaOwnsCertificate &&
                                    fiscalReady &&
                                    contactEmailReady &&
                                    canOnboard
                                ? DosaAssistantSection(
                                    key: ValueKey(
                                      'dosa-preparation-${user?.companyId}',
                                    ),
                                    portalOnly: true,
                                    postulationExternalId: view.externalId,
                                    onSessionOpened: () => setState(() {
                                      _step = EcfFlowStep.tracking;
                                    }),
                                  )
                                : null,
                            // Qué falta para poder facturar. Vive en el mismo
                            // recorrido: sin esto, el cliente que vuelve días
                            // después no sabe en qué quedó su trámite.
                            activation: dosaOwnsCertificate && canOnboard
                                ? EcfDosaActivationStatus(
                                    key: ValueKey(
                                      'dosa-activation-preparation-${user?.companyId}',
                                    ),
                                    canManage: canOnboard,
                                    compact: true,
                                  )
                                : null,
                            sequence: dosaOwnsCertificate && canManageSequences
                                ? EcfSequenceRangeSection(
                                    key: ValueKey(
                                      'dosa-sequences-preparation-${user?.companyId}',
                                    ),
                                    canManage: canManageSequences,
                                  )
                                : null,
                            simulationAvailable:
                                preparation.valueOrNull?.simulationAvailable ??
                                false,
                            simulationBadge:
                                preparation.valueOrNull?.simulationBadge,
                            simulationReason:
                                preparation.valueOrNull?.simulationReason,
                            canManage: canManage,
                            busy: _busy,
                            onStart: _startIntelligentCertification,
                            onEditFiscalData: () =>
                                setState(() => _fiscalOpen = true),
                            onGoCompany: () =>
                                setState(() => _fiscalOpen = true),
                            onGoCertificate: () =>
                                setState(() => _certificateOpen = true),
                          ),
                          EcfFlowStep.tracking => dosaOwnsCertificate
                              ? EcfDosaTrackingStep(
                                  milestone: _milestoneOf(stage).index,
                                  statusLabel: _clientStateLabel(view),
                                  statusMessage: _clientStatusMessage(view),
                                  official: view.officialAuthorization,
                                  activation: canOnboard
                                      ? EcfDosaActivationStatus(
                                          key: ValueKey(
                                            'dosa-activation-tracking-${user?.companyId}',
                                          ),
                                          canManage: canOnboard,
                                        )
                                      : null,
                                  sequence: canManageSequences
                                      ? EcfSequenceRangeSection(
                                          key: ValueKey(
                                            'dosa-sequences-tracking-${user?.companyId}',
                                          ),
                                          canManage: canManageSequences,
                                        )
                                      : null,
                                  portal: canOnboard
                                      ? DosaAssistantSection(
                                          key: ValueKey(
                                            'dosa-tracking-${user?.companyId}',
                                          ),
                                          portalOnly: true,
                                          postulationExternalId:
                                              view.externalId,
                                        )
                                      : null,
                                )
                              : _trackingStep(
                                  view: view,
                                  stage: stage,
                                  wide: wide,
                                  canManage: canManage,
                                  canRecordAuthorization:
                                      canRecordAuthorization,
                                  canRegisterEvidence: canRegisterEvidence,
                                  canReviewEvidence: canReviewEvidence,
                                  activation: activation.valueOrNull,
                                  testBadge:
                                      preparation
                                              .valueOrNull
                                              ?.simulationAvailable ==
                                          true
                                      ? preparation.valueOrNull?.simulationBadge
                                      : null,
                                ),
                        };
                      }

                      // Errores y progreso de escritura: fuera del cuerpo del paso,
                      // para que un fallo se vea sin perder el contexto.
                      Widget framed(Widget child) => Column(
                        children: [
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  10,
                                  8,
                                  10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.errorSoft,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: AppColors.errorBorder,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      size: 16,
                                      color: AppColors.error,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _error!,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _refresh,
                                      child: const Text('Reintentar'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (_busy)
                            const LinearProgressIndicator(minHeight: 2),
                          Expanded(child: child),
                        ],
                      );

                      if (step == EcfFlowStep.welcome && !_applicationOpen) {
                        return framed(body);
                      }

                      if (!wide) {
                        return Column(
                          children: [
                            EcfStepRail(
                              current: step,
                              horizontal: true,
                              onSelect: _goToStep,
                            ),
                            const Divider(height: 1),
                            Expanded(child: framed(body)),
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: framed(body)),
                          SizedBox(
                            width: 216,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                              child: SingleChildScrollView(
                                child: EcfStepRail(
                                  current: step,
                                  onSelect: _goToStep,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Solo el estado persistido y vigente que devuelve el servidor permite avanzar.
  bool _certificateReady(EcfDgiiHabilitationView view) =>
      !_certificateRestarted && view.certificateValidation?.ready == true;

  /// Arranca el motor de postulación con las condiciones del servidor.
  Future<void> _startIntelligentCertification() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(ecfCertificationRepositoryProvider).start();
      ref.invalidate(ecfActivationProgressProvider);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = EcfFlowStep.tracking;
      });
      AppFeedback.showToast(
        context,
        title: 'Postulación en marcha',
        body: 'El sistema ejecutó los pasos disponibles en modo de prueba.',
        kind: AppFeedbackKind.success,
        dedupeKey: 'ecf_certification_started',
      );
    } catch (error) {
      ref.invalidate(ecfActivationProgressProvider);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  /// Qué está haciendo FullPOS y qué toca después: una frase y una acción.
  ({String message, String label, VoidCallback action}) _nextAction(
    EcfDgiiHabilitationView view,
    _EcfStage stage, {
    required bool canRecordAuthorization,
  }) {
    switch (stage) {
      case _EcfStage.prepare:
      case _EcfStage.application:
        if (view.state == 'APPLICATION_PENDING') {
          if (_submissionGuideOpen) {
            return (
              message:
                  'Tu expediente está listo. La presentación se hace en el '
                  'portal de la DGII con la guía de abajo.',
              label: 'Actualizar estado',
              action: _refresh,
            );
          }
          return (
            message:
                'Falta presentar el expediente en el portal de la DGII. Te '
                'mostramos cómo, paso a paso.',
            label: 'Ver cómo presentar',
            action: () => setState(() => _submissionGuideOpen = true),
          );
        }
        return (
          message:
              'Revisamos contigo lo que falta del expediente. No se envía nada '
              'a la DGII sin tu confirmación.',
          label: 'Preparar expediente',
          action: () => setState(() => _applicationOpen = true),
        );
      case _EcfStage.tests:
        return (
          message:
              'Aquí solo se ejecutan las comprobaciones disponibles en FullPOS.',
          label: 'Ver comprobaciones',
          action: () => setState(() => _activationOpen = true),
        );
      case _EcfStage.activation:
        if (view.officialAuthorization) {
          return (
            message:
                'Tu habilitación consta verificada. La emisión real sigue '
                'bloqueada hasta completar las comprobaciones de producción.',
            label: 'Revisar activación',
            action: () => setState(() => _activationOpen = true),
          );
        }
        return (
          message:
              'Esperamos una respuesta verificable de la DGII. Cuando llegue, '
              'se registra el documento oficial.',
          label: canRecordAuthorization
              ? 'Registrar autorización'
              : 'Actualizar estado',
          action: canRecordAuthorization ? _recordAuthorization : _refresh,
        );
    }
  }

  Widget _trackingStep({
    required EcfDgiiHabilitationView view,
    required _EcfStage stage,
    required bool wide,
    required bool canManage,
    required bool canRecordAuthorization,
    required bool canRegisterEvidence,
    required bool canReviewEvidence,
    required EcfActivationProgress? activation,
    required String? testBadge,
  }) {
    final next = _nextAction(
      view,
      stage,
      canRecordAuthorization: canRecordAuthorization,
    );
    // El motor solo aporta cifras cuando ya ejecutó algo; antes de eso el
    // progreso real es el del expediente.
    final useMotor =
        activation != null && activation.percent > 0 && activation.total > 0;
    final percent = useMotor ? activation.percent : view.progress.percent;
    final resolved = useMotor
        ? activation.resolvedCount
        : view.progress.resolvedCount;
    final total = useMotor ? activation.total : view.progress.total;

    // La solicitud es la única etapa que entrega un XML de postulación.
    final needsXml = stage == _EcfStage.application;

    return EcfTrackingStep(
      wide: wide,
      milestone: _milestoneOf(stage).index,
      official: view.officialAuthorization,
      reviewing: view.state == 'APPLICATION_PENDING',
      statusLabel: _clientStateLabel(view),
      statusMessage: _clientStatusMessage(view),
      percent: percent,
      resolvedCount: resolved,
      total: total,
      nextMessage: next.message,
      nextActionLabel: next.label,
      nextActionEnabled: !_busy,
      onNextAction: next.action,
      testBadge: testBadge,
      xmlSlot: needsXml
          ? EcfPostulationXmlCard(onUploaded: () => setState(() {}))
          : null,
      extraSections: [
        // Seguimiento reutiliza el mismo portal; el embed legado permanece oculto.
        if (stage == _EcfStage.application && canManage)
          const DosaAssistantSection(portalOnly: true),
        if (_submissionGuideOpen && view.state == 'APPLICATION_PENDING') ...[
          const EcfSurface(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: _SubmissionGuide(),
          ),
          if (canRegisterEvidence)
            _EvidenceCard(
              view: view,
              receiptOnly: true,
              canRegisterEvidence: true,
              canReviewEvidence: canReviewEvidence,
              busy: _busy,
              onRegister: () => _registerEvidence(receiptOnly: true),
              onReview: _reviewEvidence,
            ),
        ],
        // Quien revisa evidencias pero no gestiona el proceso las ve aquí: la
        // revisión interna no puede quedar escondida en el bloque de administración.
        if (!canManage &&
            canReviewEvidence &&
            view.evidence.any((item) => item.reviewStatus == 'PENDING'))
          _EvidenceCard(
            view: view,
            canRegisterEvidence: false,
            canReviewEvidence: canReviewEvidence,
            busy: _busy,
            onRegister: _registerEvidence,
            onReview: _reviewEvidence,
          ),
      ],
    );
  }

  /// Pantalla propia de la administración (`/ecf/administracion`).
  ///
  /// No reutiliza el recorrido del cliente a propósito: entrar por «Administrar»
  /// no debe devolver a la bienvenida ni obligar a pasar otra vez por
  /// Preparación y Postulación. Aquí solo vive lo que acredita la aprobación de
  /// la DGII y, para soporte, el diagnóstico del expediente.
  Widget _adminScreen(
    EcfDgiiHabilitationView view, {
    required _EcfStage stage,
    required bool dosaPosted,
    required CompanySettings settings,
    required bool hasContent,
  }) {
    final name = settings.companyName.trim();
    final rnc = settings.rnc.trim();
    final identity = [
      name,
      rnc,
    ].where((value) => value.isNotEmpty).join(' · ');

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EcfStepTitle(
                title: 'Administración e-CF',
                subtitle: 'Evidencias y autorización oficial de la DGII.',
              ),
              const SizedBox(height: 14),
              if (identity.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: EcfSummaryRow(
                    label: 'Empresa',
                    value: identity,
                    tone: EcfTone.current,
                  ),
                ),
              if (hasContent)
                _adminAdvanced(view, stage: stage, dosaPosted: dosaPosted)
              else
                const EcfInlineNote(
                  tone: EcfTone.pending,
                  text:
                      'No hay acciones administrativas pendientes para esta '
                      'empresa.',
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Controles administrativos de la vista `/ecf/administracion`.
  ///
  /// Se separan DOS cosas que antes vivían juntas bajo «Avanzado»:
  ///
  ///  * **Acciones del cliente**: subir la constancia de la DGII y registrarla.
  ///    Es el único camino para que la aprobación oficial conste, así que se
  ///    muestra siempre que el usuario tenga el permiso.
  ///  * **Herramientas de soporte**: diagnóstico del intento, avance, emisión,
  ///    datos fiscales y estado interno. No son necesarias para facturar y solo
  ///    se muestran al personal de plataforma.
  Widget _adminAdvanced(
    EcfDgiiHabilitationView view, {
    required _EcfStage stage,
    required bool dosaPosted,
  }) {
    final companyId = ref.read(authStateProvider).user?.companyId ?? '';
    final user = ref.watch(authStateProvider).user;
    final canRegisterEvidence =
        hasUserPermission(user, AppPermission.manageEcfOnboarding) ||
        hasUserPermission(user, AppPermission.registerEcfDgiiEvidence);
    final canReviewEvidence = hasUserPermission(
      user,
      AppPermission.reviewEcfDgiiEvidence,
    );
    final canRecordAuthorization = hasUserPermission(
      user,
      AppPermission.recordEcfDgiiOfficialVerification,
    );
    final staff = ref.watch(ecfPlatformStaffProvider).valueOrNull == true;
    final hasDgiiActions = canRegisterEvidence || canRecordAuthorization;

    // La autorización se ofrece cuando REALMENTE falta. Antes dependía del
    // escalón interno (`stage == activation`), y una empresa que ya terminó su
    // postulación en DOSA pero conserva el expediente interno en `NOT_STARTED`
    // se quedaba sin la acción: su bloqueo era justo «la DGII no ha aprobado».
    final showAuthorization =
        canRecordAuthorization &&
        !view.officialAuthorization &&
        (stage == _EcfStage.activation || dosaPosted);

    // Sin acciones propias ni herramientas de soporte no hay nada que mostrar.
    if (!hasDgiiActions && !staff) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasDgiiActions)
          _adminGroup(
            title: 'Evidencias y autorización de la DGII',
            subtitle:
                'Sube la constancia oficial y regístrala: es lo que acredita la '
                'aprobación ante la DGII.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (view.evidence.isNotEmpty || canRegisterEvidence)
                  _EvidenceCard(
                    view: view,
                    canRegisterEvidence: canRegisterEvidence,
                    canReviewEvidence: canReviewEvidence,
                    busy: _busy,
                    onRegister: () => _registerEvidence(),
                    onReview: _reviewEvidence,
                  ),
                if (showAuthorization)
                  _OfficialAuthorizationCard(
                    view: view,
                    busy: _busy,
                    onRecordAuthorization: _recordAuthorization,
                    onRevoke: _revokeAuthorization,
                  ),
              ],
            ),
          ),
        if (staff) ...[
          if (hasDgiiActions) const SizedBox(height: 10),
          _adminGroup(
            title: 'Diagnóstico e-CF',
            subtitle: 'Información de soporte. No es necesaria para facturar.',
            child: DosaCertificationDiagnosticSection(
              key: ValueKey('dosa-diagnostic-$companyId'),
            ),
          ),
          const SizedBox(height: 10),
          _adminGroup(
            title: 'Información técnica',
            subtitle: 'Avance, emisión, datos fiscales y estado interno.',
            child: _technicalDetailsBody(view, stage: stage),
          ),
        ],
      ],
    );
  }

  /// Acordeón de administración con la superficie del sistema.
  Widget _adminGroup({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return EcfSurface(
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(
            title,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textMuted,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [child],
        ),
      ),
    );
  }

  /// Registros técnicos internos: solo soporte.
  Widget _technicalDetailsBody(
    EcfDgiiHabilitationView view, {
    required _EcfStage stage,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AdvancedSection(
          view: view,
          progress: view.progress,
          settings: ref.read(companySettingsProvider).valueOrNull,
          history: ref.watch(ecfDgiiHistoryProvider),
          canManage: true,
          busy: _busy,
          onAdvance: () => _advance(view),
          onEditObservations: () => _editObservations(view),
          showPlatform: ref.watch(ecfPlatformStaffProvider).valueOrNull == true,
          onOpenPlatform: () => context.go(Routes.ecfPlatformReview),
          onOpenWizard: () => setState(() => _applicationOpen = true),
          onOpenActivation: () => setState(() => _activationOpen = true),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.go(Routes.ecfCertificationRecovery),
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: const Text('Reconciliación de intentos'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Secciones
// ---------------------------------------------------------------------------

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.view,
    required this.history,
    required this.canManage,
    required this.busy,
    required this.showPlatform,
    required this.onAdvance,
    required this.onEditObservations,
    required this.onOpenWizard,
    required this.onOpenActivation,
    required this.onOpenPlatform,
  });

  final EcfDgiiHabilitationView view;
  final AsyncValue<List<EcfDgiiHistoryEntry>> history;
  final bool canManage;
  final bool busy;
  final bool showPlatform;
  final VoidCallback onAdvance;
  final VoidCallback onEditObservations;
  final VoidCallback onOpenWizard;
  final VoidCallback onOpenActivation;
  final VoidCallback onOpenPlatform;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Los bloqueos sí se ven sin abrir nada: son la razón por la que el
        // proceso no avanza.
        if (view.blockers.isNotEmpty) ...[
          _Section(
            title: 'Pendientes y bloqueos',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final blocker in view.blockers)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_outlined,
                          size: 16,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            blocker.message,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        _Section(
          title: 'Estado técnico y accesos',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // El nombre técnico del estado vive aquí: el cliente ve una
              // etiqueta comprensible, el administrador conserva el valor real.
              _Row(label: 'Estado interno', value: view.stateLabel),
              if (view.reviewState != null && view.reviewState!.isNotEmpty)
                _Row(label: 'Revisión', value: view.reviewState!),
              if (view.authorizedAt != null)
                _Row(
                  label: 'Autorizado el',
                  value: _fmtDate(view.authorizedAt),
                ),
              if (view.externalId != null && view.externalId!.isNotEmpty)
                _Row(label: 'Identificador externo', value: view.externalId!),
              _Row(label: 'Iniciado', value: _fmtDate(view.startedAt)),
              _Row(label: 'Actualizado', value: _fmtDate(view.updatedAt)),
              // La nota que dejó el equipo sobre el estado actual se conserva:
              // explica el seguimiento sin ocupar la navegación del cliente.
              if (view.observations != null &&
                  view.observations!.trim().isNotEmpty)
                _Row(label: 'Observaciones', value: view.observations!.trim()),
              if (canManage) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: busy ? null : onAdvance,
                      icon: const Icon(Icons.trending_flat, size: 18),
                      label: const Text('Avanzar estado'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : onEditObservations,
                      icon: const Icon(Icons.edit_note, size: 18),
                      label: const Text('Observaciones'),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: busy ? null : onOpenWizard,
                    icon: const Icon(Icons.assignment_outlined, size: 18),
                    label: const Text('Asistente de postulación'),
                  ),
                  TextButton.icon(
                    onPressed: busy ? null : onOpenActivation,
                    icon: const Icon(Icons.rocket_launch_outlined, size: 18),
                    label: const Text('Activar facturación electrónica'),
                  ),
                  if (showPlatform)
                    TextButton.icon(
                      onPressed: onOpenPlatform,
                      icon: const Icon(
                        Icons.admin_panel_settings_outlined,
                        size: 18,
                      ),
                      label: const Text('Revisión de expedientes'),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _HistoryCard(history: history),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmissionCard extends StatelessWidget {
  const _EmissionCard({required this.view});

  final EcfDgiiHabilitationView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emission = view.emission;
    final realBlocked = !emission.realEmissionAuthorized;
    return _Section(
      title: 'Autorización para emitir',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusTile(
            icon: realBlocked ? Icons.block : Icons.check_circle_outline,
            color: realBlocked
                ? theme.colorScheme.error
                : const Color(0xFF1B7F3B),
            title: 'Emisión real',
            subtitle: realBlocked ? 'Bloqueada' : 'Autorizada',
          ),
          _StatusTile(
            icon: emission.simulatedDispatchAuthorized
                ? Icons.science_outlined
                : Icons.do_not_disturb_on_outlined,
            color: emission.simulatedDispatchAuthorized
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
            title: 'Emisión de prueba',
            subtitle: emission.simulatedDispatchAuthorized
                ? 'Disponible: no contacta a la DGII ni consume numeración'
                : 'No disponible en este entorno',
          ),
          _StatusTile(
            icon: emission.productionEmissionImplemented
                ? Icons.check_circle_outline
                : Icons.construction_outlined,
            color: theme.colorScheme.outline,
            title: 'Emisión real implementada',
            subtitle: emission.productionEmissionImplemented
                ? 'Sí'
                : 'No: la emisión real todavía no está implementada en el producto',
          ),
        ],
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.progress});

  final EcfDgiiProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Resumen, NO una lista de pasos.
    //
    // El recorrido del trámite se hace en el asistente (que va indicando cada
    // paso) y en la Oficina Virtual de la DGII. Repetirlo aquí añadía quince
    // filas que el cliente no puede resolver desde esta pantalla y que además
    // se confundían con acciones reales.
    return _Section(
      title: 'Avance del expediente',
      subtitle:
          'Dato informativo: el avance lo calcula el sistema con las etapas '
          'reales del trámite.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: progress.ratio,
                  minHeight: 6,
                ),
              ),
              const SizedBox(width: 10),
              Text('${progress.percent}%', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${progress.resolvedCount} de ${progress.total} requisitos · '
            'obligatorios ${progress.mandatoryResolved}/${progress.mandatoryTotal}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

class _FiscalDataCard extends StatelessWidget {
  const _FiscalDataCard({required this.view, required this.settings});

  final EcfDgiiHabilitationView view;
  final CompanySettings? settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fiscalBlocker = view.blockers
        .where((blocker) => blocker.code == 'ECF_FISCAL_CONFIGURATION_INVALID')
        .toList(growable: false);
    final rnc = settings?.rnc ?? '';
    final companyName = settings?.companyName ?? '';

    // Si los datos fiscales ya están completos no se repiten aquí: la tarjeta
    // solo aparece cuando hay algo que corregir. Repetir datos correctos en
    // cada pantalla era parte del ruido que hacía difícil leer el proceso.
    if (fiscalBlocker.isEmpty &&
        rnc.trim().isNotEmpty &&
        companyName.trim().isNotEmpty) {
      return const SizedBox.shrink();
    }

    return _Section(
      title: 'Datos fiscales',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Row(
            label: 'Razón social',
            value: companyName.isEmpty ? 'Sin registrar' : companyName,
          ),
          _Row(label: 'RNC', value: rnc.isEmpty ? 'Sin registrar' : rnc),
          if (settings != null && settings!.address.trim().isNotEmpty)
            _Row(label: 'Dirección', value: settings!.address),
          // Solo se nombra lo que falta. Un listado de «todo correcto» ocupa
          // espacio y no aporta ninguna decisión.
          if (fiscalBlocker.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              fiscalBlocker.first.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => context.go(Routes.ecfFiscalData),
              child: const Text('Revisar y corregir estos datos'),
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({
    required this.view,
    required this.canRegisterEvidence,
    required this.canReviewEvidence,
    required this.busy,
    required this.onRegister,
    required this.onReview,
    this.receiptOnly = false,
  });

  final EcfDgiiHabilitationView view;
  final bool canRegisterEvidence;
  final bool canReviewEvidence;
  final bool busy;
  final VoidCallback onRegister;
  final ValueChanged<EcfDgiiEvidenceView> onReview;
  final bool receiptOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Section(
      title: 'Evidencias',
      subtitle:
          'Una evidencia respalda la revisión; registrarla no autoriza emisión. '
          'Una declaración manual queda como nota interna.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Row(
            label: 'Fuente de verificación',
            value: switch (view.authorizationSource) {
              'DGII_OFFICIAL_RECORD' => 'Registro oficial DGII',
              'MANUAL_OPERATOR_DECLARATION' => 'Declaración interna',
              'PROVIDER_CONFIRMATION' => 'Confirmación del proveedor',
              _ => 'Sin verificar',
            },
          ),
          _Row(
            label: 'Autorización oficial',
            value: view.officialAuthorization ? 'Registrada' : 'No registrada',
          ),
          const SizedBox(height: 8),
          if (view.evidence.isEmpty)
            Text(
              'Esta empresa todavía no ha registrado evidencias.',
              style: theme.textTheme.bodySmall,
            ),
          for (final evidence in view.evidence)
            _EvidenceRow(
              evidence: evidence,
              canReview: canReviewEvidence,
              busy: busy,
              onReview: () => onReview(evidence),
            ),
          // Registrar es lo único que se hace aquí; la autorización oficial
          // tiene su propia sección para no mezclar dos trámites distintos en
          // una fila de botones.
          if (canRegisterEvidence &&
              (!receiptOnly || view.state == 'APPLICATION_PENDING')) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: busy ? null : onRegister,
                icon: const Icon(Icons.attach_file, size: 18),
                label: Text(
                  receiptOnly
                      ? 'Registrar referencia de constancia DGII'
                      : 'Registrar evidencia para revisión',
                ),
              ),
            ),
          ],
          // Se explica la ausencia de los controles de revisión siempre que
          // falte el permiso, aunque no se muestre ningún botón: ocultar una
          // acción sin decir por qué deja al usuario sin salida.
          if (!canReviewEvidence && view.evidence.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'La revisión de evidencias requiere el permiso específico.',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

/// Autorización oficial de la DGII: sección propia.
///
/// Registrar lo que la DGII comunicó es un trámite distinto de subir
/// evidencias, así que no comparte fila de botones con ellas. Solo se pinta
/// cuando la sesión puede registrarla.
class _OfficialAuthorizationCard extends StatelessWidget {
  const _OfficialAuthorizationCard({
    required this.view,
    required this.busy,
    required this.onRecordAuthorization,
    required this.onRevoke,
  });

  final EcfDgiiHabilitationView view;
  final bool busy;
  final VoidCallback onRecordAuthorization;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canRevoke =
        view.officialAuthorization || view.authorizationSource != 'NONE';
    return _Section(
      title: 'Autorización oficial',
      subtitle:
          'Registra aquí lo que la DGII te haya comunicado. La aprobación no '
          'la da este sistema.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                busy ? Icons.hourglass_empty : Icons.upload_file_outlined,
                size: 16,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: busy ? null : onRecordAuthorization,
                  icon: const Icon(Icons.verified_outlined, size: 18),
                  label: const Text('Registrar autorización recibida'),
                ),
              ),
            ],
          ),
          if (canRevoke) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: busy ? null : onRevoke,
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Revocar'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _evidenceKindLabel(String kind) => switch (kind) {
  'REPRESENTATIVE_ID' => 'Identificación del representante',
  'COMPANY_DOCUMENT' => 'Documento de la empresa',
  'AUTHORIZATION' => 'Documento de autorización',
  'POSTULATION_XML' => 'XML de postulación',
  'DGII_RECEIPT' => 'Constancia de presentación DGII',
  _ => 'Evidencia del expediente',
};

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({
    required this.evidence,
    required this.canReview,
    required this.busy,
    required this.onReview,
  });

  final EcfDgiiEvidenceView evidence;
  final bool canReview;
  final bool busy;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final official = evidence.isOfficialDocument;
    final reviewedAt = evidence.reviewedAt;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                official
                    ? Icons.description_outlined
                    : Icons.edit_note_outlined,
                size: 18,
                color: official
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      evidence.fileName?.isNotEmpty == true
                          ? evidence.fileName!
                          : _evidenceKindLabel(evidence.kind),
                      style: theme.textTheme.bodyMedium,
                    ),
                    Text(
                      '${evidence.sourceLabel} · '
                      '${_fmtDate(evidence.createdAt)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    Text(
                      'Revisión: ${evidence.reviewStatusLabel}'
                      '${reviewedAt == null ? '' : ' · ${_fmtDate(reviewedAt)}'}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (evidence.reviewNote != null)
                      Text(
                        evidence.reviewNote!,
                        style: theme.textTheme.bodySmall,
                      ),
                    if (evidence.description != null &&
                        evidence.description!.isNotEmpty)
                      Text(
                        evidence.description!,
                        style: theme.textTheme.bodySmall,
                      ),
                    Text(
                      evidence.supportsOfficialAuthorization
                          ? 'Puede sustentar una autorización oficial.'
                          : 'No puede sustentar una autorización oficial.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (canReview)
                IconButton(
                  onPressed: busy ? null : onReview,
                  tooltip: evidence.isPendingReview
                      ? 'Revisar evidencia'
                      : 'Volver a revisar',
                  icon: const Icon(Icons.rule, size: 18),
                ),
              // El registro de la autorización oficial pide el identificador de
              // la evidencia y la tarjeta no lo mostraba: sin esto el paso era
              // imposible de completar desde la app.
              IconButton(
                onPressed: () => Clipboard.setData(
                  ClipboardData(text: evidence.id),
                ),
                tooltip: 'Copiar ID de la evidencia',
                icon: const Icon(Icons.copy_all_outlined, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.history});

  final AsyncValue<List<EcfDgiiHistoryEntry>> history;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Historial de cambios', style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        history.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Text('No se pudo cargar el historial.'),
          data: (entries) => entries.isEmpty
              ? Text(
                  'Todavía no hay cambios registrados.',
                  style: theme.textTheme.bodySmall,
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final entry in entries) _HistoryRow(entry: entry),
                  ],
                ),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final EcfDgiiHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.history, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(entry.actionLabel, style: theme.textTheme.bodyMedium),
          ),
          Text(_fmtDate(entry.createdAt), style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Diálogos
// ---------------------------------------------------------------------------

class _EvidenceInput {
  const _EvidenceInput({
    required this.source,
    required this.kind,
    required this.storageRef,
    this.description,
  });

  final String source;
  final String kind;
  final String storageRef;
  final String? description;
}

/// Mismo formato que valida el backend en `storageRef`.
final _storageRefPattern = RegExp(
  r'^(storage|s3|r2|evidence|uat)://[A-Za-z0-9._:\/@_-]{3,512}$',
);

class _EvidenceDialog extends StatefulWidget {
  const _EvidenceDialog({required this.receiptOnly});

  final bool receiptOnly;

  @override
  State<_EvidenceDialog> createState() => _EvidenceDialogState();
}

class _EvidenceDialogState extends State<_EvidenceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _kind = TextEditingController();
  final _storageRef = TextEditingController();
  final _description = TextEditingController();
  String _source = 'MANUAL_DECLARATION';

  @override
  void dispose() {
    _kind.dispose();
    _storageRef.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.receiptOnly
            ? 'Constancia de presentación DGII'
            : 'Registrar evidencia para revisión',
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.receiptOnly
                    ? 'Registra solo la referencia de una constancia que ya recibiste. '
                          'Aquí no se carga el archivo ni se acredita autorización para emitir.'
                    : 'Se guarda la referencia de una evidencia existente. '
                          'La revisión interna no concede autorización oficial.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (!widget.receiptOnly) ...[
                DropdownButtonFormField<String>(
                  initialValue: _source,
                  decoration: const InputDecoration(labelText: 'Procedencia'),
                  items: const [
                    DropdownMenuItem(
                      value: 'MANUAL_DECLARATION',
                      child: Text('Declaración de la empresa'),
                    ),
                    DropdownMenuItem(
                      value: 'OFFICIAL_DOCUMENT',
                      child: Text('Documento oficial recibido'),
                    ),
                    DropdownMenuItem(
                      value: 'PROVIDER_ARTIFACT',
                      child: Text('Documento del proveedor'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _source = value ?? _source),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _kind,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del documento',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Indica el nombre del documento'
                      : null,
                ),
                const SizedBox(height: 8),
              ],
              TextFormField(
                controller: _storageRef,
                decoration: const InputDecoration(
                  labelText: 'Referencia del documento',
                ),
                validator: (value) {
                  final raw = value?.trim() ?? '';
                  if (raw.isEmpty) return 'Indica la referencia';
                  if (!_storageRefPattern.hasMatch(raw)) {
                    return 'Debe empezar por storage://, s3://, r2://, evidence:// o uat://';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _description,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            Navigator.of(context).pop(
              _EvidenceInput(
                source: widget.receiptOnly ? 'MANUAL_DECLARATION' : _source,
                kind: widget.receiptOnly ? 'DGII_RECEIPT' : _kind.text.trim(),
                storageRef: _storageRef.text.trim(),
                description: _description.text.trim(),
              ),
            );
          },
          child: const Text('Registrar'),
        ),
      ],
    );
  }
}

class _AuthorizationInput {
  const _AuthorizationInput({
    required this.source,
    this.evidenceId,
    this.externalId,
  });

  final String source;
  final String? evidenceId;
  final String? externalId;
}

class _AuthorizationDialog extends StatefulWidget {
  const _AuthorizationDialog();

  @override
  State<_AuthorizationDialog> createState() => _AuthorizationDialogState();
}

class _AuthorizationDialogState extends State<_AuthorizationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _evidenceId = TextEditingController();
  final _externalId = TextEditingController();
  String _source = 'DGII_OFFICIAL_RECORD';

  @override
  void dispose() {
    _evidenceId.dispose();
    _externalId.dispose();
    super.dispose();
  }

  bool get _requiresEvidence => _source == 'DGII_OFFICIAL_RECORD';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Registrar autorización recibida'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Registra un hecho EXTERNO. Solo la fuente oficial y con '
                'evidencia documental produce autorización efectiva; el backend '
                'rechaza lo demás. Esto no habilita la emisión real.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _source,
                decoration: const InputDecoration(labelText: 'Fuente'),
                items: const [
                  DropdownMenuItem(
                    value: 'DGII_OFFICIAL_RECORD',
                    child: Text('Registro oficial de la DGII'),
                  ),
                  DropdownMenuItem(
                    value: 'PROVIDER_CONFIRMATION',
                    child: Text('Confirmación del proveedor'),
                  ),
                  DropdownMenuItem(
                    value: 'MANUAL_OPERATOR_DECLARATION',
                    child: Text('Declaración manual del operador'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _source = value ?? _source),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _evidenceId,
                decoration: const InputDecoration(
                  labelText: 'Identificador de la evidencia',
                  hintText: 'Pega el ID (botón copiar de la tarjeta)',
                ),
                validator: (value) {
                  if (!_requiresEvidence) return null;
                  final raw = value?.trim() ?? '';
                  if (raw.isEmpty) return 'La fuente oficial exige evidencia';
                  return null;
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _externalId,
                decoration: const InputDecoration(
                  labelText: 'Identificador externo',
                  hintText: 'Número de resolución o expediente',
                ),
                validator: (value) {
                  if (!_requiresEvidence) return null;
                  final raw = value?.trim() ?? '';
                  if (raw.isEmpty) {
                    return 'La fuente oficial exige identificador';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            Navigator.of(context).pop(
              _AuthorizationInput(
                source: _source,
                evidenceId: _evidenceId.text.trim().isEmpty
                    ? null
                    : _evidenceId.text.trim(),
                externalId: _externalId.text.trim().isEmpty
                    ? null
                    : _externalId.text.trim(),
              ),
            );
          },
          child: const Text('Registrar'),
        ),
      ],
    );
  }
}

class _ReviewInput {
  const _ReviewInput({required this.decision, this.note});

  final String decision;
  final String? note;
}

/// Revisión INTERNA de una evidencia.
///
/// El diálogo dice explícitamente que revisar no autoriza nada, y exige motivo
/// al rechazar: el backend también lo exige, y sin motivo la decisión no sería
/// auditable.
class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({required this.evidence});

  final EcfDgiiEvidenceView evidence;

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _submit(String decision) {
    final note = _note.text.trim();
    if (decision == 'REJECTED' && note.isEmpty) {
      setState(
        () => _error = 'Un rechazo necesita un motivo para ser auditable.',
      );
      return;
    }
    Navigator.of(
      context,
    ).pop(_ReviewInput(decision: decision, note: note.isEmpty ? null : note));
  }

  @override
  Widget build(BuildContext context) {
    final evidence = widget.evidence;
    return AlertDialog(
      title: const Text('Revisión interna de la evidencia'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              evidence.fileName?.isNotEmpty == true
                  ? evidence.fileName!
                  : evidence.kind,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(evidence.levelLabel, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            const Text(
              'Esta revisión es una decisión interna de la empresa: deja '
              'constancia de que alguien miró el documento. No es una '
              'verificación de la DGII y no autoriza nada por sí sola.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLines: 3,
              maxLength: 1000,
              decoration: InputDecoration(
                labelText: 'Motivo o nota',
                hintText: 'Obligatorio si rechazas',
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => _submit('REJECTED'),
          child: const Text('Rechazar'),
        ),
        FilledButton(
          onPressed: () => _submit('REVIEWED'),
          child: const Text('Marcar como revisada'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Piezas comunes
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final valueStyle = theme.textTheme.bodyMedium;

    return LayoutBuilder(
      builder: (context, constraints) {
        // En pantallas estrechas (iPhone/Android) la etiqueta pasa encima del
        // valor: una columna fija de 180 px desperdiciaría media pantalla.
        if (constraints.maxWidth < 380) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: labelStyle),
                Text(value, style: valueStyle),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 180, child: Text(label, style: labelStyle)),
              Expanded(child: Text(value, style: valueStyle)),
            ],
          ),
        );
      },
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.bodyMedium),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 40,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'No se pudo cargar la habilitación DGII.',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Comprueba la conexión con el servidor.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => onRetry(),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etapas internas para elegir la próxima tarea del cliente.
///
/// Los quince requisitos del backend siguen existiendo y siguen mandando, pero
/// al cliente se le presentan en tres hitos de la postulación.
enum _EcfStage { prepare, application, tests, activation }

enum _EcfMilestone { application, tests, certification }

_EcfMilestone _milestoneOf(_EcfStage stage) => switch (stage) {
  _EcfStage.prepare || _EcfStage.application => _EcfMilestone.application,
  _EcfStage.tests => _EcfMilestone.tests,
  _EcfStage.activation => _EcfMilestone.certification,
};

/// Reparto interno de los requisitos del catálogo del backend.
///
/// Es una agrupación de PRESENTACIÓN sobre las claves que ya existen; no
/// inventa requisitos ni cambia su obligatoriedad, y cualquier clave no
/// contemplada aquí cae en «Pruebas», que es la etapa más conservadora.
const _stageRequirementKeys = <_EcfStage, List<String>>{
  _EcfStage.prepare: ['FISCAL_DATA'],
  _EcfStage.application: [
    'REQUIREMENTS',
    'DIGITAL_CERTIFICATE',
    'ALANUBE_REGISTRATION',
    'DGII_POSTULATION',
  ],
  _EcfStage.tests: [
    'XML_SIGNATURE',
    'SET_TESTS',
    'SIMULATIONS',
    'PRINTED_REPRESENTATION',
    'SERVICE_URLS',
    'SWORN_DECLARATION',
  ],
  _EcfStage.activation: [
    'FINAL_AUTHORIZATION',
    'ENCF_REQUEST',
    'ROLE_ASSIGNMENT',
    'PRODUCTION_ENABLEMENT',
  ],
};

/// Etapa en la que está el proceso: la del primer requisito obligatorio sin
/// resolver. Sin pendientes manda el estado del expediente.
_EcfStage _stageOf(
  EcfDgiiProgress progress,
  String state, {
  bool fiscalReady = false,
}) {
  if (!fiscalReady) return _EcfStage.prepare;
  // APPLICATION_PENDING solo confirma revisión interna del snapshot.
  // No adelanta el hito de solicitud sin una transición posterior comprobada.
  if (_companyStillPreparing(state) || state == 'APPLICATION_PENDING') {
    return _EcfStage.application;
  }
  final pending = progress.requirements.where(
    (requirement) => !requirement.resolved && requirement.mandatory,
  );
  if (pending.isNotEmpty) {
    final keys = _stageRequirementKeys.entries.toList(growable: false);
    for (final entry in keys) {
      if (entry.value.any((key) => pending.any((r) => r.key == key))) {
        return entry.key;
      }
    }
    return _EcfStage.tests;
  }
  // Sin requisitos pendientes el proceso está en la etapa final. Si el backend
  // todavía no ha creado los requisitos, la empresa sigue preparando.
  if (progress.requirements.isEmpty) {
    return switch (state) {
      'APPROVED' || 'IN_CERTIFICATION' => _EcfStage.activation,
      'TESTS_PENDING' || 'IN_PROGRESS' => _EcfStage.tests,
      _ => _EcfStage.application,
    };
  }
  return _EcfStage.activation;
}

/// Datos mínimos del emisor, con la MISMA regla que aplica el backend al emitir
/// (`assertIssuerComplete`): sin nombre, RNC y dirección no hay comprobante.
bool fiscalDataReady(CompanySettings? settings) =>
    settings != null && ecfIssuerDataReady(settings);

/// Explicación del estado en palabras del cliente.
///
/// El estado técnico (`APPLICATION_PENDING`, códigos de bloqueo y conteo de
/// requisitos) describe el seguimiento INTERNO de FullPOS, no algo que el
/// cliente pueda resolver. Aquí se traduce a una sola frase comprensible y se
/// evita la contradicción de mostrar a la vez «pendiente», «bloqueada»,
/// «enviado a revisión» y «14 requisitos pendientes».
String _clientStatusMessage(EcfDgiiHabilitationView view) {
  switch (view.state) {
    case 'APPLICATION_PENDING':
      return 'Tu expediente fue recibido para revisión interna. Todavía no se '
          'ha presentado oficialmente ante la DGII.';
    case 'PREPARING_REQUIREMENTS':
      return 'Estamos preparando tu expediente con los datos de tu empresa. Te '
          'indicaremos el siguiente paso cuando corresponda.';
    case 'IN_PROGRESS':
      return 'El expediente está en proceso de revisión interna. Todavía no '
          'consta una presentación oficial ante la DGII.';
    case 'REQUIRES_CORRECTION':
      return 'Necesitamos una corrección en tu expediente. Revisa las '
          'observaciones y vuelve a enviarlo.';
    case 'TESTS_PENDING':
      return 'El expediente avanzó a la etapa de pruebas. Aquí solo se ejecutan '
          'las comprobaciones disponibles en FullPOS.';
    case 'IN_CERTIFICATION':
      return 'La solicitud está en certificación. La autorización oficial la '
          'otorga la DGII cuando corresponda.';
    case 'APPROVED':
      return 'La revisión interna está aprobada. Siguen pendientes la '
          'autorización oficial de la DGII y la habilitación de emisión.';
    case 'REJECTED':
      return 'La revisión interna no fue aprobada. Revisa las observaciones '
          'antes de volver a enviar el expediente.';
    default:
      return 'Todavía no has iniciado el trámite. El asistente te indicará el '
          'primer paso.';
  }
}

/// Nombre del estado pensado para el cliente.
///
/// El nombre técnico interno (`stateLabel`) se reserva para «Detalle técnico»:
/// «Solicitud pendiente» no significa lo mismo para quien ya envió su
/// expediente que para el sistema interno.
String _clientStateLabel(EcfDgiiHabilitationView view) {
  switch (view.state) {
    case 'NOT_STARTED':
      return 'Sin iniciar';
    case 'PREPARING_REQUIREMENTS':
      return 'Preparando tu expediente';
    case 'APPLICATION_PENDING':
      return 'Recibido para revisión interna';
    case 'IN_PROGRESS':
      return 'En revisión interna';
    case 'TESTS_PENDING':
      return 'En pruebas';
    case 'IN_CERTIFICATION':
      return 'En certificación';
    case 'APPROVED':
      return 'Revisión interna aprobada';
    case 'REJECTED':
      return 'Revisión interna no aprobada';
    case 'REQUIRES_CORRECTION':
      return 'Necesita corrección';
    default:
      return view.stateLabel;
  }
}

/// Todo lo técnico, en un solo bloque plegado.
class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection({
    required this.view,
    required this.progress,
    required this.settings,
    required this.history,
    required this.canManage,
    required this.busy,
    required this.onAdvance,
    required this.onEditObservations,
    required this.showPlatform,
    required this.onOpenPlatform,
    required this.onOpenWizard,
    required this.onOpenActivation,
  });

  final EcfDgiiHabilitationView view;
  final EcfDgiiProgress progress;
  final CompanySettings? settings;
  final AsyncValue<List<EcfDgiiHistoryEntry>> history;
  final bool canManage;
  final bool busy;
  final VoidCallback onAdvance;
  final VoidCallback onEditObservations;
  final bool showPlatform;
  final VoidCallback onOpenPlatform;
  final VoidCallback onOpenWizard;
  final VoidCallback onOpenActivation;

  @override
  Widget build(BuildContext context) {
    // Vive dentro del panel de soporte, así que no es un acordeón: es la vista
    // secundaria de administrador con los registros técnicos.
    //
    // No repite el título «Detalle técnico»: el acordeón que lo contiene ya lo
    // dice. Dos encabezados iguales, uno dentro del otro, se leían como dos
    // bloques distintos con el mismo contenido.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProgressCard(progress: progress),
        const SizedBox(height: 12),
        _EmissionCard(view: view),
        const SizedBox(height: 12),
        _FiscalDataCard(view: view, settings: settings),
        const SizedBox(height: 12),
        _StateCard(
          view: view,
          history: history,
          canManage: canManage,
          busy: busy,
          showPlatform: showPlatform,
          onAdvance: onAdvance,
          onEditObservations: onEditObservations,
          onOpenWizard: onOpenWizard,
          onOpenActivation: onOpenActivation,
          onOpenPlatform: onOpenPlatform,
        ),
      ],
    );
  }
}

/// Guía paso a paso para presentar la solicitud ante la DGII.
///
/// Dice lo que el cliente debe hacer, dónde, con qué y qué parte NO hace
/// FullPOS. No inventa integraciones: si algo no está automatizado, se dice
/// explícitamente. Nunca pide credenciales de la Oficina Virtual.
class _SubmissionGuide extends StatelessWidget {
  const _SubmissionGuide();

  /// Restricciones del procedimiento que el cliente debe conocer. Salen de la
  /// auditoría externa (DGII CA5244 y Norma 10-21, art. 14) y no son
  /// integraciones: son reglas que FullPOS no puede saltarse.
  static const _procedureNotices = <String>[
    'Una postulación en curso no puede convivir con otra de un proveedor '
        'distinto: si cambias de proveedor, la DGII exige iniciar de nuevo el '
        'trámite (CA5244).',
    'La delegación de firma de comprobantes electrónicos no cubre la '
        'declaración jurada: ese acto sigue siendo del representante legal '
        '(Norma 10-21, art. 14).',
  ];

  static const _steps = <(String, String)>[
    (
      'Qué trámite corresponde',
      'Presentar la solicitud de habilitación como emisor de comprobantes '
          'fiscales electrónicos (e-CF) ante la DGII.',
    ),
    (
      'Dónde se realiza',
      'En la Oficina Virtual de la DGII, con el usuario y la clave del '
          'contribuyente (RNC de la empresa). FullPOS no solicita ni guarda '
          'esas credenciales.',
    ),
    (
      'Qué necesitas tener a mano',
      'RNC y clave de la Oficina Virtual, certificado digital vigente y los '
          'datos del representante legal.',
    ),
    (
      'Qué hace FullPOS por ti',
      'Conserva y organiza tu expediente y sus documentos, y los deja listos '
          'para adjuntar. No presenta la solicitud en tu nombre.',
    ),
    (
      'Cómo volver al asistente',
      'Entra en Facturación electrónica → Habilitación DGII. El asistente '
          'retoma el expediente donde quedó.',
    ),
    (
      'Cómo registrar el resultado',
      'Adjunta el acuse o el número de radicado como evidencia. Quedará en '
          'revisión interna: registrarlo aquí no acredita aprobación oficial.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cómo presentar tu solicitud',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < _steps.length; i++) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}.',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1957E6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _steps[i].$1,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2A37),
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _steps[i].$2,
                          style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (i < _steps.length - 1) const SizedBox(height: 10),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Color(0xFFB45309),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'La presentación automática ante la DGII o ante el '
                      'proveedor certificado todavía no está integrada en esta '
                      'versión: el trámite lo realiza el contribuyente.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                        height: 1.35,
                        color: const Color(0xFF7C4A03),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Restricciones del procedimiento que el cliente debe conocer antes
            // de empezar. No son integraciones: son reglas de la DGII.
            for (final notice in _procedureNotices)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.gavel_outlined,
                      size: 14,
                      color: Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        notice,
                        style: const TextStyle(
                          fontSize: 11,
                          height: 1.35,
                          color: Color(0xFF64748B),
                        ),
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

/// Ayuda y soporte: preguntas frecuentes y asistencia temporal de Fulltech.
class _SupportSheet extends StatelessWidget {
  const _SupportSheet({required this.canManage});

  final bool canManage;

  static const _faq = <(String, String)>[
    (
      '¿Esto envía algo a la DGII?',
      'No. Aquí registras tu avance y tus documentos. La presentación ante la '
          'DGII se hace por su canal oficial.',
    ),
    (
      '¿Cuándo podré facturar electrónicamente?',
      'Después de registrar la autorización oficial, completar las '
          'comprobaciones y habilitar la integración productiva por empresa.',
    ),
    (
      '¿Quién puede ver mi expediente?',
      'Solo tu empresa. Si concedes asistencia temporal, el equipo de Fulltech '
          'puede revisarlo hasta la fecha indicada, y puedes revocarla.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.headset_mic_outlined,
                  size: 20,
                  color: Color(0xFF1957E6),
                ),
                const SizedBox(width: 8),
                Text(
                  'Ayuda y soporte',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final entry in _faq) ...[
              Text(
                entry.$1,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2A37),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                entry.$2,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.3,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 10),
            ],
            const Divider(height: 20),
            EcfSupportGrantCard(canManage: canManage),
          ],
        ),
      ),
    );
  }
}

/// Estados que la propia EMPRESA declara (`CUSTOMER_ACTION` en
/// `ECF_STATE_OWNERSHIP` del backend): iniciar y preparar el expediente.
///
/// Mientras el proceso esté en uno de estos estados todavía no existe una
/// postulación presentada, así que ofrecer «registrar autorización recibida» no
/// tendría sentido: no hay nada que la DGII pueda haber contestado.
bool _companyStillPreparing(String state) =>
    state == 'NOT_STARTED' || state == 'PREPARING_REQUIREMENTS';

String _fmtDate(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
