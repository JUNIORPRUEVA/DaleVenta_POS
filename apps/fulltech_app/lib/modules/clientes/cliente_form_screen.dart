import 'package:flutter/material.dart';
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

  const ClienteFormScreen({
    super.key,
    this.clienteId,
    this.returnSavedClient = false,
    this.compactDialog = false,
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
    if (!_formKey.currentState!.validate()) return;

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
              left: Radius.circular(28),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 28,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(22, 18, 14, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withValues(alpha: 0.84),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
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
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Crea el cliente sin salir del formulario de operaciones.',
                            style: theme.textTheme.bodyMedium?.copyWith(
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
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
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

  Widget _buildFormContent(
    BuildContext context, {
    required ClientesState state,
  }) {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFormField(
            controller: _nombreCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nombre *',
              hintText: 'Nombre completo del cliente',
            ),
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
            decoration: const InputDecoration(
              labelText: 'Telefono *',
              hintText: 'Ej: +1 809 555 1234',
            ),
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return 'El telefono es obligatorio';
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
            controller: _direccionCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Direccion',
              hintText: 'Opcional',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _taxIdCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'RNC / cedula fiscal',
              hintText: 'Opcional para comprobante B01',
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: state.saving ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: state.saving ? null : _save,
                  icon: state.saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Guardar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
