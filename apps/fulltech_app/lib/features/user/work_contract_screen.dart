import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:signature/signature.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/models/user_model.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../modules/nomina/data/nomina_repository.dart';
import '../../modules/nomina/nomina_models.dart';
import 'data/users_repository.dart';
import 'utils/work_contract_pdf_service.dart';

class WorkContractScreen extends ConsumerStatefulWidget {
  const WorkContractScreen({super.key});

  @override
  ConsumerState<WorkContractScreen> createState() => _WorkContractScreenState();
}

class _WorkContractScreenState extends ConsumerState<WorkContractScreen> {
  static const String _workContractVersion = '2026-03-07';

  late final SignatureController _signatureCtrl;

  late final Future<_ContractPdfState> _pdfFuture;

  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _signatureCtrl = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
    _pdfFuture = _buildPdf();
  }

  @override
  void dispose() {
    _signatureCtrl.dispose();
    super.dispose();
  }

  Future<_ContractPdfState> _buildPdf() async {
    final auth = ref.read(authStateProvider);
    final authUser = auth.user;
    if (authUser == null) {
      throw StateError('Usuario no autenticado');
    }

    final usersRepo = ref.read(usersRepositoryProvider);
    final settingsRepo = ref.read(companySettingsRepositoryProvider);
    final nominaRepo = ref.read(nominaRepositoryProvider);

    UserModel user;
    try {
      user = await usersRepo.fetchMe();
    } catch (_) {
      user = authUser;
    }

    final company = await settingsRepo.getSettings();

    final payrollSnapshot = await _resolvePayrollSnapshot(user, nominaRepo);
    final contractStartDate = user.workContractStartDate ?? user.fechaIngreso;

    final bytes = await buildWorkContractPdf(
      employee: user,
      company: company,
      salario: payrollSnapshot.salaryFormatted,
      moneda: 'DOP',
      periodicidadPago: payrollSnapshot.paymentFrequency,
      metodoPago: payrollSnapshot.paymentMethod,
      puesto: payrollSnapshot.position,
      fechaInicio: contractStartDate,
    );

    final safeName = user.nombreCompleto.trim().isEmpty
        ? 'empleado'
        : user.nombreCompleto.trim().replaceAll(RegExp(r'\s+'), '_');
    final dateFmt = DateFormat('yyyyMMdd');
    final fileName =
        'contrato_${safeName}_${dateFmt.format(DateTime.now())}.pdf';

    return _ContractPdfState(bytes: bytes, fileName: fileName, employee: user);
  }

  Future<_PayrollContractSnapshot> _resolvePayrollSnapshot(
    UserModel user,
    NominaRepository nominaRepo,
  ) async {
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
          if (config == null || config.baseSalary <= 0) {
            continue;
          }
          baseSalary = config.baseSalary;
          paymentFrequency = _inferPaymentFrequency(
            period.startDate,
            period.endDate,
          );
          break;
        }
      }
    } catch (_) {
      // Si no se puede leer nómina activa, usamos el historial como respaldo.
    }

    try {
      if (baseSalary == null || baseSalary <= 0) {
        final history = await nominaRepo.listMyPayrollHistory();
        final latest = history.isEmpty
            ? null
            : history.reduce(
                (a, b) => a.periodEnd.isAfter(b.periodEnd) ? a : b,
              );
        if (latest != null && latest.baseSalary > 0) {
          baseSalary = latest.baseSalary;
          paymentFrequency ??= _inferPaymentFrequency(
            latest.periodStart,
            latest.periodEnd,
          );
        }
      }
    } catch (_) {
      // Si el historial falla también, el contrato se genera con placeholders.
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

      if (normalizedPhone.isEmpty) {
        return employee;
      }

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
    if (account.isEmpty) {
      return 'Transferencia bancaria';
    }
    return 'Transferencia bancaria a cuenta $account';
  }

  Future<void> _signNow(UserModel user) async {
    if (_submitting) return;

    if (_signatureCtrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes firmar antes de continuar')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final png = await _signatureCtrl.toPngBytes();
      if (png == null || png.isEmpty) {
        throw StateError('No se pudo exportar la firma');
      }

      final repo = ref.read(usersRepositoryProvider);
      final fileName =
          'firma_contrato_${user.id}_${DateTime.now().millisecondsSinceEpoch}.png';
      final signatureUrl = await repo.uploadUserDocument(
        bytes: png,
        fileName: fileName,
      );

      final updated = await repo.signWorkContract(
        version: _workContractVersion,
        signatureUrl: signatureUrl,
      );

      ref.read(authStateProvider.notifier).setUser(updated);
      _signatureCtrl.clear();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contrato firmado correctamente')),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo firmar: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final user = auth.user;

    final signedAt = user?.workContractSignedAt;
    final isSigned = signedAt != null;

    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Contrato',
        showLogo: false,
        showDepartmentLabel: false,
      ),
      body: user == null
          ? const Center(child: Text('No hay usuario autenticado'))
          : Column(
              children: [
                Expanded(
                  child: FutureBuilder<_ContractPdfState>(
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
                ),
                Material(
                  elevation: 6,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.edit_document, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  isSigned
                                      ? 'Firmado el ${DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(signedAt)}'
                                      : 'Firma obligatoria',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (user.workContractVersion != null &&
                                  user.workContractVersion!.trim().isNotEmpty)
                                Text(
                                  'v ${user.workContractVersion}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outline,
                                      ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          if (isSigned)
                            const Text(
                              'Ya has firmado este contrato.',
                              textAlign: TextAlign.left,
                            )
                          else ...[
                            Container(
                              height: 140,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Signature(
                                controller: _signatureCtrl,
                                backgroundColor: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: _submitting
                                        ? null
                                        : () => _signatureCtrl.clear(),
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Borrar'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: _submitting
                                        ? null
                                        : () => _signNow(user),
                                    icon: _submitting
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.check),
                                    label: Text(
                                      _submitting ? 'Firmando...' : 'Firmar',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ContractPdfState {
  final Uint8List bytes;
  final String fileName;
  final UserModel employee;

  _ContractPdfState({
    required this.bytes,
    required this.fileName,
    required this.employee,
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
