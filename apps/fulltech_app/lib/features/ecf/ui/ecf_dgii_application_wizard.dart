import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/utils/app_feedback.dart';
import '../data/ecf_application_repository.dart';
import '../data/ecf_repository.dart';
import '../domain/ecf_fiscal_readiness.dart';
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
  const EcfDgiiApplicationWizard({
    super.key,
    this.embedded = false,
    this.onClose,
    this.onSubmitted,
  });

  final bool embedded;
  final VoidCallback? onClose;
  final VoidCallback? onSubmitted;

  @override
  ConsumerState<EcfDgiiApplicationWizard> createState() =>
      EcfDgiiApplicationWizardState();
}

class EcfDgiiApplicationWizardState
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
  bool _submitInProgress = false;
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
  late final Map<String, FocusNode> _fieldFocus;
  final Set<String> _visiblePending = {};
  int _editVersion = 0;
  List<String> _missingFields = const [];
  final Map<String, String> _conflicts = {};
  bool _reviewData = false;
  bool _reviewDocuments = false;
  bool _hasPersistedDraft = false;
  bool _loadingDraft = true;
  bool _draftLoadFailed = false;
  bool _applyingDraft = false;
  bool _draftEditable = true;

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
    _fieldFocus = {for (final path in _fieldLabels.keys) path: FocusNode()};
    for (final entry in _fieldFocus.entries) {
      entry.value.addListener(() {
        if (entry.value.hasFocus || !mounted) return;
        setState(() => _updatePendingVisibility(entry.key));
      });
    }
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
    for (final node in _fieldFocus.values) {
      node.dispose();
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
    if (_applyingDraft) return;
    _editVersion++;
    if (!_dirty) setState(() => _dirty = true);
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, _autoSave);
  }

  /// Guarda el borrador ahora y devuelve si quedó persistido.
  ///
  /// Las respuestas fuera de orden se descartan: si mientras se esperaba se
  /// lanzó otro guardado, esta respuesta ya no es la vigente.
  Future<bool> _autoSave() async {
    if (!_canWrite) return false;
    _debounce?.cancel();
    final attempt = ++_saveSequence;
    final editVersion = _editVersion;
    final payload = _payload();
    if (mounted) setState(() => _saveStatus = _DataSaveStatus.saving);
    try {
      final saved = await ref
          .read(ecfApplicationRepositoryProvider)
          .saveDraft(payload, expectedRevision: _draftRevision);
      if (attempt != _saveSequence) return false;
      if (!mounted) return false;
      setState(() {
        final editedSinceRequest = editVersion != _editVersion;
        _saveStatus = editedSinceRequest
            ? _DataSaveStatus.saving
            : _DataSaveStatus.saved;
        _dirty = editedSinceRequest;
        _hasPersistedDraft = true;
        _draftRevision = saved.draftRevision;
      });
      if (editVersion != _editVersion) {
        _debounce?.cancel();
        _debounce = Timer(_debounceDelay, _autoSave);
        return false;
      }
      return true;
    } catch (error) {
      if (attempt != _saveSequence) return false;
      if (!mounted) return false;
      if (error.toString().contains('ECF_DGII_DRAFT_CONFLICT')) {
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
      setState(() {
        if (!_dirty && !_fieldFocus.values.any((node) => node.hasFocus)) {
          _applyDraft(draft);
        }
        _draftRevision = draft.draftRevision;
        _draftEditable = _editableState(draft.state);
        _saveStatus = _dirty ? _DataSaveStatus.error : _DataSaveStatus.saved;
        _error = _dirty
            ? 'El borrador cambió en otro dispositivo. Tu edición sigue en pantalla; revisa y vuelve a guardar.'
            : 'El borrador se actualizó en otro dispositivo. Revisa los datos antes de continuar.';
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
    setState(() {
      _loadingDraft = true;
      _draftLoadFailed = false;
    });
    try {
      final draft = await ref.read(ecfApplicationRepositoryProvider).draft();
      if (!mounted) return;
      setState(() {
        _applyDraft(draft);
        _draftRevision = draft.draftRevision;
        _draftEditable = _editableState(draft.state);
        _loadingDraft = false;
        _error = null;
      });
    } catch (error) {
      // No se puede editar sin conocer la revisión vigente del servidor.
      if (!mounted) return;
      setState(() {
        _loadingDraft = false;
        _draftLoadFailed = true;
        _error = _messageFor(error);
      });
    }
  }

  static const _fieldLabels = <String, String>{
    'company.rnc': 'el RNC',
    'company.legalName': 'la razón social',
    'company.address': 'la dirección fiscal',
    'representative.fullName': 'el nombre del representante',
    'representative.identification': 'la cédula del representante',
    'representative.email': 'el correo electrónico del representante',
  };

  bool _editableState(String state) => const {
    'NOT_STARTED',
    'PREPARING_REQUIREMENTS',
    'REQUIRES_CORRECTION',
    'REJECTED',
  }.contains(state);

  Future<void> _close() async {
    if (_reviewDocuments) {
      setState(() => _reviewDocuments = false);
      return;
    }
    if (_dirty && _canWrite && !await _autoSave()) return;
    if (mounted) widget.onClose?.call();
  }

  Future<void> goBack() => _close();

  String _missingMessage(List<String> fields) {
    if (fields.length == 1) {
      return 'Necesitamos ${_fieldLabels[fields.single] ?? 'un dato obligatorio'} para continuar.';
    }
    return 'Necesitamos completar: ${fields.map((key) => _fieldLabels[key] ?? 'un dato obligatorio').join(', ')}.';
  }

  void _applyDraft(EcfApplicationDraft draft) {
    const paths = [
      'company.rnc',
      'company.legalName',
      'company.address',
      'representative.fullName',
      'representative.identification',
      'representative.email',
    ];
    _applyingDraft = true;
    _debounce?.cancel();
    _conflicts.clear();
    for (var i = 0; i < paths.length; i++) {
      final path = paths[i];
      final parts = path.split('.');
      final group = draft.suggested[parts.first];
      final suggested = group is Map
          ? (group[parts.last] as String?)?.trim() ?? ''
          : '';
      final saved = draft.read(path)?.trim() ?? '';
      _controllers[i].text = saved.isNotEmpty ? saved : suggested;
      if (saved.isNotEmpty && suggested.isNotEmpty && saved != suggested) {
        _conflicts[path] = suggested;
      }
    }
    _missingFields = _incompleteFields();
    _visiblePending
      ..clear()
      ..addAll(_missingFields);
    _dirty = false;
    _hasPersistedDraft = draft.draft != null;
    _reviewDocuments = false;
    _saveStatus = _DataSaveStatus.idle;
    _applyingDraft = false;
  }

  List<String> _incompleteFields() {
    final email = _repEmail.text.trim();
    return [
      if (!isEcfTaxIdValid(_rnc.text)) 'company.rnc',
      if (_legalName.text.trim().isEmpty) 'company.legalName',
      if (_address.text.trim().isEmpty) 'company.address',
      if (_repName.text.trim().isEmpty) 'representative.fullName',
      if (!isEcfCedulaValid(_repId.text)) 'representative.identification',
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email))
        'representative.email',
    ];
  }

  void _updatePendingVisibility(String path) {
    _missingFields = _incompleteFields();
    if (_missingFields.contains(path)) {
      _visiblePending.add(path);
    } else {
      _visiblePending.remove(path);
    }
  }

  List<String> get _fieldsToShow => _reviewData
      ? _fieldLabels.keys.toList()
      : _fieldLabels.keys
            .where(
              (path) =>
                  _visiblePending.contains(path) || _fieldFocus[path]!.hasFocus,
            )
            .toList();

  /// Guarda el borrador y deja el asistente en el paso de requisitos.
  Future<void> _advance() async {
    if (_step != 0) {
      setState(() => _step += 1);
      return;
    }
    if (_conflicts.isNotEmpty) {
      setState(() => _error = 'Revisa las diferencias antes de continuar.');
      return;
    }
    if (!_canWrite) {
      setState(
        () => _error = 'No tienes permiso para gestionar el expediente.',
      );
      return;
    }
    final incomplete = _incompleteFields();
    if (incomplete.isNotEmpty) {
      setState(() {
        _missingFields = incomplete;
        _visiblePending.addAll(incomplete);
        _error = _missingMessage(incomplete);
      });
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
    // Aviso flotante, no barra inferior: confirma el guardado sin tapar el
    // formulario ni mover el foco del campo que se está editando.
    AppFeedback.showToast(
      context,
      title: 'Borrador guardado',
      body: 'Tus datos quedaron guardados en el servidor.',
      kind: AppFeedbackKind.success,
      dedupeKey: 'ecf_draft_saved',
    );
  }

  bool get _canWrite {
    final user = ref.watch(authStateProvider).user;
    return !_loadingDraft &&
        !_draftLoadFailed &&
        _draftEditable &&
        hasUserPermission(user, AppPermission.manageEcfOnboarding);
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
      return _missingFields.isEmpty
          ? 'Revisa los datos del expediente antes de continuar.'
          : _missingMessage(_missingFields);
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
    final file = (result == null || result.files.isEmpty)
        ? null
        : result.files.first;
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
      await ref
          .read(ecfRepositoryProvider)
          .uploadDgiiDocument(kind: _kind, bytes: bytes, fileName: file.name);
      if (!mounted) return;
      setState(() => _picked = null);
      AppFeedback.showToast(
        context,
        title: 'Documento añadido',
        body: 'El documento quedó adjunto al expediente.',
        kind: AppFeedbackKind.success,
        dedupeKey: 'ecf_document_added',
      );
    });
  }

  Future<void> _download(EcfDgiiEvidenceView evidence) async {
    await _run(() async {
      final bytes = await ref
          .read(ecfRepositoryProvider)
          .downloadDgiiDocument(evidence.id);
      final path = await _saver.save(
        fileName: evidence.fileName ?? 'documento',
        bytes: bytes,
      );
      if (!mounted) return;
      AppFeedback.showToast(
        context,
        title: 'Documento guardado',
        body: 'Se guardó en $path.',
        kind: AppFeedbackKind.info,
        dedupeKey: 'ecf_document_downloaded',
      );
    });
  }

  Future<void> _submit() async {
    if (!_canWrite || _submitInProgress) return;
    _submitInProgress = true;
    // El overlay raíz se resuelve AHORA: tras el envío el asistente puede
    // cerrarse, y el aviso debe seguir siendo visible después.
    final rootOverlay = Navigator.of(context, rootNavigator: true).overlay;
    try {
      final incomplete = _incompleteFields();
      if (incomplete.isNotEmpty) {
        setState(() {
          _missingFields = incomplete;
          _visiblePending.addAll(incomplete);
          _error = _missingMessage(incomplete);
          _step = 0;
        });
        return;
      }
      // Nunca se envía con cambios locales sin persistir: el snapshot guardaría
      // datos distintos de los que el usuario está viendo.
      if (_dirty || _saveStatus != _DataSaveStatus.saved) {
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
          _visiblePending.addAll(draft.missingFields);
          _error = _missingMessage(draft.missingFields);
          _step = 0;
        });
        return;
      }

      if (!mounted) return;
      final accepted = await _confirmConsent(draft);
      if (accepted != true) return;

      await _run(() async {
        // El servidor crea una versión INMUTABLE con los datos y los hashes de los
        // documentos. No autoriza nada ante la DGII.
        final result = await ref
            .read(ecfApplicationRepositoryProvider)
            .submit(
              consentVersion: draft.requiredConsentVersion,
              payload: _payload(),
            );
        ref.invalidate(ecfApplicationDraftProvider);
        if (!mounted) return;
        if (widget.embedded) {
          (widget.onSubmitted ?? widget.onClose)?.call();
        } else {
          Navigator.of(context).pop();
        }
        AppFeedback.showToastOnOverlay(
          rootOverlay,
          title: 'Expediente guardado',
          body: result.idempotent
              ? 'Ya estaba en revisión interna (versión ${result.version}). No se duplicó el envío.'
              : 'Tu solicitud quedó registrada para revisión interna. Versión ${result.version}.',
          kind: AppFeedbackKind.success,
          dedupeKey: 'ecf_application_submitted_${result.version}',
        );
      });
    } finally {
      _submitInProgress = false;
    }
  }

  Future<void> _continueToDocuments() async {
    final incomplete = _incompleteFields();
    if (incomplete.isNotEmpty) {
      setState(() {
        _missingFields = incomplete;
        _visiblePending.addAll(incomplete);
        _error = _missingMessage(incomplete);
      });
      return;
    }
    if (_conflicts.isNotEmpty || !_canWrite) return;
    if (_dirty || !_hasPersistedDraft) {
      if (!await _autoSave()) return;
    }
    if (mounted) setState(() => _reviewDocuments = true);
  }

  Future<bool?> _confirmConsent(EcfApplicationDraft draft) {
    var accepted = false;
    // El texto lo manda el servidor: se muestra EXACTAMENTE lo que se versiona
    // y se registra al aceptar. La interfaz no redacta ni resume el
    // consentimiento; si el servidor cambia el texto, aquí se ve el nuevo.
    final blocks = draft.consentPurpose
        .split('\n\n')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    final noteIndex = blocks.indexWhere(_isClosingNote);
    final body = noteIndex <= 0 ? blocks : blocks.sublist(0, noteIndex);
    final note = noteIndex <= 0 ? null : blocks.sublist(noteIndex).join('\n\n');

    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final media = MediaQuery.of(context);
          final theme = Theme.of(context);
          final narrow = media.size.width < 520;
          final horizontal = narrow ? 16.0 : 20.0;
          // Alto según el CONTENIDO con un máximo sensato: el texto hace scroll
          // y la casilla y los botones nunca salen de la pantalla. Antes había
          // una altura fija de 600-680 px, que dejaba medio diálogo vacío.
          final maxHeight = (media.size.height - media.padding.vertical - 64)
              .clamp(240.0, 560.0);
          return Dialog(
            insetPadding: EdgeInsets.symmetric(
              horizontal: narrow ? 12 : 40,
              vertical: 24,
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              key: const ValueKey('ecf_consent_dialog_box'),
              constraints: BoxConstraints(maxWidth: 560, maxHeight: maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      16,
                      horizontal,
                      10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Autorización y consentimiento para revisión interna',
                          style: narrow
                              ? theme.textTheme.titleMedium
                              : theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Lee y acepta las condiciones para continuar con la revisión de tu expediente.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        12,
                        horizontal,
                        12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < body.length; i++) ...[
                            Text(
                              body[i],
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.45,
                              ),
                            ),
                            if (i < body.length - 1) const SizedBox(height: 12),
                          ],
                          if (note != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              note,
                              style: theme.textTheme.bodySmall?.copyWith(
                                height: 1.4,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            'Versión del texto: ${draft.requiredConsentVersion}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      narrow ? 6 : 10,
                      4,
                      horizontal,
                      0,
                    ),
                    // Toda la fila es pulsable: la casilla sola es un objetivo
                    // pequeño en móvil.
                    child: InkWell(
                      onTap: () => setDialogState(() => accepted = !accepted),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Checkbox(
                              value: accepted,
                              onChanged: (value) => setDialogState(
                                () => accepted = value ?? false,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'He leído y acepto esta autorización para la revisión interna de mi expediente',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontal,
                      2,
                      horizontal,
                      narrow ? 8 : 14,
                    ),
                    child: narrow
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FilledButton(
                                onPressed: accepted
                                    ? () => Navigator.of(context).pop(true)
                                    : null,
                                child: const Text(
                                  'Autorizo y envío a revisión interna',
                                ),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('Cancelar'),
                              ),
                            ],
                          )
                        : Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: accepted
                                    ? () => Navigator.of(context).pop(true)
                                    : null,
                                child: const Text(
                                  'Autorizo y envío a revisión interna',
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// La nota final del servidor se resalta aparte del cuerpo del consentimiento.
  ///
  /// Si el servidor cambia la redacción, la nota simplemente pasa a leerse como
  /// un párrafo más: nada se oculta ni se reescribe aquí.
  static bool _isClosingNote(String part) =>
      part.startsWith('Esta aceptación autoriza únicamente');

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(ecfDgiiHabilitationProvider);
    if (widget.embedded) {
      return async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _ErrorCard(
          onRetry: () => ref.invalidate(ecfDgiiHabilitationProvider),
        ),
        data: _embeddedBody,
      );
    }
    final body = async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _ErrorCard(
        onRetry: () {
          ref.invalidate(ecfDgiiHabilitationProvider);
        },
      ),
      data: (view) => _draftLoadFailed
          ? _loadFailureBody()
          : Column(
              children: [
                if (!widget.embedded) _StepsHeader(step: _step),
                if (_loadingDraft) const LinearProgressIndicator(),
                if (widget.embedded && widget.onClose != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _close,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Volver a la guía'),
                    ),
                  ),
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
                            _DataSaveStatus.saving =>
                              Icons.cloud_upload_outlined,
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
                              _DataSaveStatus.saved =>
                                'Guardado en el servidor',
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
                      visible: _fieldsToShow,
                      focusNodes: _fieldFocus,
                      conflicts: _conflicts,
                      review: _reviewData,
                      canWrite: _canWrite,
                      onReview: () =>
                          setState(() => _reviewData = !_reviewData),
                      onResolve: (path, useSuggested) {
                        final paths = _fieldLabels.keys.toList();
                        final index = paths.indexOf(path);
                        if (index < 0) return;
                        setState(() {
                          if (useSuggested) {
                            _controllers[index].text = _conflicts[path]!;
                          }
                          _conflicts.remove(path);
                        });
                      },
                    ),
                    1 => _RequirementsStep(
                      view: view,
                      showProgress: !widget.embedded,
                    ),
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
                  canWrite: _canWrite && !_loadingDraft && _conflicts.isEmpty,
                  onBack: _step == 0 ? null : () => setState(() => _step -= 1),
                  onNext: _step == 3 ? null : _advance,
                ),
              ],
            ),
    );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('Postulación DGII')),
      body: body,
    );
  }

  Widget _embeddedBody(EcfDgiiHabilitationView view) {
    if (_draftLoadFailed) return _loadFailureBody();
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        if (_loadingDraft) const LinearProgressIndicator(),
        if (widget.onClose != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _close,
              child: Text(
                _reviewDocuments
                    ? 'Volver a los datos del expediente'
                    : 'Volver a los datos fiscales',
              ),
            ),
          ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_saveStatus == _DataSaveStatus.saving)
          const Text('Guardando…')
        else if (_saveStatus == _DataSaveStatus.saved)
          const Text('Guardado en el servidor')
        else if (_saveStatus == _DataSaveStatus.error)
          TextButton(
            onPressed: _autoSave,
            child: const Text('Reintentar guardado'),
          ),
        _ApplicationDataStep(
          rnc: _rnc,
          legalName: _legalName,
          address: _address,
          representativeName: _repName,
          representativeId: _repId,
          representativeEmail: _repEmail,
          missing: _missingFields,
          visible: _fieldsToShow,
          focusNodes: _fieldFocus,
          conflicts: _conflicts,
          review: _reviewData,
          canWrite: _canWrite,
          embedded: true,
          onReview: () => setState(() => _reviewData = !_reviewData),
          onResolve: (path, useSuggested) {
            final index = _fieldLabels.keys.toList().indexOf(path);
            if (index < 0) return;
            setState(() {
              if (useSuggested) _controllers[index].text = _conflicts[path]!;
              _conflicts.remove(path);
            });
          },
        ),
        if (_reviewDocuments &&
            _missingFields.isEmpty &&
            _conflicts.isEmpty) ...[
          _DocumentsStep(
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
            embedded: true,
          ),
          const SizedBox(height: 8),
          const Text(
            'La revisión interna no acredita presentación ni autorización oficial ante la DGII.',
          ),
        ],
        if (_canWrite && !_loadingDraft)
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: _busy || _conflicts.isNotEmpty
                  ? null
                  : _reviewDocuments
                  ? _submit
                  : _missingFields.isEmpty
                  ? _continueToDocuments
                  : _autoSave,
              child: Text(
                _reviewDocuments
                    ? 'Enviar a revisión interna'
                    : _missingFields.isEmpty
                    ? 'Continuar'
                    : _missingFields.length == 1 &&
                          _missingFields.single == 'representative.email'
                    ? 'Guardar correo'
                    : 'Guardar datos',
              ),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _loadFailureBody() => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error ?? 'No se pudo recuperar el expediente.'),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _loadDraft,
            child: const Text('Reintentar carga'),
          ),
        ],
      ),
    ),
  );
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
    required this.visible,
    required this.focusNodes,
    required this.conflicts,
    required this.review,
    required this.canWrite,
    required this.onReview,
    required this.onResolve,
    this.embedded = false,
  });

  final TextEditingController rnc;
  final TextEditingController legalName;
  final TextEditingController address;
  final TextEditingController representativeName;
  final TextEditingController representativeId;
  final TextEditingController representativeEmail;
  final List<String> missing;
  final List<String> visible;
  final Map<String, FocusNode> focusNodes;
  final Map<String, String> conflicts;
  final bool review;
  final bool canWrite;
  final VoidCallback onReview;
  final void Function(String, bool) onResolve;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controllers = <String, TextEditingController>{
      'company.rnc': rnc,
      'company.legalName': legalName,
      'company.address': address,
      'representative.fullName': representativeName,
      'representative.identification': representativeId,
      'representative.email': representativeEmail,
    };
    final labels = <String, String>{
      'company.rnc': 'RNC',
      'company.legalName': 'Razón social',
      'company.address': 'Dirección fiscal',
      'representative.fullName': 'Nombre del representante',
      'representative.identification': 'Cédula o identificación',
      'representative.email': 'Correo electrónico',
    };
    return ListView(
      shrinkWrap: embedded,
      physics: embedded ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          conflicts.isNotEmpty
              ? 'Revisa las diferencias antes de continuar.'
              : missing.isEmpty
              ? 'Los datos de tu empresa están registrados. Puedes continuar.'
              : 'Completa o corrige los datos necesarios para continuar.',
          style: theme.textTheme.titleSmall,
        ),
        if (!review &&
            visible.length == 1 &&
            visible.single == 'representative.email')
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Necesitamos el correo electrónico del representante para continuar.',
            ),
          ),
        TextButton(
          onPressed: onReview,
          child: Text(review ? 'Ocultar datos' : 'Revisar datos'),
        ),
        for (final entry in conflicts.entries) ...[
          Text(
            'Hay una diferencia en ${labels[entry.key]}.',
            style: theme.textTheme.bodyMedium,
          ),
          Text('Expediente: ${controllers[entry.key]!.text}'),
          Text('Datos fiscales: ${entry.value}'),
          Wrap(
            children: [
              TextButton(
                onPressed: canWrite ? () => onResolve(entry.key, false) : null,
                child: const Text('Conservar expediente'),
              ),
              TextButton(
                onPressed: canWrite ? () => onResolve(entry.key, true) : null,
                child: const Text('Usar datos fiscales'),
              ),
            ],
          ),
        ],
        for (final key in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: controllers[key],
              focusNode: focusNodes[key],
              key: ValueKey('application_field_$key'),
              readOnly: !canWrite,
              decoration: InputDecoration(labelText: labels[key]),
            ),
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
            'Datos por completar o corregir: ${missing.map((key) => labels[key] ?? 'Dato obligatorio').join(', ')}',
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
  const _RequirementsStep({required this.view, required this.showProgress});

  final EcfDgiiHabilitationView view;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final progress = view.progress;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (showProgress) ...[
          LinearProgressIndicator(value: progress.percent / 100),
          const SizedBox(height: 8),
          Text(
            '${progress.resolvedCount} de ${progress.total} requisitos '
            '· ${progress.percent}%',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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
    this.embedded = false,
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
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: embedded,
      physics: embedded ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'En esta etapa no hay un documento obligatorio definido para el expediente. '
              'Si recibes una constancia de presentación de la DGII, podrás registrar '
              'su referencia después de enviar la solicitud a revisión interna. '
              'Ese registro no acredita autorización para emitir.',
            ),
          ),
        ),
        if (view.state == 'REQUIRES_CORRECTION' && canWrite)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
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
                    onChanged: busy
                        ? null
                        : (value) {
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
                  OutlinedButton.icon(
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
          ),
        const SizedBox(height: 16),
        Text(
          'Documentos del expediente',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        if (view.evidence.isEmpty)
          const Text('Todavía no hay documentos cargados.')
        else
          for (final evidence in view.evidence)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.description_outlined),
              title: Text(
                evidence.fileName ??
                    kinds[evidence.kind] ??
                    'Documento del expediente',
              ),
              subtitle: Text(
                '${kinds[evidence.kind] ?? 'Documento del expediente'} · '
                '${evidence.reviewStatusLabel}',
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
                  Text(
                    'Pendientes obligatorios',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  for (final key in progress.pendingMandatory)
                    Text(
                      '• ${progress.requirements.where((item) => item.key == key).map((item) => item.label).firstOrNull ?? 'Requisito pendiente'}',
                    ),
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
    required this.canWrite,
    required this.onBack,
    required this.onNext,
  });

  final int step;
  final bool busy;
  final bool canWrite;
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
              TextButton(
                onPressed: busy ? null : onBack,
                child: const Text('Atrás'),
              ),
            const Spacer(),
            if (onNext != null)
              FilledButton(
                onPressed: busy || !canWrite ? null : onNext,
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
