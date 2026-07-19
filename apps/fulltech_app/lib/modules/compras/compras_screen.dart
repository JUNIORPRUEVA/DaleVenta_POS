import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/models/product_model.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/product_network_image.dart';
import '../../features/catalogo/data/catalog_repository.dart';
import 'data/purchases_repository.dart';
import 'purchase_models.dart';
import 'utils/purchase_order_pdf_service.dart';

class ComprasScreen extends ConsumerStatefulWidget {
  const ComprasScreen({super.key});

  @override
  ConsumerState<ComprasScreen> createState() => _ComprasScreenState();
}

class _ComprasScreenState extends ConsumerState<ComprasScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _searchCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _instructionsCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _shippingCtrl = TextEditingController(text: '0');
  final _additionalCtrl = TextEditingController(text: '0');
  final _taxCtrl = TextEditingController(text: '0');

  bool _loading = true;
  bool _saving = false;
  List<ProductModel> _products = const [];
  List<SupplierModel> _suppliers = const [];
  List<PurchaseOrderModel> _orders = const [];
  List<PurchaseRecommendationModel> _recommendations = const [];
  List<PurchaseDraftItem> _cart = const [];
  String? _selectedCategory;
  String? _selectedSupplierId;
  String _statusFilter = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    unawaited(_load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchCtrl.dispose();
    _notesCtrl.dispose();
    _instructionsCtrl.dispose();
    _discountCtrl.dispose();
    _shippingCtrl.dispose();
    _additionalCtrl.dispose();
    _taxCtrl.dispose();
    super.dispose();
  }

  double get _subtotal => _cart.fold(0, (sum, item) => sum + item.subtotal);
  double get _discount => _parseAmount(_discountCtrl.text);
  double get _shipping => _parseAmount(_shippingCtrl.text);
  double get _additional => _parseAmount(_additionalCtrl.text);
  double get _tax => _parseAmount(_taxCtrl.text);
  double get _total => (_subtotal - _discount + _shipping + _additional + _tax)
      .clamp(0, double.infinity)
      .toDouble();
  int get _differentProducts => _cart.length;
  double get _totalUnits => _cart.fold(0, (sum, item) => sum + item.quantity);

  List<String> get _categories =>
      (_products.map((p) => p.categoriaLabel).toSet().toList()..sort());
  List<ProductModel> get _visibleProducts {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _products.where((p) {
      final matchQ =
          q.isEmpty ||
          p.nombre.toLowerCase().contains(q) ||
          (p.codigo ?? '').toLowerCase().contains(q);
      final matchCat =
          _selectedCategory == null || p.categoriaLabel == _selectedCategory;
      return matchQ && matchCat;
    }).toList();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(purchasesRepositoryProvider);
      final results = await Future.wait([
        ref.read(catalogRepositoryProvider).fetchProducts(silent: true),
        repo.listSuppliers(),
        repo.listOrders(),
        repo.recommendations(),
      ]);
      if (!mounted) return;
      setState(() {
        _products = results[0] as List<ProductModel>;
        _suppliers = results[1] as List<SupplierModel>;
        _orders = results[2] as List<PurchaseOrderModel>;
        _recommendations = results[3] as List<PurchaseRecommendationModel>;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('No se pudo cargar Compras: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Compras',
        fallbackRoute: Routes.cotizaciones,
        preferDrawerLeading: true,
        showLogo: false,
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: const [
            Tab(
              icon: Icon(Icons.add_shopping_cart_outlined),
              text: 'Nueva compra',
            ),
            Tab(
              icon: Icon(Icons.receipt_long_outlined),
              text: 'Lista de compras',
            ),
            Tab(icon: Icon(Icons.storefront_outlined), text: 'Suplidores'),
            Tab(
              icon: Icon(Icons.trending_up_rounded),
              text: 'Productos por comprar',
            ),
          ],
        ),
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _newPurchaseTab(),
                _ordersTab(),
                _suppliersTab(),
                _recommendationsTab(),
              ],
            ),
    );
  }

  Widget _newPurchaseTab() {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 1024;
    final isTablet = size.width >= 720;
    final productGrid = Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            isWide ? 18 : 12,
            12,
            isWide ? 12 : 12,
            8,
          ),
          child: _PurchaseToolbar(
            searchController: _searchCtrl,
            selectedCategory: _selectedCategory,
            categories: _categories,
            onSearchChanged: (_) => setState(() {}),
            onCategoryChanged: (value) =>
                setState(() => _selectedCategory = value),
            onAddExternal: _openExternalProductDialog,
            onOpenOrder: isWide ? null : _openCartSheet,
            itemCount: _cart.length,
            total: _money(_total),
          ),
        ),
        if (_cart.isNotEmpty && !isWide)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: _MobileOrderSummary(
              itemCount: _cart.length,
              units: _qty(_totalUnits),
              total: _money(_total),
              onPressed: _openCartSheet,
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final crossAxisCount = width < 360
                  ? 2
                  : width < 620
                  ? 2
                  : width < 900
                  ? 3
                  : isWide
                  ? 4
                  : 3;
              final aspectRatio = width < 380
                  ? .82
                  : width < 720
                  ? .9
                  : 1.02;
              return GridView.builder(
                padding: EdgeInsets.fromLTRB(
                  isWide ? 18 : 12,
                  0,
                  isWide ? 12 : 12,
                  16,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: aspectRatio,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: _visibleProducts.length,
                itemBuilder: (context, index) => _PurchaseProductCard(
                  product: _visibleProducts[index],
                  money: _money,
                  qty: _qty,
                  onTap: () => _openProductDialog(_visibleProducts[index]),
                ),
              );
            },
          ),
        ),
      ],
    );
    final cart = _cartPanel();
    if (!isWide) return productGrid;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isTablet ? 1280 : double.infinity,
        ),
        child: Row(
          children: [
            Expanded(child: productGrid),
            SizedBox(width: size.width >= 1280 ? 460 : 420, child: cart),
          ],
        ),
      ),
    );
  }

  Widget _cartPanel() {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          left: BorderSide(color: theme.dividerColor.withValues(alpha: .45)),
        ),
      ),
      child: SafeArea(
        left: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: .35),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .04),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Orden de compra',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _StatusChip(label: '${_cart.length} items'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: _selectedSupplierId,
                    isExpanded: true,
                    decoration: _fieldDecoration(
                      'Suplidor principal',
                      icon: Icons.storefront_outlined,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Sin suplidor'),
                      ),
                      for (final s in _suppliers)
                        DropdownMenuItem<String?>(
                          value: s.id,
                          child: Text(
                            s.commercialName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedSupplierId = value),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: _cart.isEmpty
                        ? _EmptyOrderState(
                            onAddExternal: _openExternalProductDialog,
                          )
                        : ListView.separated(
                            itemCount: _cart.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) => _CartItemTile(
                              item: _cart[index],
                              money: _money,
                              qty: _qty,
                              onEdit: () => _editCartItem(index),
                              onDelete: () => setState(
                                () => _cart = [..._cart]..removeAt(index),
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stack = constraints.maxWidth < 360;
                      final fields = [
                        _moneyField(_discountCtrl, 'Descuento'),
                        _moneyField(_shippingCtrl, 'Transporte'),
                        _moneyField(_additionalCtrl, 'Adicional'),
                        _moneyField(_taxCtrl, 'Impuestos'),
                      ];
                      if (stack) {
                        return Column(
                          children: [
                            for (final field in fields) ...[
                              field,
                              const SizedBox(height: 8),
                            ],
                          ],
                        );
                      }
                      return Column(
                        children: [
                          Row(
                            children: [
                              Expanded(child: fields[0]),
                              const SizedBox(width: 8),
                              Expanded(child: fields[1]),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(child: fields[2]),
                              const SizedBox(width: 8),
                              Expanded(child: fields[3]),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _instructionsCtrl,
                    minLines: 1,
                    maxLines: 2,
                    decoration: _fieldDecoration(
                      'Instrucciones o enlace para suplidor',
                      icon: Icons.link_outlined,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesCtrl,
                    minLines: 1,
                    maxLines: 2,
                    decoration: _fieldDecoration(
                      'Observaciones internas',
                      icon: Icons.notes_outlined,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _TotalsPanel(
                    units: _qty(_totalUnits),
                    products: '$_differentProducts',
                    subtotal: _money(_subtotal),
                    total: _money(_total),
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final stack = constraints.maxWidth < 380;
                      final draft = OutlinedButton.icon(
                        onPressed: _cart.isEmpty || _saving
                            ? null
                            : () => _saveOrder(draft: true),
                        icon: const Icon(Icons.save_outlined),
                        label: const Text(
                          'Borrador',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                      final generate = FilledButton.icon(
                        onPressed: _cart.isEmpty || _saving
                            ? null
                            : () => _saveOrder(draft: false),
                        icon: _saving
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text(
                          'Generar orden',
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                      if (stack) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            draft,
                            const SizedBox(height: 8),
                            generate,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: draft),
                          const SizedBox(width: 8),
                          Expanded(child: generate),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _ordersTab() {
    final visible = _orders
        .where((o) => _statusFilter.isEmpty || o.status == _statusFilter)
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Órdenes creadas',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              DropdownButton<String>(
                value: _statusFilter,
                items: const [
                  DropdownMenuItem(value: '', child: Text('Todos')),
                  DropdownMenuItem(value: 'DRAFT', child: Text('Borrador')),
                  DropdownMenuItem(value: 'APPROVED', child: Text('Aprobada')),
                  DropdownMenuItem(value: 'SENT', child: Text('Enviada')),
                  DropdownMenuItem(
                    value: 'PARTIALLY_RECEIVED',
                    child: Text('Parcial'),
                  ),
                  DropdownMenuItem(value: 'RECEIVED', child: Text('Recibida')),
                  DropdownMenuItem(
                    value: 'CANCELLED',
                    child: Text('Cancelada'),
                  ),
                ],
                onChanged: (v) => setState(() => _statusFilter = v ?? ''),
              ),
            ],
          ),
        ),
        Expanded(
          child: visible.isEmpty
              ? const Center(child: Text('No hay órdenes de compra.'))
              : ListView.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) => _orderTile(visible[index]),
                ),
        ),
      ],
    );
  }

  Widget _orderTile(PurchaseOrderModel order) {
    return ListTile(
      title: Text(
        '${order.orderNumber} · ${order.supplier?.commercialName ?? 'Sin suplidor'}',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: Text(
        '${order.items.length} artículos · ${_qty(order.items.fold(0, (sum, i) => sum + i.quantity))} unidades · ${order.status}',
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          Text(
            _money(order.total),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          IconButton(
            tooltip: 'PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => _sharePdf(order),
          ),
          IconButton(
            tooltip: 'Aprobar',
            icon: const Icon(Icons.verified_outlined),
            onPressed: order.status == 'DRAFT'
                ? () => _orderAction(
                    () =>
                        ref.read(purchasesRepositoryProvider).approve(order.id),
                    'Orden aprobada.',
                  )
                : null,
          ),
          IconButton(
            tooltip: 'Enviada',
            icon: const Icon(Icons.send_outlined),
            onPressed: ['APPROVED', 'DRAFT'].contains(order.status)
                ? () => _orderAction(
                    () => ref
                        .read(purchasesRepositoryProvider)
                        .markSent(order.id),
                    'Orden enviada al suplidor.',
                  )
                : null,
          ),
          IconButton(
            tooltip: 'Registrar recepción',
            icon: const Icon(Icons.inventory_outlined),
            onPressed:
                [
                  'SENT',
                  'APPROVED',
                  'PARTIALLY_RECEIVED',
                ].contains(order.status)
                ? () => _receive(order)
                : null,
          ),
          IconButton(
            tooltip: 'Duplicar',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () => _orderAction(
              () => ref.read(purchasesRepositoryProvider).duplicate(order.id),
              'Orden duplicada.',
            ),
          ),
        ],
      ),
      onTap: () => _showOrderDetail(order),
    );
  }

  Widget _suppliersTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Suplidores',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _supplierDialog(),
                icon: const Icon(Icons.add_business_outlined),
                label: const Text('Crear suplidor'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _suppliers.isEmpty
              ? const Center(child: Text('No hay suplidores.'))
              : ListView.separated(
                  itemCount: _suppliers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final s = _suppliers[index];
                    return ListTile(
                      leading: Icon(
                        s.isActive
                            ? Icons.storefront_outlined
                            : Icons.block_outlined,
                      ),
                      title: Text(
                        s.commercialName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        [
                          s.contactName,
                          s.phone,
                          s.whatsapp,
                          s.email,
                        ].where((e) => (e ?? '').isNotEmpty).join(' · '),
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          Text(_money(s.totalPurchased)),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _supplierDialog(supplier: s),
                            tooltip: 'Editar',
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deactivateSupplier(s),
                            tooltip: 'Desactivar',
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _recommendationsTab() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _recommendations.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final r = _recommendations[index];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Theme.of(context).dividerColor),
          ),
          child: ListTile(
            leading: SizedBox(
              width: 44,
              height: 44,
              child: ProductNetworkImage(
                imageUrl: r.product.displayFotoUrl ?? '',
                productId: r.product.id,
                productName: r.product.nombre,
                originalUrl: r.product.originalFotoUrl,
                fit: BoxFit.cover,
                fallback: const Icon(Icons.inventory_2_outlined),
              ),
            ),
            title: Text(
              r.product.nombre,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              '${r.reason} · Stock ${_qty(r.stock)} · Ordenado ${_qty(r.alreadyOrdered)} · Sugerido ${_qty(r.suggestedQuantity)}',
            ),
            trailing: FilledButton.tonalIcon(
              onPressed: r.suggestedQuantity <= 0
                  ? null
                  : () =>
                        _addProduct(r.product, initialQty: r.suggestedQuantity),
              icon: const Icon(Icons.add_shopping_cart_outlined),
              label: const Text('Agregar'),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openProductDialog(ProductModel product) => _addProduct(product);

  Future<void> _addProduct(
    ProductModel product, {
    double initialQty = 1,
  }) async {
    final qty = TextEditingController(text: _qty(initialQty));
    final cost = TextEditingController(text: product.costo.toStringAsFixed(2));
    final notes = TextEditingController();
    String? supplierId = _selectedSupplierId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(product.nombre),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: qty,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Cantidad a comprar',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: cost,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Precio de compra unitario',
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: supplierId,
                  decoration: const InputDecoration(labelText: 'Suplidor'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Sin suplidor'),
                    ),
                    for (final s in _suppliers)
                      DropdownMenuItem(
                        value: s.id,
                        child: Text(s.commercialName),
                      ),
                  ],
                  onChanged: (v) => setDialogState(() => supplierId = v),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(labelText: 'Observación'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final item = PurchaseDraftItem(
      product: product,
      productId: product.id,
      productName: product.nombre,
      productCode: product.codigo,
      description: product.descripcion,
      image: product.displayFotoUrl,
      quantity: _parseAmount(qty.text).clamp(.0001, double.infinity).toDouble(),
      unitCost: _parseAmount(cost.text).clamp(0, double.infinity).toDouble(),
      supplierId: supplierId,
      notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
    );
    setState(() => _cart = [..._cart, item]);
  }

  Future<void> _openExternalProductDialog() async {
    final name = TextEditingController();
    final qty = TextEditingController(text: '1');
    final cost = TextEditingController();
    final description = TextEditingController();
    bool createOnReceipt = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Agregar producto externo'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del producto',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: description,
                    decoration: const InputDecoration(
                      labelText: 'Descripción / marca / modelo / enlace',
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: qty,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Cantidad'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: cost,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Precio unitario',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: createOnReceipt,
                    onChanged: (v) =>
                        setDialogState(() => createOnReceipt = v ?? false),
                    title: const Text(
                      'Crear este producto en el inventario cuando sea recibido',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Agregar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    setState(
      () => _cart = [
        ..._cart,
        PurchaseDraftItem(
          productName: name.text.trim(),
          description: description.text.trim().isEmpty
              ? null
              : description.text.trim(),
          quantity: _parseAmount(
            qty.text,
          ).clamp(.0001, double.infinity).toDouble(),
          unitCost: _parseAmount(
            cost.text,
          ).clamp(0, double.infinity).toDouble(),
          supplierId: _selectedSupplierId,
          createInventoryProductOnReceipt: createOnReceipt,
        ),
      ],
    );
  }

  Future<void> _editCartItem(int index) async {
    final item = _cart[index];
    final qty = TextEditingController(text: _qty(item.quantity));
    final cost = TextEditingController(text: item.unitCost.toStringAsFixed(2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.productName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qty,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Cantidad'),
            ),
            TextField(
              controller: cost,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Costo unitario'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      final next = [..._cart];
      next[index] = item.copyWith(
        quantity: _parseAmount(qty.text),
        unitCost: _parseAmount(cost.text),
      );
      _cart = next;
    });
  }

  Future<void> _saveOrder({required bool draft}) async {
    if (_cart.isEmpty) return _snack('Agrega al menos un producto.');
    setState(() => _saving = true);
    try {
      final order = await ref
          .read(purchasesRepositoryProvider)
          .createOrder(
            supplierId: _selectedSupplierId,
            items: _cart,
            discount: _discount,
            shippingCost: _shipping,
            additionalCost: _additional,
            tax: _tax,
            notes: _notesCtrl.text.trim(),
            supplierInstructions: _instructionsCtrl.text.trim(),
          );
      if (!draft && order.supplier == null) {
        _snack('Orden guardada. Selecciona un suplidor antes de aprobar.');
      }
      if (!draft) await _sharePdf(order);
      setState(() {
        _orders = [order, ..._orders];
        _cart = const [];
        _notesCtrl.clear();
        _instructionsCtrl.clear();
      });
      _snack('Orden guardada correctamente.');
    } catch (e) {
      _snack(
        'No fue posible completar la operación. No se realizaron cambios. $e',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _orderAction(
    Future<PurchaseOrderModel> Function() action,
    String message,
  ) async {
    try {
      final updated = await action();
      setState(
        () => _orders = [
          for (final o in _orders)
            if (o.id == updated.id) updated else o,
        ],
      );
      _snack(message);
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _receive(PurchaseOrderModel order) async {
    final update = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar recepción'),
        content: const Text(
          '¿Desea actualizar el inventario con las cantidades recibidas pendientes?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Solo registrar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Actualizar inventario'),
          ),
        ],
      ),
    );
    if (update == null) return;
    await _orderAction(
      () => ref
          .read(purchasesRepositoryProvider)
          .receive(order: order, updateInventory: update),
      update
          ? 'Inventario actualizado correctamente.'
          : 'Recepción registrada.',
    );
  }

  Future<void> _sharePdf(PurchaseOrderModel order) async {
    final company = await ref.read(companySettingsProvider.future);
    final bytes = await buildPurchaseOrderPdf(order: order, company: company);
    final supplier = (order.supplier?.commercialName ?? 'Suplidor').replaceAll(
      RegExp(r'[^A-Za-z0-9_-]+'),
      '_',
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'Orden_Compra_${order.orderNumber}_$supplier.pdf',
    );
  }

  Future<void> _supplierDialog({SupplierModel? supplier}) async {
    final name = TextEditingController(text: supplier?.commercialName ?? '');
    final phone = TextEditingController(text: supplier?.phone ?? '');
    final whatsapp = TextEditingController(text: supplier?.whatsapp ?? '');
    final email = TextEditingController(text: supplier?.email ?? '');
    final contact = TextEditingController(text: supplier?.contactName ?? '');
    final address = TextEditingController(text: supplier?.address ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(supplier == null ? 'Crear suplidor' : 'Editar suplidor'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Nombre comercial',
                  ),
                ),
                TextField(
                  controller: contact,
                  decoration: const InputDecoration(
                    labelText: 'Persona de contacto',
                  ),
                ),
                TextField(
                  controller: phone,
                  decoration: const InputDecoration(labelText: 'Teléfono'),
                ),
                TextField(
                  controller: whatsapp,
                  decoration: const InputDecoration(labelText: 'WhatsApp'),
                ),
                TextField(
                  controller: email,
                  decoration: const InputDecoration(labelText: 'Correo'),
                ),
                TextField(
                  controller: address,
                  decoration: const InputDecoration(labelText: 'Dirección'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final saved = await ref
          .read(purchasesRepositoryProvider)
          .saveSupplier(
            SupplierModel(
              id: supplier?.id ?? '',
              commercialName: name.text.trim(),
              contactName: contact.text.trim(),
              phone: phone.text.trim(),
              whatsapp: whatsapp.text.trim(),
              email: email.text.trim(),
              address: address.text.trim(),
            ),
          );
      setState(
        () =>
            _suppliers = [saved, ..._suppliers.where((s) => s.id != saved.id)],
      );
      _snack('Suplidor guardado.');
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _deactivateSupplier(SupplierModel supplier) async {
    await ref.read(purchasesRepositoryProvider).deactivateSupplier(supplier.id);
    setState(
      () => _suppliers = _suppliers.where((s) => s.id != supplier.id).toList(),
    );
    _snack('Suplidor desactivado.');
  }

  void _showOrderDetail(PurchaseOrderModel order) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '${order.orderNumber} · ${order.status}',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          Text(order.supplier?.commercialName ?? 'Sin suplidor'),
          const Divider(),
          for (final item in order.items)
            ListTile(
              title: Text(item.productName),
              subtitle: Text(
                'Pedido ${_qty(item.quantity)} · Recibido ${_qty(item.receivedQuantity)} · Pendiente ${_qty(item.pendingQuantity)}',
              ),
              trailing: Text(_money(item.subtotal)),
            ),
          const Divider(),
          _totalRow('Total general', _money(order.total), strong: true),
        ],
      ),
    );
  }

  void _openCartSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) =>
          FractionallySizedBox(heightFactor: .92, child: _cartPanel()),
    );
  }

  InputDecoration _fieldDecoration(String label, {IconData? icon}) =>
      InputDecoration(
        labelText: label,
        prefixIcon: icon == null ? null : Icon(icon, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: .55),
          ),
        ),
        isDense: true,
        filled: true,
        fillColor: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: .35),
      );

  Widget _moneyField(TextEditingController ctrl, String label) => TextField(
    controller: ctrl,
    keyboardType: TextInputType.number,
    onChanged: (_) => setState(() {}),
    decoration: _fieldDecoration(label),
  );

  Widget _totalRow(
    String label,
    String value, {
    bool strong = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: strong ? const TextStyle(fontWeight: FontWeight.w800) : null,
        ),
        Text(
          value,
          style: strong ? const TextStyle(fontWeight: FontWeight.w900) : null,
        ),
      ],
    ),
  );

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
  String _money(double value) => formatRdCurrencyAccounting(value);
  String _qty(num value) =>
      value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  double _parseAmount(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
}

class _PurchaseToolbar extends StatelessWidget {
  const _PurchaseToolbar({
    required this.searchController,
    required this.selectedCategory,
    required this.categories,
    required this.onSearchChanged,
    required this.onCategoryChanged,
    required this.onAddExternal,
    required this.itemCount,
    required this.total,
    this.onOpenOrder,
  });

  final TextEditingController searchController;
  final String? selectedCategory;
  final List<String> categories;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onCategoryChanged;
  final VoidCallback onAddExternal;
  final VoidCallback? onOpenOrder;
  final int itemCount;
  final String total;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 680;
    final search = TextField(
      controller: searchController,
      onChanged: onSearchChanged,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: 'Buscar producto',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
        filled: true,
        suffixIcon: searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpiar búsqueda',
                onPressed: () {
                  searchController.clear();
                  onSearchChanged('');
                },
                icon: const Icon(Icons.close),
              ),
      ),
    );
    final category = DropdownButtonFormField<String?>(
      initialValue: selectedCategory,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Categoría',
        prefixIcon: const Icon(Icons.filter_alt_outlined, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
        filled: true,
      ),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Todas')),
        for (final c in categories)
          DropdownMenuItem<String?>(
            value: c,
            child: Text(c, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onCategoryChanged,
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          onPressed: onAddExternal,
          tooltip: 'Agregar producto externo',
          icon: const Icon(Icons.add_box_outlined),
        ),
        if (onOpenOrder != null) ...[
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onOpenOrder,
            icon: const Icon(Icons.receipt_long_outlined),
            label: Text(
              itemCount == 0 ? 'Orden' : '$itemCount · $total',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
    if (compact) {
      return Column(
        children: [
          search,
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: category),
              const SizedBox(width: 8),
              actions,
            ],
          ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(flex: 3, child: search),
        const SizedBox(width: 10),
        Expanded(flex: 2, child: category),
        const SizedBox(width: 10),
        actions,
      ],
    );
  }
}

class _MobileOrderSummary extends StatelessWidget {
  const _MobileOrderSummary({
    required this.itemCount,
    required this.units,
    required this.total,
    required this.onPressed,
  });

  final int itemCount;
  final String units;
  final String total;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primaryContainer.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.receipt_long_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$itemCount productos · $units unidades',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(total, style: const TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PurchaseProductCard extends StatelessWidget {
  const _PurchaseProductCard({
    required this.product,
    required this.money,
    required this.qty,
    required this.onTap,
  });

  final ProductModel product;
  final String Function(double) money;
  final String Function(num) qty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stock = product.stock ?? 0;
    final suggested = (10 - stock).clamp(0, double.infinity).toDouble();
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: .35)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: .6,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: ProductNetworkImage(
                    imageUrl: product.displayFotoUrl ?? '',
                    productId: product.id,
                    productName: product.nombre,
                    originalUrl: product.originalFotoUrl,
                    fit: BoxFit.contain,
                    fallback: const Icon(Icons.inventory_2_outlined, size: 38),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.nombre,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _MiniChip(label: 'Stock ${qty(stock)}'),
                      _MiniChip(label: 'Sug ${qty(suggested)}'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Costo ${money(product.costo)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({
    required this.item,
    required this.money,
    required this.qty,
    required this.onEdit,
    required this.onDelete,
  });

  final PurchaseDraftItem item;
  final String Function(double) money;
  final String Function(num) qty;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: ProductNetworkImage(
                    imageUrl: item.image ?? '',
                    productId: item.productId ?? item.productName,
                    productName: item.productName,
                    originalUrl: item.image,
                    fit: BoxFit.cover,
                    fallback: const Icon(Icons.inventory_2_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${qty(item.quantity)} x ${money(item.unitCost)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money(item.subtotal),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  SizedBox(
                    width: 62,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: 'Editar',
                            iconSize: 16,
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: onEdit,
                          ),
                        ),
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: 'Eliminar',
                            iconSize: 16,
                            icon: const Icon(Icons.close),
                            onPressed: onDelete,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalsPanel extends StatelessWidget {
  const _TotalsPanel({
    required this.units,
    required this.products,
    required this.subtotal,
    required this.total,
  });

  final String units;
  final String products;
  final String subtotal;
  final String total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: .32),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: .12),
        ),
      ),
      child: Column(
        children: [
          _totalLine('Unidades', units),
          _totalLine('Productos', products),
          _totalLine('Subtotal', subtotal),
          const Divider(height: 14),
          _totalLine('Inversión total', total, strong: true),
        ],
      ),
    );
  }

  Widget _totalLine(String label, String value, {bool strong = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _EmptyOrderState extends StatelessWidget {
  const _EmptyOrderState({required this.onAddExternal});

  final VoidCallback onAddExternal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_shopping_cart_outlined,
              size: 42,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 10),
            Text(
              'Agrega productos para iniciar',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onAddExternal,
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Producto externo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => _MiniChip(label: label);
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
