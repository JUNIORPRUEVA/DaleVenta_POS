import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/plans_repository.dart';
import 'plan_ui.dart';

/// Rejilla de planes: 4 columnas en escritorio, 2 en tableta y 1 en telefono.
///
/// Todas las tarjetas comparten altura (IntrinsicHeight) y el boton queda
/// siempre alineado al pie.
class PlansGrid extends StatelessWidget {
  const PlansGrid({
    super.key,
    required this.plans,
    required this.currentPlanCode,
    required this.busy,
    required this.onChoose,
  });

  final List<PlanOffer> plans;
  final String? currentPlanCode;
  final bool busy;
  final ValueChanged<PlanOffer> onChoose;

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) {
      return const ErrorBlock(
        message: 'El catalogo de planes esta vacio. Contacta soporte.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1180 ? 4 : (width >= 660 ? 2 : 1);
        final gap = columns == 1 ? 14.0 : 18.0;
        final rows = <Widget>[];
        for (var i = 0; i < plans.length; i += columns) {
          final slice = plans.skip(i).take(columns).toList();
          rows.add(
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Los huecos se reservan: con un solo plan la tarjeta no se
                  // estira a todo el ancho de la pagina.
                  for (var j = 0; j < columns; j++) ...[
                    if (j < slice.length)
                      Expanded(
                        child: PlanCard(
                          plan: slice[j],
                          current:
                              currentPlanCode != null &&
                              currentPlanCode!.toLowerCase() ==
                                  slice[j].code.toLowerCase(),
                          busy: busy,
                          compact: columns == 1,
                          onChoose: () => onChoose(slice[j]),
                        ),
                      )
                    else
                      const Expanded(child: SizedBox()),
                    if (j < columns - 1) SizedBox(width: gap),
                  ],
                ],
              ),
            ),
          );
          if (i + columns < plans.length) {
            rows.add(SizedBox(height: gap));
          }
        }
        return Column(children: rows);
      },
    );
  }
}

/// Tonos del catalogo. Deliberadamente **fuera del azul de marca**: tarjetas
/// blancas, tinta grafito para el plan recomendado y grises muy suaves para
/// los bordes. El azul no desaparece del producto, pero no compite aqui.
class _Ink {
  const _Ink._();

  static const primary = Color(0xFF111827);
  static const secondary = Color(0xFF5A6572);
  static const muted = Color(0xFF8B95A3);
  static const hair = Color(0xFFE8ECF1);
  static const hairSoft = Color(0xFFF1F4F8);
  static const check = Color(0xFF0F9D6E);
}

class PlanCard extends StatelessWidget {
  const PlanCard({
    super.key,
    required this.plan,
    required this.current,
    required this.busy,
    required this.onChoose,
    this.compact = false,
  });

  final PlanOffer plan;
  final bool current;
  final bool busy;
  final VoidCallback onChoose;

  /// Columna unica (telefono): menos aire y menos funciones visibles.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final highlighted = plan.highlight && !current;
    final pad = compact ? 15.0 : 24.0;
    final features = plan.included
        .take(compact ? 4 : 6)
        .toList(growable: false);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlighted ? _Ink.primary : _Ink.hair,
          width: highlighted ? 1.4 : 1,
        ),
        boxShadow: highlighted
            ? const [
                BoxShadow(
                  color: Color(0x1A111827),
                  blurRadius: 28,
                  spreadRadius: -8,
                  offset: Offset(0, 12),
                ),
              ]
            : const [
                BoxShadow(
                  color: Color(0x0A111827),
                  blurRadius: 18,
                  spreadRadius: -6,
                  offset: Offset(0, 6),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, pad, pad, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    plan.shortName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 16 : 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: _Ink.primary,
                    ),
                  ),
                ),
                if (highlighted) ...[
                  const SizedBox(width: 8),
                  const _RecommendedBadge(),
                ],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(pad, compact ? 10 : 12, pad, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          money(plan.monthlyPrice, plan.currency),
                          style: TextStyle(
                            fontSize: compact ? 25 : 36,
                            fontWeight: FontWeight.w700,
                            height: 1,
                            letterSpacing: -1.1,
                            color: _Ink.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      '/mes',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: _Ink.muted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                // Lo que realmente hay que transferir hoy, con el credito de
                // los dias no consumidos ya aplicado por el servidor.
                _PayTodayLine(planCode: plan.code),
                SizedBox(height: compact ? 10 : 14),
                Container(height: 1, color: _Ink.hairSoft),
                SizedBox(height: compact ? 9 : 12),
                for (final item in features)
                  _FeatureLine(label: item, compact: compact),
              ],
            ),
          ),
          const Spacer(),
          Padding(
            padding: EdgeInsets.fromLTRB(pad, compact ? 6 : 12, pad, pad),
            child: _PlanAction(
              label: current ? 'Renovar plan' : 'Elegir plan',
              current: current,
              highlighted: highlighted,
              onPressed: busy ? null : onChoose,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendedBadge extends StatelessWidget {
  const _RecommendedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: _Ink.primary,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Más elegido',
        style: TextStyle(
          fontSize: 9.8,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Boton de la tarjeta: redondeado, bajo y sin azul.
class _PlanAction extends StatelessWidget {
  const _PlanAction({
    required this.label,
    required this.current,
    required this.highlighted,
    required this.onPressed,
  });

  final String label;
  final bool current;
  final bool highlighted;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final Color background;
    final Color foreground;
    final Color? border;
    if (current) {
      background = Colors.white;
      foreground = _Ink.primary;
      border = _Ink.primary;
    } else if (highlighted) {
      background = _Ink.primary;
      foreground = Colors.white;
      border = null;
    } else {
      background = Colors.white;
      foreground = _Ink.primary;
      border = _Ink.hair;
    }
    return SizedBox(
      height: 46,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: _Ink.hairSoft,
          disabledForegroundColor: _Ink.muted,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: border == null ? BorderSide.none : BorderSide(color: border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _FeatureLine extends StatelessWidget {
  const _FeatureLine({required this.label, required this.compact});

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 5 : 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1.5),
            child: Icon(Icons.check_rounded, size: 15, color: _Ink.check),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 12.3 : 14,
                height: 1.3,
                fontWeight: FontWeight.w500,
                color: _Ink.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// «Hoy pagas»: importe real a transferir con el credito ya aplicado.
///
/// Lo calcula el servidor; mientras no llega no se muestra ninguna cifra
/// (nunca se estima un dinero a mano).
class _PayTodayLine extends ConsumerWidget {
  const _PayTodayLine({required this.planCode});

  final String planCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quote = ref
        .watch(orderQuoteProvider((planCode: planCode, months: 1)))
        .valueOrNull;
    if (quote == null) return const SizedBox(height: 15);
    return SizedBox(
      height: 15,
      child: Text(
        'Hoy pagas ${money(quote.amountDue, quote.currency)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 11.8,
          fontWeight: FontWeight.w600,
          color: _Ink.secondary,
        ),
      ),
    );
  }
}
