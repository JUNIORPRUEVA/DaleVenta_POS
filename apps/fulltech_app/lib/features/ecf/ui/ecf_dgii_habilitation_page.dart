import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/company/company_settings_model.dart';
import '../../../core/company/company_settings_repository.dart';
import '../../../core/routing/routes.dart';
import '../data/ecf_platform_repository.dart';
import '../data/ecf_repository.dart';
import '../ecf_models.dart';
import 'ecf_activation_page.dart';
import 'ecf_dgii_application_wizard.dart';
import 'ecf_support_grant_card.dart';

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
  const EcfDgiiHabilitationPage({super.key});

  @override
  ConsumerState<EcfDgiiHabilitationPage> createState() =>
      _EcfDgiiHabilitationPageState();
}

class _EcfDgiiHabilitationPageState
    extends ConsumerState<EcfDgiiHabilitationPage> {
  bool _busy = false;
  String? _error;

  Future<void> _refresh() async {
    ref.invalidate(ecfDgiiHabilitationProvider);
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
              child: Text('No hay transiciones disponibles desde el estado actual.'),
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
      () => ref
          .read(ecfRepositoryProvider)
          .updateDgiiHabilitation(state: next),
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

  Future<void> _registerEvidence() async {
    final input = await showDialog<_EvidenceInput>(
      context: context,
      builder: (context) => const _EvidenceDialog(),
    );
    if (input == null) return;
    await _run(
      () => ref.read(ecfRepositoryProvider).registerDgiiEvidence(
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
      () => ref.read(ecfRepositoryProvider).recordDgiiAuthorization(
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
      () => ref.read(ecfRepositoryProvider).reviewDgiiEvidence(
            evidenceId: evidence.id,
            decision: input.decision,
            note: input.note,
          ),
    );
  }

  /// Seguimiento interno de UN requisito: quién lo lleva y para cuándo.
  Future<void> _editRequirementTracking(
    EcfDgiiRequirementProgress requirement,
  ) async {
    final input = await showDialog<_RequirementTrackingInput>(
      context: context,
      builder: (context) =>
          _RequirementTrackingDialog(requirement: requirement),
    );
    if (input == null) return;
    await _run(
      () => ref.read(ecfRepositoryProvider).updateDgiiRequirement(
            key: requirement.key,
            status: input.status,
            note: input.note,
            dueDate: input.dueDate,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(authStateProvider).user;
    // Cada acción se gatea con EL MISMO permiso que valida `RolesGuard` en el
    // backend. Mostrar un botón que el servidor va a rechazar es peor que no
    // mostrarlo; y los nombres coinciden, así que la bandera guardada en la base
    // y lo que se ve aquí no pueden discrepar.
    final canManage = hasUserPermission(user, AppPermission.manageEcfConfig) ||
        hasUserPermission(user, AppPermission.manageEcfOnboarding) ||
        hasUserPermission(user, AppPermission.manageEcfDgiiRequirements);
    final canRegisterEvidence =
        hasUserPermission(user, AppPermission.manageEcfOnboarding) ||
            hasUserPermission(user, AppPermission.registerEcfDgiiEvidence);
    final canReviewEvidence =
        hasUserPermission(user, AppPermission.reviewEcfDgiiEvidence);
    final canRecordAuthorization = hasUserPermission(
      user,
      AppPermission.recordEcfDgiiOfficialVerification,
    );
    final habilitation = ref.watch(ecfDgiiHabilitationProvider);
    final history = ref.watch(ecfDgiiHistoryProvider);
    final settings = ref.watch(companySettingsProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Habilitación DGII'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(Routes.ecf),
        ),
        actions: [
          IconButton(
            tooltip: 'Activar facturación electrónica',
            icon: const Icon(Icons.rocket_launch_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const EcfActivationPage(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Asistente de postulación',
            icon: const Icon(Icons.assignment_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const EcfDgiiApplicationWizard(),
              ),
            ),
          ),
          // El acceso al panel de plataforma se pregunta al backend: si la
          // sesión no pertenece al equipo de Fulltech, el botón no se muestra.
          if (ref.watch(ecfPlatformStaffProvider).valueOrNull == true)
            IconButton(
              tooltip: 'Revisión de expedientes (Fulltech)',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => context.go(Routes.ecfPlatformReview),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: Center(
          child: ConstrainedBox(
            // En Windows y Web el contenido se centra con un ancho legible; en
            // móvil ocupa el ancho disponible.
            constraints: const BoxConstraints(maxWidth: 900),
            child: habilitation.when(
              loading: () => const _LoadingBody(),
              error: (_, __) => _ErrorBody(onRetry: _refresh),
              data: (view) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _DistinctionBanner(view: view),
                  const SizedBox(height: 12),
                  _StateCard(
                    view: view,
                    canManage: canManage,
                    busy: _busy,
                    onAdvance: () => _advance(view),
                    onEditObservations: () => _editObservations(view),
                  ),
                  const SizedBox(height: 12),
                  _EmissionCard(view: view),
                  const SizedBox(height: 12),
                  _ProgressCard(
                    progress: view.progress,
                    canTrack: canManage,
                    busy: _busy,
                    onTrack: _editRequirementTracking,
                  ),
                  const SizedBox(height: 12),
                  _FiscalDataCard(view: view, settings: settings),
                  const SizedBox(height: 12),
                  _EvidenceCard(
                    view: view,
                    canRegisterEvidence: canRegisterEvidence,
                    canReviewEvidence: canReviewEvidence,
                    canRecordAuthorization: canRecordAuthorization,
                    busy: _busy,
                    onRegister: _registerEvidence,
                    onReview: _reviewEvidence,
                    onRecordAuthorization: _recordAuthorization,
                    onRevoke: _revokeAuthorization,
                  ),
                  const SizedBox(height: 12),
                  EcfSupportGrantCard(canManage: canManage),
                  const SizedBox(height: 12),
                  _HistoryCard(history: history),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: theme.colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: theme.colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color: theme.colorScheme.onErrorContainer,
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
                  ],
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(minHeight: 3),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Secciones
// ---------------------------------------------------------------------------

/// Distinción explícita entre seguimiento interno y autorización oficial.
class _DistinctionBanner extends StatelessWidget {
  const _DistinctionBanner({required this.view});

  final EcfDgiiHabilitationView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final official = view.officialAuthorization;
    final scheme = theme.colorScheme;
    return Card(
      color: official ? scheme.primaryContainer : scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  official ? Icons.verified_outlined : Icons.info_outline,
                  color: official ? scheme.onPrimaryContainer : scheme.onSurface,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    official
                        ? 'Autorización oficial registrada'
                        : 'Sin autorización oficial de la DGII',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: official ? scheme.onPrimaryContainer : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              official
                  ? 'Existe un registro oficial verificable con evidencia. '
                        'Aun así, la emisión real sigue bloqueada hasta que el '
                        'backend la habilite.'
                  : 'El avance que ves abajo es un proceso INTERNO de '
                        'preparación. Nadie dentro de FullPOS puede declarar la '
                        'empresa aprobada: la autorización depende de la DGII.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: official ? scheme.onPrimaryContainer : null,
              ),
            ),
            if (!official && view.officialAuthorizationBlockers.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final blocker in view.officialAuthorizationBlockers)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '· ${blocker.message}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.view,
    required this.canManage,
    required this.busy,
    required this.onAdvance,
    required this.onEditObservations,
  });

  final EcfDgiiHabilitationView view;
  final bool canManage;
  final bool busy;
  final VoidCallback onAdvance;
  final VoidCallback onEditObservations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Section(
      title: 'Seguimiento interno del proceso',
      subtitle:
          'Estados administrativos de la empresa. No son estados oficiales de '
          'la DGII.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Row(label: 'Estado', value: view.stateLabel),
          if (view.reviewState != null && view.reviewState!.isNotEmpty)
            _Row(label: 'Revisión', value: view.reviewState!),
          if (view.authorizedAt != null)
            _Row(label: 'Autorizado el', value: _fmtDate(view.authorizedAt)),
          if (view.externalId != null && view.externalId!.isNotEmpty)
            _Row(label: 'Identificador externo', value: view.externalId!),
          _Row(label: 'Iniciado', value: _fmtDate(view.startedAt)),
          _Row(label: 'Actualizado', value: _fmtDate(view.updatedAt)),
          if (view.observations != null && view.observations!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Observaciones', style: theme.textTheme.labelLarge),
            Text(view.observations!, style: theme.textTheme.bodySmall),
          ],
          if (view.blockers.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Pendientes y bloqueos', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
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
          if (canManage) ...[
            const SizedBox(height: 12),
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
        ],
      ),
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
      subtitle: 'Lo decide la compuerta del backend, no esta pantalla.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusTile(
            icon: realBlocked ? Icons.block : Icons.check_circle_outline,
            color: realBlocked
                ? theme.colorScheme.error
                : const Color(0xFF1B7F3B),
            title: 'Emisión real',
            subtitle: realBlocked
                ? 'Bloqueada'
                : 'Autorizada',
          ),
          _StatusTile(
            icon: emission.simulatedDispatchAuthorized
                ? Icons.science_outlined
                : Icons.do_not_disturb_on_outlined,
            color: emission.simulatedDispatchAuthorized
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
            title: 'Despacho simulado (UAT local)',
            subtitle: emission.simulatedDispatchAuthorized
                ? 'Disponible: no contacta al proveedor ni consume numeración'
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
  const _ProgressCard({
    required this.progress,
    required this.canTrack,
    required this.busy,
    required this.onTrack,
  });

  final EcfDgiiProgress progress;
  final bool canTrack;
  final bool busy;
  final ValueChanged<EcfDgiiRequirementProgress> onTrack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Section(
      title: 'Requisitos y progreso',
      subtitle:
          'El porcentaje lo calcula el backend sobre las etapas reales de la '
          'empresa. El seguimiento de cada requisito es gestión interna y no '
          'cambia ese porcentaje.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: LinearProgressIndicator(
                  value: progress.ratio,
                  minHeight: 8,
                ),
              ),
              const SizedBox(width: 10),
              Text('${progress.percent}%', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${progress.resolvedCount} de ${progress.total} requisitos · '
            'obligatorios ${progress.mandatoryResolved}/${progress.mandatoryTotal}',
            style: theme.textTheme.bodySmall,
          ),
          if (progress.requirements.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'El backend todavía no ha creado los requisitos de esta empresa.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 8),
          for (final requirement in progress.requirements)
            _RequirementRow(
              requirement: requirement,
              canTrack: canTrack,
              busy: busy,
              onTrack: () => onTrack(requirement),
            ),
        ],
      ),
    );
  }
}

class _RequirementRow extends StatelessWidget {
  const _RequirementRow({
    required this.requirement,
    required this.canTrack,
    required this.busy,
    required this.onTrack,
  });

  final EcfDgiiRequirementProgress requirement;
  final bool canTrack;
  final bool busy;
  final VoidCallback onTrack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolved = requirement.resolved;
    final tracking = requirement.tracking;
    final dueDate = tracking?.dueDate;
    final dueSuffix = dueDate == null ? '' : ' · vence $dueDate';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                resolved ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 16,
                color:
                    resolved ? const Color(0xFF1B7F3B) : theme.colorScheme.outline,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  requirement.label,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (tracking != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6, top: 2),
                  child: Text(
                    tracking.statusLabel,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              if (requirement.mandatory)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Tooltip(
                    message: 'Requisito obligatorio',
                    child: Icon(
                      Icons.priority_high,
                      size: 14,
                      color: resolved
                          ? theme.colorScheme.outline
                          : theme.colorScheme.error,
                    ),
                  ),
                ),
              if (!requirement.automatable)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Tooltip(
                    message: 'Requiere trámite externo',
                    child: Icon(Icons.open_in_new, size: 14),
                  ),
                ),
              if (canTrack)
                IconButton(
                  onPressed: busy ? null : onTrack,
                  tooltip: 'Registrar seguimiento interno',
                  icon: const Icon(Icons.edit_note, size: 18),
                ),
            ],
          ),
          if (tracking != null)
            Padding(
              padding: const EdgeInsets.only(left: 24, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Seguimiento interno: ${tracking.statusLabel}$dueSuffix',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (tracking.note != null)
                    Text(tracking.note!, style: theme.textTheme.bodySmall),
                ],
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

    return _Section(
      title: 'Datos fiscales registrados',
      subtitle:
          'Se editan en Configuración de empresa. Aquí solo se comprueba que '
          'existen.',
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
          if (settings != null &&
              settings!.legalRepresentativeName.trim().isNotEmpty)
            _Row(
              label: 'Representante legal',
              value: settings!.legalRepresentativeName,
            ),
          _Row(
            label: 'Configuración fiscal',
            value: fiscalBlocker.isEmpty ? 'Completa' : 'Incompleta',
          ),
          _Row(
            label: 'Integración con el proveedor',
            value: view.providerIntegrationConfigured
                ? 'Configurada'
                : 'Sin configurar',
          ),
          _Row(
            label: 'Certificación (interna)',
            value: view.certificationStatus,
          ),
          if (fiscalBlocker.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              fiscalBlocker.first.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
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
    required this.canRecordAuthorization,
    required this.busy,
    required this.onRegister,
    required this.onReview,
    required this.onRecordAuthorization,
    required this.onRevoke,
  });

  final EcfDgiiHabilitationView view;
  final bool canRegisterEvidence;
  final bool canReviewEvidence;
  final bool canRecordAuthorization;
  final bool busy;
  final VoidCallback onRegister;
  final ValueChanged<EcfDgiiEvidenceView> onReview;
  final VoidCallback onRecordAuthorization;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Section(
      title: 'Evidencias y fuente de verificación',
      subtitle:
          'Solo una fuente OFICIAL autoriza. Una declaración manual se guarda '
          'como registro interno y no habilita nada, ni siquiera después de '
          'marcarla como revisada.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Row(
            label: 'Fuente de verificación',
            value: view.authorizationSource,
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
          if (canRegisterEvidence ||
              canReviewEvidence ||
              canRecordAuthorization) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canRegisterEvidence)
                  OutlinedButton.icon(
                    onPressed: busy ? null : onRegister,
                    icon: const Icon(Icons.attach_file, size: 18),
                    label: const Text('Registrar evidencia'),
                  ),
                if (canRecordAuthorization)
                  FilledButton.tonalIcon(
                    onPressed: busy ? null : onRecordAuthorization,
                    icon: const Icon(Icons.verified_outlined, size: 18),
                    label: const Text('Registrar autorización recibida'),
                  ),
                if (canRecordAuthorization &&
                    (view.officialAuthorization ||
                        view.authorizationSource != 'NONE'))
                  TextButton.icon(
                    onPressed: busy ? null : onRevoke,
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Revocar'),
                  ),
              ],
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
                          : evidence.kind,
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
    return _Section(
      title: 'Historial de cambios',
      child: history.when(
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
  const _EvidenceDialog();

  @override
  State<_EvidenceDialog> createState() => _EvidenceDialogState();
}

class _EvidenceDialogState extends State<_EvidenceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _kind = TextEditingController();
  final _storageRef = TextEditingController();
  final _description = TextEditingController();
  String _source = 'OFFICIAL_DOCUMENT';

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
      title: const Text('Registrar evidencia'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Se guarda la REFERENCIA a la evidencia, nunca el documento ni '
                'credenciales.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _source,
                decoration: const InputDecoration(labelText: 'Procedencia'),
                items: const [
                  DropdownMenuItem(
                    value: 'OFFICIAL_DOCUMENT',
                    child: Text('Documento oficial'),
                  ),
                  DropdownMenuItem(
                    value: 'PROVIDER_ARTIFACT',
                    child: Text('Artefacto del proveedor'),
                  ),
                  DropdownMenuItem(
                    value: 'MANUAL_DECLARATION',
                    child: Text('Declaración manual'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _source = value ?? _source),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _kind,
                decoration: const InputDecoration(
                  labelText: 'Tipo de evidencia',
                  hintText: 'resolucion-dgii, certificado, acuse…',
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Indica el tipo de evidencia'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _storageRef,
                decoration: const InputDecoration(
                  labelText: 'Referencia de almacenamiento',
                  hintText: 'uat://empresa/resolucion-2026',
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
                source: _source,
                kind: _kind.text.trim(),
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
                  hintText: 'UUID de una evidencia ya registrada',
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
                  if (raw.isEmpty) return 'La fuente oficial exige identificador';
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
    Navigator.of(context).pop(
      _ReviewInput(decision: decision, note: note.isEmpty ? null : note),
    );
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

class _RequirementTrackingInput {
  const _RequirementTrackingInput({
    required this.status,
    this.note,
    this.dueDate,
  });

  final String status;
  final String? note;
  final String? dueDate;
}

/// Seguimiento interno de un requisito: estado de gestión, fecha y nota.
class _RequirementTrackingDialog extends StatefulWidget {
  const _RequirementTrackingDialog({required this.requirement});

  final EcfDgiiRequirementProgress requirement;

  @override
  State<_RequirementTrackingDialog> createState() =>
      _RequirementTrackingDialogState();
}

class _RequirementTrackingDialogState extends State<_RequirementTrackingDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _note;
  late final TextEditingController _dueDate;
  late String _status;

  @override
  void initState() {
    super.initState();
    final tracking = widget.requirement.tracking;
    _status = tracking?.status ?? 'IN_PROGRESS';
    _note = TextEditingController(text: tracking?.note ?? '');
    _dueDate = TextEditingController(text: tracking?.dueDate ?? '');
  }

  @override
  void dispose() {
    _note.dispose();
    _dueDate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final requirement = widget.requirement;
    return AlertDialog(
      title: const Text('Seguimiento del requisito'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                requirement.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              const Text(
                'Es una libreta de trabajo interna: no cambia el progreso real '
                'de la empresa ni acredita nada ante la DGII.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Estado interno'),
                items: [
                  for (final status in EcfDgiiRequirementTracking.statuses)
                    DropdownMenuItem(
                      value: status,
                      child: Text(
                        EcfDgiiRequirementTracking.labelForStatus(status),
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _status = value ?? _status),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _dueDate,
                decoration: const InputDecoration(
                  labelText: 'Fecha objetivo',
                  hintText: 'AAAA-MM-DD',
                ),
                validator: (value) {
                  final raw = value?.trim() ?? '';
                  if (raw.isEmpty) return null;
                  final ok = RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw);
                  return ok ? null : 'Usa el formato AAAA-MM-DD';
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _note,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Nota'),
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
              _RequirementTrackingInput(
                status: _status,
                note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                dueDate: _dueDate.text.trim().isEmpty
                    ? null
                    : _dueDate.text.trim(),
              ),
            );
          },
          child: const Text('Guardar'),
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
              SizedBox(
                width: 180,
                child: Text(label, style: labelStyle),
              ),
              Expanded(
                child: Text(value, style: valueStyle),
              ),
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

String _fmtDate(DateTime? value) {
  if (value == null) return '—';
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} '
      '${two(local.hour)}:${two(local.minute)}';
}
