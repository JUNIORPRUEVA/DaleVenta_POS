import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:validators/validators.dart' as validators;

import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/errors/api_exception.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/app_navigation.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'application/clientes_controller.dart';
import 'client_location_utils.dart';
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
  final _locationUrlCtrl = TextEditingController();
  final _correoCtrl = TextEditingController();
  final _taxIdCtrl = TextEditingController();
  final _businessNameCtrl = TextEditingController();

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
    _locationUrlCtrl.dispose();
    _correoCtrl.dispose();
    _taxIdCtrl.dispose();
    _businessNameCtrl.dispose();
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
        _locationUrlCtrl.text = cliente.locationUrl ?? '';
        _correoCtrl.text = cliente.correo ?? '';
        _taxIdCtrl.text = cliente.taxId ?? '';
        _businessNameCtrl.text = cliente.businessName ?? '';
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
            locationUrl: normalizeClientLocationUrl(_locationUrlCtrl.text),
            correo: _correoCtrl.text,
            taxId: _taxIdCtrl.text,
            businessName: _businessNameCtrl.text,
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
    final normalizedLocationUrl = normalizeClientLocationUrl(
      _locationUrlCtrl.text,
    );
    final locationPreview = parseClientLocationPreview(normalizedLocationUrl);
    final locationUri = Uri.tryParse(normalizedLocationUrl);
    final formContent = _buildFormContent(
      context,
      state: state,
      normalizedLocationUrl: normalizedLocationUrl,
      locationPreview: locationPreview,
      locationUri: locationUri,
    );

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
    required String normalizedLocationUrl,
    required ClientLocationPreview locationPreview,
    required Uri? locationUri,
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
            controller: _locationUrlCtrl,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Link de ubicacion',
              hintText: 'https://maps.google.com/...',
              suffixIcon: IconButton(
                tooltip: 'Abrir link',
                onPressed: normalizedLocationUrl.isEmpty
                    ? null
                    : () async {
                        final uri = locationUri;
                        if (uri == null) return;
                        await safeOpenUrl(context, uri);
                      },
                icon: const Icon(Icons.open_in_new_rounded),
              ),
            ),
            onChanged: (_) => setState(() {}),
            validator: (value) {
              final normalized = normalizeClientLocationUrl(value);
              if (normalized.isEmpty) return null;
              final uri = Uri.tryParse(normalized);
              final looksValid =
                  uri != null &&
                  uri.hasScheme &&
                  (uri.host.isNotEmpty || uri.scheme == 'geo');
              if (!looksValid) {
                return 'Ingresa un link de ubicacion valido';
              }
              return null;
            },
          ),
          if (normalizedLocationUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            _LocationPreviewCard(
              locationUrl: normalizedLocationUrl,
              latitude: locationPreview.latitude,
              longitude: locationPreview.longitude,
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _correoCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Correo',
              hintText: 'Opcional',
            ),
            validator: (value) {
              final text = (value ?? '').trim();
              if (text.isEmpty) return null;
              if (!validators.isEmail(text)) {
                return 'Correo invalido';
              }
              return null;
            },
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
          const SizedBox(height: 12),
          TextFormField(
            controller: _businessNameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Razon social',
              hintText: 'Opcional',
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

class _LocationPreviewCard extends ConsumerWidget {
  const _LocationPreviewCard({
    required this.locationUrl,
    this.latitude,
    this.longitude,
  });

  final String locationUrl;
  final double? latitude;
  final double? longitude;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final uri = Uri.tryParse(locationUrl);
    final directPreview = ClientLocationPreview(
      latitude: latitude,
      longitude: longitude,
      resolvedUrl: locationUrl,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Vista previa de ubicacion',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            FutureBuilder<ClientLocationPreview>(
              future: resolveClientLocationPreview(
                locationUrl,
                dio: ref.read(dioProvider),
              ),
              initialData: directPreview,
              builder: (context, snapshot) {
                final preview = snapshot.data ?? directPreview;

                if (preview.hasCoordinates) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(
                          height: 180,
                          child: FlutterMap(
                            options: MapOptions(
                              initialCenter: LatLng(
                                preview.latitude!,
                                preview.longitude!,
                              ),
                              initialZoom: 15,
                              interactionOptions: const InteractionOptions(
                                flags: InteractiveFlag.none,
                              ),
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.fulltech.app',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point: LatLng(
                                      preview.latitude!,
                                      preview.longitude!,
                                    ),
                                    width: 40,
                                    height: 40,
                                    child: Icon(
                                      Icons.location_pin,
                                      color: theme.colorScheme.error,
                                      size: 40,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${preview.latitude!.toStringAsFixed(6)}, ${preview.longitude!.toStringAsFixed(6)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  );
                }

                return Text(
                  'El enlace se guardara, pero no se pudieron extraer coordenadas para mostrar el mapa aqui.',
                  style: theme.textTheme.bodyMedium,
                );
              },
            ),
            if (uri != null) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => safeOpenUrl(context, uri),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: const Text('Abrir enlace'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
