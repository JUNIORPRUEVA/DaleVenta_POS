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

class _ComprasScreenState extends ConsumerState<ComprasScreen> with SingleTickerProviderStateMixin {
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
  double get _total => (_subtotal - _discount + _shipping + _additional + _tax).clamp(0, double.infinity).toDouble();
  int get _differentProducts => _cart.length;
  double get _totalUnits => _cart.fold(0, (sum, item) => sum + item.quantity);

  List<String> get _categories => (_products.map((p) => p.categoriaLabel).toSet().toList()..sort());
  List<ProductModel> get _visibleProducts {
    final q = _searchCtrl.text.trim().toLowerCase();
    return _products.where((p) {
      final matchQ = q.isEmpty || p.nombre.toLowerCase().contains(q) || (p.codigo ?? '').toLowerCase().contains(q);
      final matchCat = _selectedCategory == null || p.categoriaLabel == _selectedCategory;
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
            Tab(icon: Icon(Icons.add_shopping_cart_outlined), text: 'Nueva compra'),
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Lista de compras'),
            Tab(icon: Icon(Icons.storefront_outlined), text: 'Suplidores'),
            Tab(icon: Icon(Icons.trending_up_rounded), text: 'Productos por comprar'),
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
    final isWide = MediaQuery.sizeOf(context).width >= 980;
    final productGrid = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar producto', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String?>(
                value: _selectedCategory,
                hint: const Text('Categoría'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Todas')),
                  for (final c in _categories) DropdownMenuItem<String?>(value: c, child: Text(c)),
                ],
                onChanged: (value) => setState(() => _selectedCategory = value),
              ),
              IconButton(onPressed: _openExternalProductDialog, icon: const Icon(Icons.add_box_outlined), tooltip: 'Agregar producto externo'),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isWide ? 4 : 2,
              childAspectRatio: isWide ? 1.05 : .86,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _visibleProducts.length,
            itemBuilder: (context, index) {
              final p = _visibleProducts[index];
              final stock = p.stock ?? 0;
              final suggested = (10 - stock).clamp(0, double.infinity).toDouble();
              return Card(
                elevation: 0,
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Theme.of(context).dividerColor)),
                child: InkWell(
                  onTap: () => _openProductDialog(p),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Center(
                            child: ProductNetworkImage(
                              imageUrl: p.displayFotoUrl ?? '',
                              productId: p.id,
                              productName: p.nombre,
                              originalUrl: p.originalFotoUrl,
                              fit: BoxFit.contain,
                              fallback: const Icon(Icons.inventory_2_outlined, size: 42),
                            ),
                          ),
                        ),
                        Text(p.nombre, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                        Text('Stock: ${_qty(stock)} · Min: 5 · Sug: ${_qty(suggested)}', style: Theme.of(context).textTheme.bodySmall),
                        Text('Costo: ${_money(p.costo)}', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
    final cart = _cartPanel();
    return isWide ? Row(children: [Expanded(child: productGrid), SizedBox(width: 430, child: cart)]) : Column(children: [Expanded(child: productGrid), SizedBox(height: 330, child: cart)]);
  }

  Widget _cartPanel() {
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(left: BorderSide(color: Theme.of(context).dividerColor))),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<String?>(
              initialValue: _selectedSupplierId,
              decoration: const InputDecoration(labelText: 'Suplidor principal', border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Sin suplidor')),
                for (final s in _suppliers) DropdownMenuItem<String?>(value: s.id, child: Text(s.commercialName)),
              ],
              onChanged: (value) => setState(() => _selectedSupplierId = value),
            ),
          ),
          Expanded(
            child: _cart.isEmpty
                ? const Center(child: Text('Agrega al menos un producto.'))
                : ListView.separated(
                    itemCount: _cart.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = _cart[index];
                      return ListTile(
                        dense: true,
                        leading: SizedBox(
                          width: 38,
                          height: 38,
                          child: ProductNetworkImage(
                            imageUrl: item.image ?? '',
                            productId: item.productId ?? item.productName,
                            productName: item.productName,
                            originalUrl: item.image,
                            fit: BoxFit.cover,
                            fallback: const Icon(Icons.inventory_2_outlined),
                          ),
                        ),
                        title: Text(item.productName, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${_qty(item.quantity)} x ${_money(item.unitCost)} · ${_money(item.subtotal)}'),
                        trailing: Wrap(
                          spacing: 2,
                          children: [
                            IconButton(tooltip: 'Editar', icon: const Icon(Icons.edit_outlined), onPressed: () => _editCartItem(index)),
                            IconButton(tooltip: 'Eliminar', icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _cart = [..._cart]..removeAt(index))),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(children: [
                  Expanded(child: _moneyField(_discountCtrl, 'Descuento')),
                  const SizedBox(width: 8),
                  Expanded(child: _moneyField(_shippingCtrl, 'Transporte')),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: _moneyField(_additionalCtrl, 'Adicional')),
                  const SizedBox(width: 8),
                  Expanded(child: _moneyField(_taxCtrl, 'Impuestos')),
                ]),
                const SizedBox(height: 8),
                TextField(controller: _notesCtrl, minLines: 1, maxLines: 2, decoration: const InputDecoration(labelText: 'Observaciones', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                _totalRow('Unidades', _qty(_totalUnits)),
                _totalRow('Productos', '$_differentProducts'),
                _totalRow('Subtotal', _money(_subtotal)),
                _totalRow('Inversión total', _money(_total), strong: true),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: OutlinedButton.icon(onPressed: _cart.isEmpty ? null : () => _saveOrder(draft: true), icon: const Icon(Icons.save_outlined), label: const Text('Guardar borrador'))),
                    const SizedBox(width: 8),
                    Expanded(child: FilledButton.icon(onPressed: _cart.isEmpty || _saving ? null : () => _saveOrder(draft: false), icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Generar orden de compra'))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ordersTab() {
    final visible = _orders.where((o) => _statusFilter.isEmpty || o.status == _statusFilter).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            Expanded(child: Text('Órdenes creadas', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
            DropdownButton<String>(
              value: _statusFilter,
              items: const [
                DropdownMenuItem(value: '', child: Text('Todos')),
                DropdownMenuItem(value: 'DRAFT', child: Text('Borrador')),
                DropdownMenuItem(value: 'APPROVED', child: Text('Aprobada')),
                DropdownMenuItem(value: 'SENT', child: Text('Enviada')),
                DropdownMenuItem(value: 'PARTIALLY_RECEIVED', child: Text('Parcial')),
                DropdownMenuItem(value: 'RECEIVED', child: Text('Recibida')),
                DropdownMenuItem(value: 'CANCELLED', child: Text('Cancelada')),
              ],
              onChanged: (v) => setState(() => _statusFilter = v ?? ''),
            ),
          ]),
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
      title: Text('${order.orderNumber} · ${order.supplier?.commercialName ?? 'Sin suplidor'}', style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text('${order.items.length} artículos · ${_qty(order.items.fold(0, (sum, i) => sum + i.quantity))} unidades · ${order.status}'),
      trailing: Wrap(
        spacing: 4,
        children: [
          Text(_money(order.total), style: const TextStyle(fontWeight: FontWeight.w800)),
          IconButton(tooltip: 'PDF', icon: const Icon(Icons.picture_as_pdf_outlined), onPressed: () => _sharePdf(order)),
          IconButton(tooltip: 'Aprobar', icon: const Icon(Icons.verified_outlined), onPressed: order.status == 'DRAFT' ? () => _orderAction(() => ref.read(purchasesRepositoryProvider).approve(order.id), 'Orden aprobada.') : null),
          IconButton(tooltip: 'Enviada', icon: const Icon(Icons.send_outlined), onPressed: ['APPROVED', 'DRAFT'].contains(order.status) ? () => _orderAction(() => ref.read(purchasesRepositoryProvider).markSent(order.id), 'Orden enviada al suplidor.') : null),
          IconButton(tooltip: 'Registrar recepción', icon: const Icon(Icons.inventory_outlined), onPressed: ['SENT', 'APPROVED', 'PARTIALLY_RECEIVED'].contains(order.status) ? () => _receive(order) : null),
          IconButton(tooltip: 'Duplicar', icon: const Icon(Icons.copy_outlined), onPressed: () => _orderAction(() => ref.read(purchasesRepositoryProvider).duplicate(order.id), 'Orden duplicada.')),
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
          child: Row(children: [
            Expanded(child: Text('Suplidores', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
            FilledButton.icon(onPressed: () => _supplierDialog(), icon: const Icon(Icons.add_business_outlined), label: const Text('Crear suplidor')),
          ]),
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
                      leading: Icon(s.isActive ? Icons.storefront_outlined : Icons.block_outlined),
                      title: Text(s.commercialName, style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text([s.contactName, s.phone, s.whatsapp, s.email].where((e) => (e ?? '').isNotEmpty).join(' · ')),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          Text(_money(s.totalPurchased)),
                          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _supplierDialog(supplier: s), tooltip: 'Editar'),
                          IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _deactivateSupplier(s), tooltip: 'Desactivar'),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Theme.of(context).dividerColor)),
          child: ListTile(
            leading: SizedBox(
              width: 44,
              height: 44,
              child: ProductNetworkImage(imageUrl: r.product.displayFotoUrl ?? '', productId: r.product.id, productName: r.product.nombre, originalUrl: r.product.originalFotoUrl, fit: BoxFit.cover, fallback: const Icon(Icons.inventory_2_outlined)),
            ),
            title: Text(r.product.nombre, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${r.reason} · Stock ${_qty(r.stock)} · Ordenado ${_qty(r.alreadyOrdered)} · Sugerido ${_qty(r.suggestedQuantity)}'),
            trailing: FilledButton.tonalIcon(
              onPressed: r.suggestedQuantity <= 0 ? null : () => _addProduct(r.product, initialQty: r.suggestedQuantity),
              icon: const Icon(Icons.add_shopping_cart_outlined),
              label: const Text('Agregar'),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openProductDialog(ProductModel product) => _addProduct(product);

  Future<void> _addProduct(ProductModel product, {double initialQty = 1}) async {
    final qty = TextEditingController(text: _qty(initialQty));
    final cost = TextEditingController(text: product.costo.toStringAsFixed(2));
    final notes = TextEditingController();
    String? supplierId = _selectedSupplierId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(product.nombre),
          content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad a comprar')),
            const SizedBox(height: 8),
            TextField(controller: cost, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Precio de compra unitario')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(initialValue: supplierId, decoration: const InputDecoration(labelText: 'Suplidor'), items: [
              const DropdownMenuItem(value: null, child: Text('Sin suplidor')),
              for (final s in _suppliers) DropdownMenuItem(value: s.id, child: Text(s.commercialName)),
            ], onChanged: (v) => setDialogState(() => supplierId = v)),
            const SizedBox(height: 8),
            TextField(controller: notes, decoration: const InputDecoration(labelText: 'Observación')),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Agregar')),
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
          content: SizedBox(width: 380, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre del producto')),
            const SizedBox(height: 8),
            TextField(controller: description, decoration: const InputDecoration(labelText: 'Descripción / marca / modelo / enlace')),
            const SizedBox(height: 8),
            TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad')),
            const SizedBox(height: 8),
            TextField(controller: cost, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Precio unitario')),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: createOnReceipt,
              onChanged: (v) => setDialogState(() => createOnReceipt = v ?? false),
              title: const Text('Crear este producto en el inventario cuando sea recibido'),
            ),
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Agregar')),
          ],
        ),
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    setState(() => _cart = [
      ..._cart,
      PurchaseDraftItem(
        productName: name.text.trim(),
        description: description.text.trim().isEmpty ? null : description.text.trim(),
        quantity: _parseAmount(qty.text).clamp(.0001, double.infinity).toDouble(),
        unitCost: _parseAmount(cost.text).clamp(0, double.infinity).toDouble(),
        supplierId: _selectedSupplierId,
        createInventoryProductOnReceipt: createOnReceipt,
      ),
    ]);
  }

  Future<void> _editCartItem(int index) async {
    final item = _cart[index];
    final qty = TextEditingController(text: _qty(item.quantity));
    final cost = TextEditingController(text: item.unitCost.toStringAsFixed(2));
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.productName),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Cantidad')),
          TextField(controller: cost, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Costo unitario')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() {
      final next = [..._cart];
      next[index] = item.copyWith(quantity: _parseAmount(qty.text), unitCost: _parseAmount(cost.text));
      _cart = next;
    });
  }

  Future<void> _saveOrder({required bool draft}) async {
    if (_cart.isEmpty) return _snack('Agrega al menos un producto.');
    setState(() => _saving = true);
    try {
      final order = await ref.read(purchasesRepositoryProvider).createOrder(
        supplierId: _selectedSupplierId,
        items: _cart,
        discount: _discount,
        shippingCost: _shipping,
        additionalCost: _additional,
        tax: _tax,
        notes: _notesCtrl.text.trim(),
        supplierInstructions: _instructionsCtrl.text.trim(),
      );
      if (!draft && order.supplier == null) _snack('Orden guardada. Selecciona un suplidor antes de aprobar.');
      if (!draft) await _sharePdf(order);
      setState(() {
        _orders = [order, ..._orders];
        _cart = const [];
        _notesCtrl.clear();
      });
      _snack('Orden guardada correctamente.');
    } catch (e) {
      _snack('No fue posible completar la operación. No se realizaron cambios. $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _orderAction(Future<PurchaseOrderModel> Function() action, String message) async {
    try {
      final updated = await action();
      setState(() => _orders = [for (final o in _orders) if (o.id == updated.id) updated else o]);
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
        content: const Text('¿Desea actualizar el inventario con las cantidades recibidas pendientes?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Solo registrar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Actualizar inventario')),
        ],
      ),
    );
    if (update == null) return;
    await _orderAction(() => ref.read(purchasesRepositoryProvider).receive(order: order, updateInventory: update), update ? 'Inventario actualizado correctamente.' : 'Recepción registrada.');
  }

  Future<void> _sharePdf(PurchaseOrderModel order) async {
    final company = await ref.read(companySettingsProvider.future);
    final bytes = await buildPurchaseOrderPdf(order: order, company: company);
    final supplier = (order.supplier?.commercialName ?? 'Suplidor').replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
    await Printing.sharePdf(bytes: bytes, filename: 'Orden_Compra_${order.orderNumber}_$supplier.pdf');
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
        content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nombre comercial')),
          TextField(controller: contact, decoration: const InputDecoration(labelText: 'Persona de contacto')),
          TextField(controller: phone, decoration: const InputDecoration(labelText: 'Teléfono')),
          TextField(controller: whatsapp, decoration: const InputDecoration(labelText: 'WhatsApp')),
          TextField(controller: email, decoration: const InputDecoration(labelText: 'Correo')),
          TextField(controller: address, decoration: const InputDecoration(labelText: 'Dirección')),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final saved = await ref.read(purchasesRepositoryProvider).saveSupplier(SupplierModel(
            id: supplier?.id ?? '',
            commercialName: name.text.trim(),
            contactName: contact.text.trim(),
            phone: phone.text.trim(),
            whatsapp: whatsapp.text.trim(),
            email: email.text.trim(),
            address: address.text.trim(),
          ));
      setState(() => _suppliers = [saved, ..._suppliers.where((s) => s.id != saved.id)]);
      _snack('Suplidor guardado.');
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _deactivateSupplier(SupplierModel supplier) async {
    await ref.read(purchasesRepositoryProvider).deactivateSupplier(supplier.id);
    setState(() => _suppliers = _suppliers.where((s) => s.id != supplier.id).toList());
    _snack('Suplidor desactivado.');
  }

  void _showOrderDetail(PurchaseOrderModel order) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${order.orderNumber} · ${order.status}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
          Text(order.supplier?.commercialName ?? 'Sin suplidor'),
          const Divider(),
          for (final item in order.items)
            ListTile(
              title: Text(item.productName),
              subtitle: Text('Pedido ${_qty(item.quantity)} · Recibido ${_qty(item.receivedQuantity)} · Pendiente ${_qty(item.pendingQuantity)}'),
              trailing: Text(_money(item.subtotal)),
            ),
          const Divider(),
          _totalRow('Total general', _money(order.total), strong: true),
        ],
      ),
    );
  }

  Widget _moneyField(TextEditingController ctrl, String label) => TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      );

  Widget _totalRow(String label, String value, {bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: strong ? const TextStyle(fontWeight: FontWeight.w800) : null),
          Text(value, style: strong ? const TextStyle(fontWeight: FontWeight.w900) : null),
        ]),
      );

  void _snack(String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  String _money(double value) => formatRdCurrencyAccounting(value);
  String _qty(num value) => value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  double _parseAmount(String value) => double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
}
