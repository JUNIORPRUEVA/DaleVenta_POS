import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/warnings_controller.dart';
import '../data/employee_warning_model.dart';
import '../../../core/routing/routes.dart';
import 'warning_labels.dart';
import 'warning_create_screen.dart';

class AmonestacionesScreen extends ConsumerStatefulWidget {
  const AmonestacionesScreen({super.key});

  @override
  ConsumerState<AmonestacionesScreen> createState() =>
      _AmonestacionesScreenState();
}

class _AmonestacionesScreenState extends ConsumerState<AmonestacionesScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(canAccessAmonestacionesProvider);

    // Si no es admin, mostrar acceso denegado
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Amonestaciones'),
          backgroundColor: const Color(0xFF1a1a2e),
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Acceso no permitido',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Solo administradores pueden acceder a este módulo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Volver'),
              ),
            ],
          ),
        ),
      );
    }

    final state = ref.watch(warningsListControllerProvider);
    final ctrl = ref.read(warningsListControllerProvider.notifier);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text(
          'Amonestaciones',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ctrl.load(reset: true),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
        onPressed: () => _openCreate(context),
        icon: const Icon(Icons.add),
        label: const Text('Nueva'),
      ),
      body: Column(
        children: [
          _FilterBar(
            searchCtrl: _searchCtrl,
            filterStatus: state.filterStatus,
            filterWarningType: state.filterWarningType,
            onSearch: ctrl.setSearch,
            onStatus: ctrl.setFilterStatus,
            onWarningType: ctrl.setFilterWarningType,
          ),
          Expanded(
            child: state.loading && state.items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : state.error != null && state.items.isEmpty
                ? _ErrorView(
                    message: state.error!,
                    onRetry: () => ctrl.load(reset: true),
                  )
                : state.items.isEmpty
                ? const _EmptyView()
                : RefreshIndicator(
                    onRefresh: () => ctrl.load(reset: true),
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                      itemCount: state.items.length,
                      itemBuilder: (context, i) => _WarningCard(
                        warning: state.items[i],
                        onTap: () => _openDetail(context, state.items[i].id),
                        onDelete: () =>
                            _confirmDelete(context, state.items[i], ctrl),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _openCreate(BuildContext context) async {
    final result = await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const WarningCreateScreen()));
    if (result == true && mounted) {
      ref.read(warningsListControllerProvider.notifier).load(reset: true);
    }
  }

  void _openDetail(BuildContext context, String id) {
    context.push(Routes.amonestacionById(id));
  }

  Future<void> _confirmDelete(
    BuildContext context,
    EmployeeWarning w,
    WarningsListController ctrl,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar amonestacion'),
        content: Text(
          '¿Eliminar "${w.warningNumber}"? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ctrl.deleteWarning(w.id);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
}

// ── Filter bar ────────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final TextEditingController searchCtrl;
  final String? filterStatus;
  final String? filterWarningType;
  final void Function(String) onSearch;
  final void Function(String?) onStatus;
  final void Function(String?) onWarningType;

  const _FilterBar({
    required this.searchCtrl,
    required this.filterStatus,
    required this.filterWarningType,
    required this.onSearch,
    required this.onStatus,
    required this.onWarningType,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          TextField(
            controller: searchCtrl,
            decoration: InputDecoration(
              hintText: 'Buscar por nombre, número…',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            onChanged: onSearch,
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _DropFilter(
                  label: 'Estado',
                  value: filterStatus,
                  options: WarningLabels.status,
                  onChanged: onStatus,
                ),
                const SizedBox(width: 8),
                _DropFilter(
                  label: 'Tipo',
                  value: filterWarningType,
                  options: WarningLabels.warningType,
                  onChanged: onWarningType,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DropFilter extends StatelessWidget {
  final String label;
  final String? value;
  final Map<String, String> options;
  final void Function(String?) onChanged;

  const _DropFilter({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: value,
      hint: Text(
        label,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      isDense: true,
      underline: const SizedBox(),
      style: const TextStyle(fontSize: 12, color: Colors.black87),
      items: [
        DropdownMenuItem<String>(
          value: null,
          child: Text('Todos ($label)', style: const TextStyle(fontSize: 12)),
        ),
        ...options.entries.map(
          (e) => DropdownMenuItem<String>(
            value: e.key,
            child: Text(e.value, style: const TextStyle(fontSize: 12)),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

// ── Warning card ──────────────────────────────────────────────────────────────

class _WarningCard extends StatelessWidget {
  final EmployeeWarning warning;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _WarningCard({
    required this.warning,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = WarningLabels.statusColor(warning.status);
    final typeLabel =
        WarningLabels.warningType[warning.warningType ?? ''] ??
        (warning.warningType ?? 'No registrado');
    final reason = (warning.reason ?? warning.title).trim();
    final employeeName =
        (warning.employeeNameSnapshot ??
                warning.employeeUser?.nombreCompleto ??
                warning.employeeUserId)
            .trim();
    final issuer =
        (warning.issuedByNameSnapshot ??
                warning.createdByUser?.nombreCompleto ??
                'No registrado')
            .trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      warning.warningNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  _Pill(
                    label:
                        WarningLabels.status[warning.status] ?? warning.status,
                    color: statusColor,
                  ),
                  if (onDelete != null) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: onDelete,
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                reason,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 13,
                    color: Colors.grey.shade500,
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      employeeName,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _Pill(label: typeLabel, color: const Color(0xFF34495e)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${WarningLabels.fmt(warning.warningDate)}  |  Encargado: $issuer',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final String label;
  final Color color;

  const _Pill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 42),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: onRetry, child: const Text('Reintentar')),
      ],
    ),
  );
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.assignment_outlined, size: 52, color: Colors.grey),
        SizedBox(height: 8),
        Text('No hay amonestaciones', style: TextStyle(color: Colors.grey)),
      ],
    ),
  );
}
