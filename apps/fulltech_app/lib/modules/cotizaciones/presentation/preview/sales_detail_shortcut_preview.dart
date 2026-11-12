import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../widgets/sales_detail_shortcut.dart';

/// Vista aislada de los accesos reales, con importes de ejemplo y sin servicios.
void main() => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: const SalesDetailShortcutPreview(),
  ),
);

class SalesDetailShortcutPreview extends StatelessWidget {
  const SalesDetailShortcutPreview({super.key});

  void _showAction(BuildContext context, String action) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$action · Vista previa sin datos de empresa')),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Vista previa · Accesos de venta')),
    body: Center(
      child: SizedBox(
        width: 550,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Se conservan cliente, tipo de factura, mayoreo y totales. Solo cambian los dos accesos oscuros.',
              ),
              const SizedBox(height: 24),
              Container(
                color: AppColors.surface,
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(6),
                      child: Row(
                        children: [
                          Text('Subtotal'),
                          Spacer(),
                          Text(r'RD$100.00'),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(6),
                      child: Row(
                        children: [
                          Text('Utilidad'),
                          Spacer(),
                          Text(
                            r'RD$100.00',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 64,
                            child: FilledButton(
                              onPressed: () => _showAction(context, 'Cobrar'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              child: const Row(
                                children: [
                                  Text(
                                    'Cobrar',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 18,
                                    ),
                                  ),
                                  Spacer(),
                                  Text(
                                    r'RD$100.00',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 26,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SalesDetailShortcut(
                          tooltip: 'Calculadora',
                          asset: SalesDetailShortcut.calculatorAsset,
                          onPressed: () => _showAction(context, 'Calculadora'),
                        ),
                        const SizedBox(width: 6),
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: SalesDetailShortcut(
                            tooltip: 'Ventas',
                            label: 'Ventas',
                            asset: SalesDetailShortcut.salesAsset,
                            width: 70,
                            iconSize: 28,
                            onPressed: () => _showAction(context, 'Ventas'),
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.all(6),
                      child: Row(
                        children: [
                          Text(
                            '1 producto agregado',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                            ),
                          ),
                          Spacer(),
                          Text(
                            'Cancelar venta',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Vista aislada · Importes de ejemplo. No registra ventas.',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
