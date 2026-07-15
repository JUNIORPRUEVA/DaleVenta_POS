import 'dart:async';
import 'dart:typed_data';
import 'dart:developer' as dev;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/api/env.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/product_model.dart';
import '../../../core/utils/media_file_actions.dart';
import '../../../core/widgets/product_network_image.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../features/catalogo/data/catalog_repository.dart';
import '../../../modules/service_orders/service_order_models.dart';
import '../application/publicidad_images_controller.dart';
import '../data/media_gallery_repository.dart';
import '../media_gallery_models.dart';
import '../models/publicidad_image_model.dart';
import '../widgets/media_gallery_card.dart';

// ─── State & Controller ─────────────────────────────────────────────────────

class _GaleriaPublicidadState {
  const _GaleriaPublicidadState({
    this.items = const [],
    this.loading = false,
    this.error,
  });

  final List<MediaGalleryItem> items;
  final bool loading;
  final String? error;

  _GaleriaPublicidadState copyWith({
    List<MediaGalleryItem>? items,
    bool? loading,
    String? error,
    bool clearError = false,
  }) {
    return _GaleriaPublicidadState(
      items: items ?? this.items,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final _galeriaPublicidadControllerProvider =
    StateNotifierProvider.autoDispose<
      _GaleriaPublicidadController,
      _GaleriaPublicidadState
    >((ref) {
      return _GaleriaPublicidadController(ref);
    });

class _GaleriaPublicidadController
    extends StateNotifier<_GaleriaPublicidadState> {
  _GaleriaPublicidadController(this._ref)
    : super(const _GaleriaPublicidadState()) {
    unawaited(load());
  }

  final Ref _ref;

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final items = await _ref
          .read(mediaGalleryRepositoryProvider)
          .fetchPublicidad();
      state = state.copyWith(items: items, loading: false);
    } catch (error) {
      state = state.copyWith(
        loading: false,
        error: 'No se pudo cargar la galería de publicidad.',
      );
    }
  }

  Future<void> removeItem(String id) async {
    try {
      await _ref.read(mediaGalleryRepositoryProvider).unmarkForPublicidad(id);
      final updated = state.items
          .where((i) => i.id != id)
          .toList(growable: false);
      state = state.copyWith(items: updated);
    } catch (error) {
      state = state.copyWith(
        error: 'No se pudo quitar el elemento de publicidad.',
      );
    }
  }
}

// ─── Screen ─────────────────────────────────────────────────────────────────

class GaleriaPublicidadScreen extends ConsumerStatefulWidget {
  const GaleriaPublicidadScreen({super.key});

  @override
  ConsumerState<GaleriaPublicidadScreen> createState() =>
      _GaleriaPublicidadScreenState();
}

class _GaleriaPublicidadScreenState
    extends ConsumerState<GaleriaPublicidadScreen> {
  String _searchQuery = '';
  bool _isUploading = false;
  int _uploadCurrent = 0;
  int _uploadTotal = 0;
  MediaGalleryTypeFilter _galleryTypeFilter = MediaGalleryTypeFilter.all;
  MediaGalleryInstallationFilter _galleryInstallationFilter =
      MediaGalleryInstallationFilter.all;
  ServiceOrderStatus? _galleryOrderStatusFilter;

  List<MediaGalleryItem> _applySearchAndFilters(List<MediaGalleryItem> items) {
    final q = _searchQuery.trim().toLowerCase();
    return items
        .where((item) {
          if (q.isNotEmpty && !item.searchableText.contains(q)) return false;
          if (_galleryTypeFilter == MediaGalleryTypeFilter.image &&
              !item.isImage) {
            return false;
          }
          if (_galleryTypeFilter == MediaGalleryTypeFilter.video &&
              !item.isVideo) {
            return false;
          }
          if (_galleryInstallationFilter ==
                  MediaGalleryInstallationFilter.completed &&
              !item.isInstallationCompleted) {
            return false;
          }
          if (_galleryInstallationFilter ==
                  MediaGalleryInstallationFilter.pending &&
              item.isInstallationCompleted) {
            return false;
          }
          if (_galleryOrderStatusFilter != null &&
              item.orderStatus != _galleryOrderStatusFilter) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  String _typeFilterLabel(MediaGalleryTypeFilter filter) {
    switch (filter) {
      case MediaGalleryTypeFilter.all:
        return 'Todo tipo';
      case MediaGalleryTypeFilter.image:
        return 'Imagen';
      case MediaGalleryTypeFilter.video:
        return 'Video';
    }
  }

  String _installationFilterLabel(MediaGalleryInstallationFilter filter) {
    switch (filter) {
      case MediaGalleryInstallationFilter.all:
        return 'Toda instalación';
      case MediaGalleryInstallationFilter.completed:
        return 'Instalado';
      case MediaGalleryInstallationFilter.pending:
        return 'Pendiente';
    }
  }

  Future<void> _openAddMenu() async {
    final source = await showModalBottomSheet<_PublicidadAddSource>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.upload_rounded),
                  title: const Text('Subir imagen manual'),
                  subtitle: const Text(
                    'Desde galería del dispositivo o por URL',
                  ),
                  onTap: () =>
                      Navigator.of(context).pop(_PublicidadAddSource.manual),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_rounded),
                  title: const Text('Agregar desde galería de contenido'),
                  subtitle: const Text(
                    'Selecciona evidencias y pásalas a Publicidad',
                  ),
                  onTap: () => Navigator.of(
                    context,
                  ).pop(_PublicidadAddSource.mediaGallery),
                ),
                ListTile(
                  leading: const Icon(Icons.inventory_2_rounded),
                  title: const Text('Agregar desde productos'),
                  subtitle: const Text(
                    'Importa imágenes del catálogo de productos',
                  ),
                  onTap: () =>
                      Navigator.of(context).pop(_PublicidadAddSource.products),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || source == null) return;

    switch (source) {
      case _PublicidadAddSource.manual:
        await _showUploadDialog(context);
        return;
      case _PublicidadAddSource.mediaGallery:
        await _addFromMediaGallery();
        return;
      case _PublicidadAddSource.products:
        await _addFromProducts();
        return;
    }
  }

  Future<void> _addFromMediaGallery() async {
    final selectedIds = await showDialog<List<String>>(
      context: context,
      builder: (_) => const _SelectMediaForPublicidadDialog(),
    );
    if (!mounted || selectedIds == null || selectedIds.isEmpty) return;

    setState(() {
      _isUploading = true;
      _uploadTotal = selectedIds.length;
      _uploadCurrent = 0;
    });

    var successCount = 0;
    final failed = <String>[];
    final repository = ref.read(mediaGalleryRepositoryProvider);
    for (var i = 0; i < selectedIds.length; i++) {
      if (!mounted) break;
      setState(() => _uploadCurrent = i + 1);
      final id = selectedIds[i];
      try {
        await repository.markForPublicidad(id);
        successCount++;
      } catch (_) {
        failed.add(id);
      }
    }

    await ref.read(_galeriaPublicidadControllerProvider.notifier).load();

    if (!mounted) return;
    setState(() {
      _isUploading = false;
      _uploadCurrent = 0;
      _uploadTotal = 0;
    });

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (failed.isEmpty) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text('$successCount elemento(s) agregado(s) a Publicidad.'),
        ),
      );
    } else {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            '$successCount agregado(s). ${failed.length} no se pudieron agregar.',
          ),
        ),
      );
    }
  }

  Future<void> _addFromProducts() async {
    final selectedProducts =
        await showDialog<List<_ProductForPublicidadCandidate>>(
          context: context,
          builder: (_) => const _SelectProductsForPublicidadDialog(),
        );
    if (!mounted || selectedProducts == null || selectedProducts.isEmpty) {
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadTotal = selectedProducts.length;
      _uploadCurrent = 0;
    });

    var successCount = 0;
    final failed = <String>[];
    final controller = ref.read(publicidadImagesControllerProvider.notifier);
    await controller.load();

    for (var i = 0; i < selectedProducts.length; i++) {
      if (!mounted) break;
      setState(() => _uploadCurrent = i + 1);
      final product = selectedProducts[i];
      try {
        await controller.create(
          url: _resolveImportedProductImageUrl(product.url),
          caption: product.caption,
        );
        successCount++;
      } catch (_) {
        failed.add(product.caption);
      }
    }

    if (!mounted) return;
    setState(() {
      _isUploading = false;
      _uploadCurrent = 0;
      _uploadTotal = 0;
    });

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (failed.isEmpty) {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            '$successCount imagen(es) importada(s) desde productos.',
          ),
        ),
      );
    } else {
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            '$successCount importada(s). ${failed.length} no se pudieron agregar.',
          ),
        ),
      );
    }
  }

  String _resolveImportedProductImageUrl(String rawUrl) {
    final value = rawUrl.trim();
    if (value.isEmpty) return value;
    if (value.startsWith('http://') || value.startsWith('https://'))
      return value;

    final base = Env.apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) return value;

    final normalized = value.startsWith('/') ? value : '/$value';
    return '$base$normalized';
  }

  Future<void> _downloadItem(MediaGalleryItem item) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final dio = ref.read(dioProvider);
      final bytes = await _downloadMediaBytes(dio, item.url);
      final extension = item.suggestedFileName.split('.').last.toLowerCase();
      final saved = await saveMediaBytes(
        bytes: bytes,
        fileName: item.suggestedFileName,
        allowedExtensions: [extension],
        mimeType: item.isVideo ? 'video/mp4' : 'image/jpeg',
      );
      if (!mounted || !saved) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            '${item.isVideo ? 'Video' : 'Imagen'} descargado correctamente.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(content: Text('No se pudo descargar el archivo: $error')),
      );
    }
  }

  Future<Uint8List> _downloadMediaBytes(Dio dio, String url) async {
    try {
      final response = await dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          extra: const {'skipLoader': true, 'silent': true},
        ),
      );
      final data = response.data;
      if (data != null && data.isNotEmpty) {
        return Uint8List.fromList(data);
      }
    } on DioException {
      // fall through to stream fallback
    }

    final response = await dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        extra: const {'skipLoader': true, 'silent': true},
      ),
    );
    final body = response.data;
    if (body == null) throw Exception('El servidor no devolvió contenido');
    final builder = BytesBuilder(copy: false);
    await for (final chunk in body.stream) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) throw Exception('El archivo llegó vacío');
    return bytes;
  }

  Future<void> _showUploadDialog(BuildContext context) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final results = await showDialog<List<_UploadDialogResult>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const _UploadPublicidadDialog(),
    );
    if (results == null || results.isEmpty || !mounted) return;

    setState(() {
      _isUploading = true;
      _uploadTotal = results.length;
      _uploadCurrent = 0;
    });

    final ctrl = ref.read(publicidadImagesControllerProvider.notifier);
    int successCount = 0;
    final List<String> failedNames = [];
    final List<String> failedDetails = [];
    final uploadEndpoint =
        '${ref.read(dioProvider).options.baseUrl}/publicidad-images/upload';

    for (int i = 0; i < results.length; i++) {
      if (!mounted) break;
      setState(() => _uploadCurrent = i + 1);
      final result = results[i];

      // Validar tipo MIME y tamaño del archivo antes de enviarlo
      if (result.bytes != null) {
        final ext = (result.filename ?? '').split('.').last.toLowerCase();
        final allowedExtensions = ['jpg', 'jpeg', 'png', 'gif'];
        final maxFileSize = 15 * 1024 * 1024; // 15 MB

        if (!allowedExtensions.contains(ext)) {
          failedNames.add(result.filename ?? 'imagen');
          failedDetails.add('Extensión de archivo no permitida: $ext');
          continue;
        }

        if (result.bytes!.lengthInBytes > maxFileSize) {
          failedNames.add(result.filename ?? 'imagen');
          failedDetails.add(
            'El archivo excede el tamaño máximo permitido de 15 MB',
          );
          continue;
        }
      }

      try {
        if (result.bytes != null) {
          final ext = (result.filename ?? '').split('.').last.toLowerCase();
          dev.log(
            '[PublicidadUpload][prepare] file=${result.filename ?? 'sin_nombre'} ext=$ext bytes=${result.bytes!.lengthInBytes} endpoint=$uploadEndpoint',
            name: 'PublicidadUpload',
          );
          await ctrl.uploadBytesAndSave(
            bytes: result.bytes!,
            contentType: result.contentType ?? 'image/jpeg',
            filename: result.filename ?? 'publicidad.jpg',
            caption: result.caption,
          );
        } else if (result.url != null) {
          await ctrl.create(url: result.url!, caption: result.caption);
        }
        successCount++;
      } catch (e) {
        failedNames.add(result.filename ?? 'imagen');
        failedDetails.add(_formatUploadError(e, endpoint: uploadEndpoint));
        dev.log(
          '[PublicidadUpload][ui-error] file=${result.filename ?? 'imagen'} detail=${failedDetails.last}',
          name: 'PublicidadUpload',
          error: e,
          stackTrace: e is Error ? e.stackTrace : null,
        );
      }
    }

    if (!mounted) return;
    if (failedNames.isEmpty) {
      final label = successCount == 1
          ? 'Imagen agregada correctamente.'
          : '$successCount imágenes agregadas correctamente.';
      messenger?.showSnackBar(SnackBar(content: Text(label)));
    } else if (successCount == 0) {
      final detail = failedDetails.isEmpty ? '' : '\n${failedDetails.first}';
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            'No se pudo agregar ninguna imagen: ${failedNames.join(', ')}$detail',
          ),
          duration: const Duration(seconds: 8),
        ),
      );
    } else {
      final detail = failedDetails.isEmpty ? '' : '\n${failedDetails.first}';
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            '$successCount subida(s) correctas. Falló: ${failedNames.join(', ')}$detail',
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    }
    if (mounted) {
      setState(() {
        _isUploading = false;
        _uploadCurrent = 0;
        _uploadTotal = 0;
      });
    }
  }

  Future<void> _confirmRemove(MediaGalleryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar de publicidad'),
        content: const Text(
          '¿Deseas quitar esta evidencia de la Galería de Publicidad?\n'
          'La evidencia seguirá existiendo en la galería de medios.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await ref
        .read(_galeriaPublicidadControllerProvider.notifier)
        .removeItem(item.id);
    if (!mounted) return;
    messenger?.showSnackBar(
      const SnackBar(content: Text('Elemento quitado de publicidad.')),
    );
  }

  Future<void> _confirmDeleteOwn(PublicidadImage img) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar imagen'),
        content: const Text(
          '¿Deseas eliminar esta imagen de publicidad?\nEsta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await ref.read(publicidadImagesControllerProvider.notifier).delete(img.id);
    if (!mounted) return;
    messenger?.showSnackBar(
      const SnackBar(content: Text('Imagen eliminada correctamente.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final canView =
        auth.isAuthenticated &&
        auth.user != null &&
        hasPermission(auth.user!.appRole, AppPermission.viewGaleriaPublicidad);
    final state = ref.watch(_galeriaPublicidadControllerProvider);
    final controller = ref.read(_galeriaPublicidadControllerProvider.notifier);
    final ownImagesState = ref.watch(publicidadImagesControllerProvider);

    if (!canView) {
      return Scaffold(
        drawer: buildAdaptiveDrawer(context, currentUser: auth.user),
        appBar: const CustomAppBar(
          title: 'Galería de Publicidad',
          showLogo: false,
          showDepartmentLabel: false,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Esta pantalla está disponible solo para administradores.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final visibleItems = _applySearchAndFilters(state.items);

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: auth.user),
      appBar: CustomAppBar(
        title: 'Galería de Publicidad',
        showLogo: false,
        showDepartmentLabel: false,
        leading: IconButton(
          tooltip: 'Regresar',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
              return;
            }
            Scaffold.maybeOf(context)?.openDrawer();
          },
        ),
        actions: [
          if (_searchQuery.isNotEmpty)
            IconButton(
              tooltip: 'Limpiar búsqueda',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() => _searchQuery = ''),
            ),
          IconButton(
            tooltip: 'Buscar',
            icon: const Icon(Icons.search_rounded),
            onPressed: state.items.isEmpty
                ? null
                : () async {
                    final result = await showSearch<String?>(
                      context: context,
                      delegate: _PublicidadSearchDelegate(
                        items: state.items,
                        initialQuery: _searchQuery,
                      ),
                    );
                    if (!mounted || result == null) return;
                    setState(() => _searchQuery = result.trim());
                  },
          ),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: state.loading ? null : () => controller.load(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (state.loading || _isUploading) ? null : _openAddMenu,
        backgroundColor: _isUploading
            ? const Color(0xFF9F67FF)
            : const Color(0xFF7C3AED),
        foregroundColor: Colors.white,
        icon: _isUploading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.add_photo_alternate_rounded),
        label: Text(
          _isUploading
              ? (_uploadTotal > 1
                    ? 'Subiendo $_uploadCurrent/$_uploadTotal...'
                    : 'Subiendo...')
              : 'Agregar imagen',
        ),
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: () => controller.load(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                // Header info chip
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3E8FF),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFD8B4FE)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.campaign_rounded,
                                size: 16,
                                color: Color(0xFF7C3AED),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${visibleItems.length} elemento${visibleItems.length != 1 ? 's' : ''} para publicidad',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF7C3AED),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SizedBox(
                          width: 150,
                          child: _FilterDropdown<MediaGalleryTypeFilter>(
                            value: _galleryTypeFilter,
                            items: MediaGalleryTypeFilter.values,
                            labelBuilder: _typeFilterLabel,
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() => _galleryTypeFilter = value);
                            },
                          ),
                        ),
                        SizedBox(
                          width: 170,
                          child:
                              _FilterDropdown<MediaGalleryInstallationFilter>(
                                value: _galleryInstallationFilter,
                                items: MediaGalleryInstallationFilter.values,
                                labelBuilder: _installationFilterLabel,
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(
                                    () => _galleryInstallationFilter = value,
                                  );
                                },
                              ),
                        ),
                        SizedBox(
                          width: 170,
                          child: _FilterDropdown<ServiceOrderStatus?>(
                            value: _galleryOrderStatusFilter,
                            items: <ServiceOrderStatus?>[
                              null,
                              ...ServiceOrderStatus.values,
                            ],
                            labelBuilder: (status) =>
                                status?.label ?? 'Todo estado',
                            onChanged: (value) {
                              setState(() => _galleryOrderStatusFilter = value);
                            },
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _galleryTypeFilter = MediaGalleryTypeFilter.all;
                              _galleryInstallationFilter =
                                  MediaGalleryInstallationFilter.all;
                              _galleryOrderStatusFilter = null;
                            });
                          },
                          icon: const Icon(
                            Icons.filter_alt_off_rounded,
                            size: 16,
                          ),
                          label: const Text('Limpiar filtros'),
                        ),
                      ],
                    ),
                  ),
                ),

                // Loading / Error / Empty / Grid states
                if (state.loading && state.items.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if ((state.error ?? '').isNotEmpty && state.items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                      icon: Icons.campaign_outlined,
                      title: 'No se pudo cargar',
                      message: state.error!,
                      actionLabel: 'Reintentar',
                      onAction: () => controller.load(),
                    ),
                  )
                else if (visibleItems.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(
                      icon: Icons.campaign_outlined,
                      title: 'Sin elementos de publicidad',
                      message: _searchQuery.trim().isNotEmpty
                          ? 'No hay coincidencias con la búsqueda.'
                          : 'Desde la Galería Media, un administrador puede marcar\nevidencias para que aparezcan aquí.',
                      actionLabel: _searchQuery.trim().isNotEmpty
                          ? 'Limpiar búsqueda'
                          : null,
                      onAction: _searchQuery.trim().isNotEmpty
                          ? () => setState(() => _searchQuery = '')
                          : null,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.crossAxisExtent;
                        final crossAxisCount = width >= 1600
                            ? 6
                            : width >= 1300
                            ? 5
                            : width >= 980
                            ? 4
                            : width >= 700
                            ? 3
                            : 2;
                        final childAspectRatio = width >= 1300
                            ? 1.02
                            : width >= 980
                            ? 0.96
                            : width >= 700
                            ? 0.9
                            : 0.84;

                        return SliverGrid(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final item = visibleItems[index];
                            return MediaGalleryCard(
                              item: item,
                              isAdmin: true,
                              onTap: () => showMediaGalleryViewer(
                                context,
                                visibleItems,
                                index,
                                _downloadItem,
                              ),
                              onDownload: () => _downloadItem(item),
                              onDelete: () => _confirmRemove(item),
                            );
                          }, childCount: visibleItems.length),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: childAspectRatio,
                              ),
                        );
                      },
                    ),
                  ),

                // ─── Section: Own Publicidad Images ──────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                    child: Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'Imágenes subidas directamente',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: const Color(0xFF7C3AED),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                  ),
                ),
                if (ownImagesState.isLoading)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else if (ownImagesState.hasError)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No se pudo cargar las imágenes subidas.',
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      ),
                    ),
                  )
                else if ((ownImagesState.value ?? []).isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
                      child: Center(
                        child: Column(
                          children: [
                            const Icon(
                              Icons.add_photo_alternate_outlined,
                              size: 40,
                              color: Color(0xFFCBD5E1),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Sin imágenes subidas aún.',
                              style: TextStyle(color: Color(0xFF94A3B8)),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Usa el botón + para agregar imágenes de publicidad.',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 48),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.crossAxisExtent;
                        final crossAxisCount = width >= 1600
                            ? 6
                            : width >= 1300
                            ? 5
                            : width >= 980
                            ? 4
                            : width >= 700
                            ? 3
                            : 2;

                        return SliverGrid(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final img = ownImagesState.value![index];
                            return _PublicidadImageCard(
                              image: img,
                              onDelete: () => _confirmDeleteOwn(img),
                            );
                          }, childCount: ownImagesState.value!.length),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 12,
                                childAspectRatio: width >= 980 ? 1.0 : 0.9,
                              ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          // Upload loading overlay
          if (_isUploading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 24,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            color: Color(0xFF7C3AED),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _uploadTotal > 1
                                ? 'Subiendo imagen $_uploadCurrent de $_uploadTotal...'
                                : 'Subiendo imagen...',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatUploadError(Object error, {required String endpoint}) {
    if (error is ApiException) {
      final status = error.code?.toString() ?? 'n/a';
      final body = (error.responseBody ?? '').trim();
      final bodySummary = body.isEmpty ? 'n/a' : body;
      return 'statusCode=$status endpoint=$endpoint body=$bodySummary';
    }
    if (error is DioException) {
      final status = error.response?.statusCode?.toString() ?? 'n/a';
      final body = (error.response?.data ?? '').toString();
      final bodySummary = body.trim().isEmpty ? 'n/a' : body;
      return 'statusCode=$status endpoint=$endpoint body=$bodySummary';
    }
    return 'endpoint=$endpoint error=$error';
  }
}

// ─── Publicidad Image Card ───────────────────────────────────────────────────

class _PublicidadImageCard extends StatelessWidget {
  const _PublicidadImageCard({required this.image, required this.onDelete});

  final PublicidadImage image;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  image.url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      size: 40,
                      color: Color(0xFFCBD5E1),
                    ),
                  ),
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return const Center(child: CircularProgressIndicator());
                  },
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Material(
                    color: Colors.transparent,
                    child: Ink(
                      decoration: const BoxDecoration(
                        color: Color(0xCCDC2626),
                        shape: BoxShape.circle,
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: onDelete,
                        child: const Padding(
                          padding: EdgeInsets.all(6),
                          child: Icon(
                            Icons.delete_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (image.caption != null && image.caption!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Text(
                image.caption!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
              ),
            ),
        ],
      ),
    );
  }
}

class _PublicidadSearchDelegate extends SearchDelegate<String?> {
  _PublicidadSearchDelegate({required this.items, String initialQuery = ''}) {
    query = initialQuery;
  }

  final List<MediaGalleryItem> items;

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          tooltip: 'Limpiar',
          icon: const Icon(Icons.clear_rounded),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      tooltip: 'Regresar',
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    close(context, query.trim());
    return const SizedBox.shrink();
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final q = query.trim().toLowerCase();
    final results = q.isEmpty
        ? items
        : items.where((i) => i.searchableText.contains(q)).toList();
    if (results.isEmpty) {
      return const Center(child: Text('Sin resultados'));
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: results.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = results[index];
        return ListTile(
          leading: const Icon(Icons.campaign_outlined),
          title: Text(item.displayComment),
          subtitle: Text('Orden: ${item.orderId.substring(0, 8)}...'),
          onTap: () => close(context, item.searchableText),
        );
      },
    );
  }
}

// ─── Empty / Error State ─────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: const Color(0xFF94A3B8)),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: Color(0xFF475569),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: const TextStyle(color: Color(0xFF64748B)),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Upload Dialog ───────────────────────────────────────────────────────────

class _UploadDialogResult {
  final Uint8List? bytes;
  final String? url;
  final String? caption;
  final String? contentType;
  final String? filename;

  _UploadDialogResult({
    this.bytes,
    this.url,
    this.caption,
    this.contentType,
    this.filename,
  });
}

class _UploadPublicidadDialog extends StatefulWidget {
  const _UploadPublicidadDialog();

  @override
  State<_UploadPublicidadDialog> createState() =>
      _UploadPublicidadDialogState();
}

class _UploadPublicidadDialogState extends State<_UploadPublicidadDialog> {
  final _captionController = TextEditingController();
  final _urlController = TextEditingController();
  List<XFile> _pickedFiles = [];
  bool _useUrl = false;
  bool _isReadingFile = false;
  static const _allowedExtensions = {'jpg', 'jpeg', 'png', 'webp'};

  @override
  void dispose() {
    _captionController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    if (_isReadingFile) return;
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 85);
    if (picked.isNotEmpty && mounted) {
      final filtered = picked
          .where((file) {
            final ext = file.name.split('.').last.toLowerCase();
            return _allowedExtensions.contains(ext);
          })
          .toList(growable: false);
      if (filtered.length != picked.length) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Se omitieron archivos no permitidos. Solo JPG, JPEG, PNG y WEBP.',
            ),
          ),
        );
      }
      setState(() {
        _pickedFiles = filtered;
        _useUrl = false;
      });
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit || _isReadingFile) return;

    if (_useUrl) {
      final url = _urlController.text.trim();
      if (url.isEmpty) return;
      Navigator.of(context).pop(<_UploadDialogResult>[
        _UploadDialogResult(
          url: url,
          caption: _captionController.text.trim().isEmpty
              ? null
              : _captionController.text.trim(),
        ),
      ]);
      return;
    }

    // Read bytes for ALL picked files using XFile.readAsBytes() — works with
    // content:// URIs on Android and sandbox paths on iOS.
    setState(() => _isReadingFile = true);
    try {
      const contentTypeMap = {
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'webp': 'image/webp',
      };
      final results = <_UploadDialogResult>[];
      for (final file in _pickedFiles) {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          throw Exception('Archivo vacío detectado: ${file.name}');
        }
        final ext = file.name.split('.').last.toLowerCase();
        if (!_allowedExtensions.contains(ext)) {
          throw Exception('Extensión no permitida para ${file.name}');
        }
        results.add(
          _UploadDialogResult(
            bytes: bytes,
            caption: _captionController.text.trim().isEmpty
                ? null
                : _captionController.text.trim(),
            contentType: contentTypeMap[ext] ?? 'image/jpeg',
            filename: file.name,
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isReadingFile = false);
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('No se pudo leer la imagen: $e')));
    }
  }

  bool get _canSubmit {
    if (_useUrl) return _urlController.text.trim().isNotEmpty;
    return _pickedFiles.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar imagen a publicidad'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: _ModeButton(
                    label: 'Desde galería',
                    icon: Icons.photo_library_rounded,
                    selected: !_useUrl,
                    onTap: () => setState(() => _useUrl = false),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ModeButton(
                    label: 'Por URL',
                    icon: Icons.link_rounded,
                    selected: _useUrl,
                    onTap: () => setState(() => _useUrl = true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!_useUrl) ...[
              if (_pickedFiles.isEmpty)
                OutlinedButton.icon(
                  onPressed: _pickImages,
                  icon: const Icon(Icons.add_photo_alternate_rounded),
                  label: const Text('Seleccionar imagen(es)'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                )
              else
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF16A34A),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _pickedFiles.length == 1
                            ? _pickedFiles.first.name
                            : '${_pickedFiles.length} imágenes seleccionadas',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: _pickImages,
                      child: const Text('Cambiar'),
                    ),
                  ],
                ),
            ] else ...[
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'URL de la imagen',
                  hintText: 'https://ejemplo.com/imagen.jpg',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link_rounded),
                ),
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _captionController,
              decoration: const InputDecoration(
                labelText: 'Descripción (opcional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.text_fields_rounded),
              ),
              maxLines: 2,
              maxLength: 200,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isReadingFile
              ? null
              : () => Navigator.of(context).pop(null),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: (_canSubmit && !_isReadingFile) ? _submit : null,
          icon: _isReadingFile
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.upload_rounded),
          label: Text(_isReadingFile ? 'Preparando...' : 'Agregar'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF7C3AED),
          ),
        ),
      ],
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFF3E8FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF7C3AED) : const Color(0xFFCBD5E1),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected
                  ? const Color(0xFF7C3AED)
                  : const Color(0xFF64748B),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: selected
                    ? const Color(0xFF7C3AED)
                    : const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PublicidadAddSource { manual, mediaGallery, products }

class _FilterDropdown<T> extends StatelessWidget {
  const _FilterDropdown({
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final String Function(T value) labelBuilder;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: const InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(),
      ),
      items: items
          .map(
            (item) => DropdownMenuItem<T>(
              value: item,
              child: Text(
                labelBuilder(item),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          )
          .toList(growable: false),
      onChanged: onChanged,
    );
  }
}

class _SelectMediaForPublicidadDialog extends ConsumerStatefulWidget {
  const _SelectMediaForPublicidadDialog();

  @override
  ConsumerState<_SelectMediaForPublicidadDialog> createState() =>
      _SelectMediaForPublicidadDialogState();
}

class _SelectMediaForPublicidadDialogState
    extends ConsumerState<_SelectMediaForPublicidadDialog> {
  bool _loading = true;
  String _error = '';
  String _query = '';
  List<MediaGalleryItem> _items = const [];
  final Set<String> _selectedIds = <String>{};
  MediaGalleryTypeFilter _typeFilter = MediaGalleryTypeFilter.all;
  MediaGalleryInstallationFilter _installationFilter =
      MediaGalleryInstallationFilter.all;
  ServiceOrderStatus? _statusFilter;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final repository = ref.read(mediaGalleryRepositoryProvider);
      final collected = <MediaGalleryItem>[];
      String? cursor;
      var pageCount = 0;
      while (pageCount < 8) {
        final page = await repository.fetchPage(
          limit: 120,
          cursor: cursor,
          silent: true,
          typeFilter: MediaGalleryTypeFilter.all,
          installationFilter: MediaGalleryInstallationFilter.all,
        );
        collected.addAll(page.items);
        cursor = page.nextCursor;
        pageCount++;
        if (cursor == null || cursor.isEmpty) break;
      }
      if (!mounted) return;
      setState(() {
        _items = collected;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar la galería de contenido.';
      });
    }
  }

  List<MediaGalleryItem> get _visibleItems {
    final q = _query.trim().toLowerCase();
    return _items
        .where((item) {
          if (q.isNotEmpty && !item.searchableText.contains(q)) return false;
          if (_typeFilter == MediaGalleryTypeFilter.image && !item.isImage) {
            return false;
          }
          if (_typeFilter == MediaGalleryTypeFilter.video && !item.isVideo) {
            return false;
          }
          if (_installationFilter == MediaGalleryInstallationFilter.completed &&
              !item.isInstallationCompleted) {
            return false;
          }
          if (_installationFilter == MediaGalleryInstallationFilter.pending &&
              item.isInstallationCompleted) {
            return false;
          }
          if (_statusFilter != null && item.orderStatus != _statusFilter) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleItems;
    return AlertDialog(
      title: const Text('Agregar desde galería de contenido'),
      content: SizedBox(
        width: 920,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Buscar por comentario, estado u orden',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 150,
                  child: _FilterDropdown<MediaGalleryTypeFilter>(
                    value: _typeFilter,
                    items: MediaGalleryTypeFilter.values,
                    labelBuilder: (value) {
                      switch (value) {
                        case MediaGalleryTypeFilter.all:
                          return 'Todo tipo';
                        case MediaGalleryTypeFilter.image:
                          return 'Imagen';
                        case MediaGalleryTypeFilter.video:
                          return 'Video';
                      }
                    },
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _typeFilter = value);
                    },
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: _FilterDropdown<MediaGalleryInstallationFilter>(
                    value: _installationFilter,
                    items: MediaGalleryInstallationFilter.values,
                    labelBuilder: (value) {
                      switch (value) {
                        case MediaGalleryInstallationFilter.all:
                          return 'Toda instalación';
                        case MediaGalleryInstallationFilter.completed:
                          return 'Instalado';
                        case MediaGalleryInstallationFilter.pending:
                          return 'Pendiente';
                      }
                    },
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _installationFilter = value);
                    },
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: _FilterDropdown<ServiceOrderStatus?>(
                    value: _statusFilter,
                    items: <ServiceOrderStatus?>[
                      null,
                      ...ServiceOrderStatus.values,
                    ],
                    labelBuilder: (value) => value?.label ?? 'Todo estado',
                    onChanged: (value) => setState(() => _statusFilter = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 380,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error.isNotEmpty
                  ? Center(child: Text(_error))
                  : visible.isEmpty
                  ? const Center(
                      child: Text('No hay elementos con esos filtros.'),
                    )
                  : ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = visible[index];
                        final alreadyInPublicidad = item.forPublicidad;
                        final selected = _selectedIds.contains(item.id);
                        return CheckboxListTile(
                          dense: true,
                          value: selected,
                          controlAffinity: ListTileControlAffinity.trailing,
                          onChanged: (value) {
                            if (alreadyInPublicidad) return;
                            setState(() {
                              if (value == true) {
                                _selectedIds.add(item.id);
                              } else {
                                _selectedIds.remove(item.id);
                              }
                            });
                          },
                          secondary: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              item.url,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                          title: Text(
                            item.displayComment,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            alreadyInPublicidad
                                ? '${item.orderStatusLabel} · ${item.installationLabel} · Ya en publicidad'
                                : '${item.orderStatusLabel} · ${item.installationLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: alreadyInPublicidad
                                  ? const Color(0xFF7C3AED)
                                  : null,
                            ),
                          ),
                          enabled: !alreadyInPublicidad,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _selectedIds.isEmpty
              ? null
              : () => Navigator.of(
                  context,
                ).pop(_selectedIds.toList(growable: false)),
          icon: const Icon(Icons.add_circle_outline_rounded),
          label: Text('Agregar (${_selectedIds.length})'),
        ),
      ],
    );
  }
}

class _ProductForPublicidadCandidate {
  const _ProductForPublicidadCandidate({
    required this.url,
    required this.caption,
  });

  final String url;
  final String caption;
}

class _SelectProductsForPublicidadDialog extends ConsumerStatefulWidget {
  const _SelectProductsForPublicidadDialog();

  @override
  ConsumerState<_SelectProductsForPublicidadDialog> createState() =>
      _SelectProductsForPublicidadDialogState();
}

class _SelectProductsForPublicidadDialogState
    extends ConsumerState<_SelectProductsForPublicidadDialog> {
  bool _loading = true;
  String _error = '';
  String _query = '';
  bool _onlyWithImage = true;
  bool _onlyActive = true;
  List<ProductModel> _products = const [];
  final Set<String> _selectedIds = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final rows = await ref
          .read(catalogRepositoryProvider)
          .fetchProducts(silent: true);
      if (!mounted) return;
      setState(() {
        _products = rows;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar el catálogo de productos.';
      });
    }
  }

  List<ProductModel> get _visibleProducts {
    final q = _query.trim().toLowerCase();
    return _products
        .where((product) {
          if (_onlyActive && !product.activo) return false;
          final image = (product.displayFotoUrl ?? '').trim();
          if (_onlyWithImage && image.isEmpty) return false;
          if (q.isEmpty) return true;
          return product.nombre.toLowerCase().contains(q) ||
              (product.descripcion ?? '').toLowerCase().contains(q) ||
              (product.codigo ?? '').toLowerCase().contains(q) ||
              (product.categoria ?? '').toLowerCase().contains(q);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleProducts;
    return AlertDialog(
      title: const Text('Agregar desde productos'),
      content: SizedBox(
        width: 920,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Buscar producto por nombre, código o categoría',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  selected: _onlyActive,
                  onSelected: (value) => setState(() => _onlyActive = value),
                  label: const Text('Solo activos'),
                ),
                FilterChip(
                  selected: _onlyWithImage,
                  onSelected: (value) => setState(() => _onlyWithImage = value),
                  label: const Text('Solo con imagen'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 380,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error.isNotEmpty
                  ? Center(child: Text(_error))
                  : visible.isEmpty
                  ? const Center(
                      child: Text('No hay productos con esos filtros.'),
                    )
                  : ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final product = visible[index];
                        final selected = _selectedIds.contains(product.id);
                        final imageUrl = _bestProductImageUrl(product);
                        return ListTile(
                          dense: true,
                          enabled: imageUrl.isNotEmpty,
                          onTap: imageUrl.isEmpty
                              ? null
                              : () {
                                  setState(() {
                                    if (selected) {
                                      _selectedIds.remove(product.id);
                                    } else {
                                      _selectedIds.add(product.id);
                                    }
                                  });
                                },
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: imageUrl.isEmpty
                                ? Container(
                                    width: 48,
                                    height: 48,
                                    color: const Color(0xFFE2E8F0),
                                    child: const Icon(
                                      Icons.image_not_supported_outlined,
                                    ),
                                  )
                                : SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: ProductNetworkImage(
                                      imageUrl: imageUrl,
                                      productId: product.id,
                                      productName: product.nombre,
                                      originalUrl: product.originalFotoUrl,
                                      fit: BoxFit.cover,
                                      loading: Container(
                                        color: const Color(0xFFE2E8F0),
                                        alignment: Alignment.center,
                                        child: const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                      fallback: Container(
                                        color: const Color(0xFFE2E8F0),
                                        alignment: Alignment.center,
                                        child: const Icon(
                                          Icons.broken_image_outlined,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                          title: Text(
                            product.nombre,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            product.categoriaLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Checkbox(
                            value: selected,
                            onChanged: imageUrl.isEmpty
                                ? null
                                : (value) {
                                    setState(() {
                                      if (value == true) {
                                        _selectedIds.add(product.id);
                                      } else {
                                        _selectedIds.remove(product.id);
                                      }
                                    });
                                  },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _selectedIds.isEmpty
              ? null
              : () {
                  final selected = _products
                      .where((p) => _selectedIds.contains(p.id))
                      .map(
                        (p) => _ProductForPublicidadCandidate(
                          url: _bestProductImageUrl(p),
                          caption: p.nombre,
                        ),
                      )
                      .where((candidate) => candidate.url.trim().isNotEmpty)
                      .toList(growable: false);
                  Navigator.of(context).pop(selected);
                },
          icon: const Icon(Icons.add_circle_outline_rounded),
          label: Text('Agregar (${_selectedIds.length})'),
        ),
      ],
    );
  }

  String _bestProductImageUrl(ProductModel product) {
    final candidates = <String?>[
      product.originalFotoUrl,
      product.fotoUrl,
      product.displayFotoUrl,
    ];
    for (final candidate in candidates) {
      final value = candidate?.trim() ?? '';
      if (value.isEmpty) continue;
      if (value.startsWith('http://') || value.startsWith('https://')) {
        return value;
      }
      final base = Env.apiBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
      if (base.isNotEmpty) {
        final normalized = value.startsWith('/') ? value : '/$value';
        return '$base$normalized';
      }
    }
    return '';
  }
}
