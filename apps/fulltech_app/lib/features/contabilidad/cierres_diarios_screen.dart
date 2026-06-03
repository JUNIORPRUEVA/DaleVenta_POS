import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/api/env.dart';
import '../../core/utils/pdf_file_actions.dart';
import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/errors/api_exception.dart';
import '../../core/models/close_model.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'application/cierres_diarios_controller.dart';
import 'data/contabilidad_repository.dart';
import 'models/close_financial_summary_model.dart';
import 'widgets/app_card.dart';
import 'widgets/section_title.dart';
import 'deposit_bank_catalog.dart';

enum _FinancialSummaryPreset { hoy, ayer, quincena, mes, personalizado }

final NumberFormat _accountingAmountFormatter = NumberFormat(
  '#,##0.00',
  'en_US',
);
final NumberFormat _accountingCurrencyFormatter = NumberFormat.currency(
  locale: 'en_US',
  symbol: 'RD\$ ',
  decimalDigits: 2,
);

String _formatAccountingAmount(double value) {
  return _accountingAmountFormatter.format(value);
}

String _formatAccountingMoney(double value) {
  return _accountingCurrencyFormatter.format(value);
}

double _parseAccountingMoney(String? raw) {
  if (raw == null) return 0;
  final cleaned = raw.replaceAll(RegExp(r'[^0-9,\.\-]'), '').trim();
  if (cleaned.isEmpty || cleaned == '-') return 0;

  final sign = cleaned.startsWith('-') ? '-' : '';
  final unsigned = cleaned.replaceAll('-', '');
  final lastDot = unsigned.lastIndexOf('.');
  final lastComma = unsigned.lastIndexOf(',');

  if (lastDot >= 0 && lastComma >= 0) {
    final decimalIndex = lastDot > lastComma ? lastDot : lastComma;
    final integer = unsigned
        .substring(0, decimalIndex)
        .replaceAll(RegExp(r'[^0-9]'), '');
    final decimal = unsigned
        .substring(decimalIndex + 1)
        .replaceAll(RegExp(r'[^0-9]'), '');
    return double.tryParse(
          '$sign${integer.isEmpty ? '0' : integer}.$decimal',
        ) ??
        0;
  }

  if (lastComma >= 0) {
    final decimalDigits = unsigned.length - lastComma - 1;
    if (decimalDigits > 0 && decimalDigits <= 2) {
      final integer = unsigned
          .substring(0, lastComma)
          .replaceAll(RegExp(r'[^0-9]'), '');
      final decimal = unsigned
          .substring(lastComma + 1)
          .replaceAll(RegExp(r'[^0-9]'), '');
      return double.tryParse(
            '$sign${integer.isEmpty ? '0' : integer}.$decimal',
          ) ??
          0;
    }
    return double.tryParse('$sign${unsigned.replaceAll(',', '')}') ?? 0;
  }

  return double.tryParse('$sign${unsigned.replaceAll(',', '')}') ?? 0;
}

void _prepareAccountingMoneyEditing(TextEditingController controller) {
  final text = controller.text;
  if (_parseAccountingMoney(text) == 0) {
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: text.length,
    );
    return;
  }
  final decimalIndex = text.indexOf('.');
  controller.selection = TextSelection.collapsed(
    offset: decimalIndex >= 0 ? decimalIndex : text.length,
  );
}

class _AccountingMoneyInputFormatter extends TextInputFormatter {
  const _AccountingMoneyInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.trim().isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final decimalIndex = newValue.text.indexOf('.');
    final integerText = decimalIndex >= 0
        ? newValue.text.substring(0, decimalIndex)
        : newValue.text;
    final decimalText = decimalIndex >= 0
        ? newValue.text.substring(decimalIndex + 1)
        : '';
    final integerDigits = integerText.replaceAll(RegExp(r'[^0-9]'), '');
    final centsDigits = decimalText.replaceAll(RegExp(r'[^0-9]'), '');
    final whole =
        double.tryParse(integerDigits.isEmpty ? '0' : integerDigits) ?? 0;
    final cents = centsDigits.isEmpty
        ? 0.0
        : (double.tryParse(centsDigits.padRight(2, '0').substring(0, 2)) ?? 0) /
              100;
    final formatted = _formatAccountingAmount(whole + cents);
    final cursorOffset = formatted.indexOf('.');

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: cursorOffset >= 0 ? cursorOffset : formatted.length,
      ),
    );
  }
}

DepositBankOption? _resolveDepositBank(String? bankName) {
  final normalized = (bankName ?? '').trim().toLowerCase();
  for (final bank in depositBankCatalog) {
    if (bank.id == normalized || bank.label.toLowerCase() == normalized) {
      return bank;
    }
  }
  return null;
}

String _resolveContabilidadAssetUrl(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return value;
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return value;
  }

  final base = Env.apiBaseUrl.replaceAll(RegExp(r'/+$'), '');
  if (value.startsWith('/public/contabilidad/object?')) {
    return '$base$value';
  }
  if (value.startsWith('public/contabilidad/object?')) {
    return '$base/$value';
  }

  final encodedKey = Uri.encodeQueryComponent(value.replaceAll('\\', '/'));
  return '$base/public/contabilidad/object?key=$encodedKey';
}

bool _isCloseVoucherImage(CloseTransferVoucherModel voucher) {
  final mime = voucher.mimeType.toLowerCase();
  final name = voucher.fileName.toLowerCase();
  final url = voucher.fileUrl.toLowerCase();
  final byMime = mime.startsWith('image/');
  final byName =
      name.endsWith('.jpg') ||
      name.endsWith('.jpeg') ||
      name.endsWith('.png') ||
      name.endsWith('.webp');
  final byUrl =
      url.contains('.jpg') ||
      url.contains('.jpeg') ||
      url.contains('.png') ||
      url.contains('.webp');
  return byMime || byName || byUrl;
}

bool _isPickedCloseVoucherImage(PlatformFile file) {
  final extension = (file.extension ?? '').toLowerCase();
  final name = file.name.toLowerCase();
  return extension == 'jpg' ||
      extension == 'jpeg' ||
      extension == 'png' ||
      extension == 'webp' ||
      name.endsWith('.jpg') ||
      name.endsWith('.jpeg') ||
      name.endsWith('.png') ||
      name.endsWith('.webp');
}

String _closeVoucherPreviewKey(CloseTransferVoucherModel voucher) {
  final storageKey = voucher.storageKey.trim();
  if (storageKey.isNotEmpty) return storageKey;
  final fileUrl = voucher.fileUrl.trim();
  if (fileUrl.isNotEmpty) return fileUrl;
  return '${voucher.fileName}|${voucher.mimeType}';
}

class CierresDiariosScreen extends ConsumerStatefulWidget {
  const CierresDiariosScreen({super.key});

  @override
  ConsumerState<CierresDiariosScreen> createState() =>
      _CierresDiariosScreenState();
}

class _CierresDiariosScreenState extends ConsumerState<CierresDiariosScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cashCtrl = TextEditingController(text: _formatAccountingAmount(0));
  final _cardCtrl = TextEditingController(text: _formatAccountingAmount(0));
  final _otherIncomeCtrl = TextEditingController(
    text: _formatAccountingAmount(0),
  );
  final _expensesCtrl = TextEditingController(text: _formatAccountingAmount(0));
  final _cashDeliveredCtrl = TextEditingController(
    text: _formatAccountingAmount(0),
  );
  final _notesCtrl = TextEditingController();
  final _correctionReasonCtrl = TextEditingController();
  final _assistantFormScrollCtrl = ScrollController();

  CloseType _type = CloseType.tienda;
  DateTime _date = DateTime.now();
  String? _editingId;
  bool _isCorrection = false;
  String? _correctionOfCloseId;
  final List<_TransferDraft> _transferEntries = [];
  final List<_ExpenseDraft> _expenseEntries = [];
  final Map<String, Uint8List> _voucherPreviewBytes = {};
  CloseTransferVoucherModel? _posVoucher;
  bool _uploadingPosVoucher = false;
  ProviderSubscription<CierresDiariosState>? _cierresStateSubscription;
  String? _lastLoadedUserId;
  bool _assistantEmptyReloadRequested = false;
  int _assistantEmptyReloadAttempts = 0; // Limitar reintentos

  @override
  void initState() {
    super.initState();
    _cierresStateSubscription = ref.listenManual<CierresDiariosState>(
      cierresDiariosControllerProvider,
      (previous, next) {
        final prevId = previous?.editingClose?.id;
        final nextEdit = next.editingClose;
        if (nextEdit != null && nextEdit.id != prevId) {
          _applyEdit(nextEdit);
        }
        if (prevId != null && nextEdit == null) {
          _resetForm();
        }
      },
    );
  }

  @override
  void dispose() {
    _cierresStateSubscription?.close();
    _cashCtrl.dispose();
    for (final entry in _transferEntries) {
      entry.dispose();
    }
    for (final expense in _expenseEntries) {
      expense.dispose();
    }
    _cardCtrl.dispose();
    _otherIncomeCtrl.dispose();
    _expensesCtrl.dispose();
    _cashDeliveredCtrl.dispose();
    _notesCtrl.dispose();
    _correctionReasonCtrl.dispose();
    _assistantFormScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final user = auth.user;
    final role = parseAppRole(user?.role);
    final isAdmin = role.isAdmin;
    final isAssistant = role == AppRole.asistente;
    final state = ref.watch(cierresDiariosControllerProvider);
    final controller = ref.read(cierresDiariosControllerProvider.notifier);
    final canUseModule = isAdmin || isAssistant;
    final selectedType = state.typeFilter ?? CloseType.tienda;
    final currentUserId = user?.id.trim();

    if (currentUserId != _lastLoadedUserId) {
      _lastLoadedUserId = currentUserId;
      _assistantEmptyReloadRequested = false;
      _assistantEmptyReloadAttempts = 0; // Resetear contador de reintentos
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || (currentUserId ?? '').isEmpty) return;
        controller.refresh();
      });
    }

    // Solo reintentar UNA VEZ si la lista está vacía (máximo 1 intento)
    if (isAssistant &&
        !state.loading &&
        state.error == null &&
        state.closes.isEmpty &&
        !_assistantEmptyReloadRequested &&
        _assistantEmptyReloadAttempts < 1) {
      _assistantEmptyReloadRequested = true;
      _assistantEmptyReloadAttempts++;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        controller.refresh();
      });
    }

    if (state.closes.isNotEmpty && _assistantEmptyReloadRequested) {
      _assistantEmptyReloadRequested = false;
    }

    if (!isAdmin && state.editingClose != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        controller.cancelEditing();
        _resetForm();
      });
    }

    if (_type != selectedType && _editingId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _type = selectedType);
      });
    }

    if (isAdmin && canUseModule) {
      return _HistoryFullScreenPage(initialType: selectedType);
    }

    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Cierres diarios',
        showLogo: false,
        showDepartmentLabel: false,
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      floatingActionButton: null,
      body: !canUseModule
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Este módulo está disponible solo para ADMIN y ASISTENTE.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            )
          : isAssistant
          ? RefreshIndicator(
              onRefresh: controller.refresh,
              child: _buildAssistantBody(context, state, controller, user?.id),
            )
          : RefreshIndicator(
              onRefresh: controller.refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: _buildFormCard(context, state, controller),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (state.loading) const LinearProgressIndicator(),
                  if (state.error != null) ...[
                    const SizedBox(height: 8),
                    _ErrorBox(message: state.error!),
                  ],
                  const SizedBox(height: 10),
                ],
              ),
            ),
    );
  }

  Widget _buildAssistantBody(
    BuildContext context,
    CierresDiariosState state,
    CierresDiariosController controller,
    String? currentUserId,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 980;
        final formPanel = Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: SizedBox(
              width: desktop ? double.infinity : null,
              height: desktop ? constraints.maxHeight - 32 : null,
              child: _buildFormCard(
                context,
                state,
                controller,
                assistantMode: true,
                scrollInsideCard: desktop,
                currentUserId: currentUserId,
              ),
            ),
          ),
        );
        final history = _AssistantRawHistoryList(
          closes: state.closes,
          fromDate: state.from,
          toDate: state.to,
        );
        final statusWidgets = <Widget>[
          if (state.loading) const LinearProgressIndicator(),
          if (state.error != null) ...[
            const SizedBox(height: 8),
            _ErrorBox(message: state.error!),
          ],
        ];

        if (!desktop) {
          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              ...statusWidgets,
              formPanel,
              const SizedBox(height: 12),
              history,
            ],
          );
        }

        return SizedBox(
          height: constraints.maxHeight,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                ...statusWidgets,
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: constraints.maxWidth >= 1280 ? 380 : 330,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: _AssistantHistoryShell(child: history),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(flex: 7, child: formPanel),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFormCard(
    BuildContext context,
    CierresDiariosState state,
    CierresDiariosController controller, {
    bool assistantMode = false,
    bool scrollInsideCard = false,
    String? currentUserId,
  }) {
    final editing = state.editingClose != null;
    final transfer = _transferEntries.fold<double>(
      0,
      (sum, entry) => sum + _toMoney(entry.amountCtrl.text),
    );
    final money = _accountingCurrencyFormatter;
    final cash = _toMoney(_cashCtrl.text);
    final card = _toMoney(_cardCtrl.text);
    final otherIncome = _toMoney(_otherIncomeCtrl.text);
    final expenses = _expenseEntries.isEmpty
        ? _toMoney(_expensesCtrl.text)
        : _expenseEntries.fold<double>(
            0,
            (sum, expense) => sum + _toMoney(expense.amountCtrl.text),
          );
    final delivered = _toMoney(_cashDeliveredCtrl.text);
    final totalIncome = cash + transfer + card + otherIncome;
    // Si el efectivo declarado no alcanza para cubrir los gastos,
    // se toma de las otras fuentes (transferencias, tarjeta, otros ingresos)
    // para cubrir la diferencia. El netTotal nunca debe ser negativo
    // si hay suficientes ingresos totales.
    final netTotal = totalIncome >= expenses ? totalIncome - expenses : 0.0;
    final difference = cash - delivered;
    final locked =
        state.editingClose?.isApproved == true ||
        state.editingClose?.isRejected == true;

    final form = Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (assistantMode) ...[
            _AssistantDailyPairBanner(
              date: _date,
              closes: state.closes,
              editingId: _editingId,
              isCorrection: _isCorrection,
            ),
            const SizedBox(height: 12),
          ],
          SectionTitle(
            title: editing
                ? 'Editar cierre ${_type.label}'
                : assistantMode
                ? 'Registrar cierre'
                : 'Nuevo cierre',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _UnitChipButton(
                  label: 'Tecnología',
                  selected: _type == CloseType.tienda,
                  onPressed: editing
                      ? null
                      : () =>
                            _trySelectType(CloseType.tienda, state, controller),
                ),
                _UnitChipButton(
                  label: 'PhytoEmagry',
                  selected: _type == CloseType.phytoemagry,
                  onPressed: editing
                      ? null
                      : () => _trySelectType(
                          CloseType.phytoemagry,
                          state,
                          controller,
                        ),
                ),
                if (editing)
                  TextButton(
                    onPressed: () {
                      controller.cancelEditing();
                      _resetForm();
                    },
                    child: const Text('Cancelar edición'),
                  ),
                if (assistantMode) ...[
                  const SizedBox(width: 4),
                  SizedBox(
                    height: 34,
                    child: FilledButton.icon(
                      onPressed: state.saving || locked
                          ? null
                          : () => _submitCloseFromForm(
                              state: state,
                              controller: controller,
                              assistantMode: assistantMode,
                              editing: editing,
                            ),
                      icon: state.saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded, size: 16),
                      label: const Text('Enviar cierre'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (assistantMode)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _buildDatePickerField(state, editing)),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: _buildAssistantCorrectionToggle()),
                const SizedBox(width: 8),
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _notesCtrl,
                    maxLines: 1,
                    decoration: const InputDecoration(
                      labelText: 'Comentario',
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            )
          else
            _buildDatePickerField(state, editing),
          if (locked) ...[
            _StatusNotice(close: state.editingClose!),
            const SizedBox(height: 12),
          ],
          if (assistantMode && _isCorrection) ...[
            const SizedBox(height: 8),
            _buildAssistantCorrectionDetails(state.closes, currentUserId),
          ],
          const SizedBox(height: 10),
          if (assistantMode)
            Row(
              children: [
                Expanded(
                  child: _moneyField(
                    _cashCtrl,
                    'Efectivo declarado',
                    required: true,
                    mustBeGreaterThanZero: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(child: _moneyField(_cardCtrl, 'Pagos con tarjetas')),
              ],
            )
          else
            _moneyField(
              _cashCtrl,
              'Efectivo declarado',
              required: true,
              mustBeGreaterThanZero: true,
            ),
          const SizedBox(height: 10),
          _buildTransferSection(money, assistantMode: assistantMode),
          if (!assistantMode) ...[
            const SizedBox(height: 10),
            _moneyField(_cardCtrl, 'Pago con tarjeta'),
          ],
          const SizedBox(height: 10),
          _moneyField(_otherIncomeCtrl, 'Otros ingresos'),
          const SizedBox(height: 10),
          _buildExpensesSection(money, assistantMode: assistantMode),
          const SizedBox(height: 10),
          if (_type != CloseType.phytoemagry)
            _moneyField(
              _cashDeliveredCtrl,
              'Fondo de caja (efectivo inicial)',
              required: true,
            ),
          if (!assistantMode) ...[
            const SizedBox(height: 10),
            TextFormField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notas',
                alignLabelWithHint: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          const SizedBox(height: 12),
          _buildPosVoucherSection(),
          if (!assistantMode) ...[
            const SizedBox(height: 12),
            _CloseSummaryBlock(
              totalIncome: totalIncome,
              netTotal: netTotal,
              cashDeclared: cash,
              cashDelivered: delivered,
              difference: difference,
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: state.saving || locked
                    ? null
                    : () => _submitCloseFromForm(
                        state: state,
                        controller: controller,
                        assistantMode: assistantMode,
                        editing: editing,
                      ),
                icon: state.saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(editing ? Icons.save_outlined : Icons.add_circle),
                label: const Text('Confirmar y enviar cierre'),
              ),
            ),
          ],
        ],
      ),
    );

    final formContent = scrollInsideCard
        ? Scrollbar(
            controller: _assistantFormScrollCtrl,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _assistantFormScrollCtrl,
              primary: false,
              padding: const EdgeInsets.only(right: 10),
              child: form,
            ),
          )
        : form;

    if (assistantMode) {
      final theme = Theme.of(context);
      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.72),
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.045),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: formContent,
        ),
      );
    }

    return AppCard(padding: const EdgeInsets.all(16), child: formContent);
  }

  Future<void> _submitCloseFromForm({
    required CierresDiariosState state,
    required CierresDiariosController controller,
    required bool assistantMode,
    required bool editing,
  }) async {
    if (!_formKey.currentState!.validate()) return;
    if (_posVoucher == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El boucher del cierre es obligatorio para guardar o enviar el cierre.',
          ),
        ),
      );
      return;
    }

    for (final entry in _transferEntries) {
      if (entry.bankCtrl.text.trim().isEmpty ||
          _toMoney(entry.amountCtrl.text) <= 0 ||
          entry.vouchers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cada transferencia requiere banco, monto mayor a cero y al menos un voucher.',
            ),
          ),
        );
        return;
      }
    }

    if (assistantMode && _isCorrection) {
      if ((_correctionOfCloseId ?? '').trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selecciona el cierre anterior que vas a corregir.'),
          ),
        );
        return;
      }
      if (_correctionReasonCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('El motivo de la corrección es obligatorio.'),
          ),
        );
        return;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar cierre diario'),
        content: Text(
          _isCorrection
              ? '¿Seguro que deseas registrar este cierre de corrección? El cierre anterior quedará intacto.'
              : '¿Seguro que deseas enviar este cierre diario?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!editing &&
        !_isCorrection &&
        _hasActiveCloseFor(_date, _type, state, excludingId: _editingId)) {
      _showDuplicateDateMessage();
      return;
    }

    final transfer = _transferEntries.fold<double>(
      0,
      (sum, entry) => sum + _toMoney(entry.amountCtrl.text),
    );
    final expenses = _expenseEntries.isEmpty
        ? _toMoney(_expensesCtrl.text)
        : _expenseEntries.fold<double>(
            0,
            (sum, expense) => sum + _toMoney(expense.amountCtrl.text),
          );
    final submittedType = _type;
    final submittedPosVoucher = _posVoucher;
    final submittedPosPreviewBytes = submittedPosVoucher == null
        ? null
        : _voucherPreviewBytes[_closeVoucherPreviewKey(submittedPosVoucher)];

    await controller.saveClose(
      type: _type,
      date: _date,
      cash: _toMoney(_cashCtrl.text),
      transfer: transfer,
      transfers: _transferPayload(),
      card: _toMoney(_cardCtrl.text),
      otherIncome: _toMoney(_otherIncomeCtrl.text),
      expenses: expenses,
      cashDelivered: _toMoney(_cashDeliveredCtrl.text),
      notes: _notesCtrl.text,
      posVoucher: _posVoucher,
      expenseDetails: _expensePayload(),
      correctionOfCloseId: assistantMode && _isCorrection
          ? _correctionOfCloseId
          : null,
      correctionReason: assistantMode && _isCorrection
          ? _correctionReasonCtrl.text
          : null,
    );

    if (!mounted) return;
    final nextState = ref.read(cierresDiariosControllerProvider);
    if (nextState.error != null) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Cierre enviado'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );

    if (assistantMode && !editing) {
      _resetAssistantFormAfterSubmit(
        nextType: submittedType == CloseType.tienda
            ? CloseType.phytoemagry
            : submittedType,
        preservedPosVoucher: submittedType == CloseType.tienda
            ? submittedPosVoucher
            : null,
        preservedPosPreviewBytes: submittedType == CloseType.tienda
            ? submittedPosPreviewBytes
            : null,
      );
    }
  }

  TextFormField _moneyField(
    TextEditingController controller,
    String label, {
    bool required = false,
    bool mustBeGreaterThanZero = false,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: const [_AccountingMoneyInputFormatter()],
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        prefixText: 'RD\$ ',
      ),
      onTap: () => _prepareAccountingMoneyEditing(controller),
      onChanged: (value) {
        setState(() {});
        onChanged?.call(value);
      },
      validator: (value) {
        if (required && (value ?? '').trim().isEmpty) {
          return 'Campo obligatorio';
        }
        final amount = _toMoney(value);
        if (amount < 0) return 'No puede ser negativo';
        if (mustBeGreaterThanZero && amount <= 0) {
          return 'Debe ser mayor a cero';
        }
        return null;
      },
    );
  }

  Widget _buildDatePickerField(CierresDiariosState state, bool editing) {
    return FormField<DateTime>(
      initialValue: _date,
      validator: (_) =>
          _dateOnly(_date).trim().isEmpty ? 'Fecha obligatoria' : null,
      builder: (field) => InkWell(
        onTap: editing
            ? null
            : () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2024),
                  lastDate: DateTime(2100),
                );
                if (picked == null) return;
                if (_hasActiveCloseFor(
                      picked,
                      _type,
                      state,
                      excludingId: _editingId,
                    ) &&
                    !_isCorrection) {
                  _showDuplicateDateMessage();
                  return;
                }
                setState(() => _date = picked);
                field.didChange(picked);
              },
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Fecha del cierre *',
            errorText: field.errorText,
          ),
          child: Text(_dateOnly(_date)),
        ),
      ),
    );
  }

  Widget _buildAssistantCorrectionToggle() {
    final theme = Theme.of(context);
    return Container(
      height: 54,
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Corrige uno anterior',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
          Transform.scale(
            scale: 0.78,
            child: Switch.adaptive(
              value: _isCorrection,
              onChanged: (value) {
                setState(() {
                  _isCorrection = value;
                  if (!value) {
                    _correctionOfCloseId = null;
                    _correctionReasonCtrl.clear();
                  }
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssistantCorrectionDetails(
    List<CloseModel> closes,
    String? currentUserId,
  ) {
    final selectable = closes.where((close) {
      if (close.id == _editingId) return false;
      if ((currentUserId ?? '').trim().isEmpty) return true;
      return close.createdById == currentUserId;
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final selectedExists = selectable.any(
      (close) => close.id == _correctionOfCloseId,
    );

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: selectedExists ? _correctionOfCloseId : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Cierre anterior a corregir',
            ),
            items: selectable.map((close) {
              final label = [
                DateFormat('dd/MM/yyyy').format(close.date),
                close.type == CloseType.tienda
                    ? 'Tecnología'
                    : close.type.label,
                _formatAccountingMoney(close.netTotal),
              ].join(' · ');
              return DropdownMenuItem(value: close.id, child: Text(label));
            }).toList(),
            onChanged: (value) => setState(() => _correctionOfCloseId = value),
            validator: (_) {
              if (!_isCorrection) return null;
              return (_correctionOfCloseId ?? '').trim().isEmpty
                  ? 'Selecciona el cierre anterior'
                  : null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _correctionReasonCtrl,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Motivo de corrección',
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {}),
            validator: (value) {
              if (!_isCorrection) return null;
              return (value ?? '').trim().isEmpty
                  ? 'El motivo es obligatorio'
                  : null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTransferSection(
    NumberFormat money, {
    bool assistantMode = false,
  }) {
    final total = _transferEntries.fold<double>(
      0,
      (sum, entry) => sum + _toMoney(entry.amountCtrl.text),
    );
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(assistantMode ? 8 : 12),
      decoration: BoxDecoration(
        color: assistantMode
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.10)
            : null,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(
            alpha: assistantMode ? 0.58 : 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Transferencias ${money.format(total)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: assistantMode ? 12 : null,
                    color: assistantMode
                        ? theme.colorScheme.onSurfaceVariant
                        : null,
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Agregar transferencia',
                onPressed: () {
                  setState(() => _transferEntries.add(_TransferDraft()));
                },
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          if (_transferEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Sin transferencias',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            ..._transferEntries.asMap().entries.map((entry) {
              final index = entry.key;
              final draft = entry.value;
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _TransferEntryEditor(
                  index: index,
                  draft: draft,
                  onChanged: () => setState(() {}),
                  onRemove: () {
                    setState(() {
                      for (final voucher in draft.vouchers) {
                        _voucherPreviewBytes.remove(
                          _closeVoucherPreviewKey(voucher),
                        );
                      }
                      _transferEntries.removeAt(index).dispose();
                    });
                  },
                  onPickVoucher: () => _pickVoucher(draft),
                  onOpenVoucher: (voucher) => _openVoucherPreview(voucher),
                  previewBytesFor: (voucher) =>
                      _voucherPreviewBytes[_closeVoucherPreviewKey(voucher)],
                  onVoucherRemoved: (voucher) => _voucherPreviewBytes.remove(
                    _closeVoucherPreviewKey(voucher),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildExpensesSection(
    NumberFormat money, {
    bool assistantMode = false,
  }) {
    final total = _expenseEntries.fold<double>(
      0,
      (sum, entry) => sum + _toMoney(entry.amountCtrl.text),
    );
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.all(assistantMode ? 8 : 12),
      decoration: BoxDecoration(
        color: assistantMode
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.10)
            : null,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(
            alpha: assistantMode ? 0.58 : 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Gastos del día ${money.format(total)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: assistantMode ? 12 : null,
                    color: assistantMode
                        ? theme.colorScheme.onSurfaceVariant
                        : null,
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Agregar gasto',
                onPressed: () {
                  setState(() => _expenseEntries.add(_ExpenseDraft()));
                },
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          if (_expenseEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Sin gastos registrados. Agrega concepto y monto.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            ..._expenseEntries.asMap().entries.map((entry) {
              final index = entry.key;
              final draft = entry.value;
              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _ExpenseEntryEditor(
                  index: index,
                  draft: draft,
                  onChanged: () => setState(() {}),
                  onRemove: () {
                    setState(() {
                      for (final voucher in draft.vouchers) {
                        _voucherPreviewBytes.remove(
                          _closeVoucherPreviewKey(voucher),
                        );
                      }
                      _expenseEntries.removeAt(index).dispose();
                    });
                  },
                  onPickVoucher: () => _pickExpenseVoucher(draft),
                  onOpenVoucher: (voucher) => _openVoucherPreview(voucher),
                  previewBytesFor: (voucher) =>
                      _voucherPreviewBytes[_closeVoucherPreviewKey(voucher)],
                  onVoucherRemoved: (voucher) => _voucherPreviewBytes.remove(
                    _closeVoucherPreviewKey(voucher),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _pickVoucher(_TransferDraft draft) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => draft.uploading = true);
    final repo = ref.read(contabilidadRepositoryProvider);
    try {
      for (final file in result.files) {
        final uploaded = await repo.uploadCloseVoucher(file);
        draft.vouchers.add(uploaded);
        final previewBytes = file.bytes;
        if (previewBytes != null &&
            (_isCloseVoucherImage(uploaded) ||
                _isPickedCloseVoucherImage(file))) {
          _voucherPreviewBytes[_closeVoucherPreviewKey(uploaded)] =
              previewBytes;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al subir voucher: $e')));
      }
    } finally {
      if (mounted) setState(() => draft.uploading = false);
    }
  }

  Future<void> _pickExpenseVoucher(_ExpenseDraft draft) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => draft.uploading = true);
    final repo = ref.read(contabilidadRepositoryProvider);
    try {
      for (final file in result.files) {
        final uploaded = await repo.uploadCloseVoucher(file);
        draft.vouchers.add(uploaded);
        final previewBytes = file.bytes;
        if (previewBytes != null &&
            (_isCloseVoucherImage(uploaded) ||
                _isPickedCloseVoucherImage(file))) {
          _voucherPreviewBytes[_closeVoucherPreviewKey(uploaded)] =
              previewBytes;
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al subir comprobante de gasto: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => draft.uploading = false);
    }
  }

  void _openVoucherPreview(CloseTransferVoucherModel voucher) {
    final fileUrl = _resolveContabilidadAssetUrl(voucher.fileUrl);
    final isImage = _isCloseVoucherImage(voucher);
    final previewBytes = _voucherPreviewBytes[_closeVoucherPreviewKey(voucher)];
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 640),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(voucher.fileName),
                trailing: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              Expanded(
                child: isImage
                    ? InteractiveViewer(
                        child: previewBytes != null
                            ? Image.memory(previewBytes, fit: BoxFit.contain)
                            : Image.network(
                                fileUrl,
                                fit: BoxFit.contain,
                                loadingBuilder:
                                    (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return const Center(
                                        child: CircularProgressIndicator(),
                                      );
                                    },
                                errorBuilder: (context, error, stackTrace) {
                                  return const Center(
                                    child: Text('No se pudo cargar la imagen.'),
                                  );
                                },
                              ),
                      )
                    : Center(child: Text(fileUrl, textAlign: TextAlign.center)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _transferPayload() {
    return _transferEntries.map((entry) {
      return {
        'bankName': entry.bankCtrl.text.trim(),
        'amount': _toMoney(entry.amountCtrl.text),
        if (entry.referenceCtrl.text.trim().isNotEmpty)
          'referenceNumber': entry.referenceCtrl.text.trim(),
        if (entry.noteCtrl.text.trim().isNotEmpty)
          'note': entry.noteCtrl.text.trim(),
        'vouchers': entry.vouchers.map((item) => item.toJson()).toList(),
      };
    }).toList();
  }

  List<Map<String, dynamic>> _expensePayload() {
    return _expenseEntries
        .where((e) => e.conceptCtrl.text.trim().isNotEmpty)
        .map(
          (e) => {
            'concept': e.conceptCtrl.text.trim(),
            'amount': _toMoney(e.amountCtrl.text),
            if (e.vouchers.isNotEmpty)
              'vouchers': e.vouchers.map((item) => item.toJson()).toList(),
          },
        )
        .toList();
  }

  Widget _buildPosVoucherSection() {
    final voucher = _posVoucher;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: 'Boucher cierre POS *'),
        if (voucher != null) ...[
          _CloseVoucherInlinePreview(
            voucher: voucher,
            previewBytes:
                _voucherPreviewBytes[_closeVoucherPreviewKey(voucher)],
            onOpen: () => _openVoucherPreview(voucher),
            onRemove: () {
              setState(() {
                _voucherPreviewBytes.remove(_closeVoucherPreviewKey(voucher));
                _posVoucher = null;
              });
            },
          ),
        ] else ...[
          OutlinedButton.icon(
            onPressed: _uploadingPosVoucher ? null : _pickPosVoucher,
            icon: _uploadingPosVoucher
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file_outlined),
            label: const Text('Subir boucher del POS'),
          ),
        ],
      ],
    );
  }

  Future<void> _pickPosVoucher() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _uploadingPosVoucher = true);
    try {
      final file = result.files.first;
      final uploaded = await ref
          .read(contabilidadRepositoryProvider)
          .uploadPosVoucher(file);
      final previewBytes = file.bytes;
      if (mounted) {
        setState(() {
          _posVoucher = uploaded;
          if (previewBytes != null &&
              (_isCloseVoucherImage(uploaded) ||
                  _isPickedCloseVoucherImage(file))) {
            _voucherPreviewBytes[_closeVoucherPreviewKey(uploaded)] =
                previewBytes;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al subir voucher POS: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingPosVoucher = false);
    }
  }

  void _applyEdit(CloseModel close) {
    setState(() {
      _editingId = close.id;
      _type = close.type;
      _date = close.date;
      _cashCtrl.text = _formatAccountingAmount(close.cash);
      for (final entry in _transferEntries) {
        entry.dispose();
      }
      _transferEntries
        ..clear()
        ..addAll(close.transfers.map(_TransferDraft.fromModel));
      _cardCtrl.text = _formatAccountingAmount(close.card);
      _otherIncomeCtrl.text = _formatAccountingAmount(close.otherIncome);
      _expensesCtrl.text = _formatAccountingAmount(close.expenses);
      _expenseEntries.clear();
      if (close.expenseDetails.isNotEmpty) {
        _expenseEntries.addAll(close.expenseDetails.map(_expenseDraftFromJson));
      } else if (close.expenses > 0) {
        _expenseEntries.add(
          _ExpenseDraft(
            concept: 'Gastos del día',
            amount: _formatAccountingAmount(close.expenses),
          ),
        );
      }
      _cashDeliveredCtrl.text = _formatAccountingAmount(close.cashDelivered);
      _notesCtrl.text = close.notes ?? '';
      _posVoucher = close.evidenceUrl != null && close.evidenceFileName != null
          ? CloseTransferVoucherModel(
              fileUrl: close.evidenceUrl!,
              fileName: close.evidenceFileName!,
              mimeType: close.evidenceMimeType ?? 'image/jpeg',
              storageKey: close.evidenceStorageKey ?? '',
            )
          : null;
    });
  }

  void _resetForm() {
    setState(() {
      _editingId = null;
      _isCorrection = false;
      _correctionOfCloseId = null;
      _type =
          ref.read(cierresDiariosControllerProvider).typeFilter ??
          CloseType.tienda;
      _date = DateTime.now();
      _cashCtrl.text = _formatAccountingAmount(0);
      for (final entry in _transferEntries) {
        entry.dispose();
      }
      _transferEntries.clear();
      for (final expense in _expenseEntries) {
        expense.dispose();
      }
      _expenseEntries.clear();
      _cardCtrl.text = _formatAccountingAmount(0);
      _otherIncomeCtrl.text = _formatAccountingAmount(0);
      _expensesCtrl.text = _formatAccountingAmount(0);
      _cashDeliveredCtrl.text = _formatAccountingAmount(0);
      _notesCtrl.clear();
      _correctionReasonCtrl.clear();
      _voucherPreviewBytes.clear();
      _posVoucher = null;
      _uploadingPosVoucher = false;
    });
  }

  void _resetAssistantFormAfterSubmit({
    required CloseType nextType,
    CloseTransferVoucherModel? preservedPosVoucher,
    Uint8List? preservedPosPreviewBytes,
  }) {
    ref.read(cierresDiariosControllerProvider.notifier).setTypeFilter(nextType);
    setState(() {
      _editingId = null;
      _isCorrection = false;
      _correctionOfCloseId = null;
      _type = nextType;
      _date = DateTime.now();
      _cashCtrl.text = _formatAccountingAmount(0);
      for (final entry in _transferEntries) {
        entry.dispose();
      }
      _transferEntries.clear();
      for (final expense in _expenseEntries) {
        expense.dispose();
      }
      _expenseEntries.clear();
      _cardCtrl.text = _formatAccountingAmount(0);
      _otherIncomeCtrl.text = _formatAccountingAmount(0);
      _expensesCtrl.text = _formatAccountingAmount(0);
      _cashDeliveredCtrl.text = _formatAccountingAmount(0);
      _notesCtrl.clear();
      _correctionReasonCtrl.clear();
      _voucherPreviewBytes.clear();
      _posVoucher = preservedPosVoucher;
      if (preservedPosVoucher != null && preservedPosPreviewBytes != null) {
        _voucherPreviewBytes[_closeVoucherPreviewKey(preservedPosVoucher)] =
            preservedPosPreviewBytes;
      }
      _uploadingPosVoucher = false;
    });
  }

  String _dateOnly(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  double _toMoney(String? raw) {
    return _parseAccountingMoney(raw);
  }

  _ExpenseDraft _expenseDraftFromJson(Map<String, dynamic> value) {
    final amount = value['amount'];
    final parsedAmount = amount is num
        ? amount.toDouble()
        : double.tryParse((amount ?? '0').toString().replaceAll(',', '.')) ?? 0;
    final vouchers = ((value['vouchers'] as List?) ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              CloseTransferVoucherModel.fromJson(item.cast<String, dynamic>()),
        )
        .toList();

    return _ExpenseDraft(
      concept: (value['concept'] as String?)?.trim() ?? 'Gastos del día',
      amount: _formatAccountingAmount(parsedAmount),
      vouchers: vouchers,
    );
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _hasActiveCloseFor(
    DateTime date,
    CloseType type,
    CierresDiariosState state, {
    String? excludingId,
  }) {
    return state.closes.any((close) {
      if (excludingId != null && close.id == excludingId) return false;
      if (close.type != type) return false;
      if (close.isRejected) return false;
      return _sameDay(close.date, date);
    });
  }

  void _showDuplicateDateMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Ya existe un cierre activo para esta categoria y fecha. Selecciona otra fecha o categoria.',
        ),
      ),
    );
  }

  void _trySelectType(
    CloseType type,
    CierresDiariosState state,
    CierresDiariosController controller,
  ) {
    if (!_isCorrection &&
        _hasActiveCloseFor(_date, type, state, excludingId: _editingId)) {
      _showDuplicateDateMessage();
      return;
    }
    controller.setTypeFilter(type);
  }
}

class _AssistantDailyPairBanner extends StatelessWidget {
  const _AssistantDailyPairBanner({
    required this.date,
    required this.closes,
    required this.editingId,
    required this.isCorrection,
  });

  final DateTime date;
  final List<CloseModel> closes;
  final String? editingId;
  final bool isCorrection;

  static bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  CloseModel? _latestForType(CloseType type) {
    final matches = closes.where((close) {
      if (editingId != null && close.id == editingId) return false;
      if (close.type != type) return false;
      return _sameDay(close.date, date);
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return matches.isEmpty ? null : matches.first;
  }

  String _statusLabel(CloseModel? close) {
    if (close == null) return 'Sin registrar';
    if (close.isApproved) return 'Aprobado';
    if (close.isRejected) return 'Rechazado';
    return 'Pendiente';
  }

  Color _statusColor(BuildContext context, CloseModel? close) {
    if (close == null) return Theme.of(context).colorScheme.outline;
    if (close.isApproved) return const Color(0xFF15803D);
    if (close.isRejected) return Theme.of(context).colorScheme.error;
    return const Color(0xFFB45309);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tecnologia = _latestForType(CloseType.tienda);
    final phyto = _latestForType(CloseType.phytoemagry);

    final missing = <String>[
      if (tecnologia == null) 'Tecnología',
      if (phyto == null) 'PhytoEmagry',
    ];
    final statusText = missing.isEmpty
        ? 'Par diario completo para ${DateFormat('dd/MM/yyyy').format(date)}'
        : 'Falta registrar: ${missing.join(' y ')}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.9),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _MiniCloseTag(
                label: 'Tecnología: ${_statusLabel(tecnologia)}',
                color: _statusColor(context, tecnologia),
              ),
              _MiniCloseTag(
                label: 'PhytoEmagry: ${_statusLabel(phyto)}',
                color: _statusColor(context, phyto),
              ),
            ],
          ),
          if (!isCorrection) ...[
            const SizedBox(height: 6),
            Text(
              statusText,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AssistantDailyHistoryGroup {
  const _AssistantDailyHistoryGroup({required this.day, required this.closes});

  final DateTime day;
  final List<CloseModel> closes;

  bool get hasTecnologia => closes.any((item) => item.type == CloseType.tienda);
  bool get hasPhyto => closes.any((item) => item.type == CloseType.phytoemagry);
}

class _AssistantHistoryShell extends StatelessWidget {
  const _AssistantHistoryShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

enum _AssistantCloseListFilter {
  todos,
  pendientes,
  aprobados,
  rechazados,
  correcciones,
}

class _AssistantRawHistoryList extends StatefulWidget {
  const _AssistantRawHistoryList({
    required this.closes,
    required this.fromDate,
    required this.toDate,
  });

  final List<CloseModel> closes;
  final DateTime fromDate;
  final DateTime toDate;

  @override
  State<_AssistantRawHistoryList> createState() =>
      _AssistantRawHistoryListState();
}

class _AssistantRawHistoryListState extends State<_AssistantRawHistoryList> {
  _AssistantCloseListFilter _filter = _AssistantCloseListFilter.todos;
  final _listScrollCtrl = ScrollController();

  @override
  void dispose() {
    _listScrollCtrl.dispose();
    super.dispose();
  }

  String _money(double value) => _formatAccountingMoney(value);

  String _filterLabel(_AssistantCloseListFilter filter) {
    switch (filter) {
      case _AssistantCloseListFilter.todos:
        return 'Todos';
      case _AssistantCloseListFilter.pendientes:
        return 'Pendientes';
      case _AssistantCloseListFilter.aprobados:
        return 'Aprobados';
      case _AssistantCloseListFilter.rechazados:
        return 'Rechazados';
      case _AssistantCloseListFilter.correcciones:
        return 'Correcciones';
    }
  }

  bool _matchesFilter(CloseModel close) {
    switch (_filter) {
      case _AssistantCloseListFilter.todos:
        return true;
      case _AssistantCloseListFilter.pendientes:
        return close.isPending;
      case _AssistantCloseListFilter.aprobados:
        return close.isApproved;
      case _AssistantCloseListFilter.rechazados:
        return close.isRejected;
      case _AssistantCloseListFilter.correcciones:
        return close.isCorrection;
    }
  }

  String _statusLabel(CloseModel close) {
    if (close.isApproved) return 'Aprobado';
    if (close.isRejected) return 'Rechazado';
    return 'Pendiente';
  }

  Color _statusColor(BuildContext context, CloseModel close) {
    if (close.isApproved) return const Color(0xFF15803D);
    if (close.isRejected) return Theme.of(context).colorScheme.error;
    return const Color(0xFFB45309);
  }

  String _referenceLabel(CloseModel close) {
    final id = (close.correctionOfCloseId ?? '').trim();
    if (id.isEmpty) return 'N/D';
    return id.length <= 8 ? id : id.substring(0, 8);
  }

  bool _wasEdited(CloseModel close) {
    return close.updatedAt.difference(close.createdAt).abs().inSeconds > 30;
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  int _typeOrder(CloseType type) {
    if (type == CloseType.tienda) return 0;
    if (type == CloseType.phytoemagry) return 1;
    return 2;
  }

  List<_AssistantDailyHistoryGroup> _buildGroups(List<CloseModel> rows) {
    final sorted = [...rows]
      ..sort((a, b) {
        final aDay = DateTime(a.date.year, a.date.month, a.date.day);
        final bDay = DateTime(b.date.year, b.date.month, b.date.day);
        final byDate = bDay.compareTo(aDay);
        if (byDate != 0) return byDate;
        final byType = _typeOrder(a.type).compareTo(_typeOrder(b.type));
        if (byType != 0) return byType;
        return b.createdAt.compareTo(a.createdAt);
      });

    final groups = <_AssistantDailyHistoryGroup>[];
    for (final close in sorted) {
      final day = DateTime(close.date.year, close.date.month, close.date.day);
      if (groups.isEmpty || !_sameDay(groups.last.day, day)) {
        groups.add(_AssistantDailyHistoryGroup(day: day, closes: [close]));
        continue;
      }
      groups.last.closes.add(close);
    }
    return groups;
  }

  void _openDetail(BuildContext context, CloseModel close) {
    showDialog<void>(
      context: context,
      builder: (context) => _AssistantCloseDetailDialog(
        close: close,
        money: _money,
        statusLabel: _statusLabel(close),
        statusColor: _statusColor(context, close),
        referenceLabel: _referenceLabel(close),
        wasEdited: _wasEdited(close),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = [...widget.closes].where(_matchesFilter).toList();
    final groups = _buildGroups(rows);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: AppCard(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final boundedHeight =
                  constraints.hasBoundedHeight &&
                  constraints.maxHeight.isFinite;
              final list = SingleChildScrollView(
                controller: boundedHeight ? _listScrollCtrl : null,
                primary: false,
                physics: boundedHeight
                    ? const BouncingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final group in groups) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              DateFormat('dd/MM/yyyy').format(group.day),
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          _MiniCloseTag(
                            label: group.hasTecnologia && group.hasPhyto
                                ? 'Par completo'
                                : 'Par incompleto',
                            color: group.hasTecnologia && group.hasPhyto
                                ? const Color(0xFF15803D)
                                : const Color(0xFFB45309),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      for (final close in group.closes) ...[
                        _AssistantCloseTile(
                          close: close,
                          money: _money,
                          statusLabel: _statusLabel(close),
                          statusColor: _statusColor(context, close),
                          referenceLabel: _referenceLabel(close),
                          wasEdited: _wasEdited(close),
                          onTap: () => _openDetail(context, close),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ],
                ),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Cierres registrados',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        '${rows.length}/${widget.closes.length}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final filter
                            in _AssistantCloseListFilter.values) ...[
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              selected: _filter == filter,
                              label: Text(_filterLabel(filter)),
                              labelStyle: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 10.5,
                              ),
                              visualDensity: const VisualDensity(
                                horizontal: -3,
                                vertical: -3,
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onSelected: (_) =>
                                  setState(() => _filter = filter),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (rows.isEmpty)
                    Text(
                      'Sin cierres para este filtro entre ${DateFormat('dd/MM/yyyy').format(widget.fromDate)} y ${DateFormat('dd/MM/yyyy').format(widget.toDate)}.',
                      style: theme.textTheme.bodyMedium,
                    )
                  else if (boundedHeight)
                    Expanded(child: list)
                  else
                    list,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AssistantCloseTile extends StatelessWidget {
  const _AssistantCloseTile({
    required this.close,
    required this.money,
    required this.statusLabel,
    required this.statusColor,
    required this.referenceLabel,
    required this.wasEdited,
    required this.onTap,
  });

  final CloseModel close;
  final String Function(double value) money;
  final String statusLabel;
  final Color statusColor;
  final String referenceLabel;
  final bool wasEdited;
  final VoidCallback onTap;

  String get _category =>
      close.type == CloseType.tienda ? 'Tecnología' : close.type.label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.18,
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.72),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _category,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  _AnimatedCloseStatusBadge(
                    label: statusLabel,
                    color: statusColor,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat('dd/MM/yyyy').format(close.date),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  Text(
                    money(close.netTotal),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _MiniCloseTag(
                    label: close.isCorrection
                        ? 'Correccion #$referenceLabel'
                        : 'Normal',
                    color: theme.colorScheme.primary,
                  ),
                  if (wasEdited)
                    _MiniCloseTag(
                      label: 'Editado',
                      color: theme.colorScheme.tertiary,
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

class _AnimatedCloseStatusBadge extends StatelessWidget {
  const _AnimatedCloseStatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.86, end: 1),
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(scale: value, child: child);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniCloseTag extends StatelessWidget {
  const _MiniCloseTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _AssistantCloseDetailDialog extends StatelessWidget {
  const _AssistantCloseDetailDialog({
    required this.close,
    required this.money,
    required this.statusLabel,
    required this.statusColor,
    required this.referenceLabel,
    required this.wasEdited,
  });

  final CloseModel close;
  final String Function(double value) money;
  final String statusLabel;
  final Color statusColor;
  final String referenceLabel;
  final bool wasEdited;

  String get _category =>
      close.type == CloseType.tienda ? 'Tecnología' : close.type.label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Detalle del cierre',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _AnimatedCloseStatusBadge(
                    label: statusLabel,
                    color: statusColor,
                  ),
                  _MiniCloseTag(
                    label: close.isCorrection ? 'Corregido' : 'Normal',
                    color: close.isCorrection
                        ? const Color(0xFF7C3AED)
                        : theme.colorScheme.primary,
                  ),
                  if (wasEdited)
                    const _MiniCloseTag(
                      label: 'Editado',
                      color: Color(0xFF0369A1),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _RawHistoryField(
                    label: 'Fecha',
                    value: DateFormat('dd/MM/yyyy').format(close.date),
                  ),
                  _RawHistoryField(label: 'Categoría', value: _category),
                  _RawHistoryField(
                    label: 'Monto total',
                    value: money(close.netTotal),
                  ),
                  _RawHistoryField(label: 'Efectivo', value: money(close.cash)),
                  _RawHistoryField(
                    label: 'Transferencias',
                    value: money(close.transfer),
                  ),
                  _RawHistoryField(label: 'Tarjeta', value: money(close.card)),
                  _RawHistoryField(
                    label: 'Gastos',
                    value: money(close.expenses),
                  ),
                  _RawHistoryField(
                    label: 'Creado por',
                    value: close.createdByName ?? close.createdById ?? 'N/D',
                  ),
                  _RawHistoryField(
                    label: 'Fecha de creación',
                    value: DateFormat(
                      'dd/MM/yyyy h:mm a',
                      'es_DO',
                    ).format(close.createdAt),
                  ),
                  if (close.isCorrection)
                    _RawHistoryField(
                      label: 'Corrige cierre',
                      value: referenceLabel,
                    ),
                ],
              ),
              if (close.isCorrection ||
                  (close.notes ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                if (close.isCorrection)
                  _DialogTextBlock(
                    label: 'Motivo de corrección',
                    value: close.correctionReason ?? 'N/D',
                  ),
                if ((close.notes ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _DialogTextBlock(label: 'Notas', value: close.notes!.trim()),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DialogTextBlock extends StatelessWidget {
  const _DialogTextBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.32,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _RawHistoryField extends StatelessWidget {
  const _RawHistoryField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _DetailAmountLine extends StatelessWidget {
  const _DetailAmountLine({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final bool emphasize;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: colorScheme.outlineVariant))
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: emphasize ? colorScheme.error : colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _RightTotalLine extends StatelessWidget {
  const _RightTotalLine({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.showDivider = true,
  });

  final String label;
  final String value;
  final bool emphasize;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: colorScheme.outlineVariant))
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: emphasize ? colorScheme.error : colorScheme.onSurface,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryFullScreenPage extends ConsumerStatefulWidget {
  final CloseType initialType;

  const _HistoryFullScreenPage({required this.initialType});

  @override
  ConsumerState<_HistoryFullScreenPage> createState() =>
      _HistoryFullScreenPageState();
}

class _HistoryFullScreenPageState
    extends ConsumerState<_HistoryFullScreenPage> {
  CloseType? _selectedType;
  String _selectedStatus = 'TODOS';
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _selectionMode = false;
  bool _deletingSelection = false;
  final Set<String> _selectedCloseIds = <String>{};
  _FinancialSummaryPreset _summaryPreset = _FinancialSummaryPreset.hoy;
  DateTime? _summaryFromDate;
  DateTime? _summaryToDate;
  CloseType? _summaryBusinessType;
  bool _summaryLoading = false;
  String? _summaryError;
  CloseFinancialSummaryModel? _summary;

  bool get _isAdmin {
    final role = ref.read(authStateProvider).user?.role;
    return parseAppRole(role).isAdmin;
  }

  @override
  void initState() {
    super.initState();
    if (_isAdmin) {
      _setSummaryPreset(_FinancialSummaryPreset.hoy, refresh: false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(cierresDiariosControllerProvider.notifier).loadAdminHistory();
        _fetchSummary();
      });
    }
  }

  String _dateOnly(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

  String? _normalizeAdminPassword(String? value) {
    final cleaned = (value ?? '').trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  Future<String?> _askAdminPassword() async {
    final ctrl = TextEditingController();
    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminacion'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Contrasena de administrador',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return _normalizeAdminPassword(password);
  }

  Future<void> _deleteOneClose(CloseModel close) async {
    final password = await _askAdminPassword();
    if (!mounted || password == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cierre'),
        content: Text(
          'Se eliminara el cierre de ${close.type.label} del ${_dateOnly(close.date)}. Esta accion no se puede deshacer.',
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

    await ref
        .read(cierresDiariosControllerProvider.notifier)
        .deleteClose(close.id, adminPassword: password);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cierre eliminado correctamente.')),
    );
  }

  Future<void> _deleteSelectedCloses() async {
    if (_selectedCloseIds.isEmpty || _deletingSelection) return;

    final password = await _askAdminPassword();
    if (!mounted || password == null) return;

    final total = _selectedCloseIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar seleccion'),
        content: Text(
          'Se eliminaran $total cierres seleccionados. Esta accion no se puede deshacer.',
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

    setState(() => _deletingSelection = true);
    try {
      await ref
          .read(cierresDiariosControllerProvider.notifier)
          .deleteClosesBulk(
            ids: _selectedCloseIds.toList(),
            adminPassword: password,
          );
      if (!mounted) return;
      setState(() {
        _selectedCloseIds.clear();
        _selectionMode = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Se eliminaron $total cierres.')));
    } finally {
      if (mounted) {
        setState(() => _deletingSelection = false);
      }
    }
  }

  bool _isWithinRange(CloseModel close) {
    if (_fromDate != null) {
      final from = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
      if (close.date.isBefore(from)) return false;
    }
    if (_toDate != null) {
      final to = DateTime(
        _toDate!.year,
        _toDate!.month,
        _toDate!.day,
        23,
        59,
        59,
      );
      if (close.date.isAfter(to)) return false;
    }
    return true;
  }

  void _setSummaryPreset(
    _FinancialSummaryPreset preset, {
    bool refresh = true,
  }) {
    final now = DateTime.now();
    DateTime from;
    DateTime to;

    switch (preset) {
      case _FinancialSummaryPreset.hoy:
        from = DateTime(now.year, now.month, now.day);
        to = from;
        break;
      case _FinancialSummaryPreset.ayer:
        final yesterday = now.subtract(const Duration(days: 1));
        from = DateTime(yesterday.year, yesterday.month, yesterday.day);
        to = from;
        break;
      case _FinancialSummaryPreset.quincena:
        if (now.day >= 15) {
          from = DateTime(now.year, now.month, 15);
          to = DateTime(now.year, now.month + 1, 0);
        } else {
          from = DateTime(now.year, now.month, 1);
          to = DateTime(now.year, now.month, 14);
        }
        break;
      case _FinancialSummaryPreset.mes:
        from = DateTime(now.year, now.month, 1);
        to = DateTime(now.year, now.month + 1, 0);
        break;
      case _FinancialSummaryPreset.personalizado:
        from = _summaryFromDate ?? DateTime(now.year, now.month, now.day);
        to = _summaryToDate ?? from;
        break;
    }

    setState(() {
      _summaryPreset = preset;
      _summaryFromDate = DateTime(from.year, from.month, from.day);
      _summaryToDate = DateTime(to.year, to.month, to.day);
    });

    if (refresh) {
      _fetchSummary();
    }
  }

  Future<void> _pickSummaryDate({required bool fromDate}) async {
    final base = fromDate ? _summaryFromDate : _summaryToDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: base ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;

    setState(() {
      _summaryPreset = _FinancialSummaryPreset.personalizado;
      if (fromDate) {
        _summaryFromDate = DateTime(picked.year, picked.month, picked.day);
      } else {
        _summaryToDate = DateTime(picked.year, picked.month, picked.day);
      }
    });
  }

  Future<void> _fetchSummary() async {
    if (!_isAdmin) return;

    final from = _summaryFromDate ?? DateTime.now();
    final to = _summaryToDate ?? from;

    setState(() {
      _summaryLoading = true;
      _summaryError = null;
    });

    try {
      final summary = await ref
          .read(contabilidadRepositoryProvider)
          .getCloseFinancialSummary(
            fromDate: from,
            toDate: to,
            businessType: _summaryBusinessType,
          );
      if (!mounted) return;
      setState(() {
        _summary = summary;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _summaryError = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _summaryLoading = false;
        });
      }
    }
  }

  void _clearSummaryFilters() {
    setState(() {
      _summaryBusinessType = null;
    });
    _setSummaryPreset(_FinancialSummaryPreset.hoy);
  }

  String _money(double value) => _formatAccountingMoney(value);

  String _adminFilterLabel(String value) {
    switch (value) {
      case 'pending':
        return 'Pendientes';
      case 'approved':
        return 'Aprobados';
      case 'rejected':
        return 'Rechazados';
      case 'corrections':
        return 'Correcciones';
      default:
        return 'Todos';
    }
  }

  bool _matchesAdminStatusFilter(CloseModel close) {
    switch (_selectedStatus) {
      case 'pending':
        return close.isPending;
      case 'approved':
        return close.isApproved;
      case 'rejected':
        return close.isRejected;
      case 'corrections':
        return close.isCorrection;
      default:
        return true;
    }
  }

  String _adminStatusLabel(CloseModel close) {
    if (close.isApproved) return 'Aprobado';
    if (close.isRejected) return 'Rechazado';
    return 'Pendiente';
  }

  Color _adminStatusColor(CloseModel close) {
    if (close.isApproved) return const Color(0xFF15803D);
    if (close.isRejected) return const Color(0xFFB91C1C);
    return const Color(0xFFB45309);
  }

  String _shortCloseId(String? id) {
    final value = (id ?? '').trim();
    if (value.isEmpty) return 'N/D';
    return value.length <= 8 ? value : value.substring(0, 8);
  }

  String _depositStatusLabel(String status) {
    switch (status.trim().toLowerCase()) {
      case 'deposited':
        return 'Depositado';
      case 'partial':
        return 'Parcial';
      default:
        return 'Pendiente';
    }
  }

  Future<void> _toggleCashDeposited(CloseModel close, bool value) async {
    try {
      await ref
          .read(cierresDiariosControllerProvider.notifier)
          .toggleCloseCashDeposited(id: close.id, cashDeposited: value);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Cierre marcado como depositado.'
                : 'Cierre marcado como pendiente de depósito.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ApiException
                ? e.message
                : 'No se pudo actualizar el estado de depósito.',
          ),
        ),
      );
    }
  }

  Widget _buildFilteredClosesPanel(List<CloseModel> closes) {
    final totalDelivered = closes.fold<double>(
      0,
      (sum, close) => sum + close.cashDelivered,
    );
    final deposited = closes.fold<double>(
      0,
      (sum, close) => sum + (close.cashDeposited ? close.cashDelivered : 0),
    );
    final pending = totalDelivered - deposited;
    final approved = closes.where((close) => close.isApproved).length;
    final rejected = closes.where((close) => close.isRejected).length;
    final pendingReview = closes.where((close) => close.isPending).length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          const Text(
            'Fondo de caja',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
            const SizedBox(height: 4),
            Text(
              '${closes.length} cierres filtrados',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 10),
            _RightTotalLine(
              label: 'Fondo de caja',
              value: _money(totalDelivered),
            ),
            _RightTotalLine(label: 'Depositado', value: _money(deposited)),
            _RightTotalLine(
              label: 'Pendiente por depositar',
              value: _money(pending),
              emphasize: pending > 0.009,
            ),
            _RightTotalLine(
              label: 'Pendientes revisión',
              value: pendingReview.toString(),
            ),
            _RightTotalLine(label: 'Aprobados', value: approved.toString()),
            _RightTotalLine(
              label: 'Rechazados',
              value: rejected.toString(),
              showDivider: false,
            ),
            if (closes.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              const Text(
                'Cierres incluidos',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              ...closes
                  .take(8)
                  .map(
                    (close) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${DateFormat('dd/MM').format(close.date)} · ${close.type == CloseType.tienda ? 'Tecnología' : close.type.label}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          Text(
                            _money(close.cashDelivered),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              if (closes.length > 8)
                Text(
                  '+${closes.length - 8} cierres más',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  bool _isDepositMoneyAvailable(CloseFinancialSummaryModel summary) {
    final available = summary.availableForDeposit.total;
    final pending = summary.totals.pendingDeposit;
    return available > 0.009 && pending > 0.009;
  }

  String _depositAvailabilityReason(CloseFinancialSummaryModel summary) {
    final status = summary.depositStatus.status.trim().toLowerCase();
    final available = summary.availableForDeposit.total;
    final pending = summary.totals.pendingDeposit;

    if (available <= 0.009 || pending <= 0.009) {
      if (status == 'deposited' ||
          summary.totals.deposited >= summary.totals.netTotal) {
        return 'No disponible: este rango ya fue depositado.';
      }
      return 'No disponible: no hay fondos pendientes por depositar en este rango.';
    }

    if (status == 'partial') {
      return 'Disponible parcial: aún queda dinero pendiente por depositar.';
    }

    return 'Disponible: hay dinero pendiente por depositar.';
  }

  int _getResponsiveColumnCount(double maxWidth) {
    if (maxWidth < 500) return 1;
    if (maxWidth < 900) return 2;
    return 3;
  }

  Widget _buildMetricsGrid(int columnsCount, CloseFinancialTotals totals) {
    const spacing = 5.0;
    const columnSpacing = 5.0;

    // Organizar métricas en secciones lógicas
    final metricRows = [
      // Income section (3 cols)
      [
        ('Efectivo declarado', totals.cashDeclared, null),
        ('Fondo de caja', totals.cashDelivered, null),
        ('Efec. disponible', totals.cashAvailable, const Color(0xFF047857)),
      ],
      // Transfers section (2 cols)
      [
        ('Transferencias', totals.transfers, null),
        ('Pago tarjeta', totals.cardPayments, null),
      ],
      // Expenses section (1 col)
      [
        ('Otros ingresos', totals.otherIncome, null),
        ('Gastos', totals.expenses, const Color(0xFFB91C1C)),
      ],
      // Deposit section (3 cols)
      [
        ('Total neto', totals.netTotal, null),
        ('Depositado', totals.deposited, null),
        ('Pendiente dep.', totals.pendingDeposit, const Color(0xFF1D4ED8)),
      ],
      // Difference section (1 col)
      [('Diferencia', totals.difference, const Color(0xFFB91C1C))],
    ];

    final gridCards = <Widget>[];
    for (final row in metricRows) {
      for (final (title, amount, color) in row) {
        gridCards.add(
          _buildSummaryMetricCard(title, amount, amountColor: color),
        );
      }
    }

    // Agrupar en filas según número de columnas
    final rows = <List<Widget>>[];
    for (int i = 0; i < gridCards.length; i += columnsCount) {
      final rowEnd = (i + columnsCount > gridCards.length)
          ? gridCards.length
          : i + columnsCount;
      rows.add(gridCards.sublist(i, rowEnd));
    }

    return Column(
      children: rows.map((rowCards) {
        return Padding(
          padding: EdgeInsets.only(bottom: spacing),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rowCards.asMap().entries.map((entry) {
              final isLast = entry.key == rowCards.length - 1;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: isLast ? 0 : columnSpacing),
                  child: entry.value,
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSummaryMetricCard(
    String title,
    double amount, {
    Color? amountColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            _money(amount),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: amountColor ?? const Color(0xFF0F172A),
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryPanel({required bool compact}) {
    final summary = _summary;
    final cardColor = const Color(0xFFF8FAFC);

    return Container(
      height: compact ? null : double.infinity,
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: LayoutBuilder(
          builder: (context, panelConstraints) {
            final moneyAvailable = summary == null
                ? false
                : _isDepositMoneyAvailable(summary);
            final availabilityReason = summary == null
                ? 'No hay resumen para calcular disponibilidad.'
                : _depositAvailabilityReason(summary);

            final content = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Resumen financiero',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Solo administración',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    ChoiceChip(
                      label: const Text('Hoy', style: TextStyle(fontSize: 11)),
                      selected: _summaryPreset == _FinancialSummaryPreset.hoy,
                      onSelected: (_) =>
                          _setSummaryPreset(_FinancialSummaryPreset.hoy),
                    ),
                    ChoiceChip(
                      label: const Text('Ayer', style: TextStyle(fontSize: 11)),
                      selected: _summaryPreset == _FinancialSummaryPreset.ayer,
                      onSelected: (_) =>
                          _setSummaryPreset(_FinancialSummaryPreset.ayer),
                    ),
                    ChoiceChip(
                      label: const Text(
                        'Quincena',
                        style: TextStyle(fontSize: 11),
                      ),
                      selected:
                          _summaryPreset == _FinancialSummaryPreset.quincena,
                      onSelected: (_) =>
                          _setSummaryPreset(_FinancialSummaryPreset.quincena),
                    ),
                    ChoiceChip(
                      label: const Text('Mes', style: TextStyle(fontSize: 11)),
                      selected: _summaryPreset == _FinancialSummaryPreset.mes,
                      onSelected: (_) =>
                          _setSummaryPreset(_FinancialSummaryPreset.mes),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickSummaryDate(fromDate: true),
                        icon: const Icon(
                          Icons.calendar_today_outlined,
                          size: 14,
                        ),
                        label: Text(
                          _summaryFromDate == null
                              ? 'Desde'
                              : _dateOnly(_summaryFromDate!),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickSummaryDate(fromDate: false),
                        icon: const Icon(Icons.event_outlined, size: 14),
                        label: Text(
                          _summaryToDate == null
                              ? 'Hasta'
                              : _dateOnly(_summaryToDate!),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Unidad de cierre',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<CloseType?>(
                      value: _summaryBusinessType,
                      isExpanded: true,
                      items: const [
                        DropdownMenuItem<CloseType?>(
                          value: null,
                          child: Text('Todos', style: TextStyle(fontSize: 12)),
                        ),
                        DropdownMenuItem<CloseType?>(
                          value: CloseType.tienda,
                          child: Text('Tienda', style: TextStyle(fontSize: 12)),
                        ),
                        DropdownMenuItem<CloseType?>(
                          value: CloseType.phytoemagry,
                          child: Text(
                            'PhytoEmagry',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => _summaryBusinessType = value);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _summaryLoading ? null : _fetchSummary,
                        icon: const Icon(Icons.filter_alt_outlined, size: 14),
                        label: const Text(
                          'Aplicar',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton(
                      onPressed: _summaryLoading ? null : _clearSummaryFilters,
                      child: const Text(
                        'Limpiar',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                if (_summaryLoading)
                  const LinearProgressIndicator()
                else if (_summaryError != null)
                  _ErrorBox(message: _summaryError!)
                else if (summary == null)
                  const Text(
                    'No hay resumen disponible para este rango.',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 11),
                  )
                else ...[
                  Text(
                    '${summary.count} cierres incluidos',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 5),
                  _buildMetricsGrid(
                    _getResponsiveColumnCount(panelConstraints.maxWidth),
                    summary.totals,
                  ),
                  const SizedBox(height: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: moneyAvailable
                            ? const Color(0xFFD1FAE5)
                            : const Color(0xFFFECACA),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          moneyAvailable
                              ? 'Dinero disponible para depósito'
                              : 'Dinero no disponible para depósito',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: moneyAvailable
                                ? const Color(0xFF065F46)
                                : const Color(0xFF991B1B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          availabilityReason,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 10.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Efectivo: ${_money(summary.availableForDeposit.cash)} · Transferencias: ${_money(summary.availableForDeposit.transfers)} · Total: ${_money(summary.availableForDeposit.total)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFDBEAFE)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Dinero depositado',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1E3A8A),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Total: ${_money(summary.totals.deposited)} · Último: ${summary.depositStatus.lastDepositDate == null ? 'N/D' : _dateOnly(summary.depositStatus.lastDepositDate!)} · Banco: ${summary.depositStatus.destinationBank ?? 'N/D'} · Estado: ${_depositStatusLabel(summary.depositStatus.status)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Transferencias por banco',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  ...summary.transfersByBank.map(
                    (row) => Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              row.bank,
                              style: const TextStyle(fontSize: 10.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            _money(row.amount),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                if (compact) const SizedBox(height: 4),
              ],
            );

            return SingleChildScrollView(child: content);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cierresDiariosControllerProvider);
    final canDelete = _isAdmin;
    final filtered = state.closes.where((close) {
      if (_selectedType != null && close.type != _selectedType) return false;
      if (!_matchesAdminStatusFilter(close)) return false;
      return _isWithinRange(close);
    }).toList();

    final pairedFiltered = [...filtered]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final visibleIds = pairedFiltered.map((e) => e.id).toSet();
    if (_selectedCloseIds.any((id) => !visibleIds.contains(id))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selectedCloseIds.removeWhere((id) => !visibleIds.contains(id));
          if (_selectedCloseIds.isEmpty) {
            _selectionMode = false;
          }
        });
      });
    }

    Widget historyFilters() {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final range = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2024),
                        lastDate: DateTime(2100),
                        initialDateRange: DateTimeRange(
                          start: _fromDate ?? DateTime.now(),
                          end: _toDate ?? DateTime.now(),
                        ),
                      );
                      if (range == null) return;
                      setState(() {
                        _fromDate = range.start;
                        _toDate = range.end;
                      });
                    },
                    icon: const Icon(Icons.date_range_outlined),
                    label: Text(
                      _fromDate == null || _toDate == null
                          ? 'Elegir rango'
                          : '${_dateOnly(_fromDate!)} - ${_dateOnly(_toDate!)}',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_fromDate != null || _toDate != null)
                  TextButton(
                    onPressed: () => setState(() {
                      _fromDate = null;
                      _toDate = null;
                    }),
                    child: const Text('Limpiar'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                  label: const Text('Todas'),
                  selected: _selectedType == null,
                  onSelected: (_) => setState(() => _selectedType = null),
                ),
                FilterChip(
                  label: const Text('Tecnología'),
                  selected: _selectedType == CloseType.tienda,
                  onSelected: (_) =>
                      setState(() => _selectedType = CloseType.tienda),
                ),
                FilterChip(
                  label: const Text('PhytoEmagry'),
                  selected: _selectedType == CloseType.phytoemagry,
                  onSelected: (_) =>
                      setState(() => _selectedType = CloseType.phytoemagry),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedStatus,
                    decoration: const InputDecoration(labelText: 'Estado'),
                    items:
                        const [
                              'TODOS',
                              'pending',
                              'approved',
                              'rejected',
                              'corrections',
                            ]
                            .map(
                              (value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(
                                  _adminFilterLabel(value),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _selectedStatus = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${pairedFiltered.length} registros',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ],
        ),
      );
    }

    Widget historyList() {
      if (pairedFiltered.isEmpty) {
        return const Center(
          child: Text('No hay cierres para el filtro seleccionado.'),
        );
      }

      final byDay = <DateTime, List<CloseModel>>{};
      for (final close in pairedFiltered) {
        final day = DateTime(close.date.year, close.date.month, close.date.day);
        byDay.putIfAbsent(day, () => <CloseModel>[]).add(close);
      }

      final orderedDays = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

      int typeRank(CloseType type) {
        if (type == CloseType.tienda) return 0;
        if (type == CloseType.phytoemagry) return 1;
        return 2;
      }

      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
        itemCount: orderedDays.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final day = orderedDays[index];
          final closes = [...(byDay[day] ?? const <CloseModel>[])]
            ..sort((a, b) {
              final typeCompare = typeRank(a.type).compareTo(typeRank(b.type));
              if (typeCompare != 0) return typeCompare;
              return b.createdAt.compareTo(a.createdAt);
            });
          final hasTecnologia = closes.any(
            (close) => close.type == CloseType.tienda,
          );
          final hasPhyto = closes.any(
            (close) => close.type == CloseType.phytoemagry,
          );
          final pairComplete = hasTecnologia && hasPhyto;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Theme.of(context).colorScheme.surface,
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        DateFormat('dd/MM/yyyy').format(day),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    _MiniCloseTag(
                      label: pairComplete ? 'Par completo' : 'Par incompleto',
                      color: pairComplete
                          ? const Color(0xFF15803D)
                          : const Color(0xFFB45309),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...closes.asMap().entries.map((entry) {
                  final close = entry.value;
                  final statusLabel = _adminStatusLabel(close);
                  final statusColor = _adminStatusColor(close);

                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: entry.key == closes.length - 1 ? 0 : 8,
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () async {
                          if (_selectionMode) {
                            setState(() {
                              if (_selectedCloseIds.contains(close.id)) {
                                _selectedCloseIds.remove(close.id);
                              } else {
                                _selectedCloseIds.add(close.id);
                              }
                            });
                            return;
                          }

                          final duplicate = await Navigator.of(context)
                              .push<CloseModel>(
                                MaterialPageRoute(
                                  builder: (_) => _CloseDetailFullScreenPage(
                                    closeId: close.id,
                                  ),
                                ),
                              );
                          if (duplicate != null && context.mounted) {
                            Navigator.of(context).pop(duplicate);
                          }
                        },
                        child: Ink(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: close.isPending
                                ? const Color(0xFFFFFBEB)
                                : Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.26),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: close.isPending
                                  ? const Color(
                                      0xFFF59E0B,
                                    ).withValues(alpha: 0.42)
                                  : Theme.of(
                                      context,
                                    ).colorScheme.outlineVariant,
                            ),
                          ),
                          child: Row(
                            children: [
                              if (_selectionMode)
                                Checkbox(
                                  value: _selectedCloseIds.contains(close.id),
                                  onChanged: (_) {
                                    setState(() {
                                      if (_selectedCloseIds.contains(
                                        close.id,
                                      )) {
                                        _selectedCloseIds.remove(close.id);
                                      } else {
                                        _selectedCloseIds.add(close.id);
                                      }
                                    });
                                  },
                                ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            close.type == CloseType.tienda
                                                ? 'Tecnología'
                                                : close.type.label,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            const Text(
                                              'Fondo de caja',
                                              style: TextStyle(
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                            Text(
                                              _money(close.cashDelivered),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 13.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    Wrap(
                                      spacing: 7,
                                      runSpacing: 5,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          'Creado por ${close.createdByName ?? close.createdById ?? 'N/D'}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                        if (close.isCorrection)
                                          _MiniCloseTag(
                                            label:
                                                'Corrección #${_shortCloseId(close.correctionOfCloseId)}',
                                            color: const Color(0xFF7C3AED),
                                          ),
                                        if ((close.reviewNote ?? '')
                                                .trim()
                                                .isNotEmpty &&
                                            close.isRejected)
                                          const _MiniCloseTag(
                                            label: 'Con motivo',
                                            color: Color(0xFFB91C1C),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: statusColor.withValues(alpha: 0.12),
                                  border: Border.all(
                                    color: statusColor.withValues(alpha: 0.28),
                                  ),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                              if (!_selectionMode && canDelete) ...[
                                const SizedBox(width: 8),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Depositado',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF64748B),
                                      ),
                                    ),
                                    Switch.adaptive(
                                      value: close.cashDeposited,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      onChanged: state.saving
                                          ? null
                                          : (value) => _toggleCashDeposited(
                                              close,
                                              value,
                                            ),
                                    ),
                                  ],
                                ),
                              ],
                              if (!_selectionMode &&
                                  canDelete &&
                                  close.isPending) ...[
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.rate_review_outlined,
                                  size: 18,
                                ),
                              ],
                              if (!_selectionMode && canDelete)
                                IconButton(
                                  tooltip: 'Eliminar cierre',
                                  onPressed: () => _deleteOneClose(close),
                                  icon: const Icon(Icons.delete_outline),
                                )
                              else if (!_selectionMode) ...[
                                const SizedBox(width: 8),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectionMode
              ? 'Seleccionados (${_selectedCloseIds.length})'
              : 'Historial de cierres diarios',
        ),
        actions: [
          if (canDelete && !_selectionMode)
            IconButton(
              tooltip: 'Seleccion multiple',
              onPressed: filtered.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _selectionMode = true;
                        _selectedCloseIds.clear();
                      });
                    },
              icon: const Icon(Icons.checklist_outlined),
            ),
          if (canDelete && _selectionMode)
            IconButton(
              tooltip: 'Eliminar seleccionados',
              onPressed: _selectedCloseIds.isEmpty || _deletingSelection
                  ? null
                  : _deleteSelectedCloses,
              icon: _deletingSelection
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_sweep_outlined),
            ),
          if (canDelete && _selectionMode)
            IconButton(
              tooltip: 'Cancelar seleccion',
              onPressed: () {
                setState(() {
                  _selectionMode = false;
                  _selectedCloseIds.clear();
                });
              },
              icon: const Icon(Icons.close),
            ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () async {
              await ref
                  .read(cierresDiariosControllerProvider.notifier)
                  .refresh();
              if (canDelete) {
                await _fetchSummary();
              }
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.loading) const LinearProgressIndicator(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final showSidePanel = canDelete && constraints.maxWidth >= 1240;

                if (showSidePanel) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              historyFilters(),
                              Expanded(child: historyList()),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 560,
                          child: Column(
                            children: [
                              _buildFilteredClosesPanel(pairedFiltered),
                              const SizedBox(height: 12),
                              Expanded(
                                child: _buildSummaryPanel(compact: false),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return Column(
                  children: [
                    historyFilters(),
                    if (canDelete)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          collapsedShape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          title: const Text(
                            'Resumen financiero (Admin)',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    _buildFilteredClosesPanel(pairedFiltered),
                                    const SizedBox(height: 10),
                                    _buildSummaryPanel(compact: true),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(child: historyList()),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CloseDetailFullScreenPage extends ConsumerStatefulWidget {
  final String closeId;

  const _CloseDetailFullScreenPage({required this.closeId});

  @override
  ConsumerState<_CloseDetailFullScreenPage> createState() =>
      _CloseDetailFullScreenPageState();
}

class _CloseDetailFullScreenPageState
    extends ConsumerState<_CloseDetailFullScreenPage> {
  bool _runningAi = false;
  bool _exportingPdf = false;
  bool _deletingClose = false;
  String _aiStep = '';

  String _money(double value) => _formatAccountingMoney(value);

  String _shortCloseId(String? id) {
    final value = (id ?? '').trim();
    if (value.isEmpty) return 'N/D';
    return value.length <= 8 ? value : value.substring(0, 8);
  }

  List<String> _asStringList(dynamic value) {
    if (value is List) {
      return value
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    }
    final asText = value?.toString().trim() ?? '';
    return asText.isEmpty ? const [] : [asText];
  }

  bool _isImageVoucher(CloseTransferVoucherModel voucher) {
    return _isCloseVoucherImage(voucher);
  }

  String _normalizeAssetUrl(String raw) => _resolveContabilidadAssetUrl(raw);

  Future<String?> _askAdminPassword() async {
    final ctrl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar eliminacion'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Contrasena de administrador',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    final cleaned = (value ?? '').trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  Future<void> _deleteCurrentClose(CloseModel close) async {
    if (_deletingClose) return;
    final password = await _askAdminPassword();
    if (!mounted || password == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cierre'),
        content: const Text(
          'Este cierre se eliminara definitivamente. Esta accion no se puede deshacer.',
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

    setState(() => _deletingClose = true);
    try {
      await ref
          .read(cierresDiariosControllerProvider.notifier)
          .deleteClose(close.id, adminPassword: password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cierre eliminado correctamente.')),
      );
      Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _deletingClose = false);
    }
  }

  Future<void> _exportPdf(CloseModel close) async {
    if (_exportingPdf) return;
    final rawUrl = _normalizeAssetUrl(close.pdfUrl ?? '');
    if (rawUrl.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este cierre aun no tiene PDF disponible para exportar.',
          ),
        ),
      );
      return;
    }

    setState(() => _exportingPdf = true);
    try {
      final bytes = await ref
          .read(contabilidadRepositoryProvider)
          .downloadClosePdfBytes(rawUrl);
      final fileName = (close.pdfFileName ?? '').trim().isNotEmpty
          ? close.pdfFileName!
          : 'cierre-${DateFormat('yyyy-MM-dd').format(close.date)}.pdf';
      final saved = await savePdfBytes(bytes: bytes, fileName: fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved
                ? 'PDF exportado correctamente.'
                : 'Exportacion cancelada por el usuario.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo exportar el PDF: $e')));
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _runAiReport(CloseModel close) async {
    if (_runningAi) return;
    setState(() {
      _runningAi = true;
      _aiStep = 'Preparando contexto contable...';
    });
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() {
      _aiStep =
          'Analizando diferencia contra gastos, ingresos y comprobantes...';
    });
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() {
      _aiStep = 'Generando reporte IA y guardando resultado...';
    });
    try {
      await ref
          .read(cierresDiariosControllerProvider.notifier)
          .generateAiReport(close.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe IA generado correctamente.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _runningAi = false;
          _aiStep = '';
        });
      }
    }
  }

  Future<void> _askApproveReject({
    required CloseModel close,
    required bool approve,
  }) async {
    final ctrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Aprobar cierre' : 'Rechazar cierre'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: approve ? 'Nota de revisión' : 'Motivo de rechazo *',
              alignLabelWithHint: true,
            ),
            validator: (value) {
              if (approve) return null;
              return (value ?? '').trim().isEmpty
                  ? 'El motivo de rechazo es obligatorio'
                  : null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (!approve && !formKey.currentState!.validate()) return;
              Navigator.pop(context, ctrl.text.trim());
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (note == null) return;
    final controller = ref.read(cierresDiariosControllerProvider.notifier);
    if (approve) {
      await controller.approveClose(close.id, reviewNote: note);
    } else {
      await controller.rejectClose(close.id, reviewNote: note);
    }
    if (!mounted) return;
    final error = ref.read(cierresDiariosControllerProvider).error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ?? (approve ? 'Cierre aprobado.' : 'Cierre rechazado.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(cierresDiariosControllerProvider);
    CloseModel? close;
    for (final item in state.closes) {
      if (item.id == widget.closeId) {
        close = item;
        break;
      }
    }
    final role = ref.watch(authStateProvider).user?.role;
    final canAdmin = parseAppRole(role).isAdmin;
    final canReview = canAdmin;
    final canDelete = canAdmin;

    if (close == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detalle de cierre')),
        body: const Center(
          child: Text('No se encontró el cierre seleccionado.'),
        ),
      );
    }
    final currentClose = close;
    final statusLabel = switch (currentClose.status) {
      'approved' => 'Aprobado',
      'rejected' => 'Rechazado',
      _ => 'Pendiente',
    };

    if (!canAdmin) {
      return _AssistantCloseDetailScaffold(
        close: currentClose,
        statusLabel: statusLabel,
      );
    }

    final posVoucher = CloseTransferVoucherModel(
      storageKey: currentClose.evidenceStorageKey ?? '',
      fileUrl: _normalizeAssetUrl(currentClose.evidenceUrl ?? ''),
      fileName: currentClose.evidenceFileName ?? '',
      mimeType: currentClose.evidenceMimeType ?? '',
    );
    final posVoucherIsImage = _isImageVoucher(posVoucher);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Detalle · ${currentClose.type.label} · ${DateFormat('dd/MM/yyyy').format(currentClose.date)}',
        ),
        actions: [
          if (currentClose.isRejected)
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(currentClose),
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Duplicar'),
            ),
          if (canDelete)
            IconButton(
              tooltip: 'Eliminar cierre',
              onPressed: _deletingClose
                  ? null
                  : () => _deleteCurrentClose(currentClose),
              icon: _deletingClose
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
            ),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: currentClose.isPending && canReview
          ? FloatingActionButton.extended(
              tooltip: 'Aprobar o rechazar cierre',
              backgroundColor: AppTheme.primaryColor,
              onPressed: () => _showApproveFab(currentClose),
              icon: const Icon(Icons.done_all_outlined),
              label: const Text('Gestionar'),
            )
          : null,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final showSidePanel = constraints.maxWidth >= 1240;

          if (showSidePanel) {
            // IA column (left, fixed 340px)
            final iaColumn = SizedBox(
              width: 340,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Análisis IA',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _runningAi
                                  ? null
                                  : () => _runAiReport(currentClose),
                              icon: const Icon(Icons.auto_awesome_outlined),
                              label: const Text('Generar'),
                            ),
                          ),
                        ],
                      ),
                      if (_runningAi) ...[
                        const SizedBox(height: 10),
                        LinearProgressIndicator(
                          color: AppTheme.primaryColor,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _aiStep,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                      if ((currentClose.aiReportSummary ?? '')
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _InfoPill(
                          label: 'Riesgo',
                          value: (currentClose.aiRiskLevel ?? 'N/D')
                              .toUpperCase(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          currentClose.aiReportSummary!.trim(),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if ((currentClose.aiReportJson ?? const {})
                            .isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Builder(
                            builder: (context) {
                              final report =
                                  currentClose.aiReportJson ?? const {};
                              final detectedIssues = _asStringList(
                                report['detectedIssues'] ??
                                    report['detected_issues'],
                              );
                              final suggestedActions = _asStringList(
                                report['suggestedAdminActions'] ??
                                    report['suggested_admin_actions'],
                              );
                              final fraudSignals = _asStringList(
                                report['fraudSignals'] ??
                                    report['fraud_signals'],
                              );
                              final auditorNotes = _asStringList(
                                report['auditorNotes'] ??
                                    report['auditor_notes'],
                              );
                              final financialBreakdown =
                                  report['financialBreakdown']
                                      as Map<String, dynamic>?;

                              Widget sectionTitle(String title) => Padding(
                                padding: const EdgeInsets.only(
                                  top: 8,
                                  bottom: 6,
                                ),
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11,
                                  ),
                                ),
                              );

                              Widget bulletList(
                                List<String> rows, {
                                String empty = 'N/D',
                              }) {
                                if (rows.isEmpty) {
                                  return Text(
                                    empty,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  );
                                }
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: rows
                                      .map(
                                        (row) => Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 4,
                                          ),
                                          child: Text(
                                            '• $row',
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                );
                              }

                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outlineVariant,
                                  ),
                                  color: Theme.of(context).colorScheme.surface,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    sectionTitle('Evaluación'),
                                    if (financialBreakdown != null) ...[
                                      Text(
                                        'Dif: ${financialBreakdown['difference'] ?? currentClose.difference}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ] else
                                      Text(
                                        'Dif: ${currentClose.difference}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    sectionTitle('Problemas'),
                                    bulletList(
                                      detectedIssues,
                                      empty: 'Sin alertas.',
                                    ),
                                    sectionTitle('Fraude'),
                                    bulletList(
                                      fraudSignals,
                                      empty: 'No detectado.',
                                    ),
                                    sectionTitle('Acciones'),
                                    bulletList(suggestedActions, empty: 'N/A'),
                                    sectionTitle('Notas'),
                                    bulletList(auditorNotes, empty: 'N/A'),
                                  ],
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 10),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text(
                              'Ver JSON',
                              style: TextStyle(fontSize: 11),
                            ),
                            children: [
                              SelectableText(
                                const JsonEncoder.withIndent(
                                  '  ',
                                ).convert(currentClose.aiReportJson),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            );

            // Center column (scrollable, all details)
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                iaColumn,
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _InfoPill(label: 'Estado', value: statusLabel),
                          _InfoPill(
                            label: 'Creado por',
                            value:
                                currentClose.createdByName ??
                                currentClose.createdById ??
                                'N/D',
                          ),
                          _InfoPill(
                            label: 'Creado en',
                            value: DateFormat(
                              'dd/MM/yyyy h:mm a',
                              'es_DO',
                            ).format(currentClose.createdAt),
                          ),
                          if (currentClose.reviewedAt != null)
                            _InfoPill(
                              label: 'Revisado en',
                              value: DateFormat(
                                'dd/MM/yyyy h:mm a',
                                'es_DO',
                              ).format(currentClose.reviewedAt!),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (currentClose.isCorrection ||
                          currentClose.isRejected) ...[
                        if (currentClose.isCorrection)
                          _RawHistoryField(
                            label: 'Corrección de cierre',
                            value:
                                '#${_shortCloseId(currentClose.correctionOfCloseId)}',
                          ),
                        if (currentClose.isRejected)
                          _RawHistoryField(
                            label: 'Motivo de rechazo',
                            value:
                                (currentClose.reviewNote ?? '')
                                    .trim()
                                    .isNotEmpty
                                ? currentClose.reviewNote!.trim()
                                : 'Sin motivo registrado',
                          ),
                        if ((currentClose.correctionReason ?? '')
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _DialogTextBlock(
                            label: 'Motivo de corrección',
                            value: currentClose.correctionReason!.trim(),
                          ),
                        ],
                        const SizedBox(height: 14),
                      ],
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Desglose del cierre',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _DetailAmountLine(
                              label: 'Efectivo declarado',
                              value: _money(currentClose.cash),
                            ),
                            _DetailAmountLine(
                              label: 'Total transferido',
                              value: _money(currentClose.transfer),
                            ),
                            _DetailAmountLine(
                              label: 'Tarjeta',
                              value: _money(currentClose.card),
                            ),
                            _DetailAmountLine(
                              label: 'Otros ingresos',
                              value: _money(currentClose.otherIncome),
                            ),
                            _DetailAmountLine(
                              label: 'Gastos detallados',
                              value: _money(currentClose.expenses),
                            ),
                            _DetailAmountLine(
                              label: 'Fondo de caja',
                              value: _money(currentClose.cashDelivered),
                            ),
                            _DetailAmountLine(
                              label: 'Total ingresos',
                              value: _money(currentClose.incomeTotal),
                            ),
                            _DetailAmountLine(
                              label: 'Total neto',
                              value: _money(currentClose.netTotal),
                            ),
                            _DetailAmountLine(
                              label: 'Diferencia',
                              value: _money(currentClose.difference),
                              emphasize: currentClose.difference != 0,
                              showDivider: false,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      // Voucher POS
                      if (currentClose.evidenceUrl != null &&
                          currentClose.evidenceFileName != null) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Voucher POS',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                  color: Theme.of(context).colorScheme.surface,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      if (posVoucherIsImage)
                                        InkWell(
                                          onTap: () =>
                                              _showVoucherPreviewDialog(
                                                context,
                                                posVoucher,
                                              ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            child: SizedBox(
                                              width: 88,
                                              height: 68,
                                              child: Image.network(
                                                _normalizeAssetUrl(
                                                  currentClose.evidenceUrl!,
                                                ),
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    Container(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .surfaceContainerHighest,
                                                      alignment:
                                                          Alignment.center,
                                                      child: const Icon(
                                                        Icons
                                                            .broken_image_outlined,
                                                      ),
                                                    ),
                                              ),
                                            ),
                                          ),
                                        )
                                      else
                                        Container(
                                          width: 56,
                                          height: 56,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                          ),
                                          alignment: Alignment.center,
                                          child: const Icon(
                                            Icons.picture_as_pdf_outlined,
                                          ),
                                        ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              currentClose.evidenceFileName!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 11,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              posVoucherIsImage
                                                  ? 'Vista previa.'
                                                  : 'Archivo adjunto.',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    fontSize: 10,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            _showVoucherPreviewDialog(
                                              context,
                                              posVoucher,
                                            ),
                                        icon: const Icon(
                                          Icons.fullscreen_outlined,
                                          size: 16,
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 10,
                                          ),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        label: const Text('Ver'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      // Gastos
                      if (currentClose.expenseDetails.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Gastos',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ...currentClose.expenseDetails.asMap().entries.map((
                                entry,
                              ) {
                                final idx = entry.key;
                                final row = entry.value;
                                final concept = (row['concept'] as String?)
                                    ?.trim();
                                final amount =
                                    (row['amount'] as num?)?.toDouble() ?? 0;
                                final vouchers =
                                    ((row['vouchers'] as List?) ?? const [])
                                        .whereType<Map>()
                                        .map(
                                          (v) =>
                                              CloseTransferVoucherModel.fromJson(
                                                v.cast<String, dynamic>(),
                                              ),
                                        )
                                        .map(
                                          (v) => CloseTransferVoucherModel(
                                            storageKey: v.storageKey,
                                            fileUrl: _normalizeAssetUrl(
                                              v.fileUrl,
                                            ),
                                            fileName: v.fileName,
                                            mimeType: v.mimeType,
                                          ),
                                        )
                                        .toList();
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (idx > 0) const Divider(height: 1),
                                    ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 8,
                                          ),
                                      title: Text(
                                        concept?.isNotEmpty == true
                                            ? concept!
                                            : 'Sin concepto',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 11,
                                        ),
                                      ),
                                      trailing: Text(
                                        _money(amount),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                    if (vouchers.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                        child: Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: vouchers
                                              .map(
                                                (v) => InkWell(
                                                  onTap: () =>
                                                      _showVoucherPreviewDialog(
                                                        context,
                                                        v,
                                                      ),
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                    child: SizedBox(
                                                      width: 56,
                                                      height: 56,
                                                      child:
                                                          v.mimeType.startsWith(
                                                            'image/',
                                                          )
                                                          ? Image.network(
                                                              v.fileUrl,
                                                              fit: BoxFit.cover,
                                                              errorBuilder: (_, __, ___) => Container(
                                                                color: Theme.of(context)
                                                                    .colorScheme
                                                                    .surfaceContainerHighest,
                                                                alignment:
                                                                    Alignment
                                                                        .center,
                                                                child: const Icon(
                                                                  Icons
                                                                      .picture_as_pdf_outlined,
                                                                  size: 20,
                                                                ),
                                                              ),
                                                            )
                                                          : Container(
                                                              color: Theme.of(context)
                                                                  .colorScheme
                                                                  .surfaceContainerHighest,
                                                              alignment:
                                                                  Alignment
                                                                      .center,
                                                              child: const Icon(
                                                                Icons
                                                                    .picture_as_pdf_outlined,
                                                                size: 20,
                                                              ),
                                                            ),
                                                    ),
                                                  ),
                                                ),
                                              )
                                              .toList(),
                                        ),
                                      ),
                                  ],
                                );
                              }),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      // Transferencias
                      if (currentClose.transfers.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Transferencias',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ...currentClose.transfers.asMap().entries.map((
                                entry,
                              ) {
                                final transfer = entry.value;
                                final imageVouchers = transfer.vouchers
                                    .where(_isImageVoucher)
                                    .map(
                                      (v) => CloseTransferVoucherModel(
                                        storageKey: v.storageKey,
                                        fileUrl: _normalizeAssetUrl(v.fileUrl),
                                        fileName: v.fileName,
                                        mimeType: v.mimeType,
                                      ),
                                    )
                                    .toList();
                                final fileVouchers = transfer.vouchers
                                    .where((v) => !_isImageVoucher(v))
                                    .map(
                                      (v) => CloseTransferVoucherModel(
                                        storageKey: v.storageKey,
                                        fileUrl: _normalizeAssetUrl(v.fileUrl),
                                        fileName: v.fileName,
                                        mimeType: v.mimeType,
                                      ),
                                    )
                                    .toList();
                                return ExpansionTile(
                                  initiallyExpanded: true,
                                  tilePadding: const EdgeInsets.symmetric(
                                    horizontal: 0,
                                    vertical: 4,
                                  ),
                                  title: Text(
                                    '${entry.key + 1}. ${transfer.bankName} · ${_money(transfer.amount)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                  subtitle:
                                      [
                                        if ((transfer.referenceNumber ?? '')
                                            .trim()
                                            .isNotEmpty)
                                          'Ref: ${transfer.referenceNumber}',
                                        if ((transfer.note ?? '')
                                            .trim()
                                            .isNotEmpty)
                                          transfer.note!.trim(),
                                      ].join(' · ').isEmpty
                                      ? null
                                      : Text(
                                          [
                                            if ((transfer.referenceNumber ?? '')
                                                .trim()
                                                .isNotEmpty)
                                              'Ref: ${transfer.referenceNumber}',
                                            if ((transfer.note ?? '')
                                                .trim()
                                                .isNotEmpty)
                                              transfer.note!.trim(),
                                          ].join(' · '),
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                  children: [
                                    if (fileVouchers.isNotEmpty)
                                      ...fileVouchers.map(
                                        (v) => ListTile(
                                          dense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 8,
                                              ),
                                          leading: const Icon(
                                            Icons.picture_as_pdf_outlined,
                                            size: 18,
                                          ),
                                          title: Text(
                                            v.fileName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 10,
                                            ),
                                          ),
                                          trailing: SizedBox(
                                            width: 50,
                                            child: OutlinedButton(
                                              onPressed: () =>
                                                  _showVoucherPreviewDialog(
                                                    context,
                                                    v,
                                                  ),
                                              style: OutlinedButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                      vertical: 2,
                                                    ),
                                                visualDensity:
                                                    VisualDensity.compact,
                                              ),
                                              child: const Text(
                                                'Ver',
                                                style: TextStyle(fontSize: 9),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (imageVouchers.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              imageVouchers.length == 1
                                                  ? '1 comprobante visual'
                                                  : '${imageVouchers.length} comprobantes visuales',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 6,
                                              children: imageVouchers
                                                  .map(
                                                    (v) => InkWell(
                                                      onTap: () =>
                                                          _showVoucherPreviewDialog(
                                                            context,
                                                            v,
                                                          ),
                                                      child: ClipRRect(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                        child: SizedBox(
                                                          width: 50,
                                                          height: 50,
                                                          child: Image.network(
                                                            v.fileUrl,
                                                            fit: BoxFit.cover,
                                                            errorBuilder:
                                                                (
                                                                  _,
                                                                  __,
                                                                  ___,
                                                                ) => Container(
                                                                  color: Theme.of(
                                                                    context,
                                                                  ).colorScheme.surfaceContainerHighest,
                                                                  alignment:
                                                                      Alignment
                                                                          .center,
                                                                  child: const Icon(
                                                                    Icons
                                                                        .broken_image_outlined,
                                                                    size: 16,
                                                                  ),
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  )
                                                  .toList(),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                );
                              }),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      // Notas
                      if ((currentClose.notes ?? '').trim().isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Notas',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                currentClose.notes!.trim(),
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 600,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(0, 14, 14, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Historial / Movimientos
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'Historial del cierre',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.add_task_outlined,
                                  size: 18,
                                ),
                                title: const Text(
                                  'Creación del cierre',
                                  style: TextStyle(fontSize: 11),
                                ),
                                subtitle: Text(
                                  '${DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(currentClose.createdAt)} · ${currentClose.createdByName ?? currentClose.createdById ?? 'N/D'}',
                                  style: const TextStyle(fontSize: 10),
                                ),
                              ),
                              if (currentClose.aiGeneratedAt != null)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.auto_awesome_outlined,
                                    size: 18,
                                  ),
                                  title: const Text(
                                    'Informe IA generado',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  subtitle: Text(
                                    DateFormat(
                                      'dd/MM/yyyy h:mm a',
                                      'es_DO',
                                    ).format(currentClose.aiGeneratedAt!),
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ),
                              if (currentClose.reviewedAt != null)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.verified_outlined,
                                    size: 18,
                                  ),
                                  title: Text(
                                    'Revisión: $statusLabel',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  subtitle: Text(
                                    '${DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(currentClose.reviewedAt!)} · ${currentClose.reviewedByName ?? currentClose.reviewedById ?? 'N/D'}',
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ),
                              if ((currentClose.notificationStatus ?? '')
                                  .trim()
                                  .isNotEmpty)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(
                                    Icons.notifications_active_outlined,
                                    size: 18,
                                  ),
                                  title: const Text(
                                    'Notificación a admins',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  subtitle: Text(
                                    'Estado: ${currentClose.notificationStatus} ${((currentClose.notificationError ?? '').trim().isNotEmpty) ? '· ${currentClose.notificationError}' : ''}',
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        // PDF
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                'PDF del cierre',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 10),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(
                                  Icons.picture_as_pdf_outlined,
                                ),
                                title: Text(
                                  (currentClose.pdfFileName ?? '')
                                          .trim()
                                          .isNotEmpty
                                      ? currentClose.pdfFileName!
                                      : 'PDF de cierre',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                subtitle: Text(
                                  (currentClose.pdfUrl ?? '').trim().isNotEmpty
                                      ? 'Disponible para exportar o revisar.'
                                      : 'Aún no disponible',
                                  style: const TextStyle(fontSize: 10),
                                ),
                                trailing: FilledButton.icon(
                                  onPressed: _exportingPdf
                                      ? null
                                      : () => _exportPdf(currentClose),
                                  icon: _exportingPdf
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.download_outlined),
                                  label: const Text('Exportar'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                  child: _buildCloseSummaryPanel(currentClose, statusLabel),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCloseSummaryPanel(CloseModel close, String statusLabel) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Resumen del cierre',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoPill(label: 'Estado', value: statusLabel),
              _InfoPill(
                label: 'Creado por',
                value: close.createdByName ?? close.createdById ?? 'N/D',
              ),
              _InfoPill(
                label: 'Creado en',
                value: DateFormat(
                  'dd/MM/yyyy h:mm a',
                  'es_DO',
                ).format(close.createdAt),
              ),
              if (close.reviewedAt != null)
                _InfoPill(
                  label: 'Revisado en',
                  value: DateFormat(
                    'dd/MM/yyyy h:mm a',
                    'es_DO',
                  ).format(close.reviewedAt!),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),
          const Text(
            'Montos',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
          const SizedBox(height: 8),
          _buildCompactMoneyRow('Total ingresos', _money(close.incomeTotal)),
          _buildCompactMoneyRow('Total neto', _money(close.netTotal)),
          _buildCompactMoneyRow(
            'Diferencia',
            _money(close.difference),
            isNegative: close.difference < -0.009,
          ),
          const SizedBox(height: 10),
          const Text(
            'Desglose de pagos',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
          const SizedBox(height: 8),
          _buildCompactMoneyRow('Efectivo', _money(close.cash)),
          _buildCompactMoneyRow('Transferencia', _money(close.transfer)),
          _buildCompactMoneyRow('Tarjeta', _money(close.card)),
          _buildCompactMoneyRow('Otros ingresos', _money(close.otherIncome)),
          _buildCompactMoneyRow(
            'Gastos',
            _money(close.expenses),
            isNegative: true,
          ),
          const SizedBox(height: 10),
          const Text(
            'Fondo de caja',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Text(
              _money(close.cashDelivered),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                color: Color(0xFF047857),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactMoneyRow(
    String label,
    String value, {
    bool isNegative = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: isNegative ? const Color(0xFFB91C1C) : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showApproveFab(CloseModel close) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gestionar cierre'),
        content: const Text('¿Qué acción deseas realizar con este cierre?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Rechazar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aprobar'),
          ),
        ],
      ),
    );
    if (approved == null) return;
    if (!mounted) return;
    await _askApproveReject(close: close, approve: approved);
  }
}

class _AssistantCloseDetailScaffold extends StatelessWidget {
  const _AssistantCloseDetailScaffold({
    required this.close,
    required this.statusLabel,
  });

  final CloseModel close;
  final String statusLabel;

  String _money(double value) => _formatAccountingMoney(value);

  String _referenceLabel(CloseModel close) {
    final id = (close.correctionOfCloseId ?? '').trim();
    if (id.isEmpty) return 'N/D';
    return id.length <= 8 ? id : id.substring(0, 8);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de cierre')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionTitle(title: 'Registro crudo'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    _RawHistoryField(
                      label: 'Fecha',
                      value: DateFormat('dd/MM/yyyy').format(close.date),
                    ),
                    _RawHistoryField(
                      label: 'Categoría',
                      value: close.type.label,
                    ),
                    _RawHistoryField(
                      label: 'Monto',
                      value: _money(close.netTotal),
                    ),
                    _RawHistoryField(label: 'Estado', value: statusLabel),
                    _RawHistoryField(
                      label: 'Tipo de registro',
                      value: close.isCorrection ? 'Corrección' : 'Normal',
                    ),
                    if (close.isCorrection) ...[
                      _RawHistoryField(
                        label: 'Corrige cierre',
                        value: _referenceLabel(close),
                      ),
                      _RawHistoryField(
                        label: 'Motivo',
                        value: close.correctionReason ?? 'N/D',
                      ),
                    ],
                    _RawHistoryField(
                      label: 'Creado por',
                      value: close.createdByName ?? close.createdById ?? 'N/D',
                    ),
                    _RawHistoryField(
                      label: 'Fecha de creación',
                      value: DateFormat(
                        'dd/MM/yyyy h:mm a',
                        'es_DO',
                      ).format(close.createdAt),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _showVoucherPreviewDialog(
  BuildContext context,
  CloseTransferVoucherModel voucher,
) {
  final fileUrl = _resolveContabilidadAssetUrl(voucher.fileUrl);
  final isImage = _isCloseVoucherImage(voucher);
  showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 700),
        child: Column(
          children: [
            ListTile(
              title: Text(voucher.fileName),
              subtitle: Text(voucher.mimeType),
              trailing: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            Expanded(
              child: isImage
                  ? InteractiveViewer(
                      child: Image.network(
                        fileUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Text('No se pudo cargar la imagen.'),
                          );
                        },
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(18),
                      child: SelectableText(fileUrl),
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MoneyPill extends StatelessWidget {
  final String label;
  final String value;

  const _MoneyPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _UnitChipButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  const _UnitChipButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 34),
        backgroundColor: selected ? AppTheme.primaryColor : Colors.white,
        foregroundColor: selected ? Colors.white : AppTheme.primaryColor,
        disabledForegroundColor: selected
            ? Colors.white
            : AppTheme.primaryColor.withValues(alpha: 0.55),
        side: BorderSide(
          color: selected
              ? AppTheme.primaryColor
              : AppTheme.primaryColor.withValues(alpha: 0.45),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
      ),
      child: Text(label, textAlign: TextAlign.center, maxLines: 1),
    );
  }
}

class _TransferDraft {
  final bankCtrl = TextEditingController();
  final amountCtrl = TextEditingController(text: _formatAccountingAmount(0));
  final referenceCtrl = TextEditingController();
  final noteCtrl = TextEditingController();
  final List<CloseTransferVoucherModel> vouchers = [];
  bool uploading = false;

  _TransferDraft();

  factory _TransferDraft.fromModel(CloseTransferModel model) {
    final draft = _TransferDraft();
    draft.bankCtrl.text = model.bankName;
    draft.amountCtrl.text = _formatAccountingAmount(model.amount);
    draft.referenceCtrl.text = model.referenceNumber ?? '';
    draft.noteCtrl.text = model.note ?? '';
    draft.vouchers.addAll(model.vouchers);
    return draft;
  }

  void dispose() {
    bankCtrl.dispose();
    amountCtrl.dispose();
    referenceCtrl.dispose();
    noteCtrl.dispose();
  }
}

class _ExpenseDraft {
  final conceptCtrl = TextEditingController();
  final amountCtrl = TextEditingController(text: _formatAccountingAmount(0));
  final List<CloseTransferVoucherModel> vouchers = [];
  bool uploading = false;

  _ExpenseDraft({
    String concept = '',
    String amount = '0.00',
    List<CloseTransferVoucherModel> vouchers = const [],
  }) {
    conceptCtrl.text = concept;
    amountCtrl.text = amount;
    this.vouchers.addAll(vouchers);
  }

  void dispose() {
    conceptCtrl.dispose();
    amountCtrl.dispose();
  }
}

class _CloseVoucherInlinePreview extends StatelessWidget {
  const _CloseVoucherInlinePreview({
    required this.voucher,
    this.previewBytes,
    required this.onOpen,
    required this.onRemove,
  });

  final CloseTransferVoucherModel voucher;
  final Uint8List? previewBytes;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isImage = _isCloseVoucherImage(voucher);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 132,
        height: 96,
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
          color: theme.colorScheme.surface,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpen,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: isImage
                          ? _CloseVoucherImage(
                              voucher: voucher,
                              previewBytes: previewBytes,
                            )
                          : Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: const Icon(Icons.picture_as_pdf_outlined),
                            ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _VoucherRemoveButton(
                      tooltip: 'Quitar voucher POS',
                      onPressed: onRemove,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CloseVoucherCompactPreview extends StatelessWidget {
  const _CloseVoucherCompactPreview({
    required this.voucher,
    this.previewBytes,
    required this.onOpen,
    required this.onRemove,
  });

  final CloseTransferVoucherModel voucher;
  final Uint8List? previewBytes;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isImage = _isCloseVoucherImage(voucher);

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surface,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: isImage
                        ? _CloseVoucherImage(
                            voucher: voucher,
                            previewBytes: previewBytes,
                          )
                        : Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.picture_as_pdf_outlined,
                              size: 20,
                            ),
                          ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: _VoucherRemoveButton(
                    tooltip: 'Quitar comprobante',
                    onPressed: onRemove,
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

class _VoucherRemoveButton extends StatelessWidget {
  const _VoucherRemoveButton({required this.tooltip, required this.onPressed});

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 26,
      child: IconButton.filled(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        tooltip: tooltip,
        icon: const Icon(Icons.close, size: 15),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: Colors.black.withValues(alpha: 0.58),
          foregroundColor: Colors.white,
        ),
      ),
    );
  }
}

class _CloseVoucherImage extends StatelessWidget {
  const _CloseVoucherImage({required this.voucher, this.previewBytes});

  final CloseTransferVoucherModel voucher;
  final Uint8List? previewBytes;

  @override
  Widget build(BuildContext context) {
    if (previewBytes != null) {
      return Image.memory(previewBytes!, fit: BoxFit.cover);
    }

    return Image.network(
      _resolveContabilidadAssetUrl(voucher.fileUrl),
      fit: BoxFit.cover,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      },
      errorBuilder: (context, error, stackTrace) {
        return Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined, size: 20),
        );
      },
    );
  }
}

class _VoucherAddButton extends StatelessWidget {
  const _VoucherAddButton({
    required this.uploading,
    required this.tooltip,
    required this.onPressed,
  });

  final bool uploading;
  final String tooltip;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: uploading ? null : onPressed,
        icon: uploading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_photo_alternate_outlined, size: 20),
      ),
    );
  }
}

class _VoucherPreviewStrip extends StatelessWidget {
  const _VoucherPreviewStrip({
    required this.vouchers,
    required this.previewBytesFor,
    required this.onOpenVoucher,
    required this.onVoucherRemoved,
  });

  final List<CloseTransferVoucherModel> vouchers;
  final Uint8List? Function(CloseTransferVoucherModel voucher) previewBytesFor;
  final void Function(CloseTransferVoucherModel voucher) onOpenVoucher;
  final void Function(CloseTransferVoucherModel voucher) onVoucherRemoved;

  @override
  Widget build(BuildContext context) {
    if (vouchers.isEmpty) return const SizedBox.shrink();

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      itemCount: vouchers.length,
      separatorBuilder: (_, __) => const SizedBox(width: 6),
      itemBuilder: (context, index) {
        final voucher = vouchers[index];
        return _CloseVoucherCompactPreview(
          voucher: voucher,
          previewBytes: previewBytesFor(voucher),
          onOpen: () => onOpenVoucher(voucher),
          onRemove: () => onVoucherRemoved(voucher),
        );
      },
    );
  }
}

class _TransferEntryEditor extends StatelessWidget {
  final int index;
  final _TransferDraft draft;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final Future<void> Function() onPickVoucher;
  final void Function(CloseTransferVoucherModel voucher) onOpenVoucher;
  final Uint8List? Function(CloseTransferVoucherModel voucher) previewBytesFor;
  final void Function(CloseTransferVoucherModel voucher) onVoucherRemoved;

  const _TransferEntryEditor({
    required this.index,
    required this.draft,
    required this.onChanged,
    required this.onRemove,
    required this.onPickVoucher,
    required this.onOpenVoucher,
    required this.previewBytesFor,
    required this.onVoucherRemoved,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${index + 1}.',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                initialValue: _resolveDepositBank(draft.bankCtrl.text)?.id,
                items: depositBankCatalog
                    .map(
                      (bank) => DropdownMenuItem(
                        value: bank.id,
                        child: Text(bank.label),
                      ),
                    )
                    .toList(),
                decoration: const InputDecoration(
                  labelText: 'Banco',
                  isDense: true,
                ),
                onChanged: (value) {
                  if (value == null) return;
                  final bank = depositBankCatalog.firstWhere(
                    (item) => item.id == value,
                    orElse: () => depositBankCatalog.first,
                  );
                  draft.bankCtrl.text = bank.label;
                  onChanged();
                },
                validator: (value) => value == null ? 'Banco requerido' : null,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 132,
              child: TextFormField(
                controller: draft.amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const [_AccountingMoneyInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Monto',
                  prefixText: 'RD\$ ',
                  isDense: true,
                ),
                onTap: () => _prepareAccountingMoneyEditing(draft.amountCtrl),
                onChanged: (_) => onChanged(),
                validator: (value) {
                  final amount = _parseAccountingMoney(value);
                  return amount <= 0 ? 'Mayor a 0' : null;
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: draft.referenceCtrl,
                decoration: const InputDecoration(
                  labelText: 'Referencia',
                  isDense: true,
                ),
                onChanged: (_) => onChanged(),
              ),
            ),
            const SizedBox(width: 8),
            _VoucherAddButton(
              uploading: draft.uploading,
              tooltip: 'Subir boucher de transferencia',
              onPressed: onPickVoucher,
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 148,
              height: 48,
              child: _VoucherPreviewStrip(
                vouchers: draft.vouchers,
                previewBytesFor: previewBytesFor,
                onOpenVoucher: onOpenVoucher,
                onVoucherRemoved: (voucher) {
                  onVoucherRemoved(voucher);
                  draft.vouchers.remove(voucher);
                  onChanged();
                },
              ),
            ),
            IconButton(
              tooltip: 'Eliminar transferencia',
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseEntryEditor extends StatelessWidget {
  final int index;
  final _ExpenseDraft draft;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final Future<void> Function() onPickVoucher;
  final void Function(CloseTransferVoucherModel voucher) onOpenVoucher;
  final Uint8List? Function(CloseTransferVoucherModel voucher) previewBytesFor;
  final void Function(CloseTransferVoucherModel voucher) onVoucherRemoved;

  const _ExpenseEntryEditor({
    required this.index,
    required this.draft,
    required this.onChanged,
    required this.onRemove,
    required this.onPickVoucher,
    required this.onOpenVoucher,
    required this.previewBytesFor,
    required this.onVoucherRemoved,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        color: theme.colorScheme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${index + 1}.',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: TextFormField(
                controller: draft.conceptCtrl,
                decoration: const InputDecoration(
                  labelText: 'Concepto',
                  hintText: 'Nombre del gasto',
                  isDense: true,
                ),
                onChanged: (_) => onChanged(),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Concepto requerido';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 132,
              child: TextFormField(
                controller: draft.amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: const [_AccountingMoneyInputFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Monto',
                  prefixText: 'RD\$ ',
                  isDense: true,
                ),
                onTap: () => _prepareAccountingMoneyEditing(draft.amountCtrl),
                onChanged: (_) => onChanged(),
                validator: (value) {
                  final amount = _parseAccountingMoney(value);
                  return amount <= 0 ? 'Mayor a 0' : null;
                },
              ),
            ),
            const SizedBox(width: 8),
            _VoucherAddButton(
              uploading: draft.uploading,
              tooltip: 'Subir boucher del gasto',
              onPressed: onPickVoucher,
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 148,
              height: 48,
              child: _VoucherPreviewStrip(
                vouchers: draft.vouchers,
                previewBytesFor: previewBytesFor,
                onOpenVoucher: onOpenVoucher,
                onVoucherRemoved: (voucher) {
                  onVoucherRemoved(voucher);
                  draft.vouchers.remove(voucher);
                  onChanged();
                },
              ),
            ),
            IconButton(
              tooltip: 'Eliminar gasto',
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloseSummaryBlock extends StatelessWidget {
  final double totalIncome;
  final double netTotal;
  final double cashDeclared;
  final double cashDelivered;
  final double difference;

  const _CloseSummaryBlock({
    required this.totalIncome,
    required this.netTotal,
    required this.cashDeclared,
    required this.cashDelivered,
    required this.difference,
  });

  @override
  Widget build(BuildContext context) {
    final money = _accountingCurrencyFormatter;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _MoneyPill(label: 'Total ingresos', value: money.format(totalIncome)),
          _MoneyPill(label: 'Total neto', value: money.format(netTotal)),
          _MoneyPill(
            label: 'Efectivo declarado',
            value: money.format(cashDeclared),
          ),
          _MoneyPill(
            label: 'Fondo de caja',
            value: money.format(cashDelivered),
          ),
          _MoneyPill(label: 'Diferencia', value: money.format(difference)),
        ],
      ),
    );
  }
}

class _StatusNotice extends StatelessWidget {
  final CloseModel close;

  const _StatusNotice({required this.close});

  @override
  Widget build(BuildContext context) {
    final approved = close.isApproved;
    final scheme = Theme.of(context).colorScheme;
    final text = approved
        ? 'Este cierre ya fue aprobado y no se puede editar.'
        : 'Este cierre fue rechazado. Duplica los datos para registrar una correccion.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: approved ? Colors.green.shade50 : scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: approved ? Colors.green.shade200 : scheme.error,
        ),
      ),
      child: Row(
        children: [
          Icon(
            approved ? Icons.verified_outlined : Icons.block_outlined,
            color: approved ? Colors.green.shade700 : scheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: approved
                    ? Colors.green.shade900
                    : scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final String value;

  const _InfoPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;

  const _ErrorBox({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: scheme.onErrorContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
