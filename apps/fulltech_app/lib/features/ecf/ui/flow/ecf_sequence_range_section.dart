import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/ecf_repository.dart';
import '../../ecf_authorized_sequence_models.dart';
import '../../ecf_models.dart';
import 'ecf_flow_kit.dart';

/// Declaración de la numeración que la **DGII** autorizó a la empresa.
///
/// Por qué existe
/// -------------
/// Ningún sistema puede leer la autorización de la DGII: el cliente la ve en la
/// Oficina Virtual y la transcribe. Este formulario convierte esa transcripción
/// en un control real: el backend exige una declaración explícita, guarda quién
/// la firmó y la versión del texto, y rechaza cualquier rango que se salga de lo
/// autorizado.
///
/// Decisiones de diseño
/// --------------------
/// * **Un solo sitio.** La autorización y el rango se declaran juntos: el cliente
///   no tiene que entrar en dos pantallas para el mismo dato.
/// * **Nada se prellena** con lo que dijo el proveedor. El dato de la DGII manda.
/// * **Fail-closed en la interfaz**: no se puede guardar sin marcar la
///   declaración, y el rango se valida contra la cantidad aprobada antes de
///   enviar. El servidor lo vuelve a validar igualmente.
/// * **Se oculta sola** cuando ya hay numeración usable y declarada: no se pide
///   dos veces el mismo dato, pero queda un resumen legible de lo declarado.
class EcfSequenceRangeSection extends ConsumerStatefulWidget {
  const EcfSequenceRangeSection({super.key, required this.canManage});

  /// Mismo permiso que exige el backend (`manageEcfSequences`).
  final bool canManage;

  @override
  ConsumerState<EcfSequenceRangeSection> createState() =>
      _EcfSequenceRangeSectionState();
}

class _EcfSequenceRangeSectionState
    extends ConsumerState<EcfSequenceRangeSection> {
  final _authorization = TextEditingController();
  final _from = TextEditingController();
  final _to = TextEditingController();
  final _approved = TextEditingController();
  final _expires = TextEditingController();

  EcfAuthorizedSequencesView _authorized = EcfAuthorizedSequencesView.empty;
  List<EcfSequenceInfo> _sequences = const [];
  String? _selectedType;
  bool _declarationAccepted = false;
  bool _showAnotherType = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    if (widget.canManage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _authorization.dispose();
    _from.dispose();
    _to.dispose();
    _approved.dispose();
    _expires.dispose();
    super.dispose();
  }

  /// Tipos soportados que todavía no tienen autorización declarada.
  List<String> get _pendingTypes => _authorized.supportedTypes
      .where((type) => _authorized.forType(type) == null)
      .toList(growable: false);

  /// ¿Ya hay un rango activo y usable para el tipo? Debe tener números libres y
  /// no estar vencido: un rango agotado o vencido no permite emitir.
  bool _hasUsableRange(String type) {
    final now = DateTime.now();
    return _sequences.any(
      (sequence) =>
          sequence.active &&
          sequence.documentType == type &&
          sequence.remaining > 0 &&
          (sequence.validUntil == null || sequence.validUntil!.isAfter(now)),
    );
  }

  /// Rango activo del tipo, aunque esté agotado o vencido. Sirve para renovar
  /// desde el número ya consumido y no reutilizar uno entregado.
  EcfSequenceInfo? _activeSequenceFor(String type) {
    EcfSequenceInfo? found;
    for (final sequence in _sequences) {
      if (!sequence.active || sequence.documentType != type) continue;
      if (found == null || sequence.endNumber > found.endNumber) {
        found = sequence;
      }
    }
    return found;
  }

  /// Tipos declarados a los que les falta la numeración (sin rango, agotada o
  /// vencida). Sin esto la empresa no puede emitir ese tipo de comprobante y la
  /// pantalla antes solo lo mostraba en gris, sin ninguna forma de arreglarlo.
  List<String> get _typesMissingSequence {
    final missing = <String>[];
    for (final item in _authorized.items) {
      if (!_hasUsableRange(item.documentType)) {
        missing.add(item.documentType);
      }
    }
    return missing;
  }

  /// Registra o renueva el rango del tipo con los números que la DGII autorizó.
  Future<void> _syncRange(String type) async {
    if (_saving) return;
    final authorization = _authorized.forType(type);
    if (authorization == null) return;
    final current = _activeSequenceFor(type);
    final renew = current != null;
    final start =
        current == null || current.nextNumber <= authorization.rangeFrom
        ? authorization.rangeFrom
        : current.nextNumber;
    if (start > authorization.rangeTo) {
      setState(() {
        _error =
            'La autorización de la DGII para ${_typeLabel(type)} ya está '
            'agotada. Registra la nueva autorización que te dio la DGII.';
        _success = null;
        _showAnotherType = true;
        _selectedType = type;
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      final repository = ref.read(ecfRepositoryProvider);
      if (renew) {
        await repository.renewSequence(
          expectedEnvironment: _authorized.environment,
          documentType: type,
          startNumber: start,
          endNumber: authorization.rangeTo,
        );
      } else {
        await repository.registerSequence(
          expectedEnvironment: _authorized.environment,
          documentType: type,
          startNumber: start,
          endNumber: authorization.rangeTo,
        );
      }
      if (!mounted) return;
      setState(() {
        _success = renew
            ? 'Numeración renovada para ${_typeLabel(type)}.'
            : 'Numeración registrada para ${_typeLabel(type)}.';
      });
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _describeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final authorized = await ref
          .read(ecfRepositoryProvider)
          .authorizedSequences();
      final sequences = await ref.read(ecfRepositoryProvider).sequences();
      if (!mounted) return;
      setState(() {
        _authorized = authorized;
        _sequences = sequences;
        final pending = _pendingTypes;
        if (_selectedType == null ||
            !_authorized.supportedTypes.contains(_selectedType)) {
          _selectedType = pending.isNotEmpty
              ? pending.first
              : _authorized.supportedTypes.isEmpty
              ? null
              : _authorized.supportedTypes.first;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo consultar la numeración autorizada.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving || _selectedType == null) return;

    final authorizationNumber = _authorization.text.trim();
    final from = int.tryParse(_from.text.trim());
    final to = int.tryParse(_to.text.trim());
    final approved = int.tryParse(_approved.text.trim());

    if (authorizationNumber.length < 4) {
      setState(() => _error = _authorizationError);
      return;
    }
    if (from == null || to == null || from < 1 || to < from) {
      setState(() => _error = _rangeError);
      return;
    }
    if (approved == null || approved < 1) {
      setState(() => _error = _quantityError);
      return;
    }
    if (to - from + 1 != approved) {
      setState(
        () => _error =
            'La DGII aprobó $approved comprobantes y el rango declara '
            '${to - from + 1}. Corrige los números o la cantidad aprobada.',
      );
      return;
    }
    if (!_declarationAccepted) {
      setState(() => _error = 'Debes aceptar la declaración para guardar.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      final repository = ref.read(ecfRepositoryProvider);
      // 1) La autorización primero: es la fuente de verdad del rango.
      await repository.declareAuthorizedSequence(
        expectedEnvironment: _authorized.environment,
        documentType: _selectedType!,
        authorizationNumber: authorizationNumber,
        rangeFrom: from,
        rangeTo: to,
        approvedQuantity: approved,
        expiresAt: _normalizeExpiry(_expires.text),
        declarationAccepted: true,
      );
      // 2) El rango de numeración, que el backend valida contra lo declarado.
      // Si el tipo ya tenía rango activo, este es un cambio de autorización
      // (la DGII dio otro cupo): se renueva en lugar de registrar, porque
      // `register` rechazaría el tipo con `ECF_SEQUENCE_ALREADY_EXISTS`.
      if (_activeSequenceFor(_selectedType!) != null) {
        await repository.renewSequence(
          expectedEnvironment: _authorized.environment,
          documentType: _selectedType!,
          startNumber: from,
          endNumber: to,
        );
      } else {
        await repository.registerSequence(
          expectedEnvironment: _authorized.environment,
          documentType: _selectedType!,
          startNumber: from,
          endNumber: to,
        );
      }
      if (!mounted) return;
      _authorization.clear();
      _from.clear();
      _to.clear();
      _approved.clear();
      _expires.clear();
      setState(() {
        _declarationAccepted = false;
        _showAnotherType = false;
        _success = 'Numeración declarada.';
      });
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _describeError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String get _authorizationError =>
      'Escribe el número de autorización tal como aparece en la Oficina '
      'Virtual de la DGII.';

  String get _rangeError =>
      'El número final no puede ser menor que el inicial.';

  String get _quantityError => 'La cantidad aprobada debe ser mayor que cero.';

  /// Acepta `31/12/2027` o una fecha ISO. Vacío = sin vencimiento (N/A).
  ///
  /// La fecha se envía como **fin del día** (23:59:59.999Z): la DGII autoriza
  /// hasta el último día inclusive, y mandarla a medianoche bloquearía la
  /// emisión precisamente ese día.
  String? _normalizeExpiry(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final parts = text.split(RegExp(r'[/\-.]'));
    if (parts.length == 3 && parts[0].length <= 2) {
      final day = parts[0].padLeft(2, '0');
      final month = parts[1].padLeft(2, '0');
      return '${parts[2]}-$month-${day}T23:59:59.999Z';
    }
    return text;
  }

  /// Traduce los códigos del backend a algo que el cliente pueda corregir.
  String _describeError(Object error) {
    final text = error.toString();
    final backendMessage = _messageAfterCode(text);
    if (text.contains('ECF_DGII_SEQUENCE_QUANTITY_MISMATCH')) {
      return backendMessage ?? _quantityError;
    }
    if (text.contains('ECF_SEQUENCE_EXCEEDS_AUTHORIZED')) {
      return backendMessage ?? 'El rango se sale de lo autorizado por la DGII.';
    }
    if (text.contains('ECF_SEQUENCE_NOT_AUTHORIZED')) {
      return 'Falta declarar la numeración autorizada por la DGII.';
    }
    if (text.contains('ECF_DGII_SEQUENCE_EXPIRED')) {
      return backendMessage ?? 'La autorización de la DGII está vencida.';
    }
    if (text.contains('ECF_SEQUENCE_ALREADY_EXISTS')) {
      return 'Ya tienes una numeración activa para ese tipo de comprobante.';
    }
    if (text.contains('ECF_SEQUENCE_REUSE_BLOCKED')) {
      return 'No puedes empezar por debajo de un número que ya usaste.';
    }
    if (text.contains('ECF_DGII_SEQUENCE_AUTHORIZATION_REQUIRED')) {
      return _authorizationError;
    }
    // El repositorio ya entrega el motivo del servidor sin envoltorio técnico;
    // mostrarlo evita el «Inténtalo de nuevo» que no dice nada.
    final trimmed = text.trim();
    final isTechnical =
        trimmed.isEmpty ||
        trimmed.startsWith('DioException') ||
        trimmed.startsWith('Exception') ||
        trimmed.startsWith('SocketException');
    return isTechnical
        ? 'No se pudo guardar la numeración. Inténtalo de nuevo.'
        : trimmed;
  }

  /// El backend envía `CODIGO: mensaje legible`; se muestra la parte legible.
  String? _messageAfterCode(String text) {
    final match = RegExp(r'ECF_[A-Z_]+:\s*(.+)').firstMatch(text);
    return match?.group(1)?.trim();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(ecfCapabilitiesProvider.select((state) => state.valueOrNull?.environment), (previous, next) {
      if (previous != null && next != null && previous != next && widget.canManage && mounted) {
        _authorization.clear(); _from.clear(); _to.clear(); _approved.clear(); _expires.clear();
        _selectedType = null; _declarationAccepted = false; _showAnotherType = false;
        _load();
      }
    });
    if (!widget.canManage || _loading) return const SizedBox.shrink();
    if (_authorized.supportedTypes.isEmpty) return const SizedBox.shrink();

    final pending = _pendingTypes;
    final declared = _authorized.items;

    // Con algo ya declarado se muestra el resumen: no se le pide al cliente un
    // tipo que quizá no use. Declarar otro tipo es una acción explícita.
    if (declared.isNotEmpty && !_showAnotherType) {
      return EcfSection(
        title: _authorized.environment == 'SANDBOX'
            ? 'Numeración de pruebas (TEST)'
            : 'Numeración autorizada por la DGII',
        subtitle:
            'Ya está declarada. Declara otro tipo si la DGII te autorizó '
            'más de uno.',
        icon: Icons.verified_outlined,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in declared) _declaredSummary(item),
            for (final type in _typesMissingSequence) _missingSequenceRow(type),
            if (_success != null) ...[
              const SizedBox(height: 8),
              EcfInlineNote(tone: EcfTone.done, text: _success!),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              EcfInlineNote(tone: EcfTone.warning, text: _error!),
            ],
            if (pending.isNotEmpty) ...[
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('ecf_dgii_declare_another'),
                  onPressed: () => setState(() {
                    _showAnotherType = true;
                    _selectedType = pending.first;
                    _error = null;
                    _success = null;
                  }),
                  icon: const Icon(Icons.add, size: 16),
                  label: Text('Declarar ${_typeLabel(pending.first)}'),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return EcfSection(
      title: _authorized.environment == 'SANDBOX'
          ? 'Numeración de pruebas (TEST)'
          : 'Numeración autorizada por la DGII',
      subtitle: _authorized.environment == 'SANDBOX'
          ? 'Registra solo rangos y vencimientos confirmados para TEST. '
                'No se comparten con producción.'
          : 'Transcribe los datos tal como aparecen en la Oficina Virtual '
                'de la DGII. Sin esta información no se puede emitir.',
      icon: Icons.verified_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_selectedType == null)
            const SizedBox.shrink()
          else ...[
            if (_authorized.supportedTypes.length > 1) ...[
              _typeSelector(),
              const SizedBox(height: 10),
            ],
            _label(
              _authorized.environment == 'SANDBOX'
                  ? 'Referencia de autorización TEST'
                  : 'N.º de autorización',
            ),
            TextField(
              key: const ValueKey('ecf_dgii_authorization_number'),
              controller: _authorization,
              textCapitalization: TextCapitalization.characters,
              decoration: _decoration(
                _authorized.environment == 'SANDBOX'
                    ? 'Referencia confirmada por el proveedor'
                    : 'Como aparece en la DGII',
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _numericField('Desde', _from, 'ecf_dgii_from')),
                const SizedBox(width: 10),
                Expanded(child: _numericField('Hasta', _to, 'ecf_dgii_to')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _numericField(
                    'Cantidad aprobada',
                    _approved,
                    'ecf_dgii_approved',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _textField(
                    'Vence',
                    _expires,
                    '31/12/2027',
                    'ecf_dgii_expires',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _authorized.environment == 'SANDBOX'
                  ? 'Escribe solo los números: el prefijo lo agrega el sistema. Usa el vencimiento confirmado para TEST; si no aplica, deja «Vence» vacío.'
                  : 'Escribe solo los números: el prefijo lo agrega el sistema. Si la DGII muestra «N/A», deja «Vence» vacío.',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 14),
            _declaration(),
            if (_success != null) ...[
              const SizedBox(height: 10),
              EcfInlineNote(tone: EcfTone.done, text: _success!),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              EcfInlineNote(tone: EcfTone.warning, text: _error!),
            ],
            const SizedBox(height: 12),
            EcfPrimaryAction(
              label: 'Guardar declaración y numeración',
              icon: Icons.save_outlined,
              busy: _saving,
              onPressed: _saving || !_declarationAccepted ? null : _save,
              buttonKey: const ValueKey('ecf_dgii_declaration_save'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _typeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('Tipo de comprobante'),
        DropdownButtonFormField<String>(
          isExpanded: true,
          key: const ValueKey('ecf_dgii_type'),
          initialValue: _selectedType,
          isDense: true,
          decoration: _decoration(null),
          items: [
            for (final type in _authorized.supportedTypes)
              DropdownMenuItem(
                value: type,
                child: Text(
                  _typeLabel(type),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: _saving
              ? null
              : (value) => setState(() {
                  _selectedType = value;
                  _error = null;
                  _success = null;
                }),
        ),
      ],
    );
  }

  /// La declaración es el acto del cliente: se presenta como un bloque propio
  /// separado por una línea, **no** como una tarjeta dentro de la tarjeta. El
  /// kit del módulo prohíbe anidar superficies: eso es exactamente el ruido que
  /// el recorrido debe evitar.
  Widget _declaration() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1, color: AppColors.border),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              key: const ValueKey('ecf_dgii_declaration_check'),
              value: _declarationAccepted,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: _saving
                  ? null
                  : (value) => setState(() {
                      _declarationAccepted = value ?? false;
                      _error = null;
                    }),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _authorized.declarationText.isEmpty
                      ? 'Declaro que estos datos son los que la DGII autorizó a '
                            'mi empresa y que no usaré números fuera de ese rango.'
                      : _authorized.declarationText,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _declaredSummary(EcfAuthorizedSequence item) {
    final range =
        '${item.rangeFrom}–${item.rangeTo} · ${item.approvedQuantity} aprobados';
    final expiry = item.expiresAt == null
        ? 'Sin vencimiento'
        : 'Vence ${_formatDate(item.expiresAt!)}';
    return EcfSummaryRow(
      label: _typeLabel(item.documentType),
      value: '$range · $expiry · aut. ${item.authorizationNumber}',
      tone: _hasUsableRange(item.documentType) ? EcfTone.done : EcfTone.pending,
    );
  }

  /// Acción para un tipo que ya está declarado pero sin numeración usable.
  ///
  /// Muestra el motivo real según el estado del rango (nunca registrado, agotado
  /// o vencido) para que el cliente sepa qué está arreglando.
  Widget _missingSequenceRow(String type) {
    final current = _activeSequenceFor(type);
    final now = DateTime.now();
    final expired =
        current?.validUntil != null && !current!.validUntil!.isAfter(now);
    final reason = current == null
        ? 'Falta registrar la numeración de la DGII.'
        : expired
        ? 'La numeración de la DGII está vencida: hay que renovarla.'
        : 'Se agotaron los números autorizados: hay que renovar el rango.';
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(
              Icons.error_outline,
              size: 15,
              color: AppColors.textMuted,
            ),
          ),
          Expanded(
            child: Text(
              reason,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            key: ValueKey(
              current == null
                  ? 'ecf_sequence_register_$type'
                  : 'ecf_sequence_renew_$type',
            ),
            onPressed: _saving ? null : () => _syncRange(type),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: Text(current == null ? 'Registrar' : 'Renovar'),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          letterSpacing: 0.2,
          color: AppColors.textMuted,
        ),
      ),
    );
  }

  /// Campo compacto y cuadrado.
  ///
  /// El tema global usa radio 16 y 14 px de alto interno, que en un formulario
  /// de cuatro campos seguidos se lee como cuatro pastillas grandes. Aquí se
  /// declaran también los estados (`enabled`, `focused`, `error`) porque, si no,
  /// los hereda del tema y el campo recupera el radio redondeado al enfocarlo.
  static const _fieldRadius = BorderRadius.all(Radius.circular(6));

  InputDecoration _decoration(String? hint) {
    final errorColor = Theme.of(context).colorScheme.error;
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFFAFBFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      border: const OutlineInputBorder(
        borderRadius: _fieldRadius,
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: _fieldRadius,
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: _fieldRadius,
        borderSide: BorderSide(color: Color(0xFF1957E6), width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: _fieldRadius,
        borderSide: BorderSide(color: errorColor),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: _fieldRadius,
        borderSide: BorderSide(color: errorColor, width: 1.4),
      ),
    );
  }

  Widget _numericField(
    String label,
    TextEditingController controller,
    String keyName,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        TextField(
          key: ValueKey(keyName),
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: _decoration(null),
        ),
      ],
    );
  }

  Widget _textField(
    String label,
    TextEditingController controller,
    String hint,
    String keyName,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        TextField(
          key: ValueKey(keyName),
          controller: controller,
          decoration: _decoration(hint),
        ),
      ],
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'E31':
        return 'Factura de Crédito Fiscal (E31)';
      case 'E34':
        return 'Nota de Crédito (E34)';
      case 'E32':
        return 'Factura de Consumo (E32)';
      default:
        return type;
    }
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }
}
