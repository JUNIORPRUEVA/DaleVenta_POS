import 'package:flutter/material.dart';

import 'ecf_pos_fiscal.dart';

/// Selector fiscal del POS para empresas que facturan electrónicamente.
///
/// Sustituye al antiguo selector de talonarios B01/B02 (ya retirado). Las
/// opciones son E31/E32 y, solo si la empresa habilitó la excepción, «Normal».
///
/// El disparador NO es un campo de formulario: es una ficha con la etiqueta
/// pequeña y el comprobante elegido en grande, en esquinas rectas y con un
/// acento de color a la izquierda. Al pulsarla se despliega, **desde la propia
/// ficha**, una lista numerada y animada. Se descartó la hoja inferior y el
/// `InputDecorator` porque la etiqueta flotante se solapaba con el valor en
/// alturas compactas.
///
/// Una venta «Normal» es una venta interna: no lleva comprobante, no se declara
/// ante la DGII, no pide motivo y no muestra ningún aviso al vendedor. Solo se
/// ofrece si la empresa habilitó la opción.
class EcfPosFiscalSelector extends StatelessWidget {
  const EcfPosFiscalSelector({
    super.key,
    required this.modes,
    required this.selected,
    required this.onSelected,
    this.missingBuyer = false,
    this.compact = false,
  });

  final List<EcfPosFiscalMode> modes;
  final EcfPosFiscalMode? selected;

  final ValueChanged<EcfPosFiscalMode> onSelected;

  /// El modo elegido exige receptor y todavía no está identificado.
  final bool missingBuyer;

  final bool compact;

  static const Color _ink = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _line = Color(0xFFD6E2EF);
  static const Color _surface = Color(0xFFFFFFFF);

  @override
  Widget build(BuildContext context) {
    if (modes.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final current = selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final menuWidth = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : 288.0;
            return MenuAnchor(
              style: MenuStyle(
                backgroundColor: const WidgetStatePropertyAll(_surface),
                // Recto: la lista no lleva radios, igual que el disparador.
                shape: const WidgetStatePropertyAll(
                  RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                ),
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                // Mismo ancho que la ficha: el desplegable sale DE ella.
                minimumSize: WidgetStatePropertyAll(Size(menuWidth, 0)),
                elevation: const WidgetStatePropertyAll(14),
              ),
              menuChildren: [
                for (var i = 0; i < modes.length; i++)
                  _EcfModeMenuItem(
                    width: menuWidth,
                    index: i + 1,
                    mode: modes[i],
                    active: modes[i] == current,
                    onPressed: () => onSelected(modes[i]),
                  ),
              ],
              builder: (context, controller, child) {
                return _Trigger(
                  compact: compact,
                  current: current,
                  invalid: missingBuyer,
                  open: controller.isOpen,
                  theme: theme,
                  onTap: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                );
              },
            );
          },
        ),
        if (missingBuyer) ...[
          const SizedBox(height: 6),
          Text(
            'E31 exige un cliente con RNC/Cédula y nombre.',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// Ficha del comprobante elegido. Esquinas rectas y acento a la izquierda.
class _Trigger extends StatelessWidget {
  const _Trigger({
    required this.compact,
    required this.current,
    required this.invalid,
    required this.open,
    required this.theme,
    required this.onTap,
  });

  final bool compact;
  final EcfPosFiscalMode? current;
  final bool invalid;
  final bool open;
  final ThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = invalid ? theme.colorScheme.error : theme.colorScheme.primary;
    final hasValue = current != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          height: compact ? 44 : 50,
          decoration: BoxDecoration(
            color: open ? const Color(0xFFF6FAFF) : _EcfPosFiscalSelectorColors.surface,
            border: Border(
              left: BorderSide(color: accent, width: 3),
              top: BorderSide(
                color: open ? accent.withValues(alpha: 0.55) : _EcfPosFiscalSelectorColors.line,
              ),
              right: BorderSide(
                color: open ? accent.withValues(alpha: 0.55) : _EcfPosFiscalSelectorColors.line,
              ),
              bottom: BorderSide(
                color: open ? accent.withValues(alpha: 0.55) : _EcfPosFiscalSelectorColors.line,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'COMPROBANTE ELECTRÓNICO',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                        color: _EcfPosFiscalSelectorColors.muted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasValue ? current!.label : 'Elegir comprobante',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 12 : 13,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                        color: hasValue
                            ? (invalid
                                  ? theme.colorScheme.error
                                  : _EcfPosFiscalSelectorColors.ink)
                            : _EcfPosFiscalSelectorColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: open ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Entrada enumerada de la lista desplegable.
class _EcfModeMenuItem extends StatelessWidget {
  const _EcfModeMenuItem({
    required this.width,
    required this.index,
    required this.mode,
    required this.active,
    required this.onPressed,
  });

  final double width;
  final int index;
  final EcfPosFiscalMode mode;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return SizedBox(
      width: width,
      child: MenuItemButton(
        onPressed: onPressed,
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(
            EdgeInsets.fromLTRB(10, 10, 12, 10),
          ),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          ),
          backgroundColor: WidgetStatePropertyAll(
            active ? primary.withValues(alpha: 0.06) : Colors.transparent,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Número de la opción: la lista se lee como un enum.
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(
                  color: active
                      ? primary
                      : _EcfPosFiscalSelectorColors.line,
                  width: active ? 1.4 : 1,
                ),
              ),
              child: Text(
                '$index',
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: active
                      ? primary
                      : _EcfPosFiscalSelectorColors.muted,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mode.label,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                      color: active
                          ? primary
                          : _EcfPosFiscalSelectorColors.ink,
                    ),
                  ),
                ],
              ),
            ),
            if (active) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_rounded, size: 16, color: primary),
            ],
          ],
        ),
      ),
    );
  }
}

class _EcfPosFiscalSelectorColors {
  static const Color ink = EcfPosFiscalSelector._ink;
  static const Color muted = EcfPosFiscalSelector._muted;
  static const Color line = EcfPosFiscalSelector._line;
  static const Color surface = EcfPosFiscalSelector._surface;
}
