import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/errors/api_exception.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'application/clientes_controller.dart';
import 'cliente_model.dart';

Future<ClienteModel?> openClienteFormAdaptive(
  BuildContext context, {
  String? clienteId,
  bool returnSavedClient = true,
  bool useRootNavigator = false,
  bool requireFiscalData = false,
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

  const ClienteFormScreen({
    super.key,
    this.clienteId,
    this.returnSavedClient = false,
    this.compactDialog = false,
    this.requireFiscalData = false,
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

  bool get _isEdit => widget.clienteId != null && widget.clienteId!.isNotEmpty;

  @override
  void initState() {
    super.initState();
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
          (_nombreCtrl.text.trim().isEmpty ||
              _taxIdCtrl.text.trim().isEmpty)) {
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
    final formContent = _buildFormContent(context, state: state);

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
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(0),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isEdit ? 'Editar cliente' : 'Nuevo cliente',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Crea el cliente sin salir del formulario de operaciones.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onPrimary.withValues(
                                alpha: 0.84,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Cerrar',
                      onPressed: state.saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.18),
                        foregroundColor: theme.colorScheme.onPrimary,
                      ),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
                    child: formContent,
                  ),
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
              child: formContent,
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

  InputDecoration _fieldDecoration({
    required String label,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFFFFFFF),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      labelStyle: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: Color(0xFF5B6B7A),
      ),
      hintStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: Color(0xFF9AA7B2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFD3D9DF), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF1957E6), width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.4),
      ),
    );
  }

  Widget _buildFormContent(
    BuildContext context, {
    required ClientesState state,
  }) {
    final form = Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _nombreCtrl,
            textCapitalization: TextCapitalization.words,
            style: const TextStyle(fontSize: 14.5),
            decoration: _fieldDecoration(
              label: 'Nombre o razón social *',
              hint: 'Nombre de persona o empresa',
            ),
            onFieldSubmitted: (_) => _save(),
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return 'El nombre es obligatorio';
              if (text.length < 2) {
                return 'Ingresa un nombre valido';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
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
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _taxIdCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 14.5),
            onFieldSubmitted: (_) => _save(),
            decoration: _fieldDecoration(
              label: widget.requireFiscalData
                  ? 'RNC / Cédula *'
                  : 'RNC / Cédula',
              hint: widget.requireFiscalData
                  ? 'Requerido para factura fiscal'
                  : 'Opcional para comprobante B01',
            ),
            validator: widget.requireFiscalData
                ? (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) {
                      return 'Requerido para factura fiscal';
                    }
                    return null;
                  }
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _direccionCtrl,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 14.5),
            decoration: _fieldDecoration(label: 'Dirección', hint: 'Opcional'),
            onFieldSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: state.saving ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1957E6),
                    backgroundColor: Colors.white,
                    side: const BorderSide(
                      color: Color(0xFF1957E6),
                      width: 1.2,
                    ),
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: state.saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1957E6),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
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
          ),
        ],
      ),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _save,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _save,
      },
      child: Focus(
        autofocus: true,
        child: form,
      ),
    );
  }
}
