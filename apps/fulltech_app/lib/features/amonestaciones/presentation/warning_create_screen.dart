import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_provider.dart';
import '../../../core/models/user_model.dart';
import '../../user/data/users_repository.dart';
import '../application/warnings_controller.dart';
import '../data/employee_warning_model.dart';
import '../data/employee_warnings_repository.dart';
import 'warning_labels.dart';

class WarningCreateScreen extends ConsumerStatefulWidget {
  final EmployeeWarning? existing;
  const WarningCreateScreen({super.key, this.existing});

  @override
  ConsumerState<WarningCreateScreen> createState() =>
      _WarningCreateScreenState();
}

class _WarningCreateScreenState extends ConsumerState<WarningCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _saveAsDraft = false;

  List<UserModel> _employees = [];
  UserModel? _selectedEmployee;

  final _reasonCtrl = TextEditingController();
  final _detailsCtrl = TextEditingController();
  final _incidentTimeCtrl = TextEditingController();
  final _incidentPlaceCtrl = TextEditingController();
  final _issuerNameCtrl = TextEditingController();
  final _issuerRoleCtrl = TextEditingController();
  final _internalNotesCtrl = TextEditingController();

  DateTime _warningDate = DateTime.now();
  DateTime _incidentDate = DateTime.now();
  String _warningType = 'WRITTEN';

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _fillFromExisting();
    final user = ref.read(authStateProvider).user;
    _issuerNameCtrl.text = user?.nombreCompleto ?? '';
  }

  void _fillFromExisting() {
    final w = widget.existing;
    if (w == null) return;

    _reasonCtrl.text = (w.reason ?? w.title).trim();
    _detailsCtrl.text = (w.details ?? w.description).trim();
    _incidentTimeCtrl.text = (w.incidentTime ?? '').trim();
    _incidentPlaceCtrl.text = (w.incidentPlace ?? '').trim();
    _issuerNameCtrl.text = (w.issuedByNameSnapshot ?? '').trim();
    _issuerRoleCtrl.text = (w.issuedByPositionSnapshot ?? '').trim();
    _internalNotesCtrl.text = (w.internalNotes ?? '').trim();
    _warningDate = w.warningDate;
    _incidentDate = w.incidentDate;
    _warningType = (w.warningType ?? 'WRITTEN').trim().isEmpty
        ? 'WRITTEN'
        : (w.warningType ?? 'WRITTEN');
    _saveAsDraft = w.status == 'DRAFT';
  }

  Future<void> _loadEmployees() async {
    try {
      final all = await ref.read(usersRepositoryProvider).getAllUsers();
      if (!mounted) return;
      setState(() {
        _employees = all;
        final existing = widget.existing;
        if (existing != null) {
          _selectedEmployee = all
              .where((u) => u.id == existing.employeeUserId)
              .firstOrNull;
        }
      });
    } catch (_) {
      // handled by validator on submit
    }
  }

  Future<void> _pickDate({required bool warningDate}) async {
    final initial = warningDate ? _warningDate : _incidentDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (warningDate) {
        _warningDate = picked;
      } else {
        _incidentDate = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedEmployee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona un empleado.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final repo = ref.read(employeeWarningsRepositoryProvider);
      final payload = {
        'employeeUserId': _selectedEmployee!.id,
        'warningDate': _warningDate.toIso8601String(),
        'incidentDate': _incidentDate.toIso8601String(),
        'warningType': _warningType,
        'reason': _reasonCtrl.text.trim(),
        'details': _detailsCtrl.text.trim(),
        'incidentTime': _incidentTimeCtrl.text.trim(),
        'incidentPlace': _incidentPlaceCtrl.text.trim(),
        'issuedByNameSnapshot': _issuerNameCtrl.text.trim(),
        'issuedByPositionSnapshot': _issuerRoleCtrl.text.trim(),
        'internalNotes': _internalNotesCtrl.text.trim(),
        'saveAsDraft': _saveAsDraft,
      };

      if (widget.existing == null) {
        await repo.create(payload);
      } else {
        await repo.update(widget.existing!.id, payload);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Amonestacion registrada correctamente.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _detailsCtrl.dispose();
    _incidentTimeCtrl.dispose();
    _incidentPlaceCtrl.dispose();
    _issuerNameCtrl.dispose();
    _issuerRoleCtrl.dispose();
    _internalNotesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(canAccessAmonestacionesProvider);
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nueva amonestacion')),
        body: const Center(
          child: Text('Acceso no permitido para este usuario'),
        ),
      );
    }

    final selected = _selectedEmployee;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: Text(
          widget.existing == null
              ? 'Nueva amonestacion'
              : 'Editar amonestacion',
        ),
        backgroundColor: const Color(0xFF1a1a2e),
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _CardSection(
              title: 'Empleado',
              children: [
                DropdownButtonFormField<UserModel>(
                  value: selected,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Buscar/seleccionar empleado',
                  ),
                  items: _employees
                      .map(
                        (u) => DropdownMenuItem<UserModel>(
                          value: u,
                          child: Text(
                            u.nombreCompleto,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _selectedEmployee = v),
                  validator: (v) => v == null ? 'Empleado requerido' : null,
                ),
                const SizedBox(height: 10),
                _InfoRow(label: 'Nombre', value: selected?.nombreCompleto),
                _InfoRow(label: 'Cedula', value: selected?.cedula),
                _InfoRow(label: 'Cargo', value: selected?.workContractJobTitle),
                _InfoRow(
                  label: 'Departamento/Area',
                  value: selected?.workContractWorkLocation,
                ),
                _InfoRow(label: 'Telefono', value: selected?.telefono),
              ],
            ),
            const SizedBox(height: 12),
            _CardSection(
              title: 'Datos de la amonestacion',
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _DateInput(
                        label: 'Fecha amonestacion',
                        date: _warningDate,
                        onTap: () => _pickDate(warningDate: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _DateInput(
                        label: 'Fecha del hecho',
                        date: _incidentDate,
                        onTap: () => _pickDate(warningDate: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _warningType,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de amonestacion',
                  ),
                  items: WarningLabels.warningType.entries
                      .map(
                        (e) => DropdownMenuItem<String>(
                          value: e.key,
                          child: Text(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _warningType = v ?? _warningType),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Motivo o causa',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Motivo requerido'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _detailsCtrl,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Detalle de los hechos',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty)
                      return 'Detalle requerido';
                    if (v.trim().length < 10)
                      return 'Especifica un detalle mas claro';
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _incidentTimeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Hora aproximada (opcional)',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _incidentPlaceCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Lugar o area (opcional)',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _issuerNameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Encargado que emite',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Encargado requerido'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _issuerRoleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Cargo del encargado',
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _internalNotesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Observaciones internas (opcional)',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  value: _saveAsDraft,
                  onChanged: (v) => setState(() => _saveAsDraft = v),
                  title: const Text('Guardar como borrador'),
                  subtitle: const Text(
                    'Si no se marca, se guarda como emitida',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1a1a2e),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Guardar amonestacion'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _CardSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String? value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final v = (value ?? '').trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
          Expanded(
            child: Text(
              v.isEmpty ? 'No registrado' : v,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateInput extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;
  const _DateInput({
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = WarningLabels.fmt(date);
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(text),
      ),
    );
  }
}

extension on Iterable<UserModel> {
  UserModel? get firstOrNull => isEmpty ? null : first;
}
