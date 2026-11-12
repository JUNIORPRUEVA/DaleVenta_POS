import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../api/env.dart';
import '../auth/token_storage.dart';
import 'guardian_agent_log.dart';

/// Estado del monitoreo APPYRA Guardian AI para la empresa de la sesión.
class GuardianMonitoringStatus {
  const GuardianMonitoringStatus({
    required this.guardianEnabled,
    required this.activeInstallations,
    required this.maxInstallations,
    required this.autoEnrollmentAllowed,
  });

  final bool guardianEnabled;
  final int activeInstallations;
  final int maxInstallations;
  final bool autoEnrollmentAllowed;
}

/// Acceso al panel administrativo de Guardian (revelación y control).
///
/// Nunca lanza: la pantalla de ajustes no puede romperse porque el backend no
/// responda o porque el usuario no sea administrador.
class GuardianMonitoringRepository {
  GuardianMonitoringRepository({
    required this.baseUrl,
    required this.tokenProvider,
    Dio? dio,
    this.timeout = const Duration(seconds: 8),
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               validateStatus: (_) => true,
               // El límite vive en el cliente HTTP: `close(force: true)` lo
               // cancela junto con la conexión, sin dejar temporizadores vivos.
               connectTimeout: timeout,
               sendTimeout: timeout,
               receiveTimeout: timeout,
             ),
           );

  final String baseUrl;
  final Future<String?> Function() tokenProvider;
  final Duration timeout;
  final Dio _dio;
  final CancelToken _cancelToken = CancelToken();
  bool _closed = false;

  /// Aborta la petición en curso (si la hay) sin liberar el cliente HTTP.
  void cancel() {
    if (!_cancelToken.isCancelled) _cancelToken.cancel();
  }

  /// Aborta la petición y libera el cliente HTTP propio.
  ///
  /// Necesario cuando quien usa el repositorio desaparece: una petición
  /// pendiente deja vivo su temporizador de timeout y su conexión.
  void close() {
    cancel();
    if (_closed) return;
    _closed = true;
    _dio.close(force: true);
  }

  Future<GuardianMonitoringStatus?> fetchStatus() async {
    final body = await _request('GET', '/guardian/admin/company/status');
    if (body == null) return null;
    return GuardianMonitoringStatus(
      guardianEnabled: body['guardianEnabled'] == true,
      activeInstallations: _asInt(body['activeInstallations']),
      maxInstallations: _asInt(body['maxInstallations']),
      autoEnrollmentAllowed: body['autoEnrollmentAllowed'] == true,
    );
  }

  /// Desactiva el monitoreo para la empresa y revoca las credenciales.
  Future<bool> disable() async {
    final body = await _request('POST', '/guardian/admin/company/disable');
    return body != null && body['guardianEnabled'] == false;
  }

  Future<Map<String, dynamic>?> _request(String method, String path) async {
    final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty || _closed) return null;

    try {
      final token = (await tokenProvider())?.trim();
      if (token == null || token.isEmpty) return null;
      if (_closed) return null;

      final response = await _dio.request<dynamic>(
        '$base$path',
        cancelToken: _cancelToken,
        options: Options(
          method: method,
          validateStatus: (_) => true,
          headers: <String, String>{
            'content-type': 'application/json',
            'authorization': 'Bearer $token',
          },
        ),
      );
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        unawaited(
          GuardianAgentLog.info('panel Guardian http=$status ruta=$path'),
        );
        return null;
      }
      final data = response.data;
      if (data is Map) return Map<String, dynamic>.from(data);
      if (data is String && data.trim().isNotEmpty) {
        final decoded = jsonDecode(data);
        return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
      }
      return null;
    } catch (error) {
      unawaited(
        GuardianAgentLog.info('panel Guardian fallo ruta=$path: $error'),
      );
      return null;
    }
  }

  static int _asInt(dynamic raw) {
    if (raw is int) return raw;
    return int.tryParse('${raw ?? ''}') ?? 0;
  }

  /// Instancia por defecto (sesión actual + API configurada).
  static GuardianMonitoringRepository fromSession() =>
      GuardianMonitoringRepository(
        baseUrl: Env.apiBaseUrl,
        tokenProvider: () => TokenStorage().getAccessToken(),
      );
}

/// Revelación + control de desactivación del monitoreo.
///
/// El texto es explícito sobre **qué** se envía (errores técnicos) y sobre
/// **qué no** se envía (ventas, clientes, inventario), y el interruptor apaga el
/// monitoreo de verdad (el servidor revoca las credenciales de las estaciones).
class GuardianMonitoringPanel extends StatefulWidget {
  const GuardianMonitoringPanel({
    super.key,
    this.repository,
    this.accentColor,
    this.surfaceColor,
    this.textStyle,
    this.captionStyle,
  });

  final GuardianMonitoringRepository? repository;
  final Color? accentColor;
  final Color? surfaceColor;
  final TextStyle? textStyle;
  final TextStyle? captionStyle;

  @override
  State<GuardianMonitoringPanel> createState() =>
      _GuardianMonitoringPanelState();
}

class _GuardianMonitoringPanelState extends State<GuardianMonitoringPanel> {
  late final GuardianMonitoringRepository _repository =
      widget.repository ?? GuardianMonitoringRepository.fromSession();

  GuardianMonitoringStatus? _status;
  bool _loading = false;
  bool _busy = false;
  bool _failed = false;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    // La consulta es explícita: este panel vive en Ajustes y no debe lanzar una
    // petición autenticada (ni armar temporizadores) solo por abrir la pantalla.
  }

  @override
  void dispose() {
    // El panel puede desaparecer con una consulta en curso (p. ej. al cerrar
    // los ajustes): se aborta para no dejar temporizadores ni conexiones vivas.
    if (widget.repository == null) {
      _repository.close();
    } else {
      _repository.cancel();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _requested = true;
      _loading = true;
    });
    final status = await _repository.fetchStatus();
    if (!mounted) return;
    setState(() {
      _status = status;
      _loading = false;
      _failed = status == null;
    });
  }

  Future<void> _disable() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Desactivar APPYRA Guardian AI'),
        content: const Text(
          'Se dejarán de enviar diagnósticos desde esta empresa y se revocarán '
          'las credenciales de monitoreo de las estaciones. El POS sigue '
          'funcionando igual.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Desactivar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    final ok = await _repository.disable();
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Monitoreo APPYRA Guardian AI desactivado'),
        ),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo desactivar el monitoreo')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final enabled = status?.guardianEnabled ?? false;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: widget.surfaceColor ?? Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (widget.accentColor ?? Theme.of(context).colorScheme.primary)
              .withValues(alpha: 0.24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monitor_heart_outlined, color: widget.accentColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Monitoreo APPYRA Guardian AI',
                  style: widget.textStyle?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (status != null)
                Chip(
                  label: Text(enabled ? 'Activo' : 'Desactivado'),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Se envían solo diagnósticos técnicos (tipo de error, módulo, mensaje '
            'y traza depurada) para detectar fallos y avisar al equipo de soporte. '
            'No se envían ventas, clientes, inventario ni datos fiscales.',
            style: widget.captionStyle,
          ),
          if (_failed) ...[
            const SizedBox(height: 8),
            Text(
              'No se pudo consultar el estado del monitoreo.',
              style: widget.captionStyle?.copyWith(
                color: Colors.orange.shade700,
              ),
            ),
          ],
          if (status != null) ...[
            const SizedBox(height: 8),
            Text(
              'Estaciones monitoreadas: ${status.activeInstallations} de '
              '${status.maxInstallations}',
              style: widget.captionStyle,
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: !_requested
                ? OutlinedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Consultar estado del monitoreo'),
                  )
                : OutlinedButton.icon(
                    onPressed: (enabled && !_busy) ? _disable : null,
                    icon: _busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.pause_circle_outline, size: 18),
                    label: const Text('Desactivar monitoreo'),
                  ),
          ),
        ],
      ),
    );
  }
}
