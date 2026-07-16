import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../../core/company/company_settings_repository.dart';
import '../../../core/models/user_model.dart';
import '../../../core/widgets/custom_app_bar.dart';
import '../../../modules/nomina/data/nomina_repository.dart';
import '../../../modules/nomina/nomina_models.dart';
import '../data/users_repository.dart';
import 'work_contract_pdf_service.dart';

class WorkContractPreviewScreen extends ConsumerStatefulWidget {
  final UserModel employee;

  const WorkContractPreviewScreen({super.key, required this.employee});

  @override
  ConsumerState<WorkContractPreviewScreen> createState() =>
      _WorkContractPreviewScreenState();
}

class _WorkContractPreviewScreenState
    extends ConsumerState<WorkContractPreviewScreen> {
  late UserModel _employee;
  late Future<_ContractPreviewData> _pdfFuture;
  bool _saving = false;
  bool _aiEditing = false;

  @override
  void initState() {
    super.initState();
    _employee = widget.employee;
    _pdfFuture = _buildPdf(_employee);
  }

  Future<_ContractBuildContext> _buildContractContext(
    UserModel employee,
  ) async {
    final company = await ref
        .read(companySettingsRepositoryProvider)
        .getSettings();
    final payrollSnapshot = await _resolvePayrollSnapshot(employee);
    final fields = resolveWorkContractFields(
      employee: employee,
      company: company,
      salario: payrollSnapshot.salaryFormatted,
      moneda: 'DOP',
      periodicidadPago: payrollSnapshot.paymentFrequency,
      metodoPago: payrollSnapshot.paymentMethod,
      puesto: payrollSnapshot.position,
      fechaInicio: employee.workContractStartDate ?? employee.fechaIngreso,
    );
    final clauses = buildWorkContractClauses(
      employee: employee,
      company: company,
      salario: payrollSnapshot.salaryFormatted,
      moneda: 'DOP',
      periodicidadPago: payrollSnapshot.paymentFrequency,
      metodoPago: payrollSnapshot.paymentMethod,
      puesto: payrollSnapshot.position,
      fechaInicio: employee.workContractStartDate ?? employee.fechaIngreso,
    );

    return _ContractBuildContext(
      company: company,
      payrollSnapshot: payrollSnapshot,
      fields: fields,
      clauses: clauses,
    );
  }

  Future<_ContractPreviewData> _buildPdf(UserModel employee) async {
    final contractContext = await _buildContractContext(employee);

    final bytes = await buildWorkContractPdf(
      employee: employee,
      company: contractContext.company,
      salario: contractContext.payrollSnapshot.salaryFormatted,
      moneda: 'DOP',
      periodicidadPago: contractContext.payrollSnapshot.paymentFrequency,
      metodoPago: contractContext.payrollSnapshot.paymentMethod,
      puesto: contractContext.payrollSnapshot.position,
      fechaInicio: employee.workContractStartDate ?? employee.fechaIngreso,
    );

    final safeName = employee.nombreCompleto.trim().isEmpty
        ? 'empleado'
        : employee.nombreCompleto.trim().replaceAll(RegExp(r'\s+'), '_');
    final fileName =
        'contrato_${safeName}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';

    return _ContractPreviewData(
      bytes: bytes,
      fileName: fileName,
      contractContext: contractContext,
    );
  }

  Future<_PayrollContractSnapshot> _resolvePayrollSnapshot(
    UserModel user,
  ) async {
    final nominaRepo = ref.read(nominaRepositoryProvider);
    PayrollEmployee? payrollEmployee;
    double? baseSalary;
    String? paymentFrequency;

    try {
      final employees = await nominaRepo.listEmployees(activeOnly: false);
      payrollEmployee = _matchPayrollEmployee(user, employees);

      if (payrollEmployee != null) {
        final periods = await nominaRepo.listPeriods();
        periods.sort((a, b) => b.endDate.compareTo(a.endDate));

        for (final period in periods) {
          final config = await nominaRepo.getEmployeeConfig(
            period.id,
            payrollEmployee.id,
          );
          if (config == null || config.baseSalary <= 0) continue;
          baseSalary = config.baseSalary;
          paymentFrequency = _inferPaymentFrequency(
            period.startDate,
            period.endDate,
          );
          break;
        }
      }
    } catch (_) {
      // Si nómina falla, el contrato puede generarse con valores manuales.
    }

    final currency = NumberFormat.currency(
      locale: 'en_US',
      symbol: 'RD\$ ',
      decimalDigits: 2,
    );
    final payrollPosition = payrollEmployee?.puesto?.trim();

    return _PayrollContractSnapshot(
      salaryFormatted: (user.workContractSalary ?? '').trim().isNotEmpty
          ? user.workContractSalary!.trim()
          : baseSalary != null && baseSalary > 0
          ? currency.format(baseSalary)
          : null,
      paymentFrequency:
          (user.workContractPaymentFrequency ?? '').trim().isNotEmpty
          ? user.workContractPaymentFrequency!.trim()
          : paymentFrequency ?? 'Quincenal',
      paymentMethod: (user.workContractPaymentMethod ?? '').trim().isNotEmpty
          ? user.workContractPaymentMethod!.trim()
          : _resolvePaymentMethod(user),
      position: (user.workContractJobTitle ?? '').trim().isNotEmpty
          ? user.workContractJobTitle!.trim()
          : (payrollPosition == null || payrollPosition.isEmpty)
          ? null
          : payrollPosition,
    );
  }

  PayrollEmployee? _matchPayrollEmployee(
    UserModel user,
    List<PayrollEmployee> employees,
  ) {
    final exactId = employees.where((employee) => employee.id == user.id);
    if (exactId.isNotEmpty) return exactId.first;

    final normalizedName = user.nombreCompleto.trim().toLowerCase();
    final normalizedPhone = user.telefono.trim();

    for (final employee in employees) {
      final sameName = employee.nombre.trim().toLowerCase() == normalizedName;
      if (!sameName) continue;
      if (normalizedPhone.isEmpty) return employee;
      if ((employee.telefono ?? '').trim() == normalizedPhone) {
        return employee;
      }
    }

    return null;
  }

  String _inferPaymentFrequency(DateTime start, DateTime end) {
    final days = end.difference(start).inDays.abs() + 1;
    if (days <= 8) return 'Semanal';
    if (days <= 17) return 'Quincenal';
    if (days <= 35) return 'Mensual';
    return 'Periodicidad variable';
  }

  String _resolvePaymentMethod(UserModel user) {
    final account = (user.cuentaNominaPreferencial ?? '').trim();
    if (account.isEmpty) return 'Transferencia bancaria';
    return 'Transferencia bancaria a cuenta $account';
  }

  Future<void> _openEditDialog() async {
    final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
    final jobTitleCtrl = TextEditingController(
      text: _employee.workContractJobTitle ?? '',
    );
    final salaryCtrl = TextEditingController(
      text: _employee.workContractSalary ?? '',
    );
    final frequencyCtrl = TextEditingController(
      text: _employee.workContractPaymentFrequency ?? '',
    );
    final paymentMethodCtrl = TextEditingController(
      text: _employee.workContractPaymentMethod ?? '',
    );
    final workScheduleCtrl = TextEditingController(
      text: _employee.workContractWorkSchedule ?? '',
    );
    final workLocationCtrl = TextEditingController(
      text: _employee.workContractWorkLocation ?? '',
    );
    final customClausesCtrl = TextEditingController(
      text: _employee.workContractCustomClauses ?? '',
    );
    DateTime? workContractStartDate = _employee.workContractStartDate;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Editar contrato'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: jobTitleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Cargo contractual',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: salaryCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Salario contractual',
                      hintText: 'Ej: RD\$ 25,000.00',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: frequencyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Periodicidad de pago',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: paymentMethodCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Método de pago',
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fecha de inicio contractual'),
                    subtitle: Text(
                      workContractStartDate == null
                          ? 'Usar fecha de ingreso'
                          : DateFormat(
                              'dd/MM/yyyy',
                            ).format(workContractStartDate!),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (workContractStartDate != null)
                          IconButton(
                            tooltip: 'Quitar fecha',
                            onPressed: () => setDialogState(
                              () => workContractStartDate = null,
                            ),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        const Icon(Icons.calendar_today_outlined),
                      ],
                    ),
                    onTap: () async {
                      final now = DateTime.now();
                      final picked = await showDatePicker(
                        context: context,
                        initialDate:
                            workContractStartDate ??
                            _employee.fechaIngreso ??
                            now,
                        firstDate: DateTime(1990),
                        lastDate: DateTime(now.year + 5),
                      );
                      if (picked != null) {
                        setDialogState(() => workContractStartDate = picked);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: workScheduleCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Horario contractual',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: workLocationCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Lugar de trabajo contractual',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: customClausesCtrl,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Cláusulas especiales',
                    ),
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<_ContractBuildContext>(
                    future: _buildContractContext(_employee),
                    builder: (context, snapshot) {
                      final clauses =
                          snapshot.data?.clauses ??
                          const <WorkContractClause>[];
                      return ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        title: Text('Cláusulas actuales (${clauses.length})'),
                        subtitle: const Text(
                          'Vista previa de las cláusulas que usa el contrato',
                        ),
                        children: clauses
                            .map(
                              (clause) => ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('${clause.label} ${clause.title}'),
                                subtitle: Text(clause.text),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: _saving
                  ? null
                  : () async {
                      final navigator = Navigator.of(context);
                      setState(() => _saving = true);
                      try {
                        final payload = <String, dynamic>{
                          'workContractJobTitle': jobTitleCtrl.text.trim(),
                          'workContractSalary': salaryCtrl.text.trim(),
                          'workContractPaymentFrequency': frequencyCtrl.text
                              .trim(),
                          'workContractPaymentMethod': paymentMethodCtrl.text
                              .trim(),
                          'workContractWorkSchedule': workScheduleCtrl.text
                              .trim(),
                          'workContractWorkLocation': workLocationCtrl.text
                              .trim(),
                          'workContractCustomClauses': customClausesCtrl.text
                              .trim(),
                          'workContractStartDate': workContractStartDate
                              ?.toIso8601String(),
                        };

                        final updated = await ref
                            .read(usersRepositoryProvider)
                            .updateUser(_employee.id, payload);

                        if (!mounted) return;
                        setState(() {
                          _employee = updated;
                          _pdfFuture = _buildPdf(updated);
                        });
                        navigator.pop();
                        scaffoldMessenger?.showSnackBar(
                          const SnackBar(
                            content: Text('Contrato actualizado y regenerado'),
                          ),
                        );
                      } catch (e) {
                        if (!mounted) return;
                        scaffoldMessenger?.showSnackBar(
                          SnackBar(content: Text('No se pudo guardar: $e')),
                        );
                      } finally {
                        if (mounted) setState(() => _saving = false);
                      }
                    },
              child: Text(_saving ? 'Guardando...' : 'Guardar cambios'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Contrato · ${_employee.nombreCompleto}',
        showLogo: false,
        showDepartmentLabel: false,
        actions: [
          IconButton(
            tooltip: 'Editar con IA',
            onPressed: _saving || _aiEditing ? null : _openAiEditDialog,
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          IconButton(
            tooltip: 'Editar contrato',
            onPressed: _saving || _aiEditing ? null : _openEditDialog,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Regenerar PDF',
            onPressed: () => setState(() => _pdfFuture = _buildPdf(_employee)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<_ContractPreviewData>(
        future: _pdfFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Text(
                'No se pudo generar el contrato.\n${snapshot.error ?? ''}',
                textAlign: TextAlign.center,
              ),
            );
          }

          final data = snapshot.data!;
          return PdfPreview(
            pdfFileName: data.fileName,
            canChangeOrientation: false,
            canChangePageFormat: false,
            build: (format) async => data.bytes,
          );
        },
      ),
    );
  }

  Future<void> _openAiEditDialog() async {
    final previewContext = await _buildContractContext(_employee);
    if (!mounted) return;

    final instructionCtrl = TextEditingController();
    final scaffoldMessenger = ScaffoldMessenger.maybeOf(context);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        bool submitting = false;
        String? errorText;

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Editar contrato con IA'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Describe en un solo párrafo qué quieres cambiar y la IA ajustará los campos y cláusulas correspondientes.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: instructionCtrl,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Instrucción',
                        hintText:
                            'Ej: cambia la jornada a lunes a viernes de 8am a 5pm, agrega confidencialidad reforzada y deja el pago quincenal por transferencia.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: Text(
                        'Ver cláusulas actuales (${previewContext.clauses.length})',
                      ),
                      subtitle: const Text(
                        'La IA trabajará sobre estas cláusulas y campos actuales',
                      ),
                      children: [
                        ...previewContext.clauses.map(
                          (clause) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('${clause.label} ${clause.title}'),
                            subtitle: Text(clause.text),
                          ),
                        ),
                        if (previewContext.fields.additionalClauses.isNotEmpty)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'DECIMO SEGUNDO: Cláusulas Especiales',
                            ),
                            subtitle: Text(
                              previewContext.fields.additionalClauses,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: submitting
                    ? null
                    : () async {
                        final instruction = instructionCtrl.text.trim();
                        if (instruction.length < 10) {
                          setDialogState(
                            () => errorText =
                                'Describe con más detalle el cambio que deseas.',
                          );
                          return;
                        }

                        setDialogState(() {
                          submitting = true;
                          errorText = null;
                        });
                        setState(() => _aiEditing = true);

                        try {
                          final result = await ref
                              .read(usersRepositoryProvider)
                              .applyAiWorkContractEdit(
                                userId: _employee.id,
                                instruction: instruction,
                                currentFields: previewContext.fields
                                    .toApiPayload(_employee),
                                currentClauses: previewContext.clauses
                                    .map(
                                      (clause) => {
                                        'key': clause.key,
                                        'label': clause.label,
                                        'title': clause.title,
                                        'text': clause.text,
                                      },
                                    )
                                    .toList(growable: false),
                              );

                          if (!mounted) return;
                          setState(() {
                            _employee = result.user;
                            _pdfFuture = _buildPdf(result.user);
                          });
                          if (!dialogContext.mounted) return;
                          Navigator.of(dialogContext).pop();
                          scaffoldMessenger?.showSnackBar(
                            SnackBar(
                              content: Text(
                                result.summary.trim().isEmpty
                                    ? 'Contrato actualizado con IA'
                                    : result.summary,
                              ),
                            ),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          setDialogState(
                            () => errorText = 'No se pudo aplicar la IA: $e',
                          );
                        } finally {
                          if (mounted) setState(() => _aiEditing = false);
                          if (dialogContext.mounted) {
                            setDialogState(() => submitting = false);
                          }
                        }
                      },
                child: Text(submitting ? 'Aplicando...' : 'Aplicar con IA'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ContractPreviewData {
  final Uint8List bytes;
  final String fileName;
  final _ContractBuildContext contractContext;

  const _ContractPreviewData({
    required this.bytes,
    required this.fileName,
    required this.contractContext,
  });
}

class _ContractBuildContext {
  final dynamic company;
  final _PayrollContractSnapshot payrollSnapshot;
  final WorkContractResolvedFields fields;
  final List<WorkContractClause> clauses;

  const _ContractBuildContext({
    required this.company,
    required this.payrollSnapshot,
    required this.fields,
    required this.clauses,
  });
}

class _PayrollContractSnapshot {
  final String? salaryFormatted;
  final String paymentFrequency;
  final String paymentMethod;
  final String? position;

  const _PayrollContractSnapshot({
    required this.salaryFormatted,
    required this.paymentFrequency,
    required this.paymentMethod,
    required this.position,
  });
}
