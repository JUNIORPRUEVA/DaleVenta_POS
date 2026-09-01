import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/token_storage.dart';
import 'offline_store.dart';
import 'sync_queue_service.dart';

enum SyncHeaderStatus { synced, syncing, pending, error }

SyncHeaderStatus resolveSyncHeaderStatus(SyncQueueState state) {
  if (state.isProcessing || state.syncingCount > 0) {
    return SyncHeaderStatus.syncing;
  }
  if (state.errorCount > 0 || (state.lastError ?? '').trim().isNotEmpty) {
    return SyncHeaderStatus.error;
  }
  if (state.pendingCount > 0) {
    return SyncHeaderStatus.pending;
  }
  return SyncHeaderStatus.synced;
}

class SyncStatusMenuButton extends ConsumerWidget {
  const SyncStatusMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncQueueServiceProvider);
    final status = resolveSyncHeaderStatus(state);
    final colors = _SyncStatusColors.forStatus(status);
    final label = _statusLabel(status);
    final isProcessing = state.isProcessing || state.syncingCount > 0;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final menuWidth = screenWidth < 420
        ? (screenWidth - 24).clamp(284.0, 360.0)
        : 336.0;

    return PopupMenuButton<void>(
      tooltip: 'Estado de sincronización',
      offset: const Offset(0, 42),
      padding: EdgeInsets.zero,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      constraints: BoxConstraints(minWidth: menuWidth, maxWidth: menuWidth),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.border),
      ),
      itemBuilder: (menuContext) => [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _SyncStatusPopover(
            state: state,
            status: status,
            colors: colors,
            width: menuWidth,
            onSyncNow: isProcessing
                ? null
                : () {
                    Navigator.of(menuContext).pop();
                    unawaited(
                      ref
                          .read(syncQueueServiceProvider.notifier)
                          .processPending(),
                    );
                  },
          ),
        ),
      ],
      child: _SyncHeaderButton(
        label: label,
        colors: colors,
        syncing: isProcessing,
      ),
    );
  }

  static String _statusLabel(SyncHeaderStatus status) {
    return switch (status) {
      SyncHeaderStatus.synced => 'Sync',
      SyncHeaderStatus.syncing => 'Sync',
      SyncHeaderStatus.pending => 'Pendiente',
      SyncHeaderStatus.error => 'Revisar',
    };
  }
}

class _SyncHeaderButton extends StatefulWidget {
  const _SyncHeaderButton({
    required this.label,
    required this.colors,
    required this.syncing,
  });

  final String label;
  final _SyncStatusColors colors;
  final bool syncing;

  @override
  State<_SyncHeaderButton> createState() => _SyncHeaderButtonState();
}

class _SyncHeaderButtonState extends State<_SyncHeaderButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _pressed;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerCancel: (_) => setState(() => _pressed = false),
        onPointerUp: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : (_hovered ? 1.012 : 1),
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: 36,
            padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
            decoration: BoxDecoration(
              color: active ? widget.colors.activeBackground : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: widget.colors.border),
              boxShadow: [
                BoxShadow(
                  color: widget.colors.accent.withValues(
                    alpha: active ? 0.15 : 0.08,
                  ),
                  blurRadius: active ? 14 : 8,
                  spreadRadius: -4,
                  offset: Offset(0, active ? 5 : 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SyncGlyph(
                  color: widget.colors.accent,
                  syncing: widget.syncing,
                ),
                const SizedBox(width: 7),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.colors.foreground,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SyncGlyph extends StatefulWidget {
  const _SyncGlyph({required this.color, required this.syncing});

  final Color color;
  final bool syncing;

  @override
  State<_SyncGlyph> createState() => _SyncGlyphState();
}

class _SyncGlyphState extends State<_SyncGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 980),
    );
    _syncAnimationState();
  }

  @override
  void didUpdateWidget(covariant _SyncGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncing != widget.syncing) _syncAnimationState();
  }

  void _syncAnimationState() {
    if (widget.syncing) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: RotationTransition(
        turns: _controller,
        child: Icon(Icons.sync_rounded, size: 18, color: widget.color),
      ),
    );
  }
}

class _SyncStatusPopover extends StatelessWidget {
  const _SyncStatusPopover({
    required this.state,
    required this.status,
    required this.colors,
    required this.width,
    required this.onSyncNow,
  });

  final SyncQueueState state;
  final SyncHeaderStatus status;
  final _SyncStatusColors colors;
  final double width;
  final VoidCallback? onSyncNow;

  @override
  Widget build(BuildContext context) {
    final lastError = (state.lastError ?? '').trim();
    final hasWork =
        state.pendingCount > 0 ||
        state.syncingCount > 0 ||
        state.errorCount > 0;
    final effectiveOnSyncNow = hasWork ? onSyncNow : null;
    final syncButtonLabel = onSyncNow == null
        ? 'Sincronizando...'
        : hasWork
        ? 'Sincronizar ahora'
        : 'Todo sincronizado';

    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.activeBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.border),
                  ),
                  child: Icon(
                    Icons.sync_rounded,
                    size: 19,
                    color: colors.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title(status),
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle(status),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SyncMetricRow(label: 'Pendientes', value: '${state.pendingCount}'),
            _SyncMetricRow(
              label: 'Sincronizando',
              value: '${state.syncingCount}',
            ),
            _SyncMetricRow(label: 'Errores', value: '${state.errorCount}'),
            _SyncMetricRow(
              label: 'Última vez',
              value: formatSyncLastSeen(state.lastSyncedAt),
            ),
            if (state.lastAttemptAt != null)
              _SyncMetricRow(
                label: 'Último intento',
                value: formatSyncLastSeen(state.lastAttemptAt),
              ),
            if (lastError.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF1FF),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  lastError,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF123A75),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            if (status == SyncHeaderStatus.error) ...[
              const SizedBox(height: 8),
              FutureBuilder<List<_OfflineSaleConflict>>(
                future: _loadSaleConflicts(),
                builder: (context, snapshot) {
                  final conflicts = snapshot.data ?? const [];
                  if (conflicts.isEmpty) return const SizedBox.shrink();
                  return Column(
                    children: [
                      for (final conflict in conflicts.take(3))
                        _OfflineConflictRow(conflict: conflict),
                    ],
                  );
                },
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 34,
              child: FilledButton.icon(
                onPressed: effectiveOnSyncNow,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF1957E6),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE2E8F0),
                  disabledForegroundColor: const Color(0xFF64748B),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(7),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                icon: const Icon(Icons.sync_rounded, size: 17),
                label: Text(
                  syncButtonLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<List<_OfflineSaleConflict>> _loadSaleConflicts() async {
    final user = await TokenStorage().getUserSnapshot();
    final companyId = user?.companyId?.trim();
    final userId = user?.id.trim();
    if ((companyId ?? '').isEmpty) return const [];
    final rows = await OfflineStore.instance.listOfflineSales(
      companyId: companyId!,
      userId: (userId ?? '').isEmpty ? null : userId,
      status: 'conflict',
      limit: 5,
    );
    return rows
        .map(_OfflineSaleConflict.fromOfflineSale)
        .whereType<_OfflineSaleConflict>()
        .toList(growable: false);
  }

  static String _title(SyncHeaderStatus status) {
    return switch (status) {
      SyncHeaderStatus.synced => 'Datos sincronizados',
      SyncHeaderStatus.syncing => 'Sincronización en curso',
      SyncHeaderStatus.pending => 'Cambios pendientes',
      SyncHeaderStatus.error => 'Sincronización por revisar',
    };
  }

  static String _subtitle(SyncHeaderStatus status) {
    return switch (status) {
      SyncHeaderStatus.synced => 'La cola local está al día',
      SyncHeaderStatus.syncing => 'Procesando cambios guardados',
      SyncHeaderStatus.pending => 'Se enviarán al recuperar conexión',
      SyncHeaderStatus.error => 'La app conserva los datos y reintenta',
    };
  }
}

class _OfflineConflictRow extends StatelessWidget {
  const _OfflineConflictRow({required this.conflict});

  final _OfflineSaleConflict conflict;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Venta offline sin sincronizar',
            style: TextStyle(
              color: Color(0xFF9A3412),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            conflict.message,
            softWrap: true,
            style: const TextStyle(
              color: Color(0xFF7C2D12),
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (conflict.productLine.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              conflict.productLine,
              softWrap: true,
              style: const TextStyle(
                color: Color(0xFF7C2D12),
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _OfflineSaleConflict {
  const _OfflineSaleConflict({
    required this.message,
    required this.productLine,
  });

  final String message;
  final String productLine;

  static _OfflineSaleConflict? fromOfflineSale(Map<String, dynamic> row) {
    final raw = row['error']?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      data = decoded.cast<String, dynamic>();
    } catch (_) {
      return _OfflineSaleConflict(message: raw, productLine: '');
    }
    final details = data['details'] is Map
        ? (data['details'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final message =
        data['message']?.toString() ??
        'Esta venta no pudo sincronizarse porque el stock cambió mientras el dispositivo estaba sin conexión.';
    final product = (details['productName'] ?? 'Producto').toString();
    final requested = details['requestedQuantity']?.toString();
    final available = details['availableQuantity']?.toString();
    final productLine = requested == null || available == null
        ? product
        : '$product: solicitado $requested, disponible $available';
    return _OfflineSaleConflict(message: message, productLine: productLine);
  }
}

class _SyncMetricRow extends StatelessWidget {
  const _SyncMetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncStatusColors {
  const _SyncStatusColors({
    required this.accent,
    required this.foreground,
    required this.border,
    required this.activeBackground,
  });

  final Color accent;
  final Color foreground;
  final Color border;
  final Color activeBackground;

  factory _SyncStatusColors.forStatus(SyncHeaderStatus status) {
    return switch (status) {
      SyncHeaderStatus.synced => const _SyncStatusColors(
        accent: Color(0xFF1957E6),
        foreground: Color(0xFF123A75),
        border: Color(0xFF9FB6C8),
        activeBackground: Color(0xFFE4F8FF),
      ),
      SyncHeaderStatus.syncing => const _SyncStatusColors(
        accent: Color(0xFF1957E6),
        foreground: Color(0xFF123A75),
        border: Color(0xFF9FB6C8),
        activeBackground: Color(0xFFE4F8FF),
      ),
      SyncHeaderStatus.pending => const _SyncStatusColors(
        accent: Color(0xFF0D5EA6),
        foreground: Color(0xFF123A75),
        border: Color(0xFF9FB6C8),
        activeBackground: Color(0xFFEAF1FF),
      ),
      SyncHeaderStatus.error => const _SyncStatusColors(
        accent: Color(0xFF143C94),
        foreground: Color(0xFF123A75),
        border: Color(0xFF9FB6C8),
        activeBackground: Color(0xFFEAF1FF),
      ),
    };
  }
}

String formatSyncLastSeen(DateTime? value) {
  if (value == null) return 'No disponible';
  final local = value.toLocal();
  final diff = DateTime.now().difference(local);
  if (diff.inSeconds < 45) return 'Ahora';
  if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
  if (diff.inDays == 1) return 'Ayer';
  if (diff.inDays < 7) return 'Hace ${diff.inDays} días';
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year}';
}
