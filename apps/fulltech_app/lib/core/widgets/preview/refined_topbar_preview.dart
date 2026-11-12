import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../branded_menu_button.dart';
import '../refined_topbar_controls.dart';

/// Muestra componentes reales con estados de ejemplo, sin consultar servicios.
void main() => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: const RefinedTopbarPreview(),
  ),
);

class RefinedTopbarPreview extends StatefulWidget {
  const RefinedTopbarPreview({super.key});

  @override
  State<RefinedTopbarPreview> createState() => _RefinedTopbarPreviewState();
}

class _RefinedTopbarPreviewState extends State<RefinedTopbarPreview> {
  bool _open = true;
  String _status = 'Sincronizado';
  bool _longCompany = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    drawer: const Drawer(
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Menú principal'),
        ),
      ),
    ),
    appBar: AppBar(
      toolbarHeight: 56,
      automaticallyImplyLeading: false,
      titleSpacing: 8,
      title: Builder(
        builder: (context) => BrandedMenuButton(
          onPressed: () => Scaffold.of(context).openDrawer(),
        ),
      ),
      shape: const Border(bottom: BorderSide(color: AppColors.border)),
      actions: [
        PopupMenuButton<bool>(
          tooltip: 'Estado del turno',
          onSelected: (value) => setState(() => _open = value),
          itemBuilder: (_) => const [
            PopupMenuItem(value: true, child: Text('Mostrar turno abierto')),
            PopupMenuItem(value: false, child: Text('Mostrar turno cerrado')),
          ],
          child: RefinedTurnChip(
            open: _open,
            unverified: false,
            activity: Icon(
              Icons.circle,
              size: 7,
              color: _open ? AppColors.primary : AppColors.textMuted,
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: 'Estado de sincronización: $_status',
          onSelected: (value) => setState(() => _status = value),
          itemBuilder: (_) => [
            for (final value in [
              'Sincronizado',
              'Pendientes',
              'Revisar',
              'Sin conexión',
            ])
              PopupMenuItem(value: value, child: Text(value)),
          ],
          child: RefinedSyncIndicator(
            label: _status,
            glyph: const Icon(
              Icons.sync_rounded,
              size: 18,
              color: AppColors.primary,
            ),
            badge: _status == 'Sincronizado'
                ? null
                : _status == 'Pendientes'
                ? '3'
                : '!',
            badgeColor: _status == 'Revisar'
                ? AppColors.error
                : AppColors.warning,
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<void>(
          tooltip: 'Cuenta y empresa',
          itemBuilder: (_) => const [
            PopupMenuItem(child: Text('Cuenta y empresa · Vista previa')),
          ],
          child: RefinedCompanyLabel(
            label: _longCompany
                ? 'Distribuidora de productos y servicios del Caribe'
                : 'Junior Lopez POS',
            logo: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.storefront_rounded,
                size: 14,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vista previa del AppBar',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text('Prueba los menús superiores para comparar sus estados.'),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => setState(() => _longCompany = !_longCompany),
            child: const Text('Probar nombre largo'),
          ),
          const Spacer(),
          Text(
            'Vista aislada · No modifica cajas, ventas ni datos de empresa.',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    ),
  );
}
