import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/native_phone_layout.dart';

/// The backend has already confirmed POS readiness before this view is shown.
/// The local acknowledgement only controls the notice, never fiscal permission.
class EcfReadyHome extends StatefulWidget {
  const EcfReadyHome({
    super.key,
    required this.companyId,
    required this.userId,
    required this.onSales,
    required this.onDocuments,
    required this.onNumbering,
    required this.canManageNumbering,
    this.overview,
  });
  final String companyId, userId;
  final VoidCallback onSales, onDocuments, onNumbering;
  final bool canManageNumbering;
  final Widget? overview;

  @override
  State<EcfReadyHome> createState() => _EcfReadyHomeState();
}

class _EcfReadyHomeState extends State<EcfReadyHome> {
  bool _showNotice = false;

  @override
  void initState() {
    super.initState();
    _readAcknowledgement();
  }

  Future<void> _readAcknowledgement() async {
    if (widget.companyId.isEmpty || widget.userId.isEmpty) return;
    final key = 'ecf.ready-notice.v1.${widget.companyId}.${widget.userId}';
    try {
      final preferences = await SharedPreferences.getInstance();
      if (preferences.getBool(key) == true) return;
      final saved = await preferences.setBool(key, true);
      if (mounted && saved) setState(() => _showNotice = true);
    } catch (_) {
      // Optional acknowledgement cannot prevent access or grant permissions.
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.all(usesNativePhoneLayout(context) ? 12 : 24),
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 940),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_showNotice) ...[
              Material(
                color: AppColors.successSoft,
                borderRadius: BorderRadius.circular(6),
                child: ListTile(
                  leading: const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.success,
                  ),
                  title: const Text('Tu empresa está lista para facturar'),
                  trailing: IconButton(
                    tooltip: 'Cerrar confirmación',
                    onPressed: () => setState(() => _showNotice = false),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (!usesNativePhoneLayout(context)) Text(
              'Facturación electrónica',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (!usesNativePhoneLayout(context)) const SizedBox(height: 12),
            if (widget.overview != null) ...[
              widget.overview!,
              const SizedBox(height: 16),
            ],
            _entry(
              context,
              Icons.receipt_long_outlined,
              'Facturas electrónicas',
              widget.onDocuments,
            ),
            if (widget.canManageNumbering) ...[
              const SizedBox(height: 10),
              _entry(
                context,
                Icons.format_list_numbered,
                'Numeración fiscal',
                widget.onNumbering,
              ),
            ],
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: widget.onSales,
                icon: const Icon(Icons.point_of_sale_outlined, size: 18),
                label: const Text('Ir a ventas'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _entry(
    BuildContext context,
    IconData icon,
    String title,
    VoidCallback onTap,
  ) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
      side: const BorderSide(color: AppColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    ),
  );
}
