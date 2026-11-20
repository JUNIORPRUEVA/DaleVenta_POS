import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/license/license_repository.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/plans_repository.dart';
import '../plans_shell.dart';
import '../widgets/plan_ui.dart';
import '../widgets/plans_action_mixin.dart';

/// Pantalla unica de pago por transferencia.
///
/// Es **la misma** para cualquier estado de la licencia: renovar, pagar meses
/// por adelantado o cambiar de plan. El importe lo calcula el servidor
/// (`GET /license/orders/quote`), que descuenta lo no consumido cuando se
/// cambia de plan, asi que lo que se muestra es exactamente lo que viaja en la
/// orden y lo que el cliente debe transferir.
class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({
    super.key,
    this.planCode,
    this.months,
    this.startPayment = false,
  });

  /// Plan pedido desde el catalogo (si viene, manda sobre el plan actual).
  final String? planCode;
  final int? months;
  /// `true` cuando el cliente ya eligio pagar: se muestra el detalle.
  final bool startPayment;

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen>
    with PlansActionMixin {
  int _months = 1;
  bool _initialized = false;
  /// Comprobante ya subido en esta pantalla (nombre del archivo).
  String? _evidenceName;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _months = (widget.months ?? 1).clamp(1, 12);
  }

  String? _targetPlanCode(LicenseStatusModel? license) {
    final fromQuery = (widget.planCode ?? '').trim().toLowerCase();
    if (fromQuery.isNotEmpty) return fromQuery;
    final current = license?.planCode?.trim().toLowerCase();
    return current == null || current.isEmpty ? null : current;
  }

  Future<void> _generateOrder(OrderQuote quote) async {
    final created = await run(
      () => ref
          .read(plansRepositoryProvider)
          .createOrder(quote.planCode, months: quote.months),
    );
    if (created == null) return;
    ref.invalidate(licenseOrdersProvider);
    // La licencia cambia en cuanto existe la orden (queda pendiente de pago):
    // se vuelve a pedir para que el aviso de la app se actualice al instante.
    ref.invalidate(licenseStatusProvider);
    snack('Orden ${created.reference} creada. Transfiere y sube el comprobante.');
  }

  Future<void> _upload(LicenseOrder order) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: kIsWeb,
    );
    final file = picked?.files.isEmpty == false ? picked!.files.first : null;
    if (!mounted || file == null) return;
    final path = kIsWeb ? null : file.path;
    if (file.size > 8 * 1024 * 1024) {
      snack('El comprobante no puede superar 8 MB.');
      return;
    }
    if (file.bytes == null && path == null) {
      snack('No se pudo leer el comprobante. Seleccionalo nuevamente.');
      return;
    }

    final result = await run(
      () => ref.read(plansRepositoryProvider).uploadEvidence(
        orderId: order.id,
        filePath: path,
        fileBytes: file.bytes,
        fileName: file.name,
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _evidenceName = file.name);
    ref.invalidate(licenseOrdersProvider);
    ref.invalidate(licenseStatusProvider);
    snack(
      result.activated
          ? 'Comprobante recibido. Tu plan quedo actualizado.'
          : 'Comprobante recibido. Queda en revision.',
    );
  }

  /// Ultimo paso: el cliente confirma que hizo la transferencia del monto
  /// exacto. Sin esa confirmacion el pago no se da por bueno.
  Future<void> _confirmPayment(OrderQuote? quote) async {
    final amount = quote == null
        ? 'el monto exacto'
        : money(quote.amountDue, quote.currency);
    final ok = await confirm(
      title: 'Confirmar pago',
      message:
          'Estas seguro de que realizaste la transferencia de $amount a la '
          'cuenta de FULLTECH, SRL con la referencia de la orden?',
      accept: 'Si, ya transferi',
    );
    if (!ok) return;
    snack('Pago confirmado. Soporte lo verifica y tu plan se actualiza.');
  }

  Future<void> _cancel(LicenseOrder order) async {
    final ok = await confirm(
      title: 'Cancelar orden',
      message: 'La orden ${order.reference} dejara de estar disponible.',
      accept: 'Cancelar orden',
    );
    if (!ok) return;
    final done = await run(() async {
      await ref.read(plansRepositoryProvider).cancelOrder(order.id);
      return true;
    });
    if (done != true) return;
    ref.invalidate(licenseOrdersProvider);
    snack('Orden cancelada.');
  }

  @override
  Widget build(BuildContext context) {
    final license = ref.watch(licenseStatusProvider).valueOrNull;
    final orders = ref.watch(licenseOrdersProvider).valueOrNull ?? const [];
    final instructions = ref.watch(paymentInstructionsProvider).valueOrNull;
    final planCode = _targetPlanCode(license);
    final wide = MediaQuery.sizeOf(context).width >= 980;

    // Entrada sin eleccion previa: centro de pagos (estado + dos caminos).
    final isHub = !widget.startPayment && (widget.planCode ?? '').isEmpty;
    if (isHub) {
      return _PagosHub(
        license: license,
        orders: orders,
      );
    }

    final quoteAsync = planCode == null
        ? const AsyncValue<OrderQuote>.loading()
        : ref.watch(
            orderQuoteProvider((planCode: planCode, months: _months)),
          );
    final quote = quoteAsync.valueOrNull;
    final openOrder = openOrderOf(orders);
    final orderMatches =
        openOrder != null &&
        quote != null &&
        openOrder.planCode == quote.planCode &&
        openOrder.months == quote.months &&
        openOrder.amount == quote.amountDue;
    // El saldo cubre la mejora: no hay nada que transferir.
    final covered = quote?.covered == true;
    // Hay cuota vencida o una orden abierta: no es «pago adelantado».
    final owes = license?.renewal?.isOverdue == true || openOrder != null;
    // La cuota pendiente del plan actual **no se cancela**: solo se descarta
    // sola cuando el cliente paga otro plan. Si la orden es de un cambio de
    // plan, si se puede cancelar.
    final renewalOrder =
        openOrder != null &&
        (license?.planCode ?? '').trim().toLowerCase() ==
            openOrder.planCode.trim().toLowerCase() &&
        openOrder.months == 1;
    final canCancelOrder =
        orderMatches && !renewalOrder && !(license?.renewal?.isOverdue == true);

    return PopScope(
      // Con una orden abierta no se sale sin terminar el pago o cancelarla.
      canPop: !orderMatches,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        snack('Termina el pago o cancela la orden para salir.');
      },
      child: PlansShell(
      section: PlansSection.pago,
      actions: [
        TextButton.icon(
          onPressed: () => context.push(Routes.planesHistorial),
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: const Text('Historial de transferencia'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            textStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 6,
                  child: _ResumenCard(
                    quoteAsync: quoteAsync,
                    quote: quote,
                    months: _months,
                    isActive: license?.isUsable == true,
                    onMonths: (value) => setState(() => _months = value),
                    orderMatches: orderMatches,
                    openOrder: openOrder,
                    busy: busy,
                    onGenerate: quote == null
                        ? null
                        : () => _generateOrder(quote),
                    onRetryQuote: planCode == null
                        ? null
                        : () => ref.invalidate(
                            orderQuoteProvider((
                              planCode: planCode,
                              months: _months,
                            )),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(flex: 5, child: _PasosCard()),
              ],
            )
          else ...[
            _ResumenCard(
              quoteAsync: quoteAsync,
              quote: quote,
              months: _months,
              isActive: license?.isUsable == true,
              onMonths: (value) => setState(() => _months = value),
              orderMatches: orderMatches,
              openOrder: openOrder,
              busy: busy,
              onGenerate: quote == null ? null : () => _generateOrder(quote),
              onRetryQuote: planCode == null
                  ? null
                  : () => ref.invalidate(
                      orderQuoteProvider((
                        planCode: planCode,
                        months: _months,
                      )),
                    ),
            ),
            const SizedBox(height: 12),
            const _PasosCard(),
          ],
          // Con saldo suficiente no hay transferencia: no se muestran datos
          // bancarios ni se pide comprobante.
          if (covered)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'La plataforma aplica tu saldo y activa el plan nuevo. No envies dinero.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          if (!covered) ...[
            const SizedBox(height: 12),
            _BancoCard(
              instructions: instructions,
              order: orderMatches ? openOrder : null,
              evidenceName: _evidenceName,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SquareButton(
                  label: covered
                      ? (orderMatches
                            ? 'Solicitud enviada, revisando tu saldo'
                            : 'Solicitar la mejora con mi saldo')
                      : _evidenceName != null
                      ? 'Confirmar pago'
                      : orderMatches
                      ? 'Subir comprobante de la transferencia'
                      : (license?.isUsable == true
                            ? (owes
                                  ? 'Generar orden para transferir'
                                  : 'Pagar por adelantado')
                            : 'Generar orden para transferir'),
                  icon: covered
                      ? Icons.verified_rounded
                      : _evidenceName != null
                      ? Icons.verified_rounded
                      : orderMatches
                      ? Icons.upload_file_rounded
                      : Icons.arrow_forward_rounded,
                  onPressed: busy
                      ? null
                      : covered
                      ? (orderMatches || quote == null
                            ? null
                            : () => _generateOrder(quote))
                      : _evidenceName != null
                      ? () => _confirmPayment(quote)
                      : orderMatches
                      ? () => _upload(openOrder)
                      : quote == null
                      ? null
                      : () => _generateOrder(quote),
                ),
              ),
              if (canCancelOrder) ...[
                const SizedBox(width: 10),
                SizedBox(
                  width: 190,
                  child: SquareButton(
                    label: 'Cancelar orden',
                    variant: SquareVariant.ghost,
                    onPressed: busy ? null : () => _cancel(openOrder),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Tambien puedes hacer este proceso desde la app movil: es el mismo '
            'y ahi tienes mas comodidad.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Centro de pagos: estado de la suscripcion y los dos caminos posibles.
///
/// Es la primera pantalla al entrar en «Transferencia». Si el cliente esta al
/// dia lo dice con un visto; si debe algo, ofrece pagar.
class _PagosHub extends ConsumerWidget {
  const _PagosHub({required this.license, required this.orders});

  final LicenseStatusModel? license;
  final List<LicenseOrder> orders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(plansCatalogProvider).valueOrNull ?? const [];
    final openOrder = openOrderOf(orders);
    final planName = currentPlanName(license, catalog) ?? 'Tu plan';
    final price = _monthlyPriceOf(license, catalog);

    // El servidor decide el estado de la cuota; aqui solo se dibuja.
    final renewal = license?.renewal;
    final inReview = renewal?.isInReview == true;
    final overdue = renewal?.isOverdue == true;
    final pending = openOrder != null;
    final upcoming = renewal?.isUpcoming == true;

    IconData icon;
    Color tint;
    String title;
    String detail;
    if (inReview) {
      // El cliente **si** pago: no se le habla como si no lo hubiera hecho.
      icon = Icons.hourglass_top_rounded;
      tint = const Color(0xFF1D4ED8);
      title = 'Tu pago esta en verificacion';
      detail =
          'Recibimos tu comprobante${renewal?.order?.reference != null ? ' ${renewal!.order!.reference}' : ''} '
          'y lo estamos revisando. Tu plan sigue activo hasta '
          '${_shortDate(license?.periodEndsAt)}: no tienes que pagar de nuevo.';
    } else if (overdue) {
      icon = Icons.error_outline_rounded;
      tint = const Color(0xFFB45309);
      title = 'Tu cuota esta vencida';
      detail =
          'Tu plan vencio el ${_shortDate(license?.periodEndsAt)}. '
          'Paga ahora para reactivarlo sin perder datos.';
    } else if (upcoming) {
      // Cuota proxima: **no** esta vencida, aunque ya exista una orden abierta
      // (la genera el recordatorio). El servicio sigue activo.
      icon = Icons.schedule_rounded;
      tint = const Color(0xFFB45309);
      title = 'Tu proxima cuota esta por vencer';
      detail =
          'Vence en ${renewal?.daysLeft ?? 0} '
          '${(renewal?.daysLeft ?? 0) == 1 ? 'dia' : 'dias'}. '
          'Puedes pagarla ya y tu servicio no se interrumpe.';
    } else if (pending) {
      icon = Icons.error_outline_rounded;
      tint = const Color(0xFFB45309);
      title = 'Tienes un pago pendiente';
      detail = 'Completa la transferencia para reactivar tu plan.';
    } else {
      icon = Icons.check_circle_rounded;
      tint = const Color(0xFF15803D);
      title = 'Tu suscripcion esta al dia';
      detail =
          'No tienes ningun pago pendiente. Puedes adelantar meses o mejorar '
          'tu plan cuando quieras.';
    }

    final showNextDue = inReview == false && (upcoming || overdue || pending);
    // Hay algo que pagar hoy: ni «adelantado» ni «cuota proxima» — es la
    // cuota pendiente y el boton debe decirlo asi.
    final owes = overdue || pending;
    final payPath = () {
      final code = (renewal?.planCode ?? license?.planCode ?? '').trim();
      return code.isEmpty
          ? '${Routes.planesPago}?paso=pagar'
          : '${Routes.planesPago}?plan=$code&paso=pagar';
    }();

    return PlansShell(
      section: PlansSection.pago,
      actions: [
        TextButton.icon(
          onPressed: () => context.push(Routes.planesHistorial),
          icon: const Icon(Icons.receipt_long_outlined, size: 18),
          label: const Text('Historial de transferencia'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            textStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlansPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 22, color: tint),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Container(height: 1, color: AppColors.border),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _HubStat(label: 'Plan', value: planName),
                    ),
                    Expanded(
                      child: _HubStat(
                        label: 'Mensualidad',
                        value: price == null
                            ? '—'
                            : money(price, 'DOP'),
                      ),
                    ),
                    Expanded(
                      child: _HubStat(
                        label: 'Vence',
                        value: _shortDate(license?.periodEndsAt),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (showNextDue) ...[
            const SizedBox(height: 12),
            _NextDueCard(
              renewal: renewal,
              fallbackAmount: price,
              overdue: overdue,
              pendingReference: pending ? openOrder.reference : null,
              onPay: () {
                final code = renewal?.planCode ?? license?.planCode;
                final plan = (code ?? '').trim();
                context.push(
                  plan.isEmpty
                      ? '${Routes.planesPago}?paso=pagar'
                      : '${Routes.planesPago}?plan=$plan&paso=pagar',
                );
              },
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SquareButton(
                  label: owes
                      ? 'Pagar cuota pendiente'
                      : 'Pagar meses por adelantado',
                  icon: owes
                      ? Icons.arrow_forward_rounded
                      : Icons.event_repeat_rounded,
                  onPressed: () => context.push(
                    owes ? payPath : '${Routes.planesPago}?paso=pagar',
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SquareButton(
                  label: 'Mejorar mi plan',
                  variant: SquareVariant.outline,
                  icon: Icons.trending_up_rounded,
                  onPressed: () =>
                      context.push('${Routes.planesCatalogo}?superiores=1'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Al mejorar de plan se descuenta el valor del tiempo que ya tienes pagado, '
            'incluidos los meses adelantados.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  double? _monthlyPriceOf(LicenseStatusModel? license, List<PlanOffer> catalog) {
    final code = license?.planCode?.trim().toLowerCase();
    if (code == null || code.isEmpty) return null;
    for (final plan in catalog) {
      if (plan.code.toLowerCase() == code) return plan.monthlyPrice;
    }
    return null;
  }

  String _shortDate(DateTime? value) {
    if (value == null) return '—';
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}

/// Cuota que ya se puede pagar: importe, vencimiento y «Pagar ahora».
///
/// Pagar aqui **no** cobra dos veces: al confirmar el pago, el servidor suma
/// el mes al vencimiento actual, asi que los dias que quedan no se pierden.
class _NextDueCard extends StatelessWidget {
  const _NextDueCard({
    required this.renewal,
    required this.fallbackAmount,
    required this.overdue,
    required this.pendingReference,
    required this.onPay,
  });

  final RenewalInfo? renewal;
  final double? fallbackAmount;
  final bool overdue;
  final String? pendingReference;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final amount = renewal?.amount ?? fallbackAmount;
    final currency = renewal?.currency ?? 'DOP';
    final due = renewal?.dueDate;
    final days = renewal?.daysLeft;
    final reference = renewal?.order?.reference ?? pendingReference;

    return PlansPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PlansEyebrow(
                overdue ? 'CUOTA VENCIDA' : 'PROXIMA CUOTA',
              ),
              const Spacer(),
              if (days != null && !overdue)
                Text(
                  days == 1 ? 'vence manana' : 'en $days dias',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB45309),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      amount == null ? '—' : money(amount, currency),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      due == null
                          ? 'Fecha de vencimiento por confirmar'
                          : 'Vence el ${_formatDate(due)} · 1 mes',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 150,
                child: SquareButton(
                  label: 'Pagar ahora',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: onPay,
                ),
              ),
            ],
          ),
          if (reference != null && reference.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Referencia: ${reference.trim()}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Si pagas antes del vencimiento, el mes se suma a tu periodo actual: '
            'no pierdes los dias que te quedan.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
  }
}

class _HubStat extends StatelessWidget {
  const _HubStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Importe a pagar hoy, con selector de meses y el credito aplicado.
class _ResumenCard extends StatelessWidget {
  const _ResumenCard({
    required this.quoteAsync,
    required this.quote,
    required this.months,
    required this.isActive,
    required this.onMonths,
    required this.orderMatches,
    required this.openOrder,
    required this.busy,
    required this.onGenerate,
    this.onRetryQuote,
  });
  final AsyncValue<OrderQuote> quoteAsync;
  final OrderQuote? quote;
  final int months;
  final bool isActive;
  final ValueChanged<int> onMonths;
  final bool orderMatches;
  final LicenseOrder? openOrder;
  final bool busy;
  final VoidCallback? onGenerate;
  final VoidCallback? onRetryQuote;

  @override
  Widget build(BuildContext context) {
    return PlansPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: PlansEyebrow(
                  orderMatches
                      ? 'Pago pendiente · transfiere este monto'
                      : isActive
                      ? 'Estas al dia · paga por adelantado'
                      : 'Lo que vas a pagar hoy',
                ),
              ),
              _MesesSelector(months: months, onChanged: onMonths),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quote?.planName ?? 'Plan',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      quote?.planChange == true
                          ? 'Cambio de plan: se descuenta lo que aun no consumes.'
                          : isActive
                          ? 'Adelanta los meses que quieras: se suman al periodo actual.'
                          : 'Renovacion del plan que tienes.',
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (quoteAsync.isLoading)
            const LoadingBlock(height: 96)
          else if (quoteAsync.hasError)
            ErrorBlock(
              message: errorText(quoteAsync.error ?? ''),
              // Reintentar tiene que **volver a pedir** la cotización; antes
              // llamaba a `onGenerate`, que es nulo justo cuando falla, asi que
              // el boton no hacia nada y parecia que la API seguia caida.
              onRetry: onRetryQuote ?? onGenerate,
            )
          else if (quote != null) ...[
            _MoneyLine(
              label: '${quote!.months} x ${money(quote!.monthlyPrice, quote!.currency)}',
              value: money(quote!.subtotal, quote!.currency),
            ),
            if (quote!.hasCredit)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: _MoneyLine(
                  label:
                      'Lo que aun no consumes (${quote!.creditDays} dias)',
                  value: '- ${money(quote!.credit, quote!.currency)}',
                  highlight: const Color(0xFF15803D),
                ),
              ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: const BoxDecoration(color: AppColors.primarySoft),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      quote!.covered
                          ? 'No requiere transferencia'
                          : 'Total a transferir',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                  Text(
                    money(quote!.amountDue, quote!.currency),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ],
              ),
            ),
            if (quote!.covered)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Tu saldo cubre la mejora completa: no tienes que transferir nada.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF15803D),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            const Text(
              'Se suma a tu plan al confirmar el pago.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            if (orderMatches && openOrder != null)
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 16,
                    color: Color(0xFF15803D),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Orden ${openOrder!.reference} lista: transfiere este monto exacto.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF15803D),
                      ),
                    ),
                  ),
                ],
              )
            else
              const Text(
                'Al continuar se genera la orden con su referencia. Escribirla en el '
                'banco ayuda, pero no es obligatoria: tu comprobante llega con la orden.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Los tres pasos, siempre visibles.
class _PasosCard extends StatelessWidget {
  const _PasosCard();

  static const _steps = <(String, String, String)>[
    (
      '1',
      'Transfiere el monto exacto',
      'Usa el total que aparece a la izquierda. Si puedes, escribe la referencia; si no, no pasa nada.',
    ),
    (
      '2',
      'Sube el comprobante',
      'PDF o foto de la transferencia. Queda guardado en un almacen privado.',
    ),
    (
      '3',
      'Listo: tu plan se renueva',
      'Soporte verifica el pago. Si algo no cuadra, te escribe por WhatsApp.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return PlansPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PlansEyebrow('Como funciona'),
          const SizedBox(height: 10),
          for (var i = 0; i < _steps.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  color: AppColors.primary,
                  child: Text(
                    _steps[i].$1,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _steps[i].$2,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _steps[i].$3,
                        style: const TextStyle(
                          fontSize: 11.8,
                          height: 1.35,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Datos bancarios y referencia. Nunca se inventan: si no estan configurados,
/// se dice y el cliente contacta soporte.
class _BancoCard extends StatelessWidget {
  const _BancoCard({
    required this.instructions,
    required this.order,
    this.evidenceName,
  });

  final PaymentInstructions? instructions;
  final LicenseOrder? order;
  /// Comprobante ya subido: se muestra pequeno bajo la referencia.
  final String? evidenceName;

  @override
  Widget build(BuildContext context) {
    final data = instructions;
    final account = data?.accountNumber;
    return PlansPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PlansEyebrow('Datos para transferir'),
          const SizedBox(height: 8),
          // Aviso previo: monto exacto y a nombre de quien se paga.
          if ((data?.beforeTransfer ?? '').trim().isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              color: AppColors.primarySoft,
              child: Text(
                data!.beforeTransfer!,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (account != null && account.trim().isNotEmpty)
                      Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Cuenta ${data?.accountType ?? ''}'.trim(),
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              Text(
                                account,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            tooltip: 'Copiar cuenta',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: account));
                              showPlansToast(context, 'Cuenta copiada');
                            },
                            icon: const Icon(Icons.copy_rounded, size: 18),
                          ),
                        ],
                      ),
                    if ((data?.holder ?? '').trim().isNotEmpty)
                      _BankLine('Titular', data!.holder!),
                    if ((data?.holderTaxId ?? '').trim().isNotEmpty)
                      // El boton va pegado al valor: se lee como parte del RNC.
                      _BankLine(
                        'RNC',
                        data!.holderTaxId!,
                        trailing: IconButton(
                          tooltip: 'Copiar RNC',
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: data.holderTaxId!),
                            );
                            showPlansToast(context, 'RNC copiado');
                          },
                          icon: const Icon(Icons.copy_rounded, size: 16),
                        ),
                      ),
                    if ((data?.bankName ?? '').trim().isNotEmpty)
                      _BankLine('Banco', data!.bankName!),
                    if (data?.singleAccount == true)
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text(
                          'Esta es la unica cuenta para pagos.',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ),
                    if ((data?.otherBankNote ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4E5),
                          border: Border.all(color: const Color(0xFFF0B45F)),
                        ),
                        child: Text(
                          data!.otherBankNote!,
                          style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF9A5B00),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PlansEyebrow('Referencia'),
                    const SizedBox(height: 8),
                    if (order == null)
                      const Text(
                        'Se genera al crear la orden. No hace falta escribirla en el banco: '
                        'tu comprobante se asocia solo a esta orden.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      )
                    else ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              order!.reference,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.4,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copiar referencia',
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: order!.reference),
                              );
                              showPlansToast(context, 'Referencia copiada');
                            },
                            icon: const Icon(Icons.copy_rounded, size: 18),
                          ),
                        ],
                      ),
                      Text(
                        'Monto: ${money(order!.amount, order!.currency)} · '
                        '${order!.months} ${order!.months == 1 ? 'mes' : 'meses'}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'No hace falta escribir la referencia en el banco: tu comprobante '
                        'se asocia solo a esta orden.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                    if ((evidenceName ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSubtle,
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.receipt_outlined,
                              size: 16,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Comprobante subido',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                  Text(
                                    evidenceName!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BankLine extends StatelessWidget {
  const _BankLine(this.label, this.value, {this.trailing});

  final String label;
  final String value;
  /// Accion pegada al valor (por ejemplo, copiar).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 66,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textMuted,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoneyLine extends StatelessWidget {
  const _MoneyLine({
    required this.label,
    required this.value,
    this.highlight,
  });

  final String label;
  final String value;
  final Color? highlight;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: highlight ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Meses a pagar: de 1 a 12. Se puede pagar por adelantado.
class _MesesSelector extends StatelessWidget {
  const _MesesSelector({required this.months, required this.onChanged});

  final int months;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: months,
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
          items: [
            for (var m = 1; m <= 12; m++)
              DropdownMenuItem(
                value: m,
                child: Text(m == 1 ? '1 mes' : '$m meses'),
              ),
          ],
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

