import 'package:daleventa_pos/core/widgets/mobile_action_icon.dart';
import 'package:daleventa_pos/core/widgets/mobile_page_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/admin_authorization.dart';
import '../../core/auth/app_permissions.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/api/server_connection.dart';
import '../../core/errors/user_safe_error_text.dart';
import '../../core/errors/api_exception.dart';
import '../../core/offline/offline_store.dart';
import '../../core/offline/sync_queue_service.dart';
import '../../core/offline/pending_sync_action.dart';
import '../../core/offline/sale_attempt_audit.dart';
import '../../core/offline/sale_attempt_declaration.dart';
import '../../core/offline/sale_attempt_reconciliation.dart';
import '../../core/offline/sale_attempt_reconciliation_providers.dart';
import '../../core/offline/sale_attempt_recovery_engine.dart';
import '../../core/offline/sale_attempt_recovery_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../modules/cotizaciones/cotizaciones_screen.dart';
import '../../core/offline/recovery_sale_draft.dart';
import '../../core/routing/routes.dart';
import 'package:go_router/go_router.dart';
import 'reconciliation_obligations_panel.dart';
import 'recovery_status_card.dart';
import 'recovery_reviews_panel.dart';
import 'recovery_presentation.dart';
import '../../core/offline/recovery_review_repository.dart';

const _recoveryButtonStyle = ButtonStyle(
  shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
);

/// Centro de recuperación de cobros sin confirmar.
///
/// Objetivo: que el negocio pueda resolver por sí mismo un intento de cobro
/// incierto, sin llamar al desarrollador, **sin repetir el cobro** y sin que
/// un incidente antiguo bloquee las ventas nuevas.
///
/// Reglas que esta pantalla respeta:
///  - Verificar solo consulta; nunca reenvía ni crea ventas.
///  - Un resultado ambiguo (NOT_FOUND / UNKNOWN) conserva el intento intacto.
///  - Resolver a mano exige autorización administrativa y deja rastro.
///  - «No se realizó esta venta» no borra nada en el servidor.
///  - «Sí recibimos dinero» abre conciliación; no inventa una venta.
class SaleAttemptRecoveryScreen extends ConsumerStatefulWidget {
  const SaleAttemptRecoveryScreen({super.key});

  @override
  ConsumerState<SaleAttemptRecoveryScreen> createState() =>
      _SaleAttemptRecoveryScreenState();
}

class _SaleAttemptRecoveryScreenState
    extends ConsumerState<SaleAttemptRecoveryScreen> {
  bool _loading = true;
  bool _isAdmin = false;
  bool _synchronizing = false;
  final Map<String, SaleAttemptReconciliationResult> _checks = {};
  int _loadVersion = 0;
  String? _error;
  String? _companyId;
  int _pendingDeclarations = 0;
  List<PendingSyncAction> _queuedDeclarations = const [];
  List<PendingSyncAction> _attempts = const [];
  List<PendingSyncAction> _financialActions = const [];
  final Map<String, List<SaleAttemptAuditEntry>> _history = {};
  final Set<String> _busy = <String>{};

  String _queueLabel(PendingSyncAction action) {
    if (action.status == 'review_resolved') {
      return 'Revisión finalizada';
    }
    if (action.status == 'syncing') return 'Enviando';
    if (action.status == 'auth_blocked') return 'Inicia sesión';
    if (action.status == 'requires_action' || action.status == 'conflict') {
      return 'Por revisar';
    }
    if (!action.isAutomaticallyRetryable) return 'Revisión pendiente';
    return action.status == 'error' ? 'Reintento pendiente' : 'Pendiente';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await ref.read(tokenStorageProvider).getUserSnapshot();
      if (!mounted || version != _loadVersion) return;
      if (user?.role != 'ADMIN') {
        setState(() {
          _isAdmin = false;
          _checks.clear();
          _loading = false;
          _attempts = const [];
          _financialActions = const [];
          _queuedDeclarations = const [];
          _history.clear();
          _companyId = null;
        });
        return;
      }
      setState(() => _isAdmin = true);
      final companyId = user?.companyId?.trim();
      final userId = user?.id.trim();
      if ((companyId ?? '').isEmpty || (userId ?? '').isEmpty) {
        setState(() {
          _loading = false;
          _error =
              'No pudimos identificar tu empresa y usuario. Vuelve a iniciar sesión.';
        });
        return;
      }
      setState(() => _isAdmin = true);
      final attempts = await OfflineStore.instance.listUnresolvedSaleAttempts(
        companyId: companyId,
        userId: userId,
      );
      // Declaraciones «sí recibí el dinero» todavía no enviadas al servidor.
      final queued = await OfflineStore.instance.listPendingActions(
        companyId: companyId,
        userId: userId,
        limit: null,
      );
      final declarations = queued
          .where((action) => action.type == SaleAttemptDeclaration.actionType && action.status != 'review_resolved')
          .toList(growable: false);
      final history = <String, List<SaleAttemptAuditEntry>>{};
      for (final action in attempts) {
        final requestId = SaleAttemptReconciler.requestIdOf(action);
        history[action.id] = await OfflineStore.instance.listSaleAttemptAudit(
          companyId: companyId,
          clientRequestId: requestId.isEmpty ? null : requestId,
          limit: 20,
        );
      }
      final currentUser = await ref
          .read(tokenStorageProvider)
          .getUserSnapshot();
      if (!mounted ||
          version != _loadVersion ||
          currentUser?.companyId != companyId ||
          currentUser?.id != userId) {
        return;
      }
      await ref.read(syncQueueServiceProvider.notifier).refreshStats();
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _companyId = companyId;
        _attempts = attempts;
        _pendingDeclarations = declarations.length;
        _queuedDeclarations = declarations;
        _financialActions = queued
            .where(
              (action) =>
                  action.type != SaleAttemptReconciler.attemptType &&
                  action.type != SaleAttemptDeclaration.actionType &&
                  (action.type.startsWith('cash.') ||
                      action.type.startsWith('sales.')),
            )
            .toList();
        _history
          ..clear()
          ..addAll(history);
        _loading = false;
      });
      // Las obligaciones de conciliación viven en el servidor: tras cualquier
      // resolución, se vuelven a pedir (nunca se inventan localmente).
      final scopedCompanyId = _companyId;
      if (scopedCompanyId != null && scopedCompanyId.isNotEmpty) {
        ref.invalidate(reconciliationObligationsProvider(scopedCompanyId));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No pudimos leer las incidencias guardadas en este equipo.';
      });
    }
  }

  Future<void> _synchronize() async {
    if (_synchronizing) return;
    setState(() => _synchronizing = true);
    try {
      await ref.read(syncQueueServiceProvider.notifier).processPending();
      final user = await ref.read(tokenStorageProvider).getUserSnapshot();
      if (user?.role == 'ADMIN') {
        await ref.read(recoveryEngineProvider).runOnce(
          trigger: RecoveryTrigger.manual, companyId: user?.companyId, userId: user?.id);
      }
      ref.invalidate(recoveryReviewsProvider);
      await _load();
    } catch (error) {
      if (mounted) {
        await _showInfo(title: 'Pendientes guardados',
        body: userSafeErrorMessage(error, fallback: 'Se volverá a intentar al recuperar la conexión.'));
      }
    } finally {
      if (mounted) setState(() => _synchronizing = false);
    }
  }

  Future<void> _verify(PendingSyncAction action) async {
    if (_busy.contains(action.id)) return;
    setState(() => _busy.add(action.id));
    try {
      final reconciler = ref.read(saleAttemptReconcilerProvider);
      final result = await reconciler.verifyThoroughly(action);
      if (mounted && result != null) setState(() => _checks[action.id] = result);
      if (!mounted) return;
      if (result == null) {
        await _showInfo(
          title: 'No pudimos verificar todavía',
          body:
              'El servidor no respondió. El cobro sigue guardado. No lo repitas.',
        );
        return;
      }
      await _load();
      if (!mounted) return;
      await _showInfo(
        title: 'Resultado de la verificación',
        body: _explainStatus(result),
      );
    } catch (error) {
      if (mounted) {
        await _showInfo(
          title: 'No se pudo comprobar',
          body: userSafeErrorMessage(
            error,
            fallback: 'El cobro sigue guardado. Vuelve a consultar más tarde.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(action.id));
    }
  }

  String _explainStatus(SaleAttemptReconciliationResult result) {
    switch (result.guidance) {
      case 'LOOKUP_HTTP_401':
        return 'Inicia sesión con la cuenta original para comprobar el cobro.';
      case 'LOOKUP_HTTP_403':
        return 'El servidor no autorizó la consulta. Revisa la sesión y la empresa.';
      case 'LOOKUP_HTTP_429':
      case 'WAIT_RETRY_AFTER':
        return 'Espera antes de consultar de nuevo. El cobro sigue guardado.';
      case 'LOOKUP_HTTP_422':
        return 'Los datos requieren revisión. No repitas el cobro.';
    }
    return switch (result.status) {
      SaleAttemptReconciliationStatus.confirmed =>
        result.voided
            ? 'La venta fue registrada y después anulada o devuelta.'
            : 'Venta registrada. Si fue una transferencia, confirma el ingreso en el banco.',
      SaleAttemptReconciliationStatus.definitivelyRejected =>
        'Operación rechazada. Revisa los datos antes de preparar otro cobro.',
      SaleAttemptReconciliationStatus.notFound =>
        'No se encontró la venta. Esto no confirma que el pago haya fallado. No repitas el cobro.',
      SaleAttemptReconciliationStatus.unknown =>
        'El resultado no es concluyente. El cobro sigue guardado para revisión.',
      SaleAttemptReconciliationStatus.notChecked =>
        'Declaración guardada. El cobro aún no está conciliado.',
    };
  }

  Future<void> _resolveManually(
    PendingSyncAction action,
    SaleAttemptDecision decision,
  ) async {
    final authorized = await ensureAdminAuthorization(
      context,
      ref,
      permission: AppPermission.cancelSales,
      reason: decision == SaleAttemptDecision.manualNotPerformed
          ? 'Declarar que el cobro no se realizó'
          : 'Declarar que sí se recibió el dinero',
    );
    if (!authorized || !mounted) return;

    final note = await _askNote(decision);
    if (note == null || !mounted) return;

    final user = await ref.read(tokenStorageProvider).getUserSnapshot();
    if (!mounted) return;
    setState(() => _busy.add(action.id));
    try {
      if (user?.role != 'ADMIN' || user?.id != action.userId || user?.companyId != action.companyId) return;
      if (decision == SaleAttemptDecision.manualNotPerformed) {
        final proof = await ref.read(saleAttemptReconcilerProvider).verifyThoroughly(action);
        if (proof?.status != SaleAttemptReconciliationStatus.notFound &&
            proof?.status != SaleAttemptReconciliationStatus.definitivelyRejected) {
          _checks.remove(action.id);
          await _load();
          if (mounted) {
            await _showInfo(title: 'Pendiente conservado',
            body: proof?.status == SaleAttemptReconciliationStatus.confirmed
                ? 'La venta ya está registrada. No se eliminó ningún cobro.'
                : 'No se pudo comprobar el resultado. No se retiró el pendiente.');
          }
          return;
        }
        // Close the company case before archiving locally; otherwise an
        // automatically published copy would reappear as an open incident.
        final repository = ref.read(recoveryReviewRepositoryProvider);
        await repository.resolveNotPerformed(action, note);
        ref.invalidate(recoveryReviewsProvider);
      }
      final resolved = await ref
          .read(saleAttemptReconcilerProvider)
          .resolveManually(
            action: action,
            decision: decision,
            actorUserId: user?.id,
            actorRole: user?.role,
            note: note,
          );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      final moneyReceived = decision == SaleAttemptDecision.manualMoneyReceived;
      final String title;
      final String body;
      if (resolved) {
        title = moneyReceived ? 'Declaración guardada' : 'Revisión finalizada';
        body = moneyReceived
            ? 'Queda pendiente de conciliación. No se creó una venta ni se confirmó el pago.'
            : 'Decisión guardada. Las ventas y los pagos del servidor no cambian.';
      } else {
        title = 'Revisión pendiente';
        body = moneyReceived
            ? 'No se pudo guardar la declaración. El cobro sigue pendiente; no lo repitas.'
            : 'Decisión guardada. El cobro aún necesita revisión.';
      }
      await _showInfo(title: title, body: body);
    } catch (error) {
      if (!mounted) return;
      await _showInfo(
        title: 'No se pudo cerrar la incidencia',
        body:
            'El intento sigue intacto. Pide ayuda a soporte antes de cobrar de '
            'nuevo este contenido.',
      );
    } finally {
      if (mounted) setState(() => _busy.remove(action.id));
    }
  }

  Future<String?> _askNote(SaleAttemptDecision decision) async {
    final controller = TextEditingController();
    final isNotPerformed = decision == SaleAttemptDecision.manualNotPerformed;
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          isNotPerformed
              ? 'Eliminar pendiente'
              : 'Declarar que sí se recibió el dinero',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isNotPerformed
                    ? 'Describe la evidencia. Esta decisión no anula ventas ni pagos.'
                    : 'Describe cómo recibiste el dinero. Quedará pendiente de conciliación; no crea una venta.',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                maxLength: 300,
                decoration: const InputDecoration(
                  labelText: 'Detalle de la revisión',
                  helperText: 'Mínimo 10 caracteres',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            style: _recoveryButtonStyle,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, _) => FilledButton(
              style: _recoveryButtonStyle,
              onPressed: value.text.trim().length < 10
                  ? null
                  : () => Navigator.of(dialogContext).pop(value.text.trim()),
              child: const Text('Guardar declaración'),
            ),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.dispose();
    return result;
  }

  Future<void> _showNewSaleGuidance(PendingSyncAction action) async {
    final fingerprint = (action.operationFingerprint ?? '').trim();
    final authorize = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hacer una venta nueva'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Antes de autorizar otra venta, confirma con el cliente que no hubo un cobro previo.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Artículos del intento original:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                for (final line in _itemLines(action))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                if (fingerprint.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Al continuar, autorizas una venta nueva. El intento anterior no se reenviará.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            style: _recoveryButtonStyle,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cerrar'),
          ),
          FilledButton(
              style: _recoveryButtonStyle,
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Autorizar venta nueva'),
            ),
        ],
      ),
    );
    if (authorize != true || !mounted) return;
    await _authorizeNewSale(action, fingerprint);
  }

  /// Autorización supervisada para vender OTRA VEZ el mismo contenido.
  ///
  /// No resuelve el incidente y no reenvía el intento: crea un permiso de un
  /// solo uso, de 10 minutos, con el actor registrado. La venta nueva llevará su
  /// propio `clientRequestId`.
  Future<void> _authorizeNewSale(
    PendingSyncAction action,
    String fingerprint,
  ) async {
    final authorized = await ensureAdminAuthorization(
      context,
      ref,
      permission: AppPermission.cancelSales,
      reason: 'Autorizar una venta nueva con el mismo contenido',
    );
    if (!authorized || !mounted) return;

    final user = await ref.read(tokenStorageProvider).getUserSnapshot();
    if (!mounted) return;
    setState(() => _busy.add(action.id));
    try {
      if (user?.role != 'ADMIN' || user?.companyId != action.companyId || user?.id != action.userId) {
        throw ApiException('La sesión cambió. Abre la operación con su cuenta original.');
      }
      final rawItems = action.payload['items'];
      if (rawItems is! List || rawItems.isEmpty || rawItems.any((item) {
        if (item is! Map) return true;
        final quantity = num.tryParse('${item['qty']}');
        final price = num.tryParse('${item['priceSoldUnit']}');
        return quantity == null || !quantity.isFinite || quantity <= 0 || price == null || !price.isFinite || price < 0;
      })) {
        throw ApiException('Faltan artículos o hay cantidades inválidas. Conserva la incidencia y revisa los datos originales.');
      }
      final fresh = await ref.read(saleAttemptReconcilerProvider).verifyThoroughly(action);
      if (fresh?.status != SaleAttemptReconciliationStatus.notFound && fresh?.status != SaleAttemptReconciliationStatus.definitivelyRejected) {
        _checks.remove(action.id);
        await _load();
        throw ApiException(fresh?.status == SaleAttemptReconciliationStatus.confirmed
            ? 'La venta ya está registrada. No se preparó otro cobro.'
            : 'No se pudo comprobar el cobro. Se conserva pendiente.');
      }
      if (!recoverySaleItemsAreValid(action)) {
        throw ApiException('Faltan artículos o hay cantidades inválidas. No se preparó otro cobro; conserva el pendiente.');
      }
      if (fingerprint.isNotEmpty) {
        await OfflineStore.instance.grantSameCartOverride(
        companyId: action.companyId ?? '',
        operationFingerprint: fingerprint,
        actorUserId: user?.id,
        actorRole: user?.role,
        note: 'Autorización de venta nueva independiente',
      );
      }
      await ref
          .read(saleAttemptReconcilerProvider)
          .resolveManually(
            action: action,
            decision: SaleAttemptDecision.manualAuthorizedNewSale,
            actorUserId: user?.id,
            actorRole: user?.role,
            note: 'Autorización de venta nueva independiente',
          );
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ref.read(recoverySaleDraftProvider.notifier).state = action;
      final router = GoRouter.maybeOf(context);
      if (router != null) {
        Navigator.of(context).pop();
        router.go(Routes.cotizaciones);
      } else {
        await Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => CotizacionesScreen(initialRecoveryAction: action),
        ));
      }
    } catch (error) {
      if (!mounted) return;
      await _showInfo(
        title: 'No se pudo autorizar',
        body: userSafeErrorMessage(error, fallback: 'El intento sigue conservado. No se inició otro cobro.'),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(action.id));
    }
  }

  Future<void> _showInfo({required String title, required String body}) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(body, style: const TextStyle(fontSize: 13, height: 1.45)),
        ),
        actions: [
          FilledButton(
            style: _recoveryButtonStyle,
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  String _amountText(PendingSyncAction action) {
    final raw = action.payload['expectedTotalSold'];
    final value = raw is num ? raw.toDouble() : double.tryParse('${raw ?? ''}');
    if (value != null) return value.toStringAsFixed(2);
    var sum = 0.0;
    for (final item in _items(action)) {
      sum += item.qty * item.price;
    }
    return sum.toStringAsFixed(2);
  }

  String _paymentText(PendingSyncAction action) {
    final method = (action.payload['paymentMethod'] ?? '').toString().trim();
    return switch (method.toLowerCase()) {
      'cash' => 'Efectivo',
      'transfer' => 'Transferencia',
      'credit' => 'Crédito',
      '' => 'No registrado',
      _ => method,
    };
  }

  List<({String name, String productId, double qty, double price})> _items(
    PendingSyncAction action,
  ) {
    final raw = action.payload['items'];
    if (raw is! List) return const [];
    final result =
        <({String name, String productId, double qty, double price})>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      final map = entry.cast<String, dynamic>();
      final qty = map['qty'] is num
          ? (map['qty'] as num).toDouble()
          : double.tryParse('${map['qty'] ?? ''}') ?? 0;
      final price = map['priceSoldUnit'] is num
          ? (map['priceSoldUnit'] as num).toDouble()
          : double.tryParse('${map['priceSoldUnit'] ?? ''}') ?? 0;
      result.add((
        name: (map['productName'] ?? map['name'] ?? 'Artículo').toString(),
        productId: (map['productId'] ?? '').toString(),
        qty: qty,
        price: price,
      ));
    }
    return result;
  }

  List<String> _itemLines(PendingSyncAction action) {
    final items = _items(action);
    if (items.isEmpty) return const ['(sin detalle de artículos guardado)'];
    return [
      for (final item in items)
        '• ${item.name} × ${item.qty.toStringAsFixed(item.qty % 1 == 0 ? 0 : 2)} '
            '@ ${item.price.toStringAsFixed(2)}',
    ];
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      authStateProvider.select(
        (state) => (state.user?.companyId, state.user?.id, state.user?.role),
      ),
      (previous, next) {
        if (previous == next) return;
        setState(() {
          _isAdmin = false;
          _attempts = const [];
          _queuedDeclarations = const [];
          _financialActions = const [];
          _history.clear();
          _companyId = null;
        });
        _load();
      },
    );
    if (!_isAdmin) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: MobilePageAppBar(appBar: AppBar(title: const Text('Centro de recuperación'))),
        body: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : const Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.admin_panel_settings_outlined, size: 32),
                      SizedBox(height: 12),
                      Text('Acceso de administrador', style: TextStyle(fontWeight: FontWeight.w700)),
                      SizedBox(height: 8),
                      Text('Inicia sesión como administrador para revisar operaciones.', textAlign: TextAlign.center),
                    ],
                  ),
                ),
        ),
      );
    }
    final queue = ref.watch(syncQueueServiceProvider);
    final server = ref.watch(serverConnectionProvider);
    final linked = ref.watch(recoveryReviewsProvider).asData?.value
        .where((row) => row['sourceUserId'] == ref.read(authStateProvider).user?.id)
        .map((row) => row['sourceActionId']).toSet() ?? <Object?>{};
    final hasOpenReviews = ref.watch(recoveryReviewsProvider).asData?.value
        .any((row) => row['needsIntervention'] == true) ?? false;
    final active = _financialActions
        .where((a) => a.status != 'review_resolved' && !linked.contains(a.id))
        .toList();
    final resolved = _financialActions
        .where((a) => a.status == 'review_resolved' && !linked.contains(a.id))
        .toList();
    final obligations = (_companyId ?? '').isEmpty ? null
        : ref.watch(reconciliationObligationsProvider(_companyId!));
    final cases = ref.watch(recoveryReviewsProvider);
    final allClear = !_loading && _error == null && _attempts.isEmpty &&
        active.isEmpty && _pendingDeclarations == 0 && !hasOpenReviews &&
        queue.pendingCount + queue.errorCount + queue.blockedCount + queue.conflictCount + queue.syncingCount == 0 &&
        cases.hasValue && obligations?.hasValue == true &&
        obligations!.value!.isEmpty;
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        visualDensity: VisualDensity.compact,
        listTileTheme: const ListTileThemeData(dense: true, minTileHeight: 40),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(shape: const RoundedRectangleBorder()),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: const RoundedRectangleBorder(),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(shape: const RoundedRectangleBorder()),
        ),
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: MobilePageAppBar(appBar: AppBar(title: const Text('Centro de recuperación'))),
        body: RefreshIndicator(
          onRefresh: _load,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
                children: [
                  Container(
                    key: const ValueKey('recovery-content-card'),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!allClear) ...[
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Pendientes',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Sincronizar',
                              onPressed: _loading || _synchronizing ? null : _synchronize,
                              icon: _synchronizing
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.sync_rounded, size: 20),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _RecoveryMetric(
                              label: switch (server) {
                                ServerConnection.reachable =>
                                  'Servidor accesible',
                                ServerConnection.unreachable => 'Sin conexión',
                                ServerConnection.unknown =>
                                  'Servidor sin comprobar',
                              },
                              icon: server == ServerConnection.reachable
                                  ? Icons.cloud_done_outlined
                                  : Icons.cloud_outlined,
                            ),
                            if (queue.pendingCount > 0)
                              _RecoveryMetric(
                                label: '${queue.pendingCount} pendientes',
                              ),
                            if (queue.errorCount > 0)
                              _RecoveryMetric(
                                label: '${queue.errorCount} reintentables',
                              ),
                            if (queue.blockedCount > 0)
                              _RecoveryMetric(
                                label: '${queue.blockedCount} bloqueadas',
                              ),
                            if (queue.conflictCount > 0)
                              _RecoveryMetric(
                                label: '${queue.conflictCount} por revisar',
                              ),
                            if (queue.pendingCount +
                                    queue.errorCount +
                                    queue.blockedCount +
                                    queue.conflictCount ==
                                0)
                              const _RecoveryMetric(
                                label: 'Sin pendientes locales',
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_attempts.isEmpty && active.any((a) => a.isAutomaticallyRetryable))
                          const Text('Se envían automáticamente al volver la conexión.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        if (_attempts.isNotEmpty ||
                            _pendingDeclarations > 0) ...[
                          const SizedBox(height: 16),
                          Consumer(
                            builder: (context, ref, _) {
                              final engine = ref.watch(
                                recoveryEngineStateProvider,
                              );
                              final state = engine.maybeWhen(
                                data: (value) => value,
                                orElse: () => const RecoveryEngineState(),
                              );
                              if (!state.running &&
                                  !state.waitingForConnection &&
                                  state.consecutiveFailures == 0) {
                                return const SizedBox.shrink();
                              }
                              return RecoveryStatusCard(
                                state: state,
                                openIncidents: _attempts.length,
                                pendingDeclarations: _pendingDeclarations,
                              );
                            },
                          ),
                        ],
                        ],
                        if (allClear) const _EmptyCard(),
                        if (!allClear) RecoveryReviewsPanel(
                          localSaleAttemptIds: _attempts.map((a) => a.id).toSet(),
                        ),
                        if (!allClear && (_companyId ?? '').isNotEmpty)
                          ReconciliationObligationsPanel(
                            companyId: _companyId!,
                            pendingDeclarations: _queuedDeclarations,
                            onLocalChanged: _load,
                          ),
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_error != null)
                          _ErrorCard(message: _error!, onRetry: _load)
                        else ...[
                          if (_attempts.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            const Text(
                              'Cobros por confirmar',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            for (final action in _attempts)
                              _IncidentCard(
                                key: ValueKey('sale-incident:${action.id}'),
                                action: action,
                                canResolve: _checks[action.id]?.status == SaleAttemptReconciliationStatus.notFound ||
                                    _checks[action.id]?.status == SaleAttemptReconciliationStatus.definitivelyRejected,
                                busy: _busy.contains(action.id),
                                amountText: _amountText(action),
                                paymentText: _paymentText(action),
                                onVerify: () => _verify(action),
                                onNotPerformed: () => _resolveManually(
                                  action,
                                  SaleAttemptDecision.manualNotPerformed,
                                ),
                                onNewSale: () => _showNewSaleGuidance(action),
                              ),
                          ],
                          if (active.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            const Text(
                              'Operaciones',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            for (final action in active) _financialTile(action),
                          ],
                        ],
                        if (!allClear && resolved.isNotEmpty)
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text(
                              'Revisiones finalizadas (${resolved.length})',
                            ),
                            children: [
                              for (final action in resolved)
                                _financialTile(action),
                            ],
                          ),
                      ],
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

  Future<void> _checkFinancialAction(PendingSyncAction action) async {
    if (_busy.contains(action.id)) return;
    setState(() => _busy.add(action.id));
    try {
      await ref.read(recoveryReviewRepositoryProvider).check(action);
      ref.invalidate(recoveryReviewsProvider);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Comprobación terminada. Consulta el estado.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              userSafeErrorMessage(
                error,
                fallback:
                    'No se pudo comprobar. La operación sigue guardada.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy.remove(action.id));
    }
  }

  Future<void> _markFinancialNotPerformed(PendingSyncAction action) async {
    if (_busy.contains(action.id)) return;
    final note = await _askNote(SaleAttemptDecision.manualNotPerformed);
    if (note == null || !mounted) return;
    setState(() => _busy.add(action.id));
    try {
      final repository = ref.read(recoveryReviewRepositoryProvider);
      final row = await repository.prepare(action);
      await repository.decide(row, 'NOT_PERFORMED', note);
      ref.invalidate(recoveryReviewsProvider);
      await _load();
      if (mounted) {
        await _showInfo(title: 'Marcada como no realizada', body: 'El historial se conserva. No se anularon ventas ni pagos.');
      }
    } catch (error) {
      if (mounted) {
        await _showInfo(title: 'La operación sigue pendiente', body: userSafeErrorMessage(error,
          fallback: 'No se pudo guardar la decisión. La evidencia sigue conservada.'));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(action.id));
    }
  }

  Widget _financialTile(PendingSyncAction action) {
    final canCheck =
        RecoveryReviewRepository.types.contains(action.type) &&
        !action.isAutomaticallyRetryable &&
        action.status != 'syncing' &&
        action.status != 'review_resolved';
    final rawAmount =
        action.payload['amount'] ??
        action.payload['expectedTotalSold'] ??
        action.payload['openingAmount'] ??
        action.payload['closingAmount'];
    final amount = num.tryParse('$rawAmount');
    return ExpansionTile(
      key: PageStorageKey('financial-${action.id}'),
      shape: const Border(),
      collapsedShape: const Border(),
      expandedAlignment: Alignment.centerLeft,
      dense: true,
      visualDensity: VisualDensity.compact,
      minTileHeight: 40,
      tilePadding: EdgeInsets.zero,
      leading: Icon(
        action.status == 'review_resolved'
            ? Icons.task_alt
            : Icons.receipt_long_outlined,
        color: AppColors.textSecondary,
      ),
      title: Text(
        '${recoveryOperationLabel(action.type)}${amount != null && amount.isFinite ? ' · RD\$ ${amount.toStringAsFixed(2)}' : ''}',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        action.payload['recoveryReviewId'] != null &&
                action.status != 'review_resolved'
            ? 'Por comprobar'
            : '${_queueLabel(action)} · ${recoveryMoment(action.createdAt)}',
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      childrenPadding: const EdgeInsets.only(left: 36, bottom: 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          recoveryActionMessage(action),
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        SelectableText(
          key: PageStorageKey('financial-reference-${action.id}'),
          'Referencia: ${action.idempotencyKey ?? action.id}',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        if (action.nextAttemptAt != null)
          Text(
            'Próximo intento: ${recoveryMoment(action.nextAttemptAt!)}',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        if (canCheck) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [OutlinedButton.icon(
            onPressed: _busy.contains(action.id)
                ? null
                : () => _checkFinancialAction(action),
            icon: const Icon(Icons.fact_check_outlined, size: 18),
            label: Text(
              _busy.contains(action.id) ? 'Comprobando…' : 'Comprobar',
            ),
          ), TextButton(
            onPressed: _busy.contains(action.id) ? null : () => _markFinancialNotPerformed(action),
            child: const Text('Marcar como no realizada'),
          )]),
        ],
      ],
    );
  }
}

class _RecoveryMetric extends StatelessWidget {
  const _RecoveryMetric({required this.label, this.icon});
  final String label;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.check_circle, color: AppColors.success, size: 24),
      SizedBox(width: 10),
      Text('Todo en orden', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    ]),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.errorSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.errorBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const MobileActionIcon(Icons.refresh_rounded, size: 17),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

class _IncidentCard extends StatelessWidget {
  const _IncidentCard({
    super.key,
    required this.action, required this.canResolve, required this.busy,
    required this.amountText, required this.paymentText, required this.onVerify,
    required this.onNotPerformed, required this.onNewSale,
  });
  final PendingSyncAction action;
  final bool canResolve;
  final bool busy;
  final String amountText;
  final String paymentText;
  final Future<void> Function() onVerify;
  final Future<void> Function() onNotPerformed;
  final Future<void> Function() onNewSale;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('RD\$ $amountText · $paymentText', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text(canResolve ? 'No se encontró el registro. Confirma qué ocurrió antes de resolver.' : 'Se comprueba automáticamente. Puedes verificar otra vez.',
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 6, children: [
        if (!canResolve)
          FilledButton.icon(onPressed: busy ? null : onVerify,
            icon: const MobileActionIcon(Icons.search, size: 16),
            label: Text(busy ? 'Verificando…' : 'Verificar ahora'))
        else ...[
          OutlinedButton(onPressed: busy ? null : onNotPerformed, child: const Text('Eliminar pendiente')),
          FilledButton(onPressed: busy ? null : onNewSale, child: const Text('Hacer el cobro de nuevo')),
        ],
      ]),
    ]),
  );
}
