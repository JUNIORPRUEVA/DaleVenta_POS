import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/company_whatsapp_controller.dart';
import 'whatsapp_instance_model.dart';

/// Panel for managing the company-level WhatsApp instance.
/// Displays create / QR / connected / pending states.
class CompanyWhatsappPanel extends ConsumerStatefulWidget {
  const CompanyWhatsappPanel({super.key});

  @override
  ConsumerState<CompanyWhatsappPanel> createState() =>
      _CompanyWhatsappPanelState();
}

class _CompanyWhatsappPanelState extends ConsumerState<CompanyWhatsappPanel> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  bool _isConnecting = false;
  String? _connectError;

  static String _sanitize(String raw) =>
      raw.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');

  static String _prefixPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('1') && digits.length >= 11) return digits;
    return '1$digits';
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: 'empresa');
    _phoneCtrl = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(companyWhatsappControllerProvider.notifier).loadStatus();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _createAndConnect() async {
    if (_isConnecting) return;
    setState(() {
      _isConnecting = true;
      _connectError = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Expanded(child: Text('Creando instancia de la empresa…')),
            ],
          ),
          duration: Duration(seconds: 8),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    final name = _sanitize(_nameCtrl.text);
    final phone = _prefixPhone(_phoneCtrl.text);

    await ref
        .read(companyWhatsappControllerProvider.notifier)
        .createInstance(
          instanceName: name.isEmpty ? null : name,
          phoneNumber: phone.isEmpty ? null : phone,
        );

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final s = ref.read(companyWhatsappControllerProvider);
    if (s.error != null) {
      setState(() {
        _isConnecting = false;
        _connectError = s.error;
      });
      return;
    }

    setState(() => _isConnecting = false);

    // ignore: use_build_context_synchronously
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      isDismissible: false,
      builder: (_) => const _CompanyQrSheet(),
    );

    if (mounted) {
      await ref.read(companyWhatsappControllerProvider.notifier).loadStatus();
    }
  }

  Future<void> _openQrSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      isDismissible: false,
      builder: (_) => const _CompanyQrSheet(),
    );
    if (mounted) {
      await ref.read(companyWhatsappControllerProvider.notifier).loadStatus();
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar instancia de la empresa'),
        content: const Text(
          '¿Seguro que deseas eliminar la instancia de WhatsApp de la empresa? '
          'Las notificaciones automáticas dejarán de funcionar hasta crear una nueva.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(companyWhatsappControllerProvider.notifier)
          .deleteInstance();
    }
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reiniciar instancia'),
        content: const Text(
          'Esto eliminará el registro actual y podrás crear una nueva instancia desde cero.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reiniciar'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref
          .read(companyWhatsappControllerProvider.notifier)
          .deleteInstance();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(companyWhatsappControllerProvider);
    final exists = state.instance?.exists ?? false;

    if (state.isLoading) {
      return const _CwLoadingCard();
    }

    if (!exists) {
      return _CwCreateCard(
        nameCtrl: _nameCtrl,
        phoneCtrl: _phoneCtrl,
        isConnecting: _isConnecting || state.isCreating,
        error: _connectError ?? state.error,
        onConnect: _createAndConnect,
      );
    }

    final isConnected = state.instance?.isConnected ?? false;

    if (isConnected) {
      return _CwConnectedCard(
        instance: state.instance!,
        onViewQr: _openQrSheet,
        onDisconnect: _confirmDelete,
      );
    }

    return _CwPendingCard(
      instance: state.instance!,
      onScanQr: _openQrSheet,
      onReset: _confirmReset,
    );
  }
}

// ─── Create card ──────────────────────────────────────────────────────────────

class _CwCreateCard extends StatelessWidget {
  const _CwCreateCard({
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.isConnecting,
    required this.onConnect,
    this.error,
  });

  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final bool isConnecting;
  final String? error;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.60),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF25D366).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.business_rounded,
                  color: Color(0xFF25D366),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Instancia de la empresa',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sin instancia configurada',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Nombre de la instancia',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: nameCtrl,
            enabled: !isConnecting,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: 'empresa',
              helperText: 'Solo letras, números, _ y -',
              prefixIcon: const Icon(Icons.label_rounded, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'Número de teléfono (con código de país)',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: phoneCtrl,
            enabled: !isConnecting,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => isConnecting ? null : onConnect(),
            decoration: InputDecoration(
              hintText: 'ej: 18095551234',
              helperText: 'Incluye código de país (1 para RD/USA)',
              prefixIcon: const Icon(Icons.phone_rounded, size: 18),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            style: theme.textTheme.bodyMedium,
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: scheme.onErrorContainer,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isConnecting ? null : onConnect,
              icon: isConnecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.link_rounded),
              label: Text(
                isConnecting ? 'Creando instancia...' : 'Crear y escanear QR',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Connected card ───────────────────────────────────────────────────────────

class _CwConnectedCard extends StatelessWidget {
  const _CwConnectedCard({
    required this.instance,
    required this.onViewQr,
    required this.onDisconnect,
  });

  final WhatsappInstanceStatusResponse instance;
  final VoidCallback onViewQr;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const statusColor = Color(0xFF16A34A);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  color: statusColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Instancia de la empresa',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Conectado',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((instance.phoneNumber ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            _CwInfoRow(
              icon: Icons.phone_outlined,
              label: 'Número',
              value: instance.phoneNumber!,
            ),
          ],
          if ((instance.instanceName ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            _CwInfoRow(
              icon: Icons.memory_rounded,
              label: 'Instancia',
              value: instance.instanceName!,
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: onViewQr,
                icon: const Icon(Icons.qr_code_rounded),
                label: const Text('Ver QR'),
              ),
              OutlinedButton.icon(
                onPressed: onDisconnect,
                icon: Icon(Icons.link_off_rounded, color: scheme.error),
                label: Text('Eliminar', style: TextStyle(color: scheme.error)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: scheme.error.withValues(alpha: 0.4)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Pending card ─────────────────────────────────────────────────────────────

class _CwPendingCard extends StatelessWidget {
  const _CwPendingCard({
    required this.instance,
    required this.onScanQr,
    required this.onReset,
  });

  final WhatsappInstanceStatusResponse instance;
  final VoidCallback onScanQr;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const statusColor = Color(0xFFF59E0B);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.60),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: statusColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Instancia de la empresa',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Pendiente — sin conectar',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((instance.instanceName ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            _CwInfoRow(
              icon: Icons.memory_rounded,
              label: 'Instancia',
              value: instance.instanceName!,
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onScanQr,
              icon: const Icon(Icons.qr_code_rounded),
              label: const Text('Escanear QR'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Reiniciar instancia'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Loading card ─────────────────────────────────────────────────────────────

class _CwLoadingCard extends StatelessWidget {
  const _CwLoadingCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

// ─── Info row ─────────────────────────────────────────────────────────────────

class _CwInfoRow extends StatelessWidget {
  const _CwInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── QR Sheet ─────────────────────────────────────────────────────────────────

class _CompanyQrSheet extends ConsumerStatefulWidget {
  const _CompanyQrSheet();

  @override
  ConsumerState<_CompanyQrSheet> createState() => _CompanyQrSheetState();
}

class _CompanyQrSheetState extends ConsumerState<_CompanyQrSheet> {
  void Function()? _stopPollingFn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ref.read(companyWhatsappControllerProvider.notifier);
      _stopPollingFn = controller.stopPolling;
      controller.refreshQr();
      controller.startPolling();
    });
  }

  @override
  void dispose() {
    _stopPollingFn?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(companyWhatsappControllerProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isConnected = state.instance?.isConnected ?? false;
    final qr = state.qr;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isConnected
                ? '¡WhatsApp de la empresa conectado!'
                : 'Escanea el código QR',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isConnected
                ? 'La instancia de la empresa fue conectada exitosamente.'
                : 'Abre WhatsApp → Menú → Dispositivos vinculados → Vincular.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          if (isConnected)
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: const Color(0xFF25D366).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF25D366),
                size: 52,
              ),
            )
          else if (state.qrError != null)
            _QrErrorView(
              error: state.qrError!,
              onRetry: () => ref
                  .read(companyWhatsappControllerProvider.notifier)
                  .refreshQr(),
            )
          else if (qr != null && qr.qrBase64.isNotEmpty)
            _QrImageView(base64: qr.qrBase64)
          else
            const _QrLoadingView(),
          const SizedBox(height: 24),
          if (!isConnected)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => ref
                        .read(companyWhatsappControllerProvider.notifier)
                        .refreshQr(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Actualizar QR'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cerrar'),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Listo'),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── QR image / loading / error helpers ──────────────────────────────────────

class _QrImageView extends StatelessWidget {
  const _QrImageView({required this.base64});
  final String base64;

  @override
  Widget build(BuildContext context) {
    try {
      final bytes = base64Decode(
        base64.contains(',') ? base64.split(',').last : base64,
      );
      return Container(
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF25D366).withValues(alpha: 0.4),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.all(10),
        child: Image.memory(bytes, fit: BoxFit.contain),
      );
    } catch (_) {
      return const _QrLoadingView();
    }
  }
}

class _QrLoadingView extends StatelessWidget {
  const _QrLoadingView();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 220,
      height: 220,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text(
              'Generando QR...',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _QrErrorView extends StatelessWidget {
  const _QrErrorView({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: scheme.onErrorContainer,
            size: 32,
          ),
          const SizedBox(height: 10),
          Text(
            error,
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onErrorContainer,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar'),
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
          ),
        ],
      ),
    );
  }
}
