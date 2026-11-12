import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/company/company_settings_model.dart';
import '../../../core/company/company_settings_repository.dart';
import '../../../core/utils/app_feedback.dart';
import '../domain/ecf_fiscal_readiness.dart';

/// Datos fiscales de la empresa, en versión enfocada para el proceso e-CF.
///
/// La pantalla oficial de Empresa sigue igual y sigue siendo la fuente de
/// verdad; esto es una vista acotada a lo que el comprobante electrónico y la
/// DGII necesitan, para que el cliente no tenga que leer interruptores ni
/// secciones que no vienen al caso.
///
/// No inventa campos: edita exactamente los datos que la venta congela en el
/// comprobante (`companyName`, `rnc`, `address`, `phone`) y los del
/// representante legal, y guarda por las mismas vías que la pantalla oficial
/// (`saveCompanyNameOrQueue` para el nombre —dato maestro— y
/// `saveSettingsOrQueue` para el resto).
class EcfFiscalDataPage extends ConsumerWidget {
  const EcfFiscalDataPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: EcfFiscalDataContent(),
    );
  }
}

/// El mismo formulario fiscal para la ruta heredada y el asistente principal.
class EcfFiscalDataContent extends ConsumerWidget {
  const EcfFiscalDataContent({
    super.key,
    this.compact = false,
    this.onSaved,
    this.onClose,
  });

  final bool compact;
  final VoidCallback? onSaved;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(companySettingsProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(companySettingsProvider);
        await ref.read(companySettingsProvider.future);
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 940),
          child: _SettingsLoader(
            settings: settings,
            compact: compact,
            onSaved: onSaved,
            onClose: onClose,
          ),
        ),
      ),
    );
  }
}

/// Resuelve la carga de la configuración antes de montar el formulario.
class _SettingsLoader extends StatelessWidget {
  const _SettingsLoader({
    required this.settings,
    required this.compact,
    this.onSaved,
    this.onClose,
  });

  final AsyncValue<CompanySettings> settings;
  final bool compact;
  final VoidCallback? onSaved;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    // Riverpod conserva el valor anterior durante una recarga. Mantener el
    // formulario montado evita perder foco y selección mientras llega la red.
    final current = settings.valueOrNull;
    if (current != null) {
      return _form(current);
    }
    return settings.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        children: [
          _SurfacePanel(
            child: Text(
              'No se pudieron cargar los datos fiscales.\n$error',
              style: const TextStyle(fontSize: 12.5, color: Color(0xFFB42318)),
            ),
          ),
        ],
      ),
      data: _form,
    );
  }

  Widget _form(CompanySettings data) => ListView(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
    children: [
      if (onClose != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onClose,
            child: const Text('Volver a la guía'),
          ),
        ),
      _FiscalForm(initial: data, compact: compact, onSaved: onSaved),
    ],
  );
}

class _FiscalForm extends ConsumerStatefulWidget {
  const _FiscalForm({
    required this.initial,
    required this.compact,
    this.onSaved,
  });

  final CompanySettings initial;
  final bool compact;
  final VoidCallback? onSaved;

  @override
  ConsumerState<_FiscalForm> createState() => _FiscalFormState();
}

class _FiscalFormState extends ConsumerState<_FiscalForm> {
  late final TextEditingController _name;
  late final TextEditingController _rnc;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _legalName;
  late final TextEditingController _legalCedula;
  late final Map<String, FocusNode> _focusNodes;
  late final FocusNode _emailFocus;
  late final Set<String> _pendingVisible;
  bool _saving = false;
  bool _reviewAll = false;

  @override
  void initState() {
    super.initState();
    final settings = widget.initial;
    _name = TextEditingController(text: settings.companyName.trim());
    _rnc = TextEditingController(text: settings.rnc.trim());
    _address = TextEditingController(text: settings.address.trim());
    _phone = TextEditingController(text: settings.phone.trim());
    _email = TextEditingController(text: settings.ecfContactEmail.trim());
    _legalName = TextEditingController(
      text: settings.legalRepresentativeName.trim(),
    );
    _legalCedula = TextEditingController(
      text: settings.legalRepresentativeCedula.trim(),
    );
    _pendingVisible = buildEcfFiscalItems(settings)
        .where((item) => !item.ok && item.key != 'phone')
        .map((item) => item.key)
        .toSet();
    _emailFocus = FocusNode();
    _focusNodes = {
      for (final item in buildEcfFiscalItems(settings)) item.key: FocusNode(),
    };
    for (final entry in _focusNodes.entries) {
      entry.value.addListener(() {
        if (entry.value.hasFocus || !mounted) return;
        final item = buildEcfFiscalItems(
          _draft,
        ).firstWhere((item) => item.key == entry.key);
        setState(() {
          if (item.ok) {
            _pendingVisible.remove(entry.key);
          } else {
            _pendingVisible.add(entry.key);
          }
        });
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _rnc.dispose();
    _address.dispose();
    _phone.dispose();
    _email.dispose();
    _emailFocus.dispose();
    _legalName.dispose();
    _legalCedula.dispose();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Copia con lo que hay ahora en pantalla, para validar mientras se escribe.
  CompanySettings get _draft => widget.initial.copyWith(
    companyName: _name.text.trim(),
    rnc: _rnc.text.trim(),
    address: _address.text.trim(),
    phone: _phone.text.trim(),
    ecfContactEmail: _email.text.trim(),
    legalRepresentativeName: _legalName.text.trim(),
    legalRepresentativeCedula: _legalCedula.text.trim(),
  );

  Future<void> _save() async {
    final draft = _draft;
    final nameChanged = draft.companyName != widget.initial.companyName.trim();
    final repository = ref.read(companySettingsRepositoryProvider);

    setState(() => _saving = true);
    try {
      final queued = await repository.saveSettingsOrQueue(draft);
      var queuedName = false;
      // El nombre es dato maestro: solo se envía por la vía explícita cuando el
      // usuario realmente lo editó, igual que en la pantalla oficial.
      if (nameChanged) {
        queuedName = await repository.saveCompanyNameOrQueue(draft.companyName);
      }
      if (!mounted) return;
      ref.invalidate(companySettingsProvider);
      final pendingSync = queued || queuedName;
      AppFeedback.showToast(
        context,
        title: pendingSync ? 'Datos guardados sin conexión' : 'Datos guardados',
        body: pendingSync
            ? 'Se guardaron en este equipo y se sincronizarán cuando vuelva la conexión.'
            : 'Tus datos fiscales quedaron actualizados.',
        kind: pendingSync ? AppFeedbackKind.warning : AppFeedbackKind.success,
        dedupeKey: 'ecf_fiscal_data_saved',
      );
      if (!pendingSync) widget.onSaved?.call();
    } catch (error) {
      if (!mounted) return;
      // El error se queda el tiempo suficiente para leerlo y se puede cerrar.
      AppFeedback.showToast(
        context,
        title: 'No se pudieron guardar los datos',
        body: '$error',
        kind: AppFeedbackKind.error,
        dedupeKey: 'ecf_fiscal_data_error',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = buildEcfFiscalItems(_draft);
    EcfFiscalItem item(String key) =>
        items.firstWhere((entry) => entry.key == key);
    bool show(String key) =>
        !widget.compact ||
        _reviewAll ||
        _focusNodes[key]!.hasFocus ||
        _pendingVisible.contains(key);
    final blockingMissing = items
        .where((entry) => entry.blocking && !entry.ok)
        .toList();
    final recommendedMissing = items
        .where((entry) => !entry.blocking && !entry.ok)
        .toList();
    final emailValue = _email.text.trim();
    final emailMissing = !isEcfContactEmailValid(emailValue);
    final showEmail =
        !widget.compact ||
        _reviewAll ||
        emailMissing ||
        _emailFocus.hasFocus;

    return _SurfacePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Datos fiscales de la empresa',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          const Text(
            'Estos son los datos que se imprimen en cada comprobante '
            'electrónico. Completa los marcados en rojo para que la emisión no '
            'se rechace por datos del emisor.',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          _ReadinessBanner(
            blockingMissing: blockingMissing,
            recommendedMissing: recommendedMissing,
            emailMissing: emailMissing,
          ),
          const SizedBox(height: 14),
          if (widget.compact)
            TextButton(
              onPressed: () => setState(() => _reviewAll = !_reviewAll),
              child: Text(_reviewAll ? 'Mostrar pendientes' : 'Revisar datos'),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (show('companyName'))
                  _FiscalField(
                    item: item('companyName'),
                    controller: _name,
                    focusNode: _focusNodes['companyName']!,
                    hintText: 'Como debe aparecer en el comprobante',
                    onChanged: () => setState(() {}),
                  ),
                if (show('rnc'))
                  _FiscalField(
                    item: item('rnc'),
                    controller: _rnc,
                    focusNode: _focusNodes['rnc']!,
                    hintText: '000000000',
                    keyboardType: TextInputType.number,
                    onChanged: () => setState(() {}),
                  ),
                if (show('address'))
                  _FiscalField(
                    item: item('address'),
                    controller: _address,
                    focusNode: _focusNodes['address']!,
                    hintText: 'Calle, número, sector, municipio',
                    maxLines: 2,
                    onChanged: () => setState(() {}),
                  ),
                if (show('phone'))
                  _FiscalField(
                    item: item('phone'),
                    controller: _phone,
                    focusNode: _focusNodes['phone']!,
                    hintText: '8090000000',
                    keyboardType: TextInputType.phone,
                    onChanged: () => setState(() {}),
                  ),
                if (showEmail)
                  _FiscalField(
                    item: EcfFiscalItem(
                      key: 'ecfContactEmail',
                      label: 'Correo fiscal',
                      value: emailValue,
                      requirement: EcfFiscalRequirement.recommended,
                      ok: !emailMissing,
                      hint:
                          'Lo usa el portal de certificación para contactar a tu empresa.',
                    ),
                    controller: _email,
                    focusNode: _emailFocus,
                    hintText: 'facturacion@tuempresa.com',
                    keyboardType: TextInputType.emailAddress,
                    onChanged: () => setState(() {}),
                  ),
                if (show('legalRepresentativeName') ||
                    show('legalRepresentativeCedula')) ...[
                  const SizedBox(height: 4),
                  const Divider(height: 20, color: Color(0xFFEDF1F5)),
                  const SizedBox(height: 4),
                  const Text(
                    'Representante legal',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'La DGII lo solicita durante la postulación de la empresa.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 10),
                  if (show('legalRepresentativeName'))
                    _FiscalField(
                      item: item('legalRepresentativeName'),
                      controller: _legalName,
                      focusNode: _focusNodes['legalRepresentativeName']!,
                      hintText: 'Nombre completo',
                      onChanged: () => setState(() {}),
                    ),
                  if (show('legalRepresentativeCedula'))
                    _FiscalField(
                      item: item('legalRepresentativeCedula'),
                      controller: _legalCedula,
                      focusNode: _focusNodes['legalRepresentativeCedula']!,
                      hintText: '00000000000',
                      keyboardType: TextInputType.number,
                      onChanged: () => setState(() {}),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_saving ? 'Guardando…' : 'Guardar datos'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1957E6),
                  minimumSize: const Size(0, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Resumen del estado: qué falta y qué no bloquea la emisión hoy.
class _ReadinessBanner extends StatelessWidget {
  const _ReadinessBanner({
    required this.blockingMissing,
    required this.recommendedMissing,
    this.emailMissing = false,
  });

  final List<EcfFiscalItem> blockingMissing;
  final List<EcfFiscalItem> recommendedMissing;
  final bool emailMissing;

  @override
  Widget build(BuildContext context) {
    final ready = blockingMissing.isEmpty;
    final background = ready
        ? const Color(0xFFECFDF3)
        : const Color(0xFFFFF4E5);
    final foreground = ready
        ? const Color(0xFF15803D)
        : const Color(0xFFB45309);
    final icon = ready ? Icons.verified_outlined : Icons.error_outline_rounded;
    final text = ready
        ? 'Los datos obligatorios están completos: la emisión no se bloquea '
              'por datos del emisor.'
        : '${blockingMissing.length == 1 ? 'Falta 1 dato obligatorio' : 'Faltan ${blockingMissing.length} datos obligatorios'}: '
              '${blockingMissing.map((item) => item.label.toLowerCase()).join(', ')}. '
              'Sin ellos la emisión se rechaza.';
    final notes = <String>[
      if (recommendedMissing.length == 1)
        'Además, 1 dato recomendado está incompleto: '
            '${recommendedMissing.first.label.toLowerCase()}.'
      else if (recommendedMissing.length > 1)
        'Además, ${recommendedMissing.length} datos recomendados están '
            'incompletos: '
            '${recommendedMissing.map((item) => item.label.toLowerCase()).join(', ')}.',
      if (emailMissing)
        'Falta el correo fiscal: es necesario para iniciar la postulación electrónica.',
    ];
    final note = notes.isEmpty ? null : notes.join(' ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: foreground),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      note,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
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

class _FiscalField extends StatelessWidget {
  const _FiscalField({
    required this.item,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onChanged,
    this.keyboardType,
    this.maxLines = 1,
  });

  final EcfFiscalItem item;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final VoidCallback onChanged;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final invalid = !item.ok && !focusNode.hasFocus;
    final borderColor = invalid && item.blocking
        ? const Color(0xFFD92D20)
        : const Color(0xFFDDE7EE);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF5B6B7C),
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            key: ValueKey('fiscal_field_${item.key}'),
            controller: controller,
            focusNode: focusNode,
            keyboardType: keyboardType,
            maxLines: maxLines,
            onChanged: (_) => onChanged(),
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              hintText: hintText,
              hintStyle: const TextStyle(
                fontSize: 13,
                color: Color(0xFFA7B4C2),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 11,
                vertical: maxLines > 1 ? 10 : 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFF1957E6)),
              ),
            ),
          ),
          if (invalid)
            Padding(
              padding: const EdgeInsets.only(top: 3, left: 2),
              child: Text(
                item.hint,
                style: TextStyle(
                  fontSize: 10.5,
                  color: item.blocking
                      ? const Color(0xFFB42318)
                      : const Color(0xFF64748B),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SurfacePanel extends StatelessWidget {
  const _SurfacePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: child,
    );
  }
}
