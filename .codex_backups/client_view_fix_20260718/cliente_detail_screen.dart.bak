import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../../core/realtime/operations_realtime_service.dart';
import '../../core/routing/app_navigator.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/safe_url_launcher.dart';
import 'application/clientes_controller.dart';
import 'client_location_utils.dart';
import 'cliente_model.dart';
import 'cliente_profile_model.dart';
import 'cliente_timeline_model.dart';
import 'data/cliente_detail_local_repository.dart';
import 'data/clientes_repository.dart';

class ClienteDetailScreen extends ConsumerStatefulWidget {
  const ClienteDetailScreen({super.key, required this.clienteId});

  final String clienteId;

  @override
  ConsumerState<ClienteDetailScreen> createState() =>
      _ClienteDetailScreenState();
}

class _ClienteDetailScreenState extends ConsumerState<ClienteDetailScreen> {
  bool _loading = true;
  bool _refreshing = false;
  bool _deleting = false;
  String? _error;
  ClienteModel? _cliente;
  ClienteProfileResponse? _profile;
  List<ClienteTimelineEvent> _timeline = const [];
  StreamSubscription<ClientsRealtimeMessage>? _clientsRealtimeSubscription;

  static const Duration _detailTimeout = Duration(seconds: 12);

  @override
  void initState() {
    super.initState();
    _clientsRealtimeSubscription = ref
        .read(operationsRealtimeServiceProvider)
        .clientStream
        .listen(_handleRealtimeMessage);
    _load();
  }

  @override
  void dispose() {
    _clientsRealtimeSubscription?.cancel();
    super.dispose();
  }

  void _handleRealtimeMessage(ClientsRealtimeMessage message) {
    if (!mounted) return;
    final incomingId = (message.clientId ?? '').trim();
    final currentId = widget.clienteId.trim();

    if (message.type == 'client.bulkDeleted') {
      context.go(Routes.clientes);
      return;
    }

    if (incomingId.isEmpty || incomingId != currentId) {
      return;
    }

    if (message.type == 'client.deleted') {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Este cliente fue eliminado.')),
      );
      context.go(Routes.clientes);
      return;
    }

    unawaited(_load());
  }

  Future<void> _load() async {
    final hadRenderableData =
        _cliente != null || _profile != null || _timeline.isNotEmpty;
    if (mounted) {
      setState(() {
        _loading = !hadRenderableData;
        _refreshing = hadRenderableData;
        _error = null;
      });
    }

    final detailLocalRepository = ref.read(
      clienteDetailLocalRepositoryProvider,
    );

    ClienteModel? cachedClient;
    ClienteDetailLocalSnapshot localSnapshot =
        const ClienteDetailLocalSnapshot();

    try {
      final results = await Future.wait<dynamic>([
        ref.read(clientesControllerProvider.notifier).getById(widget.clienteId),
        detailLocalRepository.read(widget.clienteId),
      ]);
      cachedClient = results[0] as ClienteModel?;
      localSnapshot = results[1] as ClienteDetailLocalSnapshot;
    } catch (_) {
      try {
        cachedClient = await ref
            .read(clientesControllerProvider.notifier)
            .getById(widget.clienteId);
      } catch (_) {
        cachedClient = null;
      }
      try {
        localSnapshot = await detailLocalRepository.read(widget.clienteId);
      } catch (_) {
        localSnapshot = const ClienteDetailLocalSnapshot();
      }
    }

    if (!mounted) return;
    final effectiveLocalClient = localSnapshot.profile == null
        ? cachedClient
        : _profileToClient(localSnapshot.profile!, fallback: cachedClient);

    if (effectiveLocalClient != null || localSnapshot.hasData) {
      setState(() {
        _cliente = effectiveLocalClient ?? _cliente;
        _profile = localSnapshot.profile ?? _profile;
        _timeline = localSnapshot.timeline.isNotEmpty
            ? localSnapshot.timeline
            : _timeline;
        _loading = false;
        _refreshing = !widget.clienteId.startsWith('local_');
      });
    }

    if (widget.clienteId.startsWith('local_')) {
      setState(() {
        _profile = null;
        _timeline = const [];
        _loading = false;
        _refreshing = false;
      });
      return;
    }

    try {
      final repo = ref.read(clientesRepositoryProvider);
      final results = await Future.wait<dynamic>([
        repo.getClientProfile(id: widget.clienteId).timeout(_detailTimeout),
        repo
            .getClientTimeline(id: widget.clienteId, take: 120)
            .timeout(_detailTimeout)
            .then<ClienteTimelineResponse?>((value) => value)
            .catchError((_) => null),
      ]);

      final profile = results[0] as ClienteProfileResponse;
      final timeline = results[1] as ClienteTimelineResponse?;
      final mergedClient = _profileToClient(profile, fallback: cachedClient);

      await detailLocalRepository.write(
        clientId: widget.clienteId,
        profile: profile,
        timeline: timeline?.items.toList(growable: false) ?? const [],
      );

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _timeline = timeline?.items.toList(growable: false) ?? const [];
        _cliente = mergedClient;
      });
    } catch (error, stackTrace) {
      debugPrint('Error cargando detalle del cliente: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        if (_profile == null && _cliente == null) {
          _error = 'No se pudo cargar el detalle del cliente.';
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  ClienteModel _profileToClient(
    ClienteProfileResponse profile, {
    ClienteModel? fallback,
  }) {
    return ClienteModel.fromJson({
      'id': profile.client.id,
      'ownerId': profile.client.ownerId ?? fallback?.ownerId ?? '',
      'nombre': profile.client.nombre,
      'telefono': profile.client.telefono,
      'direccion': profile.client.direccion,
      'location_url': profile.client.locationUrl,
      'latitude': profile.client.latitude ?? fallback?.latitude,
      'longitude': profile.client.longitude ?? fallback?.longitude,
      'email': profile.client.email,
      'isDeleted': profile.client.isDeleted,
      'createdAt': profile.client.createdAt?.toIso8601String(),
      'updatedAt': profile.client.updatedAt?.toIso8601String(),
    });
  }

  Future<void> _deleteClient() async {
    final client = _cliente;
    if (client == null || _deleting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Eliminar cliente'),
          content: Text(
            'Se eliminara el cliente ${client.nombre}. Esta accion no se puede deshacer.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await ref.read(clientesControllerProvider.notifier).remove(client.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cliente eliminado')));
      context.go(Routes.clientes);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  String _formatMoney(num? value) {
    return NumberFormat.currency(
      symbol: 'RD\$ ',
      decimalDigits: 2,
    ).format(value ?? 0);
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    return DateFormat('yyyy-MM-dd h:mm a', 'es_DO').format(value.toLocal());
  }

  void _openEvent(ClienteTimelineEvent event) {
    final clienteId = widget.clienteId.trim();
    final clienteNombre = (_cliente?.nombre ?? _profile?.client.nombre ?? '')
        .trim();
    final source = (event.meta['source'] ?? '').toString().trim();
    if (event.eventType == 'cotizacion' && event.eventId.trim().isNotEmpty) {
      context.go(
        '${Routes.cotizaciones}?quotationId=${Uri.encodeQueryComponent(event.eventId)}',
      );
      return;
    }
    if (event.eventType == 'sale') {
      if (clienteId.isNotEmpty && !clienteId.startsWith('local_')) {
        final query = StringBuffer(
          '${Routes.ventasLista}?customerId=${Uri.encodeQueryComponent(clienteId)}',
        );
        if (clienteNombre.isNotEmpty) {
          query.write(
            '&customerName=${Uri.encodeQueryComponent(clienteNombre)}',
          );
        }
        context.go(query.toString());
        return;
      }
      context.go(Routes.ventasLista);
      return;
    }
    if (event.eventType == 'service' && event.eventId.trim().isNotEmpty) {
      if (source == 'legacy_service') {
        return;
      }
      final serviceOrderId = (event.meta['serviceOrderId'] ?? event.eventId)
          .toString()
          .trim();
      if (serviceOrderId.isNotEmpty) {
        context.go(Routes.serviceOrderById(serviceOrderId));
      }
    }
  }

  bool _canOpenEvent(ClienteTimelineEvent event) {
    if (event.eventType == 'sale') return true;
    if (event.eventType == 'cotizacion') return event.eventId.trim().isNotEmpty;
    if (event.eventType != 'service') return false;

    final source = (event.meta['source'] ?? '').toString().trim();
    if (source == 'legacy_service') return false;

    final serviceOrderId = (event.meta['serviceOrderId'] ?? event.eventId)
        .toString()
        .trim();
    return serviceOrderId.isNotEmpty;
  }

  IconData _timelineIcon(String type) {
    switch (type) {
      case 'sale':
        return Icons.point_of_sale_rounded;
      case 'cotizacion':
        return Icons.description_outlined;
      case 'service':
        return Icons.build_circle_outlined;
      default:
        return Icons.history_rounded;
    }
  }

  String _timelineSummary(ClienteTimelineEvent event) {
    final parts = <String>[];
    final source = (event.meta['source'] ?? '').toString().trim();
    final category = (event.meta['category'] ?? '').toString().trim();
    final orderNumber = (event.meta['orderNumber'] ?? '').toString().trim();
    final phase = (event.meta['currentPhase'] ?? '').toString().trim();
    final serviceType = (event.meta['serviceType'] ?? '').toString().trim();
    final note = (event.meta['note'] ?? '').toString().trim();
    final userName = (event.userName ?? '').trim();
    final assignedToName = (event.meta['assignedToName'] ?? '')
        .toString()
        .trim();
    final technicianName = (event.meta['technicianName'] ?? '')
        .toString()
        .trim();
    final contentPreview = (event.meta['contentPreview'] ?? '')
        .toString()
        .trim();
    final technicalNote = (event.meta['technicalNote'] ?? '').toString().trim();
    final extraRequirements = (event.meta['extraRequirements'] ?? '')
        .toString()
        .trim();
    final titleSnapshot = (event.meta['titleSnapshot'] ?? '').toString().trim();
    final evidenceType = _humanizeCode(
      (event.meta['evidenceType'] ?? '').toString(),
    );
    final reportType = _humanizeCode(
      (event.meta['reportType'] ?? '').toString(),
    );
    final paymentStatus = _humanizeCode(
      (event.meta['paymentStatus'] ?? '').toString(),
    );

    if (source == 'service_order') {
      if (serviceType.isNotEmpty) parts.add(_humanizeCode(serviceType));
      if (category.isNotEmpty) parts.add(category);
      if (assignedToName.isNotEmpty) parts.add('Asignado a $assignedToName');
      if (technicalNote.isNotEmpty) parts.add(technicalNote);
      if (extraRequirements.isNotEmpty) parts.add(extraRequirements);
      if (userName.isNotEmpty) parts.add('Creado por $userName');
      return parts.join(' • ');
    }

    if (source == 'service_evidence') {
      if (evidenceType.isNotEmpty) parts.add(evidenceType);
      if (serviceType.isNotEmpty) parts.add(_humanizeCode(serviceType));
      if (category.isNotEmpty) parts.add(category);
      if (contentPreview.isNotEmpty) parts.add(contentPreview);
      if (assignedToName.isNotEmpty) parts.add('Tecnico $assignedToName');
      if (userName.isNotEmpty) parts.add('Registrado por $userName');
      return parts.join(' • ');
    }

    if (source == 'service_report') {
      if (reportType.isNotEmpty) parts.add(reportType);
      if (serviceType.isNotEmpty) parts.add(_humanizeCode(serviceType));
      if (category.isNotEmpty) parts.add(category);
      if (contentPreview.isNotEmpty) parts.add(contentPreview);
      if (assignedToName.isNotEmpty) parts.add('Tecnico $assignedToName');
      if (userName.isNotEmpty) parts.add('Registrado por $userName');
      return parts.join(' • ');
    }

    if (source == 'legacy_service') {
      if (orderNumber.isNotEmpty) parts.add('Orden $orderNumber');
      if (titleSnapshot.isNotEmpty) parts.add(titleSnapshot);
      if (serviceType.isNotEmpty) parts.add(_humanizeCode(serviceType));
      if (category.isNotEmpty) parts.add(category);
      if (phase.isNotEmpty) parts.add(_humanizeCode(phase));
      if (paymentStatus.isNotEmpty) parts.add('Pago $paymentStatus');
      if (contentPreview.isNotEmpty) parts.add(contentPreview);
      if (technicianName.isNotEmpty) parts.add('Tecnico $technicianName');
      if (userName.isNotEmpty) parts.add('Creado por $userName');
      return parts.join(' • ');
    }

    if (orderNumber.isNotEmpty) parts.add('Orden $orderNumber');
    if (serviceType.isNotEmpty) parts.add(serviceType.replaceAll('_', ' '));
    if (category.isNotEmpty) parts.add(category);
    if (phase.isNotEmpty) parts.add(phase);
    if (note.isNotEmpty) parts.add(note);
    if (userName.isNotEmpty) parts.add('Por $userName');

    return parts.join(' • ');
  }

  String _timelineStatusLabel(ClienteTimelineEvent event) {
    final raw = (event.status ?? '').trim().toLowerCase();
    final source = (event.meta['source'] ?? '').toString().trim();
    if (raw.isEmpty) {
      if (source == 'service_evidence' || source == 'service_report') {
        return 'Registrado';
      }
      return event.eventType == 'sale' ? 'Finalizado' : 'Pendiente';
    }

    switch (raw) {
      case 'finalized':
      case 'finalizado':
      case 'completed':
        return 'Finalizado';
      case 'cancelled':
      case 'cancelado':
        return 'Cancelado';
      case 'in_process':
      case 'en_proceso':
      case 'en proceso':
      case 'in_progress':
      case 'in progress':
        return 'En proceso';
      case 'reserved':
      case 'reserva':
        return 'Reservado';
      case 'pospuesta':
      case 'postponed':
        return 'Pospuesta';
      default:
        return raw == 'pending' || raw == 'pendiente'
            ? 'Pendiente'
            : _humanizeCode(raw);
    }
  }

  Color _timelineStatusColor(BuildContext context, ClienteTimelineEvent event) {
    final label = _timelineStatusLabel(event);
    switch (label) {
      case 'Finalizado':
        return const Color(0xFF2E8B57);
      case 'Cancelado':
        return Theme.of(context).colorScheme.error;
      case 'Registrado':
        return const Color(0xFF2B6CB0);
      case 'En proceso':
        return const Color(0xFFD98324);
      case 'Reservado':
        return const Color(0xFF8C6A03);
      case 'Pospuesta':
        return const Color(0xFFA05A2C);
      case 'Pendiente':
      default:
        return const Color(0xFFD98324);
    }
  }

  String _humanizeCode(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return '';

    return normalized
        .replaceAll('-', '_')
        .split('_')
        .where((part) => part.trim().isNotEmpty)
        .map((part) {
          final lower = part.toLowerCase();
          return '${lower[0].toUpperCase()}${lower.substring(1)}';
        })
        .join(' ');
  }

  List<_ClientMetricData> _buildMetricItems(ClienteProfileResponse? profile) {
    final metrics = profile?.metrics;

    return [
      _ClientMetricData(
        label: 'Ventas',
        value: '${metrics?.salesCount ?? 0}',
        helper: _formatMoney(metrics?.salesTotal),
      ),
      _ClientMetricData(
        label: 'Servicios',
        value: '${metrics?.servicesCount ?? 0}',
        helper:
            'OT ${metrics?.serviceOrdersCount ?? 0} • Legacy ${metrics?.legacyServicesCount ?? 0}',
      ),
      _ClientMetricData(
        label: 'Referencias',
        value: '${metrics?.serviceReferencesCount ?? 0}',
        helper: _formatDate(metrics?.lastReferenceAt),
      ),
      _ClientMetricData(
        label: 'Cotizaciones',
        value: '${metrics?.cotizacionesCount ?? 0}',
        helper: _formatMoney(metrics?.cotizacionesTotal),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final profileClient = profile?.client;
    final metrics = profile?.metrics;
    final fallbackLocation = parseClientLocationPreview(_cliente?.locationUrl);
    final resolvedClientId =
        (profileClient?.id ?? _cliente?.id ?? widget.clienteId).trim();
    final displayName =
        (profileClient?.nombre ?? _cliente?.nombre ?? 'Detalle del cliente')
            .trim();
    final displayPhone = (profileClient?.telefono ?? _cliente?.telefono ?? '')
        .trim();
    final displayEmail = profileClient?.email ?? _cliente?.correo;
    final displayLocationUrl =
        profileClient?.locationUrl ?? _cliente?.locationUrl;
    final displayLatitude =
        profileClient?.latitude ??
        _cliente?.latitude ??
        fallbackLocation.latitude;
    final displayLongitude =
        profileClient?.longitude ??
        _cliente?.longitude ??
        fallbackLocation.longitude;
    final displayNote = (profileClient?.notas ?? '').trim();
    final lastActivityAt =
        metrics?.lastActivityAt ?? profileClient?.lastActivityAt;
    final recentTimeline = _timeline.take(5).toList(growable: false);
    final importantInfo =
        <_SimpleDetailRowData>[
              _SimpleDetailRowData(
                label: 'Correo',
                value: (displayEmail ?? '').trim(),
              ),
              _SimpleDetailRowData(
                label: 'Direccion',
                value: (profileClient?.direccion ?? _cliente?.direccion ?? '')
                    .trim(),
              ),
              _SimpleDetailRowData(
                label: 'Creado por',
                value: (profile?.createdBy?.label ?? '').trim(),
              ),
              _SimpleDetailRowData(
                label: 'Creado',
                value: profileClient?.createdAt == null
                    ? ''
                    : _formatDate(profileClient?.createdAt),
              ),
              _SimpleDetailRowData(
                label: 'Ultima actividad',
                value: lastActivityAt == null
                    ? ''
                    : _formatDate(lastActivityAt),
              ),
              _SimpleDetailRowData(
                label: 'Estado',
                value:
                    (profileClient?.isDeleted ?? _cliente?.isDeleted ?? false)
                    ? 'Eliminado'
                    : 'Activo',
              ),
            ]
            .where((row) => row.value.isNotEmpty && row.value != '-')
            .toList(growable: false);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(child: Text(_error!))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
                  children: [
                    _CompactDetailHeader(
                      name: displayName.isEmpty ? 'Cliente' : displayName,
                      phone: displayPhone,
                      deleted:
                          profileClient?.isDeleted ??
                          _cliente?.isDeleted ??
                          false,
                      deleting: _deleting,
                      onBack: () => AppNavigator.goBack(
                        context,
                        fallbackRoute: Routes.clientes,
                      ),
                      onActionSelected: (action) {
                        switch (action) {
                          case _ClienteHeaderAction.edit:
                            if (resolvedClientId.isNotEmpty && !_deleting) {
                              context.push(
                                Routes.clienteEdit(resolvedClientId),
                              );
                            }
                            break;
                          case _ClienteHeaderAction.delete:
                            if (_cliente != null && !_deleting) {
                              _deleteClient();
                            }
                            break;
                        }
                      },
                    ),
                    if (_refreshing) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(),
                    ],
                    const SizedBox(height: 18),
                    _MetricGrid(items: _buildMetricItems(profile)),
                    const SizedBox(height: 22),
                    const _SectionLabel(title: 'Datos importantes del cliente'),
                    const SizedBox(height: 10),
                    _SimpleDetailList(rows: importantInfo),
                    if (displayNote.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _InlineNoteCard(note: displayNote),
                    ],
                    const SizedBox(height: 22),
                    _LocationDetailCard(
                      locationUrl: displayLocationUrl,
                      latitude: displayLatitude,
                      longitude: displayLongitude,
                    ),
                    const SizedBox(height: 22),
                    _TimelineSection(
                      title: 'Ultimos movimientos',
                      emptyLabel:
                          'No hay ventas, cotizaciones o servicios registrados para este cliente.',
                      children: recentTimeline
                          .map(
                            (event) => _TimelineEventCard(
                              icon: _timelineIcon(event.eventType),
                              title: event.title,
                              summary: _timelineSummary(event),
                              date: _formatDate(event.at),
                              amount: event.amount == null
                                  ? null
                                  : _formatMoney(event.amount),
                              statusLabel: _timelineStatusLabel(event),
                              statusColor: _timelineStatusColor(context, event),
                              enabled: _canOpenEvent(event),
                              onTap: () => _openEvent(event),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

enum _ClienteHeaderAction { edit, delete }

class _CompactDetailHeader extends StatelessWidget {
  const _CompactDetailHeader({
    required this.name,
    required this.phone,
    required this.deleted,
    required this.deleting,
    required this.onBack,
    required this.onActionSelected,
  });

  final String name;
  final String phone;
  final bool deleted;
  final bool deleting;
  final VoidCallback onBack;
  final ValueChanged<_ClienteHeaderAction> onActionSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        IconButton(
          tooltip: 'Regresar',
          onPressed: onBack,
          style: IconButton.styleFrom(
            minimumSize: const Size(36, 36),
            padding: EdgeInsets.zero,
          ),
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  if (phone.isNotEmpty)
                    Flexible(
                      child: Text(
                        phone,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  if (deleted) ...[
                    if (phone.isNotEmpty) const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Eliminado',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        PopupMenuButton<_ClienteHeaderAction>(
          tooltip: 'Opciones',
          enabled: !deleting,
          onSelected: onActionSelected,
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _ClienteHeaderAction.edit,
              child: Text('Editar'),
            ),
            PopupMenuItem(
              value: _ClienteHeaderAction.delete,
              child: Text('Eliminar'),
            ),
          ],
          icon: deleting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.more_vert_rounded),
        ),
      ],
    );
  }
}

class _ClientMetricData {
  const _ClientMetricData({
    required this.label,
    required this.value,
    required this.helper,
  });

  final String label;
  final String value;
  final String helper;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.items});

  final List<_ClientMetricData> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: _MetricCard(
                  label: item.label,
                  value: item.value,
                  helper: item.helper,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.helper,
  });

  final String label;
  final String value;
  final String helper;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.24),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w900,
                height: 1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              helper,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: 0.1,
      ),
    );
  }
}

class _SimpleDetailRowData {
  const _SimpleDetailRowData({required this.label, required this.value});

  final String label;
  final String value;
}

class _SimpleDetailList extends StatelessWidget {
  const _SimpleDetailList({required this.rows});

  final List<_SimpleDetailRowData> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 14) / 2;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final row in rows)
              SizedBox(
                width: itemWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      row.value,
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _InlineNoteCard extends StatelessWidget {
  const _InlineNoteCard({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Notas',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(note, style: theme.textTheme.bodySmall?.copyWith(height: 1.45)),
      ],
    );
  }
}

class _LocationDetailCard extends StatelessWidget {
  const _LocationDetailCard({
    required this.locationUrl,
    this.latitude,
    this.longitude,
  });

  final String? locationUrl;
  final double? latitude;
  final double? longitude;

  String? _coordinateLabel(ClientLocationPreview preview) {
    final latitude = preview.latitude;
    final longitude = preview.longitude;
    if (!preview.hasCoordinates || latitude == null || longitude == null) {
      return null;
    }
    return '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final normalizedUrl = normalizeClientLocationUrl(locationUrl);
    final uri = normalizedUrl.isEmpty ? null : Uri.tryParse(normalizedUrl);
    final parsedPreview = parseClientLocationPreview(normalizedUrl);
    final directPreview = parsedPreview.hasCoordinates
        ? parsedPreview
        : ClientLocationPreview(
            latitude: latitude,
            longitude: longitude,
            resolvedUrl: normalizedUrl.isEmpty ? null : normalizedUrl,
          );
    final coordinateLabel = _coordinateLabel(directPreview);

    if (normalizedUrl.isEmpty && !directPreview.hasCoordinates) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(title: 'Ubicacion GPS'),
        const SizedBox(height: 10),
        if (directPreview.hasCoordinates) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox(
              height: 210,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(
                    directPreview.latitude!,
                    directPreview.longitude!,
                  ),
                  initialZoom: 15,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.fulltech.app',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(
                          directPreview.latitude!,
                          directPreview.longitude!,
                        ),
                        width: 40,
                        height: 40,
                        child: Icon(
                          Icons.location_pin,
                          color: theme.colorScheme.error,
                          size: 38,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (coordinateLabel != null)
            Text(
              coordinateLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ] else
          Text(
            normalizedUrl.isEmpty
                ? 'Sin coordenadas registradas.'
                : 'La ubicacion fue guardada como enlace, pero no tiene coordenadas para mostrar el mapa aqui.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (uri != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => safeOpenUrl(context, uri),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('Abrir ubicacion'),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              alignment: Alignment.centerLeft,
            ),
          ),
        ],
      ],
    );
  }
}

class _TimelineSection extends StatelessWidget {
  const _TimelineSection({
    required this.title,
    required this.emptyLabel,
    required this.children,
  });

  final String title;
  final String emptyLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        if (children.isEmpty)
          Text(
            emptyLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          Column(
            children: [
              for (var index = 0; index < children.length; index++) ...[
                if (index > 0)
                  Divider(
                    height: 14,
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.35,
                    ),
                  ),
                children[index],
              ],
            ],
          ),
      ],
    );
  }
}

class _TimelineEventCard extends StatelessWidget {
  const _TimelineEventCard({
    required this.icon,
    required this.title,
    required this.summary,
    required this.date,
    required this.amount,
    required this.statusLabel,
    required this.statusColor,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String summary;
  final String date;
  final String? amount;
  final String statusLabel;
  final Color statusColor;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.75,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 14,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (amount != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            amount!,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      date,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    statusLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(
                    enabled
                        ? Icons.chevron_right_rounded
                        : Icons.remove_rounded,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
