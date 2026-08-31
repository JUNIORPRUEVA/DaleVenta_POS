import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/models/product_model.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../data/warehouse_repository.dart';

class WarehouseSettingsScreen extends ConsumerWidget {
  const WarehouseSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).user;
    final warehouses = ref.watch(warehousesProvider);
    final terminals = ref.watch(warehouseTerminalsProvider);
    final transfers = ref.watch(warehouseTransfersProvider);
    final products = ref.watch(warehouseProductsProvider);
    final compact = MediaQuery.sizeOf(context).width < 720;
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      appBar: CustomAppBar(
        title: 'Almacenes',
        showLogo: false,
        showDepartmentLabel: false,
        preferDrawerLeading: true,
        leading: IconButton(
          tooltip: 'Volver',
          onPressed: () => context.go(
            MediaQuery.sizeOf(context).width >= 900
                ? Routes.cotizaciones
                : Routes.configuracion,
          ),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(warehousesProvider);
              ref.invalidate(warehouseTerminalsProvider);
              ref.invalidate(warehouseTransfersProvider);
              ref.invalidate(warehouseProductsProvider);
              await Future<void>.delayed(const Duration(milliseconds: 250));
            },
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                compact ? 12 : 22,
                compact ? 12 : 20,
                compact ? 12 : 22,
                28,
              ),
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Inventario / almacenes',
                        style: TextStyle(
                          color: Color(0xFF183548),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _openWarehouseForm(context, ref),
                      icon: const Icon(Icons.add_business_outlined),
                      label: const Text('Crear'),
                      style: _filledButtonStyle(),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Mantén la operación simple: con un solo almacén activo, ventas y productos siguen trabajando automáticamente.',
                  style: TextStyle(
                    color: Color(0xFF52667C),
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
                warehouses.when(
                  data: (items) => _WarehouseList(
                    warehouses: items,
                    terminals: terminals.valueOrNull ?? const [],
                    onEdit: (warehouse) =>
                        _openWarehouseForm(context, ref, warehouse: warehouse),
                    onSetDefault: (warehouse) =>
                        _runWarehouseAction(context, ref, () async {
                          await ref
                              .read(warehouseRepositoryProvider)
                              .setDefault(warehouse.id);
                        }, 'Almacén predeterminado actualizado'),
                    onToggle: (warehouse) =>
                        _runWarehouseAction(context, ref, () async {
                          final repo = ref.read(warehouseRepositoryProvider);
                          if (warehouse.isActive) {
                            await repo.deactivate(warehouse.id);
                          } else {
                            await repo.activate(warehouse.id);
                          }
                        }, 'Estado del almacén actualizado'),
                  ),
                  loading: () => const _WarehouseSurface(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                  error: (error, _) => _WarehouseStatePanel(
                    icon: Icons.error_outline_rounded,
                    title: 'No se pudieron cargar los almacenes',
                    message: '$error',
                  ),
                ),
                const SizedBox(height: 14),
                terminals.when(
                  data: (items) => _TerminalAssignments(
                    terminals: items,
                    warehouses: warehouses.valueOrNull ?? const [],
                    onChanged: (terminal, warehouseId) =>
                        _runWarehouseAction(context, ref, () async {
                          await ref
                              .read(warehouseRepositoryProvider)
                              .updateTerminalWarehouse(
                                terminalId: terminal.id,
                                warehouseId: warehouseId,
                              );
                        }, 'Terminal actualizada'),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 14),
                warehouses.when(
                  data: (items) => _TransferPanel(
                    warehouses: items,
                    transfers: transfers.valueOrNull ?? const [],
                    products: products.valueOrNull ?? const [],
                    loading:
                        transfers.isLoading ||
                        products.isLoading ||
                        products.isRefreshing ||
                        transfers.isRefreshing,
                    error: transfers.error ?? products.error,
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WarehouseList extends StatelessWidget {
  const _WarehouseList({
    required this.warehouses,
    required this.terminals,
    required this.onEdit,
    required this.onSetDefault,
    required this.onToggle,
  });

  final List<WarehouseModel> warehouses;
  final List<TerminalWarehouseModel> terminals;
  final ValueChanged<WarehouseModel> onEdit;
  final ValueChanged<WarehouseModel> onSetDefault;
  final ValueChanged<WarehouseModel> onToggle;

  @override
  Widget build(BuildContext context) {
    if (warehouses.isEmpty) {
      return const _WarehouseStatePanel(
        icon: Icons.inventory_2_outlined,
        title: 'Sin almacenes',
        message: 'Crea el almacén principal para operar inventario local.',
      );
    }
    final activeCount = warehouses.where((item) => item.isActive).length;
    return _WarehouseSurface(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          if (compact) {
            return Column(
              children: [
                _WarehouseSummaryStrip(activeCount: activeCount),
                for (final warehouse in warehouses)
                  _WarehouseCard(
                    warehouse: warehouse,
                    onEdit: () => onEdit(warehouse),
                    onSetDefault: warehouse.isDefault || !warehouse.isActive
                        ? null
                        : () => onSetDefault(warehouse),
                    onToggle: () => onToggle(warehouse),
                  ),
              ],
            );
          }
          return Column(
            children: [
              _WarehouseSummaryStrip(activeCount: activeCount),
              const Divider(height: 1),
              for (final warehouse in warehouses) ...[
                _WarehouseTableRow(
                  warehouse: warehouse,
                  terminalCount: terminals
                      .where(
                        (item) =>
                            item.isActive &&
                            item.defaultWarehouseId == warehouse.id,
                      )
                      .length,
                  onEdit: () => onEdit(warehouse),
                  onSetDefault: warehouse.isDefault || !warehouse.isActive
                      ? null
                      : () => onSetDefault(warehouse),
                  onToggle: () => onToggle(warehouse),
                ),
                const Divider(height: 1),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _WarehouseSummaryStrip extends StatelessWidget {
  const _WarehouseSummaryStrip({required this.activeCount});

  final int activeCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const Icon(Icons.warehouse_outlined, color: AppColors.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              activeCount <= 1
                  ? 'Operación simple: un almacén activo'
                  : '$activeCount almacenes activos',
              style: const TextStyle(
                color: Color(0xFF183548),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _StatusChip(
            label: activeCount <= 1 ? 'Automático' : 'Multi-almacén',
            color: activeCount <= 1
                ? const Color(0xFF0F766E)
                : AppColors.secondary,
          ),
        ],
      ),
    );
  }
}

class _WarehouseTableRow extends StatelessWidget {
  const _WarehouseTableRow({
    required this.warehouse,
    required this.terminalCount,
    required this.onEdit,
    required this.onSetDefault,
    required this.onToggle,
  });

  final WarehouseModel warehouse;
  final int terminalCount;
  final VoidCallback onEdit;
  final VoidCallback? onSetDefault;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        children: [
          Expanded(flex: 3, child: _WarehouseNameBlock(warehouse: warehouse)),
          Expanded(child: Text(warehouse.code, style: _cellStyle())),
          Expanded(
            child: _StatusChip(
              label: warehouse.isActive ? 'Activo' : 'Inactivo',
              color: warehouse.isActive ? const Color(0xFF0F766E) : Colors.grey,
            ),
          ),
          Expanded(
            child: Text('$terminalCount terminales', style: _cellStyle()),
          ),
          IconButton(
            tooltip: 'Editar',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Predeterminado',
            onPressed: onSetDefault,
            icon: const Icon(Icons.star_border_rounded),
          ),
          IconButton(
            tooltip: warehouse.isActive ? 'Desactivar' : 'Activar',
            onPressed: onToggle,
            icon: Icon(
              warehouse.isActive
                  ? Icons.toggle_on_rounded
                  : Icons.toggle_off_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _WarehouseCard extends StatelessWidget {
  const _WarehouseCard({
    required this.warehouse,
    required this.onEdit,
    required this.onSetDefault,
    required this.onToggle,
  });

  final WarehouseModel warehouse;
  final VoidCallback onEdit;
  final VoidCallback? onSetDefault;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFF),
          border: Border.all(color: const Color(0xFFDDE7EE)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _WarehouseNameBlock(warehouse: warehouse),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatusChip(
                    label: warehouse.code,
                    color: AppColors.secondary,
                  ),
                  _StatusChip(
                    label: warehouse.isActive ? 'Activo' : 'Inactivo',
                    color: warehouse.isActive
                        ? const Color(0xFF0F766E)
                        : Colors.grey,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Editar',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
                  IconButton(
                    tooltip: 'Predeterminado',
                    onPressed: onSetDefault,
                    icon: const Icon(Icons.star_border_rounded),
                  ),
                  IconButton(
                    tooltip: warehouse.isActive ? 'Desactivar' : 'Activar',
                    onPressed: onToggle,
                    icon: Icon(
                      warehouse.isActive
                          ? Icons.toggle_on_rounded
                          : Icons.toggle_off_rounded,
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

class _WarehouseNameBlock extends StatelessWidget {
  const _WarehouseNameBlock({required this.warehouse});

  final WarehouseModel warehouse;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(
            Icons.store_mall_directory_outlined,
            size: 18,
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                warehouse.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF183548),
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (warehouse.isDefault)
                const Text(
                  'Predeterminado',
                  style: TextStyle(
                    color: Color(0xFF0F766E),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TerminalAssignments extends StatelessWidget {
  const _TerminalAssignments({
    required this.terminals,
    required this.warehouses,
    required this.onChanged,
  });

  final List<TerminalWarehouseModel> terminals;
  final List<WarehouseModel> warehouses;
  final void Function(TerminalWarehouseModel terminal, String warehouseId)
  onChanged;

  @override
  Widget build(BuildContext context) {
    if (terminals.isEmpty) return const SizedBox.shrink();
    final activeWarehouses = warehouses.where((item) => item.isActive).toList();
    return _WarehouseSurface(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Terminales',
              style: TextStyle(
                color: Color(0xFF183548),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            for (final terminal in terminals)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 560;
                    final label = Text(
                      '${terminal.name} → ${terminal.defaultWarehouseName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _cellStyle(),
                    );
                    final selector = DropdownButtonFormField<String>(
                      initialValue:
                          activeWarehouses.any(
                            (warehouse) =>
                                warehouse.id == terminal.defaultWarehouseId,
                          )
                          ? terminal.defaultWarehouseId
                          : null,
                      isExpanded: true,
                      decoration: _inputDecoration('Almacén operativo'),
                      items: [
                        for (final warehouse in activeWarehouses)
                          DropdownMenuItem(
                            value: warehouse.id,
                            child: Text(
                              '${warehouse.name} (${warehouse.code})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: terminal.isActive
                          ? (value) {
                              if (value != null) onChanged(terminal, value);
                            }
                          : null,
                    );
                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [label, const SizedBox(height: 8), selector],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: label),
                        const SizedBox(width: 12),
                        SizedBox(width: 320, child: selector),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TransferPanel extends ConsumerStatefulWidget {
  const _TransferPanel({
    required this.warehouses,
    required this.transfers,
    required this.products,
    required this.loading,
    required this.error,
  });

  final List<WarehouseModel> warehouses;
  final List<WarehouseTransferModel> transfers;
  final List<ProductModel> products;
  final bool loading;
  final Object? error;

  @override
  ConsumerState<_TransferPanel> createState() => _TransferPanelState();
}

class _TransferPanelState extends ConsumerState<_TransferPanel> {
  String? _sourceId;
  String? _destinationId;
  String? _productId;
  final _quantityCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _quantityCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeWarehouses = widget.warehouses
        .where((warehouse) => warehouse.isActive)
        .toList();
    if (activeWarehouses.length <= 1) {
      return const _WarehouseStatePanel(
        icon: Icons.swap_horiz_rounded,
        title: 'Transferencias automáticas',
        message:
            'Con un solo almacén activo no necesitas mover inventario entre ubicaciones.',
      );
    }

    _sourceId ??= activeWarehouses.first.id;
    _destinationId ??= activeWarehouses
        .firstWhere((warehouse) => warehouse.id != _sourceId)
        .id;
    final selectedProduct = widget.products
        .where((product) => product.id == _productId)
        .firstOrNull;

    return _WarehouseSurface(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final form = _buildForm(context, activeWarehouses, selectedProduct);
            final history = _buildHistory();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.swap_horiz_rounded,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Transferencias',
                        style: TextStyle(
                          color: Color(0xFF183548),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (widget.loading)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                if (widget.error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${widget.error}',
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                if (compact) ...[
                  form,
                  const SizedBox(height: 12),
                  history,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: form),
                      const SizedBox(width: 14),
                      Expanded(flex: 4, child: history),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildForm(
    BuildContext context,
    List<WarehouseModel> activeWarehouses,
    ProductModel? selectedProduct,
  ) {
    final sourceId = _sourceId;
    final destinationId = _destinationId;
    final sameWarehouse =
        sourceId != null && destinationId != null && sourceId == destinationId;
    final available = _availableQuantity(selectedProduct, sourceId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _sourceId,
                isExpanded: true,
                decoration: _inputDecoration('Origen'),
                items: [
                  for (final warehouse in activeWarehouses)
                    DropdownMenuItem(
                      value: warehouse.id,
                      child: Text('${warehouse.name} (${warehouse.code})'),
                    ),
                ],
                onChanged: (value) => setState(() => _sourceId = value),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.arrow_forward_rounded,
                color: AppColors.secondary,
              ),
            ),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _destinationId,
                isExpanded: true,
                decoration: _inputDecoration('Destino'),
                items: [
                  for (final warehouse in activeWarehouses)
                    DropdownMenuItem(
                      value: warehouse.id,
                      child: Text('${warehouse.name} (${warehouse.code})'),
                    ),
                ],
                onChanged: (value) => setState(() => _destinationId = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _productId,
          isExpanded: true,
          decoration: _inputDecoration('Producto'),
          items: [
            for (final product in widget.products)
              DropdownMenuItem(value: product.id, child: Text(product.nombre)),
          ],
          onChanged: (value) => setState(() => _productId = value),
        ),
        const SizedBox(height: 8),
        Text(
          selectedProduct == null
              ? 'Disponible en origen: selecciona producto'
              : 'Disponible en origen: ${_formatQuantity(available)} ${selectedProduct.unitOfMeasure.symbol}',
          style: const TextStyle(
            color: Color(0xFF52667C),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _quantityCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _inputDecoration('Cantidad'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _notesCtrl,
          maxLines: 2,
          decoration: _inputDecoration('Notas'),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _saving || sameWarehouse || selectedProduct == null
              ? null
              : () => _confirmTransfer(context, selectedProduct, available),
          icon: const Icon(Icons.check_circle_outline_rounded),
          label: Text(_saving ? 'Transfiriendo...' : 'Confirmar transferencia'),
          style: _filledButtonStyle(),
        ),
        if (sameWarehouse) ...[
          const SizedBox(height: 6),
          const Text(
            'El origen y el destino deben ser distintos.',
            style: TextStyle(
              color: Color(0xFFB91C1C),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHistory() {
    if (widget.transfers.isEmpty) {
      return const _WarehouseStatePanel(
        icon: Icons.history_rounded,
        title: 'Sin transferencias',
        message: 'Las transferencias confirmadas aparecerán aquí.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Historial', style: TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        for (final transfer in widget.transfers.take(6))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FBFF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFDDE7EE)),
              ),
              child: ListTile(
                dense: true,
                title: Text(
                  '${transfer.sourceWarehouseName} → ${transfer.destinationWarehouseName}',
                  overflow: TextOverflow.ellipsis,
                  style: _cellStyle(weight: FontWeight.w900),
                ),
                subtitle: Text(
                  '${transfer.status} · ${transfer.itemCount} productos',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showTransferDetail(context, transfer),
              ),
            ),
          ),
      ],
    );
  }

  double _availableQuantity(ProductModel? product, String? warehouseId) {
    if (product == null || warehouseId == null) return 0;
    final breakdown = ref.watch(productWarehouseStockProvider(product.id));
    final line = breakdown.valueOrNull?.lineFor(warehouseId);
    return line?.quantity ?? 0;
  }

  Future<void> _confirmTransfer(
    BuildContext context,
    ProductModel product,
    double available,
  ) async {
    final quantity = double.tryParse(_quantityCtrl.text.replaceAll(',', '.'));
    if (quantity == null || quantity <= 0) {
      _showMessage('La cantidad debe ser mayor que cero.');
      return;
    }
    if (quantity > available) {
      _showMessage('La cantidad supera el disponible del almacén origen.');
      return;
    }
    final source = _warehouseName(_sourceId);
    final destination = _warehouseName(_destinationId);
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confirmar transferencia'),
        content: Text(
          '$source → $destination\n${product.nombre}\n${_formatQuantity(quantity)} ${product.unitOfMeasure.symbol}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.swap_horiz_rounded),
            label: const Text('Transferir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      final transfer = await ref
          .read(warehouseRepositoryProvider)
          .createTransfer(
            sourceWarehouseId: _sourceId!,
            destinationWarehouseId: _destinationId!,
            items: [
              WarehouseTransferItemDraft(
                productId: product.id,
                quantity: _quantityCtrl.text.replaceAll(',', '.'),
              ),
            ],
            notes: _notesCtrl.text,
          );
      ref.invalidate(warehouseTransfersProvider);
      ref.invalidate(productWarehouseStockProvider(product.id));
      ref.invalidate(warehouseProductsProvider);
      if (!mounted || !navigator.mounted) return;
      _quantityCtrl.clear();
      _notesCtrl.clear();
      _showMessage('Transferencia completada');
      _showTransferDetail(navigator.context, transfer);
    } catch (error) {
      if (mounted) _showMessage('$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showTransferDetail(
    BuildContext context,
    WarehouseTransferModel transfer,
  ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Detalle de transferencia'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${transfer.sourceWarehouseName} → ${transfer.destinationWarehouseName}',
                style: _cellStyle(weight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              for (final item in transfer.items)
                Text(
                  '${item.productName}: ${item.quantityDecimal} ${item.unitSymbolSnapshot}',
                ),
              if ((transfer.notes ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(transfer.notes!),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  String _warehouseName(String? id) {
    return widget.warehouses
            .where((warehouse) => warehouse.id == id)
            .map((warehouse) => warehouse.name)
            .firstOrNull ??
        'Almacén';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

String _formatQuantity(double value) {
  final text = value.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');
  return text.isEmpty ? '0' : text;
}

Future<void> _openWarehouseForm(
  BuildContext context,
  WidgetRef ref, {
  WarehouseModel? warehouse,
}) async {
  final nameCtrl = TextEditingController(text: warehouse?.name ?? '');
  final codeCtrl = TextEditingController(text: warehouse?.code ?? '');
  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(warehouse == null ? 'Crear almacén' : 'Editar almacén'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: _inputDecoration('Nombre'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: codeCtrl,
              decoration: _inputDecoration('Código'),
              textInputAction: TextInputAction.done,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(dialogContext, true),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Guardar'),
        ),
      ],
    ),
  );
  if (saved != true || !context.mounted) return;
  await _runWarehouseAction(context, ref, () async {
    final repo = ref.read(warehouseRepositoryProvider);
    if (warehouse == null) {
      await repo.createWarehouse(name: nameCtrl.text, code: codeCtrl.text);
    } else {
      await repo.updateWarehouse(
        id: warehouse.id,
        name: nameCtrl.text,
        code: codeCtrl.text,
      );
    }
  }, warehouse == null ? 'Almacén creado' : 'Almacén actualizado');
}

Future<void> _runWarehouseAction(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action,
  String successMessage,
) async {
  try {
    await action();
    ref.invalidate(warehousesProvider);
    ref.invalidate(warehouseTerminalsProvider);
    ref.invalidate(warehouseInventoryOverviewProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(successMessage)));
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$error')));
  }
}

class _WarehouseSurface extends StatelessWidget {
  const _WarehouseSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: child,
    );
  }
}

class _WarehouseStatePanel extends StatelessWidget {
  const _WarehouseStatePanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return _WarehouseSurface(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, color: AppColors.secondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _cellStyle(weight: FontWeight.w900)),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: const TextStyle(
                      color: Color(0xFF52667C),
                      fontWeight: FontWeight.w600,
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    isDense: true,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
  );
}

TextStyle _cellStyle({FontWeight weight = FontWeight.w700}) {
  return TextStyle(
    color: const Color(0xFF183548),
    fontWeight: weight,
    letterSpacing: 0,
  );
}

ButtonStyle _filledButtonStyle() {
  return FilledButton.styleFrom(
    backgroundColor: AppColors.secondary,
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}
