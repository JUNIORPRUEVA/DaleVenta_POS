import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/admin_authorization.dart';
import '../../core/auth/app_permissions.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/offline/offline_store.dart';
import '../../core/offline/pending_sync_action.dart';
import '../../core/offline/sale_attempt_audit.dart';
import '../../core/offline/sale_attempt_reconciliation.dart';
import '../../core/offline/sale_attempt_reconciliation_providers.dart';
import '../../core/theme/app_colors.dart';

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
  String? _error;
  List<PendingSyncAction> _attempts = const [];
  final Map<String, List<SaleAttemptAuditEntry>> _history = {};
  final Set<String> _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await ref.read(tokenStorageProvider).getUserSnapshot();
      final companyId = user?.companyId?.trim();
      final userId = user?.id.trim();
      if ((companyId ?? '').isEmpty || (userId ?? '').isEmpty) {
        setState(() {
          _loading = false;
          _error = 'No pudimos identificar tu empresa y usuario. Vuelve a iniciar sesión.';
        });
        return;
      }
      final attempts = await OfflineStore.instance.listUnresolvedSaleAttempts(
        companyId: companyId,
        userId: userId,
      );
      final history = <String, List<SaleAttemptAuditEntry>>{};
      for (final action in attempts) {
        final requestId = SaleAttemptReconciler.requestIdOf(action);
        history[action.id] = await OfflineStore.instance.listSaleAttemptAudit(
          companyId: companyId,
          clientRequestId: requestId.isEmpty ? null : requestId,
          limit: 20,
        );
      }
      if (!mounted) return;
      setState(() {
        _attempts = attempts;
        _history
          ..clear()
          ..addAll(history);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No pudimos leer las incidencias guardadas en este equipo.';
      });
    }
  }

  Future<void> _verify(PendingSyncAction action) async {
    if (_busy.contains(action.id)) return;
    setState(() => _busy.add(action.id));
    try {
      final reconciler = ref.read(saleAttemptReconcilerProvider);
      final result = await reconciler.verify(action);
      if (!mounted) return;
      if (result == null) {
        await _showInfo(
          title: 'No pudimos verificar todavía',
          body:
              'No hubo respuesta del servidor. El cobro sigue guardado sin cambios: '
              'no se ha repetido ni descartado. Puedes seguir vendiendo y volver a '
              'verificar más tarde.',
        );
        return;
      }
      await _load();
      if (!mounted) return;
      await _showInfo(
        title: 'Resultado de la verificación',
        body: _explainStatus(result),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(action.id));
    }
  }

  String _explainStatus(SaleAttemptReconciliationResult result) {
    switch (result.status) {
      case SaleAttemptReconciliationStatus.confirmed:
        final sale = result.saleId == null
            ? 'La venta está registrada en el sistema.'
            : 'La venta ${result.saleId} está registrada en el sistema.';
        if (result.voided) {
          return '$sale Después fue anulada o devuelta, así que no hay un cobro '
              'pendiente. Esto NO significa que el cobro haya fallado.';
        }
        return '$sale Esto confirma el registro de la operación, no el dinero '
            'recibido. Si el pago fue por transferencia, compruébalo en el banco.';
      case SaleAttemptReconciliationStatus.definitivelyRejected:
        return 'El servidor informa un rechazo definitivo. Revisa el detalle con '
            'el encargado antes de cobrar de nuevo.';
      case SaleAttemptReconciliationStatus.notFound:
        return 'El servidor no tiene registro de este intento. Eso NO demuestra '
            'que el cobro no se haya hecho: puede ser un pago externo o una '
            'respuesta perdida. El intento se conserva intacto.';
      case SaleAttemptReconciliationStatus.unknown:
        return 'La información es incompleta o contradictoria. El intento se '
            'conserva intacto para que el encargado decida con evidencia.';
    }
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
      await _showInfo(
        title: resolved ? 'Incidencia cerrada' : 'Decisión registrada',
        body: resolved
            ? 'Se guardó tu declaración con tu usuario y la hora, y el aviso se '
                  'retiró de este equipo. En el servidor no se modificó ninguna '
                  'venta, pago, deuda ni inventario.'
            : 'La decisión quedó registrada pero el intento se conserva para '
                  'revisión.',
      );
    } catch (error) {
      if (!mounted) return;
      await _showInfo(
        title: 'No se pudo cerrar la incidencia',
        body: 'El intento sigue intacto. Pide ayuda a soporte antes de cobrar de '
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
              ? 'Declarar que la venta no se realizó'
              : 'Declarar que sí se recibió el dinero',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isNotPerformed
                  ? 'Esta declaración cierra la incidencia en este equipo, pero NO '
                        'borra ventas, pagos, deudas ni inventario del servidor. '
                        'Describe qué comprobaste (datáfono, banco, caja).'
                  : 'Esta declaración registra que el dinero entró. No crea una '
                        'venta retroactiva ni marca el pago como recibido: la '
                        'conciliación se hace después por el flujo oficial. '
                        'Describe la evidencia que tienes.',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: 'Detalle de la revisión',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.length < 10) return;
              Navigator.of(dialogContext).pop(text);
            },
            child: const Text('Registrar declaración'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _showReviewRequest(PendingSyncAction action) async {
    final requestId = SaleAttemptReconciler.requestIdOf(action);
    final history = _history[action.id] ?? const <SaleAttemptAuditEntry>[];
    final lines = <String>[
      'INCIDENCIA DE COBRO — FULLPOS',
      'Reporte generado: ${DateTime.now().toUtc().toIso8601String()}',
      'Empresa: ${action.companyId ?? '-'}',
      'Usuario: ${action.userId ?? '-'}',
      'Identificador de la operación: $requestId',
      'Registrado: ${action.createdAt.toUtc().toIso8601String()}',
      'Importe esperado: ${_amountText(action)}',
      'Medio de pago: ${_paymentText(action)}',
      'Estado local: ${action.status}',
      'Último intento: ${action.lastAttemptAt?.toUtc().toIso8601String() ?? '-'}',
      'Detalle guardado: ${action.error ?? '-'}',
      'Historial de verificaciones: ${history.length}',
      for (final entry in history)
        '  - ${entry.checkedAt.toUtc().toIso8601String()} '
            '${entry.decision.code}'
            '${entry.serverStatus == null ? '' : ' estado=${entry.serverStatus}'}'
            '${entry.guidance == null ? '' : ' motivo=${entry.guidance}'}'
            '${entry.actorRole == null ? '' : ' por=${entry.actorRole}'}',
      'Contenido del intento (para reconstruir, nunca reenviar):',
      ..._itemLines(action),
      '',
      'Nota: este reporte no contiene contraseñas ni tokens. El cobro NO se ha '
          'repetido ni descartado.',
    ];
    final report = lines.join('\n');
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reporte para soporte'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: SelectableText(
              report,
              style: const TextStyle(fontSize: 12, height: 1.45),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: report));
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Copiar reporte'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showNewSaleGuidance(PendingSyncAction action) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Preparar la venta de nuevo'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Puedes registrar una venta nueva con normalidad: este incidente '
                  'no bloquea el punto de venta. Antes de cobrar, confirma con el '
                  'cliente que no se le cobró dos veces.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Estos eran los artículos del intento. Reconstrúyelos en una '
                  'venta NUEVA; el sistema no reenviará este intento.',
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
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  Future<void> _showInfo({required String title, required String body}) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body, style: const TextStyle(fontSize: 13, height: 1.45)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  String _amountText(PendingSyncAction action) {
    final raw = action.payload['expectedTotalSold'];
    final value = raw is num
        ? raw.toDouble()
        : double.tryParse('${raw ?? ''}');
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
    final result = <({String name, String productId, double qty, double price})>[];
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: const Text(
          'Centro de recuperación',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            const _Notice(
              icon: Icons.storefront_rounded,
              text:
                  'Puedes seguir vendiendo con normalidad. Un cobro sin confirmar '
                  'no bloquea el punto de venta; solo se bloquea repetir ese mismo '
                  'cobro o ese mismo carrito.',
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _ErrorCard(message: _error!, onRetry: _load)
            else if (_attempts.isEmpty)
              const _EmptyCard()
            else
              for (final action in _attempts)
                _IncidentCard(
                  action: action,
                  history: _history[action.id] ?? const [],
                  busy: _busy.contains(action.id),
                  amountText: _amountText(action),
                  paymentText: _paymentText(action),
                  itemLines: _itemLines(action),
                  onVerify: () => _verify(action),
                  onNotPerformed: () => _resolveManually(
                    action,
                    SaleAttemptDecision.manualNotPerformed,
                  ),
                  onMoneyReceived: () => _resolveManually(
                    action,
                    SaleAttemptDecision.manualMoneyReceived,
                  ),
                  onNewSale: () => _showNewSaleGuidance(action),
                  onReview: () => _showReviewRequest(action),
                ),
          ],
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.secondaryBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.verified_rounded, size: 34, color: AppColors.success),
          SizedBox(height: 10),
          Text(
            'No hay cobros sin confirmar',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Todo lo registrado en este equipo está conciliado.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
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
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Reintentar'),
          ),
        ],
      ),
    );
  }
}

class _IncidentCard extends StatefulWidget {
  const _IncidentCard({
    required this.action,
    required this.history,
    required this.busy,
    required this.amountText,
    required this.paymentText,
    required this.itemLines,
    required this.onVerify,
    required this.onNotPerformed,
    required this.onMoneyReceived,
    required this.onNewSale,
    required this.onReview,
  });

  final PendingSyncAction action;
  final List<SaleAttemptAuditEntry> history;
  final bool busy;
  final String amountText;
  final String paymentText;
  final List<String> itemLines;
  final Future<void> Function() onVerify;
  final Future<void> Function() onNotPerformed;
  final Future<void> Function() onMoneyReceived;
  final Future<void> Function() onNewSale;
  final Future<void> Function() onReview;

  @override
  State<_IncidentCard> createState() => _IncidentCardState();
}

class _IncidentCardState extends State<_IncidentCard> {
  bool _details = false;
  bool _historyOpen = false;

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final requestId = SaleAttemptReconciler.requestIdOf(action);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warningBorder),
        boxShadow: const [
          BoxShadow(color: AppColors.shadow, blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: const BoxDecoration(
                  color: AppColors.warningSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.help_outline_rounded,
                  size: 18,
                  color: AppColors.warning,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Cobro sin confirmar',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatDate(action.createdAt)} · '
                      'RD\$ ${widget.amountText} · ${widget.paymentText}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _details = !_details),
                child: Text(_details ? 'Ocultar' : 'Detalles'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'No sabemos si este cobro se registró. No se ha repetido ni '
            'descartado: sigue guardado tal como quedó.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textSecondary,
            ),
          ),
          if (widget.history.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Última verificación: ${_formatDate(widget.history.first.checkedAt)} · '
              '${_decisionLabel(widget.history.first.decision)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
          if (_details) ...[
            const SizedBox(height: 10),
            _DetailRow(label: 'Identificador', value: requestId),
            _DetailRow(
              label: 'Último intento',
              value: action.lastAttemptAt == null
                  ? 'Nunca'
                  : _formatDate(action.lastAttemptAt!),
            ),
            _DetailRow(label: 'Empresa', value: action.companyId ?? '-'),
            _DetailRow(label: 'Usuario', value: action.userId ?? '-'),
            _DetailRow(
              label: 'Artículos',
              value: widget.itemLines.join(' · '),
            ),
            for (final entry in widget.history.take(5))
              _DetailRow(
                label: _decisionLabel(entry.decision),
                value:
                    '${_formatDate(entry.checkedAt)}'
                    '${entry.actorRole == null ? '' : ' · ${entry.actorRole}'}'
                    '${entry.note == null ? '' : ' · ${entry.note}'}',
              ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: widget.busy ? null : () => widget.onVerify(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                icon: widget.busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.search_rounded, size: 16),
                label: const Text(
                  'Verificar ahora',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              OutlinedButton.icon(
                onPressed: widget.busy ? null : () => widget.onNewSale(),
                icon: const Icon(Icons.add_shopping_cart_rounded, size: 16),
                label: const Text(
                  'Preparar venta nueva',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              OutlinedButton.icon(
                onPressed: widget.busy ? null : () => widget.onReview(),
                icon: const Icon(Icons.description_outlined, size: 16),
                label: const Text(
                  'Solicitar revisión',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _historyOpen = !_historyOpen),
                icon: const Icon(Icons.history_rounded, size: 16),
                label: Text(
                  'Historial (${widget.history.length})',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          if (_historyOpen) ...[
            const SizedBox(height: 6),
            if (widget.history.isEmpty)
              const Text(
                'Todavía no hay verificaciones registradas en este equipo.',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              )
            else
              for (final entry in widget.history)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '• ${_formatDate(entry.checkedAt)} · '
                    '${_decisionLabel(entry.decision)}'
                    '${entry.saleId == null ? '' : ' · venta ${entry.saleId}'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
          ],
          const Divider(height: 22),
          const Text(
            'Resolver con autorización del encargado',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: widget.busy ? null : () => widget.onNotPerformed(),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    alignment: Alignment.centerLeft,
                  ),
                  child: const Text(
                    'No se realizó esta venta',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: widget.busy ? null : () => widget.onMoneyReceived(),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    alignment: Alignment.centerLeft,
                  ),
                  child: const Text(
                    'Sí recibimos el dinero',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          const Text(
            'Cerrar la incidencia no borra ventas, pagos, deudas ni inventario, y '
            'no repite el cobro.',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  static String _decisionLabel(SaleAttemptDecision decision) {
    return switch (decision) {
      SaleAttemptDecision.autoConfirmed => 'Registrada en el servidor',
      SaleAttemptDecision.autoRegisteredThenVoided =>
        'Registrada y luego anulada',
      SaleAttemptDecision.keptInconclusive => 'Sin conclusión: conservada',
      SaleAttemptDecision.manualNotPerformed =>
        'Declarada como no realizada',
      SaleAttemptDecision.manualMoneyReceived => 'Dinero recibido declarado',
      SaleAttemptDecision.manualEscalated => 'Revisión solicitada',
    };
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
