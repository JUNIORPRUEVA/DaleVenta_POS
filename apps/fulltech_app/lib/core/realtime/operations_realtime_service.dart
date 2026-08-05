import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../api/env.dart';
import '../auth/auth_provider.dart';
import '../auth/auth_repository.dart';
import '../auth/token_storage.dart';

class OperationsRealtimeMessage {
  const OperationsRealtimeMessage({
    required this.eventId,
    required this.type,
    this.serviceId,
    this.service,
  });

  final String eventId;
  final String type;
  final String? serviceId;
  final Map<String, dynamic>? service;
}

class ClientsRealtimeMessage {
  const ClientsRealtimeMessage({
    required this.eventId,
    required this.type,
    this.clientId,
    this.client,
  });

  final String eventId;
  final String type;
  final String? clientId;
  final Map<String, dynamic>? client;
}

class LicenseRealtimeMessage {
  const LicenseRealtimeMessage({
    required this.eventId,
    required this.type,
    required this.companyId,
    required this.license,
  });

  final String eventId;
  final String type;
  final String companyId;
  final Map<String, dynamic> license;
}

class OperationsRealtimeService {
  OperationsRealtimeService(this._storage);

  final TokenStorage _storage;
  final StreamController<OperationsRealtimeMessage> _controller =
      StreamController<OperationsRealtimeMessage>.broadcast();
  final StreamController<ClientsRealtimeMessage> _clientsController =
      StreamController<ClientsRealtimeMessage>.broadcast();
  final StreamController<Map<String, dynamic>> _whatsappController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<LicenseRealtimeMessage> _licenseController =
      StreamController<LicenseRealtimeMessage>.broadcast();
  final Set<String> _seenEventIds = <String>{};

  io.Socket? _socket;

  Stream<OperationsRealtimeMessage> get stream => _controller.stream;
  Stream<ClientsRealtimeMessage> get clientStream => _clientsController.stream;
  Stream<Map<String, dynamic>> get whatsappStream => _whatsappController.stream;
  Stream<LicenseRealtimeMessage> get licenseStream => _licenseController.stream;

  /// Register a callback for incoming WhatsApp CRM messages.
  void onWhatsappMessage(void Function(Map<String, dynamic> data) callback) {
    _whatsappController.stream.listen(callback);
  }

  Future<void> connect(AuthState authState) async {
    if (!authState.isAuthenticated) {
      disconnect();
      return;
    }

    final token = await _storage.getAccessToken();
    if (token == null || token.trim().isEmpty) {
      disconnect();
      return;
    }

    final existing = _socket;
    if (existing != null && (existing.connected || existing.active)) {
      return;
    }

    final socket = io.io(
      Env.apiBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(999999)
          .setReconnectionDelay(1500)
          .setAuth({'token': token})
          .build(),
    );

    socket.on('service.event', (data) {
      if (data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      final eventId = payload['eventId']?.toString() ?? '';
      if (eventId.isNotEmpty && !_seenEventIds.add(eventId)) {
        return;
      }
      if (_seenEventIds.length > 300) {
        _seenEventIds.remove(_seenEventIds.first);
      }

      final serviceId = payload['serviceId']?.toString().trim();
      final serviceJson = payload['service'];
      Map<String, dynamic>? service;
      if (serviceJson is Map) {
        service = Map<String, dynamic>.from(serviceJson);
      }

      // If there's no service snapshot, we still forward the message so
      // listeners can trigger a refresh by id.
      if (service == null && (serviceId == null || serviceId.isEmpty)) {
        return;
      }

      final resolvedId = (serviceId != null && serviceId.isNotEmpty)
          ? serviceId
          : (service?['id']?.toString().trim());

      _controller.add(
        OperationsRealtimeMessage(
          eventId: eventId,
          type: payload['type']?.toString() ?? 'service.updated',
          serviceId: (resolvedId != null && resolvedId.isNotEmpty)
              ? resolvedId
              : null,
          service: service,
        ),
      );
    });

    socket.on('whatsapp.message', (data) {
      if (data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      if (!_whatsappController.isClosed) {
        _whatsappController.add(payload);
      }
    });

    socket.on('client.event', (data) {
      if (data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      final eventId = payload['eventId']?.toString() ?? '';
      if (eventId.isNotEmpty && !_seenEventIds.add(eventId)) {
        return;
      }
      if (_seenEventIds.length > 300) {
        _seenEventIds.remove(_seenEventIds.first);
      }

      final clientId = payload['clientId']?.toString().trim();
      final clientJson = payload['client'];
      Map<String, dynamic>? client;
      if (clientJson is Map) {
        client = Map<String, dynamic>.from(clientJson);
      }

      if (client == null && (clientId == null || clientId.isEmpty)) {
        return;
      }

      final resolvedId = (clientId != null && clientId.isNotEmpty)
          ? clientId
          : (client?['id']?.toString().trim());

      _clientsController.add(
        ClientsRealtimeMessage(
          eventId: eventId,
          type: payload['type']?.toString() ?? 'client.updated',
          clientId: (resolvedId != null && resolvedId.isNotEmpty)
              ? resolvedId
              : null,
          client: client,
        ),
      );
    });

    socket.on('license.event', (data) {
      if (data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      final eventId = payload['eventId']?.toString() ?? '';
      if (eventId.isNotEmpty && !_seenEventIds.add(eventId)) {
        return;
      }
      if (_seenEventIds.length > 300) {
        _seenEventIds.remove(_seenEventIds.first);
      }

      final licenseJson = payload['license'];
      final companyId = payload['companyId']?.toString().trim() ?? '';
      if (companyId.isEmpty || licenseJson is! Map) return;

      _licenseController.add(
        LicenseRealtimeMessage(
          eventId: eventId,
          type: payload['type']?.toString() ?? 'license.updated',
          companyId: companyId,
          license: Map<String, dynamic>.from(licenseJson),
        ),
      );
    });

    socket.connect();
    _socket = socket;
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }
}

final operationsRealtimeServiceProvider = Provider<OperationsRealtimeService>((
  ref,
) {
  final storage = ref.read(tokenStorageProvider);
  return OperationsRealtimeService(storage);
});
