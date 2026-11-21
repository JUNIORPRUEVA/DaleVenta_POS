import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/errors/user_safe_error_text.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/customer_visible_text.dart';
import 'product_lifecycle_feedback.dart';
import 'product_artwork.dart';
import '../../catalogo/data/catalog_repository.dart';
import '../../catalogo/data/product_lifecycle_snapshot.dart';

/// Online-only decisions. Eligibility and financial changes belong to the API.
class ProductLifecycleDialog extends ConsumerStatefulWidget {
  const ProductLifecycleDialog({
    super.key,
    required this.productId,
    required this.name,
    required this.onChanged,
  });
  final String productId;
  final String name;
  final Future<void> Function() onChanged;
  @override
  ConsumerState<ProductLifecycleDialog> createState() =>
      _ProductLifecycleDialogState();
}

class _ProductLifecycleDialogState
    extends ConsumerState<ProductLifecycleDialog> {
  ProductLifecycleSnapshot? _snapshot;
  String? _error;
  bool _busy = true;
  final _reason = TextEditingController();
  final _operationId = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _snapshot = null;
    });
    try {
      final snapshot = await ref
          .read(catalogRepositoryProvider)
          .productLifecycle(widget.productId);
      if (mounted) setState(() => _snapshot = snapshot);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userSafeErrorMessage(
            error,
            fallback: 'No se pudo comprobar el producto.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _act(String action) async {
    final state = _snapshot;
    if (state == null || _busy) return;
    if (action == 'annul' && _reason.text.trim().length < 10) {
      setState(() => _error = 'Escribe un motivo de al menos 10 caracteres.');
      return;
    }
    final confirmed = await ProductLifecycleFeedback.confirm(context, action);
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(catalogRepositoryProvider);
    try {
      switch (action) {
        case 'delete':
          await repo.deleteProduct(widget.productId);
          break;
        case 'annul':
          await repo.annulProduct(
            widget.productId,
            operationId: _operationId,
            expectedVersion: state.version,
            reason: _reason.text,
          );
          break;
        case 'restore':
          await repo.restoreProduct(widget.productId);
          break;
        default:
          await repo.archiveProduct(widget.productId);
      }
      var refreshed = true;
      try {
        await widget.onChanged();
      } catch (_) {
        refreshed = false;
      }
      if (mounted) {
        ProductLifecycleFeedback.notice(
          context,
          refreshed
              ? ProductLifecycleFeedback.success(action)
              : 'Cambio guardado. Actualiza el catálogo.',
          warning: !refreshed,
        );
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) return;
      // Keep the command identity after an uncertain response. A retry cannot
      // create another compensating movement; the server also rechecks version.
      setState(() {
        _snapshot = null;
        _error = userSafeErrorMessage(
          error,
          fallback: 'No se confirmó el cambio. Comprueba el estado.',
        );
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _snapshot;
    final buttonStyle = OutlinedButton.styleFrom(
      shape: const RoundedRectangleBorder(),
    );
    return AlertDialog(
      shape: const RoundedRectangleBorder(),
      title: const Text('Gestionar producto'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.name == widget.productId
                    ? 'Producto'
                    : customerVisibleText(widget.name, fallback: 'Producto'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (!_busy && state != null) ...[
                const SizedBox(height: 12),
                Text(
                  '${switch (state.status) {
                    'ANNULLED' => 'Alta anulada',
                    'ARCHIVED' => 'Archivado',
                    _ => 'Activo',
                  }} · Existencias: ${state.stock}',
                ),
                const SizedBox(height: 8),
                Text(
                  customerVisibleText(state.reason),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (state.canAnnul) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _reason,
                    maxLength: 500,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Motivo para anular el alta',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (state.canArchive)
                      OutlinedButton.icon(
                        style: buttonStyle,
                        onPressed: () => _act('archive'),
                        icon: const Icon(Icons.archive_outlined),
                        label: const Text('Archivar'),
                      ),
                    if (state.canRestore)
                      OutlinedButton.icon(
                        style: buttonStyle,
                        onPressed: () => _act('restore'),
                        icon: const Icon(Icons.unarchive_outlined),
                        label: const Text('Restaurar'),
                      ),
                    if (state.canDelete)
                      OutlinedButton.icon(
                        style: buttonStyle,
                        onPressed: () => _act('delete'),
                        icon: const ProductArtwork(ProductArtworkKind.delete),
                        label: const Text('Eliminar definitivamente'),
                      ),
                    if (state.canAnnul)
                      OutlinedButton.icon(
                        style: buttonStyle,
                        onPressed: () => _act('annul'),
                        icon: const Icon(Icons.undo),
                        label: const Text('Anular alta'),
                      ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (!_busy)
          TextButton(onPressed: _load, child: const Text('Comprobar estado')),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

class ArchivedProductsDialog extends ConsumerStatefulWidget {
  const ArchivedProductsDialog({super.key, required this.onChanged});
  final Future<void> Function() onChanged;
  @override
  ConsumerState<ArchivedProductsDialog> createState() =>
      _ArchivedProductsDialogState();
}

class _ArchivedProductsDialogState
    extends ConsumerState<ArchivedProductsDialog> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  int _page = 1;
  bool _busy = false, _more = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool next = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = next ? _page + 1 : 1;
      final rows = await ref
          .read(catalogRepositoryProvider)
          .archivedProducts(search: _search.text, page: page);
      if (mounted) {
        setState(() {
          _items = next ? [..._items, ...rows] : rows;
          _page = page;
          _more = rows.length == 50;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = userSafeErrorMessage(
            error,
            fallback: 'No se pudieron cargar los archivados.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    shape: const RoundedRectangleBorder(),
    title: const Text('Productos archivados'),
    content: SizedBox(
      width: 820,
      height: MediaQuery.sizeOf(context).height < 640
          ? MediaQuery.sizeOf(context).height * .55
          : (MediaQuery.sizeOf(context).height * .75).clamp(480.0, 640.0),
      child: Column(
        children: [
          TextField(
            controller: _search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              labelText: 'Buscar por nombre o código',
              border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
              enabledBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: AppColors.border),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: AppColors.primary),
              ),
              suffixIcon: IconButton(
                tooltip: 'Buscar',
                onPressed: _busy ? null : () => _load(),
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: AppColors.error)),
          Expanded(
            child: !_busy && _error == null && _items.isEmpty
                ? const Center(child: Text('Sin productos archivados'))
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final item = _items[i];
                      final annulled = item['annulledAt'] != null;
                      return ListTile(
                        dense: true,
                        shape: const RoundedRectangleBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        leading: Icon(
                          annulled ? Icons.task_alt : Icons.archive_outlined,
                          size: 20,
                          color: AppColors.primary,
                        ),
                        title: Text(
                          item['nombre'] == item['id']
                              ? 'Producto'
                              : customerVisibleText(
                                  '${item['nombre'] ?? ''}',
                                  fallback: 'Producto',
                                ),
                        ),
                        subtitle: Text(
                          '${item['codigo'] == item['id'] ? 'Sin código' : customerVisibleText('${item['codigo'] ?? ''}', fallback: 'Sin código')} · ${annulled ? 'Alta anulada' : 'Archivado'}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _busy
                            ? null
                            : () => showDialog<void>(
                                context: context,
                                builder: (_) => ProductLifecycleDialog(
                                  productId: '${item['id']}',
                                  name: '${item['nombre']}',
                                  onChanged: () async {
                                    await widget.onChanged();
                                    await _load();
                                  },
                                ),
                              ),
                      );
                    },
                  ),
          ),
          if (_more && !_busy)
            TextButton(
              onPressed: () => _load(next: true),
              child: const Text('Ver más'),
            ),
        ],
      ),
    ),
    actions: [
      if (_error != null && !_busy)
        TextButton(onPressed: () => _load(), child: const Text('Reintentar')),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cerrar'),
      ),
    ],
  );
}
