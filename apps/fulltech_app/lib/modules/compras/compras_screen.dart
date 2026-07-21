import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/errors/api_exception.dart';
import '../../core/models/product_model.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/pdf_action_menu.dart';
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
  static const _draftStorageKey = 'purchase_order_draft_v1';

  late final TabController _tabs;
  final _searchCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _instructionsCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _shippingCtrl = TextEditingController(text: '0');
  final _additionalCtrl = TextEditingController(text: '0');
  final _taxCtrl = TextEditingController(text: '0');
  final _invoiceSearchCtrl = TextEditingController();
  final _invoiceFromCtrl = TextEditingController();
  final _invoiceToCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  Timer? _draftSaveTimer;
  bool _restoringDraft = false;
  List<ProductModel> _products = const [];
  List<SupplierModel> _suppliers = const [];
  List<PurchaseOrderModel> _orders = const [];
  List<PurchaseRecommendationModel> _recommendations = const [];
  List<PurchaseInvoiceModel> _purchaseInvoices = const [];
  List<PurchaseDraftItem> _cart = const [];
  String? _selectedCategory;
  String? _selectedSupplierId;
  String? _selectedOrderDetailId;
  String? _selectedSupplierDetailId;
  String? _invoiceSupplierFilterId;
  String? _selectedInvoiceDetailId;
  String _statusFilter = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
    for (final ctrl in [
      _notesCtrl,
      _instructionsCtrl,
      _discountCtrl,
      _shippingCtrl,
      _additionalCtrl,
      _taxCtrl,
    ]) {
      ctrl.addListener(_scheduleDraftSave);
    }
    for (final ctrl in [_invoiceSearchCtrl, _invoiceFromCtrl, _invoiceToCtrl]) {
      ctrl.addListener(() {
        if (mounted) setState(() {});
      });
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    _tabs.dispose();
    _searchCtrl.dispose();
    _notesCtrl.dispose();
    _instructionsCtrl.dispose();
    _discountCtrl.dispose();
    _shippingCtrl.dispose();
    _additionalCtrl.dispose();
    _taxCtrl.dispose();
    _invoiceSearchCtrl.dispose();
    _invoiceFromCtrl.dispose();
    _invoiceToCtrl.dispose();
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
        repo.listInvoices(),
      ]);
      if (!mounted) return;
      setState(() {
        _products = results[0] as List<ProductModel>;
        _suppliers = results[1] as List<SupplierModel>;
        _orders = results[2] as List<PurchaseOrderModel>;
        _recommendations = results[3] as List<PurchaseRecommendationModel>;
        _purchaseInvoices = results[4] as List<PurchaseInvoiceModel>;
        _loading = false;
      });
      await _restoreDraft();
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
            Tab(icon: Icon(Icons.folder_copy_outlined), text: 'Facturas'),
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
                _purchaseInvoicesTab(),
                _recommendationsTab(),
              ],
            ),
    );
  }

  Widget _newPurchaseTab() {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 1024;
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
                  ? 3
                  : width < 900
                  ? 4
                  : width < 1180
                  ? 5
                  : isWide
                  ? 7
                  : 5;
              final aspectRatio = width < 380
                  ? .98
                  : width < 720
                  ? 1.08
                  : 1.36;
              return GridView.builder(
                padding: EdgeInsets.fromLTRB(
                  isWide ? 16 : 12,
                  0,
                  isWide ? 10 : 12,
                  16,
                ),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: aspectRatio,
                  crossAxisSpacing: 7,
                  mainAxisSpacing: 7,
                ),
                itemCount: _visibleProducts.length,
                itemBuilder: (context, index) => _PurchaseProductCard(
                  product: _visibleProducts[index],
                  money: _money,
                  qty: _qty,
                  onTap: () => _quickAddProduct(_visibleProducts[index]),
                ),
              );
            },
          ),
        ),
      ],
    );
    final cart = _cartPanel();
    if (!isWide) return productGrid;
    return Row(
      children: [
        Expanded(child: productGrid),
        SizedBox(width: (size.width * .38).clamp(520.0, 720.0), child: cart),
      ],
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
                    onChanged: (value) => setState(() {
                      _selectedSupplierId = value;
                      _scheduleDraftSave();
                    }),
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
                              onDelete: () => setState(() {
                                _cart = [..._cart]..removeAt(index);
                                _scheduleDraftSave();
                              }),
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
                      final preview = OutlinedButton.icon(
                        onPressed: _cart.isEmpty || _saving
                            ? null
                            : _openDraftPdfPreview,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text(
                          'PDF',
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
                            preview,
                            const SizedBox(height: 8),
                            generate,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: draft),
                          const SizedBox(width: 8),
                          Expanded(child: preview),
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
    final canDeleteOrders =
        ref.watch(authStateProvider).user?.appRole.isAdmin ?? false;
    final visible = _orders
        .where((o) => _statusFilter.isEmpty || o.status == _statusFilter)
        .toList();
    final isWide = MediaQuery.sizeOf(context).width >= 980;
    PurchaseOrderModel? selected;
    for (final order in visible) {
      if (order.id == _selectedOrderDetailId) {
        selected = order;
        break;
      }
    }
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
              : Row(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) => _orderTile(
                          visible[index],
                          selected: visible[index].id == _selectedOrderDetailId,
                          showInlineDetail: isWide,
                          canDelete: canDeleteOrders,
                        ),
                      ),
                    ),
                    if (isWide)
                      Builder(
                        builder: (context) {
                          final selectedOrder = selected;
                          return SizedBox(
                            width: (MediaQuery.sizeOf(context).width * .38)
                                .clamp(500.0, 680.0),
                            child: _OrderDetailPanel(
                              order: selectedOrder,
                              money: _money,
                              qty: _qty,
                              onPdf: selectedOrder == null
                                  ? null
                                  : () => _openOrderPdfPreview(selectedOrder),
                              onSend: selectedOrder == null
                                  ? null
                                  : () =>
                                        _sendOrderPdfToSupplier(selectedOrder),
                              onReceive: selectedOrder == null
                                  ? null
                                  : () => _receive(selectedOrder),
                              onDuplicate: selectedOrder == null
                                  ? null
                                  : () => _orderAction(
                                      () => ref
                                          .read(purchasesRepositoryProvider)
                                          .duplicate(selectedOrder.id),
                                      'Orden duplicada.',
                                    ),
                              onDelete:
                                  selectedOrder == null || !canDeleteOrders
                                  ? null
                                  : () => _confirmDeleteOrder(selectedOrder),
                            ),
                          );
                        },
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _orderTile(
    PurchaseOrderModel order, {
    bool selected = false,
    bool showInlineDetail = false,
    bool canDelete = false,
  }) {
    final theme = Theme.of(context);
    final title =
        '${order.orderNumber} · ${order.supplier?.commercialName ?? 'Sin suplidor'}';
    final subtitle =
        '${order.items.length} artículos · ${_qty(order.items.fold(0, (sum, i) => sum + i.quantity))} unidades · ${order.status}';
    void open() {
      if (showInlineDetail) {
        setState(() => _selectedOrderDetailId = order.id);
      } else {
        _showOrderDetail(order, canDelete: canDelete);
      }
    }

    final actions = <PopupMenuEntry<String>>[
      const PopupMenuItem(value: 'pdf', child: Text('Ver PDF')),
      if (order.status == 'DRAFT')
        const PopupMenuItem(value: 'approve', child: Text('Aprobar')),
      if (['APPROVED', 'DRAFT'].contains(order.status))
        const PopupMenuItem(value: 'send', child: Text('Enviar')),
      if (['SENT', 'APPROVED', 'PARTIALLY_RECEIVED'].contains(order.status))
        const PopupMenuItem(
          value: 'receive',
          child: Text('Registrar recepción'),
        ),
      const PopupMenuItem(value: 'duplicate', child: Text('Duplicar')),
      if (canDelete) const PopupMenuDivider(),
      if (canDelete)
        const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
    ];
    void runAction(String value) {
      if (value == 'pdf') _openOrderPdfPreview(order);
      if (value == 'approve') {
        _orderAction(
          () => ref.read(purchasesRepositoryProvider).approve(order.id),
          'Orden aprobada.',
        );
      }
      if (value == 'send') _sendOrderPdfToSupplier(order);
      if (value == 'receive') _receive(order);
      if (value == 'duplicate') {
        _orderAction(
          () => ref.read(purchasesRepositoryProvider).duplicate(order.id),
          'Orden duplicada.',
        );
      }
      if (value == 'delete') _confirmDeleteOrder(order);
    }

    if (MediaQuery.sizeOf(context).width < 720) {
      return Card(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: theme.dividerColor.withValues(alpha: .45)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Acciones',
                      onSelected: runAction,
                      itemBuilder: (_) => actions,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF52657A)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _StatusChip(label: order.status),
                    const Spacer(),
                    Text(
                      _money(order.total),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    return ListTile(
      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(
        alpha: .35,
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle),
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
            onPressed: () => _openOrderPdfPreview(order),
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
                ? () => _sendOrderPdfToSupplier(order)
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
          if (canDelete)
            IconButton(
              tooltip: 'Eliminar',
              color: Theme.of(context).colorScheme.error,
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _confirmDeleteOrder(order),
            ),
        ],
      ),
      onTap: open,
    );
  }

  Widget _suppliersTab() {
    final isWide = MediaQuery.sizeOf(context).width >= 980;
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    SupplierModel? selected;
    for (final supplier in _suppliers) {
      if (supplier.id == _selectedSupplierDetailId) {
        selected = supplier;
        break;
      }
    }
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(isMobile ? 10 : 12),
          child: isMobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Suplidores',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: () => _supplierDialog(),
                      icon: const Icon(Icons.add_business_outlined),
                      label: const Text('Crear suplidor'),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Suplidores',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
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
              : Row(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        itemCount: _suppliers.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final s = _suppliers[index];
                          if (isMobile) {
                            return Card(
                              elevation: 0,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                                side: BorderSide(
                                  color: Theme.of(
                                    context,
                                  ).dividerColor.withValues(alpha: .45),
                                ),
                              ),
                              child: ListTile(
                                leading: Icon(
                                  s.isActive
                                      ? Icons.storefront_outlined
                                      : Icons.block_outlined,
                                ),
                                title: Text(
                                  s.commercialName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                subtitle: Text(
                                  [s.contactName, s.phone, s.whatsapp, s.email]
                                      .where((e) => (e ?? '').isNotEmpty)
                                      .join(' · '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                ),
                                onTap: () => _showSupplierDetail(s),
                              ),
                            );
                          }
                          return ListTile(
                            selected: s.id == _selectedSupplierDetailId,
                            selectedTileColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: .35),
                            leading: Icon(
                              s.isActive
                                  ? Icons.storefront_outlined
                                  : Icons.block_outlined,
                            ),
                            title: Text(
                              s.commercialName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              [
                                s.contactName,
                                s.phone,
                                s.whatsapp,
                                s.email,
                              ].where((e) => (e ?? '').isNotEmpty).join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              _money(s.totalPurchased),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            onTap: () {
                              if (isWide) {
                                setState(
                                  () => _selectedSupplierDetailId = s.id,
                                );
                              } else {
                                _supplierDialog(supplier: s);
                              }
                            },
                          );
                        },
                      ),
                    ),
                    if (isWide)
                      Builder(
                        builder: (context) {
                          final selectedSupplier = selected;
                          return SizedBox(
                            width: (MediaQuery.sizeOf(context).width * .35)
                                .clamp(460.0, 640.0),
                            child: _SupplierDetailPanel(
                              supplier: selectedSupplier,
                              money: _money,
                              onEdit: selectedSupplier == null
                                  ? null
                                  : () => _supplierDialog(
                                      supplier: selectedSupplier,
                                    ),
                              onDeactivate: selectedSupplier == null
                                  ? null
                                  : () => _deactivateSupplier(selectedSupplier),
                            ),
                          );
                        },
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _purchaseInvoicesTab() {
    final isWide = MediaQuery.sizeOf(context).width >= 980;
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final filtered = _purchaseInvoices.where((invoice) {
      final supplierMatch =
          _invoiceSupplierFilterId == null ||
          invoice.supplier.id == _invoiceSupplierFilterId;
      final query = _invoiceSearchCtrl.text.trim().toLowerCase();
      final queryMatch =
          query.isEmpty ||
          invoice.supplier.commercialName.toLowerCase().contains(query) ||
          (invoice.invoiceNumber ?? '').toLowerCase().contains(query) ||
          invoice.fileName.toLowerCase().contains(query) ||
          (invoice.notes ?? '').toLowerCase().contains(query) ||
          (invoice.uploadedByName ?? '').toLowerCase().contains(query);
      final date = invoice.invoiceDate;
      final from = _parseDateOnly(_invoiceFromCtrl.text);
      final to = _parseDateOnly(_invoiceToCtrl.text);
      final dateMatch =
          date == null ||
          ((from == null || !date.isBefore(from)) &&
              (to == null || date.isBefore(to.add(const Duration(days: 1)))));
      return supplierMatch && queryMatch && dateMatch;
    }).toList();
    PurchaseInvoiceModel? selected;
    for (final invoice in filtered) {
      if (invoice.id == _selectedInvoiceDetailId) {
        selected = invoice;
        break;
      }
    }
    if (isWide && selected == null && filtered.isNotEmpty) {
      selected = filtered.first;
    }
    return Column(
      children: [
        _invoiceFiltersHeader(isMobile: isMobile, resultCount: filtered.length),
        Expanded(
          child: filtered.isEmpty
              ? _EmptyPurchaseInvoices(onUpload: _uploadPurchaseInvoiceDialog)
              : Row(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          isMobile ? 10 : 12,
                          0,
                          isMobile ? 10 : 0,
                          12,
                        ),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            SizedBox(height: isMobile ? 8 : 0),
                        itemBuilder: (context, index) {
                          final invoice = filtered[index];
                          return _purchaseInvoiceTile(
                            invoice,
                            selected: invoice.id == selected?.id,
                            inline: isWide,
                          );
                        },
                      ),
                    ),
                    if (isWide)
                      SizedBox(
                        width: (MediaQuery.sizeOf(context).width * .44).clamp(
                          620.0,
                          840.0,
                        ),
                        child: _PurchaseInvoiceDetailPanel(
                          invoice: selected,
                          money: _money,
                          dateLabel: _dateLabel,
                          fileSizeLabel: _fileSizeLabel,
                          isImage: _invoiceIsImage,
                          isPdf: _invoiceIsPdf,
                          onOpen: selected == null
                              ? null
                              : () => _openInvoiceFile(selected!),
                          onDelete: selected == null
                              ? null
                              : () => _confirmDeleteInvoice(selected!),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _invoiceFiltersHeader({
    required bool isMobile,
    required int resultCount,
  }) {
    final title = Text(
      'Facturas de compra',
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
    );
    final search = TextField(
      controller: _invoiceSearchCtrl,
      decoration: _fieldDecoration('Buscar factura', icon: Icons.search),
    );
    final from = TextField(
      controller: _invoiceFromCtrl,
      keyboardType: TextInputType.datetime,
      decoration: _fieldDecoration('Desde', icon: Icons.event_outlined),
    );
    final to = TextField(
      controller: _invoiceToCtrl,
      keyboardType: TextInputType.datetime,
      decoration: _fieldDecoration('Hasta', icon: Icons.event_outlined),
    );
    final upload = FilledButton.icon(
      onPressed: _uploadPurchaseInvoiceDialog,
      icon: const Icon(Icons.upload_file_outlined),
      label: const Text('Subir factura'),
    );
    final clear = IconButton.filledTonal(
      tooltip: 'Limpiar filtros',
      onPressed: () {
        setState(() {
          _invoiceSupplierFilterId = null;
          _invoiceSearchCtrl.clear();
          _invoiceFromCtrl.clear();
          _invoiceToCtrl.clear();
          _selectedInvoiceDetailId = null;
        });
      },
      icon: const Icon(Icons.filter_alt_off_outlined),
    );

    return Padding(
      padding: EdgeInsets.all(isMobile ? 10 : 12),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                title,
                const SizedBox(height: 8),
                _invoiceSupplierFilter(),
                const SizedBox(height: 8),
                search,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: from),
                    const SizedBox(width: 8),
                    Expanded(child: to),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: upload),
                    const SizedBox(width: 8),
                    clear,
                  ],
                ),
                const SizedBox(height: 6),
                Text('$resultCount registros'),
              ],
            )
          : Row(
              children: [
                Expanded(child: title),
                SizedBox(width: 260, child: _invoiceSupplierFilter()),
                const SizedBox(width: 10),
                SizedBox(width: 260, child: search),
                const SizedBox(width: 10),
                SizedBox(width: 130, child: from),
                const SizedBox(width: 8),
                SizedBox(width: 130, child: to),
                const SizedBox(width: 8),
                clear,
                const SizedBox(width: 8),
                upload,
              ],
            ),
    );
  }

  Widget _invoiceSupplierFilter() {
    return DropdownButtonFormField<String>(
      initialValue: _invoiceSupplierFilterId,
      isExpanded: true,
      decoration: _fieldDecoration(
        'Filtrar por suplidor',
        icon: Icons.storefront_outlined,
      ),
      items: [
        const DropdownMenuItem<String>(
          value: null,
          child: Text('Todos los suplidores'),
        ),
        for (final supplier in _suppliers)
          DropdownMenuItem(
            value: supplier.id,
            child: Text(
              supplier.commercialName,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) => setState(() {
        _invoiceSupplierFilterId = value;
        _selectedInvoiceDetailId = null;
      }),
    );
  }

  Widget _purchaseInvoiceTile(
    PurchaseInvoiceModel invoice, {
    required bool selected,
    required bool inline,
  }) {
    final theme = Theme.of(context);
    final title = invoice.invoiceNumber?.isNotEmpty == true
        ? 'Factura ${invoice.invoiceNumber}'
        : invoice.fileName;
    final subtitle = [
      invoice.supplier.commercialName,
      _dateLabel(invoice.invoiceDate),
      _fileSizeLabel(invoice.fileSize),
    ].where((item) => item.isNotEmpty).join(' · ');
    void open() {
      if (inline) {
        setState(() => _selectedInvoiceDetailId = invoice.id);
      } else {
        _showPurchaseInvoiceDetail(invoice);
      }
    }

    if (MediaQuery.sizeOf(context).width < 720) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: theme.dividerColor.withValues(alpha: .45)),
        ),
        child: ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          subtitle: Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: open,
        ),
      );
    }
    return ListTile(
      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer.withValues(
        alpha: .35,
      ),
      leading: const Icon(Icons.description_outlined),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(
        _dateLabel(invoice.invoiceDate),
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      onTap: open,
    );
  }

  Widget _recommendationsTab() {
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    return ListView.separated(
      padding: EdgeInsets.all(isMobile ? 10 : 12),
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
          child: isMobile
              ? Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 48,
                            height: 48,
                            child: ProductNetworkImage(
                              imageUrl: r.product.displayFotoUrl ?? '',
                              productId: r.product.id,
                              productName: r.product.nombre,
                              originalUrl: r.product.originalFotoUrl,
                              fit: BoxFit.cover,
                              fallback: const Icon(Icons.inventory_2_outlined),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.product.nombre,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${r.reason} · Stock ${_qty(r.stock)} · Ordenado ${_qty(r.alreadyOrdered)}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF52657A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        onPressed: r.suggestedQuantity <= 0
                            ? null
                            : () => _quickAddProduct(
                                r.product,
                                initialQty: r.suggestedQuantity,
                              ),
                        icon: const Icon(Icons.add_shopping_cart_outlined),
                        label: Text('Agregar ${_qty(r.suggestedQuantity)}'),
                      ),
                    ],
                  ),
                )
              : ListTile(
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
                        : () => _quickAddProduct(
                            r.product,
                            initialQty: r.suggestedQuantity,
                          ),
                    icon: const Icon(Icons.add_shopping_cart_outlined),
                    label: const Text('Agregar'),
                  ),
                ),
        );
      },
    );
  }

  void _quickAddProduct(ProductModel product, {double initialQty = 1}) {
    final idx = _cart.indexWhere((item) => item.productId == product.id);
    setState(() {
      if (idx >= 0) {
        final next = [..._cart];
        next[idx] = next[idx].copyWith(
          quantity: next[idx].quantity + initialQty,
          supplierId: next[idx].supplierId ?? _selectedSupplierId,
        );
        _cart = next;
      } else {
        _cart = [
          ..._cart,
          PurchaseDraftItem(
            product: product,
            productId: product.id,
            productName: product.nombre,
            productCode: product.codigo,
            description: product.descripcion,
            image: product.displayFotoUrl,
            quantity: initialQty.clamp(.0001, double.infinity).toDouble(),
            unitCost: product.costo.clamp(0, double.infinity).toDouble(),
            supplierId: _selectedSupplierId,
          ),
        ];
      }
      _scheduleDraftSave();
    });
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
    setState(() {
      _cart = [
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
      ];
      _scheduleDraftSave();
    });
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
      _scheduleDraftSave();
    });
  }

  Future<void> _saveOrder({required bool draft}) async {
    if (_cart.isEmpty) return _snack('Agrega al menos un producto.');
    setState(() => _saving = true);
    try {
      final order = await _persistCurrentOrder(clearDraft: true);
      if (!draft && order.supplier == null) {
        _snack('Orden guardada. Selecciona un suplidor antes de aprobar.');
      }
      if (!draft) await _openOrderPdfPreview(order);
      _snack('Orden guardada correctamente.');
    } catch (e) {
      _snack(
        'No fue posible completar la operación. No se realizaron cambios. $e',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<PurchaseOrderModel> _persistCurrentOrder({
    required bool clearDraft,
  }) async {
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
    if (!mounted) return order;
    setState(() => _orders = [order, ..._orders]);
    if (clearDraft) {
      _restoringDraft = true;
      setState(() {
        _cart = const [];
        _notesCtrl.clear();
        _instructionsCtrl.clear();
      });
      _restoringDraft = false;
      _draftSaveTimer?.cancel();
      await _clearDraft();
    }
    return order;
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

  Future<void> _confirmDeleteOrder(PurchaseOrderModel order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar orden de compra'),
        content: Text(
          '¿Seguro que deseas eliminar la orden ${order.orderNumber}? Esta acción la ocultará del módulo de compras.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(purchasesRepositoryProvider).deleteOrder(order.id);
      setState(() {
        _orders = [
          for (final item in _orders)
            if (item.id != order.id) item,
        ];
        if (_selectedOrderDetailId == order.id) {
          _selectedOrderDetailId = null;
        }
      });
      _snack('Orden eliminada.');
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

  Future<void> _openDraftPdfPreview() async {
    if (_cart.isEmpty) {
      _snack('Agrega al menos un producto para generar PDF.');
      return;
    }
    await _openOrderPdfPreview(
      _buildDraftOrderForPdf(),
      persistBeforeShare: true,
    );
  }

  PurchaseOrderModel _buildDraftOrderForPdf() {
    SupplierModel? supplier;
    for (final item in _suppliers) {
      if (item.id == _selectedSupplierId) {
        supplier = item;
        break;
      }
    }
    return PurchaseOrderModel(
      id: '',
      orderNumber: 'BORRADOR',
      supplier: supplier,
      status: 'DRAFT',
      orderDate: DateTime.now(),
      subtotal: _subtotal,
      discount: _discount,
      shippingCost: _shipping,
      additionalCost: _additional,
      tax: _tax,
      total: _total,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      supplierInstructions: _instructionsCtrl.text.trim().isEmpty
          ? null
          : _instructionsCtrl.text.trim(),
      items: [
        for (var i = 0; i < _cart.length; i++)
          PurchaseOrderItemModel(
            id: 'draft_$i',
            productName: _cart[i].productName,
            productCode: _cart[i].productCode,
            image: _cart[i].image,
            quantity: _cart[i].quantity,
            receivedQuantity: 0,
            pendingQuantity: _cart[i].quantity,
            unitCost: _cart[i].unitCost,
            subtotal: _cart[i].subtotal,
            notes: _cart[i].notes,
          ),
      ],
    );
  }

  Future<void> _openOrderPdfPreview(
    PurchaseOrderModel order, {
    bool persistBeforeShare = false,
  }) async {
    final company = await ref.read(companySettingsProvider.future);
    final bytes = await buildPurchaseOrderPdf(order: order, company: company);
    final fileName = _purchaseOrderPdfFileName(order);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var busy = false;
        String? notice;
        bool noticeIsError = false;
        final media = MediaQuery.sizeOf(dialogContext);
        final compact = media.width < 560;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void showNotice(String message, {bool isError = false}) {
              setDialogState(() {
                notice = message;
                noticeIsError = isError;
              });
            }

            Future<void> shareWithSupplier(BuildContext launchContext) async {
              setDialogState(() => busy = true);
              try {
                showNotice('Preparando enlace PDF para el suplidor...');
                final persisted = persistBeforeShare
                    ? await _persistCurrentOrder(clearDraft: true)
                    : order;
                final shareBytes = persistBeforeShare
                    ? await buildPurchaseOrderPdf(
                        order: persisted,
                        company: company,
                      )
                    : bytes;
                if (!launchContext.mounted) return;
                await _sharePurchaseOrderLinkWithSupplier(
                  order: persisted,
                  pdfBytes: shareBytes,
                  launchContext: launchContext,
                ).timeout(const Duration(seconds: 25));
                showNotice('WhatsApp abierto con el enlace de la orden.');
                await _orderAction(
                  () => ref
                      .read(purchasesRepositoryProvider)
                      .markSent(persisted.id),
                  'Orden marcada como enviada.',
                );
              } on TimeoutException {
                showNotice(
                  'Tiempo de espera agotado preparando el enlace PDF.',
                  isError: true,
                );
              } catch (e) {
                showNotice(
                  'No se pudo enviar la orden al suplidor: $e',
                  isError: true,
                );
              } finally {
                if (context.mounted) setDialogState(() => busy = false);
              }
            }

            return Dialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              insetPadding: EdgeInsets.symmetric(
                horizontal: compact ? 6 : 20,
                vertical: compact ? 6 : 16,
              ),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: compact ? media.width - 12 : media.width * .94,
                height: compact ? media.height * .96 : media.height * .92,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
                      child: Row(
                        children: [
                          const Icon(Icons.picture_as_pdf_outlined),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'PDF orden de compra · ${order.orderNumber}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (busy)
                            const Padding(
                              padding: EdgeInsets.only(right: 10),
                              child: SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                          PdfActionMenu(
                            bytes: bytes,
                            fileName: fileName,
                            compact: compact,
                            shareClientLabel: 'Compartir con suplidor',
                            onShareWithClient: busy ? null : shareWithSupplier,
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    if (notice != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: noticeIsError
                              ? const Color(0xFFFFEBEE)
                              : const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: noticeIsError
                                ? const Color(0xFFE57373)
                                : const Color(0xFF81C784),
                          ),
                        ),
                        child: Text(
                          notice!,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: noticeIsError
                                ? const Color(0xFFB71C1C)
                                : const Color(0xFF1B5E20),
                          ),
                        ),
                      ),
                    Expanded(
                      child: ColoredBox(
                        color: Colors.white,
                        child: PdfPreview(
                          canChangePageFormat: false,
                          canChangeOrientation: false,
                          canDebug: false,
                          allowPrinting: false,
                          allowSharing: false,
                          maxPageWidth: compact ? 700 : 980,
                          scrollViewDecoration: const BoxDecoration(
                            color: Colors.white,
                          ),
                          pdfPreviewPageDecoration: const BoxDecoration(
                            color: Colors.white,
                            boxShadow: <BoxShadow>[],
                          ),
                          build: (_) async => bytes,
                        ),
                      ),
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

  Future<void> _sendOrderPdfToSupplier(PurchaseOrderModel order) async {
    try {
      final company = await ref.read(companySettingsProvider.future);
      final bytes = await buildPurchaseOrderPdf(order: order, company: company);
      if (!mounted) return;
      await _sharePurchaseOrderLinkWithSupplier(
        order: order,
        pdfBytes: bytes,
        launchContext: context,
      ).timeout(const Duration(seconds: 25));
      await _orderAction(
        () => ref.read(purchasesRepositoryProvider).markSent(order.id),
        'Orden enviada al suplidor.',
      );
    } on TimeoutException {
      _snack('Tiempo de espera agotado preparando el enlace PDF.');
    } catch (e) {
      _snack('No se pudo enviar la orden al suplidor: $e');
    }
  }

  Future<void> _sharePurchaseOrderLinkWithSupplier({
    required PurchaseOrderModel order,
    required List<int> pdfBytes,
    required BuildContext launchContext,
  }) async {
    final phone = _normalizeWhatsAppLinkPhone(
      order.supplier?.whatsapp ?? order.supplier?.phone,
    );
    if (phone.isEmpty) {
      throw ApiException('El suplidor no tiene teléfono o WhatsApp válido.');
    }
    final pdfUrl = await ref
        .read(purchasesRepositoryProvider)
        .createPdfShareLink(
          purchaseOrderId: order.id,
          pdfBytes: pdfBytes,
          fileName: _purchaseOrderPdfFileName(order),
        );
    final uri = Uri.https('wa.me', '/$phone', {
      'text': _buildSupplierWhatsAppMessage(order, pdfUrl),
    });
    if (!launchContext.mounted) return;
    await safeOpenWhatsApp(
      launchContext,
      uri,
      copiedMessage: 'No se pudo abrir WhatsApp. Enlace de orden copiado.',
    );
  }

  String _purchaseOrderPdfFileName(PurchaseOrderModel order) {
    final supplier = (order.supplier?.commercialName ?? 'Suplidor').replaceAll(
      RegExp(r'[^A-Za-z0-9_-]+'),
      '_',
    );
    final number = order.orderNumber.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]+'),
      '_',
    );
    return 'Orden_Compra_${number}_$supplier.pdf';
  }

  String _normalizeWhatsAppLinkPhone(String? value) {
    var digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '').trim();
    if (digits.length == 10 && digits.startsWith(RegExp(r'[268]'))) {
      digits = '1$digits';
    }
    if (digits.length == 11 && digits.startsWith('1')) return digits;
    if (digits.length >= 11 && digits.length <= 15) return digits;
    return '';
  }

  String _buildSupplierWhatsAppMessage(
    PurchaseOrderModel order,
    String pdfUrl,
  ) {
    final supplierName = (order.supplier?.commercialName ?? '').trim().isEmpty
        ? 'suplidor'
        : order.supplier!.commercialName.trim();
    return 'Hola $supplierName, te compartimos una orden de compra en PDF.\n'
        'Puedes abrir el enlace para ver o descargar la orden.\n'
        'Orden: ${order.orderNumber}\n'
        'Total: ${_money(order.total)}\n'
        'PDF: $pdfUrl';
  }

  Future<void> _uploadPurchaseInvoiceDialog() async {
    if (_suppliers.isEmpty) {
      _snack('Primero crea un suplidor para asociar la factura.');
      return;
    }
    String? supplierId = _invoiceSupplierFilterId ?? _selectedSupplierId;
    if (supplierId == null || !_suppliers.any((s) => s.id == supplierId)) {
      supplierId = _suppliers.first.id;
    }
    PlatformFile? pickedFile;
    final numberCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Subir factura de compra'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: supplierId,
                      isExpanded: true,
                      decoration: _fieldDecoration(
                        'Suplidor',
                        icon: Icons.storefront_outlined,
                      ),
                      items: [
                        for (final supplier in _suppliers)
                          DropdownMenuItem(
                            value: supplier.id,
                            child: Text(
                              supplier.commercialName,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) => setDialogState(() {
                        supplierId = value;
                      }),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: numberCtrl,
                      decoration: _fieldDecoration(
                        'Número de factura (opcional)',
                        icon: Icons.tag_outlined,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notesCtrl,
                      minLines: 2,
                      maxLines: 4,
                      decoration: _fieldDecoration(
                        'Notas',
                        icon: Icons.notes_outlined,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: const [
                            'pdf',
                            'png',
                            'jpg',
                            'jpeg',
                            'webp',
                            'doc',
                            'docx',
                            'xls',
                            'xlsx',
                          ],
                          withData: true,
                        );
                        final file = result?.files.single;
                        if (file == null) return;
                        setDialogState(() => pickedFile = file);
                      },
                      icon: const Icon(Icons.attach_file_outlined),
                      label: Text(
                        pickedFile == null
                            ? 'Seleccionar archivo'
                            : pickedFile!.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'La fecha se guarda automáticamente al subir.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF52657A),
                        ),
                      ),
                    ),
                    if (pickedFile != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _fileSizeLabel(pickedFile!.size),
                          style: const TextStyle(color: Color(0xFF52657A)),
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
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Guardar factura'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final file = pickedFile;
    final selectedSupplierId = supplierId;
    if (selectedSupplierId == null) {
      _snack('Selecciona un suplidor.');
      return;
    }
    if (file == null) {
      _snack('Selecciona el archivo de la factura.');
      return;
    }
    try {
      final invoice = await ref
          .read(purchasesRepositoryProvider)
          .uploadInvoice(
            file: file,
            supplierId: selectedSupplierId,
            invoiceNumber: numberCtrl.text,
            notes: notesCtrl.text,
          );
      setState(() {
        _purchaseInvoices = [
          invoice,
          ..._purchaseInvoices.where((item) => item.id != invoice.id),
        ];
        _invoiceSupplierFilterId ??= invoice.supplier.id;
        _selectedInvoiceDetailId = invoice.id;
      });
      _snack('Factura de compra guardada.');
    } catch (e) {
      _snack('$e');
    }
  }

  void _showPurchaseInvoiceDetail(PurchaseInvoiceModel invoice) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .9,
        child: _PurchaseInvoiceDetailPanel(
          invoice: invoice,
          money: _money,
          dateLabel: _dateLabel,
          fileSizeLabel: _fileSizeLabel,
          isImage: _invoiceIsImage,
          isPdf: _invoiceIsPdf,
          onOpen: () => _openInvoiceFile(invoice),
          onDelete: () => _confirmDeleteInvoice(invoice),
        ),
      ),
    );
  }

  Future<void> _openInvoiceFile(PurchaseInvoiceModel invoice) async {
    final url = invoice.fileUrl.trim();
    if (url.isEmpty) {
      _snack('La factura no tiene enlace de archivo.');
      return;
    }
    await safeOpenUrl(
      context,
      Uri.parse(url),
      copiedMessage: 'No se pudo abrir la factura. Enlace copiado.',
    );
  }

  Future<void> _confirmDeleteInvoice(PurchaseInvoiceModel invoice) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar factura'),
        content: Text(
          '¿Seguro que deseas eliminar el registro ${invoice.invoiceNumber ?? invoice.fileName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(purchasesRepositoryProvider).deleteInvoice(invoice.id);
      setState(() {
        _purchaseInvoices = [
          for (final item in _purchaseInvoices)
            if (item.id != invoice.id) item,
        ];
        if (_selectedInvoiceDetailId == invoice.id) {
          _selectedInvoiceDetailId = null;
        }
      });
      _snack('Factura eliminada.');
    } catch (e) {
      _snack('$e');
    }
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
    if (name.text.trim().isEmpty) {
      _snack('Escribe el nombre comercial del suplidor.');
      return;
    }
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
      setState(() {
        _suppliers = [saved, ..._suppliers.where((s) => s.id != saved.id)];
        _selectedSupplierId ??= saved.id;
        _scheduleDraftSave();
      });
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

  void _showOrderDetail(PurchaseOrderModel order, {bool canDelete = false}) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .94,
        child: _OrderDetailPanel(
          order: order,
          money: _money,
          qty: _qty,
          onPdf: () => _openOrderPdfPreview(order),
          onSend: () => _sendOrderPdfToSupplier(order),
          onReceive: () => _receive(order),
          onDuplicate: () => _orderAction(
            () => ref.read(purchasesRepositoryProvider).duplicate(order.id),
            'Orden duplicada.',
          ),
          onDelete: canDelete ? () => _confirmDeleteOrder(order) : null,
        ),
      ),
    );
  }

  void _showSupplierDetail(SupplierModel supplier) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .9,
        child: _SupplierDetailPanel(
          supplier: supplier,
          money: _money,
          onEdit: () {
            Navigator.pop(context);
            _supplierDialog(supplier: supplier);
          },
          onDeactivate: () {
            Navigator.pop(context);
            _deactivateSupplier(supplier);
          },
        ),
      ),
    );
  }

  void _openCartSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (context) =>
          FractionallySizedBox(heightFactor: .96, child: _cartPanel()),
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

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
  String _money(double value) => formatRdCurrencyAccounting(value);
  String _qty(num value) =>
      value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  double _parseAmount(String value) =>
      double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
  String _dateLabel(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  String _fileSizeLabel(int bytes) {
    if (bytes <= 0) return 'Archivo';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }

  DateTime? _parseDateOnly(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  bool _invoiceIsImage(PurchaseInvoiceModel invoice) {
    final value = '${invoice.mimeType} ${invoice.fileName}'.toLowerCase();
    return value.contains('image/') ||
        value.endsWith('.png') ||
        value.endsWith('.jpg') ||
        value.endsWith('.jpeg') ||
        value.endsWith('.webp');
  }

  bool _invoiceIsPdf(PurchaseInvoiceModel invoice) {
    final value = '${invoice.mimeType} ${invoice.fileName}'.toLowerCase();
    return value.contains('application/pdf') || value.endsWith('.pdf');
  }

  void _scheduleDraftSave() {
    if (_restoringDraft) return;
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 350), () {
      unawaited(_saveDraft());
    });
  }

  Future<void> _saveDraft() async {
    if (_cart.isEmpty) {
      await _clearDraft();
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _draftStorageKey,
        jsonEncode({
          'supplierId': _selectedSupplierId,
          'notes': _notesCtrl.text,
          'instructions': _instructionsCtrl.text,
          'discount': _discountCtrl.text,
          'shipping': _shippingCtrl.text,
          'additional': _additionalCtrl.text,
          'tax': _taxCtrl.text,
          'items': _cart.map((item) => item.toDraftJson()).toList(),
        }),
      );
    } catch (_) {
      // El borrador local no debe bloquear la operacion principal.
    }
  }

  Future<void> _restoreDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftStorageKey);
      if (raw == null || raw.trim().isEmpty) return;
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final items = ((data['items'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (row) =>
                PurchaseDraftItem.fromDraftJson(Map<String, dynamic>.from(row)),
          )
          .where((item) => item.productName.trim().isNotEmpty)
          .toList();
      if (!mounted) return;
      _restoringDraft = true;
      setState(() {
        final supplierId = data['supplierId'];
        _selectedSupplierId =
            supplierId is String &&
                _suppliers.any((supplier) => supplier.id == supplierId)
            ? supplierId
            : null;
        _notesCtrl.text = '${data['notes'] ?? ''}';
        _instructionsCtrl.text = '${data['instructions'] ?? ''}';
        _discountCtrl.text = '${data['discount'] ?? '0'}';
        _shippingCtrl.text = '${data['shipping'] ?? '0'}';
        _additionalCtrl.text = '${data['additional'] ?? '0'}';
        _taxCtrl.text = '${data['tax'] ?? '0'}';
        _cart = items;
      });
    } catch (_) {
      await _clearDraft();
    } finally {
      _restoringDraft = false;
    }
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftStorageKey);
    } catch (_) {}
  }
}

class _PurchaseInvoiceDetailPanel extends StatelessWidget {
  const _PurchaseInvoiceDetailPanel({
    required this.invoice,
    required this.money,
    required this.dateLabel,
    required this.fileSizeLabel,
    required this.isImage,
    required this.isPdf,
    this.onOpen,
    this.onDelete,
  });

  final PurchaseInvoiceModel? invoice;
  final String Function(double value) money;
  final String Function(DateTime? value) dateLabel;
  final String Function(int bytes) fileSizeLabel;
  final bool Function(PurchaseInvoiceModel invoice) isImage;
  final bool Function(PurchaseInvoiceModel invoice) isPdf;
  final VoidCallback? onOpen;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final current = invoice;
    final theme = Theme.of(context);
    if (current == null) {
      return Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: theme.dividerColor)),
          color: theme.colorScheme.surface,
        ),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Selecciona una factura para ver el detalle.'),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: theme.dividerColor)),
        color: theme.colorScheme.surface,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.description_outlined,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        current.invoiceNumber?.isNotEmpty == true
                            ? 'Factura ${current.invoiceNumber}'
                            : current.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        current.supplier.commercialName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFF52657A)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: _InfoPill(
                          icon: Icons.event_outlined,
                          label: 'Fecha',
                          value: dateLabel(current.invoiceDate),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _InfoPill(
                          icon: Icons.insert_drive_file_outlined,
                          label: 'Archivo',
                          value: fileSizeLabel(current.fileSize),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: _InvoicePreview(
                      invoice: current,
                      isImage: isImage(current),
                      isPdf: isPdf(current),
                      onOpen: onOpen,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Column(
                    children: [
                      _DetailRow(label: 'Archivo', value: current.fileName),
                      if ((current.notes ?? '').isNotEmpty)
                        _DetailRow(label: 'Notas', value: current.notes!),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onOpen,
                    icon: const Icon(Icons.open_in_new_outlined),
                    label: const Text('Abrir archivo'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: 'Eliminar',
                  color: theme.colorScheme.error,
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPurchaseInvoices extends StatelessWidget {
  const _EmptyPurchaseInvoices({required this.onUpload});

  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_copy_outlined, size: 46),
            const SizedBox(height: 12),
            const Text(
              'No hay facturas de compra guardadas.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onUpload,
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Subir primera factura'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoicePreview extends StatelessWidget {
  const _InvoicePreview({
    required this.invoice,
    required this.isImage,
    required this.isPdf,
    this.onOpen,
  });

  final PurchaseInvoiceModel invoice;
  final bool isImage;
  final bool isPdf;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = invoice.fileUrl.trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: .35,
          ),
          border: Border.all(color: theme.dividerColor.withValues(alpha: .7)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: url.isEmpty
            ? const Center(child: Text('Archivo no disponible'))
            : isImage
            ? InteractiveViewer(
                minScale: .8,
                maxScale: 4,
                child: Center(
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(child: CircularProgressIndicator());
                    },
                    errorBuilder: (context, error, stack) => _PreviewFallback(
                      icon: Icons.broken_image_outlined,
                      message: 'No se pudo cargar la imagen.',
                      onOpen: onOpen,
                    ),
                  ),
                ),
              )
            : isPdf
            ? SfPdfViewer.network(
                url,
                canShowScrollHead: true,
                canShowPaginationDialog: true,
              )
            : _PreviewFallback(
                icon: Icons.insert_drive_file_outlined,
                message: 'Vista previa no disponible para este archivo.',
                onOpen: onOpen,
              ),
      ),
    );
  }
}

class _PreviewFallback extends StatelessWidget {
  const _PreviewFallback({
    required this.icon,
    required this.message,
    this.onOpen,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 42),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new_outlined),
              label: const Text('Abrir archivo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF52657A),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  value.isEmpty ? 'Sin fecha' : value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF52657A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderDetailPanel extends StatelessWidget {
  const _OrderDetailPanel({
    required this.order,
    required this.money,
    required this.qty,
    required this.onPdf,
    required this.onSend,
    required this.onReceive,
    required this.onDuplicate,
    required this.onDelete,
  });

  final PurchaseOrderModel? order;
  final String Function(double) money;
  final String Function(num) qty;
  final VoidCallback? onPdf;
  final VoidCallback? onSend;
  final VoidCallback? onReceive;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = order;
    return Container(
      height: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          left: BorderSide(color: theme.dividerColor.withValues(alpha: .45)),
        ),
      ),
      child: selected == null
          ? const Center(
              child: Text('Selecciona una orden para ver el detalle'),
            )
          : SafeArea(
              left: false,
              child: Padding(
                padding: const EdgeInsets.all(14),
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
                            selected.orderNumber,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _MiniChip(label: selected.status),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      selected.supplier?.commercialName ?? 'Sin suplidor',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: onPdf,
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('PDF'),
                        ),
                        FilledButton.icon(
                          onPressed: onSend,
                          icon: const Icon(Icons.send_outlined),
                          label: const Text('Enviar'),
                        ),
                        OutlinedButton.icon(
                          onPressed: onReceive,
                          icon: const Icon(Icons.inventory_outlined),
                          label: const Text('Recibir'),
                        ),
                        IconButton.filledTonal(
                          onPressed: onDuplicate,
                          tooltip: 'Duplicar',
                          icon: const Icon(Icons.copy_outlined),
                        ),
                        IconButton.filledTonal(
                          onPressed: onDelete,
                          tooltip: 'Eliminar',
                          icon: const Icon(Icons.delete_outline_rounded),
                          color: theme.colorScheme.error,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _TotalsPanel(
                      units: qty(
                        selected.items.fold<num>(
                          0,
                          (sum, item) => sum + item.quantity,
                        ),
                      ),
                      products: '${selected.items.length}',
                      subtotal: money(selected.subtotal),
                      total: money(selected.total),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: selected.items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final item = selected.items[index];
                          return Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: .45),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.productName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        '${qty(item.quantity)} x ${money(item.unitCost)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  money(item.subtotal),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    if ((selected.notes ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        selected.notes!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}

class _SupplierDetailPanel extends StatelessWidget {
  const _SupplierDetailPanel({
    required this.supplier,
    required this.money,
    required this.onEdit,
    required this.onDeactivate,
  });

  final SupplierModel? supplier;
  final String Function(double) money;
  final VoidCallback? onEdit;
  final VoidCallback? onDeactivate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = supplier;
    return Container(
      height: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          left: BorderSide(color: theme.dividerColor.withValues(alpha: .45)),
        ),
      ),
      child: selected == null
          ? const Center(
              child: Text('Selecciona un suplidor para ver el detalle'),
            )
          : SafeArea(
              left: false,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.storefront_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            selected.commercialName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        _MiniChip(
                          label: selected.isActive ? 'Activo' : 'Inactivo',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _SupplierInfoLine(
                      icon: Icons.person_outline,
                      label: selected.contactName ?? 'Sin contacto',
                    ),
                    _SupplierInfoLine(
                      icon: Icons.phone_outlined,
                      label: selected.phone ?? 'Sin teléfono',
                    ),
                    _SupplierInfoLine(
                      icon: Icons.chat_outlined,
                      label: selected.whatsapp ?? 'Sin WhatsApp',
                    ),
                    _SupplierInfoLine(
                      icon: Icons.mail_outline,
                      label: selected.email ?? 'Sin correo',
                    ),
                    _SupplierInfoLine(
                      icon: Icons.location_on_outlined,
                      label: selected.address ?? 'Sin dirección',
                    ),
                    const SizedBox(height: 12),
                    _TotalsPanel(
                      units: '${selected.ordersCount}',
                      products: 'compras',
                      subtotal: money(selected.totalPurchased),
                      total: money(selected.totalPurchased),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: onEdit,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Editar'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: onDeactivate,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Desactivar'),
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

class _SupplierInfoLine extends StatelessWidget {
  const _SupplierInfoLine({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
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
    final theme = Theme.of(context);
    final search = Row(
      children: [
        SizedBox(
          width: 44,
          height: 42,
          child: FilledButton(
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => onSearchChanged(searchController.text),
            child: const Icon(Icons.search),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SizedBox(
            height: 42,
            child: TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Buscar producto por nombre o código...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: theme.dividerColor.withValues(alpha: .45),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: theme.dividerColor.withValues(alpha: .45),
                  ),
                ),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                suffixIcon: searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar búsqueda',
                        onPressed: () {
                          searchController.clear();
                          onSearchChanged('');
                        },
                        icon: const Icon(Icons.close, size: 18),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
    final externalButton = OutlinedButton.icon(
      onPressed: onAddExternal,
      icon: const Icon(Icons.add_box_outlined, size: 17),
      label: const Text('Nuevo producto', overflow: TextOverflow.ellipsis),
    );
    final orderButton = onOpenOrder == null
        ? null
        : FilledButton.icon(
            onPressed: onOpenOrder,
            icon: const Icon(Icons.receipt_long_outlined, size: 17),
            label: Text(
              itemCount == 0 ? 'Detalle' : '$itemCount · $total',
              overflow: TextOverflow.ellipsis,
            ),
          );
    final actions = compact
        ? Row(
            children: [
              Expanded(child: externalButton),
              if (orderButton != null) ...[
                const SizedBox(width: 8),
                Expanded(child: orderButton),
              ],
            ],
          )
        : Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [externalButton, if (orderButton != null) orderButton],
          );
    final categoryChips = SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final category = index == 0 ? null : categories[index - 1];
          final selected = category == selectedCategory;
          return ChoiceChip(
            selected: selected,
            showCheckmark: false,
            avatar: Icon(
              category == null
                  ? Icons.apps_outlined
                  : Icons.inventory_2_outlined,
              size: 15,
              color: selected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.primary,
            ),
            label: Text(
              category ?? 'Todas',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            labelStyle: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: selected
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurface,
            ),
            selectedColor: theme.colorScheme.primary,
            backgroundColor: theme.colorScheme.surface,
            side: BorderSide(color: theme.dividerColor.withValues(alpha: .5)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
            ),
            onSelected: (_) => onCategoryChanged(category),
          );
        },
      ),
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          const SizedBox(height: 8),
          actions,
          const SizedBox(height: 8),
          categoryChips,
        ],
      );
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: search),
            const SizedBox(width: 10),
            actions,
          ],
        ),
        const SizedBox(height: 8),
        categoryChips,
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
    final inStock = stock > 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: .16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .08),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xFFEAF2F7),
                        Color(0xFFC7D2D8),
                        Color(0xFF24292D),
                      ],
                      stops: [0, .48, 1],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 22, 16, 34),
                  child: ProductNetworkImage(
                    imageUrl: product.displayFotoUrl ?? '',
                    productId: product.id,
                    productName: product.nombre,
                    originalUrl: product.originalFotoUrl,
                    fit: BoxFit.contain,
                    fallback: Icon(
                      Icons.inventory_2_outlined,
                      size: 28,
                      color: Colors.black.withValues(alpha: .45),
                    ),
                  ),
                ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x00000000),
                          Color(0x22000000),
                          Color(0xDD000000),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 5,
                  top: 5,
                  child: _StockBadge(
                    label: inStock ? 'Disp. ${qty(stock)}' : 'Sin stock',
                    danger: !inStock,
                  ),
                ),
                Positioned(
                  right: 5,
                  top: 5,
                  child: _PriceBadge(label: money(product.costo)),
                ),
                Positioned(
                  left: 7,
                  right: 7,
                  bottom: 7,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        product.nombre.toUpperCase(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          height: 1.02,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: .18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          product.categoriaLabel.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(3),
                      child: Icon(Icons.add, size: 13, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.label, this.danger = false});

  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: danger ? const Color(0xFFE11D48) : const Color(0xFF2563EB),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .18),
            blurRadius: 5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PriceBadge extends StatelessWidget {
  const _PriceBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .66),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
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
