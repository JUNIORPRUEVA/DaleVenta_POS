import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_drawer.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../catalogo/application/catalog_controller.dart';
import '../data/inventory_reporting_repository.dart';
import '../data/warehouse_repository.dart';

class InventoryKardexScreen extends ConsumerStatefulWidget {
  const InventoryKardexScreen({super.key});

  @override
  ConsumerState<InventoryKardexScreen> createState() =>
      _InventoryKardexScreenState();
}

class _InventoryKardexScreenState extends ConsumerState<InventoryKardexScreen> {
  InventoryMovementFilters _filters = const InventoryMovementFilters();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(catalogControllerProvider.notifier).load(silent: true);
    });
  }

  void _updateFilters(InventoryMovementFilters filters) {
    setState(() => _filters = filters.copyWith(skip: 0));
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        drawer: buildAdaptiveDrawer(context, currentUser: user),
        backgroundColor: AppColors.background,
        appBar: CustomAppBar(
          title: 'Kardex',
          showLogo: false,
          showDepartmentLabel: false,
          actions: [
            if (isMobile)
              IconButton(
                tooltip: 'Filtros',
                onPressed: () => _openMobileFilters(context),
                icon: const Icon(Icons.filter_alt_outlined),
              ),
            IconButton(
              tooltip: 'Actualizar',
              onPressed: () {
                ref.invalidate(inventoryMovementsProvider(_filters));
                ref.invalidate(inventoryStockReportProvider);
                ref.invalidate(inventoryReconciliationProvider);
              },
              icon: const Icon(Icons.refresh_rounded),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            const Material(
              color: Colors.white,
              child: TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'Movimientos'),
                  Tab(text: 'Stock por almacén'),
                  Tab(text: 'Conciliación'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _KardexMovementsTab(
                    filters: _filters,
                    onFiltersChanged: _updateFilters,
                  ),
                  const _StockReportTab(),
                  const _ReconciliationTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMobileFilters(BuildContext context) async {
    final result = await showModalBottomSheet<InventoryMovementFilters>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) =>
          _KardexFiltersPanel(filters: _filters, compact: true),
    );
    if (result != null) _updateFilters(result);
  }
}

class _KardexMovementsTab extends ConsumerWidget {
  const _KardexMovementsTab({
    required this.filters,
    required this.onFiltersChanged,
  });

  final InventoryMovementFilters filters;
  final ValueChanged<InventoryMovementFilters> onFiltersChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final page = ref.watch(inventoryMovementsProvider(filters));
    return RefreshIndicator(
      onRefresh: () async =>
          ref.invalidate(inventoryMovementsProvider(filters)),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (!isMobile) ...[
            _KardexFiltersPanel(filters: filters, onChanged: onFiltersChanged),
            const SizedBox(height: 12),
          ],
          page.when(
            loading: () => const _StatePanel(
              icon: Icons.history_rounded,
              title: 'Cargando Kardex',
              message: 'Consultando movimientos auditados.',
            ),
            error: (error, _) => _StatePanel(
              icon: Icons.warning_amber_rounded,
              title: 'No se pudo cargar el Kardex',
              message: '$error',
            ),
            data: (data) {
              if (data.externalInventory) {
                return _StatePanel(
                  icon: Icons.cloud_outlined,
                  title: 'Inventario externo',
                  message: data.message ?? 'El Kardex local no aplica.',
                );
              }
              if (data.items.isEmpty) {
                return const _StatePanel(
                  icon: Icons.inventory_2_outlined,
                  title: 'Sin movimientos',
                  message: 'Las operaciones de inventario aparecerán aquí.',
                );
              }
              return Column(
                children: [
                  if (isMobile)
                    for (final movement in data.items)
                      _MovementCard(movement: movement)
                  else
                    _MovementsTable(movements: data.items),
                  const SizedBox(height: 12),
                  _PaginationBar(
                    skip: data.skip,
                    take: data.take,
                    total: data.total,
                    hasMore: data.hasMore,
                    onPrevious: data.skip <= 0
                        ? null
                        : () => onFiltersChanged(
                            filters.copyWith(
                              skip: (data.skip - data.take).clamp(
                                0,
                                data.total,
                              ),
                            ),
                          ),
                    onNext: data.hasMore
                        ? () => onFiltersChanged(
                            filters.copyWith(skip: data.skip + data.take),
                          )
                        : null,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _KardexFiltersPanel extends ConsumerStatefulWidget {
  const _KardexFiltersPanel({
    required this.filters,
    this.onChanged,
    this.compact = false,
  });

  final InventoryMovementFilters filters;
  final ValueChanged<InventoryMovementFilters>? onChanged;
  final bool compact;

  @override
  ConsumerState<_KardexFiltersPanel> createState() =>
      _KardexFiltersPanelState();
}

class _KardexFiltersPanelState extends ConsumerState<_KardexFiltersPanel> {
  late InventoryMovementFilters _draft = widget.filters;

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(catalogControllerProvider).items;
    final warehouses = ref.watch(warehousesProvider).valueOrNull ?? const [];
    final fields = [
      DropdownButtonFormField<String>(
        initialValue: _draft.productId,
        isExpanded: true,
        decoration: _inputDecoration('Producto'),
        items: [
          const DropdownMenuItem(value: '', child: Text('Todos')),
          for (final product in products)
            DropdownMenuItem(value: product.id, child: Text(product.nombre)),
        ],
        onChanged: (value) => setState(
          () => _draft = _draft.copyWith(
            productId: value,
            clearProduct: (value ?? '').isEmpty,
          ),
        ),
      ),
      DropdownButtonFormField<String>(
        initialValue: _draft.warehouseId,
        isExpanded: true,
        decoration: _inputDecoration('Almacén'),
        items: [
          const DropdownMenuItem(value: '', child: Text('Todos')),
          for (final warehouse in warehouses)
            DropdownMenuItem(
              value: warehouse.id,
              child: Text(
                '${warehouse.name}${warehouse.isActive ? '' : ' · Inactivo'}',
              ),
            ),
        ],
        onChanged: (value) => setState(
          () => _draft = _draft.copyWith(
            warehouseId: value,
            clearWarehouse: (value ?? '').isEmpty,
          ),
        ),
      ),
      DropdownButtonFormField<String>(
        initialValue: _draft.type,
        isExpanded: true,
        decoration: _inputDecoration('Tipo'),
        items: const [
          DropdownMenuItem(value: '', child: Text('Todos')),
          DropdownMenuItem(value: 'SALE', child: Text('Venta')),
          DropdownMenuItem(value: 'RETURN', child: Text('Devolución')),
          DropdownMenuItem(
            value: 'PURCHASE_RECEIPT',
            child: Text('Recepción de compra'),
          ),
          DropdownMenuItem(value: 'ADJUSTMENT_IN', child: Text('Ajuste +')),
          DropdownMenuItem(value: 'ADJUSTMENT_OUT', child: Text('Ajuste -')),
          DropdownMenuItem(
            value: 'TRANSFER_OUT',
            child: Text('Transferencia salida'),
          ),
          DropdownMenuItem(
            value: 'TRANSFER_IN',
            child: Text('Transferencia entrada'),
          ),
        ],
        onChanged: (value) => setState(
          () => _draft = _draft.copyWith(
            type: value,
            clearType: (value ?? '').isEmpty,
          ),
        ),
      ),
    ];
    final body = widget.compact
        ? Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [...fields, const SizedBox(height: 12), _applyButton()],
            ),
          )
        : _Surface(
            child: Row(
              children: [
                for (final field in fields) ...[
                  Expanded(child: field),
                  const SizedBox(width: 10),
                ],
                _applyButton(),
              ],
            ),
          );
    return body;
  }

  Widget _applyButton() {
    return FilledButton.icon(
      onPressed: () {
        if (widget.compact) {
          Navigator.pop(context, _draft);
        } else {
          widget.onChanged?.call(_draft);
        }
      },
      icon: const Icon(Icons.check_rounded),
      label: const Text('Aplicar'),
    );
  }
}

class _MovementCard extends StatelessWidget {
  const _MovementCard({required this.movement});

  final InventoryMovementModel movement;

  @override
  Widget build(BuildContext context) {
    final color = movement.isInbound ? AppColors.success : AppColors.error;
    return _Surface(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _showMovementDetail(context, movement),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DeltaBadge(text: movement.deltaText, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(movement.label, style: _titleStyle),
                    const SizedBox(height: 4),
                    Text(
                      movement.productName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${movement.warehouseName} · ${movement.referenceLabel}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _mutedStyle,
                    ),
                    const SizedBox(height: 4),
                    Text(movement.balanceText, style: _mutedStyle),
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

class _MovementsTable extends StatelessWidget {
  const _MovementsTable({required this.movements});

  final List<InventoryMovementModel> movements;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Fecha')),
            DataColumn(label: Text('Tipo')),
            DataColumn(label: Text('Producto')),
            DataColumn(label: Text('Almacén')),
            DataColumn(label: Text('Delta')),
            DataColumn(label: Text('Balance')),
            DataColumn(label: Text('Referencia')),
          ],
          rows: [
            for (final movement in movements)
              DataRow(
                onSelectChanged: (_) => _showMovementDetail(context, movement),
                cells: [
                  DataCell(Text(_dateText(movement.createdAt))),
                  DataCell(Text(movement.label)),
                  DataCell(Text(movement.productName)),
                  DataCell(Text(_warehouseLabel(movement))),
                  DataCell(Text(movement.deltaText)),
                  DataCell(Text(movement.balanceText)),
                  DataCell(Text(movement.referenceLabel)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StockReportTab extends ConsumerWidget {
  const _StockReportTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(inventoryStockReportProvider);
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    return report.when(
      loading: () => const _StatePanel(
        icon: Icons.table_chart_outlined,
        title: 'Cargando reporte',
        message: 'Leyendo WarehouseStock.',
      ),
      error: (error, _) => _StatePanel(
        icon: Icons.warning_amber_rounded,
        title: 'No se pudo cargar el reporte',
        message: '$error',
      ),
      data: (data) {
        if (data.externalInventory) {
          return _StatePanel(
            icon: Icons.cloud_outlined,
            title: 'Inventario externo',
            message: data.message ?? 'El reporte local no aplica.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _ReportHeader(report: data),
            const SizedBox(height: 12),
            if (isMobile)
              for (final row in data.rows) _StockReportCard(row: row)
            else
              _StockReportTable(report: data),
          ],
        );
      },
    );
  }
}

class _ReconciliationTab extends ConsumerWidget {
  const _ReconciliationTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reconciliation = ref.watch(inventoryReconciliationProvider);
    return reconciliation.when(
      loading: () => const _StatePanel(
        icon: Icons.fact_check_outlined,
        title: 'Conciliando',
        message: 'Comparando Product.stock contra WarehouseStock.',
      ),
      error: (error, _) => _StatePanel(
        icon: Icons.warning_amber_rounded,
        title: 'No se pudo conciliar',
        message: '$error',
      ),
      data: (data) {
        if (data.externalInventory) {
          return _StatePanel(
            icon: Icons.cloud_outlined,
            title: 'Inventario externo',
            message: data.message ?? 'La conciliación local no aplica.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _Surface(
              child: ListTile(
                leading: Icon(
                  data.driftCount == 0
                      ? Icons.check_circle_outline_rounded
                      : Icons.warning_amber_rounded,
                  color: data.driftCount == 0
                      ? AppColors.success
                      : AppColors.warning,
                ),
                title: Text('${data.driftCount} diferencias'),
                subtitle: Text('${data.totalProducts} productos revisados'),
              ),
            ),
            const SizedBox(height: 12),
            for (final row in data.items)
              if (!row.reconciled)
                _Surface(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text(row.productName),
                    subtitle: Text(
                      'Producto ${compactDecimal(row.productStockDecimal)} ${row.unitSymbol} · Almacenes ${compactDecimal(row.warehouseTotalDecimal)} ${row.unitSymbol}',
                    ),
                    trailing: Text(
                      compactDecimal(row.differenceDecimal),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
            if (data.driftCount == 0)
              const _StatePanel(
                icon: Icons.verified_outlined,
                title: 'Inventario conciliado',
                message: 'No hay diferencias entre producto y almacenes.',
              ),
          ],
        );
      },
    );
  }
}

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({required this.report});

  final InventoryStockReport report;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _MetricChip(
            icon: Icons.inventory_2_outlined,
            label: '${report.productCount} productos',
          ),
          _MetricChip(
            icon: Icons.warehouse_outlined,
            label: '${report.warehouseCount} almacenes',
          ),
          for (final bucket in report.quantityBuckets)
            _MetricChip(
              icon: Icons.straighten_outlined,
              label: '${bucket.productCount} productos ${bucket.unitSymbol}',
            ),
        ],
      ),
    );
  }
}

class _StockReportTable extends StatelessWidget {
  const _StockReportTable({required this.report});

  final InventoryStockReport report;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            const DataColumn(label: Text('Producto')),
            const DataColumn(label: Text('SKU')),
            const DataColumn(label: Text('UoM')),
            const DataColumn(label: Text('Total')),
            for (final warehouse in report.warehouses)
              DataColumn(
                label: Text(
                  '${warehouse.name}${warehouse.isActive ? '' : ' · Inactivo'}',
                ),
              ),
          ],
          rows: [
            for (final row in report.rows)
              DataRow(
                cells: [
                  DataCell(Text(row.productName)),
                  DataCell(Text(row.sku.isEmpty ? 'Sin SKU' : row.sku)),
                  DataCell(Text(row.unitSymbol)),
                  DataCell(
                    Text(
                      '${compactDecimal(row.companyTotalDecimal)} ${row.unitSymbol}',
                    ),
                  ),
                  for (final warehouse in report.warehouses)
                    DataCell(
                      Text(
                        '${compactDecimal(_stockFor(row, warehouse.id))} ${row.unitSymbol}',
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StockReportCard extends StatelessWidget {
  const _StockReportCard({required this.row});

  final InventoryStockReportRow row;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(row.productName, style: _titleStyle),
            const SizedBox(height: 4),
            Text(
              '${row.sku.isEmpty ? 'Sin SKU' : row.sku} · Total ${compactDecimal(row.companyTotalDecimal)} ${row.unitSymbol}',
              style: _mutedStyle,
            ),
            const SizedBox(height: 8),
            for (final warehouse in row.warehouses)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${warehouse.warehouseName}${warehouse.isActive ? '' : ' · Inactivo'}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${compactDecimal(warehouse.quantityDecimal)} ${row.unitSymbol}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
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

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.skip,
    required this.take,
    required this.total,
    required this.hasMore,
    this.onPrevious,
    this.onNext,
  });

  final int skip;
  final int take;
  final int total;
  final bool hasMore;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final from = total == 0 ? 0 : skip + 1;
    final to = (skip + take).clamp(0, total);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('$from-$to de $total', style: _mutedStyle),
        IconButton(
          tooltip: 'Anterior',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        IconButton(
          tooltip: 'Siguiente',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}

class _DeltaBadge extends StatelessWidget {
  const _DeltaBadge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 78),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18, color: AppColors.secondary),
      label: Text(label),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return _Surface(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, color: AppColors.secondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: _titleStyle),
                  const SizedBox(height: 4),
                  Text(message, style: _mutedStyle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.margin});

  final Widget child;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

InputDecoration _inputDecoration(String label) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    isDense: true,
  );
}

void _showMovementDetail(
  BuildContext context,
  InventoryMovementModel movement,
) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Detalle de movimiento'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(movement.label, style: _titleStyle),
            const SizedBox(height: 8),
            Text(movement.productName),
            Text(_warehouseLabel(movement)),
            Text(movement.deltaText),
            Text(movement.balanceText),
            Text(movement.referenceLabel),
            if ((movement.createdByName ?? '').trim().isNotEmpty)
              Text('Usuario: ${movement.createdByName}'),
            if ((movement.reason ?? '').trim().isNotEmpty)
              Text('Razón: ${movement.reason}'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ],
    ),
  );
}

String _stockFor(InventoryStockReportRow row, String warehouseId) {
  for (final stock in row.warehouses) {
    if (stock.warehouseId == warehouseId) return stock.quantityDecimal;
  }
  return '0';
}

String _warehouseLabel(InventoryMovementModel movement) {
  final inactive = movement.warehouseActive ? '' : ' · Inactivo';
  if (movement.isTransfer &&
      (movement.sourceWarehouseName ?? '').isNotEmpty &&
      (movement.destinationWarehouseName ?? '').isNotEmpty) {
    return '${movement.sourceWarehouseName} -> ${movement.destinationWarehouseName}$inactive';
  }
  return '${movement.warehouseName}$inactive';
}

String _dateText(DateTime? value) {
  if (value == null) return '--';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
}

const _titleStyle = TextStyle(
  color: Color(0xFF183548),
  fontWeight: FontWeight.w900,
);

const _mutedStyle = TextStyle(
  color: Color(0xFF52667C),
  fontWeight: FontWeight.w600,
);
