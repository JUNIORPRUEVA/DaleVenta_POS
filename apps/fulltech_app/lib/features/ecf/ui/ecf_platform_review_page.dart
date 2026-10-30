import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ecf_platform_repository.dart';
import '../ecf_platform_models.dart';
import 'dgii_document_saver_factory.dart';

/// Etiquetas legibles de los estados de seguimiento.
///
/// Son las mismas del expediente de la empresa: el panel de plataforma no
/// inventa un vocabulario nuevo para el mismo concepto.
const Map<String, String> _stateLabels = <String, String>{
  'NOT_STARTED': 'Sin iniciar',
  'PREPARING_REQUIREMENTS': 'Preparando requisitos',
  'APPLICATION_PENDING': 'Solicitud enviada',
  'IN_PROGRESS': 'En revisión',
  'TESTS_PENDING': 'Pruebas pendientes',
  'IN_CERTIFICATION': 'En certificación',
  'APPROVED': 'Aprobado',
  'REJECTED': 'Rechazado',
  'REQUIRES_CORRECTION': 'Requiere corrección',
};

String _label(String state) => _stateLabels[state] ?? state;

/// Etiquetas del seguimiento de un requisito.
const Map<String, String> _requirementLabels = <String, String>{
  'PENDING': 'Pendiente',
  'IN_PROGRESS': 'En curso',
  'BLOCKED': 'Bloqueado',
  'COMPLETED': 'Completado',
  'NOT_APPLICABLE': 'No aplica',
};

String _requirementLabel(String status) =>
    _requirementLabels[status] ?? status;

/// Etapas del motor de activación en lenguaje del producto.
const Map<String, String> _activationStageLabels = <String, String>{
  'NOT_STARTED': 'Sin iniciar',
  'RUNNING': 'En proceso',
  'BLOCKED_ON_CLIENT': 'Esperando al cliente',
  'BLOCKED_ON_PROVIDER': 'Esperando al proveedor',
  'AWAITING_AUTHORITY': 'Pendiente de la DGII',
  'COMPLETED': 'Pasos internos completados',
};

/// Dueño de cada paso del motor.
const Map<String, String> _activationClassLabels = <String, String>{
  'AUTOMATIC_LOCAL': 'Automático',
  'PROVIDER_WAIT': 'Proveedor',
  'CLIENT_ACTION': 'Cliente',
  'AUTHORITY_WAIT': 'DGII',
};

/// Estados que la cola puede filtrar.
const List<String> _filterStates = <String>[
  'APPLICATION_PENDING',
  'IN_PROGRESS',
  'TESTS_PENDING',
  'IN_CERTIFICATION',
  'REQUIRES_CORRECTION',
  'REJECTED',
  'APPROVED',
];

/// Traduce un fallo del backend a un texto accionable.
///
/// Se prefiere el código del servidor porque es el que identifica la regla
/// incumplida; nunca se sustituye por un mensaje genérico que oculte el motivo.
String _readError(Object error) {
  final text = error.toString();
  const known = <String, String>{
    'PLATFORM_STAFF_REQUIRED':
        'Tu usuario no pertenece al equipo de Fulltech.',
    'ECF_DGII_CORRECTION_REASON_REQUIRED':
        'Escribe el motivo: una corrección o un rechazo sin motivo no es '
            'auditable.',
    'ECF_DGII_TRANSITION_NOT_ALLOWED':
        'Ese cambio de estado no está permitido desde el estado actual.',
    'ECF_DGII_APPROVAL_REQUIRES_OFFICIAL_RECORD':
        'La aprobación exige un registro oficial de la DGII con evidencia, '
            'fecha e identificador externo. No se declara desde aquí.',
    'ECF_DGII_EVIDENCE_REJECTION_REASON_REQUIRED':
        'Un rechazo de evidencia exige motivo.',
    'ECF_DGII_EVIDENCE_REVIEW_DECISION_REQUIRED':
        'Elige una decisión de revisión.',
    'ECF_DGII_DOWNLOAD_NOT_SUPPORTED_ON_WEB':
        'La descarga directa no está disponible en el navegador.',
    'ECF_DGII_DOWNLOAD_NOT_SUPPORTED_ON_PLATFORM':
        'Esta plataforma no permite guardar el documento.',
    'ECF_DGII_DOCUMENT_EMPTY': 'El documento llegó vacío.',
    'ECF_DGII_DOCUMENT_NOT_FOUND': 'El documento ya no existe.',
    'ECF_DGII_APPLICATION_NOT_FOUND': 'No existe un expediente para esa empresa.',
    'ECF_DGII_STATE_UNKNOWN': 'Estado desconocido.',
  };
  for (final entry in known.entries) {
    if (text.contains(entry.key)) return entry.value;
  }
  return 'No se pudo completar la operación. Inténtalo de nuevo.';
}

/// Cola de revisión de expedientes DGII para el personal de Fulltech.
///
/// La página no decide por su cuenta quién puede verla: pregunta al backend
/// (`/ecf/platform/me`). Si la respuesta no confirma pertenencia, no se muestra
/// ningún dato de empresas, ni siquiera el número de expedientes.
class EcfPlatformReviewPage extends ConsumerStatefulWidget {
  const EcfPlatformReviewPage({super.key});

  @override
  ConsumerState<EcfPlatformReviewPage> createState() =>
      _EcfPlatformReviewPageState();
}

class _EcfPlatformReviewPageState extends ConsumerState<EcfPlatformReviewPage> {
  String? _stateFilter;

  Future<void> _refresh() async {
    ref.invalidate(ecfPlatformApplicationsProvider(_stateFilter));
    try {
      await ref.read(ecfPlatformApplicationsProvider(_stateFilter).future);
    } catch (_) {
      // El estado del provider ya pinta el error; se captura para no dejar una
      // excepción asíncrona sin manejar al reintentar.
    }
  }

  @override
  Widget build(BuildContext context) {
    final staff = ref.watch(ecfPlatformStaffProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Revisión de expedientes DGII')),
      body: staff.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _MessageCard(
          icon: Icons.error_outline,
          title: 'No se pudo verificar el acceso',
          message: _readError(error),
        ),
        data: (isStaff) {
          if (!isStaff) {
            return const _MessageCard(
              icon: Icons.lock_outline,
              title: 'Sección del equipo de Fulltech',
              message:
                  'Tu usuario no tiene acceso a la revisión de expedientes de '
                  'otras empresas.',
            );
          }
          return _buildQueue();
        },
      ),
    );
  }

  Widget _buildQueue() {
    final queue = ref.watch(ecfPlatformApplicationsProvider(_stateFilter));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _stateFilter,
                  decoration: const InputDecoration(
                    labelText: 'Estado',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Todos'),
                    ),
                    for (final state in _filterStates)
                      DropdownMenuItem<String?>(
                        value: state,
                        child: Text(_label(state)),
                      ),
                  ],
                  onChanged: (value) => setState(() => _stateFilter = value),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: queue.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _MessageCard(
              icon: Icons.cloud_off,
              title: 'No se pudo cargar la cola',
              message: _readError(error),
              action: FilledButton.tonal(
                onPressed: _refresh,
                child: const Text('Reintentar'),
              ),
            ),
            data: (page) {
              if (page.items.isEmpty) {
                return const _MessageCard(
                  icon: Icons.inbox_outlined,
                  title: 'No hay expedientes',
                  message: 'Ningún expediente coincide con el filtro elegido.',
                );
              }
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView.separated(
                  itemCount: page.items.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = page.items[index];
                    return _ApplicationTile(
                      application: item,
                      onTap: () => _openDetail(item.companyId),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _openDetail(String companyId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _EcfPlatformApplicationDetailPage(companyId: companyId),
      ),
    );
    await _refresh();
  }
}

class _ApplicationTile extends StatelessWidget {
  const _ApplicationTile({required this.application, required this.onTap});

  final EcfPlatformApplication application;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(
        application.companyName ?? application.companyId,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        _label(application.state),
        style: theme.textTheme.bodySmall,
      ),
      trailing: application.hasOfficialAuthorization
          ? Icon(Icons.verified, color: theme.colorScheme.primary)
          : const Icon(Icons.pending_outlined),
      onTap: onTap,
    );
  }
}

/// Detalle y decisión de UN expediente.
class _EcfPlatformApplicationDetailPage extends ConsumerStatefulWidget {
  const _EcfPlatformApplicationDetailPage({required this.companyId});

  final String companyId;

  @override
  ConsumerState<_EcfPlatformApplicationDetailPage> createState() =>
      _EcfPlatformApplicationDetailPageState();
}

class _EcfPlatformApplicationDetailPageState
    extends ConsumerState<_EcfPlatformApplicationDetailPage> {
  bool _busy = false;
  String? _error;

  Future<void> _decide({
    required String state,
    required bool reasonRequired,
    String reviewState = 'PENDING_FULLTECH_REVIEW',
  }) async {
    if (_busy) return;
    String? reason;
    if (reasonRequired) {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Motivo'),
          content: TextField(
            controller: controller,
            maxLines: 4,
            maxLength: 2000,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Qué debe corregir la empresa',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Guardar'),
            ),
          ],
        ),
      );
      if (reason == null) return;
      if (reason.isEmpty) {
        setState(() => _error = 'Escribe el motivo antes de continuar.');
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(ecfPlatformRepositoryProvider)
          .decide(
            companyId: widget.companyId,
            state: state,
            reviewState: reviewState,
            observations: reason,
          );
      ref.invalidate(ecfPlatformApplicationProvider(widget.companyId));
      await ref.read(ecfPlatformApplicationProvider(widget.companyId).future);
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _readError(error);
      });
    }
  }

  /// Ejecuta una mutación con protección contra doble pulsación y refresco del
  /// expediente y de los requisitos. Nunca lanza: la pantalla sigue usable.
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      ref.invalidate(ecfPlatformApplicationProvider(widget.companyId));
      ref.invalidate(ecfPlatformRequirementsProvider(widget.companyId));
      ref.invalidate(ecfPlatformActivationProvider(widget.companyId));
      await ref.read(ecfPlatformApplicationProvider(widget.companyId).future);
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _readError(error);
      });
    }
  }

  /// Revisa UN requisito del catálogo (seguimiento interno, no aprobación).
  Future<void> _reviewRequirement(EcfPlatformRequirement requirement) async {
    if (_busy) return;
    var selected = requirement.status ?? 'PENDING';
    final noteController = TextEditingController(text: requirement.note ?? '');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(requirement.label),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: const InputDecoration(
                  labelText: 'Estado del requisito',
                  isDense: true,
                ),
                items: [
                  for (final status in ecfPlatformRequirementStatuses)
                    DropdownMenuItem<String>(
                      value: status,
                      child: Text(_requirementLabel(status)),
                    ),
                ],
                onChanged: (value) =>
                    setDialogState(() => selected = value ?? selected),
              ),
              TextField(
                controller: noteController,
                maxLines: 3,
                maxLength: 500,
                decoration: const InputDecoration(labelText: 'Observación'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    final note = noteController.text.trim();
    await _run(
      () => ref
          .read(ecfPlatformRepositoryProvider)
          .reviewRequirement(
            companyId: widget.companyId,
            key: requirement.key,
            status: selected,
            note: note.isEmpty ? null : note,
          ),
    );
  }

  /// Revisa una evidencia. Rechazar exige motivo; marcar como revisada no
  /// convierte la evidencia en registro oficial.
  Future<void> _reviewEvidence(EcfPlatformEvidence item) async {
    if (_busy) return;
    var decision = item.reviewStatus == 'REVIEWED' ? 'REVIEWED' : 'REJECTED';
    final noteController = TextEditingController(text: item.reviewNote ?? '');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(item.fileName ?? item.kind),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: decision,
                decoration: const InputDecoration(
                  labelText: 'Decisión',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'REVIEWED', child: Text('Revisada')),
                  DropdownMenuItem(value: 'REJECTED', child: Text('Rechazada')),
                ],
                onChanged: (value) =>
                    setDialogState(() => decision = value ?? decision),
              ),
              TextField(
                controller: noteController,
                maxLines: 3,
                maxLength: 1000,
                decoration: InputDecoration(
                  labelText: decision == 'REJECTED'
                      ? 'Motivo del rechazo (obligatorio)'
                      : 'Nota de revisión',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (accepted != true) return;
    final note = noteController.text.trim();
    await _run(
      () => ref
          .read(ecfPlatformRepositoryProvider)
          .reviewEvidence(
            companyId: widget.companyId,
            evidenceId: item.id,
            decision: decision,
            note: note.isEmpty ? null : note,
          ),
    );
  }

  /// Descarga autorizada del documento.
  Future<void> _download(EcfPlatformEvidence item) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await ref
          .read(ecfPlatformRepositoryProvider)
          .downloadDocument(
            companyId: widget.companyId,
            evidenceId: item.id,
          );
      final path = await PlatformDgiiDocumentSaver().save(
        fileName: item.fileName ?? '${item.kind}.bin',
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Documento guardado en $path')));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _readError(error);
      });
    }
  }

  /// Cierra la revisión interna. No aprueba: deja el expediente en pruebas y
  /// la autorización oficial sigue dependiendo de un registro verificado.
  Future<void> _completeInternalReview() async {
    await _decide(
      state: 'TESTS_PENDING',
      reasonRequired: false,
      reviewState: 'FULLTECH_REVIEW_COMPLETED',
    );
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(ecfPlatformApplicationProvider(widget.companyId));
    return Scaffold(
      appBar: AppBar(title: const Text('Expediente')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _MessageCard(
          icon: Icons.cloud_off,
          title: 'No se pudo cargar el expediente',
          message: _readError(error),
        ),
        data: (data) => _buildDetail(data),
      ),
    );
  }

  /// Requisitos del catálogo con su seguimiento. Un requisito sin seguimiento
  /// se muestra como «sin revisar»: no se le atribuye un estado que no existe.
  Widget _buildRequirements() {
    final theme = Theme.of(context);
    final requirements = ref.watch(
      ecfPlatformRequirementsProvider(widget.companyId),
    );
    return requirements.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      ),
      error: (error, _) => Text(
        _readError(error),
        style: theme.textTheme.bodySmall,
      ),
      data: (items) {
        if (items.isEmpty) {
          return Text(
            'El catálogo no tiene requisitos.',
            style: theme.textTheme.bodySmall,
          );
        }
        return Column(
          children: [
            for (final item in items)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(item.label),
                subtitle: Text(
                  [
                    item.status == null
                        ? 'Sin revisar'
                        : _requirementLabel(item.status!),
                    if (item.mandatory) 'obligatorio',
                    if (item.automatable) 'automatizable',
                  ].join(' · '),
                ),
                trailing: IconButton(
                  tooltip: 'Revisar requisito',
                  onPressed: _busy ? null : () => _reviewRequirement(item),
                  icon: const Icon(Icons.fact_check_outlined),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Estado del MOTOR DE ACTIVACIÓN de la empresa.
  ///
  /// Solo lectura deliberada: la plataforma supervisa el avance, no lo produce.
  /// Por eso aquí no hay botones de ejecutar ni de completar pasos; el motor lo
  /// gobierna la empresa dueña del expediente.
  Widget _buildActivation() {
    final theme = Theme.of(context);
    final activation = ref.watch(
      ecfPlatformActivationProvider(widget.companyId),
    );
    return activation.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      ),
      error: (error, _) => Text(
        _readError(error),
        style: theme.textTheme.bodySmall,
      ),
      data: (data) {
        if (data.steps.isEmpty) {
          return Text(
            'El motor todavía no tiene pasos para esta empresa.',
            style: theme.textTheme.bodySmall,
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _activationStageLabels[data.stage] ?? data.stage,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: data.percent / 100),
            const SizedBox(height: 4),
            Text(
              '${data.resolvedCount} de ${data.total} pasos · '
              '${data.percent} %',
              style: theme.textTheme.bodySmall,
            ),
            if (data.transport.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Transporte ${data.transport}. Los pasos los ejecuta la '
                'empresa; la plataforma solo supervisa.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 4),
            for (final step in data.steps)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(
                  step.resolved
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: step.resolved
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                title: Text(step.label),
                subtitle: Text(
                  [
                    _activationClassLabels[step.className] ?? step.className,
                    step.awaiting ?? step.status,
                  ].join(' · '),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Alcance con el que esta visita está autorizada.
  ///
  /// La concesión la da la EMPRESA y caduca. Mostrarla evita que un revisor
  /// confunda una asistencia temporal con un permiso permanente, y explica por
  /// qué algunas acciones pueden estar bloqueadas: no es un fallo de la
  /// aplicación, es el alcance concedido.
  Widget _buildAccess() {
    final theme = Theme.of(context);
    final access = ref.watch(ecfPlatformAccessProvider(widget.companyId));
    return access.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: LinearProgressIndicator(minHeight: 3),
      ),
      error: (error, _) => Text(
        _readError(error),
        style: theme.textTheme.bodySmall,
      ),
      data: (data) {
        if (!data.hasGrant) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'La empresa no tiene una asistencia activa: no deberías poder ver '
              'este expediente.',
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          );
        }
        final until = data.expiresAt;
        final expiry = until == null
            ? 'sin caducidad registrada'
            : 'hasta '
                  '${until.day.toString().padLeft(2, '0')}/'
                  '${until.month.toString().padLeft(2, '0')}/${until.year} '
                  '${until.hour.toString().padLeft(2, '0')}:'
                  '${until.minute.toString().padLeft(2, '0')}';
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.vpn_key_outlined,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Asistencia autorizada por la empresa · $expiry',
                      style: theme.textTheme.labelMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Alcance: ${data.scopes.join(", ")}',
                style: theme.textTheme.bodySmall,
              ),
              if (data.isReadOnlyOnly)
                Text(
                  'Solo lectura: revisar requisitos y evidencias requiere un '
                  'alcance que la empresa no ha concedido.',
                  style: theme.textTheme.bodySmall,
                ),
              if ((data.reason ?? '').trim().isNotEmpty)
                Text(
                  'Motivo declarado: ${data.reason}',
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetail(EcfPlatformApplicationDetail data) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          data.companyName ?? data.companyId,
          style: theme.textTheme.titleMedium,
        ),
        if (data.rnc != null)
          Text('RNC ${data.rnc}', style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        _buildAccess(),
        const SizedBox(height: 8),
        _Fact(label: 'Estado', value: _label(data.state)),
        _Fact(label: 'Revisión', value: data.reviewState ?? 'Sin revisar'),
        _Fact(
          label: 'Autorización oficial',
          value: data.hasOfficialAuthorization
              ? 'Registrada (${data.authorizationSource})'
              : 'No registrada',
        ),
        _Fact(
          label: 'Observaciones',
          value: data.observations ?? 'Sin observaciones',
        ),
        const SizedBox(height: 16),
        Text('Requisitos', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        _buildRequirements(),
        const SizedBox(height: 16),
        Text('Activación', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        _buildActivation(),
        const SizedBox(height: 16),
        Text('Evidencias', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        if (data.evidence.isEmpty)
          Text('Sin documentos cargados.', style: theme.textTheme.bodySmall)
        else
          for (final item in data.evidence)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: Text(item.fileName ?? item.kind),
              subtitle: Text(
                '${item.kind} · ${item.source} · ${item.reviewStatus}',
              ),
              dense: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Descargar',
                    onPressed: _busy ? null : () => _download(item),
                    icon: const Icon(Icons.download_outlined),
                  ),
                  IconButton(
                    tooltip: 'Revisar evidencia',
                    onPressed: _busy ? null : () => _reviewEvidence(item),
                    icon: const Icon(Icons.rate_review_outlined),
                  ),
                ],
              ),
            ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonal(
              onPressed: _busy
                  ? null
                  : () => _decide(state: 'IN_PROGRESS', reasonRequired: false),
              child: const Text('Marcar en revisión'),
            ),
            FilledButton(
              onPressed: _busy ? null : _completeInternalReview,
              child: const Text('Revisión interna completada'),
            ),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _decide(
                      state: 'REQUIRES_CORRECTION',
                      reasonRequired: true,
                    ),
              child: const Text('Solicitar corrección'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => _decide(state: 'REJECTED', reasonRequired: true),
              child: const Text('Rechazar'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'No existe un botón para aprobar: la aprobación exige un registro '
          'oficial de la DGII con evidencia, fecha e identificador externo.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(
              message,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}
