import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../models/gallery_content_model.dart';

class GaleriaPublicidadScreen extends ConsumerStatefulWidget {
  const GaleriaPublicidadScreen({super.key});

  @override
  ConsumerState<GaleriaPublicidadScreen> createState() =>
      _GaleriaPublicidadScreenState();
}

class _GaleriaPublicidadScreenState
    extends ConsumerState<GaleriaPublicidadScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  String? _selectedItemId;
  bool _showImportMenu = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _loadMore() {
    // ref.read(_galleryContentControllerProvider.notifier).loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final user = auth.user;
    final isAdmin =
        user != null &&
        hasPermission(user.appRole, AppPermission.viewPublicidad);

    if (!isAdmin) {
      return Scaffold(
        appBar: const CustomAppBar(
          title: 'Galería de Publicidad',
          showLogo: false,
        ),
        body: const Center(
          child: Text('Acceso denegado. Solo ADMIN puede usar Publicidad.'),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: const CustomAppBar(
        title: 'Galería de Publicidad',
        fallbackRoute: '/publicidad',
      ),
      backgroundColor: scheme.surfaceContainerLowest,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [scheme.surface, scheme.surfaceContainerLowest],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header with search and import button
              Padding(
                padding: const EdgeInsets.all(12),
                child: _GalleryHeader(
                  searchController: _searchController,
                  onShowImportMenu: () =>
                      setState(() => _showImportMenu = !_showImportMenu),
                  showImportMenu: _showImportMenu,
                ),
              ),
              // Main content: sidebar + grid + detail panel
              Expanded(
                child: Row(
                  children: [
                    // LEFT SIDEBAR - Filters
                    _GallerySidebar(
                      onFilterSelected: (filterId) {
                        setState(() => _selectedItemId = null);
                        // ref
                        //     .read(_galleryContentControllerProvider.notifier)
                        //     .setFilter(filterId);
                      },
                    ),
                    // CENTER - Grid
                    Expanded(
                      flex: 3,
                      child: _GalleryGrid(
                        scrollController: _scrollController,
                        selectedItemId: _selectedItemId,
                        onItemSelected: (itemId) {
                          setState(() => _selectedItemId = itemId);
                        },
                      ),
                    ),
                    // RIGHT PANEL - Item Details
                    if (_selectedItemId != null)
                      _GalleryDetailPanel(
                        itemId: _selectedItemId!,
                        onClose: () => setState(() => _selectedItemId = null),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Header with Search & Import ───────────────────────────────────────────

class _GalleryHeader extends StatelessWidget {
  const _GalleryHeader({
    required this.searchController,
    required this.onShowImportMenu,
    required this.showImportMenu,
  });

  final TextEditingController searchController;
  final VoidCallback onShowImportMenu;
  final bool showImportMenu;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          spacing: 12,
          children: [
            // Search field
            Expanded(
              child: TextField(
                controller: searchController,
                decoration: InputDecoration(
                  hintText: 'Buscar contenido...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            searchController.clear();
                            // ref
                            //     .read(_galleryContentControllerProvider.notifier)
                            //     .clearSearch();
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
                onChanged: (query) {
                  // ref
                  //     .read(_galleryContentControllerProvider.notifier)
                  //     .setSearchQuery(query);
                },
              ),
            ),
            // Import button
            PopupMenuButton<String>(
              onSelected: (source) {
                _handleImportSource(context, source);
              },
              itemBuilder: (_) => ContentImportSource.sources
                  .map(
                    (source) => PopupMenuItem(
                      value: source.id,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${source.icon} ${source.name}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            source.descripcion,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
              child: FilledButton.icon(
                onPressed: onShowImportMenu,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Importar'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _handleImportSource(BuildContext context, String sourceId) {
    // Implement import logic based on source
    // This would show dialogs for selecting products, uploading files, etc.
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Importación desde: $sourceId')));
  }
}

// ─── Left Sidebar - Filters ──────────────────────────────────────────────────

class _GallerySidebar extends StatefulWidget {
  const _GallerySidebar({required this.onFilterSelected});

  final Function(String) onFilterSelected;

  @override
  State<_GallerySidebar> createState() => _GallerySidebarState();
}

class _GallerySidebarState extends State<_GallerySidebar> {
  String _selectedFilterId = 'todo';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 280,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Filtros',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          ..._buildFilterButtons(),
        ],
      ),
    );
  }

  List<Widget> _buildFilterButtons() {
    return GalleryFilter.allFilters.map((filter) {
      final isSelected = _selectedFilterId == filter.id;
      final scheme = Theme.of(context).colorScheme;

      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: isSelected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () {
              setState(() => _selectedFilterId = filter.id);
              widget.onFilterSelected(filter.id);
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                spacing: 8,
                children: [
                  if (filter.icon != null)
                    Text(filter.icon!, style: const TextStyle(fontSize: 16)),
                  Expanded(
                    child: Text(
                      filter.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: isSelected ? scheme.primary : scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }
}

// ─── Center Grid ────────────────────────────────────────────────────────────

class _GalleryGrid extends ConsumerWidget {
  const _GalleryGrid({
    required this.scrollController,
    required this.selectedItemId,
    required this.onItemSelected,
  });

  final ScrollController scrollController;
  final String? selectedItemId;
  final Function(String) onItemSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // TODO: Conectar con el estado del controlador
    // final state = ref.watch(_galleryContentControllerProvider);

    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(12),
            sliver: SliverGrid.count(
              crossAxisCount: _getCrossAxisCount(context),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.8,
              children: List.generate(
                12, // TODO: Replace with actual items count
                (index) => _GalleryGridItem(
                  index: index,
                  isSelected: selectedItemId == 'item-$index',
                  onTap: () => onItemSelected('item-$index'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  int _getCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 1200) return 2;
    if (width < 1600) return 3;
    return 4;
  }
}

// ─── Grid Item Card ─────────────────────────────────────────────────────────

class _GalleryGridItem extends StatefulWidget {
  const _GalleryGridItem({
    required this.index,
    required this.isSelected,
    required this.onTap,
  });

  final int index;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<_GalleryGridItem> createState() => _GalleryGridItemState();
}

class _GalleryGridItemState extends State<_GalleryGridItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: widget.isSelected
                  ? scheme.primary
                  : (_isHovered ? scheme.outline : scheme.outlineVariant),
              width: widget.isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
            color: scheme.surfaceContainer,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Image/Video placeholder
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(7),
                  ),
                ),
                child: Center(
                  child: Icon(
                    widget.index % 3 == 0 ? Icons.image : Icons.videocam,
                    size: 32,
                    color: scheme.outline,
                  ),
                ),
              ),
              // Info & Badges
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top badges
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: [
                        _Badge(
                          label: widget.index % 3 == 0 ? '🖼️' : '🎥',
                          size: 'small',
                        ),
                        if (widget.index % 2 == 0)
                          _Badge(label: '📦 Producto', size: 'small'),
                        if (widget.index % 4 == 0)
                          _Badge(label: '⭐', size: 'small'),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Bottom info
                  Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer.withOpacity(0.9),
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(7),
                      ),
                    ),
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(
                          'Contenido ${widget.index + 1}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Categoría • Hace 2 días',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Hover overlay
              if (_isHovered)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: FilledButton.tonal(
                      onPressed: widget.onTap,
                      child: const Text('Ver detalles'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Badge Component ────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.size});

  final String label;
  final String size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isSmall = size == 'small';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isSmall ? 6 : 8,
        vertical: isSmall ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: isSmall ? 10 : 11,
          fontWeight: FontWeight.w500,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

// ─── Right Detail Panel ──────────────────────────────────────────────────────

class _GalleryDetailPanel extends ConsumerWidget {
  const _GalleryDetailPanel({required this.itemId, required this.onClose});

  final String itemId;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    // TODO: Load actual item data based on itemId
    return Container(
      width: 360,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Detalles', style: Theme.of(context).textTheme.titleSmall),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // Large preview
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Icon(Icons.image, size: 64, color: scheme.outline),
                  ),
                ),
                const SizedBox(height: 16),
                // Metadata
                _MetadataField(label: 'Tipo', value: 'Imagen'),
                _MetadataField(label: 'Categoría', value: 'Instalaciones'),
                _MetadataField(label: 'Origen', value: 'Manual', badge: true),
                const SizedBox(height: 8),
                _MetadataField(
                  label: 'Descripción',
                  value: 'Descripción del contenido...',
                ),
                const SizedBox(height: 8),
                _MetadataField(label: 'Tags', value: 'tag1, tag2, tag3'),
                const SizedBox(height: 16),
                // Usado en
                Text(
                  'Usado en',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _UsageChip(label: 'Estados', selected: true),
                    _UsageChip(label: 'Campañas', selected: false),
                    _UsageChip(label: 'Marketplace', selected: false),
                  ],
                ),
                const SizedBox(height: 16),
                // Action buttons
                FilledButton.tonal(
                  onPressed: () {},
                  child: const Text('Editar metadatos'),
                ),
                const SizedBox(height: 8),
                FilledButton.tonal(
                  onPressed: () {},
                  child: const Text('Agregar a favoritos'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () {}, child: const Text('Eliminar')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Metadata Field ────────────────────────────────────────────────────────

class _MetadataField extends StatelessWidget {
  const _MetadataField({
    required this.label,
    required this.value,
    this.badge = false,
  });

  final String label;
  final String value;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 4,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        if (badge)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              value,
              style: TextStyle(fontSize: 12, color: scheme.onTertiaryContainer),
            ),
          )
        else
          Text(
            value,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

// ─── Usage Chip ────────────────────────────────────────────────────────────

class _UsageChip extends StatelessWidget {
  const _UsageChip({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? scheme.secondaryContainer : scheme.surfaceContainer,
        border: Border.all(
          color: selected ? scheme.secondary : scheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: selected
              ? scheme.onSecondaryContainer
              : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
