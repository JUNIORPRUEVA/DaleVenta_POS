import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/errors/api_exception.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../features/price_lists/data/price_lists_repository.dart';
import 'application/clientes_controller.dart';
import 'cliente_model.dart';

Future<ClienteModel?> openClienteFormAdaptive(
  BuildContext context, {
  String? clienteId,
  bool returnSavedClient = true,
  bool useRootNavigator = false,
  bool requireFiscalData = false,
  String? ecfDocumentType,
}) async {
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final width = MediaQuery.sizeOf(context).width;
  final isDesktop = width >= kDesktopShellBreakpoint;

  if (!isDesktop) {
    return navigator.push<ClienteModel>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ClienteFormScreen(
          clienteId: clienteId,
          returnSavedClient: returnSavedClient,
          requireFiscalData: requireFiscalData,
          ecfDocumentType: ecfDocumentType,
        ),
      ),
    );
  }

  return showGeneralDialog<ClienteModel>(
    context: context,
    useRootNavigator: useRootNavigator,
    barrierDismissible: true,
    barrierLabel: clienteId == null ? 'Crear cliente' : 'Editar cliente',
    barrierColor: Colors.black.withValues(alpha: 0.22),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final size = MediaQuery.sizeOf(dialogContext);
      final panelWidth = size.width >= 1600
          ? 560.0
          : size.width >= 1280
          ? 520.0
          : size.width >= 1024
          ? 480.0
          : (size.width * 0.46).clamp(420.0, 520.0);

      return Material(
        color: Colors.transparent,
        child: Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: panelWidth,
            height: size.height,
            child: ClienteFormScreen(
              clienteId: clienteId,
              returnSavedClient: returnSavedClient,
              compactDialog: true,
              requireFiscalData: requireFiscalData,
              ecfDocumentType: ecfDocumentType,
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: Tween<double>(begin: 0, end: 1).animate(curved),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class ClienteFormScreen extends ConsumerStatefulWidget {
  final String? clienteId;
  final bool returnSavedClient;
  final bool compactDialog;
  final bool requireFiscalData;

  /// Comprobante elegido en el cobro (`E31`, `E32`, `NORMAL`). Decide qué
  /// campos se piden primero: el crédito fiscal necesita RNC y razón social;
  /// el consumo y la venta normal, nombre y teléfono.
  final String? ecfDocumentType;

  const ClienteFormScreen({
    super.key,
    this.clienteId,
    this.returnSavedClient = false,
    this.compactDialog = false,
    this.requireFiscalData = false,
    this.ecfDocumentType,
  });

  @override
  ConsumerState<ClienteFormScreen> createState() => _ClienteFormScreenState();
}

class _ClienteFormScreenState extends ConsumerState<ClienteFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _direccionCtrl = TextEditingController();
  final _taxIdCtrl = TextEditingController();

  bool _loadingInitial = false;
  ClienteModel? _cliente;
  String? _defaultPriceListId;

  /// Los campos secundarios (dirección, RNC si no hace falta...) quedan
  /// detrás de «Ver más» para que crear un cliente sea de dos campos.
  bool _showAllFields = false;

  bool get _isEdit => widget.clienteId != null && widget.clienteId!.isNotEmpty;

  /// Crédito fiscal: el receptor se identifica con RNC y razón social.
  bool get _isCreditFiscal =>
      (widget.ecfDocumentType ?? '').trim().toUpperCase() == 'E31';

  bool get _requiresTaxId => _isCreditFiscal || widget.requireFiscalData;

  @override
  void initState() {
    super.initState();
    // Al editar se muestra todo: el usuario vino a revisar el cliente entero.
    _showAllFields = _isEdit;
    _loadIfEdit();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _direccionCtrl.dispose();
    _taxIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadIfEdit() async {
    if (!_isEdit) return;
    setState(() => _loadingInitial = true);
    try {
      final cliente = await ref
          .read(clientesControllerProvider.notifier)
          .getById(widget.clienteId!);
      if (!mounted) return;
      setState(() {
        _cliente = cliente;
        _nombreCtrl.text = cliente.nombre;
        _telefonoCtrl.text = cliente.telefono;
        _direccionCtrl.text = cliente.direccion ?? '';
        _taxIdCtrl.text = cliente.taxId ?? '';
        _defaultPriceListId = cliente.defaultPriceListId;
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo cargar el cliente para edicion'),
        ),
      );
    } finally {
      if (mounted) setState(() => _loadingInitial = false);
    }
  }

  Future<void> _save() async {
    if (ref.read(clientesControllerProvider).saving) return;
    final valid = _formKey.currentState!.validate();
    if (!valid) {
      if (widget.requireFiscalData &&
          (_nombreCtrl.text.trim().isEmpty || _taxIdCtrl.text.trim().isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Para una factura fiscal, Nombre o razón social y RNC/Cédula son obligatorios.',
            ),
          ),
        );
      }
      return;
    }

    try {
      final targetId = (_cliente?.id ?? widget.clienteId ?? '').trim();
      final saved = await ref
          .read(clientesControllerProvider.notifier)
          .saveCliente(
            id: targetId.isEmpty ? null : targetId,
            nombre: _nombreCtrl.text,
            telefono: _telefonoCtrl.text,
            direccion: _direccionCtrl.text,
            locationUrl: _cliente?.locationUrl,
            correo: _cliente?.correo,
            taxId: _taxIdCtrl.text,
            businessName: _cliente?.businessName,
            taxIdType: _taxIdCtrl.text.trim().isEmpty ? null : 'RNC',
          );
      final wholesaleEnabled =
          ref
              .read(companySettingsProvider)
              .valueOrNull
              ?.wholesalePriceListsEnabled ==
          true;
      if (wholesaleEnabled) {
        await ref
            .read(priceListsRepositoryProvider)
            .assignClientPriceList(
              clientId: saved.id,
              priceListId: _defaultPriceListId,
            );
        ref.invalidate(priceListsProvider);
      }
      if (!mounted) return;
      if (widget.returnSavedClient) {
        Navigator.of(context).pop(saved);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEdit ? 'Cliente actualizado' : 'Cliente creado'),
        ),
      );
      context.go(Routes.clienteDetail(saved.id));
    } catch (e) {
      if (!mounted) return;
      final message =
          e is ApiException &&
              (e.code == 403 || e.type == ApiErrorType.forbidden)
          ? 'No tienes permiso para crear o editar clientes'
          : e.toString();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(clientesControllerProvider);
    final user = ref.watch(authStateProvider).user;

    if (widget.compactDialog) {
      final theme = Theme.of(context);
      return Material(
        color: theme.colorScheme.surface,
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(18),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 16,
                offset: const Offset(-6, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 10, 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFEDF1F6)),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isEdit ? 'Editar cliente' : 'Nuevo cliente',
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.25,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 3),
                          const Text(
                            'Se guarda al instante y vuelve a la factura.',
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.3,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      visualDensity: VisualDensity.compact,
                      color: const Color(0xFF94A3B8),
                      onPressed: state.saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: _buildFormContent(
                      context,
                      state: state,
                      withActions: false,
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Color(0xFFEDF1F6)),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: _buildFormActions(context, state),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: CustomAppBar(
        title: _isEdit ? 'Editar cliente' : 'Nuevo cliente',
        fallbackRoute: Routes.clientes,
        showLogo: false,
        showDepartmentLabel: false,
      ),
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildFormContent(context, state: state),
            ),
          ),
          if (_loadingInitial)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration({required String label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      labelStyle: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: Color(0xFF5B6B7A),
      ),
      floatingLabelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1957E6),
      ),
      hintStyle: const TextStyle(
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
        color: Color(0xFF9AA7B2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF1957E6), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
      ),
    );
  }

  Widget _buildFormContent(
    BuildContext context, {
    required ClientesState state,
    bool withActions = true,
  }) {
    final wholesaleEnabled =
        ref
            .watch(companySettingsProvider)
            .valueOrNull
            ?.wholesalePriceListsEnabled ==
        true;
    final priceLists = wholesaleEnabled
        ? ref.watch(priceListsProvider)
        : const AsyncValue<List<PriceListModel>>.data(<PriceListModel>[]);

    final nameField = TextFormField(
      controller: _nombreCtrl,
      textCapitalization: TextCapitalization.words,
      style: const TextStyle(fontSize: 14.5),
      decoration: _fieldDecoration(
        label: _isCreditFiscal ? 'Razón social *' : 'Nombre *',
        hint: _isCreditFiscal
            ? 'Como aparece en el RNC'
            : 'Nombre del cliente',
      ),
      onFieldSubmitted: (_) => _save(),
      validator: (value) {
        final text = (value ?? '').trim();
        if (text.isEmpty) {
          return _isCreditFiscal
              ? 'La razón social es obligatoria'
              : 'El nombre es obligatorio';
        }
        if (text.length < 2) {
          return 'Ingresa un nombre valido';
        }
        return null;
      },
    );

    final phoneField = TextFormField(
      controller: _telefonoCtrl,
      keyboardType: TextInputType.phone,
      style: const TextStyle(fontSize: 14.5),
      decoration: _fieldDecoration(
        label: 'Teléfono',
        hint: 'Ej: +1 809 555 1234',
      ),
      onFieldSubmitted: (_) => _save(),
      validator: (value) {
        final text = (value ?? '').trim();
        if (text.isEmpty) return null;
        final sanitized = text.replaceAll(RegExp(r'[^0-9+]'), '');
        if (sanitized.length < 7) {
          return 'Telefono demasiado corto';
        }
        final allowed = RegExp(r'^[0-9+()\-\s]+$');
        if (!allowed.hasMatch(text)) {
          return 'Formato de telefono invalido';
        }
        return null;
      },
    );

    final taxIdField = TextFormField(
      controller: _taxIdCtrl,
      keyboardType: TextInputType.number,
      style: const TextStyle(fontSize: 14.5),
      onFieldSubmitted: (_) => _save(),
      decoration: _fieldDecoration(
        label: _requiresTaxId ? 'RNC / Cédula *' : 'RNC / Cédula',
        hint: _isCreditFiscal
            ? 'Requerido para crédito fiscal'
            : (_requiresTaxId ? 'Requerido para factura fiscal' : 'Opcional'),
      ),
      validator: _requiresTaxId
          ? (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) {
                return 'Requerido para factura fiscal';
              }
              return null;
            }
          : null,
    );

    final addressField = TextFormField(
      controller: _direccionCtrl,
      textCapitalization: TextCapitalization.sentences,
      style: const TextStyle(fontSize: 14.5),
      decoration: _fieldDecoration(label: 'Dirección', hint: 'Opcional'),
      onFieldSubmitted: (_) => _save(),
    );

    final priceListField = wholesaleEnabled
        ? priceLists.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (_, __) => DropdownButtonFormField<String?>(
              initialValue: null,
              decoration: _fieldDecoration(label: 'Lista de precios'),
              items: const [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text('No se pudieron cargar las listas'),
                ),
              ],
              onChanged: null,
            ),
            data: (lists) {
              final activeLists = lists.where((list) => list.active).toList();
              final selected =
                  activeLists.any((list) => list.id == _defaultPriceListId)
                  ? _defaultPriceListId
                  : null;
              return DropdownButtonFormField<String?>(
                initialValue: selected,
                isExpanded: true,
                decoration: _fieldDecoration(label: 'Lista de precios'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Sin lista mayorista'),
                  ),
                  for (final list in activeLists)
                    DropdownMenuItem<String?>(
                      value: list.id,
                      child: Text(list.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: state.saving
                    ? null
                    : (value) => setState(() => _defaultPriceListId = value),
              );
            },
          )
        : null;

    // Lo mínimo para identificar al cliente según el comprobante elegido:
    // crédito fiscal pide RNC y razón social; el resto, nombre y teléfono.
    final primaryFields = _isCreditFiscal
        ? <Widget>[taxIdField, nameField]
        : <Widget>[
            nameField,
            phoneField,
            if (widget.requireFiscalData) taxIdField,
          ];

    // El resto queda detrás de «Ver más».
    final extraFields = <Widget>[
      if (_isCreditFiscal) phoneField,
      if (!_isCreditFiscal && !widget.requireFiscalData) taxIdField,
      addressField,
      if (priceListField != null) priceListField,
    ];

    List<Widget> withGaps(List<Widget> fields) => [
      for (var i = 0; i < fields.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        fields[i],
      ],
    ];

    final form = Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...withGaps(primaryFields),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    setState(() => _showAllFields = !_showAllFields),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF1957E6),
                  textStyle: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: Icon(
                  _showAllFields
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 18,
                ),
                label: Text(_showAllFields ? 'Ver menos' : 'Ver más'),
              ),
            ),
          ),
          if (_showAllFields) ...[
            const SizedBox(height: 6),
            ...withGaps(extraFields),
          ],
          if (withActions) ...[
            const SizedBox(height: 18),
            _buildFormActions(context, state),
          ],
        ],
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _save,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _save,
      },
      child: Focus(autofocus: true, child: form),
    );
  }

  /// Cancelar / Guardar. Se comparte entre la página completa y el pie del
  /// panel lateral para que ambas variantes se comporten y se vean igual.
  Widget _buildFormActions(BuildContext context, ClientesState state) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: state.saving ? null : () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF334155),
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('Cancelar'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: state.saving ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1957E6),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              textStyle: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: state.saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Guardar'),
          ),
        ),
      ],
    );
  }
}
