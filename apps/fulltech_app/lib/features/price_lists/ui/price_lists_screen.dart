import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/company/company_settings_repository.dart';
import '../../../core/debug/app_error_reporter.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/user_safe_error_text.dart';
import '../../../core/models/product_model.dart';
import '../../../core/routing/routes.dart';
import '../../catalogo/application/product_search_controller.dart';
import '../data/price_lists_repository.dart';

class PriceListsScreen extends ConsumerStatefulWidget {
  const PriceListsScreen({super.key});

  @override
  ConsumerState<PriceListsScreen> createState() => _PriceListsScreenState();
}

class _PriceListsScreenState extends ConsumerState<PriceListsScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  String? _selectedListId;
  ProductModel? _selectedProduct;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled =
        ref
            .watch(companySettingsProvider)
            .valueOrNull
            ?.wholesalePriceListsEnabled ==
        true;
    if (!enabled) {
      return const Scaffold(
        body: Center(child: Text('Mayoreo no está activo para esta empresa.')),
      );
    }

    final lists = ref.watch(priceListsProvider);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go(Routes.cotizaciones)),
        title: const Text('Listas de precios'),
      ),
      body: lists.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: 'No se pudieron cargar las listas.',
          onRetry: () => ref.invalidate(priceListsProvider),
        ),
        data: (items) {
          final selected = _selectedList(items);
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 920;
              final content = [
                _ListsPanel(
                  lists: items,
                  selectedId: selected?.id,
                  onSelected: (id) => setState(() => _selectedListId = id),
                  onCreate: _createList,
                  onEdit: _editList,
                  onToggle: _toggleList,
                ),
                _RulesPanel(
                  key: ValueKey('${selected?.id}:${_selectedProduct?.id}'),
                  list: selected,
                  selectedProduct: _selectedProduct,
                  quantityController: _quantity,
                  saving: _saving,
                  onPickProduct: _pickProduct,
                  onSaveRule: _saveRule,
                  onPreview: _previewPrice,
                ),
              ];
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 360,
                          child: SingleChildScrollView(child: content[0]),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: content[1]),
                      ],
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: content,
                    );
            },
          );
        },
      ),
    );
  }

  PriceListModel? _selectedList(List<PriceListModel> lists) {
    if (lists.isEmpty) return null;
    final selectedId = _selectedListId;
    if (selectedId != null) {
      for (final list in lists) {
        if (list.id == selectedId) return list;
      }
    }
    return lists.first;
  }

  Future<void> _createList() async {
    _name.clear();
    _description.clear();
    final result = await showDialog<_ListDraft>(
      context: context,
      builder: (context) => _ListDialog(name: _name, description: _description),
    );
    if (result == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final created = await ref
          .read(priceListsRepositoryProvider)
          .createPriceList(name: result.name, description: result.description);
      setState(() => _selectedListId = created.id);
      ref.invalidate(priceListsProvider);
    } catch (error, stack) {
      _reportError(error, stack, 'No se pudo crear la lista.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleList(PriceListModel list) async {
    try {
      await ref
          .read(priceListsRepositoryProvider)
          .updatePriceList(id: list.id, active: !list.active);
      ref.invalidate(priceListsProvider);
    } catch (error, stack) {
      _reportError(error, stack, 'No se pudo cambiar el estado de la lista.');
    }
  }

  Future<void> _editList(PriceListModel list) async {
    _name.text = list.name;
    _description.text = list.description;
    final draft = await showDialog<_ListDraft>(
      context: context,
      builder: (context) => _ListDialog(
        name: _name,
        description: _description,
        title: 'Editar lista',
      ),
    );
    if (draft == null || !mounted) return;
    try {
      await ref
          .read(priceListsRepositoryProvider)
          .updatePriceList(
            id: list.id,
            name: draft.name,
            description: draft.description,
          );
      ref.invalidate(priceListsProvider);
    } catch (error, stack) {
      _reportError(error, stack, 'No se pudo guardar la lista.');
    }
  }

  void _reportError(Object error, StackTrace stack, String message) {
    AppErrorReporter.instance.record(
      error,
      stack,
      context: 'PriceLists',
      userMessage: message,
    );
  }

  Future<void> _pickProduct() async {
    final selected = await showModalBottomSheet<ProductModel>(
      context: context,
      showDragHandle: true,
      builder: (context) => const _ProductPicker(),
    );
    if (selected != null) setState(() => _selectedProduct = selected);
  }

  Future<void> _saveRule(PriceListModel list, _RuleDraft draft) async {
    final product = _selectedProduct;
    if (product == null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(priceListsRepositoryProvider)
          .upsertRule(
            priceListId: list.id,
            productId: product.id,
            mode: draft.mode,
            fixedPrice: draft.fixedPrice,
            discountPercent: draft.discountPercent,
            minQuantity: draft.minQuantity,
            tiers: draft.tiers,
          );
      ref.invalidate(priceListsProvider);
    } catch (error, stack) {
      _reportError(error, stack, 'No se pudo guardar la regla de precios.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _previewPrice(PriceListModel list) async {
    final product = _selectedProduct;
    if (product == null) return;
    final qty = double.tryParse(_quantity.text.replaceAll(',', '.')) ?? 1;
    final result = await ref
        .read(priceListsRepositoryProvider)
        .resolveLine(
          productId: product.id,
          qty: qty <= 0 ? 1 : qty,
          priceListId: list.id,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.applied
              ? 'Precio: RD\$${result.unitPrice.toStringAsFixed(2)}'
              : 'No hay regla aplicable para esa cantidad.',
        ),
      ),
    );
  }
}

class _ListsPanel extends StatelessWidget {
  const _ListsPanel({
    required this.lists,
    required this.selectedId,
    required this.onSelected,
    required this.onCreate,
    required this.onEdit,
    required this.onToggle,
  });

  final List<PriceListModel> lists;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  final VoidCallback onCreate;
  final ValueChanged<PriceListModel> onEdit;
  final ValueChanged<PriceListModel> onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Nueva lista'),
          ),
          const SizedBox(height: 12),
          for (final list in lists)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                selected: list.id == selectedId,
                title: Text(list.name, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${list.rules.length} reglas · ${list.clientCount} clientes',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Editar lista',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => onEdit(list),
                    ),
                    Switch(
                      value: list.active,
                      onChanged: (_) => onToggle(list),
                    ),
                  ],
                ),
                onTap: () => onSelected(list.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _RulesPanel extends StatefulWidget {
  const _RulesPanel({
    super.key,
    required this.list,
    required this.selectedProduct,
    required this.quantityController,
    required this.saving,
    required this.onPickProduct,
    required this.onSaveRule,
    required this.onPreview,
  });

  final PriceListModel? list;
  final ProductModel? selectedProduct;
  final TextEditingController quantityController;
  final bool saving;
  final VoidCallback onPickProduct;
  final Future<void> Function(PriceListModel list, _RuleDraft draft) onSaveRule;
  final Future<void> Function(PriceListModel list) onPreview;

  @override
  State<_RulesPanel> createState() => _RulesPanelState();
}

class _RulesPanelState extends State<_RulesPanel> {
  final _minQty = TextEditingController(text: '1');
  final _fixedPrice = TextEditingController();
  final _discount = TextEditingController();
  final _tierQty = TextEditingController();
  final _tierPrice = TextEditingController();
  final List<PriceListTierDraft> _tiers = [];
  String _mode = 'FIXED_PRICE';

  @override
  void initState() {
    super.initState();
    for (final rule in widget.list?.rules ?? <PriceListRuleModel>[]) {
      if (rule.productId != widget.selectedProduct?.id) continue;
      _mode = rule.mode;
      _minQty.text = '${rule.minQuantity}';
      _fixedPrice.text = rule.fixedPrice?.toString() ?? '';
      _discount.text = rule.discountPercent?.toString() ?? '';
      _tiers.addAll(
        rule.tiers.map(
          (tier) => PriceListTierDraft(
            minQuantity: tier.minQuantity,
            mode: tier.mode ?? rule.mode,
            fixedPrice: tier.fixedPrice,
            discountPercent: tier.discountPercent,
          ),
        ),
      );
      break;
    }
  }

  @override
  void dispose() {
    _minQty.dispose();
    _fixedPrice.dispose();
    _discount.dispose();
    _tierQty.dispose();
    _tierPrice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.list;
    if (list == null) {
      return const Center(child: Text('Crea o selecciona una lista.'));
    }
    final product = widget.selectedProduct;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      children: [
        Text(list.name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: widget.onPickProduct,
              icon: const Icon(Icons.inventory_2_outlined),
              label: Text(product?.nombre ?? 'Elegir producto'),
            ),
            SizedBox(
              width: 130,
              child: TextField(
                controller: widget.quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Cantidad'),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: product == null ? null : () => widget.onPreview(list),
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('Probar'),
            ),
          ],
        ),
        if (product != null) ...[
          const SizedBox(height: 12),
          Text('Precio general: RD\$${product.precio.toStringAsFixed(2)}'),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            selected: {_mode},
            segments: const [
              ButtonSegment(value: 'FIXED_PRICE', label: Text('Precio fijo')),
              ButtonSegment(
                value: 'PERCENT_DISCOUNT',
                label: Text('Descuento'),
              ),
            ],
            onSelectionChanged: (value) => setState(() {
              _mode = value.first;
              _tiers.clear();
            }),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _numberField(_minQty, 'Desde'),
              if (_mode == 'FIXED_PRICE')
                _numberField(_fixedPrice, 'Precio')
              else
                _numberField(_discount, 'Descuento %'),
            ],
          ),
          const SizedBox(height: 12),
          Text('Escalas', style: Theme.of(context).textTheme.titleMedium),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _numberField(_tierQty, 'Desde'),
              _numberField(
                _tierPrice,
                _mode == 'FIXED_PRICE' ? 'Precio' : 'Descuento %',
              ),
              IconButton.filledTonal(
                tooltip: 'Agregar escala',
                onPressed: _addTier,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          for (final tier in _tiers)
            ListTile(
              dense: true,
              title: Text('Desde ${tier.minQuantity}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _mode == 'FIXED_PRICE'
                        ? 'RD\$${tier.fixedPrice?.toStringAsFixed(2) ?? '-'}'
                        : '${tier.discountPercent?.toStringAsFixed(2) ?? '-'}%',
                  ),
                  IconButton(
                    tooltip: 'Quitar escala',
                    onPressed: () => setState(() => _tiers.remove(tier)),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: widget.saving ? null : () => _save(list),
            icon: const Icon(Icons.save_outlined),
            label: const Text('Guardar regla'),
          ),
        ],
        const SizedBox(height: 20),
        for (final rule in list.rules)
          Card(
            child: ListTile(
              title: Text(rule.productName),
              subtitle: Text(
                rule.mode == 'FIXED_PRICE'
                    ? 'Desde ${rule.minQuantity}: RD\$${rule.fixedPrice?.toStringAsFixed(2) ?? '-'}'
                    : 'Desde ${rule.minQuantity}: ${rule.discountPercent?.toStringAsFixed(2) ?? '-'}%',
              ),
            ),
          ),
      ],
    );
  }

  Widget _numberField(TextEditingController controller, String label) {
    return SizedBox(
      width: 132,
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9\.,]')),
        ],
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  void _addTier() {
    final qty = _number(_tierQty.text);
    final value = _number(_tierPrice.text);
    if (_tierQty.text.trim().isEmpty ||
        _tierPrice.text.trim().isEmpty ||
        qty <= 0 ||
        value < 0 ||
        (_mode == 'PERCENT_DISCOUNT' && value > 100)) {
      _invalidRule();
      return;
    }
    setState(() {
      _tiers.add(
        PriceListTierDraft(
          minQuantity: qty,
          mode: _mode,
          fixedPrice: _mode == 'FIXED_PRICE' ? value : null,
          discountPercent: _mode == 'PERCENT_DISCOUNT' ? value : null,
        ),
      );
      _tierQty.clear();
      _tierPrice.clear();
    });
  }

  Future<void> _save(PriceListModel list) {
    final text = _mode == 'FIXED_PRICE' ? _fixedPrice.text : _discount.text;
    final minQuantity = _number(_minQty.text);
    final amount = _number(text);
    if (text.trim().isEmpty ||
        minQuantity <= 0 ||
        amount < 0 ||
        (_mode == 'PERCENT_DISCOUNT' && amount > 100)) {
      _invalidRule();
      return Future.value();
    }
    final value = _mode == 'FIXED_PRICE'
        ? _number(_fixedPrice.text)
        : _number(_discount.text);
    return widget.onSaveRule(
      list,
      _RuleDraft(
        mode: _mode,
        minQuantity: _number(
          _minQty.text,
        ).clamp(0.000001, double.infinity).toDouble(),
        fixedPrice: _mode == 'FIXED_PRICE' ? value : null,
        discountPercent: _mode == 'PERCENT_DISCOUNT' ? value : null,
        tiers: _tiers,
      ),
    );
  }

  void _invalidRule() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Completa una cantidad mayor que cero y un precio válido o descuento entre 0 y 100%.',
        ),
      ),
    );
  }
}

class _ProductPicker extends ConsumerStatefulWidget {
  const _ProductPicker();

  @override
  ConsumerState<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends ConsumerState<_ProductPicker> {
  late final ProductSearchController _search;
  late final VoidCallback _removeListener;

  @override
  void initState() {
    super.initState();
    _search = ProductSearchController(dio: ref.read(dioProvider));
    _removeListener = _search.addListener((_) {
      if (mounted) setState(() {});
    }, fireImmediately: false);
    unawaited(_search.reset());
  }

  @override
  void dispose() {
    _removeListener();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _search.snapshot;
    return Column(
      children: [
        TextField(
          decoration: const InputDecoration(
            labelText: 'Buscar producto por nombre o código',
          ),
          onChanged: _search.setQuery,
        ),
        Expanded(
          child: state.isInitialLoading
              ? const Center(child: CircularProgressIndicator())
              : state.error != null
              ? _ErrorState(
                  message: userSafeErrorMessage(
                    state.error,
                    fallback: 'No se pudieron cargar los productos.',
                  ),
                  onRetry: () => unawaited(_search.refresh()),
                )
              : state.items.isEmpty
              ? const Center(
                  child: Text('No hay productos para esta búsqueda.'),
                )
              : ListView.builder(
                  itemCount: state.items.length + (state.hasMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == state.items.length) {
                      return TextButton(
                        onPressed: state.isLoadingMore
                            ? null
                            : () => unawaited(_search.loadMore()),
                        child: const Text('Cargar más productos'),
                      );
                    }
                    final product = state.items[index];
                    return ListTile(
                      title: Text(product.nombre),
                      subtitle: Text(
                        'RD\$${product.precio.toStringAsFixed(2)}',
                      ),
                      onTap: () => Navigator.of(context).pop(product),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ListDialog extends StatelessWidget {
  const _ListDialog({
    required this.name,
    required this.description,
    this.title = 'Nueva lista',
  });

  final TextEditingController name;
  final TextEditingController description;
  final String title;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Nombre'),
          ),
          TextField(
            controller: description,
            decoration: const InputDecoration(labelText: 'Descripción'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final value = name.text.trim();
            if (value.isEmpty) return;
            Navigator.of(
              context,
            ).pop(_ListDraft(value, description.text.trim()));
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}

class _ListDraft {
  const _ListDraft(this.name, this.description);

  final String name;
  final String description;
}

class _RuleDraft {
  const _RuleDraft({
    required this.mode,
    required this.minQuantity,
    this.fixedPrice,
    this.discountPercent,
    this.tiers = const [],
  });

  final String mode;
  final double minQuantity;
  final double? fixedPrice;
  final double? discountPercent;
  final List<PriceListTierDraft> tiers;
}

double _number(String value) =>
    double.tryParse(value.replaceAll(',', '.')) ?? 0;
