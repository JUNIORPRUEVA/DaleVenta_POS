import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../data/ecf_application_repository.dart';
import '../data/ecf_repository.dart';
import '../ecf_models.dart';
import 'dgii_document_saver.dart';
import 'dgii_document_saver_factory.dart';

/// Asistente de postulación DGII.
///
/// Reutiliza el expediente que ya existe (`ecf_dgii_habilitations`) y las rutas
/// documentales. **No crea un segundo expediente** ni un segundo catálogo de
/// requisitos: lee el progreso real del backend y actúa sobre él.
///
/// Lo que este asistente NO hace, por diseño:
///  * No aprueba nada: "enviar a revisión" mueve el seguimiento INTERNO.
///  * No declara habilitación oficial: esa solo se registra con evidencia
///    oficial verificada y permiso propio.
///  * No envía nada a Alanube ni a la DGII.
/// Estado visible del autoguardado del borrador.
enum _DataSaveStatus { idle, saving, saved, error }

class EcfDgiiApplicationWizard extends ConsumerStatefulWidget {
  const EcfDgiiApplicationWizard({super.key});

  @override
  ConsumerState<EcfDgiiApplicationWizard> createState() =>
      _EcfDgiiApplicationWizardState();
}

class _EcfDgiiApplicationWizardState
    extends ConsumerState<EcfDgiiApplicationWizard> {
  static const _documentKinds = <String, String>{
    'REPRESENTATIVE_ID': 'Identificación del representante',
    'COMPANY_DOCUMENT': 'Documento de la empresa',
    'AUTHORIZATION': 'Autorización',
    'POSTULATION_XML': 'XML de postulación',
    'DGII_RECEIPT': 'Constancia DGII',
    'OTHER': 'Otro documento',
  };

  int _step = 0;
  bool _busy = false;
  String? _error;
  String _kind = 'COMPANY_DOCUMENT';
  PlatformFile? _picked;

  // Datos del expediente: empresa y representante legal. Se guardan en el
  // servidor como borrador persistente, no en memoria del dispositivo.
  final _rnc = TextEditingController();
  final _legalName = TextEditingController();
  final _address = TextEditingController();
  final _repName = TextEditingController();
  final _repId = TextEditingController();
  final _repEmail = TextEditingController();
  List<String> _missingFields = const [];

  /// Estado del autoguardado que se muestra al usuario.
  _DataSaveStatus _saveStatus = _DataSaveStatus.idle;

  /// `true` cuando hay cambios locales que el servidor todavía no confirmó.
  bool _dirty = false;

  /// Secuencia de guardados: solo la ÚLTIMA petición puede escribir el estado.
  /// Sin esto, una respuesta lenta anterior podría sobrescribir el resultado de
  /// una posterior y dejar la UI mostrando «guardado» con datos sin persistir.
  int _saveSequence = 0;

  /// Revisión del borrador en el servidor (control optimista).
  int _draftRevision = 0;

  Timer? _debounce;
  static const _debounceDelay = Duration(milliseconds: 800);

  final DgiiDocumentSaver _saver = PlatformDgiiDocumentSaver();

  @override
  void initState() {
    super.initState();
    for (final controller in _controllers) {
      controller.addListener(_onFieldChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDraft());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final controller in _controllers) {
      controller.removeListener(_onFieldChanged);
      controller.dispose();
    }
    super.dispose();
  }

  List<TextEditingController> get _controllers => [
        _rnc,
        _legalName,
        _address,
        _repName,
        _repId,
        _repEmail,
      ];

  /// Marca cambios locales y programa el guardado con retardo.
  void _onFieldChanged() {
    if (!_dirty) setState(() => _dirty = true);
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, _autoSave);
  }

  /// Guarda el borrador ahora y devuelve si quedó persistido.
  ///
  /// Las respuestas fuera de orden se descartan: si mientras se esperaba se
  /// lanzó otro guardado, esta respuesta ya no es la vigente.
  Future<bool> _autoSave() async {
    _debounce?.cancel();
    final attempt = ++_saveSequence;
    if (mounted) setState(() => _saveStatus = _DataSaveStatus.saving);
    try {
      final saved = await ref
          .read(ecfApplicationRepositoryProvider)
          .saveDraft(_payload(), expectedRevision: _draftRevision);
      if (attempt != _saveSequence) return false;
      if (!mounted) return false;
      setState(() {
        _saveStatus = _DataSaveStatus.saved;
        _dirty = false;
        _draftRevision = saved.draftRevision;
        _missingFields = saved.missingFields;
      });
      return true;
    } catch (error) {
      if (attempt != _saveSequence) return false;
      if (!mounted) return false;
      if (error.toString().contains('ECF_DGII_DRAFT_CONFLICT')) {
        // Otro dispositivo guardó primero: se adopta la versión vigente en vez
        // de imponer la local. No se pierde nada en silencio.
        await _adoptServerDraft();
        return false;
      }
      setState(() {
        _saveStatus = _DataSaveStatus.error;
        _error = _messageFor(error);
      });
      return false;
    }
  }

  /// Recupera la versión vigente del servidor y rellena el formulario con ella.
  Future<void> _adoptServerDraft() async {
    try {
      final draft = await ref.read(ecfApplicationRepositoryProvider).draft();
      if (!mounted) return;
      final raw = draft.draft;
      final company = raw?['company'];
      final representative = raw?['representative'];
      setState(() {
        if (company is Map) {
          _rnc.text = (company['rnc'] as String?) ?? '';
          _legalName.text = (company['legalName'] as String?) ?? '';
          _address.text = (company['address'] as String?) ?? '';
        }
        if (representative is Map) {
          _repName.text = (representative['fullName'] as String?) ?? '';
          _repId.text = (representative['identification'] as String?) ?? '';
          _repEmail.text = (representative['email'] as String?) ?? '';
        }
        _draftRevision = draft.draftRevision;
        _saveStatus = _DataSaveStatus.saved;
        _dirty = false;
        _missingFields = draft.missingFields;
        _error =
            'El borrador se actualizó en otro dispositivo. Se cargó la versión '
            'más reciente; revisa los datos antes de continuar.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saveStatus = _DataSaveStatus.error;
        _error = _messageFor(error);
      });
    }
  }

  Map<String, dynamic> _payload() => {
        'company': {
          'rnc': _rnc.text.trim(),
          'legalName': _legalName.text.trim(),
          'address': _address.text.trim(),
        },
        'representative': {
          'fullName': _repName.text.trim(),
          'identification': _repId.text.trim(),
          'email': _repEmail.text.trim(),
        },
      };

  /// Recupera el borrador guardado: cerrar sesión y volver no pierde el trabajo.
  Future<void> _loadDraft() async {
    try {
      final draft = await ref.read(ecfApplicationRepositoryProvider).draft();
      if (!mounted) return;
      final raw = draft.draft;
      final company = raw?['company'];
      final representative = raw?['representative'];
      setState(() {
        if (company is Map) {
          _rnc.text = (company['rnc'] as String?) ?? '';
          _legalName.text = (company['legalName'] as String?) ?? '';
          _address.text = (company['address'] as String?) ?? '';
        }
        if (representative is Map) {
          _repName.text = (representative['fullName'] as String?) ?? '';
          _repId.text = (representative['identification'] as String?) ?? '';
          _repEmail.text = (representative['email'] as String?) ?? '';
        }
        _missingFields = draft.missingFields;
        _draftRevision = draft.draftRevision;
      });
    } catch (error) {
      // Un fallo al recuperar el borrador no debe impedir escribir uno nuevo.
      if (!mounted) return;
      setState(() => _error = _messageFor(error));
    }
  }

  /// Guarda el borrador y deja el asistente en el paso de requisitos.
  Future<void> _advance() async {
    if (_step != 0) {
      setState(() => _step += 1);
      return;
    }
    // No se avanza si el borrador no quedó persistido: el paso siguiente
    // mostraría progreso sobre datos que el servidor no conoce.
    final saved = await _autoSave();
    if (!saved) {
      if (!mounted) return;
      setState(
        () => _error = _dirty
            ? 'No se pudo guardar el borrador. Revisa la conexión y reintenta.'
            : _error,
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _error = null;
      _step = 1;
    });
    // Confirmación explícita en el momento de pulsar «Continuar»: es cuando el
    // usuario mira, y el estado de la cabecera pasa desapercibido.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Borrador guardado en el servidor.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  bool get _canWrite {
    final user = ref.watch(authStateProvider).user;
    return hasUserPermission(user, AppPermission.manageEcfOnboarding);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      ref.invalidate(ecfDgiiHabilitationProvider);
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _messageFor(error);
      });
    }
  }

  String _messageFor(Object error) {
    final raw = error.toString();
    if (raw.contains('ECF_DGII_DOCUMENT_TOO_LARGE')) {
      return 'El archivo supera el máximo permitido (5 MB).';
    }
    if (raw.contains('ECF_DGII_DOCUMENT_TYPE_NOT_ALLOWED')) {
      return 'Solo se admiten PDF, PNG, JPG o XML.';
    }
    if (raw.contains('ECF_DGII_DOCUMENT_MIME_MISMATCH')) {
      return 'El contenido del archivo no corresponde a su tipo.';
    }
    if (raw.contains('ECF_DGII_DOCUMENT_NOT_FOUND')) {
      return 'El documento ya no está disponible.';
    }
    if (raw.contains('ECF_DGII_DOWNLOAD_NOT_SUPPORTED_ON_WEB')) {
      return 'La descarga a disco no está disponible en el navegador.';
    }
    if (raw.contains('ECF_DGII_DRAFT_CONFLICT')) {
      return 'El borrador cambió en otro dispositivo. Se cargó la versión más reciente.';
    }
    if (raw.contains('ECF_DGII_DRAFT_REVISION_REQUIRED')) {
      return 'El borrador cambió. Recarga antes de guardar.';
    }
    if (raw.contains('ECF_DGII_DRAFT_INCOMPLETE')) {
      return 'Faltan datos obligatorios del expediente: '
          '${_missingFields.isEmpty ? 'revisa el paso Datos.' : _missingFields.join(', ')}';
    }
    if (raw.contains('ECF_DGII_CONSENT_REQUIRED')) {
      return 'Debes aceptar el consentimiento antes de enviar.';
    }
    if (raw.contains('ECF_DGII_CONSENT_VERSION_UNKNOWN')) {
      return 'El texto de consentimiento cambió. Recarga y vuelve a aceptarlo.';
    }
    if (raw.contains('ECF_DGII_TRANSITION_NOT_ALLOWED')) {
      return 'El expediente ya está en revisión. Para cambiarlo, espera una '
          'solicitud de corrección.';
    }
    if (raw.contains('403')) {
      return 'No tienes permiso para gestionar el expediente.';
    }
    if (raw.contains('401')) {
      return 'Tu sesión expiró. Vuelve a iniciar sesión.';
    }
    return 'No se pudo completar la operación. Inténtalo de nuevo.';
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: false,
    );
    final file =
        (result == null || result.files.isEmpty) ? null : result.files.first;
    if (file == null) return;
    setState(() {
      _picked = file;
      _error = null;
    });
  }

  Future<void> _upload() async {
    final file = _picked;
    final bytes = file?.bytes;
    if (file == null || bytes == null) {
      setState(() => _error = 'Selecciona un archivo antes de subirlo.');
      return;
    }
    await _run(() async {
      await ref.read(ecfRepositoryProvider).uploadDgiiDocument(
            kind: _kind,
            bytes: bytes,
            fileName: file.name,
          );
      if (!mounted) return;
      setState(() => _picked = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Documento añadido al expediente.')),
      );
    });
  }

  Future<void> _download(EcfDgiiEvidenceView evidence) async {
    await _run(() async {
      final bytes =
          await ref.read(ecfRepositoryProvider).downloadDgiiDocument(evidence.id);
      final path = await _saver.save(
        fileName: evidence.fileName ?? 'documento',
        bytes: bytes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Documento guardado en $path')),
      );
    });
  }

  Future<void> _submit() async {
    // Nunca se envía con cambios locales sin persistir: el snapshot guardaría
    // datos distintos de los que el usuario está viendo.
    if (_dirty || _saveStatus == _DataSaveStatus.saving) {
      final flushed = await _autoSave();
      if (!flushed) {
        if (!mounted) return;
        setState(
          () => _error =
              'Hay cambios sin guardar. No se puede enviar el expediente.',
        );
        return;
      }
    }

    EcfApplicationDraft draft;
    try {
      draft = await ref.read(ecfApplicationRepositoryProvider).draft();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(error));
      return;
    }
    if (draft.missingFields.isNotEmpty) {
      setState(() {
        _missingFields = draft.missingFields;
        _error = 'Faltan datos obligatorios: ${draft.missingFields.join(', ')}';
        _step = 0;
      });
      return;
    }

    final accepted = await _confirmConsent(draft);
    if (accepted != true) return;

    await _run(() async {
      // El servidor crea una versión INMUTABLE con los datos y los hashes de los
      // documentos. No autoriza nada ante la DGII.
      final result = await ref.read(ecfApplicationRepositoryProvider).submit(
            consentVersion: draft.requiredConsentVersion,
            payload: _payload(),
          );
      ref.invalidate(ecfApplicationDraftProvider);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            result.idempotent
                ? 'El expediente ya estaba enviado (versión ${result.version}).'
                : 'Expediente enviado. Versión ${result.version}.',
          ),
        ),
      );
    });
  }

  Future<bool?> _confirmConsent(EcfApplicationDraft draft) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Consentimiento'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(draft.consentPurpose),
              const SizedBox(height: 12),
              Text(
                'Versión del texto: ${draft.requiredConsentVersion}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Esta aceptación no sustituye ningún poder legal de '
                'representación ante la DGII.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Acepto y envío'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ecfDgiiHabilitationProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Postulación DGII')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _ErrorCard(onRetry: () {
          ref.invalidate(ecfDgiiHabilitationProvider);
        }),
        data: (view) => Column(
          children: [
            _StepsHeader(step: _step),
            if (_error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!),
              ),
            if (_saveStatus == _DataSaveStatus.saving ||
                _saveStatus == _DataSaveStatus.saved ||
                _saveStatus == _DataSaveStatus.error)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Icon(
                      switch (_saveStatus) {
                        _DataSaveStatus.saving => Icons.cloud_upload_outlined,
                        _DataSaveStatus.saved => Icons.cloud_done_outlined,
                        _ => Icons.cloud_off_outlined,
                      },
                      size: 16,
                      color: _saveStatus == _DataSaveStatus.error
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        switch (_saveStatus) {
                          _DataSaveStatus.saving => 'Guardando…',
                          _DataSaveStatus.saved => 'Guardado en el servidor',
                          _ => 'No se pudo guardar el borrador',
                        },
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: _saveStatus == _DataSaveStatus.error
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ),
                    if (_saveStatus == _DataSaveStatus.error)
                      TextButton(
                        onPressed: _autoSave,
                        child: const Text('Reintentar'),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: switch (_step) {
                0 => _ApplicationDataStep(
                    rnc: _rnc,
                    legalName: _legalName,
                    address: _address,
                    representativeName: _repName,
                    representativeId: _repId,
                    representativeEmail: _repEmail,
                    missing: _missingFields,
                  ),
                1 => _RequirementsStep(view: view),
                2 => _DocumentsStep(
                    view: view,
                    busy: _busy,
                    canWrite: _canWrite,
                    kind: _kind,
                    kinds: _documentKinds,
                    pickedName: _picked?.name,
                    onKind: (value) => setState(() => _kind = value),
                    onPick: _pickFile,
                    onUpload: _upload,
                    onDownload: _download,
                  ),
                _ => _SummaryStep(
                    view: view,
                    canWrite: _canWrite,
                    onSubmit: _submit,
                  ),
              },
            ),
            _BottomBar(
              step: _step,
              busy: _busy,
              onBack: _step == 0 ? null : () => setState(() => _step -= 1),
              onNext: _step == 3 ? null : _advance,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepsHeader extends StatelessWidget {
  const _StepsHeader({required this.step});

  final int step;

  static const _labels = ['Datos', 'Requisitos', 'Documentos', 'Enviar'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: List.generate(_labels.length, (index) {
          final active = index <= step;
          return Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 4,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: active ? scheme.primary : scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _labels[index],
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: active ? scheme.primary : scheme.onSurfaceVariant,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _ApplicationDataStep extends StatelessWidget {
  const _ApplicationDataStep({
    required this.rnc,
    required this.legalName,
    required this.address,
    required this.representativeName,
    required this.representativeId,
    required this.representativeEmail,
    required this.missing,
  });

  final TextEditingController rnc;
  final TextEditingController legalName;
  final TextEditingController address;
  final TextEditingController representativeName;
  final TextEditingController representativeId;
  final TextEditingController representativeEmail;
  final List<String> missing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Datos de la empresa', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: rnc,
          decoration: const InputDecoration(labelText: 'RNC'),
        ),
        TextField(
          controller: legalName,
          decoration: const InputDecoration(labelText: 'Razón social'),
        ),
        TextField(
          controller: address,
          decoration: const InputDecoration(labelText: 'Dirección fiscal'),
        ),
        const SizedBox(height: 16),
        Text('Representante legal', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: representativeName,
          decoration: const InputDecoration(labelText: 'Nombre completo'),
        ),
        TextField(
          controller: representativeId,
          decoration: const InputDecoration(labelText: 'Cédula o identificación'),
        ),
        TextField(
          controller: representativeEmail,
          decoration: const InputDecoration(labelText: 'Correo electrónico'),
        ),
        const SizedBox(height: 12),
        Text(
          'Se guarda como borrador en el servidor: puedes cerrar sesión y '
          'continuar después. No modifica tu configuración fiscal ni documentos '
          'emitidos.',
          style: theme.textTheme.bodySmall,
        ),
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Falta: ${missing.join(', ')}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

class _RequirementsStep extends StatelessWidget {
  const _RequirementsStep({required this.view});

  final EcfDgiiHabilitationView view;

  @override
  Widget build(BuildContext context) {
    final progress = view.progress;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LinearProgressIndicator(value: progress.percent / 100),
        const SizedBox(height: 8),
        Text(
          '${progress.resolvedCount} de ${progress.total} requisitos '
          '· ${progress.percent}%',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        for (final requirement in progress.requirements)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Icon(
                requirement.resolved
                    ? Icons.check_circle_outline
                    : Icons.radio_button_unchecked,
                color: requirement.resolved
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
              ),
              title: Text(requirement.label),
              subtitle: Wrap(
                spacing: 6,
                children: [
                  if (requirement.mandatory)
                    const Chip(
                      label: Text('Obligatorio'),
                      visualDensity: VisualDensity.compact,
                    ),
                  if (!requirement.automatable)
                    const Chip(
                      label: Text('Trámite externo'),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _DocumentsStep extends StatelessWidget {
  const _DocumentsStep({
    required this.view,
    required this.busy,
    required this.canWrite,
    required this.kind,
    required this.kinds,
    required this.pickedName,
    required this.onKind,
    required this.onPick,
    required this.onUpload,
    required this.onDownload,
  });

  final EcfDgiiHabilitationView view;
  final bool busy;
  final bool canWrite;
  final String kind;
  final Map<String, String> kinds;
  final String? pickedName;
  final ValueChanged<String> onKind;
  final VoidCallback onPick;
  final Future<void> Function() onUpload;
  final Future<void> Function(EcfDgiiEvidenceView) onDownload;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (canWrite)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: kind,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de documento',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final entry in kinds.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: busy ? null : (value) {
                      if (value != null) onKind(value);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          pickedName ?? 'Ningún archivo seleccionado',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: busy ? null : onPick,
                        icon: const Icon(Icons.attach_file),
                        label: const Text('Elegir'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: busy || pickedName == null ? null : onUpload,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Subir documento'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'PDF, PNG, JPG o XML · máximo 5 MB. El tipo se verifica '
                    'por el contenido del archivo.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          )
        else
          const Card(
            child: ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Solo lectura'),
              subtitle: Text(
                'Necesitas el permiso de gestión del expediente para adjuntar '
                'documentos.',
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text('Documentos del expediente',
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        if (view.evidence.isEmpty)
          const Text('Todavía no hay documentos cargados.')
        else
          for (final evidence in view.evidence)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: Text(evidence.fileName ?? evidence.kind),
              subtitle: Text(
                '${kinds[evidence.kind] ?? evidence.kind} · '
                '${evidence.reviewStatus}',
              ),
              trailing: IconButton(
                tooltip: 'Descargar',
                icon: const Icon(Icons.download_outlined),
                onPressed: busy ? null : () => onDownload(evidence),
              ),
            ),
      ],
    );
  }
}

class _SummaryStep extends StatelessWidget {
  const _SummaryStep({
    required this.view,
    required this.canWrite,
    required this.onSubmit,
  });

  final EcfDgiiHabilitationView view;
  final bool canWrite;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final progress = view.progress;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: Text('Estado: ${view.stateLabel}'),
            subtitle: Text(
              '${progress.resolvedCount}/${progress.total} requisitos · '
              '${view.evidence.length} documentos',
            ),
          ),
        ),
        if (progress.pendingMandatory.isNotEmpty)
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pendientes obligatorios',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  for (final key in progress.pendingMandatory)
                    Text('• $key'),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Enviar a revisión de Fulltech es un paso INTERNO. No equivale a una '
          'aprobación de la DGII ni habilita la emisión electrónica.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        if (canWrite)
          FilledButton.icon(
            onPressed: onSubmit,
            icon: const Icon(Icons.send_outlined),
            label: const Text('Enviar a revisión de Fulltech'),
          ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.step,
    required this.busy,
    required this.onBack,
    required this.onNext,
  });

  final int step;
  final bool busy;
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            if (onBack != null)
              TextButton(onPressed: busy ? null : onBack, child: const Text('Atrás')),
            const Spacer(),
            if (onNext != null)
              FilledButton(
                onPressed: busy ? null : onNext,
                child: const Text('Continuar'),
              ),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(left: 12),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('No se pudo cargar el expediente.'),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}
