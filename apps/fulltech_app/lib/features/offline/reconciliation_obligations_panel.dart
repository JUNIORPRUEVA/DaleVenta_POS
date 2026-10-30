import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_routes.dart';
import '../../core/auth/auth_repository.dart';
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
      declaredAtUtc: DateTime.tryParse('${json['declaredAtUtc'] ?? ''}')?.toUtc(),
      paymentMethod: json['paymentMethod']?.toString(),
      declaredByUserId: json['declaredByUserId']?.toString(),
      declaredByRole: json['declaredByRole']?.toString(),
      note: json['note']?.toString(),
      resolvedAtUtc: DateTime.tryParse('${json['resolvedAt'] ?? ''}')?.toUtc(),
      resolutionNote: json['resolutionNote']?.toString(),
    );
  }
}

/// Lista de obligaciones pendientes. Solo lectura: resolverlas es una tarea
/// administrativa, no algo que esta pantalla deba inventar.
final reconciliationObligationsProvider = FutureProvider.autoDispose
    .family<List<ReconciliationObligation>, String>((ref, companyId) async {
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
            if (ReconciliationObligation.fromJson(
                  row.cast<String, dynamic>(),
                )
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
  });

  final String companyId;
  final List<PendingSyncAction> pendingDeclarations;

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
              'No pudimos consultar las obligaciones de conciliación. No se ha '
              'perdido ninguna declaración: se enviará sola cuando vuelva la '
              'conexión.',
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
                  'Estas declaraciones están pendientes de conciliación '
                  'administrativa. No crean ventas, pagos ni movimientos de caja: '
                  'la revisión se hace por el flujo oficial.',
            ),
            const SizedBox(height: 10),
            for (final declaration in pendingDeclarations) ...[
              _PendingDeclarationCard(action: declaration),
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
    if (pendingDeclarations.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        notice ??
            const _ObligationsNotice(
              icon: Icons.outbox_rounded,
              title: 'Declaraciones por enviar',
              body:
                  'Están guardadas en este equipo y se enviarán solas cuando '
                  'vuelva la conexión. Reintentar no crea duplicados.',
            ),
        const SizedBox(height: 10),
        for (final declaration in pendingDeclarations) ...[
          _PendingDeclarationCard(action: declaration),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _PendingDeclarationCard extends StatelessWidget {
  const _PendingDeclarationCard({required this.action});

  final PendingSyncAction action;

  @override
  Widget build(BuildContext context) {
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.outbox_rounded,
                size: 18,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  amount == null ? 'Importe en revisión' : 'RD\$ ${amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Operación ${(action.payload['clientRequestId'] ?? action.entityId ?? '').toString()}',
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textSecondary,
            ),
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              note,
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ObligationCard extends StatelessWidget {
  const _ObligationCard({required this.obligation});

  final ReconciliationObligation obligation;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.pending_actions_rounded,
                size: 18,
                color: AppColors.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${obligation.currency} ${obligation.totalDeclared.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const Text(
                'Conciliación pendiente',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Operación ${obligation.clientRequestId}',
            style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
          ),
          if (obligation.declaredAtUtc != null)
            Text(
              'Declarado: ${_formatDate(obligation.declaredAtUtc!)}'
              '${obligation.declaredByRole == null ? '' : ' · ${obligation.declaredByRole}'}',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
          if ((obligation.note ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              obligation.note!.trim(),
              style: const TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.textPrimary,
              ),
            ),
          ],
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
