import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/app_permissions.dart';
import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/errors/api_exception.dart';
import 'company_manual_models.dart';
import 'company_manual_repository.dart';

class ManualInternoScreen extends ConsumerStatefulWidget {
  const ManualInternoScreen({super.key});

  @override
  ConsumerState<ManualInternoScreen> createState() =>
      _ManualInternoScreenState();
}

class _ManualInternoScreenState extends ConsumerState<ManualInternoScreen> {
  String _searchQuery = '';

  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<CompanyManualEntry> _entries = const [];
  CompanyManualEntryKind? _kindFilter;
  String? _selectedEntryId;
  Set<String> _selectedForBulkDelete = {};

  bool _canManageCurrentUser() {
    final user = ref.read(authStateProvider).user;
    return user != null &&
        hasPermission(user.appRole, AppPermission.manageCompanyManual);
  }

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    final user = ref.read(authStateProvider).user;
    final canManage =
        user != null &&
        hasPermission(user.appRole, AppPermission.manageCompanyManual);

    final repo = ref.read(companyManualRepositoryProvider);
    final cachedItems = await repo.getCachedEntries(includeHidden: canManage);

    if (mounted && cachedItems.isNotEmpty) {
      final cachedSelectedId =
          cachedItems.any((item) => item.id == _selectedEntryId)
          ? _selectedEntryId
          : cachedItems.first.id;
      setState(() {
        _entries = cachedItems;
        _loading = false;
        _error = null;
        _selectedEntryId = cachedSelectedId;
      });
    }

    if (mounted) {
      setState(() {
        _loading = _entries.isEmpty;
        _error = null;
      });
    }

    try {
      final items = await repo.listEntriesAndCache(includeHidden: canManage);

      DateTime? latest;
      for (final item in items) {
        final updatedAt = item.updatedAt ?? item.createdAt;
        if (updatedAt == null) continue;
        if (latest == null || updatedAt.isAfter(latest)) {
          latest = updatedAt;
        }
      }
      if (latest != null) {
        await repo.markSeen(latest);
        ref.invalidate(companyManualSummaryProvider);
      }

      final selectedId = items.any((item) => item.id == _selectedEntryId)
          ? _selectedEntryId
          : (items.isEmpty ? null : items.first.id);

      if (!mounted) return;
      setState(() {
        _entries = items;
        _loading = false;
        _selectedEntryId = selectedId;
        if (!canManage) {
          _selectedForBulkDelete.clear();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : '$e';
        _loading = false;
      });
    }
  }

  List<CompanyManualEntry> get _visibleEntries {
    final filteredByKind =
        (_kindFilter == null
                ? _entries
                : _entries.where((item) => item.kind == _kindFilter))
            .toList();
    final query = _searchQuery.trim().toLowerCase();
    final filtered =
        (query.isEmpty
                ? filteredByKind
                : filteredByKind.where((item) {
                    return item.title.toLowerCase().contains(query) ||
                        (item.summary ?? '').toLowerCase().contains(query) ||
                        item.content.toLowerCase().contains(query) ||
                        (item.moduleKey ?? '').toLowerCase().contains(query);
                  }))
            .toList();
    filtered.sort((left, right) {
      final byOrder = left.sortOrder.compareTo(right.sortOrder);
      if (byOrder != 0) return byOrder;
      return left.title.toLowerCase().compareTo(right.title.toLowerCase());
    });
    return filtered;
  }

  // Eliminada función de búsqueda avanzada (showSearch) y referencias a tipos eliminados.

  void _clearSearch() {
    if (_searchQuery.isEmpty) return;
    setState(() {
      _searchQuery = '';
    });
  }

  String _searchSummaryLabel() {
    final query = _searchQuery.trim();
    if (query.isEmpty) return '';
    return 'Busqueda: "$query"';
  }

  Future<bool> _openEditor({CompanyManualEntry? entry}) async {
    if (!_canManageCurrentUser()) {
      return false;
    }
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final bool? saved;
    if (isMobile) {
      final navigator = Navigator.of(context);
      saved = await navigator.push<bool>(
        MaterialPageRoute<bool>(
          fullscreenDialog: true,
          builder: (_) =>
              _CompanyManualEntryDialog(entry: entry, fullscreen: true),
        ),
      );
    } else {
      saved = await showDialog<bool>(
        context: context,
        builder: (_) => _CompanyManualEntryDialog(entry: entry),
      );
    }
    if (saved == true) {
      await _loadEntries();
      return true;
    }
    return false;
  }

  Future<bool> _deleteEntry(CompanyManualEntry entry) async {
    if (!_canManageCurrentUser()) {
      return false;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar entrada'),
        content: Text('¿Deseas eliminar "${entry.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return false;

    setState(() => _saving = true);
    try {
      await ref.read(companyManualRepositoryProvider).deleteEntry(entry.id);
      await _loadEntries();
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo eliminar: $e')));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteBulkSelected() async {
    if (!_canManageCurrentUser()) return;
    if (_selectedForBulkDelete.isEmpty) return;
    final count = _selectedForBulkDelete.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar múltiples entradas'),
        content: Text(
          '¿Estás seguro que deseas eliminar $count regla${count > 1 ? 's' : ''}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(companyManualRepositoryProvider);
      for (final id in _selectedForBulkDelete) {
        await repo.deleteEntry(id);
      }
      await _loadEntries();
      if (mounted) {
        setState(() => _selectedForBulkDelete.clear());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Se eliminaron $count regla${count > 1 ? 's' : ''}'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al eliminar: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toggleBulkSelection(String entryId) {
    if (!_canManageCurrentUser()) return;
    setState(() {
      if (_selectedForBulkDelete.contains(entryId)) {
        _selectedForBulkDelete.remove(entryId);
      } else {
        _selectedForBulkDelete.add(entryId);
      }
    });
  }

  void _toggleAllBulkSelection() {
    if (!_canManageCurrentUser()) return;
    setState(() {
      if (_selectedForBulkDelete.length == _visibleEntries.length) {
        _selectedForBulkDelete.clear();
      } else {
        _selectedForBulkDelete = _visibleEntries.map((e) => e.id).toSet();
      }
    });
  }

  CompanyManualEntry? _resolveSelectedEntry(List<CompanyManualEntry> entries) {
    if (entries.isEmpty) return null;
    for (final entry in entries) {
      if (entry.id == _selectedEntryId) return entry;
    }
    return entries.first;
  }

  void _openEntryDetail(CompanyManualEntry entry, bool canManage) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 980) {
      setState(() => _selectedEntryId = entry.id);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ManualEntryDetailScreen(
          entry: entry,
          canManage: canManage,
          onEdit: canManage
              ? () async {
                  final saved = await _openEditor(entry: entry);
                  if (saved && mounted && context.mounted) {
                    Navigator.of(context).pop();
                  }
                }
              : null,
          onDelete: canManage
              ? () async {
                  final deleted = await _deleteEntry(entry);
                  if (deleted && mounted && context.mounted) {
                    Navigator.of(context).pop();
                  }
                }
              : null,
        ),
      ),
    );
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'Sin fecha';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final canManage =
        user != null &&
        hasPermission(user.appRole, AppPermission.manageCompanyManual);
    final entries = _visibleEntries;
    final selectedEntry = _resolveSelectedEntry(entries);

    return Scaffold(
      appBar: CustomAppBar(
        title: _selectedForBulkDelete.isEmpty
            ? 'Manual Interno'
            : '${_selectedForBulkDelete.length} seleccionada${_selectedForBulkDelete.length > 1 ? 's' : ''}',
        showLogo: false,
        darkerTone: true,
        actions: [
          if (canManage && _selectedForBulkDelete.isNotEmpty) ...[
            IconButton(
              tooltip: 'Seleccionar todas',
              onPressed: _toggleAllBulkSelection,
              icon: Icon(
                _selectedForBulkDelete.length == _visibleEntries.length
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
              ),
            ),
            IconButton(
              tooltip: 'Eliminar seleccionadas',
              icon: const Icon(Icons.delete_rounded),
              onPressed: _saving ? null : _deleteBulkSelected,
            ),
            IconButton(
              tooltip: 'Cancelar selección',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() => _selectedForBulkDelete.clear()),
            ),
          ] else ...[
            IconButton(
              tooltip: 'Buscar',
              onPressed: null, // Búsqueda avanzada eliminada
              icon: const Icon(Icons.search_rounded),
            ),
            PopupMenuButton<CompanyManualEntryKind?>(
              tooltip: 'Filtrar',
              initialValue: _kindFilter,
              onSelected: (kind) {
                setState(() {
                  _kindFilter = kind;
                });
              },
              itemBuilder: (context) => [
                const PopupMenuItem<CompanyManualEntryKind?>(
                  value: null,
                  child: Text('Todo'),
                ),
                ...CompanyManualEntryKind.values.map(
                  (kind) => PopupMenuItem<CompanyManualEntryKind?>(
                    value: kind,
                    child: Text(kind.label),
                  ),
                ),
              ],
              icon: const Icon(Icons.tune_rounded),
            ),
          ],
        ],
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
              Theme.of(context).scaffoldBackgroundColor,
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: Column(
          children: [
            if (_searchQuery.isNotEmpty || _kindFilter != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                child: _ManualActiveFiltersBar(
                  searchLabel: _searchSummaryLabel(),
                  filterLabel: _kindFilter?.label,
                  onClearSearch: _searchQuery.isEmpty ? null : _clearSearch,
                  onClearFilter: _kindFilter == null
                      ? null
                      : () {
                          setState(() {
                            _kindFilter = null;
                          });
                        },
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : entries.isEmpty
                  ? const Center(child: Text('No hay reglas para mostrar'))
                  : RefreshIndicator(
                      onRefresh: _loadEntries,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 980;
                          final listPane = _ManualEntriesList(
                            entries: entries,
                            selectedEntryId: selectedEntry?.id,
                            canManage: canManage,
                            selectedForBulkDelete: _selectedForBulkDelete,
                            onOpenEntry: (entry) =>
                                _openEntryDetail(entry, canManage),
                            onEditEntry: (entry) => _openEditor(entry: entry),
                            onDeleteEntry: _deleteEntry,
                            onToggleBulkSelection: _toggleBulkSelection,
                            formatDate: _formatDate,
                          );

                          if (!isWide) {
                            return listPane;
                          }

                          // Desktop split view: left = list, right = detail
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Left: List
                                SizedBox(width: 340, child: listPane),
                                const SizedBox(width: 22),
                                // Right: Detail/content
                                Expanded(
                                  child: _ManualEntryDetailPane(
                                    entry: selectedEntry,
                                    canManage: canManage,
                                    onEdit: selectedEntry == null
                                        ? null
                                        : () =>
                                              _openEditor(entry: selectedEntry),
                                    onDelete: selectedEntry == null
                                        ? null
                                        : () => _deleteEntry(selectedEntry),
                                    formatDate: _formatDate,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('Nueva entrada'),
            )
          : null,
    );
  }
}

class _ManualActiveFiltersBar extends StatelessWidget {
  const _ManualActiveFiltersBar({
    required this.searchLabel,
    required this.filterLabel,
    required this.onClearSearch,
    required this.onClearFilter,
  });

  final String searchLabel;
  final String? filterLabel;
  final VoidCallback? onClearSearch;
  final VoidCallback? onClearFilter;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (searchLabel.isNotEmpty)
            _ManualRemovableChip(
              icon: Icons.search_rounded,
              label: searchLabel,
              onRemove: onClearSearch,
            ),
          if (filterLabel != null)
            _ManualRemovableChip(
              icon: Icons.tune_rounded,
              label: filterLabel!,
              onRemove: onClearFilter,
            ),
        ],
      ),
    );
  }
}

class _ManualRemovableChip extends StatelessWidget {
  const _ManualRemovableChip({
    required this.icon,
    required this.label,
    required this.onRemove,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: scheme.primary),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ManualEntriesList extends StatelessWidget {
  const _ManualEntriesList({
    required this.entries,
    required this.selectedEntryId,
    required this.canManage,
    required this.selectedForBulkDelete,
    required this.onOpenEntry,
    required this.onEditEntry,
    required this.onDeleteEntry,
    required this.onToggleBulkSelection,
    required this.formatDate,
  });

  final List<CompanyManualEntry> entries;
  final String? selectedEntryId;
  final bool canManage;
  final Set<String> selectedForBulkDelete;
  final ValueChanged<CompanyManualEntry> onOpenEntry;
  final Future<bool> Function(CompanyManualEntry entry) onEditEntry;
  final Future<bool> Function(CompanyManualEntry entry) onDeleteEntry;
  final ValueChanged<String> onToggleBulkSelection;
  final String Function(DateTime? value) formatDate;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _ManualTopicCard(
          entry: entry,
          isSelected: entry.id == selectedEntryId,
          isChecked: selectedForBulkDelete.contains(entry.id),
          canManage: canManage,
          onTap: () => onOpenEntry(entry),
          onEdit: () => onEditEntry(entry),
          onDelete: () => onDeleteEntry(entry),
          onToggleCheckbox: () => onToggleBulkSelection(entry.id),
          formatDate: formatDate,
        );
      },
    );
  }
}

class _ManualTopicCard extends StatelessWidget {
  const _ManualTopicCard({
    required this.entry,
    required this.isSelected,
    required this.isChecked,
    required this.canManage,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleCheckbox,
    required this.formatDate,
  });

  final CompanyManualEntry entry;
  final bool isSelected;
  final bool isChecked;
  final bool canManage;
  final VoidCallback onTap;
  final Future<bool> Function() onEdit;
  final Future<bool> Function() onDelete;
  final VoidCallback onToggleCheckbox;
  final String Function(DateTime? value) formatDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: isSelected
                ? scheme.primary.withValues(alpha: 0.08)
                : scheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected
                  ? scheme.primary.withValues(alpha: 0.45)
                  : scheme.outlineVariant,
              width: isSelected ? 1.4 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: onToggleCheckbox,
                child: Checkbox(
                  value: isChecked,
                  onChanged: (_) => onToggleCheckbox(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ManualCompactEntryBody(entry: entry, dense: false),
              ),
              const SizedBox(width: 8),
              if (canManage)
                PopupMenuButton<String>(
                  tooltip: 'Opciones',
                  onSelected: (value) async {
                    if (value == 'edit') {
                      await onEdit();
                    } else if (value == 'delete') {
                      await onDelete();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Editar')),
                    PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                  ],
                )
              else
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 15,
                  color: scheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualCompactEntryBody extends StatelessWidget {
  const _ManualCompactEntryBody({required this.entry, required this.dense});

  final CompanyManualEntry entry;
  final bool dense;

  String _headline() {
    final audienceLabel = _audienceLabel(entry);
    return 'Tipo: ${entry.kind.label}  •  Dirigido a: $audienceLabel';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          entry.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:
              (dense ? theme.textTheme.titleSmall : theme.textTheme.bodyLarge)
                  ?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: dense ? 14 : 13.6,
                  ),
        ),
        const SizedBox(height: 4),
        Text(
          _headline(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            height: 1.15,
            fontSize: dense ? 11.9 : 11.6,
          ),
        ),
      ],
    );
  }
}

String _audienceLabel(CompanyManualEntry entry) {
  if (entry.targetRoles.isNotEmpty) {
    return entry.targetRoles.map((role) => role.label).join(', ');
  }
  if (entry.audience == CompanyManualAudience.roleSpecific) {
    return 'Roles definidos';
  }
  return 'Todo el equipo';
}

class _ManualEntryDetailPane extends StatelessWidget {
  const _ManualEntryDetailPane({
    required this.entry,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
    required this.formatDate,
    this.scrollableBody = true,
  });

  final CompanyManualEntry? entry;
  final bool canManage;
  final Future<bool> Function()? onEdit;
  final Future<bool> Function()? onDelete;
  final String Function(DateTime? value) formatDate;
  final bool scrollableBody;

  @override
  Widget build(BuildContext context) {
    final selectedEntry = entry;
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    if (selectedEntry == null) {
      return const _ManualEmptyDetail();
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          _ManualDetailHeader(
            entry: selectedEntry,
            canManage: canManage,
            onEdit: onEdit,
            onDelete: onDelete,
            formatDate: formatDate,
            compact: isCompact,
          ),
          const Divider(height: 1),
          if (scrollableBody)
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isCompact ? 18 : 24),
                child: _ManualEntryBody(entry: selectedEntry),
              ),
            )
          else
            Padding(
              padding: EdgeInsets.all(isCompact ? 18 : 24),
              child: _ManualEntryBody(entry: selectedEntry),
            ),
        ],
      ),
    );
  }
}

class _ManualDetailHeader extends StatelessWidget {
  const _ManualDetailHeader({
    required this.entry,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
    required this.formatDate,
    required this.compact,
  });

  final CompanyManualEntry entry;
  final bool canManage;
  final Future<bool> Function()? onEdit;
  final Future<bool> Function()? onDelete;
  final String Function(DateTime? value) formatDate;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Variable roles eliminada porque no se usa.
    final updatedAt = entry.updatedAt ?? entry.createdAt;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        compact ? 18 : 20,
        20,
        compact ? 14 : 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  entry.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                    fontSize: compact ? 21 : null,
                  ),
                ),
              ),
              if (canManage)
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'edit' && onEdit != null) {
                      await onEdit!.call();
                    }
                    if (value == 'delete' && onDelete != null) {
                      await onDelete!.call();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Editar')),
                    PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                  ],
                ),
            ],
          ),
          SizedBox(height: compact ? 8 : 10),
          // Etiquetas eliminadas para un diseño más limpio.
          SizedBox(height: compact ? 10 : 12),
          Text(
            'Última actualización ${formatDate(updatedAt)}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualEntryBody extends StatelessWidget {
  const _ManualEntryBody({required this.entry});

  final CompanyManualEntry entry;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 700;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (entry.summary != null && entry.summary!.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(isCompact ? 14 : 16),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              entry.summary!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: isCompact ? 13 : 13.4,
                height: 1.45,
              ),
            ),
          ),
          SizedBox(height: isCompact ? 14 : 16),
        ],
        SelectableText(
          entry.content,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            height: 1.72,
            fontSize: isCompact ? 13 : 13.4,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _ManualEmptyDetail extends StatelessWidget {
  const _ManualEmptyDetail();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Selecciona un tema',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Abre una tarjeta del panel izquierdo para leer el contenido completo aquí.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManualEntryDetailScreen extends StatelessWidget {
  const _ManualEntryDetailScreen({
    required this.entry,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  final CompanyManualEntry entry;
  final bool canManage;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onDelete;

  String _formatDate(DateTime? value) {
    if (value == null) return 'Sin fecha';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                  Theme.of(context).colorScheme.surface,
                  Theme.of(context).colorScheme.surfaceContainerLowest,
                ],
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 72, 16, 20),
              child: _ManualEntryDetailPane(
                entry: entry,
                canManage: false,
                onEdit: null,
                onDelete: null,
                formatDate: _formatDate,
                scrollableBody: false,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  _FloatingDetailAction(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Regresar',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  if (canManage && onEdit != null)
                    _FloatingDetailAction(
                      icon: Icons.edit_outlined,
                      tooltip: 'Editar',
                      onTap: () async => onEdit!.call(),
                    ),
                  if (canManage && onDelete != null) ...[
                    const SizedBox(width: 8),
                    _FloatingDetailAction(
                      icon: Icons.delete_outline,
                      tooltip: 'Eliminar',
                      onTap: () async => onDelete!.call(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingDetailAction extends StatelessWidget {
  const _FloatingDetailAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.surface.withValues(alpha: 0.92),
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Icon(icon, size: 20, color: scheme.onSurface),
          ),
        ),
      ),
    );
  }
}

class _CompanyManualEntryDialog extends ConsumerStatefulWidget {
  const _CompanyManualEntryDialog({this.entry, this.fullscreen = false});

  final CompanyManualEntry? entry;
  final bool fullscreen;

  @override
  ConsumerState<_CompanyManualEntryDialog> createState() =>
      _CompanyManualEntryDialogState();
}

class _CompanyManualEntryDialogState
    extends ConsumerState<_CompanyManualEntryDialog> {
  static const List<AppRole> _editableRoles = [
    AppRole.asistente,
    AppRole.vendedor,
    AppRole.marketing,
    AppRole.tecnico,
    AppRole.admin,
  ];

  late final TextEditingController _titleCtrl;
  late final TextEditingController _summaryCtrl;
  late final TextEditingController _contentCtrl;
  late final TextEditingController _moduleCtrl;
  late final TextEditingController _sortCtrl;

  late CompanyManualEntryKind _kind;
  late CompanyManualAudience _audience;
  late bool _published;
  late Set<AppRole> _targetRoles;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.entry?.title ?? '');
    _summaryCtrl = TextEditingController(text: widget.entry?.summary ?? '');
    _contentCtrl = TextEditingController(text: widget.entry?.content ?? '');
    _moduleCtrl = TextEditingController(text: widget.entry?.moduleKey ?? '');
    _sortCtrl = TextEditingController(
      text: (widget.entry?.sortOrder ?? 0).toString(),
    );
    _kind = widget.entry?.kind ?? CompanyManualEntryKind.generalRule;
    _audience = widget.entry?.audience ?? CompanyManualAudience.general;
    _published = widget.entry?.published ?? true;
    _targetRoles = {...?widget.entry?.targetRoles};
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _summaryCtrl.dispose();
    _contentCtrl.dispose();
    _moduleCtrl.dispose();
    _sortCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final isEditing = widget.entry != null;
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    final sortOrder = int.tryParse(_sortCtrl.text.trim()) ?? 0;
    if (title.isEmpty || content.isEmpty) {
      setState(() => _error = 'Título y contenido son obligatorios');
      return;
    }
    if (_audience == CompanyManualAudience.roleSpecific &&
        _targetRoles.isEmpty) {
      setState(
        () => _error = 'Selecciona al menos un rol para una entrada por rol',
      );
      return;
    }
    if (isEditing) {
      final editId = widget.entry?.id.trim() ?? '';
      final editOwnerId = widget.entry?.ownerId.trim() ?? '';
      if (editId.isEmpty || editOwnerId.isEmpty) {
        setState(() {
          _error = 'No se puede actualizar esta norma por datos incompletos.';
        });
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final entry = CompanyManualEntry(
      id: widget.entry?.id ?? '',
      ownerId: widget.entry?.ownerId ?? '',
      title: title,
      summary: _summaryCtrl.text.trim().isEmpty
          ? null
          : _summaryCtrl.text.trim(),
      content: content,
      kind: _kind,
      audience: _audience,
      targetRoles: _targetRoles.toList()
        ..sort((a, b) => a.label.compareTo(b.label)),
      moduleKey: _moduleCtrl.text.trim().isEmpty
          ? null
          : _moduleCtrl.text.trim(),
      published: _published,
      sortOrder: sortOrder,
      createdByUserId: widget.entry?.createdByUserId ?? '',
      updatedByUserId: widget.entry?.updatedByUserId,
      createdAt: widget.entry?.createdAt,
      updatedAt: widget.entry?.updatedAt,
    );

    try {
      final repo = ref.read(companyManualRepositoryProvider);
      if (!isEditing) {
        await repo.createEntry(entry);
      } else {
        await repo.updateEntry(entry);
      }
      ref.invalidate(companyManualSummaryProvider);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  String get _screenTitle {
    return widget.entry == null ? 'Nueva norma' : 'Editar norma';
  }

  String get _screenSubtitle {
    return widget.entry == null
        ? 'Completa lo esencial primero. Luego ajusta visibilidad, roles o modulo si hace falta.'
        : 'Actualiza la norma con un formulario mas comodo para vista movil.';
  }

  Widget _buildErrorBanner(BuildContext context) {
    final message = _error;
    if (message == null || message.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildAudienceChips(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: CompanyManualAudience.values
          .map((audience) {
            final selected = _audience == audience;
            return ChoiceChip(
              label: Text(audience.label),
              selected: selected,
              onSelected: _saving
                  ? null
                  : (_) {
                      setState(() {
                        _audience = audience;
                        if (_audience == CompanyManualAudience.general) {
                          _targetRoles.clear();
                        }
                      });
                    },
            );
          })
          .toList(growable: false),
    );
  }

  Widget _buildRoleChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final role in _editableRoles)
          FilterChip(
            label: Text(role.label),
            selected: _targetRoles.contains(role),
            onSelected: _saving
                ? null
                : (selected) {
                    setState(() {
                      if (selected) {
                        _targetRoles.add(role);
                      } else {
                        _targetRoles.remove(role);
                      }
                    });
                  },
          ),
      ],
    );
  }

  Widget _buildEditorFields(BuildContext context, {required bool mobile}) {
    return ListView(
      padding: EdgeInsets.fromLTRB(16, mobile ? 16 : 0, 16, mobile ? 20 : 0),
      children: [
        if (mobile)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                  Theme.of(context).colorScheme.surfaceContainerLowest,
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _screenTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  _screenSubtitle,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        if (mobile) const SizedBox(height: 14),
        _buildErrorBanner(context),
        if (_error != null && _error!.isNotEmpty) const SizedBox(height: 14),
        _buildSectionCard(
          context: context,
          title: 'Contenido principal',
          subtitle:
              'Primero define el titulo y el texto de la norma. Eso es lo mas importante.',
          child: Column(
            children: [
              TextField(
                controller: _titleCtrl,
                enabled: !_saving,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Titulo',
                  hintText: 'Ejemplo: Protocolo para cierre de caja',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _summaryCtrl,
                enabled: !_saving,
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Resumen breve',
                  hintText: 'Describe rapidamente de que trata esta norma',
                  helperText: 'Opcional, pero ayuda mucho en movil.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contentCtrl,
                enabled: !_saving,
                textCapitalization: TextCapitalization.sentences,
                minLines: mobile ? 10 : 8,
                maxLines: mobile ? 16 : 14,
                decoration: const InputDecoration(
                  labelText: 'Contenido',
                  hintText:
                      'Escribe los pasos, reglas o indicaciones completas',
                  helperText:
                      'Usa parrafos cortos o listas para que sea facil de leer.',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildSectionCard(
          context: context,
          title: 'Clasificacion',
          subtitle:
              'Ajusta tipo, alcance y si esta norma pertenece a un modulo especifico.',
          child: Column(
            children: [
              DropdownButtonFormField<CompanyManualEntryKind>(
                initialValue: _kind,
                items: CompanyManualEntryKind.values
                    .map(
                      (kind) => DropdownMenuItem(
                        value: kind,
                        child: Text(kind.label),
                      ),
                    )
                    .toList(growable: false),
                onChanged: _saving
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _kind = value);
                      },
                decoration: const InputDecoration(labelText: 'Tipo de entrada'),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Alcance',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: _buildAudienceChips(context),
              ),
              if (_audience == CompanyManualAudience.roleSpecific) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Roles permitidos',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: _buildRoleChips(),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _moduleCtrl,
                enabled: !_saving,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Modulo relacionado',
                  hintText: 'Opcional: ventas, tecnico, inventario...',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _buildSectionCard(
          context: context,
          title: 'Visibilidad y orden',
          subtitle:
              'Controla si la norma esta visible y en que posicion se muestra.',
          child: Column(
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _published,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _published = value),
                title: const Text('Visible para usuarios'),
                subtitle: const Text('Desactivalo si todavia no debe verse.'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _sortCtrl,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Orden',
                  hintText: '0, 1, 2...',
                  helperText: 'Los numeros menores aparecen primero.',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionBar(BuildContext context, {required bool mobile}) {
    final content = Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Guardando...' : 'Guardar'),
          ),
        ),
      ],
    );

    if (!mobile) {
      return content;
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: content,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = widget.fullscreen || MediaQuery.sizeOf(context).width < 720;
    final fields = _buildEditorFields(context, mobile: mobile);

    if (mobile) {
      return Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(title: Text(_screenTitle), centerTitle: false),
        body: fields,
        bottomNavigationBar: _buildActionBar(context, mobile: true),
      );
    }

    return AlertDialog(
      title: Text(_screenTitle),
      content: SizedBox(
        width: 620,
        child: SizedBox(height: 640, child: fields),
      ),
      actions: [_buildActionBar(context, mobile: false)],
    );
  }
}
