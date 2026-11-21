import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_routes.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/errors/user_safe_error_text.dart';
import '../../core/offline/sync_queue_service.dart';
import '../../core/offline/offline_store.dart';
import '../../core/offline/pending_sync_action.dart';
import '../../core/theme/app_colors.dart';

/// Obligación de conciliación registrada en el servidor.
///
/// Es el rastro administrativo de una declaración «sí recibí el dinero». NUNCA
/// es una venta, un pago, un ingreso de caja ni un movimiento de inventario: por
/// eso `assertsPaymentReceived` y `retryAllowed` viajan explícitamente en falso.
class ReconciliationObligation {
  const ReconciliationObligation({
    required this.id,
    required this.clientRequestId,
    required this.totalDeclared,
    required this.currency,
    required this.status,
    required this.declaredAtUtc,
    this.paymentMethod,
    this.declaredByUserId,
    this.declaredByRole,
    this.note,
    this.resolvedAtUtc,
    this.resolutionNote,
    this.version = 1,
  });

  final String id;
  final String clientRequestId;
  final double totalDeclared;
  final String currency;
  final String status;
  final DateTime? declaredAtUtc;
  final String? paymentMethod;
  final String? declaredByUserId;
  final String? declaredByRole;
  final String? note;
  final DateTime? resolvedAtUtc;
  final String? resolutionNote;
  final int version;

  bool get isPending => status.trim().toUpperCase() == 'PENDING';

  static ReconciliationObligation? fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString().trim();
    final requestId = (json['clientRequestId'] ?? '').toString().trim();
    if (id.isEmpty || requestId.isEmpty) return null;
    final rawTotal = json['totalDeclared'];
    final total = rawTotal is num
        ? rawTotal.toDouble()
        : double.tryParse('${rawTotal ?? ''}');
    return ReconciliationObligation(
      id: id,
      clientRequestId: requestId,
      totalDeclared: total ?? 0,
      currency: (json['currency'] ?? 'DOP').toString(),
      status: (json['status'] ?? 'PENDING').toString(),
      declaredAtUtc: DateTime.tryParse(
        '${json['declaredAtUtc'] ?? ''}',
      )?.toUtc(),
      paymentMethod: json['paymentMethod']?.toString(),
      declaredByUserId: json['declaredByUserId']?.toString(),
      declaredByRole: json['declaredByRole']?.toString(),
      note: json['note']?.toString(),
      resolvedAtUtc: DateTime.tryParse('${json['resolvedAt'] ?? ''}')?.toUtc(),
      resolutionNote: json['resolutionNote']?.toString(),
      version: (json['version'] as num?)?.toInt() ?? 1,
    );
  }
}

final reconciliationResolutionProvider = Provider<Future<void> Function(ReconciliationObligation, String, String)>((ref) {
  return (obligation, decision, note) async {
    final owner = ref.read(authStateProvider).user;
    if (owner?.role != 'ADMIN') throw StateError('Se requiere administrador.');
    final response = await ref.read(dioProvider).post(
      '/sales/reconciliation-obligations/${obligation.id}/resolve',
      data: {'decision': decision, 'expectedVersion': obligation.version, 'note': note},
    );
    final current = ref.read(authStateProvider).user;
    if (current?.id != owner?.id || current?.companyId != owner?.companyId ||
        response.data is! Map || response.data['id'] != obligation.id ||
        response.data['clientRequestId'] != obligation.clientRequestId ||
        response.data['status'] != (decision == 'CHECK' ? 'RECONCILED' : 'DISMISSED')) {
      throw StateError('No se pudo comprobar la resolución guardada.');
    }
  };
});

/// Lista de obligaciones pendientes. Solo lectura: resolverlas es una tarea
/// administrativa, no algo que esta pantalla deba inventar.
final reconciliationObligationsProvider = FutureProvider.autoDispose
    .family<List<ReconciliationObligation>, String>((ref, companyId) async {
      ref.watch(authStateProvider.select((s) => (s.user?.companyId, s.user?.id)));
      final dio = ref.watch(dioProvider);
      final res = await dio.get(
        '${ApiRoutes.sales}/reconciliation-obligations',
        queryParameters: const {'status': 'PENDING'},
        options: Options(extra: const {'skipLoader': true}),
      );
      final data = res.data;
      final rows = data is Map ? data['items'] ?? data['data'] : data;
      if (rows is! List) return const [];
      return [
        for (final row in rows)
          if (row is Map)
            if (ReconciliationObligation.fromJson(row.cast<String, dynamic>())
                case final obligation?)
              obligation,
      ];
    });

/// Panel informativo de obligaciones de conciliación pendientes.
///
/// [pendingDeclarations] son las declaraciones que aún no se han podido enviar
/// al servidor. Se muestran igual de visibles: una declaración guardada en el
/// equipo NO puede desaparecer de la vista mientras espera la red.
class ReconciliationObligationsPanel extends ConsumerWidget {
  const ReconciliationObligationsPanel({
    super.key,
    required this.companyId,
    this.pendingDeclarations = const [],
    this.onLocalChanged,
  });

  final String companyId;
  final List<PendingSyncAction> pendingDeclarations;
  final Future<void> Function()? onLocalChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(reconciliationObligationsProvider(companyId));
    return async.when(
      loading: () => _localOnly(context),
      error: (error, stack) => _localOnly(
        context,
        notice: const _ObligationsNotice(
          icon: Icons.cloud_off_rounded,
          title: 'Conciliación no disponible ahora',
          body:
              'No se pudo consultar. Las declaraciones locales siguen guardadas.',
        ),
      ),
      data: (obligations) {
        if (obligations.isEmpty && pendingDeclarations.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _ObligationsNotice(
              icon: Icons.account_balance_wallet_rounded,
              title: 'Dinero recibido declarado',
              body:
                  'Pendiente de conciliación. No confirma una venta ni un pago.',
            ),
            const SizedBox(height: 10),
            for (final declaration in pendingDeclarations) ...[
              _PendingDeclarationCard(action: declaration, onChanged: onLocalChanged),
              const SizedBox(height: 8),
            ],
            for (final obligation in obligations) ...[
              _ObligationCard(obligation: obligation),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
          ],
        );
      },
    );
  }

  /// Solo lo que hay guardado en el equipo (sin servidor disponible).
  Widget _localOnly(BuildContext context, {Widget? notice}) {
    if (pendingDeclarations.isEmpty) return notice ?? const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        notice ??
            const _ObligationsNotice(
              icon: Icons.outbox_rounded,
              title: 'Declaraciones por enviar',
              body:
                  'Guardadas en este equipo. Consulta el estado de cada declaración.',
            ),
        const SizedBox(height: 10),
        for (final declaration in pendingDeclarations) ...[
          _PendingDeclarationCard(action: declaration, onChanged: onLocalChanged),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _PendingDeclarationCard extends ConsumerWidget {
  const _PendingDeclarationCard({required this.action, this.onChanged});

  final PendingSyncAction action;
  final Future<void> Function()? onChanged;

  Future<void> withdraw(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Eliminar pendiente'),
      content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Retira esta declaración local rechazada. Se conserva completa y no se modifica dinero.'),
        TextField(controller: controller, maxLength: 500, decoration: const InputDecoration(labelText: 'Motivo', helperText: 'Mínimo 10 caracteres')),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        ValueListenableBuilder<TextEditingValue>(valueListenable: controller, builder: (_, value, _) => FilledButton(
          onPressed: value.text.trim().length < 10 ? null : () => Navigator.pop(ctx, value.text.trim()), child: const Text('Eliminar pendiente')))],
    ));
    await Future<void>.delayed(const Duration(milliseconds: 300)); controller.dispose();
    if (note == null || !context.mounted) return;
    final user = ref.read(authStateProvider).user;
    if (user?.role != 'ADMIN' || user?.id != action.userId || user?.companyId != action.companyId) return;
    try {
      await OfflineStore.instance.archiveFailedDeclaration(id: action.id, companyId: action.companyId!, userId: action.userId!, actorRole: 'ADMIN', note: note);
      await ref.read(syncQueueServiceProvider.notifier).refreshStats();
      await onChanged?.call();
    } catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo retirar. La declaración sigue guardada.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = action.payload['totalDeclared'];
    final amount = total is num
        ? total.toDouble()
        : double.tryParse('${total ?? ''}');
    final note = (action.payload['note'] ?? '').toString().trim();
    // El estado real de la cola se dice tal cual: nunca se presenta como
    // «enviada» algo que todavía no llegó al servidor.
    final label = switch (action.status) {
      'failed' => 'Requiere revisión',
      'auth_blocked' => 'Inicia sesión',
      'error' => 'Reintentando',
      'syncing' => 'Enviando',
      _ => 'Por enviar',
    };
    return ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      expandedAlignment: Alignment.centerLeft,
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.outbox_outlined, size: 20),
      title: Text(
        amount == null
            ? 'Importe en revisión'
            : 'RD\$ ${amount.toStringAsFixed(2)}',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        label,
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      childrenPadding: const EdgeInsets.only(left: 36, bottom: 12),
      children: [
        SelectableText(
          key: PageStorageKey('declaration-reference-${action.id}'),
          'Referencia: ${action.payload['clientRequestId'] ?? action.entityId ?? ''}',
          style: const TextStyle(fontSize: 12),
        ),
        if (note.isNotEmpty)
          Text(note, style: const TextStyle(color: AppColors.textSecondary)),
        if (action.status == 'failed' && action.permanent)
          TextButton(onPressed: () => withdraw(context, ref), child: const Text('Eliminar pendiente'))
        else
          TextButton.icon(onPressed: () async {
            await ref.read(syncQueueServiceProvider.notifier).processPending();
            await onChanged?.call();
          }, icon: const Icon(Icons.sync, size: 16), label: const Text('Sincronizar declaración')),
      ],
    );
  }
}

class _ObligationCard extends ConsumerStatefulWidget {
  const _ObligationCard({required this.obligation});
  final ReconciliationObligation obligation;
  @override
  ConsumerState<_ObligationCard> createState() => _ObligationCardState();
}
class _ObligationCardState extends ConsumerState<_ObligationCard> {
  bool busy = false;
  Future<void> resolve(String decision) async {
    if (busy) return;
    String note = 'Comprobación del registro original por el administrador';
    if (decision == 'DISMISS') {
      final controller = TextEditingController();
      final result = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(
        title: const Text('Retirar declaración'),
        content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Confirma que la declaración era incorrecta. El historial se conserva; no se modifica dinero.'),
          const SizedBox(height: 12),
          TextField(controller: controller, maxLength: 500, decoration: const InputDecoration(labelText: 'Motivo', helperText: 'Mínimo 10 caracteres')),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ValueListenableBuilder<TextEditingValue>(valueListenable: controller, builder: (_, value, _) =>
            FilledButton(onPressed: value.text.trim().length < 10 ? null : () => Navigator.pop(ctx, value.text.trim()), child: const Text('Retirar declaración'))),
        ],
      ));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      controller.dispose();
      if (result == null || !mounted) return;
      note = result;
    }
    setState(() => busy = true);
    try {
      await ref.read(reconciliationResolutionProvider)(widget.obligation, decision, note);
      if (!mounted) return;
      final company = ref.read(authStateProvider).user?.companyId;
      if (company != null) ref.invalidate(reconciliationObligationsProvider(company));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Declaración resuelta. Historial conservado.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(userSafeErrorMessage(error, fallback: 'No se pudo resolver. La declaración sigue pendiente.'))));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${widget.obligation.currency} ${widget.obligation.totalDeclared.toStringAsFixed(2)}',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      const Text('Dinero declarado · pendiente de comprobar', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 6, children: [
        OutlinedButton(onPressed: busy ? null : () => resolve('CHECK'), child: const Text('Comprobar registro')),
        TextButton(onPressed: busy ? null : () => resolve('DISMISS'), child: const Text('Retirar declaración')),
      ]),
    ]),
  );
}

class _ObligationsNotice extends StatelessWidget {
  const _ObligationsNotice({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
