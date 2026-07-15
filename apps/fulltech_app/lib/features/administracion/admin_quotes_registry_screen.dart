import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/errors/user_facing_error.dart';
import '../../core/models/user_model.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/professional_recovery_card.dart';
import '../../features/user/data/users_repository.dart';
import '../../modules/cotizaciones/cotizacion_models.dart';
import '../../modules/cotizaciones/data/cotizaciones_repository.dart';

class AdminQuotesRegistryScreen extends ConsumerStatefulWidget {
  const AdminQuotesRegistryScreen({super.key});

  @override
  ConsumerState<AdminQuotesRegistryScreen> createState() =>
      _AdminQuotesRegistryScreenState();
}

class _AdminQuotesRegistryScreenState
    extends ConsumerState<AdminQuotesRegistryScreen> {
  static const List<int> _autoRetrySecondsByAttempt = <int>[3, 6, 12];

  bool _loading = false;
  bool _refreshing = false;
  UserFacingError? _error;
  List<CotizacionModel> _items = const [];
  List<UserModel> _users = const [];
  String? _selectedUserId;
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  Timer? _autoRetryTimer;
  int _autoRetryAttempt = 0;
  int _autoRetryCountdown = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _autoRetryTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    _autoRetryTimer?.cancel();

    if (mounted) {
      setState(() {
        _loading = true;
        _refreshing = false;
        _error = null;
        _autoRetryCountdown = 0;
      });
    }

    final repo = ref.read(cotizacionesRepositoryProvider);
    final selectedUserId = (_selectedUserId ?? '').trim();
    try {
      final cached = await repo.getCachedList(
        userId: selectedUserId.isEmpty ? null : selectedUserId,
        from: _from,
        to: _to,
      );
      if (!mounted) return;
      if (cached.isNotEmpty) {
        setState(() {
          _items = cached;
          _loading = false;
          _refreshing = true;
        });
      }

      final results = await Future.wait<dynamic>([
        repo.listAndCache(
          userId: selectedUserId.isEmpty ? null : selectedUserId,
          from: _from,
          to: _to,
        ),
        ref.read(usersRepositoryProvider).getAllUsers(skipLoader: true),
      ]);
      if (!mounted) return;
      final rows = results[0] as List<CotizacionModel>;
      final users = results[1] as List<UserModel>;
      final filteredRows = selectedUserId.isEmpty
          ? rows
          : rows
              .where(
                (item) => (item.createdByUserId ?? '').trim() == selectedUserId,
              )
              .toList(growable: false);
      setState(() {
        _items = filteredRows;
        _users = users;
        _loading = false;
        _refreshing = false;
        _autoRetryAttempt = 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = UserFacingError.from(e);
        _loading = false;
        _refreshing = false;
      });
      _scheduleAutoRetryIfNeeded();
    }
  }

  void _scheduleAutoRetryIfNeeded() {
    final error = _error;
    if (error == null || !error.autoRetry) return;
    if (_autoRetryAttempt >= _autoRetrySecondsByAttempt.length) return;

    _autoRetryTimer?.cancel();
    final seconds = _autoRetrySecondsByAttempt[_autoRetryAttempt];
    setState(() => _autoRetryCountdown = seconds);

    _autoRetryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_autoRetryCountdown <= 1) {
        timer.cancel();
        _autoRetryAttempt += 1;
        unawaited(_load());
        return;
      }
      setState(() => _autoRetryCountdown -= 1);
    });
  }

  Future<void> _retryNow() async {
    _autoRetryTimer?.cancel();
    if (mounted) setState(() => _autoRetryCountdown = 0);
    await _load();
  }

  String _money(double value) => formatRdCurrencyAccounting(value);

  String _dateOnlyText(DateTime value) {
    return DateFormat('dd/MM/yyyy', 'es_DO').format(value);
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
    await _load();
  }

  void _openQuoteDetail(CotizacionModel item) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Detalle de cotización'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('ID: ${item.id}'),
                  Text('Usuario: ${item.createdByUserName ?? item.createdByUserId ?? 'No disponible'}'),
                  Text('Cliente: ${item.customerName}'),
                  if ((item.customerPhone ?? '').trim().isNotEmpty)
                    Text('Teléfono: ${item.customerPhone}'),
                  Text(
                    'Fecha: ${DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(item.createdAt)}',
                  ),
                  if (item.note.trim().isNotEmpty) Text('Nota: ${item.note}'),
                  const Divider(height: 18),
                  ...item.items.map(
                    (line) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${line.nombre} x${line.qty.toStringAsFixed(line.qty % 1 == 0 ? 0 : 2)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(_money(line.total)),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 18),
                  Text('Subtotal: ${_money(item.subtotal)}'),
                  Text('ITBIS: ${_money(item.itbisAmount)}'),
                  Text('Total: ${_money(item.total)}'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authStateProvider).user;

    return Scaffold(
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      appBar: CustomAppBar(
        title: 'Registro global de cotizaciones',
        fallbackRoute: Routes.administracion,
        showLogo: false,
        showDepartmentLabel: false,
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ProfessionalRecoveryCard(
                  error: _error!,
                  autoRetryCountdown: _autoRetryCountdown > 0
                      ? _autoRetryCountdown
                      : null,
                  isRetrying: _loading,
                  onRetryNow: _retryNow,
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                      child: DropdownButtonFormField<String?>(
                        initialValue: _selectedUserId,
                        decoration: const InputDecoration(
                          labelText: 'Filtrar por usuario',
                          prefixIcon: Icon(Icons.person_search_outlined),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Todos los usuarios'),
                          ),
                          ..._users.map(
                            (user) => DropdownMenuItem<String?>(
                              value: user.id,
                              child: Text(
                                user.nombreCompleto.trim().isEmpty
                                    ? user.email
                                    : user.nombreCompleto,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _selectedUserId = value);
                          unawaited(_load());
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: _pickDateRange,
                          icon: const Icon(Icons.date_range_rounded),
                          label: Text(
                            'Rango: ${_dateOnlyText(_from)} - ${_dateOnlyText(_to)}',
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _items.isEmpty
                          ? const Center(
                              child: Text(
                                'No hay cotizaciones globales para mostrar.',
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _load,
                              child: ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                                itemCount: _items.length + (_refreshing ? 1 : 0),
                                separatorBuilder: (_, _) => const SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  if (_refreshing && index == 0) {
                                    return const LinearProgressIndicator();
                                  }
                                  final item = _items[_refreshing ? index - 1 : index];

                                  final owner = (item.createdByUserName ?? '').trim();
                                  final ownerText = owner.isEmpty
                                      ? ((item.createdByUserId ?? '').trim().isEmpty
                                          ? 'Usuario no disponible'
                                          : item.createdByUserId!)
                                      : owner;

                                  return Card(
                                    child: ListTile(
                                      onTap: () => _openQuoteDetail(item),
                                      title: Text(
                                        item.customerName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        '${DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(item.createdAt)} '
                                        '· Líneas: ${item.items.length} · Usuario: $ownerText',
                                      ),
                                      trailing: Text(
                                        _money(item.total),
                                        style: const TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }
}
