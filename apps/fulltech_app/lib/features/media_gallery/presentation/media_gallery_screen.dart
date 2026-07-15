import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/app_role.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/utils/media_file_actions.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../application/media_gallery_controller.dart';
import '../media_gallery_models.dart';
import '../widgets/media_gallery_card.dart';

class MediaGalleryScreen extends ConsumerStatefulWidget {
  const MediaGalleryScreen({super.key});

  @override
  ConsumerState<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends ConsumerState<MediaGalleryScreen> {
  late final ScrollController _scrollController;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter > 720) return;
    ref.read(mediaGalleryControllerProvider.notifier).loadMore();
  }

  List<MediaGalleryItem> _applySearch(List<MediaGalleryItem> items) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return items;
    return items
        .where((item) => item.searchableText.contains(query))
        .toList(growable: false);
  }

  Future<void> _openSearch(List<MediaGalleryItem> items) async {
    final result = await showSearch<String?>(
      context: context,
      delegate: _MediaGallerySearchDelegate(
        items: items,
        initialQuery: _searchQuery,
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _searchQuery = result.trim();
    });
  }

  Future<void> _openFilters(MediaGalleryState state) async {
    var tempType = state.typeFilter;
    var tempInstallation = state.installationFilter;
    final controller = ref.read(mediaGalleryControllerProvider.notifier);

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (bottomSheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filtrar galería',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text('Tipo de archivo'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: MediaGalleryTypeFilter.values
                          .map((filter) {
                            return ChoiceChip(
                              label: Text(_typeFilterLabel(filter)),
                              selected: tempType == filter,
                              onSelected: (_) {
                                setModalState(() {
                                  tempType = filter;
                                });
                              },
                            );
                          })
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 16),
                    const Text('Estado de instalación'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: MediaGalleryInstallationFilter.values
                          .map((filter) {
                            return ChoiceChip(
                              label: Text(_installationFilterLabel(filter)),
                              selected: tempInstallation == filter,
                              onSelected: (_) {
                                setModalState(() {
                                  tempInstallation = filter;
                                });
                              },
                            );
                          })
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              controller.setTypeFilter(
                                MediaGalleryTypeFilter.all,
                              );
                              controller.setInstallationFilter(
                                MediaGalleryInstallationFilter.all,
                              );
                              Navigator.of(bottomSheetContext).pop();
                            },
                            child: const Text('Limpiar'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              controller.setTypeFilter(tempType);
                              controller.setInstallationFilter(
                                tempInstallation,
                              );
                              Navigator.of(bottomSheetContext).pop();
                            },
                            child: const Text('Aplicar'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
      // Retry below with a stream fallback for desktop/network variance.
    }

    final response = await dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        extra: const {'skipLoader': true, 'silent': true},
      ),
    );
    final body = response.data;
    if (body == null) {
      throw Exception('El servidor no devolvió contenido');
    }

    final builder = BytesBuilder(copy: false);
    await for (final chunk in body.stream) {
      builder.add(chunk);
    }
    final bytes = builder.takeBytes();
    if (bytes.isEmpty) {
      throw Exception('El archivo llegó vacío');
    }
    return bytes;
  }

  Future<void> _confirmDelete(MediaGalleryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar evidencia'),
        content: const Text(
          '¿Estás seguro de que deseas eliminar esta evidencia?\n'
          'Esta acción no se puede deshacer.',
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
    await ref.read(mediaGalleryControllerProvider.notifier).deleteItem(item.id);
    if (!mounted) return;
    final errorState = ref.read(mediaGalleryControllerProvider).error;
    if ((errorState ?? '').isEmpty) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Evidencia eliminada correctamente.')),
      );
    } else {
      messenger?.showSnackBar(SnackBar(content: Text(errorState!)));
    }
  }

  Future<void> _confirmMarkPublicidad(MediaGalleryItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pasar a publicidad'),
        content: const Text(
          '¿Estás seguro de pasar esta evidencia a la Galería de Publicidad?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await ref
        .read(mediaGalleryControllerProvider.notifier)
        .markForPublicidad(item.id);
    if (!mounted) return;
    final errorState = ref.read(mediaGalleryControllerProvider).error;
    if ((errorState ?? '').isEmpty) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('Evidencia marcada para publicidad.')),
      );
    } else {
      messenger?.showSnackBar(SnackBar(content: Text(errorState!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final canView =
        auth.isAuthenticated &&
        auth.user != null &&
        hasPermission(auth.user!.appRole, AppPermission.viewMediaGallery);
    final isAdmin = auth.user?.appRole == AppRole.admin;
    final state = ref.watch(mediaGalleryControllerProvider);
    final controller = ref.read(mediaGalleryControllerProvider.notifier);

    if (!canView) {
      return Scaffold(
        drawer: buildAdaptiveDrawer(context, currentUser: auth.user),
        appBar: const CustomAppBar(
          title: 'Galería media',
          showLogo: false,
          showDepartmentLabel: false,
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Esta pantalla está disponible solo para administración y marketing.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final visibleItems = _applySearch(state.visibleItems);
    final totalItems = state.items.length;
    final completedCount = state.items
        .where((item) => item.isInstallationCompleted)
        .length;
    final pendingCount = totalItems - completedCount;
    final activeFilterCount = [
      state.typeFilter != MediaGalleryTypeFilter.all,
      state.installationFilter != MediaGalleryInstallationFilter.all,
      _searchQuery.trim().isNotEmpty,
    ].where((item) => item).length;

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: auth.user),
      appBar: CustomAppBar(
        title: 'Galería media',
        showLogo: false,
        showDepartmentLabel: false,
        fallbackRoute: '/publicidad',
        actions: [
          IconButton(
            tooltip: 'Buscar',
            onPressed: state.items.isEmpty
                ? null
                : () => _openSearch(state.items),
            icon: const Icon(Icons.search_rounded),
          ),
          Stack(
            alignment: Alignment.topRight,
            children: [
              IconButton(
                tooltip: 'Filtrar',
                onPressed: () => _openFilters(state),
                icon: const Icon(Icons.tune_rounded),
              ),
              if (activeFilterCount > 0)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFACC15),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$activeFilterCount',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: state.refreshing ? null : () => controller.refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => controller.refresh(),
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                child: _GalleryTopBar(
                  totalItems: totalItems,
                  visibleItems: visibleItems.length,
                  completedCount: completedCount,
                  pendingCount: pendingCount,
                  searchQuery: _searchQuery,
                  typeFilter: state.typeFilter,
                  installationFilter: state.installationFilter,
                  onClearSearch: _searchQuery.trim().isEmpty
                      ? null
                      : () {
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                ),
              ),
            ),
            if (state.loading && state.items.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if ((state.error ?? '').trim().isNotEmpty &&
                state.items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _GalleryMessageState(
                  icon: Icons.perm_media_outlined,
                  title: 'No se pudo cargar la galería',
                  message: state.error!,
                  actionLabel: 'Reintentar',
                  onAction: () => controller.retry(),
                ),
              )
            else if (visibleItems.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _GalleryMessageState(
                  icon: Icons.photo_library_outlined,
                  title: 'No hay medios para mostrar',
                  message: _searchQuery.trim().isNotEmpty
                      ? 'Intenta con otra búsqueda o limpia los filtros activos.'
                      : 'Prueba otra combinación entre tipo de archivo y estado de instalación.',
                  actionLabel: 'Mostrar todo',
                  onAction: () {
                    setState(() {
                      _searchQuery = '';
                    });
                    controller.setTypeFilter(MediaGalleryTypeFilter.all);
                    controller.setInstallationFilter(
                      MediaGalleryInstallationFilter.all,
                    );
                  },
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.crossAxisExtent;
                    final crossAxisCount = width >= 1500
                        ? 5
                        : width >= 1200
                        ? 4
                        : width >= 860
                        ? 3
                        : 2;
                    final childAspectRatio = width >= 1200
                        ? 0.92
                        : width >= 860
                        ? 0.9
                        : width >= 420
                        ? 0.72
                        : 0.66;

                    return SliverGrid(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final item = visibleItems[index];
                        return MediaGalleryCard(
                          item: item,
                          isAdmin: isAdmin,
                          onTap: () => showMediaGalleryViewer(
                            context,
                            visibleItems,
                            index,
                            _downloadItem,
                          ),
                          onDownload: () => _downloadItem(item),
                          onDelete: isAdmin ? () => _confirmDelete(item) : null,
                          onMarkPublicidad: isAdmin && !item.forPublicidad
                              ? () => _confirmMarkPublicidad(item)
                              : null,
                        );
                      }, childCount: visibleItems.length),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: childAspectRatio,
                      ),
                    );
                  },
                ),
              ),
            if (state.loadingMore)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 28),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if ((state.nextCursor ?? '').trim().isEmpty &&
                visibleItems.isNotEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 32),
                  child: Center(
                    child: Text(
                      'No hay más elementos para cargar.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GalleryTopBar extends StatelessWidget {
  const _GalleryTopBar({
    required this.totalItems,
    required this.visibleItems,
    required this.completedCount,
    required this.pendingCount,
    required this.searchQuery,
    required this.typeFilter,
    required this.installationFilter,
    this.onClearSearch,
  });

  final int totalItems;
  final int visibleItems;
  final int completedCount;
  final int pendingCount;
  final String searchQuery;
  final MediaGalleryTypeFilter typeFilter;
  final MediaGalleryInstallationFilter installationFilter;
  final VoidCallback? onClearSearch;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      _TopMetricChip(label: 'Mostrando', value: '$visibleItems'),
      _TopMetricChip(label: 'Total', value: '$totalItems'),
      _TopMetricChip(label: 'Instalados', value: '$completedCount'),
      _TopMetricChip(label: 'Pendientes', value: '$pendingCount'),
    ];

    if (typeFilter != MediaGalleryTypeFilter.all) {
      chips.add(_ActiveFilterChip(label: _typeFilterLabel(typeFilter)));
    }
    if (installationFilter != MediaGalleryInstallationFilter.all) {
      chips.add(
        _ActiveFilterChip(label: _installationFilterLabel(installationFilter)),
      );
    }
    if (searchQuery.trim().isNotEmpty) {
      chips.add(
        _ActiveFilterChip(
          label: 'Búsqueda: "$searchQuery"',
          onClear: onClearSearch,
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < chips.length; index++) ...[
            if (index > 0) const SizedBox(width: 6),
            chips[index],
          ],
        ],
      ),
    );
  }
}

class _TopMetricChip extends StatelessWidget {
  const _TopMetricChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE5EE)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D0F172A),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.4,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({required this.label, this.onClear});

  final String label;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFE6F4F7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFC7E4EA)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.tune_rounded, size: 14, color: Color(0xFF0F5D73)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF0F5D73),
              fontSize: 10.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (onClear != null) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: onClear,
              borderRadius: BorderRadius.circular(999),
              child: const Padding(
                padding: EdgeInsets.all(2),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: Color(0xFF0F5D73),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GalleryMessageState extends StatelessWidget {
  const _GalleryMessageState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 42, color: theme.colorScheme.primary),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh),
                label: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _typeFilterLabel(MediaGalleryTypeFilter filter) {
  switch (filter) {
    case MediaGalleryTypeFilter.all:
      return 'Todos';
    case MediaGalleryTypeFilter.image:
      return 'Imágenes';
    case MediaGalleryTypeFilter.video:
      return 'Videos';
  }
}

String _installationFilterLabel(MediaGalleryInstallationFilter filter) {
  switch (filter) {
    case MediaGalleryInstallationFilter.all:
      return 'Todos';
    case MediaGalleryInstallationFilter.completed:
      return 'Instalados';
    case MediaGalleryInstallationFilter.pending:
      return 'Pendientes';
  }
}

class _MediaGallerySearchDelegate extends SearchDelegate<String?> {
  _MediaGallerySearchDelegate({
    required this.items,
    required String initialQuery,
  }) : super(searchFieldLabel: 'Buscar imagen, video u orden') {
    query = initialQuery;
  }

  final List<MediaGalleryItem> items;

  List<MediaGalleryItem> get _filteredItems {
    final normalizedQuery = query.trim().toLowerCase();
    final filtered = items
        .where((item) {
          if (normalizedQuery.isEmpty) return true;
          return item.searchableText.contains(normalizedQuery);
        })
        .toList(growable: false);
    filtered.sort((left, right) => right.createdAt.compareTo(left.createdAt));
    return filtered;
  }

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      appBarTheme: theme.appBarTheme.copyWith(toolbarHeight: 64),
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.trim().isNotEmpty)
        IconButton(
          tooltip: 'Limpiar búsqueda',
          onPressed: () {
            query = '';
            showSuggestions(context);
          },
          icon: const Icon(Icons.close_rounded),
        ),
      IconButton(
        tooltip: 'Aplicar búsqueda',
        onPressed: () => close(context, query.trim()),
        icon: const Icon(Icons.check_rounded),
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      tooltip: 'Cerrar',
      onPressed: () => close(context, null),
      icon: const Icon(Icons.arrow_back_rounded),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final filtered = _filteredItems;
    if (items.isEmpty) {
      return const Center(child: Text('No hay archivos disponibles'));
    }
    if (filtered.isEmpty) {
      return const Center(child: Text('No se encontraron coincidencias'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = filtered[index];
        final orderPreview = item.orderId.length > 8
            ? item.orderId.substring(0, 8).toUpperCase()
            : item.orderId.toUpperCase();

        return ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          tileColor: Theme.of(context).colorScheme.surfaceContainerLowest,
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFE6F4F7),
            child: Icon(
              item.isVideo ? Icons.play_circle_outline : Icons.image_outlined,
              color: const Color(0xFF0F5D73),
            ),
          ),
          title: Text(
            item.displayComment,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${item.orderStatusLabel} · ${item.isVideo ? 'Video' : 'Imagen'} · $orderPreview',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.arrow_forward_rounded),
          onTap: () => close(context, query.trim()),
        );
      },
    );
  }
}
