import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/product_network_image.dart';
import 'website_controller.dart';
import 'website_product_model.dart';

const _publicWebsiteUrl = 'https://fulltechrd.com/';
const _publicStoreUrl = 'https://fulltechrd.com/tienda.html';
const _publicShareMessage =
    'Hola, conoce FULLTECH SRL. Seguridad electronica, camaras, motores de portones, punto de venta y tecnologia en Higuey.\n\nPagina web: $_publicWebsiteUrl\nTienda online: $_publicStoreUrl';

class SitioWebScreen extends ConsumerStatefulWidget {
  const SitioWebScreen({super.key});

  @override
  ConsumerState<SitioWebScreen> createState() => _SitioWebScreenState();
}

class _SitioWebScreenState extends ConsumerState<SitioWebScreen> {
  final _searchCtrl = TextEditingController();
  String _status = 'Todos';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(websiteControllerProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final state = ref.watch(websiteControllerProvider);
    final query = _searchCtrl.text.trim().toLowerCase();
    final products = state.products.where((product) {
      final matchesQuery =
          query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.baseName.toLowerCase().contains(query) ||
          product.category.toLowerCase().contains(query);
      final matchesStatus =
          _status == 'Todos' ||
          (_status == 'Visibles' && product.visible) ||
          (_status == 'Ocultos' && !product.visible) ||
          (_status == 'Destacados' && product.featured);
      return matchesQuery && matchesStatus;
    }).toList();

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Sitio web',
        showLogo: false,
        darkerTone: true,
        highContrast: true,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: state.loading
                ? null
                : () => ref.read(websiteControllerProvider.notifier).load(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: RefreshIndicator(
        onRefresh: () => ref.read(websiteControllerProvider.notifier).load(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HeroPanel(
              total: state.products.length,
              visible: state.products.where((p) => p.visible).length,
              featured: state.products.where((p) => p.featured).length,
            ),
            const SizedBox(height: 14),
            _WebLinksPanel(
              websiteUrl: _publicWebsiteUrl,
              storeUrl: _publicStoreUrl,
              onOpen: _openPublicLink,
              onCopy: _copyPublicLink,
              onShare: _sharePublicCatalog,
            ),
            const SizedBox(height: 14),
            _Toolbar(
              searchCtrl: _searchCtrl,
              status: _status,
              onSearchChanged: (_) => setState(() {}),
              onStatusChanged: (value) => setState(() => _status = value),
            ),
            const SizedBox(height: 12),
            if (state.loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (state.error != null)
              _MessageCard(
                icon: Icons.error_outline,
                title: 'No se pudo cargar',
                message: state.error!,
              )
            else if (products.isEmpty)
              const _MessageCard(
                icon: Icons.search_off_rounded,
                title: 'Sin productos',
                message: 'No hay productos con esos filtros.',
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final columns = width >= 1180
                      ? 3
                      : width >= 760
                      ? 2
                      : 1;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: products.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      mainAxisExtent: 318,
                    ),
                    itemBuilder: (context, index) => _WebsiteProductCard(
                      product: products[index],
                      onEdit: () => _openEditor(products[index]),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(WebsiteProductModel product) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _WebsiteProductEditor(product: product),
    );
  }

  Future<void> _openPublicLink(String url) async {
    await safeOpenUrl(context, Uri.parse(url));
  }

  Future<void> _copyPublicLink(String label, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copiado')));
  }

  Future<void> _sharePublicCatalog() async {
    await Clipboard.setData(const ClipboardData(text: _publicShareMessage));
    if (!mounted) return;
    final uri = Uri.https('api.whatsapp.com', '/send', {
      'text': _publicShareMessage,
    });
    await safeOpenUrl(
      context,
      uri,
      copiedMessage: 'Mensaje del catalogo copiado',
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.total,
    required this.visible,
    required this.featured,
  });

  final int total;
  final int visible;
  final int featured;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF003F46), Color(0xFF008C95)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.language_rounded, color: Colors.white, size: 30),
          const SizedBox(height: 12),
          Text(
            'Tienda online FULLTECH',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Controla como se publican los productos del inventario en la web: nombre comercial, descripcion, categoria, foto, visibilidad y destacados.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _StatChip(label: 'Productos', value: '$total'),
              _StatChip(label: 'Visibles', value: '$visible'),
              _StatChip(label: 'Destacados', value: '$featured'),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Text(
        '$value $label',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _WebLinksPanel extends StatelessWidget {
  const _WebLinksPanel({
    required this.websiteUrl,
    required this.storeUrl,
    required this.onOpen,
    required this.onCopy,
    required this.onShare,
  });

  final String websiteUrl;
  final String storeUrl;
  final ValueChanged<String> onOpen;
  final void Function(String label, String url) onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 640;
                final title = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF006D75).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.link_rounded,
                        color: Color(0xFF006D75),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Links publicos y catalogo',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Usa estos enlaces para abrir la web, copiar la tienda online o compartir el catalogo completo con clientes.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
                final shareButton = FilledButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text('Compartir catalogo'),
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [title, const SizedBox(height: 12), shareButton],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 12),
                    shareButton,
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 860;
                final cards = [
                  _WebLinkCard(
                    icon: Icons.public_rounded,
                    title: 'Pagina web',
                    description: 'Presentacion oficial de FULLTECH SRL',
                    url: websiteUrl,
                    onOpen: () => onOpen(websiteUrl),
                    onCopy: () => onCopy('Pagina web', websiteUrl),
                  ),
                  _WebLinkCard(
                    icon: Icons.storefront_rounded,
                    title: 'Tienda online',
                    description: 'Catalogo con productos reales del POS',
                    url: storeUrl,
                    onOpen: () => onOpen(storeUrl),
                    onCopy: () => onCopy('Tienda online', storeUrl),
                  ),
                ];
                if (compact) {
                  return Column(
                    children: [
                      for (final card in cards) ...[
                        card,
                        if (card != cards.last) const SizedBox(height: 10),
                      ],
                    ],
                  );
                }
                return Row(
                  children: [
                    for (final card in cards) ...[
                      Expanded(child: card),
                      if (card != cards.last) const SizedBox(width: 10),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _WebLinkCard extends StatelessWidget {
  const _WebLinkCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.url,
    required this.onOpen,
    required this.onCopy,
  });

  final IconData icon;
  final String title;
  final String description;
  final String url;
  final VoidCallback onOpen;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF006D75)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(description, style: theme.textTheme.bodySmall),
                const SizedBox(height: 6),
                SelectableText(
                  url,
                  maxLines: 1,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF006D75),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Abrir',
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new_rounded),
          ),
          const SizedBox(width: 6),
          IconButton.filledTonal(
            tooltip: 'Copiar',
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded),
          ),
        ],
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.searchCtrl,
    required this.status,
    required this.onSearchChanged,
    required this.onStatusChanged,
  });

  final TextEditingController searchCtrl;
  final String status;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final search = TextField(
          controller: searchCtrl,
          onChanged: onSearchChanged,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            hintText: 'Buscar producto, categoria o titulo web',
            border: OutlineInputBorder(),
          ),
        );
        final filter = DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: status,
                isExpanded: compact,
                items: const ['Todos', 'Visibles', 'Ocultos', 'Destacados']
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) onStatusChanged(value);
                },
              ),
            ),
          ),
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [search, const SizedBox(height: 10), filter],
          );
        }
        return Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 10),
            SizedBox(width: 180, child: filter),
          ],
        );
      },
    );
  }
}

class _WebsiteProductCard extends StatelessWidget {
  const _WebsiteProductCard({required this.product, required this.onEdit});

  final WebsiteProductModel product;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = product.image ?? product.baseImage;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl == null)
                  Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.image_outlined,
                      color: theme.colorScheme.outline,
                      size: 42,
                    ),
                  )
                else
                  ProductNetworkImage(
                    imageUrl: imageUrl,
                    productId: product.id,
                    productName: product.name,
                    originalUrl: product.baseImage,
                    fit: BoxFit.cover,
                    fallback: Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: theme.colorScheme.outline,
                        size: 42,
                      ),
                    ),
                  ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: Wrap(
                    spacing: 6,
                    children: [
                      _Badge(
                        label: product.visible ? 'Visible' : 'Oculto',
                        color: product.visible ? Colors.green : Colors.grey,
                      ),
                      if (product.featured)
                        const _Badge(
                          label: 'Destacado',
                          color: Color(0xFFF2B705),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.category, style: theme.textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  product.description.isEmpty
                      ? 'Sin descripcion web'
                      : product.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        formatRdAccountingAmount(product.price),
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: const Color(0xFF006D75),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 17),
                      label: const Text('Editar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _WebsiteProductEditor extends ConsumerStatefulWidget {
  const _WebsiteProductEditor({required this.product});

  final WebsiteProductModel product;

  @override
  ConsumerState<_WebsiteProductEditor> createState() =>
      _WebsiteProductEditorState();
}

class _WebsiteProductEditorState extends ConsumerState<_WebsiteProductEditor> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _sortCtrl;
  late final TextEditingController _seoTitleCtrl;
  late final TextEditingController _seoDescriptionCtrl;
  String? _imageUrl;
  Uint8List? _pickedBytes;
  String? _pickedName;
  late bool _visible;
  late bool _featured;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _titleCtrl = TextEditingController(text: product.name);
    _descriptionCtrl = TextEditingController(text: product.description);
    _categoryCtrl = TextEditingController(text: product.category);
    _sortCtrl = TextEditingController(text: '${product.sortOrder}');
    _seoTitleCtrl = TextEditingController(text: product.seoTitle ?? '');
    _seoDescriptionCtrl = TextEditingController(
      text: product.seoDescription ?? '',
    );
    _imageUrl = product.image;
    _visible = product.visible;
    _featured = product.featured;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _categoryCtrl.dispose();
    _sortCtrl.dispose();
    _seoTitleCtrl.dispose();
    _seoDescriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    final file = result?.files.single;
    if (file?.bytes == null) return;
    setState(() {
      _pickedBytes = file!.bytes;
      _pickedName = file.name;
    });
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final description = _descriptionCtrl.text.trim();
    final category = _categoryCtrl.text.trim();
    final sortOrder = int.tryParse(_sortCtrl.text.trim()) ?? 0;
    if (title.isEmpty || category.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Titulo y categoria son requeridos')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      var imageUrl = _imageUrl;
      if (_pickedBytes != null && _pickedName != null) {
        imageUrl = await ref
            .read(websiteControllerProvider.notifier)
            .uploadImage(bytes: _pickedBytes!, filename: _pickedName!);
      }
      await ref
          .read(websiteControllerProvider.notifier)
          .updateProduct(
            product: widget.product,
            title: title,
            description: description,
            category: category,
            imageUrl: imageUrl,
            visible: _visible,
            featured: _featured,
            sortOrder: sortOrder,
            seoTitle: _seoTitleCtrl.text.trim(),
            seoDescription: _seoDescriptionCtrl.text.trim(),
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Producto web actualizado')));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 16, 18, bottom + 18),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Editar producto web',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Text(
              'Inventario base: ${widget.product.baseName}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Titulo en la web'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descriptionCtrl,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Descripcion comercial',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _categoryCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Categoria web',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 112,
                  child: TextField(
                    controller: _sortCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Orden'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Visible en la tienda'),
              value: _visible,
              onChanged: (value) => setState(() => _visible = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Destacar en la pagina principal'),
              value: _featured,
              onChanged: (value) => setState(() => _featured = value),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _saving ? null : _pickImage,
              icon: const Icon(Icons.image_outlined),
              label: Text(_pickedName ?? 'Subir foto especifica para la web'),
            ),
            if (_imageUrl != null ||
                widget.product.baseImage != null ||
                _pickedBytes != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 150,
                  child: _pickedBytes != null
                      ? Image.memory(_pickedBytes!, fit: BoxFit.cover)
                      : ProductNetworkImage(
                          imageUrl: _imageUrl ?? widget.product.baseImage!,
                          productId: widget.product.id,
                          productName: widget.product.name,
                          originalUrl: widget.product.baseImage,
                          fit: BoxFit.cover,
                          fallback: Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _seoTitleCtrl,
              decoration: const InputDecoration(labelText: 'Titulo SEO'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _seoDescriptionCtrl,
              decoration: const InputDecoration(labelText: 'Descripcion SEO'),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Guardando...' : 'Guardar en sitio web'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(icon, size: 42, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
