import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    return PopupMenuButton<void>(
      tooltip: 'Estado de sincronización',
      offset: const Offset(0, 42),
      padding: EdgeInsets.zero,
      color: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.10),
      constraints: const BoxConstraints(minWidth: 284, maxWidth: 284),
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
    required this.onSyncNow,
  });

  final SyncQueueState state;
  final SyncHeaderStatus status;
  final _SyncStatusColors colors;
  final VoidCallback? onSyncNow;

  @override
  Widget build(BuildContext context) {
    final lastError = (state.lastError ?? '').trim();

    return SizedBox(
      width: 284,
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
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 34,
              child: FilledButton.icon(
                onPressed: onSyncNow,
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
                  onSyncNow == null ? 'Sincronizando...' : 'Sincronizar ahora',
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
