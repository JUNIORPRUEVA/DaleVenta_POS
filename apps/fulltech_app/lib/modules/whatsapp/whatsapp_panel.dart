import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'application/whatsapp_controller.dart';

/// Panel de gestión completa de la instancia WhatsApp del usuario en sesión.
/// Se puede embeber en cualquier pantalla (Configuración, WhatsApp, etc.).
class WhatsappPanel extends ConsumerStatefulWidget {
  const WhatsappPanel({
    super.key,
    this.defaultInstanceName,
    this.defaultPhoneNumber,
  });

  /// Pre-filled instance name (e.g. user name or company name).
  final String? defaultInstanceName;

  /// Pre-filled phone number with country prefix (e.g. 18095551234).
  final String? defaultPhoneNumber;

  @override
  ConsumerState<WhatsappPanel> createState() => _WhatsappPanelState();
}

class _WhatsappPanelState extends ConsumerState<WhatsappPanel> {
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
    _nameCtrl = TextEditingController(
      text: _sanitize(widget.defaultInstanceName ?? ''),
    );
    _phoneCtrl = TextEditingController(
      text: _prefixPhone(widget.defaultPhoneNumber ?? ''),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(whatsappControllerProvider.notifier).loadInstance();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  /// Creates instance then opens QR sheet.
  Future<void> _createAndConnect() async {
    if (_isConnecting) return;
    setState(() {
      _isConnecting = true;
      _connectError = null;
    });

    // Show "waiting" snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: const [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Espera un momento para que escanees el código QR…',
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 8),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();

    await ref
        .read(whatsappControllerProvider.notifier)
        .createInstance(
          instanceName: name.isEmpty ? null : name,
          phoneNumber: phone.isEmpty ? null : phone,
        );

    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    final s = ref.read(whatsappControllerProvider);
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
      builder: (_) => const WhatsappQrSheet(),
    );

    if (mounted) {
      await ref.read(whatsappControllerProvider.notifier).loadInstance();
    }
  }

  /// Opens QR sheet for an already-existing (pending) instance.
  Future<void> _openQrSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      isDismissible: false,
      builder: (_) => const WhatsappQrSheet(),
    );
    if (mounted) {
      await ref.read(whatsappControllerProvider.notifier).loadInstance();
    }
  }

  Future<void> _confirmReset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reiniciar instancia'),
        content: const Text(
          'Esto eliminará el registro actual (que está fallando) y podrás crear una nueva instancia de WhatsApp desde cero.',
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
      await ref.read(whatsappControllerProvider.notifier).deleteInstance();
    }
  }

  Future<void> _confirmDisconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desconectar WhatsApp'),
        content: const Text(
          '¿Deseas eliminar la instancia de WhatsApp? Deberás reconectar escaneando el QR nuevamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(whatsappControllerProvider.notifier).deleteInstance();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(whatsappControllerProvider);
    final exists = state.instance?.exists ?? false;

    if (state.isLoading) return const _WaLoadingCard();

    if (!exists) {
      return _WaCreateCard(
        nameCtrl: _nameCtrl,
        phoneCtrl: _phoneCtrl,
        isConnecting: _isConnecting || state.isCreating,
        error: _connectError,
        onConnect: _createAndConnect,
      );
    }

    final isConnected = state.instance?.isConnected ?? false;

    if (isConnected) {
      return _WaConnectedCard(
        state: state,
        onViewQr: _openQrSheet,
        onDisconnect: _confirmDisconnect,
      );
    }

    return _WaPendingCard(
      state: state,
      onScanQr: _openQrSheet,
      onReset: _confirmReset,
      onDisconnect: _confirmDisconnect,
    );
  }
}

// ─── Create card (no instance yet) ────────────────────────────────────────────

class _WaCreateCard extends StatelessWidget {
  const _WaCreateCard({
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
                  Icons.chat_rounded,
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
                      'Conectar WhatsApp',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sin instancia registrada',
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
              hintText: 'ej: mi_empresa',
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
            decoration: InputDecoration(
              hintText: 'ej: 18095551234',
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
              label: Text(isConnecting ? 'Conectando...' : 'Conectar'),
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

// ─── Connected card ────────────────────────────────────────────────────────────

class _WaConnectedCard extends StatelessWidget {
  const _WaConnectedCard({
    required this.state,
    required this.onViewQr,
    required this.onDisconnect,
  });

  final WhatsappState state;
  final VoidCallback onViewQr;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final instance = state.instance;
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
                      'WhatsApp',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Conectado',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((instance?.phoneNumber ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.phone_outlined,
              label: 'Número',
              value: instance!.phoneNumber!,
            ),
          ],
          if ((instance?.instanceName ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            _InfoRow(
              icon: Icons.memory_rounded,
              label: 'Instancia',
              value: instance!.instanceName!,
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
                label: Text(
                  'Desconectar',
                  style: TextStyle(color: scheme.error),
                ),
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

class _WaPendingCard extends StatelessWidget {
  const _WaPendingCard({
    required this.state,
    required this.onScanQr,
    required this.onReset,
    required this.onDisconnect,
  });

  final WhatsappState state;
  final VoidCallback onScanQr;
  final VoidCallback onReset;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final instance = state.instance;
    const statusColor = Color(0xFFF59E0B);

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
                      'WhatsApp',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Pendiente — sin conectar',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((instance?.instanceName ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            _InfoRow(
              icon: Icons.memory_rounded,
              label: 'Instancia',
              value: instance!.instanceName!,
            ),
          ],
          const SizedBox(height: 12),
          // Warning banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: statusColor.withValues(alpha: 0.30)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, color: statusColor, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Esta instancia no está activa en el servidor de WhatsApp. '
                    'Si el QR falla, usa "Reiniciar" para borrarla y crear una nueva.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Primary action: Reset to create fresh
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Reiniciar y crear nueva instancia'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Secondary action: try QR anyway
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onScanQr,
              icon: const Icon(Icons.qr_code_rounded),
              label: const Text('Intentar escanear QR'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Loading card ─────────────────────────────────────────────────────────────

class _WaLoadingCard extends StatelessWidget {
  const _WaLoadingCard();

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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
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

// ─── QR Bottom Sheet ─────────────────────────────────────────────────────────

class WhatsappQrSheet extends ConsumerStatefulWidget {
  const WhatsappQrSheet({super.key});

  @override
  ConsumerState<WhatsappQrSheet> createState() => _WhatsappQrSheetState();
}

class _WhatsappQrSheetState extends ConsumerState<WhatsappQrSheet> {
  void Function()? _stopPollingFn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ref.read(whatsappControllerProvider.notifier);
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
    final state = ref.watch(whatsappControllerProvider);
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
                ? '¡Gracias, ya está conectado!'
                : 'Escanea el código QR',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isConnected
                ? 'Tu WhatsApp fue conectado exitosamente.'
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
              onRetry: () =>
                  ref.read(whatsappControllerProvider.notifier).refreshQr(),
            )
          else if (qr != null && qr.qrBase64.isNotEmpty)
            _QrImageView(base64: qr.qrBase64)
          else
            const _QrLoadingView(),
          const SizedBox(height: 24),
          if (!isConnected)
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => ref
                            .read(whatsappControllerProvider.notifier)
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
                ),
                if (state.qrError != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await ref
                            .read(whatsappControllerProvider.notifier)
                            .deleteInstance();
                        if (context.mounted) Navigator.pop(context);
                      },
                      icon: Icon(
                        Icons.restart_alt_rounded,
                        color: scheme.error,
                      ),
                      label: Text(
                        'Reiniciar instancia',
                        style: TextStyle(color: scheme.error),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: scheme.error.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.thumb_up_alt_rounded),
                label: const Text('¡Listo!'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── QR Image ────────────────────────────────────────────────────────────────

class _QrImageView extends StatelessWidget {
  const _QrImageView({required this.base64});
  final String base64;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    try {
      final bytes = base64Decode(
        base64.contains(',') ? base64.split(',').last : base64,
      );
      return Container(
        width: 230,
        height: 230,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
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
      width: 230,
      height: 230,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            'Generando código QR…',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
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
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: theme.colorScheme.onErrorContainer,
            size: 32,
          ),
          const SizedBox(height: 8),
          Text(
            error,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
          const SizedBox(height: 10),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}
