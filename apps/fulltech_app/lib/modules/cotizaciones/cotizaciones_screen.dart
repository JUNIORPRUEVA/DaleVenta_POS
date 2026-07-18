import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/app_role.dart';
import '../../core/cache/fulltech_cache_manager.dart';
import '../../core/cache/local_json_cache.dart';
import '../../core/company/company_settings_model.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/errors/api_exception.dart';
import '../../core/models/user_model.dart';
import '../../core/models/product_model.dart';
import '../../core/printing/unified_ticket_printer.dart';
import '../../core/realtime/catalog_realtime_service.dart';
import '../../core/routing/app_route_observer.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/fulltech_dialog.dart';
import '../../core/widgets/fulltech_page_header.dart';
import '../../core/widgets/pdf_action_menu.dart';
import '../../core/widgets/responsive_shell.dart';
import '../../core/widgets/product_network_image.dart';
import '../../features/catalogo/application/catalog_controller.dart';
import '../../features/products/ui/inventory_module_pages.dart';
import '../cash/cash_repository.dart';
import '../cash/cash_turn_menu_button.dart';
import '../clientes/cliente_model.dart';
import '../clientes/cliente_form_screen.dart';
import '../service_orders/create_service_order_screen.dart';
import '../service_orders/service_order_models.dart';
import '../ventas/data/ventas_repository.dart';
import '../ventas/application/ventas_controller.dart';
import '../ventas/sales_credit_screen.dart';
import '../ventas/sales_models.dart';
import '../ventas/utils/sales_pdf_service.dart';
import 'ai/application/quotation_ai_controller.dart';
import 'ai/domain/models/ai_warning.dart';
import 'ai/domain/models/quotation_context.dart';
import 'ai/domain/services/quotation_ai_service.dart';
import 'ai/presentation/widgets/ai_chat_sheet.dart';
import 'ai/presentation/widgets/ai_warning_banner.dart';
import 'ai/presentation/widgets/quotation_rule_detail_sheet.dart';
import 'cotizacion_models.dart';
import 'data/cotizaciones_repository.dart';
import 'utils/cotizacion_pdf_service.dart';

enum _CheckoutPaymentMethod {
  cash('Efectivo', Icons.payments_outlined),
  transfer('Transferencia', Icons.account_balance_outlined),
  mixed('Mixto', Icons.call_split_rounded),
  credit('Crédito', Icons.credit_score_outlined);

  const _CheckoutPaymentMethod(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum _QuotePdfShareAction {
  sharePdf('Compartir PDF', Icons.picture_as_pdf_outlined),
  shareClient('Compartir con cliente', Icons.person_outline),
  save('Guardar en descargas', Icons.download_outlined),
  admin('Enviar admin', Icons.verified_user_outlined);

  const _QuotePdfShareAction(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _CheckoutResult {
  const _CheckoutResult({
    required this.method,
    required this.cashAmount,
    required this.transferAmount,
    required this.creditAmount,
  });

  final _CheckoutPaymentMethod method;
  final double cashAmount;
  final double transferAmount;
  final double creditAmount;
}

class _ManualItemMetric extends StatelessWidget {
  const _ManualItemMetric({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class CotizacionesScreen extends ConsumerStatefulWidget {
  const CotizacionesScreen({
    super.key,
    this.initialClient,
    this.initialQuotation,
    this.returnSavedQuotation = false,
  });

  final ClienteModel? initialClient;
  final CotizacionModel? initialQuotation;
  final bool returnSavedQuotation;

  @override
  ConsumerState<CotizacionesScreen> createState() => _CotizacionesScreenState();
}

class _CotizacionesScreenState extends ConsumerState<CotizacionesScreen>
    with WidgetsBindingObserver
    implements RouteAware {
  static const double _desktopBreakpoint = 900;
  static const String _editorDraftCachePrefix = 'cotizaciones:editorDraft:';

  final LocalJsonCache _editorDraftCache = LocalJsonCache();
  Timer? _persistEditorDraftTimer;
  Timer? _salesNoticeTimer;
  OverlayEntry? _salesNoticeEntry;
  String? _lastSalesNoticeKey;
  int _salesNoticeCount = 0;
  bool _restoringEditorDraft = false;

  final TextEditingController _searchCtrl = TextEditingController();

  final List<CotizacionItem> _items = [];
  List<ProductModel> _productos = const [];

  bool _loadingProducts = false;
  String? _error;
  String? _selectedCategory;
  bool _showDesktopManualItemForm = false;
  int? _desktopManualEditIndex;

  String? _selectedClientId;
  String _selectedClientName = 'Sin cliente';
  String? _selectedClientPhone;
  String _note = '';

  bool _includeItbis = false;
  static const double _itbisRate = 0.18;
  String _fiscalVoucherType = 'B01';
  String _fiscalVoucherNumber = '';
  DateTime? _fiscalVoucherDueDate;
  String _fiscalCustomerTaxId = '';
  String _fiscalCustomerName = '';
  double _generalDiscountAmount = 0;

  String? _editingId;
  DateTime? _editingCreatedAt;

  List<_DesktopTicketDraft> _desktopTickets = [];
  String? _activeDesktopTicketId;
  String? _lastPublishedDesktopFooterSignature;

  bool _prefillFromRouteApplied = false;
  bool _routeObserverSubscribed = false;
  RouteObserver<ModalRoute<dynamic>>? _routeObserver;
  String? _lastLoadedRouteQuotationId;
  bool _loadingRouteQuotation = false;
  bool _remoteRefreshInFlight = false;
  DateTime? _lastSuccessfulRemoteSyncAt;
  DateTime? _lastAutoSyncAt;
  Timer? _liveSyncTimer;
  StreamSubscription<CatalogRealtimeMessage>? _realtimeSubscription;
  static const Duration _liveSyncInterval = Duration(minutes: 2);
  static const Duration _silentRefreshMinInterval = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    final initialDraft = _DesktopTicketDraft.empty(
      id: _newId(),
      title: 'Ticket 1',
    );
    _desktopTickets = [initialDraft];
    _activeDesktopTicketId = initialDraft.id;
    WidgetsBinding.instance.addObserver(this);
    _subscribeRealtime();
    _applyInitialClient();
    _applyInitialQuotation();
    unawaited(_bootstrapCatalog());
    _startLiveSync();
    if (!widget.returnSavedQuotation) {
      unawaited(_restorePersistedEditorDraftIfAny());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_syncQuotationAi(triggerAi: false));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribeRouteObserver();
    _scheduleAutoSync();

    if (widget.returnSavedQuotation) {
      return;
    }

    if (_prefillFromRouteApplied) return;
    _prefillFromRouteApplied = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _applyClientPrefillFromRoute();
      unawaited(_applyQuotationPrefillFromRoute());
    });
  }

  void _applyInitialClient() {
    final client = widget.initialClient;
    if (client == null) return;
    _selectedClientId = client.id;
    _selectedClientName = client.nombre;
    _selectedClientPhone = client.telefono;
  }

  void _applyInitialQuotation() {
    final quotation = widget.initialQuotation;
    if (quotation == null) return;
    _applyQuotationToEditor(quotation);
  }

  void _applyQuotationToEditor(CotizacionModel quotation) {
    _items
      ..clear()
      ..addAll(quotation.items.map((item) => item.copyWith()));
    _selectedClientId = quotation.customerId;
    _selectedClientName = quotation.customerName;
    _selectedClientPhone = quotation.customerPhone;
    _note = quotation.note;
    _includeItbis = quotation.includeItbis;
    _generalDiscountAmount = quotation.globalDiscountAmount;
    _editingId = quotation.id;
    _editingCreatedAt = quotation.createdAt;
  }

  void _subscribeRouteObserver() {
    if (_routeObserverSubscribed) return;
    final route = ModalRoute.of(context);
    if (route == null) return;
    final observer = ref.read(appRouteObserverProvider);
    observer.subscribe(this, route);
    _routeObserver = observer;
    _routeObserverSubscribed = true;
  }

  void _subscribeRealtime() {
    _realtimeSubscription?.cancel();
    _realtimeSubscription = ref
        .read(catalogRealtimeServiceProvider)
        .stream
        .listen((_) => _loadProducts(forceRemote: true, silent: true));
  }

  void _startLiveSync() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = Timer.periodic(_liveSyncInterval, (_) {
      if (!mounted) return;
      _loadProducts(forceRemote: true, silent: true);
    });
  }

  void _stopLiveSync() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = null;
  }

  void _scheduleAutoSync() {
    final now = DateTime.now();
    final last = _lastAutoSyncAt;
    if (last != null && now.difference(last).inMilliseconds < 1200) return;
    _lastAutoSyncAt = now;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadProducts(forceRemote: true, silent: true);
    });
  }

  void _syncProductsOnEnter() {
    if (!mounted) return;
    _loadProducts(forceRemote: true, silent: true);
  }

  @override
  void didPush() {
    _syncProductsOnEnter();
  }

  @override
  void didPopNext() {
    _syncProductsOnEnter();
  }

  @override
  void didPushNext() {}

  @override
  void didPop() {}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _startLiveSync();
      _loadProducts(forceRemote: true, silent: true);
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _stopLiveSync();
    }
  }

  void _applyClientPrefillFromRoute({bool force = false}) {
    if (!mounted) return;
    final qp = GoRouterState.of(context).uri.queryParameters;
    final id = (qp['customerId'] ?? '').trim();
    final name = (qp['customerName'] ?? '').trim();
    final phone = (qp['customerPhone'] ?? '').trim();

    if (id.isEmpty && name.isEmpty && phone.isEmpty) return;

    final hasSelection =
        (_selectedClientId ?? '').trim().isNotEmpty ||
        _selectedClientName.trim() != 'Sin cliente';
    if (hasSelection && !force) return;

    setState(() {
      if (force) {
        _selectedClientId = id.isEmpty ? null : id;
        _selectedClientName = name.isEmpty ? 'Sin cliente' : name;
        _selectedClientPhone = phone.isEmpty ? null : phone;
      } else {
        if (id.isNotEmpty) _selectedClientId = id;
        if (name.isNotEmpty) _selectedClientName = name;
        if (phone.isNotEmpty) _selectedClientPhone = phone;
      }
      _writeActiveDesktopDraft();
    });
    _schedulePersistEditorDraft();
    unawaited(_syncQuotationAi(triggerAi: false));

    if ((_selectedClientId ?? '').trim().isEmpty && phone.isNotEmpty) {
      _resolveClientIdByPhone(phone);
    }
  }

  Future<void> _applyQuotationPrefillFromRoute() async {
    if (_loadingRouteQuotation) return;

    final qp = GoRouterState.of(context).uri.queryParameters;
    final quotationId = (qp['quotationId'] ?? '').trim();
    final duplicate = (qp['duplicate'] ?? '').trim() == '1';
    if (quotationId.isEmpty) return;
    final routeQuotationKey = duplicate
        ? '$quotationId:duplicate'
        : quotationId;
    if (!duplicate && (_editingId ?? '').trim() == quotationId) return;
    if (_lastLoadedRouteQuotationId == routeQuotationKey) return;

    _loadingRouteQuotation = true;
    try {
      final repository = ref.read(cotizacionesRepositoryProvider);
      final cached = await repository.getCachedById(quotationId);
      final quotation = cached ?? await repository.getByIdAndCache(quotationId);
      if (!mounted) return;

      setState(() {
        _applyQuotationToEditor(quotation);
        if (duplicate) {
          _editingId = null;
          _editingCreatedAt = null;
        }
        _writeActiveDesktopDraft();
      });
      _schedulePersistEditorDraft();
      _lastLoadedRouteQuotationId = routeQuotationKey;
      unawaited(_syncQuotationAi(triggerAi: false));
    } catch (_) {
      _lastLoadedRouteQuotationId = routeQuotationKey;
    } finally {
      _loadingRouteQuotation = false;
    }
  }

  Future<void> _resolveClientIdByPhone(String phone) async {
    try {
      final clients = await ref
          .read(ventasRepositoryProvider)
          .searchClients(phone);
      if (!mounted) return;

      ClienteModel? match;
      for (final c in clients) {
        if (c.telefono.trim() == phone.trim()) {
          match = c;
          break;
        }
      }
      match ??= clients.isEmpty ? null : clients.first;
      if (match == null) return;

      final matchId = match.id;
      final matchName = match.nombre;
      final matchPhone = match.telefono;

      setState(() {
        _selectedClientId = matchId;
        _selectedClientName = matchName;
        _selectedClientPhone = matchPhone;
        _writeActiveDesktopDraft();
      });
      _schedulePersistEditorDraft();
      unawaited(_syncQuotationAi(triggerAi: false));
    } catch (_) {
      // Silencioso: si no se puede resolver, el usuario puede escoger cliente.
    }
  }

  @override
  void dispose() {
    _hideSalesNotice();
    _clearDesktopShellFooter();
    _persistEditorDraftTimer?.cancel();
    _persistEditorDraftTimer = null;
    unawaited(_persistEditorDraft());
    WidgetsBinding.instance.removeObserver(this);
    if (_routeObserverSubscribed) {
      _routeObserver?.unsubscribe(this);
      _routeObserverSubscribed = false;
      _routeObserver = null;
    }
    _stopLiveSync();
    _realtimeSubscription?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _editorDraftCacheKey() {
    final ownerId = (ref.read(authStateProvider).user?.id ?? 'anon').trim();
    return '$_editorDraftCachePrefix$ownerId';
  }

  void _schedulePersistEditorDraft({bool immediate = false}) {
    if (_restoringEditorDraft) return;
    _persistEditorDraftTimer?.cancel();
    _persistEditorDraftTimer = null;

    if (immediate) {
      unawaited(_persistEditorDraft());
      return;
    }

    _persistEditorDraftTimer = Timer(const Duration(milliseconds: 450), () {
      _persistEditorDraftTimer = null;
      unawaited(_persistEditorDraft());
    });
  }

  Future<void> _persistEditorDraft() async {
    if (!mounted) return;
    try {
      final map = <String, dynamic>{
        'v': 1,
        'activeId': _activeDesktopTicketId,
        'tickets': _desktopTickets.map((t) => t.toMap()).toList(),
      };
      await _editorDraftCache.writeMap(_editorDraftCacheKey(), map);
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> _restorePersistedEditorDraftIfAny() async {
    if (!mounted) return;
    _restoringEditorDraft = true;
    try {
      final cached = await _editorDraftCache.readMap(_editorDraftCacheKey());
      if (!mounted) return;
      if (cached == null) return;

      final rawTickets = (cached['tickets'] as List?) ?? const [];
      final tickets = rawTickets
          .whereType<Map>()
          .map(
            (row) => _DesktopTicketDraft.fromMap(row.cast<String, dynamic>()),
          )
          .toList();

      if (tickets.isEmpty) return;

      final cachedActive = (cached['activeId'] ?? '').toString().trim();
      final activeId = tickets.any((t) => t.id == cachedActive)
          ? cachedActive
          : tickets.first.id;
      final activeTicket = tickets.firstWhere((t) => t.id == activeId);

      setState(() {
        _desktopTickets = tickets;
        _activeDesktopTicketId = activeId;
        _replaceEditorStateFromDraft(activeTicket);
        _writeActiveDesktopDraft();
      });
      _applyClientPrefillFromRoute(force: true);
      unawaited(_syncQuotationAi(triggerAi: false));
    } catch (_) {
      // Ignore invalid cache entries.
    } finally {
      _restoringEditorDraft = false;
    }
  }

  Future<void> _loadProducts({
    bool forceRemote = false,
    bool silent = false,
  }) async {
    if (silent && forceRemote && _remoteRefreshInFlight) return;
    if (silent &&
        forceRemote &&
        _productos.isNotEmpty &&
        _lastSuccessfulRemoteSyncAt != null &&
        DateTime.now().difference(_lastSuccessfulRemoteSyncAt!) <
            _silentRefreshMinInterval) {
      return;
    }
    if (silent && forceRemote) {
      _remoteRefreshInFlight = true;
    }

    if (!silent) {
      setState(() {
        _loadingProducts = true;
        _error = null;
      });
    }

    try {
      final rows = await ref
          .read(ventasRepositoryProvider)
          .fetchProducts(forceRefresh: forceRemote);
      final catalogVersion = buildCatalogSyncVersion(rows);
      final syncedRows = applyCatalogSyncVersion(rows, catalogVersion);
      final syncedAt = DateTime.now();

      if (!mounted) return;
      setState(() {
        _productos = syncedRows;
        _loadingProducts = false;
        _error = null;
      });
      unawaited(_syncQuotationAi(triggerAi: false));
      Future<void>.microtask(
        () => FulltechImageCacheManager.warmImageUrls(
          syncedRows.map((item) => item.displayFotoUrl),
        ),
      );
      _lastSuccessfulRemoteSyncAt = syncedAt;
    } catch (e) {
      if (!mounted) return;
      if (silent) return;
      setState(() {
        _loadingProducts = false;
        _error = 'No se pudieron cargar productos: $e';
      });
    } finally {
      if (silent && forceRemote) {
        _remoteRefreshInFlight = false;
      }
    }
  }

  Future<void> _bootstrapCatalog() async {
    await _loadProducts(forceRemote: true);
  }

  void _persistCatalogUiState() {}

  Future<void> _disposeControllersSafely(
    Iterable<TextEditingController> controllers,
  ) async {
    await WidgetsBinding.instance.endOfFrame;
    for (final controller in controllers) {
      controller.dispose();
    }
  }

  List<String> get _categories {
    final values = _productos
        .map((product) => product.categoriaLabel.trim())
        .where((label) => label.isNotEmpty)
        .toSet()
        .toList();
    values.sort((left, right) => left.compareTo(right));
    return values;
  }

  List<ProductModel> get _visibleProducts {
    final query = _searchCtrl.text.trim().toLowerCase();
    return _productos.where((product) {
      if (_selectedCategory != null &&
          product.categoriaLabel != _selectedCategory) {
        return false;
      }
      if (query.isEmpty) return true;
      return product.nombre.toLowerCase().contains(query) ||
          product.categoriaLabel.toLowerCase().contains(query);
    }).toList();
  }

  void _submitSearchAndAddFirstVisibleProduct() {
    final visible = _visibleProducts;
    if (visible.isEmpty) {
      return;
    }
    _addProduct(visible.first);
  }

  double get _subtotal => _items.fold(0, (sum, item) => sum + item.total);
  double get _subtotalBeforeDiscount => _items.fold(
    0,
    (sum, item) => sum + (item.effectiveOriginalUnitPrice * item.qty),
  );
  double get _lineDiscountAmount =>
      _items.fold(0, (sum, item) => sum + item.discountAmount);
  double get _grossTotalBeforeGeneralDiscount => _subtotal + _itbisAmount;
  double get _effectiveGeneralDiscountAmount {
    final maxDiscount = _grossTotalBeforeGeneralDiscount;
    if (_generalDiscountAmount <= 0) return 0;
    return _generalDiscountAmount > maxDiscount
        ? maxDiscount
        : _generalDiscountAmount;
  }

  double get _discountAmount =>
      _lineDiscountAmount + _effectiveGeneralDiscountAmount;
  double get _itbisAmount => _includeItbis ? (_subtotal * _itbisRate) : 0;
  double get _totalCost =>
      _items.fold(0, (sum, item) => sum + item.subtotalCost);
  double get _total =>
      _grossTotalBeforeGeneralDiscount - _effectiveGeneralDiscountAmount;
  double get _utilityAmount =>
      _subtotal - _totalCost - _effectiveGeneralDiscountAmount;

  String _money(double value) => formatRdCurrencyAccounting(value);

  double _roundCurrency(double value) => double.parse(value.toStringAsFixed(2));

  double _roundUnitPrice(double value) =>
      double.parse(value.toStringAsFixed(6));

  List<SaleDraftItem> _buildCheckoutSaleItems() {
    final grossMultiplier = _includeItbis ? 1 + _itbisRate : 1.0;
    final grossLines = _items
        .map((item) => (item.total * grossMultiplier).clamp(0, double.infinity))
        .toList(growable: false);
    final grossBase = grossLines.fold<double>(0, (sum, value) => sum + value);
    final targetTotal = _roundCurrency(_total.clamp(0, double.infinity));
    var remainingTotal = targetTotal;

    return [
      for (var index = 0; index < _items.length; index++)
        () {
          final item = _items[index];
          final isLast = index == _items.length - 1;
          final lineTarget = grossBase <= 0
              ? 0.0
              : isLast
              ? remainingTotal
              : _roundCurrency(targetTotal * (grossLines[index] / grossBase));
          remainingTotal = _roundCurrency(remainingTotal - lineTarget);
          final priceSoldUnit = item.qty > 0
              ? _roundUnitPrice(lineTarget / item.qty)
              : 0.0;
          return SaleDraftItem(
            productId: item.isExternal ? null : item.productId,
            name: item.nombre,
            imageUrl: item.imageUrl,
            isExternal: item.isExternal,
            qty: item.qty,
            priceSoldUnit: priceSoldUnit,
            costUnitSnapshot: item.tracedCostUnit ?? 0,
          );
        }(),
    ];
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  _DesktopTicketDraft _snapshotCurrentDesktopDraft({
    required String id,
    required String title,
  }) {
    return _DesktopTicketDraft(
      id: id,
      title: title,
      items: _items.map((item) => item.copyWith()).toList(),
      selectedClientId: _selectedClientId,
      selectedClientName: _selectedClientName,
      selectedClientPhone: _selectedClientPhone,
      note: _note,
      includeItbis: _includeItbis,
      fiscalVoucherType: _fiscalVoucherType,
      fiscalVoucherNumber: _fiscalVoucherNumber,
      fiscalVoucherDueDate: _fiscalVoucherDueDate,
      fiscalCustomerTaxId: _fiscalCustomerTaxId,
      fiscalCustomerName: _fiscalCustomerName,
      globalDiscountAmount: _generalDiscountAmount,
      editingId: _editingId,
      editingCreatedAt: _editingCreatedAt,
      selectedCategory: _selectedCategory,
      searchQuery: _searchCtrl.text,
    );
  }

  _DesktopTicketDraft? _findDesktopTicket(String? id) {
    if (id == null) return null;
    for (final ticket in _desktopTickets) {
      if (ticket.id == id) return ticket;
    }
    return null;
  }

  void _writeActiveDesktopDraft() {
    final activeId = _activeDesktopTicketId;
    if (activeId == null || _desktopTickets.isEmpty) return;
    final index = _desktopTickets.indexWhere((ticket) => ticket.id == activeId);
    if (index < 0) return;
    final current = _desktopTickets[index];
    _desktopTickets[index] = _snapshotCurrentDesktopDraft(
      id: current.id,
      title: current.title,
    );
  }

  void _replaceEditorStateFromDraft(_DesktopTicketDraft draft) {
    _items
      ..clear()
      ..addAll(draft.items.map((item) => item.copyWith()));
    _selectedClientId = draft.selectedClientId;
    _selectedClientName = draft.selectedClientName;
    _selectedClientPhone = draft.selectedClientPhone;
    _note = draft.note;
    _includeItbis = draft.includeItbis;
    _fiscalVoucherType = draft.fiscalVoucherType;
    _fiscalVoucherNumber = draft.fiscalVoucherNumber;
    _fiscalVoucherDueDate = draft.fiscalVoucherDueDate;
    _fiscalCustomerTaxId = draft.fiscalCustomerTaxId;
    _fiscalCustomerName = draft.fiscalCustomerName;
    _generalDiscountAmount = draft.globalDiscountAmount;
    _editingId = draft.editingId;
    _editingCreatedAt = draft.editingCreatedAt;
    _selectedCategory = draft.selectedCategory;
    _searchCtrl.text = draft.searchQuery;
  }

  void _resetEditorState() {
    _items.clear();
    _searchCtrl.clear();
    _selectedCategory = null;
    _selectedClientId = null;
    _selectedClientName = 'Sin cliente';
    _selectedClientPhone = null;
    _note = '';
    _includeItbis = false;
    _fiscalVoucherType = 'B01';
    _fiscalVoucherNumber = '';
    _fiscalVoucherDueDate = null;
    _fiscalCustomerTaxId = '';
    _fiscalCustomerName = '';
    _generalDiscountAmount = 0;
    _editingId = null;
    _editingCreatedAt = null;
  }

  Future<void> _confirmAndClearSale() async {
    if (_items.isEmpty) {
      _commitEditorChange(_resetEditorState);
      return;
    }
    final confirmed = await FullTechConfirmDialog.show(
      context,
      title: 'Cancelar venta',
      message:
          'Los productos serán eliminados de la venta actual.\n¿Desea continuar?',
      confirmText: 'Aceptar',
      cancelText: 'Cancelar',
      icon: Icons.delete_sweep_outlined,
      iconColor: const Color(0xFF1957E6),
      isDestructive: false,
    );
    if (confirmed != true || !mounted) return;
    _commitEditorChange(_resetEditorState);
  }

  bool get _hasEditorContent {
    return _items.isNotEmpty ||
        _searchCtrl.text.trim().isNotEmpty ||
        (_selectedClientId ?? '').trim().isNotEmpty ||
        _selectedClientName.trim() != 'Sin cliente' ||
        (_selectedClientPhone ?? '').trim().isNotEmpty ||
        _note.trim().isNotEmpty ||
        _includeItbis ||
        _fiscalVoucherNumber.trim().isNotEmpty ||
        _fiscalCustomerTaxId.trim().isNotEmpty ||
        _fiscalCustomerName.trim().isNotEmpty ||
        _fiscalVoucherDueDate != null ||
        _generalDiscountAmount != 0 ||
        (_editingId ?? '').trim().isNotEmpty ||
        (_selectedCategory ?? '').trim().isNotEmpty;
  }

  bool get _fiscalVoucherRequiresTaxId {
    return _fiscalVoucherType == 'B01' ||
        _fiscalVoucherType == 'B14' ||
        _fiscalVoucherType == 'B15';
  }

  bool get _hasFiscalVoucherReady {
    return _fiscalVoucherValidationMessage == null;
  }

  String? get _fiscalVoucherValidationMessage {
    if (!_includeItbis) return null;
    final type = _fiscalVoucherType.trim().toUpperCase();
    final ncf = _fiscalVoucherNumber.trim().toUpperCase();
    if (type.isEmpty) return 'Selecciona el tipo de comprobante.';
    if (ncf.isEmpty) return 'Indica el número de comprobante / NCF.';
    if (!ncf.startsWith(type)) {
      return 'El NCF debe iniciar con el tipo seleccionado ($type).';
    }
    if (!RegExp(r'^B\d{10}$').hasMatch(ncf)) {
      return 'El NCF debe tener formato válido, ejemplo B0100000001.';
    }
    if (_fiscalVoucherDueDate == null) {
      return 'Selecciona la fecha de vencimiento del comprobante.';
    }
    final today = DateTime.now();
    final dueDate = DateUtils.dateOnly(_fiscalVoucherDueDate!);
    if (dueDate.isBefore(DateUtils.dateOnly(today))) {
      return 'La fecha de vencimiento del comprobante no puede estar vencida.';
    }
    if (_fiscalVoucherRequiresTaxId && _fiscalCustomerTaxId.trim().isEmpty) {
      return 'Indica el RNC o cédula fiscal del cliente.';
    }
    return null;
  }

  void _setItbisEnabled(bool value) {
    _includeItbis = value;
    if (value && _fiscalCustomerName.trim().isEmpty) {
      final clientName = _selectedClientName.trim();
      _fiscalCustomerName = clientName == 'Sin cliente' ? '' : clientName;
    }
  }

  String _fiscalVoucherTypeLabel(String type) {
    return switch (type) {
      'B01' => 'B01 - Crédito fiscal',
      'B02' => 'B02 - Consumidor final',
      'B14' => 'B14 - Régimen especial',
      'B15' => 'B15 - Gubernamental',
      _ => type,
    };
  }

  List<String> _fiscalSaleNoteLines() {
    if (!_includeItbis) return const [];
    final date = _fiscalVoucherDueDate;
    return [
      'Factura con valor fiscal',
      'Tipo comprobante: ${_fiscalVoucherTypeLabel(_fiscalVoucherType)}',
      'NCF: ${_fiscalVoucherNumber.trim()}',
      if (date != null)
        'Vencimiento NCF: ${DateFormat('dd/MM/yyyy').format(date)}',
      if (_fiscalCustomerTaxId.trim().isNotEmpty)
        'RNC/Cédula: ${_fiscalCustomerTaxId.trim()}',
      if (_fiscalCustomerName.trim().isNotEmpty)
        'Razón social: ${_fiscalCustomerName.trim()}',
      'ITBIS ${(_itbisRate * 100).toStringAsFixed(0)}%: ${_money(_itbisAmount)}',
    ];
  }

  Future<void> _pickFiscalVoucherDueDate() async {
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final currentDueDate = _fiscalVoucherDueDate == null
        ? null
        : DateUtils.dateOnly(_fiscalVoucherDueDate!);
    final selected = await showDatePicker(
      context: context,
      initialDate: currentDueDate == null || currentDueDate.isBefore(today)
          ? today.add(const Duration(days: 30))
          : currentDueDate,
      firstDate: today,
      lastDate: DateTime(now.year + 10),
      helpText: 'Vencimiento del comprobante',
      cancelText: 'Cancelar',
      confirmText: 'Aplicar',
    );
    if (selected == null || !mounted) return;
    _commitEditorChange(() => _fiscalVoucherDueDate = selected);
  }

  void _commitEditorChange(VoidCallback changes) {
    setState(() {
      changes();
      _writeActiveDesktopDraft();
    });
    _schedulePersistEditorDraft();
    _persistCatalogUiState();
    unawaited(_syncQuotationAi());
  }

  bool _shouldShowAiBanner(QuotationAiState aiState) {
    return false;
  }

  void _hideSalesNotice() {
    _salesNoticeTimer?.cancel();
    _salesNoticeTimer = null;
    _salesNoticeEntry?.remove();
    _salesNoticeEntry = null;
  }

  void _showSalesNotice({
    required String title,
    required String message,
    IconData icon = Icons.info_outline_rounded,
    Color accent = const Color(0xFF1957E6),
    Duration duration = const Duration(milliseconds: 2800),
  }) {
    if (!mounted) return;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    final noticeKey = '$title|$message';
    _salesNoticeCount = _lastSalesNoticeKey == noticeKey
        ? _salesNoticeCount + 1
        : 1;
    _lastSalesNoticeKey = noticeKey;

    _hideSalesNotice();
    final topPadding = MediaQuery.viewPaddingOf(context).top + 20;
    final count = _salesNoticeCount;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: topPadding,
          right: 18,
          child: _SalesNoticeToast(
            title: title,
            message: message,
            icon: icon,
            accent: accent,
            repeatCount: count,
            onClose: _hideSalesNotice,
          ),
        );
      },
    );
    _salesNoticeEntry = entry;
    overlay.insert(entry);
    _salesNoticeTimer = Timer(duration, _hideSalesNotice);
  }

  void _closeAiBanner() {
    if (!mounted) return;
    setState(() {});
  }

  String _nextDesktopTicketTitle() => 'Ticket ${_desktopTickets.length + 1}';

  void _createNewDesktopTicket() {
    setState(() {
      _writeActiveDesktopDraft();
      final ticket = _DesktopTicketDraft.empty(
        id: _newId(),
        title: _nextDesktopTicketTitle(),
      );
      _desktopTickets = [..._desktopTickets, ticket];
      _activeDesktopTicketId = ticket.id;
      _replaceEditorStateFromDraft(ticket);
      _writeActiveDesktopDraft();
    });
    _schedulePersistEditorDraft();
  }

  void _switchDesktopTicket(String id) {
    if (id == _activeDesktopTicketId) return;
    setState(() {
      _writeActiveDesktopDraft();
      final next = _findDesktopTicket(id);
      if (next == null) return;
      _activeDesktopTicketId = next.id;
      _replaceEditorStateFromDraft(next);
    });
    _schedulePersistEditorDraft();
    unawaited(_syncQuotationAi());
  }

  Future<void> _renameDesktopTicket(String id) async {
    final ticket = _findDesktopTicket(id);
    if (ticket == null) return;
    final controller = TextEditingController(text: ticket.title);
    final nextTitle = await showDialog<String>(
      context: context,
      barrierColor: FullTechDialogTokens.overlayColor,
      builder: (dialogContext) {
        return FullTechDialog(
          title: 'Editar ticket',
          maxWidth: 420,
          showCloseButton: true,
          onClose: () => Navigator.of(dialogContext).pop(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nombre del ticket',
                  border: OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: DialogSecondaryButton(
                      label: 'Cancelar',
                      onPressed: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DialogPrimaryButton(
                      label: 'Guardar',
                      onPressed: () =>
                          Navigator.of(dialogContext).pop(controller.text),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();

    final cleanTitle = (nextTitle ?? '').trim();
    if (cleanTitle.isEmpty) return;
    setState(() {
      _writeActiveDesktopDraft();
      final index = _desktopTickets.indexWhere((row) => row.id == id);
      if (index < 0) return;
      final current = _desktopTickets[index];
      _desktopTickets[index] = current.copyWith(title: cleanTitle);
      if (_activeDesktopTicketId == id) {
        _replaceEditorStateFromDraft(_desktopTickets[index]);
      }
    });
    _schedulePersistEditorDraft();
  }

  Future<void> _deleteDesktopTicket(String id) async {
    final ticket = _findDesktopTicket(id);
    if (ticket == null) return;
    final confirmed = await FullTechConfirmDialog.show(
      context,
      title: 'Eliminar ticket',
      message: _desktopTickets.length <= 1
          ? 'Este ticket será vaciado por completo.\n¿Desea continuar?'
          : 'El ticket "${ticket.title.trim().isEmpty ? 'Ticket' : ticket.title.trim()}" será eliminado.\n¿Desea continuar?',
      confirmText: 'Aceptar',
      cancelText: 'Cancelar',
      icon: Icons.delete_outline_rounded,
      iconColor: const Color(0xFFDC2626),
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;

    if (_desktopTickets.length <= 1) {
      _commitEditorChange(_resetEditorState);
      return;
    }

    setState(() {
      _writeActiveDesktopDraft();
      final index = _desktopTickets.indexWhere((ticket) => ticket.id == id);
      if (index < 0) return;
      final nextTickets = [..._desktopTickets]..removeAt(index);
      _desktopTickets = nextTickets;
      if (_activeDesktopTicketId == id) {
        final nextIndex = index.clamp(0, nextTickets.length - 1);
        final next = nextTickets[nextIndex];
        _activeDesktopTicketId = next.id;
        _replaceEditorStateFromDraft(next);
      }
    });
    _schedulePersistEditorDraft();
    unawaited(_syncQuotationAi());
  }

  String get _activeTicketLabel {
    final active = _findDesktopTicket(_activeDesktopTicketId);
    if (active == null) return 'Ticket';
    final index = _desktopTickets.indexWhere(
      (ticket) => ticket.id == active.id,
    );
    return active.label(index < 0 ? 0 : index);
  }

  void _publishDesktopShellFooter() {
    final signature = _desktopFooterSignature();
    if (_lastPublishedDesktopFooterSignature == signature) return;
    _lastPublishedDesktopFooterSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = GoRouterState.of(context).uri.toString();
      ref
          .read(desktopShellFooterContentProvider.notifier)
          .state = DesktopShellFooterContent(
        route: route,
        builder: (_) => _DesktopSalesTicketFooter(
          tickets: _desktopTickets,
          activeTicketId: _activeDesktopTicketId,
          onCreateTicket: _createNewDesktopTicket,
          onSwitchTicket: _switchDesktopTicket,
          onRenameTicket: (id) => unawaited(_renameDesktopTicket(id)),
          onDeleteTicket: (id) => unawaited(_deleteDesktopTicket(id)),
        ),
      );
    });
  }

  String _desktopFooterSignature() {
    final buffer = StringBuffer(_activeDesktopTicketId ?? '');
    for (final ticket in _desktopTickets) {
      final total = ticket.items.fold<double>(
        0,
        (sum, item) => sum + item.total,
      );
      buffer
        ..write('|')
        ..write(ticket.id)
        ..write(':')
        ..write(ticket.title)
        ..write(':')
        ..write(ticket.selectedClientName)
        ..write(':')
        ..write(ticket.items.length)
        ..write(':')
        ..write(total.toStringAsFixed(2));
    }
    return buffer.toString();
  }

  void _clearDesktopShellFooter() {
    try {
      final notifier = ref.read(desktopShellFooterContentProvider.notifier);
      final current = notifier.state;
      final currentRoute = current?.route ?? '';
      if (currentRoute == Routes.cotizaciones ||
          currentRoute.startsWith('${Routes.cotizaciones}?')) {
        notifier.state = null;
        _lastPublishedDesktopFooterSignature = null;
      }
    } catch (_) {
      // The provider may already be disposed while the app is closing.
    }
  }

  Future<void> _openMobileTicketSheet() async {
    await showGeneralDialog<void>(
      context: context,
      barrierLabel: 'Tickets abiertos',
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.24),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final theme = Theme.of(dialogContext);
        final media = MediaQuery.of(dialogContext);
        final panelWidth = media.size.width * 0.88 > 360
            ? 360.0
            : media.size.width * 0.88;

        return SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: panelWidth,
                height: media.size.height,
                margin: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 28,
                      offset: const Offset(-8, 12),
                    ),
                  ],
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.45,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Tickets abiertos',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Cambia de ticket o crea uno nuevo sin salir del editor.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.of(dialogContext).pop();
                            _createNewDesktopTicket();
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Nuevo ticket'),
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        itemCount: _desktopTickets.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (itemContext, index) {
                          final ticket = _desktopTickets[index];
                          final selected = ticket.id == _activeDesktopTicketId;
                          final lines = ticket.items.length;
                          final clientName = ticket.selectedClientName.trim();
                          final subtitle = [
                            '$lines líneas',
                            if (clientName.isNotEmpty &&
                                clientName != 'Sin cliente')
                              clientName,
                          ].join(' · ');

                          return Material(
                            color: selected
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.10,
                                  )
                                : theme.colorScheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(18),
                            child: InkWell(
                              onTap: () {
                                Navigator.of(dialogContext).pop();
                                _switchDesktopTicket(ticket.id);
                              },
                              borderRadius: BorderRadius.circular(18),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: selected
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.surface,
                                      child: Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w900,
                                          color: selected
                                              ? theme.colorScheme.onPrimary
                                              : theme.colorScheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            ticket.label(index),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodyLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            subtitle,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                  color: theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      selected
                                          ? Icons.check_circle_rounded
                                          : Icons.chevron_right_rounded,
                                      color: selected
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  Future<void> _handleMobileQuickAction(_MobileQuickAction action) async {
    switch (action) {
      case _MobileQuickAction.client:
        await _openClientDialog();
        return;
      case _MobileQuickAction.note:
        await _openNoteDialog();
        return;
      case _MobileQuickAction.externalItem:
        await _openExternalItemDialog();
        return;
      case _MobileQuickAction.tickets:
        await _openMobileTicketSheet();
        return;
      case _MobileQuickAction.newTicket:
        _createNewDesktopTicket();
        return;
      case _MobileQuickAction.pdf:
        await _openPdfPreview();
        return;
      case _MobileQuickAction.serviceOrder:
        await _sendQuotationToServiceOrder();
        return;
      case _MobileQuickAction.clear:
        if (!_hasEditorContent) return;
        await _confirmAndClearSale();
        return;
    }
  }

  Future<void> _sendQuotationToServiceOrder() async {
    if ((_selectedClientId ?? '').trim().isEmpty ||
        _selectedClientName.trim() == 'Sin cliente') {
      _showSalesNotice(
        title: 'Cliente requerido',
        message: 'Selecciona o crea un cliente primero.',
        icon: Icons.person_add_alt_1_outlined,
        accent: const Color(0xFFF59E0B),
      );
      return;
    }

    if ((_selectedClientPhone ?? '').trim().isEmpty) {
      _showSalesNotice(
        title: 'Teléfono requerido',
        message: 'El cliente debe tener teléfono para continuar.',
        icon: Icons.call_outlined,
        accent: const Color(0xFFF59E0B),
      );
      return;
    }

    if (_items.isEmpty) {
      _showSalesNotice(
        title: 'Ticket vacío',
        message: 'Agrega al menos un producto al ticket.',
        icon: Icons.shopping_cart_outlined,
        accent: const Color(0xFFF59E0B),
      );
      return;
    }

    final repository = ref.read(cotizacionesRepositoryProvider);
    final draft = _buildDraftCotizacion();
    final wasEditing = (_editingId ?? '').trim().isNotEmpty;

    CotizacionModel savedQuotation;
    try {
      savedQuotation = wasEditing
          ? await repository.update(_editingId!, draft)
          : await repository.create(draft);
    } catch (error) {
      if (!mounted) return;
      _showSalesNotice(
        title: 'No se pudo crear la orden',
        message: error is ApiException
            ? error.message
            : 'No se pudo preparar la cotización para crear la orden.',
        icon: Icons.error_outline_rounded,
        accent: const Color(0xFFDC2626),
      );
      return;
    }

    if (!mounted) return;

    _commitEditorChange(() {
      _editingId = savedQuotation.id;
      _editingCreatedAt = savedQuotation.createdAt;
      _selectedClientId = savedQuotation.customerId;
      _selectedClientName = savedQuotation.customerName;
      _selectedClientPhone = savedQuotation.customerPhone;
    });
    _schedulePersistEditorDraft(immediate: true);

    final opened = await openCreateServiceOrderAdaptive(
      context,
      args: ServiceOrderCreateArgs(
        initialQuotation: savedQuotation,
        initialClientId: savedQuotation.customerId,
      ),
    );

    if (!mounted) return;
    if (opened == true) {
      _showSalesNotice(
        title: 'Orden creada',
        message: 'Orden de servicio creada desde la cotización.',
        icon: Icons.assignment_turned_in_outlined,
        accent: const Color(0xFF1957E6),
      );
    }
  }

  Future<void> _saveCurrentAsQuotation() async {
    if (_items.isEmpty) {
      _showSalesNotice(
        title: 'Ticket vacío',
        message: 'Agrega al menos un producto al ticket.',
        icon: Icons.shopping_cart_outlined,
        accent: const Color(0xFFF59E0B),
      );
      return;
    }

    final repository = ref.read(cotizacionesRepositoryProvider);
    final baseDraft = _buildDraftCotizacion();
    final hasClient =
        baseDraft.customerName.trim().isNotEmpty &&
        baseDraft.customerName.trim() != 'Sin cliente';
    final draft = hasClient
        ? baseDraft
        : baseDraft.copyWith(customerName: 'Consumidor Final');
    final editingId = (_editingId ?? '').trim();

    try {
      final wasQueued = editingId.isNotEmpty && _isUuid(editingId)
          ? await repository.updateOrQueue(editingId, draft)
          : await repository.createOrQueue(draft.copyWith(id: ''));

      if (!mounted) return;
      _commitEditorChange(_resetEditorState);
      _schedulePersistEditorDraft(immediate: true);

      _showSalesNotice(
        title: 'Cotización guardada',
        message: wasQueued
            ? 'Guardada localmente y pendiente de sincronizar.'
            : 'La cotización se guardó correctamente.',
        icon: Icons.request_quote_outlined,
        accent: const Color(0xFF1957E6),
      );
    } catch (error) {
      if (!mounted) return;
      _showSalesNotice(
        title: 'No se pudo guardar',
        message: error is ApiException
            ? error.message
            : 'No se pudo guardar la cotización.',
        icon: Icons.error_outline_rounded,
        accent: const Color(0xFFDC2626),
      );
    }
  }

  Future<void> _syncQuotationAi({bool triggerAi = true}) {
    return ref
        .read(quotationAiControllerProvider.notifier)
        .setContext(_buildQuotationAiContext(), triggerAi: triggerAi);
  }

  QuotationContext _buildQuotationAiContext({String? noteOverride}) {
    final effectiveNote = (noteOverride ?? _note).trim();
    final totalQuantity = _items.fold<double>(0, (sum, item) => sum + item.qty);
    final productName = _items.length == 1
        ? _items.first.nombre
        : _items.isNotEmpty
        ? '${_items.length} productos seleccionados'
        : null;

    final contextItems = _items
        .map((item) {
          final official = _findOfficialProduct(item.productId);
          return QuotationContextItem(
            productId: item.productId,
            productName: item.nombre,
            category:
                official?.categoriaLabel ??
                _selectedCategory ??
                'Sin categoría',
            qty: item.qty,
            unitPrice: item.unitPrice,
            officialUnitPrice: official?.precio,
            lineTotal: item.total,
            notes: effectiveNote.isEmpty ? null : effectiveNote,
          );
        })
        .toList(growable: false);

    final normalPrice = contextItems.fold<double>(0, (sum, item) {
      return sum + ((item.officialUnitPrice ?? item.unitPrice) * item.qty);
    });

    return QuotationContext(
      quotationId: (_editingId ?? '').trim().isEmpty ? null : _editingId,
      module: 'cotizaciones',
      productType: _selectedCategory,
      productName: productName,
      brand: null,
      quantity: totalQuantity,
      installationType: _detectInstallationType(),
      selectedPriceType: _detectSelectedPriceType(contextItems),
      selectedUnitPrice: _items.length == 1 ? _items.first.unitPrice : null,
      selectedTotal: _total,
      minimumPrice: null,
      offerPrice: null,
      normalPrice: normalPrice,
      components: _items.map((item) => item.nombre).toList(growable: false),
      notes: effectiveNote.isEmpty ? null : effectiveNote,
      extraCharges: _detectExtraCharges(),
      currentDvrType: _detectCurrentDvrType(),
      requiredDvrType: _detectRequiredDvrType(totalQuantity: totalQuantity),
      screenName: 'Cotización',
      items: contextItems,
      metadata: {
        'clientId': _selectedClientId,
        'clientName': _selectedClientName,
        'clientPhone': _selectedClientPhone,
        'includeItbis': _includeItbis,
        'subtotal': _subtotal,
        'itbisAmount': _itbisAmount,
        'activeDesktopTicketId': _activeDesktopTicketId,
      },
    );
  }

  ProductModel? _findOfficialProduct(String productId) {
    for (final product in _productos) {
      if (product.id == productId) return product;
    }
    return null;
  }

  String? _detectInstallationType() {
    final text = _note.toLowerCase();
    if (text.contains('complej')) return 'compleja';
    if (text.contains('simple')) return 'simple';
    return null;
  }

  String? _detectSelectedPriceType(List<QuotationContextItem> items) {
    if (items.isEmpty) return null;
    var hasDiscount = false;
    var hasIncrease = false;
    for (final item in items) {
      final official = item.officialUnitPrice;
      if (official == null) continue;
      if (item.unitPrice < official) hasDiscount = true;
      if (item.unitPrice > official) hasIncrease = true;
    }
    if (hasDiscount && !hasIncrease) return 'descuento';
    if (hasIncrease && !hasDiscount) return 'ajuste';
    if (!hasDiscount && !hasIncrease) return 'normal';
    return 'mixto';
  }

  List<String> _detectExtraCharges() {
    final charges = <String>[];
    for (final item in _items) {
      final text = item.nombre.toLowerCase();
      if (text.contains('instal') ||
          text.contains('recargo') ||
          text.contains('cargo')) {
        charges.add(item.nombre);
      }
    }
    return charges;
  }

  String? _detectCurrentDvrType() {
    final text = _items.map((item) => item.nombre).join(' ');
    final match = RegExp(
      r'(\d{1,2})\s*(canales|canal)',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    return '${match.group(1)} canales';
  }

  String? _detectRequiredDvrType({required double totalQuantity}) {
    final totalCameras = _items
        .where((item) => item.nombre.toLowerCase().contains('camara'))
        .fold<double>(0, (sum, item) => sum + item.qty);
    if (totalCameras <= 0) return null;
    if (totalCameras <= 4) return '4 canales';
    if (totalCameras <= 8) return '8 canales';
    if (totalCameras <= 16) return '16 canales';
    if (totalQuantity > 16) return '32 canales';
    return null;
  }

  Future<void> _openAiAssistantSheet({String? initialPrompt}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiChatSheet(initialPrompt: initialPrompt),
    );
  }

  Future<void> _openAiRelatedRule(String? ruleId, String? title) {
    return openQuotationRuleDetailSheet(
      context,
      ref,
      ruleId: ruleId,
      title: title,
    );
  }

  Future<void> _askAiAboutWarning(AiWarning warning) {
    return _openAiAssistantSheet(
      initialPrompt:
          'Explícame la advertencia "${warning.title}" usando únicamente la regla oficial relacionada.',
    );
  }

  Future<void> _applyGeneralDiscount() async {
    if (_items.isEmpty || _grossTotalBeforeGeneralDiscount <= 0) return;
    var type = _DiscountType.fixed;
    final amountCtrl = TextEditingController(
      text: _effectiveGeneralDiscountAmount > 0
          ? _formatAccountingInput(_effectiveGeneralDiscountAmount)
          : '',
    );

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            void apply() {
              final amount = type == _DiscountType.percent
                  ? double.tryParse(amountCtrl.text.trim().replaceAll(',', '.'))
                  : _parseAccountingInput(amountCtrl.text);
              if (amount == null || amount <= 0) {
                _showSalesNotice(
                  title: 'Valor inválido',
                  message: 'Ingresa un valor válido.',
                  icon: Icons.warning_amber_rounded,
                  accent: const Color(0xFFF59E0B),
                );
                return;
              }
              final nextDiscount = type == _DiscountType.percent
                  ? _grossTotalBeforeGeneralDiscount * (amount / 100)
                  : amount;
              final boundedDiscount = nextDiscount
                  .clamp(0, _grossTotalBeforeGeneralDiscount)
                  .toDouble();
              _commitEditorChange(() {
                _generalDiscountAmount = boundedDiscount;
              });
              Navigator.pop(dialogContext);
            }

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Descuento general',
                              style: TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Aplica una rebaja al total completo de la venta.',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      SegmentedButton<_DiscountType>(
                        segments: const [
                          ButtonSegment(
                            value: _DiscountType.fixed,
                            label: Text(r'RD$'),
                          ),
                          ButtonSegment(
                            value: _DiscountType.percent,
                            label: Text('%'),
                          ),
                        ],
                        selected: {type},
                        onSelectionChanged: (value) =>
                            setDialogState(() => type = value.first),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: amountCtrl,
                        autofocus: true,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => apply(),
                        decoration: InputDecoration(
                          labelText: type == _DiscountType.fixed
                              ? 'Monto de descuento'
                              : 'Porcentaje de descuento',
                          prefixText: type == _DiscountType.fixed
                              ? r'RD$ '
                              : null,
                          suffixText: type == _DiscountType.percent
                              ? '%'
                              : null,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          if (_effectiveGeneralDiscountAmount > 0)
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  _commitEditorChange(() {
                                    _generalDiscountAmount = 0;
                                  });
                                  Navigator.pop(dialogContext);
                                },
                                icon: const Icon(Icons.undo_rounded, size: 18),
                                label: const Text('Quitar'),
                              ),
                            ),
                          if (_effectiveGeneralDiscountAmount > 0)
                            const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: apply,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF1957E6),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(46),
                              ),
                              child: const Text('Aplicar descuento'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    } finally {
      await _disposeControllersSafely([amountCtrl]);
    }
  }

  void _addProduct(ProductModel product) {
    final index = _items.indexWhere((item) => item.productId == product.id);
    final nextQty = index >= 0 ? _items[index].qty + 1 : 1.0;
    final stock = product.stock;
    if (stock != null && nextQty > stock) {
      _showSalesNotice(
        title: stock <= 0 ? 'Producto sin stock' : 'Stock insuficiente',
        message:
            '${product.nombre} se agregará al detalle marcado como fuera de stock.',
        icon: Icons.warning_amber_rounded,
        accent: const Color(0xFFF59E0B),
      );
    }
    _commitEditorChange(() {
      if (index >= 0) {
        final current = _items[index];
        _items[index] = current.copyWith(qty: current.qty + 1);
      } else {
        _items.add(
          CotizacionItem(
            productId: product.id,
            nombre: product.nombre,
            imageUrl: product.displayFotoUrl,
            originalUnitPrice: product.precio,
            unitPrice: product.precio,
            qty: 1,
            costUnit: product.costo,
          ),
        );
      }
    });
  }

  Future<void> _openExternalItemDialog({int? editIndex}) async {
    final isDesktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;
    if (isDesktop) {
      setState(() {
        _showDesktopManualItemForm = true;
        _desktopManualEditIndex = editIndex;
      });
      return;
    }

    final editingItem =
        editIndex != null &&
            editIndex >= 0 &&
            editIndex < _items.length &&
            _items[editIndex].isExternal
        ? _items[editIndex]
        : null;
    final nameCtrl = TextEditingController(text: editingItem?.nombre ?? '');
    final qtyCtrl = TextEditingController(
      text: editingItem == null
          ? '1'
          : (editingItem.qty % 1 == 0
                ? editingItem.qty.toStringAsFixed(0)
                : editingItem.qty.toStringAsFixed(2)),
    );
    final costCtrl = TextEditingController(
      text: editingItem?.externalCostUnit == null
          ? ''
          : _formatAccountingInput(editingItem!.externalCostUnit!),
    );
    final priceCtrl = TextEditingController(
      text: editingItem == null
          ? ''
          : _formatAccountingInput(editingItem.unitPrice),
    );
    final isAdmin = ref.read(authStateProvider).user?.appRole == AppRole.admin;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          InputDecoration decoration(String label, {String? hint}) {
            return InputDecoration(
              labelText: label,
              hintText: hint,
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 13,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: Color(0xFF0F766E),
                  width: 1.4,
                ),
              ),
            );
          }

          final qty = _parseAccountingInput(qtyCtrl.text) ?? 0;
          final cost = _parseAccountingInput(costCtrl.text) ?? 0;
          final price = _parseAccountingInput(priceCtrl.text) ?? 0;
          final total = qty * price;
          final profit = qty * (price - cost);

          return Dialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2FE),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.add_shopping_cart_outlined,
                            color: Color(0xFF075985),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                editingItem == null
                                    ? 'Producto fuera de inventario'
                                    : 'Editar producto manual',
                                style: Theme.of(dialogContext)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF0F172A),
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Agrega un servicio o producto puntual a esta venta.',
                                style: Theme.of(dialogContext)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: const Color(0xFF64748B),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: nameCtrl,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) =>
                          FocusScope.of(dialogContext).nextFocus(),
                      decoration: decoration('Nombre producto o servicio'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: qtyCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setDialogState(() {}),
                            onSubmitted: (_) =>
                                FocusScope.of(dialogContext).nextFocus(),
                            decoration: decoration('Cantidad'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: costCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textInputAction: TextInputAction.next,
                            onChanged: (_) => setDialogState(() {}),
                            onSubmitted: (_) =>
                                FocusScope.of(dialogContext).nextFocus(),
                            decoration: decoration('Costo unitario'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setDialogState(() {}),
                      onSubmitted: (_) => Navigator.pop(dialogContext, true),
                      decoration: decoration('Precio unitario'),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _ManualItemMetric(
                              label: 'Total',
                              value: _money(total),
                            ),
                          ),
                          if (isAdmin) ...[
                            Container(
                              width: 1,
                              height: 30,
                              color: const Color(0xFFE2E8F0),
                            ),
                            Expanded(
                              child: _ManualItemMetric(
                                label: 'Utilidad',
                                value: _money(profit),
                                alignEnd: true,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0F766E),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 22,
                              vertical: 13,
                            ),
                          ),
                          child: Text(
                            editingItem == null ? 'Agregar' : 'Guardar',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    final name = nameCtrl.text.trim();
    final qty = _parseAccountingInput(qtyCtrl.text) ?? 0;
    final externalCost = costCtrl.text.trim().isEmpty
        ? null
        : _parseAccountingInput(costCtrl.text);
    final unitPrice = _parseAccountingInput(priceCtrl.text) ?? -1;

    await _disposeControllersSafely([nameCtrl, qtyCtrl, costCtrl, priceCtrl]);

    if (ok != true) return;

    if (!_validateExternalItemInput(
      name: name,
      qty: qty,
      unitPrice: unitPrice,
      externalCost: externalCost,
    )) {
      if (!mounted) return;
      _showExternalItemInputNotice();
      return;
    }

    _commitExternalItem(
      name: name,
      qty: qty,
      unitPrice: unitPrice,
      externalCost: externalCost,
      editIndex: editIndex,
    );
  }

  bool _validateExternalItemInput({
    required String name,
    required double qty,
    required double unitPrice,
    required double? externalCost,
  }) {
    return name.isNotEmpty &&
        qty > 0 &&
        unitPrice >= 0 &&
        (externalCost ?? 0) >= 0;
  }

  void _showExternalItemInputNotice() {
    _showSalesNotice(
      title: 'Datos incompletos',
      message:
          'Completa datos válidos: nombre, cantidad mayor que 0, costo y precio no negativos.',
      icon: Icons.warning_amber_rounded,
      accent: const Color(0xFFF59E0B),
    );
  }

  void _commitExternalItem({
    required String name,
    required double qty,
    required double unitPrice,
    required double? externalCost,
    int? editIndex,
  }) {
    final editingItem =
        editIndex != null &&
            editIndex >= 0 &&
            editIndex < _items.length &&
            _items[editIndex].isExternal
        ? _items[editIndex]
        : null;

    _commitEditorChange(() {
      final next = CotizacionItem(
        productId: '',
        nombre: name,
        imageUrl: null,
        originalUnitPrice: editingItem?.originalUnitPrice ?? unitPrice,
        unitPrice: unitPrice,
        qty: qty,
        externalCostUnit: externalCost,
      );
      if (editingItem != null && editIndex != null) {
        _items[editIndex] = next;
      } else {
        _items.add(next);
      }
      _showDesktopManualItemForm = false;
      _desktopManualEditIndex = null;
    });
  }

  void _setQty(int index, double qty) {
    if (qty <= 0) {
      _commitEditorChange(() => _items.removeAt(index));
      return;
    }
    _commitEditorChange(() => _items[index] = _items[index].copyWith(qty: qty));
  }

  void _setUnitPrice(int index, double price) {
    if (price < 0) return;
    _commitEditorChange(() {
      final current = _items[index];
      _items[index] = current.copyWith(
        originalUnitPrice: _nextOriginalUnitPrice(current, price),
        unitPrice: price,
      );
    });
  }

  double? _nextOriginalUnitPrice(CotizacionItem item, double nextUnitPrice) {
    final currentBase = item.originalUnitPrice;
    if (currentBase != null) return currentBase;
    if (nextUnitPrice < item.unitPrice) return item.unitPrice;
    return null;
  }

  Future<void> _openLineEditor(int index) async {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    final result = await showDialog<_LineEditResult>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.18),
      builder: (dialogContext) => _LineEditDialog(
        item: item,
        money: _money,
        parseAmount: _parseAccountingInput,
        formatAmount: _formatAccountingInput,
      ),
    );
    if (result == null || !mounted) return;
    _commitEditorChange(() {
      if (index < 0 || index >= _items.length) return;
      final current = _items[index];
      final base = current.effectiveOriginalUnitPrice;
      final discountAmount = result.discountMode == _LineDiscountMode.percent
          ? base * (result.discountValue / 100)
          : result.discountValue;
      final nextPrice = (base - discountAmount)
          .clamp(0.0, double.infinity)
          .toDouble();
      _items[index] = current.copyWith(
        qty: result.qty,
        originalUnitPrice: current.originalUnitPrice ?? base,
        unitPrice: nextPrice,
      );
    });
  }

  Future<void> _pickCategory() async {
    final selected = await showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final categories = _categories;
        final options = <String?>[null, ...categories];
        final theme = Theme.of(context);

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.70,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Categorias',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (_selectedCategory != null)
                          TextButton(
                            onPressed: () => Navigator.pop(context, null),
                            child: const Text('Quitar filtro'),
                          ),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      shrinkWrap: true,
                      itemCount: options.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final category = options[index];
                        final selectedOption = _selectedCategory == category;
                        final label = category ?? 'Todas las categorias';

                        return Material(
                          color: selectedOption
                              ? theme.colorScheme.primary.withValues(
                                  alpha: 0.10,
                                )
                              : theme.colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            onTap: () => Navigator.pop(context, category),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 24,
                                    height: 24,
                                    decoration: BoxDecoration(
                                      color: selectedOption
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.surface,
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: selectedOption
                                            ? theme.colorScheme.primary
                                            : theme.colorScheme.outlineVariant,
                                      ),
                                    ),
                                    child: Icon(
                                      selectedOption
                                          ? Icons.check_rounded
                                          : Icons.circle_outlined,
                                      size: 14,
                                      color: selectedOption
                                          ? theme.colorScheme.onPrimary
                                          : theme.colorScheme.outline,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: selectedOption
                                                ? FontWeight.w800
                                                : FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) return;
    if (selected == _selectedCategory) return;
    _commitEditorChange(() => _selectedCategory = selected);
  }

  Future<void> _openNoteDialog() async {
    final controller = TextEditingController(text: _note);
    bool applyingAi = false;

    Future<void> requestAiSuggestion(
      BuildContext dialogContext,
      void Function(VoidCallback) setDialogState,
    ) async {
      final rawNote = controller.text.trim();
      if (rawNote.isEmpty) {
        _showSalesNotice(
          title: 'Nota requerida',
          message: 'Escribe una nota antes de usar IA.',
          icon: Icons.sticky_note_2_outlined,
          accent: const Color(0xFFF59E0B),
        );
        return;
      }

      setDialogState(() => applyingAi = true);
      try {
        final suggestion = await _buildAiNoteSuggestions(rawNote);
        if (!dialogContext.mounted) return;
        final selected = await _openAiNoteChoiceDialog(
          original: rawNote,
          suggestion: suggestion,
        );
        if (!dialogContext.mounted || selected == null) return;
        controller.text = selected;
        controller.selection = TextSelection.fromPosition(
          TextPosition(offset: controller.text.length),
        );
      } finally {
        if (dialogContext.mounted) {
          setDialogState(() => applyingAi = false);
        }
      }
    }

    String? nextNote;
    try {
      nextNote = await showDialog<String>(
        context: context,
        barrierColor: FullTechDialogTokens.overlayColor,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => FullTechDialog(
            title: 'Nota de cotización',
            maxWidth: 420,
            showCloseButton: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: controller,
                  minLines: 4,
                  maxLines: 5,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: 'Escribe una nota para esta cotización',
                    filled: true,
                    fillColor: const Color(0xFFF8FBFF),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFCFE0FF)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFD3E0E7)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFF0E7490),
                        width: 1.2,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => Navigator.pop(
                    dialogContext,
                    _autocorrectNoteText(controller.text),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: applyingAi
                      ? null
                      : () =>
                            requestAiSuggestion(dialogContext, setDialogState),
                  icon: applyingAi
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_fix_high_rounded),
                  label: Text(
                    applyingAi ? 'Mejorando texto...' : 'Mejorar con IA',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0E7490),
                    side: const BorderSide(color: Color(0xFF0E7490)),
                    minimumSize: const Size.fromHeight(34),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: applyingAi
                          ? null
                          : () => Navigator.pop(dialogContext),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: applyingAi
                          ? null
                          : () => Navigator.pop(
                              dialogContext,
                              _autocorrectNoteText(controller.text),
                            ),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0E7490),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } finally {
      await _disposeControllersSafely([controller]);
    }

    if (nextNote == null || !mounted) return;
    _commitEditorChange(() => _note = _autocorrectNoteText(nextNote!));
  }

  Future<_AiNoteSuggestion> _buildAiNoteSuggestions(String rawNote) async {
    final aiService = ref.read(quotationAiServiceProvider);
    try {
      final response = await aiService.sendMessage(
        context: _buildQuotationAiContext(noteOverride: rawNote),
        message:
            'Mejora esta nota de cotizacion para cliente. Corrige ortografia y redaccion sin inventar datos. '
            'Devuelve SOLO JSON valido con esta estructura exacta: '
            '{"corrected":"texto corregido","professional":"texto profesional"}. '
            'Nota: $rawNote',
      );
      final parsed = _parseAiNoteSuggestion(response.content);
      if (parsed != null) {
        return parsed;
      }
    } catch (_) {
      // Si falla IA (API exception), usamos sugerencia local para no bloquear al usuario.
    }
    return _buildLocalAiNoteSuggestion(rawNote);
  }

  _AiNoteSuggestion _buildLocalAiNoteSuggestion(String rawNote) {
    final corrected = _autocorrectNoteText(rawNote);
    return _AiNoteSuggestion(
      corrected: corrected,
      professional: _buildProfessionalNoteText(corrected),
    );
  }

  String _autocorrectNoteText(String input) {
    var text = input.trim();
    if (text.isEmpty) return text;

    const typoFixes = <String, String>{
      'porfavor': 'por favor',
      'insteligencia': 'inteligencia',
      'profeiconal': 'profesional',
      'camara': 'cámara',
      'camaras': 'cámaras',
    };

    typoFixes.forEach((wrong, right) {
      text = text.replaceAll(
        RegExp('\\b${RegExp.escape(wrong)}\\b', caseSensitive: false),
        right,
      );
    });

    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

    final punctuation = RegExp(r'([.,;:!?])([^\s])');
    text = text.replaceAllMapped(
      punctuation,
      (match) => '${match.group(1)} ${match.group(2)}',
    );

    if (!RegExp(r'[.!?]$').hasMatch(text)) {
      text = '$text.';
    }

    final first = text[0].toUpperCase();
    return '$first${text.substring(1)}';
  }

  String _buildProfessionalNoteText(String correctedText) {
    final core = correctedText.trim();
    if (core.isEmpty) return core;
    return 'Estimado cliente, favor tomar en cuenta que este presupuesto corresponde a los trabajos descritos. $core';
  }

  _AiNoteSuggestion? _parseAiNoteSuggestion(String content) {
    final jsonText = _extractJsonObject(content);
    if (jsonText == null) return null;
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) return null;
      final corrected = (decoded['corrected'] ?? '').toString().trim();
      final professional = (decoded['professional'] ?? '').toString().trim();
      if (corrected.isEmpty || professional.isEmpty) return null;
      return _AiNoteSuggestion(
        corrected: corrected,
        professional: professional,
      );
    } catch (_) {
      return null;
    }
  }

  String? _extractJsonObject(String content) {
    final normalized = content.trim();
    if (normalized.isEmpty) return null;

    final fenced = RegExp(
      r'```(?:json)?\s*(\{[\s\S]*\})\s*```',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (fenced != null) {
      return fenced.group(1)?.trim();
    }

    final start = normalized.indexOf('{');
    final end = normalized.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return normalized.substring(start, end + 1).trim();
  }

  Future<String?> _openAiNoteChoiceDialog({
    required String original,
    required _AiNoteSuggestion suggestion,
  }) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Elige la nota sugerida'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAiNotePreviewBlock(label: 'Original', value: original),
                _buildAiNotePreviewBlock(
                  label: 'Corregida por IA',
                  value: suggestion.corrected,
                ),
                _buildAiNotePreviewBlock(
                  label: 'Profesional por IA',
                  value: suggestion.professional,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext, suggestion.corrected),
            child: const Text('Usar corregida'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, suggestion.professional),
            child: const Text('Usar profesional'),
          ),
        ],
      ),
    );
  }

  Widget _buildAiNotePreviewBlock({
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }

  Future<void> _openClientDialog() async {
    final screenContext = context;
    final repo = ref.read(ventasRepositoryProvider);
    final currentUserId = (ref.read(authStateProvider).user?.id ?? '').trim();
    final searchCtrl = TextEditingController();

    List<ClienteModel> clients = const [];
    Timer? searchDebounce;
    int requestId = 0;
    bool loading = true;
    bool dialogOpen = true;
    bool initialLoadQueued = false;
    String? error;
    var ownerFilter = _ClientOwnerFilter.all;
    var ageFilter = _ClientAgeFilter.all;

    List<ClienteModel> applyClientFilters(List<ClienteModel> rows) {
      final now = DateTime.now();
      final newSince = now.subtract(const Duration(days: 30));
      return rows
          .where((client) {
            final ownerId = client.ownerId.trim();
            final createdAt = client.createdAt;

            final matchesOwner = switch (ownerFilter) {
              _ClientOwnerFilter.all => true,
              _ClientOwnerFilter.mine =>
                currentUserId.isNotEmpty && ownerId == currentUserId,
              _ClientOwnerFilter.others =>
                currentUserId.isEmpty
                    ? ownerId.isNotEmpty
                    : ownerId != currentUserId,
            };

            final matchesAge = switch (ageFilter) {
              _ClientAgeFilter.all => true,
              _ClientAgeFilter.newer =>
                createdAt != null && !createdAt.toLocal().isBefore(newSince),
              _ClientAgeFilter.older =>
                createdAt == null || createdAt.toLocal().isBefore(newSince),
            };

            return matchesOwner && matchesAge;
          })
          .toList(growable: false);
    }

    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Seleccionar cliente',
        barrierColor: Colors.black.withValues(alpha: 0.22),
        transitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          final size = MediaQuery.sizeOf(dialogContext);
          final isDesktop = size.width >= _desktopBreakpoint;
          final panelWidth = size.width >= 1600
              ? 560.0
              : size.width >= 1280
              ? 520.0
              : (size.width * 0.42).clamp(440.0, 540.0);

          return StatefulBuilder(
            builder: (context, setStateDialog) {
              Future<void> openFilterSheet() async {
                final selected =
                    await showModalBottomSheet<_ClientFilterSelection>(
                      context: context,
                      backgroundColor: Colors.transparent,
                      builder: (sheetContext) {
                        final theme = Theme.of(sheetContext);
                        final ownerOptions = _ClientOwnerFilter.values;
                        final ageOptions = _ClientAgeFilter.values;

                        Widget buildOptionTile({
                          required bool selected,
                          required String label,
                          required VoidCallback onTap,
                        }) {
                          return Material(
                            color: selected
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.10,
                                  )
                                : theme.colorScheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              onTap: onTap,
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? theme.colorScheme.primary
                                            : theme.colorScheme.surface,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        border: Border.all(
                                          color: selected
                                              ? theme.colorScheme.primary
                                              : theme
                                                    .colorScheme
                                                    .outlineVariant,
                                        ),
                                      ),
                                      child: Icon(
                                        selected
                                            ? Icons.check_rounded
                                            : Icons.circle_outlined,
                                        size: 13,
                                        color: selected
                                            ? theme.colorScheme.onPrimary
                                            : theme.colorScheme.outline,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                              fontWeight: selected
                                                  ? FontWeight.w800
                                                  : FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        return SafeArea(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                            child: Container(
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.10),
                                    blurRadius: 24,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  12,
                                  14,
                                  14,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Center(
                                      child: Container(
                                        width: 40,
                                        height: 4,
                                        decoration: BoxDecoration(
                                          color:
                                              theme.colorScheme.outlineVariant,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 14),
                                    Text(
                                      'Filtrar clientes',
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Usuario',
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    ...ownerOptions.map(
                                      (option) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 6,
                                        ),
                                        child: buildOptionTile(
                                          selected: ownerFilter == option,
                                          label: option.label,
                                          onTap: () => Navigator.pop(
                                            sheetContext,
                                            _ClientFilterSelection(
                                              ownerFilter: option,
                                              ageFilter: ageFilter,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Antiguedad',
                                      style: theme.textTheme.labelLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    ...ageOptions.map(
                                      (option) => Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 6,
                                        ),
                                        child: buildOptionTile(
                                          selected: ageFilter == option,
                                          label: option.label,
                                          onTap: () => Navigator.pop(
                                            sheetContext,
                                            _ClientFilterSelection(
                                              ownerFilter: ownerFilter,
                                              ageFilter: option,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );

                if (selected == null) return;
                setStateDialog(() {
                  ownerFilter = selected.ownerFilter;
                  ageFilter = selected.ageFilter;
                });
              }

              Future<void> loadClients() async {
                final currentRequest = ++requestId;
                setStateDialog(() {
                  loading = true;
                  error = null;
                });
                try {
                  final rows = await repo.searchClients(searchCtrl.text.trim());
                  if (!mounted || !dialogOpen) return;
                  if (currentRequest != requestId) return;
                  setStateDialog(() {
                    clients = rows;
                    loading = false;
                  });
                } catch (e) {
                  if (!mounted || !dialogOpen) return;
                  if (currentRequest != requestId) return;
                  setStateDialog(() {
                    loading = false;
                    error = '$e';
                  });
                }
              }

              void scheduleLoadClients() {
                searchDebounce?.cancel();
                searchDebounce = Timer(
                  const Duration(milliseconds: 220),
                  loadClients,
                );
              }

              void openClientDetail(ClienteModel client) {
                Navigator.pop(context);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted || !screenContext.mounted) return;
                  screenContext.go(Routes.clienteDetail(client.id));
                });
              }

              if (!initialLoadQueued &&
                  loading &&
                  clients.isEmpty &&
                  error == null) {
                initialLoadQueued = true;
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => loadClients(),
                );
              }

              final filteredClients = applyClientFilters(clients);
              final hasActiveFilters =
                  ownerFilter != _ClientOwnerFilter.all ||
                  ageFilter != _ClientAgeFilter.all;

              final content = Column(
                mainAxisSize: isDesktop ? MainAxisSize.max : MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchCtrl,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Buscar cliente',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: searchCtrl.text.trim().isNotEmpty
                                ? IconButton(
                                    onPressed: () {
                                      searchCtrl.clear();
                                      scheduleLoadClients();
                                      setStateDialog(() {});
                                    },
                                    icon: const Icon(Icons.close),
                                  )
                                : null,
                            isDense: true,
                          ),
                          onChanged: (_) {
                            setStateDialog(() {});
                            scheduleLoadClients();
                          },
                          onSubmitted: (_) {
                            unawaited(loadClients());
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: openFilterSheet,
                        tooltip: 'Filtrar clientes',
                        icon: Icon(
                          hasActiveFilters
                              ? Icons.filter_alt
                              : Icons.filter_alt_outlined,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: () async {
                          final created = await openClienteFormAdaptive(
                            context,
                            useRootNavigator: true,
                          );
                          if (!mounted ||
                              !dialogOpen ||
                              !context.mounted ||
                              created == null) {
                            return;
                          }
                          _commitEditorChange(() {
                            _selectedClientId = created.id;
                            _selectedClientName = created.nombre;
                            _selectedClientPhone = created.telefono;
                          });
                          Navigator.pop(context);
                        },
                        tooltip: 'Agregar cliente',
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (hasActiveFilters)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (ownerFilter != _ClientOwnerFilter.all)
                            _ClientFilterChip(label: ownerFilter.label),
                          if (ageFilter != _ClientAgeFilter.all)
                            _ClientFilterChip(label: ageFilter.label),
                        ],
                      ),
                    ),
                  if (hasActiveFilters) const SizedBox(height: 8),
                  if (loading)
                    const LinearProgressIndicator()
                  else if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    )
                  else if (isDesktop)
                    Expanded(
                      child: filteredClients.isEmpty
                          ? Center(
                              child: Text(
                                clients.isEmpty
                                    ? 'No hay clientes, crea uno nuevo'
                                    : 'No hay clientes con este filtro',
                              ),
                            )
                          : ListView.separated(
                              itemCount: filteredClients.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final client = filteredClients[index];
                                final createdAt = client.createdAt?.toLocal();
                                final createdLabel = createdAt == null
                                    ? null
                                    : DateFormat(
                                        'dd/MM/yyyy',
                                      ).format(createdAt);
                                return ListTile(
                                  dense: true,
                                  title: Text(client.nombre),
                                  subtitle: Text(
                                    [
                                      client.telefono,
                                      if (createdLabel != null)
                                        'Creado $createdLabel',
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () {
                                    _commitEditorChange(() {
                                      _selectedClientId = client.id;
                                      _selectedClientName = client.nombre;
                                      _selectedClientPhone = client.telefono;
                                    });
                                    Navigator.pop(context);
                                  },
                                  trailing: TextButton.icon(
                                    onPressed: () => openClientDetail(client),
                                    icon: const Icon(
                                      Icons.open_in_new_rounded,
                                      size: 16,
                                    ),
                                    label: const Text('Ver'),
                                  ),
                                );
                              },
                            ),
                    )
                  else
                    SizedBox(
                      height: 320,
                      child: filteredClients.isEmpty
                          ? Center(
                              child: Text(
                                clients.isEmpty
                                    ? 'No hay clientes, crea uno nuevo'
                                    : 'No hay clientes con este filtro',
                              ),
                            )
                          : ListView.separated(
                              itemCount: filteredClients.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final client = filteredClients[index];
                                final createdAt = client.createdAt?.toLocal();
                                final createdLabel = createdAt == null
                                    ? null
                                    : DateFormat(
                                        'dd/MM/yyyy',
                                      ).format(createdAt);
                                return ListTile(
                                  dense: true,
                                  title: Text(client.nombre),
                                  subtitle: Text(
                                    [
                                      client.telefono,
                                      if (createdLabel != null)
                                        'Creado $createdLabel',
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () {
                                    _commitEditorChange(() {
                                      _selectedClientId = client.id;
                                      _selectedClientName = client.nombre;
                                      _selectedClientPhone = client.telefono;
                                    });
                                    Navigator.pop(context);
                                  },
                                  trailing: IconButton(
                                    tooltip: 'Ver cliente',
                                    onPressed: () => openClientDetail(client),
                                    icon: const Icon(Icons.open_in_new_rounded),
                                  ),
                                );
                              },
                            ),
                    ),
                ],
              );

              final actions = [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cerrar'),
                ),
                if ((_selectedClientId ?? '').trim().isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final clientId = (_selectedClientId ?? '').trim();
                      if (clientId.isEmpty) return;
                      final updated = await openClienteFormAdaptive(
                        context,
                        clienteId: clientId,
                        useRootNavigator: true,
                      );
                      if (!mounted ||
                          !dialogOpen ||
                          !context.mounted ||
                          updated == null) {
                        return;
                      }
                      _commitEditorChange(() {
                        _selectedClientId = updated.id;
                        _selectedClientName = updated.nombre;
                        _selectedClientPhone = updated.telefono;
                      });
                      Navigator.pop(context);
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar actual'),
                  ),
              ];

              if (!isDesktop) {
                return AlertDialog(
                  title: const Text('Cliente'),
                  content: SizedBox(width: 560, child: content),
                  actions: actions,
                );
              }

              return Material(
                color: Colors.transparent,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: panelWidth,
                    height: size.height,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x260B2A3A),
                            blurRadius: 28,
                            offset: Offset(-10, 0),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                18,
                                16,
                                14,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEAF1FF),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.person_search_outlined,
                                      color: Color(0xFF1957E6),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Cliente',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w900,
                                              ),
                                        ),
                                        Text(
                                          'Busca, selecciona o crea un cliente',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: const Color(0xFF617383),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: content,
                              ),
                            ),
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                18,
                                12,
                                18,
                                16,
                              ),
                              child: Row(
                                children: [
                                  Expanded(child: actions.first),
                                  if (actions.length > 1) ...[
                                    const SizedBox(width: 10),
                                    Expanded(child: actions.last),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: Tween<double>(begin: 0, end: 1).animate(curved),
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.08, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );
    } finally {
      dialogOpen = false;
      searchDebounce?.cancel();
      await WidgetsBinding.instance.endOfFrame;
      searchCtrl.dispose();
    }
  }

  CotizacionModel _buildDraftCotizacion() {
    final user = ref.read(authStateProvider).user;
    return CotizacionModel(
      id: _editingId ?? _newId(),
      createdAt: _editingCreatedAt ?? DateTime.now(),
      createdByUserId: user?.id,
      createdByUserName: user?.nombreCompleto,
      customerId: _selectedClientId,
      customerName: _selectedClientName,
      customerPhone: _selectedClientPhone,
      note: _note,
      includeItbis: _includeItbis,
      itbisRate: _itbisRate,
      globalDiscountAmount: _effectiveGeneralDiscountAmount,
      items: [..._items],
    );
  }

  String _tinyCustomerPhoneHint(CotizacionModel cotizacion) {
    final phone = (cotizacion.customerPhone ?? '').trim();
    if (phone.isEmpty) return '';
    return 'Cliente: $phone';
  }

  String _formatWhatsAppSendError(ApiException error, {required bool toAdmin}) {
    final message = error.message.trim();
    final lower = message.toLowerCase();
    final target = toAdmin ? 'a administradores' : 'al cliente';

    if (lower.contains('error interno') ||
        (error.code != null && error.code! >= 500)) {
      return 'No se pudo enviar $target porque el proveedor de WhatsApp reportó un fallo interno temporal. Intenta nuevamente en unos minutos.';
    }

    if (lower.contains('timeout') || lower.contains('tardó')) {
      return 'No se pudo enviar $target porque el servicio de WhatsApp tardó demasiado en responder. Verifica tu conexión e intenta otra vez.';
    }

    if (lower.contains('instancia') ||
        lower.contains('api key') ||
        lower.contains('credenciales')) {
      return 'No se pudo enviar $target por un problema de conexión con la instancia de WhatsApp. Revisa que la sesión esté conectada e intenta nuevamente.';
    }

    if (lower.contains('pdf') && lower.contains('pes')) {
      return 'No se pudo enviar $target porque el PDF es demasiado pesado para WhatsApp. Reduce el tamaño del archivo e intenta de nuevo.';
    }

    return message.isNotEmpty
        ? message
        : 'No se pudo enviar $target por un error inesperado. Intenta nuevamente.';
  }

  Future<void> enviarPdfCotizacionAAdmin({
    required CotizacionModel cotizacion,
    Uint8List? pdfBytes,
  }) async {
    final company = await _getCompanySettingsForPdf();
    final bytes =
        pdfBytes ??
        await buildCotizacionPdf(cotizacion: cotizacion, company: company);
    final dateFmt = DateFormat('yyyyMMdd_HHmm');
    final fileName =
        'cotizacion_${dateFmt.format(cotizacion.createdAt)}_${cotizacion.id.substring(0, 6)}.pdf';

    await ref
        .read(cotizacionesRepositoryProvider)
        .sendWhatsAppQuotation(
          quotationId: cotizacion.id,
          destinationType: 'admin',
          pdfBytes: bytes,
          fileName: fileName,
          messageText: _buildAdminApprovalMessage(cotizacion),
        );
  }

  Future<void> enviarPdfCotizacionACliente({
    required CotizacionModel cotizacion,
    required Uint8List pdfBytes,
    required BuildContext launchContext,
  }) async {
    final phone = _normalizeWhatsAppLinkPhone(cotizacion.customerPhone);
    if (phone.isEmpty) {
      throw ApiException(
        'El cliente no tiene teléfono válido para abrir WhatsApp.',
      );
    }

    final pdfUrl = await ref
        .read(cotizacionesRepositoryProvider)
        .createPdfShareLink(
          quotationId: cotizacion.id,
          pdfBytes: pdfBytes,
          fileName: buildCotizacionPdfFileName(cotizacion),
        );

    final uri = Uri.https('wa.me', '/$phone', {
      'text': _buildClientWhatsAppLinkMessage(cotizacion, pdfUrl),
    });

    if (!launchContext.mounted) return;
    await safeOpenWhatsApp(
      launchContext,
      uri,
      copiedMessage: 'No se pudo abrir WhatsApp. Enlace de cotización copiado.',
    );
  }

  String _buildAdminApprovalMessage(CotizacionModel cotizacion) {
    final sellerName = (cotizacion.createdByUserName ?? '').trim();
    final safeSellerName = sellerName.isEmpty ? 'El vendedor' : sellerName;
    return '$safeSellerName quiere que confirme esta cotización y que esté en orden.';
  }

  String _normalizeWhatsAppLinkPhone(String? value) {
    var digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '').trim();
    if (digits.length == 10 && digits.startsWith(RegExp(r'[268]'))) {
      digits = '1$digits';
    }
    if (digits.length == 11 && digits.startsWith('1')) return digits;
    if (digits.length >= 11 && digits.length <= 15) return digits;
    return '';
  }

  String _buildClientWhatsAppLinkMessage(
    CotizacionModel cotizacion,
    String pdfUrl,
  ) {
    final customerName = cotizacion.customerName.trim().isEmpty
        ? 'cliente'
        : cotizacion.customerName.trim();
    return 'Hola $customerName, te compartimos tu cotización/factura en PDF.\n'
        'Este documento corresponde a tu compra o solicitud en FULLTECH.\n'
        'Puedes abrir el enlace para ver o descargar tu PDF.\n'
        'Cotización: ${cotizacion.id}\n'
        'Total: ${_money(cotizacion.total)}\n'
        'PDF: $pdfUrl';
  }

  Future<CompanySettings> _getCompanySettingsForPdf() async {
    final repository = ref.read(companySettingsRepositoryProvider);
    try {
      return await repository.getSettings();
    } catch (error, stackTrace) {
      debugPrint(
        'CotizacionesScreen: usando respaldo de configuración para PDF: $error\n$stackTrace',
      );
      final cached = await repository.getCachedSettings();
      return cached ?? CompanySettings.empty();
    }
  }

  bool _isUuid(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return false;
    return RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(v);
  }

  Future<CotizacionModel> _ensurePersistedQuotationForSend(
    CotizacionModel draft,
  ) async {
    if (_isUuid(draft.id)) return draft;

    final repository = ref.read(cotizacionesRepositoryProvider);
    final saved = _isUuid(_editingId)
        ? await repository.update(_editingId!, draft)
        : await repository.create(draft);

    if (mounted) {
      _commitEditorChange(() {
        _editingId = saved.id;
        _editingCreatedAt = saved.createdAt;
        _selectedClientId = saved.customerId;
        _selectedClientName = saved.customerName;
        _selectedClientPhone = saved.customerPhone;
      });
      _schedulePersistEditorDraft(immediate: true);
    }

    return saved;
  }

  Future<void> _openPdfPreview() async {
    if (_items.isEmpty) {
      _showSalesNotice(
        title: 'Ticket vacío',
        message: 'Agrega productos para generar PDF.',
        icon: Icons.picture_as_pdf_outlined,
        accent: const Color(0xFFF59E0B),
      );
      return;
    }

    final cotizacion = _buildDraftCotizacion();
    final company = await _getCompanySettingsForPdf();
    final bytes = await buildCotizacionPdf(
      cotizacion: cotizacion,
      company: company,
    );

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        var sendingAdminApproval = false;
        var downloadingPdf = false;
        String? dialogNotification;
        bool dialogNotificationIsError = false;
        final media = MediaQuery.sizeOf(context);
        final compact = media.width < 560;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final busy = sendingAdminApproval || downloadingPdf;

            void showDialogNotification(
              String message, {
              bool isError = false,
            }) {
              if (!context.mounted) return;
              setDialogState(() {
                dialogNotification = message;
                dialogNotificationIsError = isError;
              });
            }

            Future<void> sendAdminApproval() async {
              setDialogState(() => sendingAdminApproval = true);
              try {
                showDialogNotification(
                  'Enviando cotización a administradores...',
                );
                final persisted = await _ensurePersistedQuotationForSend(
                  cotizacion,
                );
                await enviarPdfCotizacionAAdmin(
                  cotizacion: persisted,
                  pdfBytes: bytes,
                ).timeout(const Duration(seconds: 25));
                showDialogNotification(
                  'Cotización enviada a administradores correctamente.',
                );
              } on TimeoutException {
                showDialogNotification(
                  'Tiempo de espera agotado enviando a administradores.',
                  isError: true,
                );
              } on ApiException catch (e) {
                showDialogNotification(
                  _formatWhatsAppSendError(e, toAdmin: true),
                  isError: true,
                );
              } catch (e) {
                showDialogNotification(
                  'No se pudo enviar a administradores: $e',
                  isError: true,
                );
              } finally {
                if (context.mounted) {
                  setDialogState(() => sendingAdminApproval = false);
                }
              }
            }

            Future<void> downloadPdf() async {
              setDialogState(() => downloadingPdf = true);
              try {
                final saved = await saveCotizacionPdfToDownloads(
                  bytes: bytes,
                  cotizacion: cotizacion,
                );
                showDialogNotification(
                  saved
                      ? 'Cotización descargada en la carpeta Descargas.'
                      : 'No se pudo descargar la cotización.',
                  isError: !saved,
                );
              } catch (e) {
                showDialogNotification(
                  'No se pudo descargar la cotización: $e',
                  isError: true,
                );
              } finally {
                if (context.mounted) {
                  setDialogState(() => downloadingPdf = false);
                }
              }
            }

            Future<void> runShareAction(_QuotePdfShareAction action) async {
              if (!context.mounted) return;
              switch (action) {
                case _QuotePdfShareAction.sharePdf:
                  await shareCotizacionPdf(
                    bytes: bytes,
                    cotizacion: cotizacion,
                  );
                  break;
                case _QuotePdfShareAction.shareClient:
                  try {
                    showDialogNotification(
                      'Preparando enlace PDF para WhatsApp...',
                    );
                    final persisted = await _ensurePersistedQuotationForSend(
                      cotizacion,
                    );
                    if (!context.mounted) return;
                    await enviarPdfCotizacionACliente(
                      cotizacion: persisted,
                      pdfBytes: bytes,
                      launchContext: context,
                    ).timeout(const Duration(seconds: 25));
                    showDialogNotification(
                      'WhatsApp abierto con el enlace del PDF.',
                    );
                  } on TimeoutException {
                    showDialogNotification(
                      'Tiempo de espera agotado preparando el enlace del PDF.',
                      isError: true,
                    );
                  } on ApiException catch (e) {
                    showDialogNotification(
                      _formatWhatsAppSendError(e, toAdmin: false),
                      isError: true,
                    );
                  } catch (e) {
                    showDialogNotification(
                      'No se pudo enviar el PDF al cliente: $e',
                      isError: true,
                    );
                  }
                  break;
                case _QuotePdfShareAction.save:
                  await downloadPdf();
                  break;
                case _QuotePdfShareAction.admin:
                  await sendAdminApproval();
                  break;
              }
            }

            return Dialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              insetPadding: EdgeInsets.symmetric(
                horizontal: compact ? 6 : 20,
                vertical: compact ? 6 : 16,
              ),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: compact ? media.width - 12 : media.width * 0.94,
                height: compact ? media.height * 0.96 : media.height * 0.92,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 8, 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.picture_as_pdf_outlined),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'PDF de cotización',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              PopupMenuButton<_QuotePdfShareAction>(
                                enabled: !busy,
                                tooltip: 'Opciones para compartir',
                                position: PopupMenuPosition.under,
                                offset: const Offset(0, 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                onSelected: (action) =>
                                    unawaited(runShareAction(action)),
                                itemBuilder: (context) => [
                                  for (final action
                                      in _QuotePdfShareAction.values)
                                    PopupMenuItem<_QuotePdfShareAction>(
                                      value: action,
                                      child: Row(
                                        children: [
                                          Icon(
                                            action.icon,
                                            size: 18,
                                            color: const Color(0xFF0F7C92),
                                          ),
                                          const SizedBox(width: 10),
                                          Text(
                                            action.label,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      if (downloadingPdf)
                                        const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      else
                                        const Icon(Icons.ios_share_outlined),
                                      const SizedBox(width: 8),
                                      const Text('Compartir'),
                                    ],
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                          Builder(
                            builder: (context) {
                              final tinyPhoneHint = _tinyCustomerPhoneHint(
                                cotizacion,
                              );
                              if (tinyPhoneHint.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    tinyPhoneHint,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 9,
                                      height: 1,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.42),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    if (dialogNotification != null)
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: dialogNotificationIsError
                              ? const Color(0xFFFFEBEE)
                              : const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: dialogNotificationIsError
                                ? const Color(0xFFE57373)
                                : const Color(0xFF81C784),
                          ),
                        ),
                        child: Text(
                          dialogNotification!,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: dialogNotificationIsError
                                ? const Color(0xFFB71C1C)
                                : const Color(0xFF1B5E20),
                          ),
                        ),
                      ),
                    Expanded(
                      child: ColoredBox(
                        color: Colors.white,
                        child: PdfPreview(
                          canChangePageFormat: false,
                          canChangeOrientation: false,
                          canDebug: false,
                          allowPrinting: false,
                          allowSharing: false,
                          maxPageWidth: compact ? 700 : 980,
                          scrollViewDecoration: const BoxDecoration(
                            color: Colors.white,
                          ),
                          pdfPreviewPageDecoration: const BoxDecoration(
                            color: Colors.white,
                            boxShadow: <BoxShadow>[],
                          ),
                          build: (_) async => bytes,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<String> _inventoryCategories() {
    final categories = _productos
        .map((product) => product.categoriaLabel)
        .where((category) => category.trim().isNotEmpty)
        .toSet()
        .toList();
    categories.sort();
    return categories;
  }

  Future<void> _openInventoryCatalog() async {
    final result = await showInventoryProductEditor(
      context,
      categories: _inventoryCategories(),
    );
    if (!mounted || result?.saved != true) return;
    await _loadProducts(forceRemote: true);
    if (!mounted) return;
    _showSalesNotice(
      title: 'Producto creado',
      message: 'El producto se agregó al catálogo y ya está disponible aquí.',
      icon: Icons.check_circle_rounded,
      accent: const Color(0xFF059669),
    );
  }

  Future<void> _openStockAdjustments() async {
    if (_productos.isEmpty) {
      _showSalesNotice(
        title: 'Sin productos',
        message: 'Carga productos antes de ajustar stock.',
        icon: Icons.inventory_2_outlined,
        accent: const Color(0xFFF59E0B),
      );
      return;
    }

    await showInventoryStockAdjustmentsPanel(
      context,
      products: _productos,
      onRefresh: () => _loadProducts(forceRemote: true),
      onSetStock: (product, stock) async {
        await ref
            .read(catalogControllerProvider.notifier)
            .adjustStock(product: product, stock: stock);
        await _loadProducts(forceRemote: true);
      },
    );
    if (!mounted) return;
    await _loadProducts(forceRemote: true);
  }

  void _openSalesList() {
    context.go(Routes.ventasLista);
  }

  String _saleDateLabel(DateTime? date) {
    if (date == null) return 'Sin fecha';
    return DateFormat('dd/MM/yyyy HH:mm').format(date.toLocal());
  }

  String _saleShortId(SaleModel sale) {
    final id = sale.id.trim();
    if (id.length <= 8) return id;
    return '${id.substring(0, 8)}...';
  }

  String _formatQty(double value) {
    if (value == value.truncateToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  Future<void> _openRecentSalesPanel() async {
    final repo = ref.read(ventasRepositoryProvider);
    final now = DateTime.now();
    final from = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 30));
    final to = DateTime(now.year, now.month, now.day);

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Ventas recientes',
      barrierColor: Colors.black.withValues(alpha: 0.08),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: _RecentSalesPanel(
            loadSales: () =>
                repo.listInvoices(from: from, to: to, includeDeleted: true),
            money: _money,
            dateLabel: _saleDateLabel,
            shortId: _saleShortId,
            onViewSale: _showRecentSaleDetails,
            onOpenPdf: _openRecentSalePdf,
            onClose: () => Navigator.of(dialogContext).pop(),
            onOpenFullHistory: () {
              Navigator.of(dialogContext).pop();
              _openSalesList();
            },
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  Future<void> _openRecentSalePdf(SaleModel sale) async {
    final company = await _getCompanySettingsForPdf();
    final bytes = await buildSaleInvoicePdf(sale: sale, company: company);
    if (!mounted) return;
    final filename = 'factura_${_saleShortId(sale).replaceAll('...', '')}.pdf';

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: const Color(0x990B1720),
      builder: (dialogContext) {
        final media = MediaQuery.sizeOf(dialogContext);
        final compact = media.width < 720;
        return Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 28,
            vertical: compact ? 10 : 24,
          ),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(compact ? 8 : 12),
          ),
          child: SizedBox(
            width: compact ? media.width - 20 : 980,
            height: compact ? media.height - 20 : media.height * 0.88,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.picture_as_pdf_outlined,
                        color: Color(0xFF0F7C92),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'PDF factura · ${sale.customerName ?? 'Consumidor Final'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ),
                      PdfActionMenu(
                        bytes: bytes,
                        fileName: filename,
                        compact: compact,
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: PdfPreview(
                    canChangePageFormat: false,
                    canChangeOrientation: false,
                    canDebug: false,
                    allowPrinting: true,
                    allowSharing: false,
                    maxPageWidth: compact ? 640 : 900,
                    pdfFileName: filename,
                    build: (_) async => bytes,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRecentSaleDetails(SaleModel sale) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final returned = sale.isDeleted;
        return AlertDialog(
          title: Text('Factura ${_saleShortId(sale)}'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sale.customerName ?? 'Sin cliente',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(_saleDateLabel(sale.saleDate)),
                  const SizedBox(height: 10),
                  Chip(
                    label: Text(returned ? 'Devuelta' : 'Activa'),
                    backgroundColor:
                        (returned
                                ? const Color(0xFFB45309)
                                : const Color(0xFF1957E6))
                            .withValues(alpha: 0.10),
                  ),
                  const Divider(height: 20),
                  for (final item in sale.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item.productNameSnapshot} x${_formatQty(item.qty)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            _money(item.subtotalSold),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const Spacer(),
                      Text(
                        _money(sale.totalSold),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _openSalesList();
              },
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Abrir historial'),
            ),
          ],
        );
      },
    );
  }

  bool _validateCheckoutReady() {
    if (_selectedClientId == null || _selectedClientName == 'Sin cliente') {
      _showSalesNotice(
        title: 'Cliente requerido',
        message: 'Selecciona o crea un cliente primero.',
        icon: Icons.person_add_alt_1_outlined,
        accent: const Color(0xFFF59E0B),
      );
      return false;
    }

    if ((_selectedClientPhone ?? '').trim().isEmpty) {
      _showSalesNotice(
        title: 'Teléfono requerido',
        message: 'El cliente debe tener teléfono para continuar.',
        icon: Icons.call_outlined,
        accent: const Color(0xFFF59E0B),
      );
      return false;
    }

    if (_items.isEmpty) {
      _showSalesNotice(
        title: 'Ticket vacío',
        message: 'Agrega al menos un producto al ticket.',
        icon: Icons.shopping_cart_outlined,
        accent: const Color(0xFFF59E0B),
      );
      return false;
    }

    if (!_hasFiscalVoucherReady) {
      _showSalesNotice(
        title: 'Comprobante requerido',
        message:
            _fiscalVoucherValidationMessage ??
            'Completa el tipo, NCF, vencimiento y datos fiscales antes de cobrar con ITBIS.',
        icon: Icons.fact_check_outlined,
        accent: const Color(0xFFF59E0B),
      );
      return false;
    }

    return true;
  }

  String _checkoutPaymentLabel(_CheckoutPaymentMethod method) => method.label;

  Future<void> _openCheckoutDialog() async {
    if (!_validateCheckoutReady()) return;

    final cashState = await ref.read(cashRepositoryProvider).state();
    if (cashState.activeSession == null) {
      if (!mounted) return;
      _showSalesNotice(
        title: 'Caja cerrada',
        message:
            'La caja debe estar abierta para cobrar una venta. Puedes guardar el ticket como cotización.',
        icon: Icons.lock_outline_rounded,
        accent: const Color(0xFFF59E0B),
      );
      return;
    }
    if (!mounted) return;

    final result = await showDialog<_CheckoutResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CheckoutPaymentDialog(
        total: _total,
        money: _money,
        onConfirm: (method) => Navigator.of(context).pop(method),
      ),
    );
    if (result == null) return;

    await _finalizeCotizacion(checkout: result);
  }

  Future<void> _finalizeCotizacion({_CheckoutResult? checkout}) async {
    if (!_validateCheckoutReady()) return;

    final popOnSave =
        (GoRouterState.of(context).uri.queryParameters['popOnSave'] ?? '')
            .trim() ==
        '1';

    if (checkout != null) {
      final cashState = await ref.read(cashRepositoryProvider).state();
      if (cashState.activeSession == null) {
        if (!mounted) return;
        _showSalesNotice(
          title: 'Caja cerrada',
          message: 'No se puede cobrar ventas con la caja cerrada.',
          icon: Icons.lock_outline_rounded,
          accent: const Color(0xFFF59E0B),
        );
        return;
      }
    }

    final paymentLabel = checkout == null
        ? null
        : _checkoutPaymentLabel(checkout.method);
    final saleNote = [
      if (_note.trim().isNotEmpty) _note.trim(),
      ..._fiscalSaleNoteLines(),
      if (paymentLabel != null) 'Pago: $paymentLabel',
    ].join('\n');

    try {
      final saleItems = _buildCheckoutSaleItems();

      final createdSale = await ref
          .read(ventasRepositoryProvider)
          .createSale(
            customerId: _selectedClientId!,
            note: saleNote.isEmpty ? _note : saleNote,
            paymentMethod: checkout == null
                ? null
                : switch (checkout.method) {
                    _CheckoutPaymentMethod.cash => 'cash',
                    _CheckoutPaymentMethod.transfer => 'transfer',
                    _CheckoutPaymentMethod.mixed => 'mixed',
                    _CheckoutPaymentMethod.credit => 'credit',
                  },
            paymentCashAmount: checkout?.cashAmount,
            paymentTransferAmount: checkout?.transferAmount,
            creditAmount: checkout?.creditAmount,
            expectedTotalSold: _roundCurrency(_total),
            items: saleItems,
          );

      if (checkout != null && createdSale != null) {
        final saleToPrint = createdSale.items.isNotEmpty
            ? createdSale
            : await ref.read(ventasRepositoryProvider).getById(createdSale.id);
        final printResult = await ref
            .read(unifiedTicketPrinterProvider)
            .printSaleTicket(sale: saleToPrint, items: saleToPrint.items);
        if (!printResult.success && mounted) {
          _showSalesNotice(
            title: 'Factura guardada sin imprimir',
            message: printResult.message,
            icon: Icons.print_disabled_outlined,
            accent: const Color(0xFFF59E0B),
          );
        }
      }

      if (checkout?.method == _CheckoutPaymentMethod.credit) {
        ref.invalidate(salesCreditsProvider);
      }
      ref.invalidate(ventasControllerProvider);

      if (!mounted) return;

      _commitEditorChange(_resetEditorState);
      _schedulePersistEditorDraft(immediate: true);
      unawaited(_loadProducts(forceRemote: true, silent: true));

      _showSalesNotice(
        title: 'Venta guardada',
        message: 'La venta fue guardada y el stock quedó actualizado.',
        icon: Icons.check_circle_outline_rounded,
        accent: const Color(0xFF1957E6),
      );
    } catch (e) {
      if (!mounted) return;
      _showSalesNotice(
        title: 'No se pudo completar',
        message: e is ApiException ? e.message : '$e',
        icon: Icons.error_outline_rounded,
        accent: const Color(0xFFDC2626),
      );
      return;
    }

    if (!mounted) return;
    if (popOnSave) {
      context.pop(true);
    }
  }

  PreferredSizeWidget _buildDesktopAppBar(QuotationAiState aiState) {
    final showAiBanner = _shouldShowAiBanner(aiState);
    return FullTechPageHeader(
      title: 'Facturación',
      preferDrawerLeading: true,
      actions: [
        const CashTurnMenuButton(),
        const SizedBox(width: 8),
        _QuotationTopbarMenu(
          onQuote: _saveCurrentAsQuotation,
          onHistory: () => context.go(Routes.cotizacionesHistorial),
          onPdf: _openPdfPreview,
          onServiceOrder: _sendQuotationToServiceOrder,
        ),
        _ClientTopbarAction(
          hasClient:
              (_selectedClientId ?? '').trim().isNotEmpty &&
              _selectedClientName.trim() != 'Sin cliente',
          onPressed: _openClientDialog,
        ),
        if (showAiBanner)
          IconButton(
            tooltip: 'Cerrar comentario IA',
            onPressed: _closeAiBanner,
            icon: const Icon(Icons.close_rounded),
          ),
      ],
      trailing: const _CompanyAccountMenu(),
    );
  }

  Widget _buildProductStrip() {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: SizedBox(
        height: 324,
        child: _visibleProducts.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    _searchCtrl.text.trim().isNotEmpty ||
                            _selectedCategory != null
                        ? 'No hay productos con este filtro'
                        : 'El catálogo aparecerá aquí en miniatura',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              )
            : GridView.builder(
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                  childAspectRatio: 0.78,
                ),
                itemCount: _visibleProducts.length,
                itemBuilder: (context, index) {
                  final product = _visibleProducts[index];
                  return _ProductThumbCard(
                    product: product,
                    onTap: () => _addProduct(product),
                    money: _money,
                  );
                },
              ),
      ),
    );
  }

  Widget _buildTicketPanel(UserModel? currentUser) {
    final isAdmin = currentUser?.appRole == AppRole.admin;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(
        children: [
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Text(
                      'Toca un producto arriba para agregarlo',
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
                    itemCount: _items.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 6,
                      thickness: 0.6,
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.42),
                    ),
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return _TicketCompactItem(
                        item: item,
                        money: _money,
                        showCost: isAdmin,
                        onEditLine: () => _openLineEditor(index),
                        onMinus: () => _setQty(index, item.qty - 1),
                        onPlus: () => _setQty(index, item.qty + 1),
                        onChangeQty: (value) => _setQty(index, value),
                        onChangePrice: (value) => _setUnitPrice(index, value),
                        onEdit: item.isExternal
                            ? () => _openExternalItemDialog(editIndex: index)
                            : null,
                        onRemove: () =>
                            _commitEditorChange(() => _items.removeAt(index)),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 5, 12, 7),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Sub ${_money(_subtotalBeforeDiscount)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_discountAmount > 0)
                      Text(
                        'Desc -${_money(_discountAmount)}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                GestureDetector(
                  onTap: _applyGeneralDiscount,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: isAdmin
                                    ? Text(
                                        'Utilidad ${_money(_utilityAmount)}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF1957E6),
                                        ),
                                      )
                                    : (_effectiveGeneralDiscountAmount > 0
                                          ? Text(
                                              'Rebaja ${_money(_effectiveGeneralDiscountAmount)}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                    color: Theme.of(
                                                      context,
                                                    ).colorScheme.primary,
                                                  ),
                                            )
                                          : const SizedBox.shrink()),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  'TOTAL',
                                  textAlign: TextAlign.right,
                                  style: Theme.of(context).textTheme.labelMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                      ),
                                ),
                                Text(
                                  _money(_total),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    height: 1,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        if (isAdmin && _effectiveGeneralDiscountAmount > 0)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Rebaja ${_money(_effectiveGeneralDiscountAmount)}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                              ),
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            _effectiveGeneralDiscountAmount > 0
                                ? 'Toque para editar o quitar rebaja general'
                                : 'Toque para rebaja general',
                            textAlign: TextAlign.right,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontSize: 9.5,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Transform.scale(
                      scale: 0.74,
                      child: Switch.adaptive(
                        value: _includeItbis,
                        onChanged: (value) =>
                            _commitEditorChange(() => _setItbisEnabled(value)),
                      ),
                    ),
                    const Text(
                      'ITBIS',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_includeItbis) ...[
                      const SizedBox(width: 6),
                      Text(
                        _money(_itbisAmount),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const Spacer(),
                    IconButton(
                      tooltip: 'Limpiar todo',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minHeight: 24,
                        minWidth: 24,
                      ),
                      onPressed: !_hasEditorContent
                          ? null
                          : () {
                              _commitEditorChange(_resetEditorState);
                            },
                      icon: const Icon(Icons.delete_sweep_outlined),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _openCheckoutDialog,
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text('Finalizar'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          backgroundColor: const Color(0xFF1957E6),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileTopBar({required bool showAiBanner}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Row(
        children: [
          Builder(
            builder: (scaffoldContext) => Material(
              color: Colors.white.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: () => Scaffold.of(scaffoldContext).openDrawer(),
                borderRadius: BorderRadius.circular(14),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.menu_rounded, size: 20),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => _commitEditorChange(() {}),
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _submitSearchAndAddFirstVisibleProduct(),
                decoration: InputDecoration(
                  hintText: 'Buscar',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: _pickCategory,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  _selectedCategory == null
                      ? Icons.filter_alt_outlined
                      : Icons.filter_alt,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (showAiBanner) ...[
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: _closeAiBanner,
                borderRadius: BorderRadius.circular(14),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.close_rounded, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          PopupMenuButton<_MobileQuickAction>(
            tooltip: 'Más opciones',
            color: theme.colorScheme.surface,
            surfaceTintColor: theme.colorScheme.surface,
            elevation: 14,
            shadowColor: Colors.black.withValues(alpha: 0.14),
            position: PopupMenuPosition.under,
            offset: const Offset(0, 8),
            constraints: const BoxConstraints(minWidth: 250),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
            onSelected: _handleMobileQuickAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                height: 52,
                value: _MobileQuickAction.client,
                child: _MobileQuickMenuEntry(
                  icon: Icons.person_outline,
                  label: 'Cliente',
                ),
              ),
              const PopupMenuItem(
                height: 52,
                value: _MobileQuickAction.note,
                child: _MobileQuickMenuEntry(
                  icon: Icons.sticky_note_2_outlined,
                  label: 'Nota',
                ),
              ),
              const PopupMenuItem(
                height: 52,
                value: _MobileQuickAction.externalItem,
                child: _MobileQuickMenuEntry(
                  icon: Icons.add_box_outlined,
                  label: 'Fuera inventario',
                ),
              ),
              const PopupMenuItem(
                height: 52,
                value: _MobileQuickAction.tickets,
                child: _MobileQuickMenuEntry(
                  icon: Icons.receipt_long_outlined,
                  label: 'Cambiar ticket',
                ),
              ),
              const PopupMenuItem(
                height: 52,
                value: _MobileQuickAction.newTicket,
                child: _MobileQuickMenuEntry(
                  icon: Icons.add_circle_outline,
                  label: 'Nuevo ticket',
                ),
              ),
              const PopupMenuItem(
                height: 52,
                value: _MobileQuickAction.pdf,
                child: _MobileQuickMenuEntry(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'PDF',
                ),
              ),
              const PopupMenuItem(
                height: 52,
                value: _MobileQuickAction.serviceOrder,
                child: _MobileQuickMenuEntry(
                  icon: Icons.assignment_turned_in_outlined,
                  label: 'Pasar a orden de servicio',
                ),
              ),
              PopupMenuItem(
                height: 52,
                value: _MobileQuickAction.clear,
                child: _MobileQuickMenuEntry(
                  icon: Icons.delete_sweep_outlined,
                  label: 'Limpiar editor',
                  accentColor: theme.colorScheme.error,
                ),
              ),
            ],
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.all(10),
              child: const Icon(Icons.more_vert_rounded, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileTicketInfoBar() {
    final ticketNumber = _desktopTickets.indexWhere(
      (ticket) => ticket.id == _activeDesktopTicketId,
    );
    final editingLabel = _editingId == null ? 'Nuevo' : 'Editando';
    final clientLabel = _selectedClientName.trim().isEmpty
        ? 'Sin cliente'
        : _selectedClientName.trim();
    final ticketLabel = _activeTicketLabel;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        children: [
          Text(
            ticketLabel.isEmpty
                ? 'T-${ticketNumber < 0 ? 1 : ticketNumber + 1}'
                : ticketLabel,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              clientLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$editingLabel · ${_items.length}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontSize: 9.5),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileBody(QuotationAiState aiState, UserModel? currentUser) {
    final showAiBanner = _shouldShowAiBanner(aiState);
    return Column(
      children: [
        _buildMobileTopBar(showAiBanner: showAiBanner),
        _buildMobileTicketInfoBar(),
        if (showAiBanner)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            child: AiWarningBanner(
              warnings: aiState.visibleWarnings,
              analyzing: aiState.analyzing || aiState.loadingRules,
              onOpenRule: (warning) => _openAiRelatedRule(
                warning.relatedRuleId,
                warning.relatedRuleTitle,
              ),
              onAskAi: _askAiAboutWarning,
            ),
          ),
        _buildProductStrip(),
        const SizedBox(height: 8),
        Expanded(child: _buildTicketPanel(currentUser)),
      ],
    );
  }

  Widget _buildDesktopBody(QuotationAiState aiState, UserModel? currentUser) {
    final isAdmin = currentUser?.appRole == AppRole.admin;
    final showAiBanner = _shouldShowAiBanner(aiState);
    final managedCategories = ref.watch(inventoryCategoriesProvider).items;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      child: Column(
        children: [
          if (showAiBanner)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: AiWarningBanner(
                warnings: aiState.visibleWarnings,
                analyzing: aiState.analyzing || aiState.loadingRules,
                onOpenRule: (warning) => _openAiRelatedRule(
                  warning.relatedRuleId,
                  warning.relatedRuleTitle,
                ),
                onAskAi: _askAiAboutWarning,
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final quotePaneWidth = (constraints.maxWidth * 0.31).clamp(
                  500.0,
                  550.0,
                );
                final fiscalPaneWidth = (constraints.maxWidth * 0.22).clamp(
                  340.0,
                  390.0,
                );

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _DesktopCatalogPane(
                        searchController: _searchCtrl,
                        selectedCategory: _selectedCategory,
                        categories: _categories,
                        managedCategories: managedCategories,
                        allProducts: _productos,
                        visibleProducts: _visibleProducts,
                        loadingProducts: _loadingProducts,
                        error: _error,
                        money: _money,
                        onSearchChanged: () => _commitEditorChange(() {}),
                        onSearchSubmitted:
                            _submitSearchAndAddFirstVisibleProduct,
                        onSelectCategory: (category) => _commitEditorChange(
                          () => _selectedCategory = category,
                        ),
                        onAddProduct: _addProduct,
                        onAddExternalItem: () => _openExternalItemDialog(),
                        onOpenNewProduct: _openInventoryCatalog,
                        onOpenStockAdjustments: _openStockAdjustments,
                      ),
                    ),
                    SizedBox(
                      width: quotePaneWidth,
                      child: _showDesktopManualItemForm
                          ? _DesktopManualItemPanel(
                              key: ValueKey(
                                'manual-${_desktopManualEditIndex ?? 'new'}',
                              ),
                              item:
                                  _desktopManualEditIndex != null &&
                                      _desktopManualEditIndex! >= 0 &&
                                      _desktopManualEditIndex! < _items.length
                                  ? _items[_desktopManualEditIndex!]
                                  : null,
                              money: _money,
                              parseAmount: _parseAccountingInput,
                              formatAmount: _formatAccountingInput,
                              isAdmin: isAdmin,
                              onCancel: () => setState(() {
                                _showDesktopManualItemForm = false;
                                _desktopManualEditIndex = null;
                              }),
                              onSubmit:
                                  ({
                                    required name,
                                    required qty,
                                    required unitPrice,
                                    required externalCost,
                                  }) {
                                    if (!_validateExternalItemInput(
                                      name: name,
                                      qty: qty,
                                      unitPrice: unitPrice,
                                      externalCost: externalCost,
                                    )) {
                                      _showExternalItemInputNotice();
                                      return;
                                    }
                                    _commitExternalItem(
                                      name: name,
                                      qty: qty,
                                      unitPrice: unitPrice,
                                      externalCost: externalCost,
                                      editIndex: _desktopManualEditIndex,
                                    );
                                  },
                            )
                          : _DesktopQuotePanel(
                              items: _items,
                              selectedClientName: _selectedClientName,
                              includeItbis: _includeItbis,
                              subtotalBeforeDiscount: _subtotalBeforeDiscount,
                              discountAmount: _lineDiscountAmount,
                              generalDiscountAmount:
                                  _effectiveGeneralDiscountAmount,
                              subtotal: _subtotal,
                              itbisAmount: _itbisAmount,
                              total: _total,
                              isAdmin: isAdmin,
                              utilityAmount: _utilityAmount,
                              money: _money,
                              onPickClient: _openClientDialog,
                              onOpenHistory: _openRecentSalesPanel,
                              onToggleItbis: (value) => _commitEditorChange(
                                () => _setItbisEnabled(value),
                              ),
                              hasNote: _note.trim().isNotEmpty,
                              onOpenNote: _openNoteDialog,
                              onClear: !_hasEditorContent
                                  ? null
                                  : () {
                                      unawaited(_confirmAndClearSale());
                                    },
                              onFinalize: _openCheckoutDialog,
                              onApplyGeneralDiscount: _applyGeneralDiscount,
                              onMinusQty: (index) =>
                                  _setQty(index, _items[index].qty - 1),
                              onPlusQty: (index) =>
                                  _setQty(index, _items[index].qty + 1),
                              onChangePrice: _setUnitPrice,
                              onEditLine: _openLineEditor,
                              onEditExternalItem: (index) =>
                                  _openExternalItemDialog(editIndex: index),
                              onRemoveItem: (index) => _commitEditorChange(
                                () => _items.removeAt(index),
                              ),
                            ),
                    ),
                    if (_includeItbis)
                      SizedBox(
                        width: fiscalPaneWidth,
                        child: _DesktopFiscalInvoicePanel(
                          voucherType: _fiscalVoucherType,
                          voucherNumber: _fiscalVoucherNumber,
                          dueDate: _fiscalVoucherDueDate,
                          customerTaxId: _fiscalCustomerTaxId,
                          customerName: _fiscalCustomerName,
                          requiresTaxId: _fiscalVoucherRequiresTaxId,
                          onTypeChanged: (value) => _commitEditorChange(
                            () => _fiscalVoucherType = value,
                          ),
                          onVoucherNumberChanged: (value) =>
                              _commitEditorChange(
                                () => _fiscalVoucherNumber = value
                                    .trim()
                                    .toUpperCase(),
                              ),
                          onCustomerTaxIdChanged: (value) =>
                              _commitEditorChange(
                                () => _fiscalCustomerTaxId = value,
                              ),
                          onCustomerNameChanged: (value) => _commitEditorChange(
                            () => _fiscalCustomerName = value,
                          ),
                          onPickDueDate: _pickFiscalVoucherDueDate,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final aiState = ref.watch(quotationAiControllerProvider);
    final isDesktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;
    if (isDesktop) {
      _publishDesktopShellFooter();
    }

    return Scaffold(
      appBar: isDesktop ? _buildDesktopAppBar(aiState) : null,
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: SafeArea(
        child: isDesktop
            ? _buildDesktopBody(aiState, user)
            : _buildMobileBody(aiState, user),
      ),
    );
  }
}

enum _MobileQuickAction {
  client,
  note,
  externalItem,
  tickets,
  newTicket,
  pdf,
  serviceOrder,
  clear,
}

class _SalesNoticeToast extends StatelessWidget {
  const _SalesNoticeToast({
    required this.title,
    required this.message,
    required this.icon,
    required this.accent,
    required this.repeatCount,
    required this.onClose,
  });

  final String title;
  final String message;
  final IconData icon;
  final Color accent;
  final int repeatCount;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430, minWidth: 360),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.38)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(height: 3, color: accent),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, color: accent, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF0F172A),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                if (repeatCount > 1) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: accent.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      'x$repeatCount',
                                      style: TextStyle(
                                        color: accent,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              message,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF475569),
                                fontWeight: FontWeight.w600,
                                height: 1.25,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: onClose,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: const Color(0xFF64748B),
                        style: IconButton.styleFrom(
                          fixedSize: const Size(30, 30),
                          minimumSize: const Size(30, 30),
                          padding: EdgeInsets.zero,
                          backgroundColor: const Color(0xFFF1F5F9),
                        ),
                      ),
                    ],
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

class _QuotationTopbarMenu extends StatelessWidget {
  const _QuotationTopbarMenu({
    required this.onQuote,
    required this.onHistory,
    required this.onPdf,
    required this.onServiceOrder,
  });

  final VoidCallback onQuote;
  final VoidCallback onHistory;
  final VoidCallback onPdf;
  final VoidCallback onServiceOrder;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: PopupMenuButton<String>(
        tooltip: 'Cotizaciones',
        offset: const Offset(0, 42),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (value) {
          switch (value) {
            case 'quote':
              onQuote();
              break;
            case 'history':
              onHistory();
              break;
            case 'pdf':
              onPdf();
              break;
            case 'service_order':
              onServiceOrder();
              break;
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: 'quote',
            child: _QuotationMenuItem(
              icon: Icons.request_quote_outlined,
              title: 'Cotizar',
              subtitle: 'Guardar ticket actual',
            ),
          ),
          PopupMenuItem(
            value: 'history',
            child: _QuotationMenuItem(
              icon: Icons.history_edu_outlined,
              title: 'Lista de cotizaciones',
              subtitle: 'Ver cotizaciones guardadas',
            ),
          ),
          PopupMenuItem(
            value: 'pdf',
            child: _QuotationMenuItem(
              icon: Icons.picture_as_pdf_outlined,
              title: 'Ver PDF',
              subtitle: 'Vista previa o impresión',
            ),
          ),
          PopupMenuItem(
            value: 'service_order',
            child: _QuotationMenuItem(
              icon: Icons.assignment_turned_in_outlined,
              title: 'Pasar a orden de servicio',
              subtitle: 'Crear orden desde el ticket',
            ),
          ),
        ],
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F7FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFCFE0FF)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.request_quote_outlined,
                size: 18,
                color: Color(0xFF123A75),
              ),
              SizedBox(width: 7),
              Text(
                'Cotizaciones',
                style: TextStyle(
                  color: Color(0xFF123A75),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
              SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: Color(0xFF123A75),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanyAccountMenu extends ConsumerWidget {
  const _CompanyAccountMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(companySettingsProvider);
    final companyName = company.maybeWhen(
      data: (settings) => settings.companyName.trim().isEmpty
          ? 'FULLTECH'
          : settings.companyName.trim(),
      orElse: () => 'FULLTECH',
    );
    final logoBase64 = company.maybeWhen(
      data: (settings) => settings.logoBase64?.trim(),
      orElse: () => null,
    );

    return Padding(
      padding: const EdgeInsets.only(right: 10, left: 4),
      child: PopupMenuButton<String>(
        tooltip: 'Cuenta y empresa',
        offset: const Offset(0, 44),
        elevation: 0,
        color: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFD8E5F3)),
        ),
        constraints: const BoxConstraints(minWidth: 268),
        onSelected: (value) {
          switch (value) {
            case 'profile':
              context.go(Routes.profile);
              break;
            case 'teams':
              context.go(Routes.users);
              break;
            case 'settings':
              context.go(Routes.configuracion);
              break;
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(
            value: 'profile',
            child: _CompanyMenuItem(
              icon: Icons.person_outline_rounded,
              label: 'Perfil',
            ),
          ),
          PopupMenuItem(
            value: 'teams',
            child: _CompanyMenuItem(
              icon: Icons.groups_2_outlined,
              label: 'Equipos',
            ),
          ),
          PopupMenuItem(
            value: 'settings',
            child: _CompanyMenuItem(
              icon: Icons.settings_outlined,
              label: 'Configuración',
            ),
          ),
        ],
        child: Container(
          height: 38,
          padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
          decoration: BoxDecoration(
            color: const Color(0xFF1957E6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF7DA2FF)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x291957E6),
                blurRadius: 14,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _CompanyLogoBox(logoBase64: logoBase64),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 190),
                child: Text(
                  companyName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                    letterSpacing: 0,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanyLogoBox extends StatelessWidget {
  const _CompanyLogoBox({required this.logoBase64});

  final String? logoBase64;

  @override
  Widget build(BuildContext context) {
    final logoBytes = _decodeLogo(logoBase64);
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      clipBehavior: Clip.antiAlias,
      child: logoBytes == null
          ? const Icon(
              Icons.storefront_rounded,
              size: 16,
              color: Color(0xFF1957E6),
            )
          : Image.memory(logoBytes, fit: BoxFit.cover),
    );
  }

  Uint8List? _decodeLogo(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) return null;
    try {
      final payload = raw.contains(',') ? raw.split(',').last : raw;
      return base64Decode(payload);
    } catch (_) {
      return null;
    }
  }
}

class _CompanyMenuItem extends StatelessWidget {
  const _CompanyMenuItem({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F7FB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD5E2EC)),
            ),
            child: Icon(icon, size: 17, color: const Color(0xFF34475A)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF27364A),
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: Color(0xFF9AA8B6),
          ),
        ],
      ),
    );
  }
}

class _QuotationMenuItem extends StatelessWidget {
  const _QuotationMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FF),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xFFCFE0FF)),
            ),
            child: Icon(icon, color: const Color(0xFF1957E6), size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientTopbarAction extends StatefulWidget {
  const _ClientTopbarAction({required this.hasClient, required this.onPressed});

  final bool hasClient;
  final VoidCallback onPressed;

  @override
  State<_ClientTopbarAction> createState() => _ClientTopbarActionState();
}

class _ClientTopbarActionState extends State<_ClientTopbarAction> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _pressed ? 0.97 : (_hovered ? 1.035 : 1.0);
    const foreground = Color(0xFF123A75);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _pressed = false;
        }),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onPressed,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapCancel: () => setState(() => _pressed = false),
              onTapUp: (_) => setState(() => _pressed = false),
              borderRadius: BorderRadius.circular(8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 15),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F7FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFCFE0FF)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(
                        0xFF123A75,
                      ).withValues(alpha: _hovered ? 0.12 : 0.06),
                      blurRadius: _hovered ? 12 : 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: widget.hasClient
                            ? const Color(0xFFEAF1FF)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.person_add_alt_1_rounded,
                        color: widget.hasClient
                            ? const Color(0xFF1957E6)
                            : foreground,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Cliente',
                      style: const TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w900,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckoutPaymentDialog extends StatefulWidget {
  const _CheckoutPaymentDialog({
    required this.total,
    required this.money,
    required this.onConfirm,
  });

  final double total;
  final String Function(double value) money;
  final ValueChanged<_CheckoutResult> onConfirm;

  @override
  State<_CheckoutPaymentDialog> createState() => _CheckoutPaymentDialogState();
}

class _CheckoutPaymentDialogState extends State<_CheckoutPaymentDialog> {
  _CheckoutPaymentMethod _method = _CheckoutPaymentMethod.cash;
  late final TextEditingController _cashController;
  late final TextEditingController _transferController;

  @override
  void initState() {
    super.initState();
    _cashController = TextEditingController(
      text: _formatAccountingInput(widget.total),
    );
    _transferController = TextEditingController(text: '0.00');
    _cashController.addListener(() => setState(() {}));
    _transferController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _cashController.dispose();
    _transferController.dispose();
    super.dispose();
  }

  double get _cashAmount {
    return _parseAccountingInput(_cashController.text) ?? 0;
  }

  double get _transferAmount {
    if (_method == _CheckoutPaymentMethod.transfer) return widget.total;
    if (_method == _CheckoutPaymentMethod.mixed ||
        _method == _CheckoutPaymentMethod.credit) {
      return _parseAccountingInput(_transferController.text) ?? 0;
    }
    return 0;
  }

  double get _coveredAmount {
    if (_method == _CheckoutPaymentMethod.cash) return _cashAmount;
    if (_method == _CheckoutPaymentMethod.transfer) return widget.total;
    return _cashAmount + _transferAmount;
  }

  double get _creditAmount {
    if (_method != _CheckoutPaymentMethod.credit) return 0;
    return (widget.total - _coveredAmount).clamp(0, widget.total).toDouble();
  }

  double get _changeAmount {
    if (_method == _CheckoutPaymentMethod.transfer) return 0;
    return (_coveredAmount - widget.total).clamp(0, double.infinity);
  }

  bool get _canConfirm {
    if (_method == _CheckoutPaymentMethod.credit) {
      return _coveredAmount >= 0 && _coveredAmount <= widget.total + 0.0001;
    }
    return _coveredAmount + 0.0001 >= widget.total;
  }

  _CheckoutResult _result() {
    final cashAmount = switch (_method) {
      _CheckoutPaymentMethod.cash => widget.total,
      _CheckoutPaymentMethod.transfer => 0.0,
      _CheckoutPaymentMethod.mixed =>
        _cashAmount.clamp(0, widget.total).toDouble(),
      _CheckoutPaymentMethod.credit =>
        _cashAmount.clamp(0, widget.total).toDouble(),
    };
    final transferAmount = switch (_method) {
      _CheckoutPaymentMethod.cash => 0.0,
      _CheckoutPaymentMethod.transfer => widget.total,
      _CheckoutPaymentMethod.mixed =>
        _transferAmount.clamp(0, widget.total - cashAmount).toDouble(),
      _CheckoutPaymentMethod.credit =>
        _transferAmount.clamp(0, widget.total).toDouble(),
    };
    return _CheckoutResult(
      method: _method,
      cashAmount: cashAmount,
      transferAmount: transferAmount,
      creditAmount: _method == _CheckoutPaymentMethod.credit
          ? (widget.total - cashAmount - transferAmount)
                .clamp(0, widget.total)
                .toDouble()
          : 0,
    );
  }

  void _selectMethod(_CheckoutPaymentMethod method) {
    setState(() {
      _method = method;
      if (method == _CheckoutPaymentMethod.transfer) {
        _cashController.text = '0.00';
        _transferController.text = _formatAccountingInput(widget.total);
      } else if (method == _CheckoutPaymentMethod.mixed) {
        _cashController.text = _formatAccountingInput(widget.total);
        _transferController.text = '0.00';
      } else if (method == _CheckoutPaymentMethod.credit) {
        _cashController.text = '0.00';
        _transferController.text = '0.00';
      } else if (_cashAmount <= 0) {
        _cashController.text = _formatAccountingInput(widget.total);
        _transferController.text = '0.00';
      }
    });
  }

  void _confirmCheckout() {
    if (!_canConfirm) return;
    widget.onConfirm(_result());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.sizeOf(context);
    final isMobile = media.width < 640;
    final isTransfer = _method == _CheckoutPaymentMethod.transfer;
    final isMixed = _method == _CheckoutPaymentMethod.mixed;
    final isCredit = _method == _CheckoutPaymentMethod.credit;

    return CallbackShortcuts(
      bindings: {
        if (_canConfirm)
          const SingleActivator(LogicalKeyboardKey.enter): _confirmCheckout,
        if (_canConfirm)
          const SingleActivator(LogicalKeyboardKey.numpadEnter):
              _confirmCheckout,
        if (_canConfirm)
          const SingleActivator(LogicalKeyboardKey.f9): _confirmCheckout,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          insetPadding: EdgeInsets.symmetric(
            horizontal: isMobile ? 12 : 24,
            vertical: isMobile ? 10 : 20,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 760,
              maxHeight: media.height - (isMobile ? 24 : 40),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 16 : 24,
                    18,
                    isMobile ? 10 : 18,
                    16,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF1FF),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(
                          Icons.point_of_sale_rounded,
                          color: Color(0xFF1957E6),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cobrar venta',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Confirma el pago y genera la factura',
                              style: TextStyle(color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      isMobile ? 16 : 24,
                      18,
                      isMobile ? 16 : 24,
                      18,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: EdgeInsets.all(isMobile ? 14 : 18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFD6E3ED)),
                          ),
                          child: Column(
                            children: [
                              isMobile
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Total a pagar',
                                          style: TextStyle(
                                            color: Color(0xFF475569),
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          widget.money(widget.total),
                                          style: const TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Row(
                                      children: [
                                        const Text(
                                          'Total a pagar',
                                          style: TextStyle(
                                            color: Color(0xFF475569),
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          widget.money(widget.total),
                                          style: const TextStyle(
                                            fontSize: 30,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF0F172A),
                                          ),
                                        ),
                                      ],
                                    ),
                              const Divider(
                                height: 26,
                                color: Color(0xFFE2E8F0),
                              ),
                              if (!isTransfer) ...[
                                _PaymentAmountInput(
                                  label: isMixed
                                      ? 'Efectivo'
                                      : isCredit
                                      ? 'Efectivo abonado'
                                      : 'Cliente paga con',
                                  controller: _cashController,
                                  enabled: true,
                                  compact: isMobile,
                                ),
                                const SizedBox(height: 10),
                              ],
                              if (isMixed || isCredit) ...[
                                _PaymentAmountInput(
                                  label: isCredit
                                      ? 'Transferencia abonada'
                                      : 'Transferencia',
                                  controller: _transferController,
                                  enabled: true,
                                  compact: isMobile,
                                ),
                                const SizedBox(height: 10),
                              ] else if (isTransfer) ...[
                                _ReadonlyPaymentLine(
                                  icon: Icons.account_balance_outlined,
                                  label: 'Transferencia',
                                  value: widget.money(widget.total),
                                ),
                                const SizedBox(height: 10),
                              ],
                              if (isCredit) ...[
                                _ReadonlyPaymentLine(
                                  icon: Icons.credit_score_outlined,
                                  label: 'Queda a crédito',
                                  value: widget.money(_creditAmount),
                                  strong: _creditAmount > 0,
                                ),
                                const SizedBox(height: 10),
                              ],
                              _ReadonlyPaymentLine(
                                icon: Icons.keyboard_return_rounded,
                                label: 'Devuelta',
                                value: widget.money(
                                  isCredit ? 0 : _changeAmount,
                                ),
                                strong: !isCredit && _changeAmount > 0,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Método de pago',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (isMobile)
                          Column(
                            children: [
                              for (final method
                                  in _CheckoutPaymentMethod.values) ...[
                                _PaymentMethodTile(
                                  method: method,
                                  selected: _method == method,
                                  onTap: () => _selectMethod(method),
                                ),
                                if (method !=
                                    _CheckoutPaymentMethod.values.last)
                                  const SizedBox(height: 8),
                              ],
                            ],
                          )
                        else
                          Row(
                            children: [
                              for (final method
                                  in _CheckoutPaymentMethod.values) ...[
                                Expanded(
                                  child: _PaymentMethodTile(
                                    method: method,
                                    selected: _method == method,
                                    onTap: () => _selectMethod(method),
                                  ),
                                ),
                                if (method !=
                                    _CheckoutPaymentMethod.values.last)
                                  const SizedBox(width: 10),
                              ],
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 16 : 24,
                    14,
                    isMobile ? 16 : 24,
                    18,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FBFD),
                    border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                  ),
                  child: isMobile
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              _canConfirm
                                  ? 'Listo para cobrar'
                                  : isCredit
                                  ? 'El abono no puede superar el total'
                                  : 'Monto recibido insuficiente',
                              style: TextStyle(
                                color: _canConfirm
                                    ? const Color(0xFF64748B)
                                    : theme.colorScheme.error,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: _canConfirm ? _confirmCheckout : null,
                              icon: const Icon(Icons.receipt_long_outlined),
                              label: Text(
                                _method == _CheckoutPaymentMethod.credit
                                    ? 'Crear crédito'
                                    : 'Cobrar y facturar',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF1957E6),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Cancelar'),
                            ),
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(
                              child: Text(
                                _canConfirm
                                    ? 'Enter/F9 para cobrar · Esc para salir'
                                    : isCredit
                                    ? 'El abono no puede superar el total de la factura'
                                    : 'Monto recibido insuficiente para completar el cobro',
                                style: TextStyle(
                                  color: _canConfirm
                                      ? const Color(0xFF64748B)
                                      : theme.colorScheme.error,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('Cancelar'),
                            ),
                            const SizedBox(width: 10),
                            FilledButton.icon(
                              onPressed: _canConfirm ? _confirmCheckout : null,
                              icon: const Icon(Icons.receipt_long_outlined),
                              label: Text(
                                _method == _CheckoutPaymentMethod.credit
                                    ? 'Crear crédito'
                                    : 'Cobrar y facturar',
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF1957E6),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 22,
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
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

class _PaymentAmountInput extends StatelessWidget {
  const _PaymentAmountInput({
    required this.label,
    required this.controller,
    required this.enabled,
    this.compact = false,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(height: 46, child: _amountField()),
        ],
      );
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
            ),
          ),
        ),
        SizedBox(width: 210, height: 46, child: _amountField()),
      ],
    );
  }

  Widget _amountField() {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textAlign: TextAlign.right,
      style: const TextStyle(
        color: Color(0xFF1957E6),
        fontWeight: FontWeight.w900,
      ),
      decoration: InputDecoration(
        prefixText: r'RD$  ',
        filled: true,
        fillColor: const Color(0xFFF8FBFD),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: Color(0xFFC9D8EA)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: Color(0xFFC9D8EA)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(9),
          borderSide: const BorderSide(color: Color(0xFF1957E6), width: 1.4),
        ),
      ),
    );
  }
}

class _ReadonlyPaymentLine extends StatelessWidget {
  const _ReadonlyPaymentLine({
    required this.icon,
    required this.label,
    required this.value,
    this.strong = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF64748B)),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w900,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: strong ? const Color(0xFF1957E6) : const Color(0xFF64748B),
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  const _PaymentMethodTile({
    required this.method,
    required this.selected,
    required this.onTap,
  });

  final _CheckoutPaymentMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF1957E6) : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFF1957E6)
                  : const Color(0xFFD4E0EA),
            ),
          ),
          child: Row(
            children: [
              Icon(
                method.icon,
                size: 19,
                color: selected ? Colors.white : const Color(0xFF1957E6),
              ),
              const SizedBox(width: 10),
              Text(
                method.label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentSalesPanel extends StatefulWidget {
  const _RecentSalesPanel({
    required this.loadSales,
    required this.money,
    required this.dateLabel,
    required this.shortId,
    required this.onViewSale,
    required this.onOpenPdf,
    required this.onClose,
    required this.onOpenFullHistory,
  });

  final Future<List<SaleModel>> Function() loadSales;
  final String Function(double value) money;
  final String Function(DateTime? date) dateLabel;
  final String Function(SaleModel sale) shortId;
  final ValueChanged<SaleModel> onViewSale;
  final ValueChanged<SaleModel> onOpenPdf;
  final VoidCallback onClose;
  final VoidCallback onOpenFullHistory;

  @override
  State<_RecentSalesPanel> createState() => _RecentSalesPanelState();
}

class _RecentSalesPanelState extends State<_RecentSalesPanel> {
  late Future<List<SaleModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.loadSales();
  }

  void _reload() {
    setState(() => _future = widget.loadSales());
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    final width = media.width < 680 ? media.width : 550.0;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        left: false,
        child: Container(
          width: width,
          height: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            border: const Border(left: BorderSide(color: Color(0xFFD3E0E7))),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 26,
                offset: const Offset(-8, 0),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF1FF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.receipt_long_outlined,
                        color: Color(0xFF1957E6),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Ventas recientes',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Actualizar',
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFDCE7F0)),
              Expanded(
                child: FutureBuilder<List<SaleModel>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: scheme.error,
                                size: 36,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'No se pudieron cargar las ventas recientes.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: scheme.error,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton.icon(
                                onPressed: _reload,
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('Reintentar'),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final sales = (snapshot.data ?? const <SaleModel>[])
                        .take(12)
                        .toList(growable: false);
                    if (sales.isEmpty) {
                      return const Center(
                        child: Text('Todavía no hay ventas recientes'),
                      );
                    }

                    return Column(
                      children: [
                        Container(
                          height: 36,
                          color: const Color(0xFFF8FAFC),
                          child: const Row(
                            children: [
                              SizedBox(width: 16),
                              Expanded(
                                flex: 8,
                                child: Text(
                                  'Venta',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              Expanded(
                                flex: 5,
                                child: Text(
                                  'Total',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              Expanded(
                                flex: 5,
                                child: Text(
                                  'Estado',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                              SizedBox(width: 98),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ListView.separated(
                            itemCount: sales.length,
                            separatorBuilder: (_, __) => const Divider(
                              height: 1,
                              color: Color(0xFFE2E8F0),
                            ),
                            itemBuilder: (context, index) {
                              final sale = sales[index];
                              return _RecentSalesRow(
                                sale: sale,
                                money: widget.money,
                                dateLabel: widget.dateLabel,
                                shortId: widget.shortId,
                                onViewSale: widget.onViewSale,
                                onOpenPdf: widget.onOpenPdf,
                                onOpenFullHistory: widget.onOpenFullHistory,
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const Divider(height: 1, color: Color(0xFFDCE7F0)),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                child: SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: widget.onOpenFullHistory,
                    label: const Text('Ir al historial de ventas'),
                    icon: const Icon(Icons.arrow_forward_rounded),
                    iconAlignment: IconAlignment.end,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F172A),
                      side: const BorderSide(color: Color(0xFFC9D8EA)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentSalesRow extends StatelessWidget {
  const _RecentSalesRow({
    required this.sale,
    required this.money,
    required this.dateLabel,
    required this.shortId,
    required this.onViewSale,
    required this.onOpenPdf,
    required this.onOpenFullHistory,
  });

  final SaleModel sale;
  final String Function(double value) money;
  final String Function(DateTime? date) dateLabel;
  final String Function(SaleModel sale) shortId;
  final ValueChanged<SaleModel> onViewSale;
  final ValueChanged<SaleModel> onOpenPdf;
  final VoidCallback onOpenFullHistory;

  @override
  Widget build(BuildContext context) {
    final returned = sale.isDeleted;
    return Container(
      color: returned ? Colors.white : const Color(0xFFEFFBFF),
      padding: const EdgeInsets.fromLTRB(16, 9, 10, 9),
      child: Row(
        children: [
          Expanded(
            flex: 8,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Factura ${shortId(sale)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateLabel(sale.saleDate),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              money(sale.totalSold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
              returned ? 'Devuelta' : 'Activa',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: returned
                    ? const Color(0xFFB45309)
                    : const Color(0xFF1D4ED8),
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          SizedBox(
            width: 98,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Ver detalle',
                  onPressed: () => onViewSale(sale),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  color: const Color(0xFF475569),
                ),
                IconButton(
                  tooltip: 'Ver PDF',
                  onPressed: () => onOpenPdf(sale),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  color: const Color(0xFFE11D48),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _ClientOwnerFilter {
  all('Todos los usuarios'),
  mine('Mis clientes'),
  others('Otros usuarios');

  const _ClientOwnerFilter(this.label);
  final String label;
}

enum _ClientAgeFilter {
  all('Todos'),
  newer('Nuevos'),
  older('Viejos');

  const _ClientAgeFilter(this.label);
  final String label;
}

class _ClientFilterSelection {
  const _ClientFilterSelection({
    required this.ownerFilter,
    required this.ageFilter,
  });

  final _ClientOwnerFilter ownerFilter;
  final _ClientAgeFilter ageFilter;
}

class _ClientFilterChip extends StatelessWidget {
  const _ClientFilterChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.20),
        ),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _MobileQuickMenuEntry extends StatelessWidget {
  const _MobileQuickMenuEntry({
    required this.icon,
    required this.label,
    this.accentColor,
  });

  final IconData icon;
  final String label;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accentColor ?? theme.colorScheme.onSurface;

    return Row(
      children: [
        SizedBox(width: 24, child: Icon(icon, size: 20, color: color)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductThumbCard extends StatelessWidget {
  const _ProductThumbCard({
    required this.product,
    required this.onTap,
    required this.money,
  });

  final ProductModel product;
  final VoidCallback onTap;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(12),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              (product.displayFotoUrl ?? '').trim().isEmpty
                  ? Container(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: const Center(
                        child: Icon(Icons.inventory_2_outlined, size: 18),
                      ),
                    )
                  : ProductNetworkImage(
                      imageUrl: product.displayFotoUrl!,
                      productId: product.id,
                      productName: product.nombre,
                      originalUrl: product.originalFotoUrl,
                      fit: BoxFit.cover,
                      loading: Container(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                      ),
                      fallback: Container(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHighest,
                        child: const Center(
                          child: Icon(Icons.broken_image_outlined, size: 16),
                        ),
                      ),
                    ),
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x12000000), Color(0xAA000000)],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 5,
                right: 5,
                bottom: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9.4,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        product.categoriaLabel,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: const TextStyle(
                          fontSize: 8.2,
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      money(product.precio),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 8.8,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopCatalogPane extends StatefulWidget {
  const _DesktopCatalogPane({
    required this.searchController,
    required this.selectedCategory,
    required this.categories,
    required this.managedCategories,
    required this.allProducts,
    required this.visibleProducts,
    required this.loadingProducts,
    required this.error,
    required this.money,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onSelectCategory,
    required this.onAddProduct,
    required this.onAddExternalItem,
    required this.onOpenNewProduct,
    required this.onOpenStockAdjustments,
  });

  final TextEditingController searchController;
  final String? selectedCategory;
  final List<String> categories;
  final List<InventoryCategoryModel> managedCategories;
  final List<ProductModel> allProducts;
  final List<ProductModel> visibleProducts;
  final bool loadingProducts;
  final String? error;
  final String Function(double) money;
  final VoidCallback onSearchChanged;
  final VoidCallback onSearchSubmitted;
  final ValueChanged<String?> onSelectCategory;
  final ValueChanged<ProductModel> onAddProduct;
  final VoidCallback onAddExternalItem;
  final VoidCallback onOpenNewProduct;
  final VoidCallback onOpenStockAdjustments;

  @override
  State<_DesktopCatalogPane> createState() => _DesktopCatalogPaneState();
}

class _DesktopCatalogPaneState extends State<_DesktopCatalogPane> {
  late final ScrollController _gridScrollController;

  @override
  void initState() {
    super.initState();
    _gridScrollController = ScrollController();
  }

  @override
  void dispose() {
    _gridScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFFEFF5F8),
        border: Border(right: BorderSide(color: Color(0xFFD3E0E7))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1957E6),
                            borderRadius: BorderRadius.circular(5),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF1957E6,
                                ).withValues(alpha: 0.22),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.search_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: widget.searchController,
                            onChanged: (_) => widget.onSearchChanged(),
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => widget.onSearchSubmitted(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                            decoration: InputDecoration(
                              hintText:
                                  'Buscar producto por nombre o código...',
                              hintStyle: theme.textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF617383),
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                              ),
                              suffixIcon:
                                  widget.searchController.text.trim().isNotEmpty
                                  ? IconButton(
                                      tooltip: 'Limpiar búsqueda',
                                      onPressed: () {
                                        widget.searchController.clear();
                                        widget.onSearchChanged();
                                      },
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        size: 18,
                                      ),
                                    )
                                  : null,
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 0,
                              ),
                              enabledBorder: const OutlineInputBorder(
                                borderRadius: BorderRadius.zero,
                                borderSide: BorderSide(
                                  color: Color(0xFFD8E3EA),
                                ),
                              ),
                              focusedBorder: const OutlineInputBorder(
                                borderRadius: BorderRadius.zero,
                                borderSide: BorderSide(
                                  color: Color(0xFF1957E6),
                                  width: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _CatalogLineActionButton(
                  icon: Icons.add_box_outlined,
                  label: 'Nuevo producto',
                  onPressed: widget.onOpenNewProduct,
                ),
                const SizedBox(width: 8),
                _CatalogLineActionButton(
                  icon: Icons.inventory_2_outlined,
                  label: 'Agregar stock',
                  filled: true,
                  onPressed: widget.onOpenStockAdjustments,
                ),
              ],
            ),
            const SizedBox(height: 6),
            _DesktopCategoryStrip(
              categories: widget.categories,
              allProducts: widget.allProducts,
              managedCategories: widget.managedCategories,
              selectedCategory: widget.selectedCategory,
              onSelectCategory: widget.onSelectCategory,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final columns = width >= 1600
                      ? 8
                      : width >= 1280
                      ? 7
                      : width >= 1000
                      ? 6
                      : 5;
                  const spacing = 8.0;
                  final cardWidth = (width - spacing * (columns - 1)) / columns;
                  final cardHeight = (cardWidth * 1.02).clamp(95.0, 128.0);

                  return Scrollbar(
                    controller: _gridScrollController,
                    thumbVisibility: true,
                    interactive: true,
                    child: GridView.builder(
                      controller: _gridScrollController,
                      primary: false,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                        mainAxisExtent: cardHeight,
                      ),
                      itemCount: widget.visibleProducts.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _DesktopExternalProductCard(
                            onTap: widget.onAddExternalItem,
                          );
                        }
                        final product = widget.visibleProducts[index - 1];
                        return _DesktopProductCard(
                          product: product,
                          money: widget.money,
                          onTap: () => widget.onAddProduct(product),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _ManualItemSubmit =
    void Function({
      required String name,
      required double qty,
      required double unitPrice,
      required double? externalCost,
    });

class _DesktopManualItemPanel extends StatefulWidget {
  const _DesktopManualItemPanel({
    super.key,
    required this.item,
    required this.money,
    required this.parseAmount,
    required this.formatAmount,
    required this.isAdmin,
    required this.onCancel,
    required this.onSubmit,
  });

  final CotizacionItem? item;
  final String Function(double value) money;
  final double? Function(String raw) parseAmount;
  final String Function(num value) formatAmount;
  final bool isAdmin;
  final VoidCallback onCancel;
  final _ManualItemSubmit onSubmit;

  @override
  State<_DesktopManualItemPanel> createState() =>
      _DesktopManualItemPanelState();
}

class _DesktopManualItemPanelState extends State<_DesktopManualItemPanel> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _costCtrl;
  late final TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _nameCtrl = TextEditingController(text: item?.nombre ?? '');
    _qtyCtrl = TextEditingController(
      text: item == null
          ? '1'
          : (item.qty % 1 == 0
                ? item.qty.toStringAsFixed(0)
                : item.qty.toStringAsFixed(2)),
    );
    _costCtrl = TextEditingController(
      text: item?.externalCostUnit == null
          ? ''
          : widget.formatAmount(item!.externalCostUnit!),
    );
    _priceCtrl = TextEditingController(
      text: item == null ? '' : widget.formatAmount(item.unitPrice),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  double get _qty => widget.parseAmount(_qtyCtrl.text) ?? 0;
  double get _cost => widget.parseAmount(_costCtrl.text) ?? 0;
  double get _price => widget.parseAmount(_priceCtrl.text) ?? 0;
  double get _total => _qty * _price;
  double get _profit => _qty * (_price - _cost);

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF0F766E), width: 1.4),
      ),
    );
  }

  void _submit() {
    widget.onSubmit(
      name: _nameCtrl.text.trim(),
      qty: _qty,
      unitPrice: _price,
      externalCost: _costCtrl.text.trim().isEmpty ? null : _cost,
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.item != null;
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Color(0xFFD3E0E7))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2FE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.add_shopping_cart_outlined,
                    color: Color(0xFF075985),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        editing
                            ? 'Editar producto manual'
                            : 'Producto fuera de inventario',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Venta puntual sin registrar en catálogo.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: widget.onCancel,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              decoration: _decoration('Nombre producto o servicio'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: _decoration('Cantidad'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _costCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: _decoration('Costo unitario'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              decoration: _decoration('Precio unitario'),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _ManualItemMetric(
                      label: 'Total',
                      value: widget.money(_total),
                    ),
                  ),
                  if (widget.isAdmin) ...[
                    Container(
                      width: 1,
                      height: 30,
                      color: const Color(0xFFE2E8F0),
                    ),
                    Expanded(
                      child: _ManualItemMetric(
                        label: 'Utilidad',
                        value: widget.money(_profit),
                        alignEnd: true,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onCancel,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: const Color(0xFF0F766E),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(editing ? 'Guardar' : 'Agregar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopQuotePanel extends StatelessWidget {
  const _DesktopQuotePanel({
    required this.items,
    required this.selectedClientName,
    required this.includeItbis,
    required this.subtotalBeforeDiscount,
    required this.discountAmount,
    required this.generalDiscountAmount,
    required this.subtotal,
    required this.itbisAmount,
    required this.total,
    required this.isAdmin,
    required this.utilityAmount,
    required this.money,
    required this.onPickClient,
    required this.onOpenHistory,
    required this.onToggleItbis,
    required this.hasNote,
    required this.onOpenNote,
    required this.onClear,
    required this.onFinalize,
    required this.onApplyGeneralDiscount,
    required this.onMinusQty,
    required this.onPlusQty,
    required this.onChangePrice,
    required this.onEditLine,
    required this.onEditExternalItem,
    required this.onRemoveItem,
  });

  final List<CotizacionItem> items;
  final String selectedClientName;
  final bool includeItbis;
  final double subtotalBeforeDiscount;
  final double discountAmount;
  final double generalDiscountAmount;
  final double subtotal;
  final double itbisAmount;
  final double total;
  final bool isAdmin;
  final double utilityAmount;
  final String Function(double) money;
  final VoidCallback onPickClient;
  final VoidCallback onOpenHistory;
  final ValueChanged<bool> onToggleItbis;
  final bool hasNote;
  final VoidCallback onOpenNote;
  final VoidCallback? onClear;
  final VoidCallback onFinalize;
  final VoidCallback onApplyGeneralDiscount;
  final ValueChanged<int> onMinusQty;
  final ValueChanged<int> onPlusQty;
  final void Function(int index, double value) onChangePrice;
  final ValueChanged<int> onEditLine;
  final ValueChanged<int> onEditExternalItem;
  final ValueChanged<int> onRemoveItem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasItems = items.isNotEmpty;
    final hasClient =
        selectedClientName.trim().isNotEmpty &&
        selectedClientName.trim() != 'Sin cliente';
    final itemCountText = items.length == 1
        ? '1 producto'
        : '${items.length} productos';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(left: BorderSide(color: Color(0xFFD3E0E7))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasClient) ...[
              Material(
                color: const Color(0xFFF3F8FA),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: onPickClient,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF1FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.person_outline_rounded,
                            size: 18,
                            color: Color(0xFF1957E6),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            selectedClientName.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF183548),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.local_offer_outlined,
                            size: 52,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Agrega productos desde el catálogo',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _DesktopTicketItem(
                          item: item,
                          money: money,
                          onEditLine: () => onEditLine(index),
                          onMinus: () => onMinusQty(index),
                          onPlus: () => onPlusQty(index),
                          onChangePrice: (value) => onChangePrice(index, value),
                          onEdit: item.isExternal
                              ? () => onEditExternalItem(index)
                              : null,
                          onRemove: () => onRemoveItem(index),
                        );
                      },
                    ),
            ),
            if (hasItems) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFD3E0E7),
                    width: 1.1,
                  ),
                ),
                child: Column(
                  children: [
                    _CompactTotalLine(
                      label: 'Subtotal',
                      value: money(subtotalBeforeDiscount),
                    ),
                    if (discountAmount > 0)
                      _CompactTotalLine(
                        label: 'Descuento',
                        value: '-${money(discountAmount)}',
                        valueColor: Colors.red.shade700,
                      ),
                    if (generalDiscountAmount > 0)
                      _CompactTotalLine(
                        label: 'Desc. general',
                        value: '-${money(generalDiscountAmount)}',
                        valueColor: Colors.red.shade700,
                      ),
                    if (includeItbis)
                      _CompactTotalLine(
                        label: 'ITBIS',
                        value: money(itbisAmount),
                      ),
                    if (isAdmin)
                      _CompactTotalLine(
                        label: 'Utilidad',
                        value: money(utilityAmount),
                        valueColor: const Color(0xFF1957E6),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onDoubleTap: onApplyGeneralDiscount,
                      child: FilledButton(
                        onPressed: onFinalize,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1957E6),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(70),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Text(
                              'Cobrar',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              money(total),
                              style: const TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 70,
                    height: 70,
                    child: OutlinedButton(
                      onPressed: onOpenHistory,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1957E6),
                        side: const BorderSide(color: Color(0xFFD3E0E7)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(7),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.receipt_long_outlined),
                          SizedBox(height: 4),
                          Text(
                            'Ventas',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFD3E0E7),
                    width: 1.1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF1FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        itemCountText,
                        style: const TextStyle(
                          color: Color(0xFF1957E6),
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'ITBIS',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF647985),
                          ),
                        ),
                        Transform.scale(
                          scale: 0.72,
                          child: Switch.adaptive(
                            value: includeItbis,
                            onChanged: onToggleItbis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        _DesktopPanelSwitchAction(
                          label: 'Notas',
                          value: hasNote,
                          onTap: onOpenNote,
                        ),
                      ],
                    ),
                    TextButton.icon(
                      onPressed: onClear,
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Cancelar venta'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red.shade600,
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DesktopFiscalInvoicePanel extends StatefulWidget {
  const _DesktopFiscalInvoicePanel({
    required this.voucherType,
    required this.voucherNumber,
    required this.dueDate,
    required this.customerTaxId,
    required this.customerName,
    required this.requiresTaxId,
    required this.onTypeChanged,
    required this.onVoucherNumberChanged,
    required this.onCustomerTaxIdChanged,
    required this.onCustomerNameChanged,
    required this.onPickDueDate,
  });

  final String voucherType;
  final String voucherNumber;
  final DateTime? dueDate;
  final String customerTaxId;
  final String customerName;
  final bool requiresTaxId;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onVoucherNumberChanged;
  final ValueChanged<String> onCustomerTaxIdChanged;
  final ValueChanged<String> onCustomerNameChanged;
  final VoidCallback onPickDueDate;

  @override
  State<_DesktopFiscalInvoicePanel> createState() =>
      _DesktopFiscalInvoicePanelState();
}

class _DesktopFiscalInvoicePanelState
    extends State<_DesktopFiscalInvoicePanel> {
  late final TextEditingController _voucherCtrl;
  late final TextEditingController _taxIdCtrl;
  late final TextEditingController _customerNameCtrl;

  @override
  void initState() {
    super.initState();
    _voucherCtrl = TextEditingController(text: widget.voucherNumber);
    _taxIdCtrl = TextEditingController(text: widget.customerTaxId);
    _customerNameCtrl = TextEditingController(text: widget.customerName);
  }

  @override
  void didUpdateWidget(covariant _DesktopFiscalInvoicePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController(_voucherCtrl, widget.voucherNumber);
    _syncController(_taxIdCtrl, widget.customerTaxId);
    _syncController(_customerNameCtrl, widget.customerName);
  }

  void _syncController(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.text = value;
    controller.selection = TextSelection.collapsed(offset: value.length);
  }

  @override
  void dispose() {
    _voucherCtrl.dispose();
    _taxIdCtrl.dispose();
    _customerNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dueDateText = widget.dueDate == null
        ? 'Seleccionar fecha'
        : DateFormat('dd/MM/yyyy').format(widget.dueDate!);
    final border = Border.all(color: const Color(0xFFD3E0E7), width: 1.1);

    return Container(
      height: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFFF8FBFF),
        border: Border(left: BorderSide(color: Color(0xFFD3E0E7))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: border,
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF1FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.fact_check_outlined,
                      color: Color(0xFF1957E6),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Factura fiscal',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF132337),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Datos del comprobante',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF647985),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: border,
                ),
                child: ListView(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: widget.voucherType,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de comprobante',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'B01',
                          child: Text('B01 - Crédito fiscal'),
                        ),
                        DropdownMenuItem(
                          value: 'B02',
                          child: Text('B02 - Consumidor final'),
                        ),
                        DropdownMenuItem(
                          value: 'B14',
                          child: Text('B14 - Régimen especial'),
                        ),
                        DropdownMenuItem(
                          value: 'B15',
                          child: Text('B15 - Gubernamental'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) widget.onTypeChanged(value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _voucherCtrl,
                      onChanged: widget.onVoucherNumberChanged,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Número de comprobante / NCF',
                        hintText: 'Ej. B0100000001',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: widget.onPickDueDate,
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(dueDateText),
                      ),
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        foregroundColor: const Color(0xFF132337),
                        side: const BorderSide(color: Color(0xFFD3E0E7)),
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _taxIdCtrl,
                      onChanged: widget.onCustomerTaxIdChanged,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: widget.requiresTaxId
                            ? 'RNC / Cédula fiscal'
                            : 'RNC / Cédula (opcional)',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _customerNameCtrl,
                      onChanged: widget.onCustomerNameChanged,
                      decoration: const InputDecoration(
                        labelText: 'Razón social / cliente fiscal',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    if (widget.requiresTaxId) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Este tipo de comprobante requiere RNC o cédula fiscal del cliente.',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF647985),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopPanelSwitchAction extends StatelessWidget {
  const _DesktopPanelSwitchAction({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: value
                    ? const Color(0xFF1957E6)
                    : const Color(0xFF647985),
              ),
            ),
            Transform.scale(
              scale: 0.72,
              child: Switch.adaptive(value: value, onChanged: (_) => onTap()),
            ),
          ],
        ),
      ),
    );
  }
}

class _CatalogLineActionButton extends StatelessWidget {
  const _CatalogLineActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final background = filled ? const Color(0xFF1957E6) : Colors.white;
    final foreground = filled ? Colors.white : const Color(0xFF1957E6);
    return SizedBox(
      height: 42,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          side: BorderSide(
            color: filled ? const Color(0xFF1957E6) : const Color(0xFFBBD0FF),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12.2,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
      ),
    );
  }
}

class _DesktopCategoryStrip extends StatelessWidget {
  const _DesktopCategoryStrip({
    required this.categories,
    required this.allProducts,
    required this.managedCategories,
    required this.selectedCategory,
    required this.onSelectCategory,
  });

  final List<String> categories;
  final List<ProductModel> allProducts;
  final List<InventoryCategoryModel> managedCategories;
  final String? selectedCategory;
  final ValueChanged<String?> onSelectCategory;

  ProductModel? _thumbnailProduct(String category) {
    for (final product in allProducts) {
      if (product.categoriaLabel == category) return product;
    }
    return null;
  }

  InventoryCategoryModel? _managedCategory(String category) {
    final target = category.trim().toLowerCase();
    for (final item in managedCategories) {
      if (item.name.trim().toLowerCase() == target) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hasFilter = selectedCategory != null;
    final totalItems = categories.length + (hasFilter ? 1 : 0);

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: totalItems,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          if (hasFilter && index == 0) {
            return SizedBox(
              width: 76,
              child: Material(
                color: const Color(0xFF1957E6),
                borderRadius: BorderRadius.circular(7),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onSelectCategory(null),
                  child: const Center(
                    child: Text(
                      'Limpiar',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }

          final categoryIndex = hasFilter ? index - 1 : index;
          final category = categories[categoryIndex];
          final product = _thumbnailProduct(category);
          final managedCategory = _managedCategory(category);
          return _DesktopCategoryStripItem(
            label: category,
            product: product,
            managedCategory: managedCategory,
            selected: selectedCategory == category,
            onTap: () => onSelectCategory(category),
          );
        },
      ),
    );
  }
}

class _DesktopCategoryStripItem extends StatelessWidget {
  const _DesktopCategoryStripItem({
    required this.label,
    required this.product,
    required this.managedCategory,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final ProductModel? product;
  final InventoryCategoryModel? managedCategory;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = product?.displayFotoUrl?.trim() ?? '';
    final categoryImageBytes = _decodeManagedCategoryImage(
      managedCategory?.imageBase64,
    );
    final normalizedLabel = label.trim().toUpperCase();
    final tileWidth = (normalizedLabel.length * 6.3 + 48).clamp(108.0, 236.0);

    return SizedBox(
      width: tileWidth,
      child: Material(
        color: selected ? const Color(0xFFEAF1FF) : Colors.white,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: selected
                    ? const Color(0xFF1957E6)
                    : const Color(0xFFD3E0E7),
                width: selected ? 1.2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFCFE0FF)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0B2A3A).withValues(alpha: 0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: categoryImageBytes != null
                      ? Image.memory(categoryImageBytes, fit: BoxFit.cover)
                      : imageUrl.isEmpty || product == null
                      ? const Icon(
                          Icons.inventory_2_outlined,
                          color: Color(0xFF8DA2B4),
                          size: 15,
                        )
                      : ProductNetworkImage(
                          imageUrl: imageUrl,
                          productId: product!.id,
                          productName: product!.nombre,
                          originalUrl: product!.originalFotoUrl,
                          fit: BoxFit.cover,
                          loading: const SizedBox.shrink(),
                          fallback: const Icon(
                            Icons.inventory_2_outlined,
                            color: Color(0xFF8DA2B4),
                            size: 15,
                          ),
                        ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    normalizedLabel,
                    maxLines: 2,
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: const Color(0xFF152238),
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                      fontSize: 10.2,
                      height: 1.0,
                    ),
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

Uint8List? _decodeManagedCategoryImage(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  try {
    final payload = raw.contains(',') ? raw.split(',').last : raw;
    return base64Decode(payload);
  } catch (_) {
    return null;
  }
}

class _DesktopProductCard extends StatelessWidget {
  const _DesktopProductCard({
    required this.product,
    required this.money,
    required this.onTap,
  });

  final ProductModel product;
  final String Function(double) money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stock = product.stock;
    final stockText = _formatProductStock(stock);
    final stockColor = stock == null
        ? const Color(0xFF64748B)
        : stock <= 0
        ? const Color(0xFFDC2626)
        : const Color(0xFF1957E6);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                (product.displayFotoUrl ?? '').trim().isEmpty
                    ? Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Center(
                          child: Icon(
                            Icons.inventory_2_outlined,
                            size: 24,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      )
                    : ProductNetworkImage(
                        imageUrl: product.displayFotoUrl!,
                        productId: product.id,
                        productName: product.nombre,
                        originalUrl: product.originalFotoUrl,
                        fit: BoxFit.cover,
                        loading: Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Center(
                            child: Icon(
                              Icons.inventory_2_outlined,
                              size: 20,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                        fallback: Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              size: 20,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                      ),
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xD0000000)],
                        stops: [0.30, 1.0],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 5,
                  left: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: stockColor.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      stockText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 9.2,
                        height: 1,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 5,
                  right: 5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.70),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      money(product.precio),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 9.5,
                        height: 1,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 6,
                  right: 6,
                  bottom: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        product.nombre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9.8,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 3,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          product.categoriaLabel,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: const TextStyle(
                            fontSize: 8.2,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            height: 1,
                          ),
                        ),
                      ),
                    ],
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

String _formatProductStock(double? stock) {
  if (stock == null) return 'Disp. --';
  if (stock <= 0) return 'Sin stock';
  final text = stock % 1 == 0
      ? stock.toStringAsFixed(0)
      : stock.toStringAsFixed(2);
  return 'Disp. $text';
}

String _formatAccountingInput(num value) => formatRdAccountingAmount(value);

double? _parseAccountingInput(String raw) {
  var value = raw
      .trim()
      .replaceAll('RD\$', '')
      .replaceAll('rd\$', '')
      .replaceAll(' ', '');
  if (value.isEmpty) return null;
  if (value.contains(',') && value.contains('.')) {
    value = value.replaceAll(',', '');
  } else {
    value = value.replaceAll(',', '.');
  }
  return double.tryParse(value);
}

class _DesktopExternalProductCard extends StatelessWidget {
  const _DesktopExternalProductCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF8FB3FF), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1957E6).withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                const Positioned.fill(
                  left: 0,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 4,
                      height: 86,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xFF1957E6),
                          borderRadius: BorderRadius.horizontal(
                            right: Radius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF1FF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFCFE0FF)),
                        ),
                        child: const Icon(
                          Icons.add_shopping_cart_rounded,
                          color: Color(0xFF1957E6),
                          size: 25,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Sin inventario',
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFF152238),
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Venta manual',
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFF1957E6),
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          height: 1,
                        ),
                      ),
                    ],
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

class _CompactTotalLine extends StatelessWidget {
  const _CompactTotalLine({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF536A78),
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: valueColor ?? const Color(0xFF17212B),
            ),
          ),
        ],
      ),
    );
  }
}

enum _LineDiscountMode { amount, percent }

class _LineEditResult {
  const _LineEditResult({
    required this.qty,
    required this.discountMode,
    required this.discountValue,
  });

  final double qty;
  final _LineDiscountMode discountMode;
  final double discountValue;
}

class _LineEditDialog extends StatefulWidget {
  const _LineEditDialog({
    required this.item,
    required this.money,
    required this.parseAmount,
    required this.formatAmount,
  });

  final CotizacionItem item;
  final String Function(double) money;
  final double? Function(String) parseAmount;
  final String Function(double) formatAmount;

  @override
  State<_LineEditDialog> createState() => _LineEditDialogState();
}

class _LineEditDialogState extends State<_LineEditDialog> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _discountCtrl;
  _LineDiscountMode _mode = _LineDiscountMode.amount;
  String? _error;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _qtyCtrl = TextEditingController(text: _formatQty(item.qty));
    _discountCtrl = TextEditingController(
      text: item.discountUnitAmount > 0
          ? widget.formatAmount(item.discountUnitAmount)
          : '',
    );
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  void _stepQty(double delta) {
    final current = widget.parseAmount(_qtyCtrl.text) ?? widget.item.qty;
    final next = (current + delta).clamp(1.0, 999999.0).toDouble();
    _qtyCtrl.text = _formatQty(next);
    setState(() => _error = null);
  }

  void _submit() {
    final qty = widget.parseAmount(_qtyCtrl.text) ?? 0;
    final discount = widget.parseAmount(_discountCtrl.text) ?? 0;
    final base = widget.item.effectiveOriginalUnitPrice;
    if (qty <= 0) {
      setState(() => _error = 'La cantidad debe ser mayor que cero.');
      return;
    }
    if (discount < 0) {
      setState(() => _error = 'El descuento no puede ser negativo.');
      return;
    }
    if (_mode == _LineDiscountMode.percent && discount > 100) {
      setState(() => _error = 'El porcentaje no puede pasar de 100%.');
      return;
    }
    if (_mode == _LineDiscountMode.amount && discount > base) {
      setState(() => _error = 'El descuento no puede superar el precio.');
      return;
    }
    Navigator.of(context).pop(
      _LineEditResult(qty: qty, discountMode: _mode, discountValue: discount),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _submit,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _submit,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          alignment: Alignment.center,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.nombre,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF142033),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Cantidad',
                          style: TextStyle(
                            color: Color(0xFF52677C),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      _LineEditIconButton(
                        icon: Icons.remove_rounded,
                        onPressed: () => _stepQty(-1),
                      ),
                      const SizedBox(width: 6),
                      SizedBox(
                        width: 92,
                        child: TextField(
                          controller: _qtyCtrl,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: _lineInputDecoration(),
                          onSubmitted: (_) => _submit(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _LineEditIconButton(
                        icon: Icons.add_rounded,
                        onPressed: () => _stepQty(1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Descuento',
                    style: TextStyle(
                      color: Color(0xFF52677C),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      SegmentedButton<_LineDiscountMode>(
                        segments: const [
                          ButtonSegment(
                            value: _LineDiscountMode.percent,
                            label: Text('%'),
                          ),
                          ButtonSegment(
                            value: _LineDiscountMode.amount,
                            label: Text('RD\$'),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (value) {
                          setState(() {
                            _mode = value.first;
                            _error = null;
                          });
                        },
                        style: ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          textStyle: WidgetStateProperty.all(
                            const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _discountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: _lineInputDecoration(
                            hintText: _mode == _LineDiscountMode.percent
                                ? '0%'
                                : '0.00',
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _submit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(42, 38),
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Icon(Icons.check_rounded, size: 19),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFDC2626),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _lineInputDecoration({String? hintText}) {
    return InputDecoration(
      hintText: hintText,
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFF8FBFF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFD3E0E7)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFD3E0E7)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF1957E6), width: 1.2),
      ),
    );
  }

  String _formatQty(double value) {
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  }
}

class _LineEditIconButton extends StatelessWidget {
  const _LineEditIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFFF3F7FB),
        foregroundColor: const Color(0xFF43566B),
        side: const BorderSide(color: Color(0xFFD8E5F3)),
        fixedSize: const Size(34, 34),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _DesktopTicketItem extends StatefulWidget {
  const _DesktopTicketItem({
    required this.item,
    required this.money,
    required this.onEditLine,
    required this.onMinus,
    required this.onPlus,
    required this.onChangePrice,
    required this.onEdit,
    required this.onRemove,
  });

  final CotizacionItem item;
  final String Function(double) money;
  final VoidCallback onEditLine;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final ValueChanged<double> onChangePrice;
  final VoidCallback? onEdit;
  final VoidCallback onRemove;

  @override
  State<_DesktopTicketItem> createState() => _DesktopTicketItemState();
}

class _DesktopTicketItemState extends State<_DesktopTicketItem> {
  late final TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(
      text: _formatAccountingInput(widget.item.unitPrice),
    );
  }

  @override
  void didUpdateWidget(covariant _DesktopTicketItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.unitPrice != widget.item.unitPrice) {
      _priceCtrl.text = _formatAccountingInput(widget.item.unitPrice);
    }
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final hasDiscount = item.hasDiscount;
    final discountText = widget.money(item.discountAmount);
    final qtyText = item.qty % 1 == 0
        ? item.qty.toStringAsFixed(0)
        : item.qty.toStringAsFixed(2);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onDoubleTap: widget.onEditLine,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: item.isExternal
                ? const Color(0xFFEAF1FF)
                : const Color(0xFFF8FBFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: item.isExternal
                  ? const Color(0xFF8FB3FF)
                  : const Color(0xFFD7E4EB),
              width: 1.05,
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: (item.imageUrl ?? '').trim().isEmpty
                      ? Container(
                          color: item.isExternal
                              ? const Color(0xFFEAF1FF)
                              : theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            item.isExternal
                                ? Icons.edit_note_outlined
                                : Icons.inventory_2_outlined,
                            size: 15,
                            color: item.isExternal
                                ? const Color(0xFF1957E6)
                                : null,
                          ),
                        )
                      : ProductNetworkImage(
                          imageUrl: item.imageUrl!,
                          productId: item.productId,
                          productName: item.nombre,
                          originalUrl: item.imageUrl,
                          fit: BoxFit.cover,
                          loading: Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                          fallback: Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(
                              Icons.broken_image_outlined,
                              size: 14,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    if (hasDiscount || item.isExternal)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (hasDiscount)
                              Text(
                                'desc: $discountText',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            if (item.isExternal)
                              _buildTicketTag(
                                label: 'Manual',
                                backgroundColor: const Color(0xFF1957E6),
                                foregroundColor: Colors.white,
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: TextField(
                  controller: _priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(fontSize: 11),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Precio',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  onTap: () {},
                  onSubmitted: (value) {
                    final parsed = _parseAccountingInput(value);
                    if (parsed != null) {
                      widget.onChangePrice(parsed);
                      _priceCtrl.text = _formatAccountingInput(parsed);
                    }
                  },
                ),
              ),
              if (hasDiscount)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    widget.money(item.effectiveOriginalUnitPrice),
                    style: theme.textTheme.bodySmall?.copyWith(
                      decoration: TextDecoration.lineThrough,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Restar unidad',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onMinus,
                icon: const Icon(Icons.remove, size: 16),
              ),
              SizedBox(
                width: 24,
                child: Text(
                  qtyText,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Sumar unidad',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onPlus,
                icon: const Icon(Icons.add, size: 16),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 96,
                child: Text(
                  widget.money(item.total),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
              if (widget.onEdit != null)
                IconButton(
                  tooltip: 'Editar producto manual',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16),
                ),
              IconButton(
                tooltip: 'Eliminar producto',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onRemove,
                icon: const Icon(Icons.close, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _buildTicketTag({
  required String label,
  required Color backgroundColor,
  required Color foregroundColor,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: foregroundColor,
        fontWeight: FontWeight.w800,
        fontSize: 9,
      ),
    ),
  );
}

class _DesktopSalesTicketFooter extends StatelessWidget {
  const _DesktopSalesTicketFooter({
    required this.tickets,
    required this.activeTicketId,
    required this.onCreateTicket,
    required this.onSwitchTicket,
    required this.onRenameTicket,
    required this.onDeleteTicket,
  });

  final List<_DesktopTicketDraft> tickets;
  final String? activeTicketId;
  final VoidCallback onCreateTicket;
  final ValueChanged<String> onSwitchTicket;
  final ValueChanged<String> onRenameTicket;
  final ValueChanged<String> onDeleteTicket;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 56,
      padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFC),
        border: Border(top: BorderSide(color: const Color(0xFFD6E1E8))),
      ),
      child: Row(
        children: [
          Tooltip(
            message: 'Nuevo ticket',
            child: SizedBox(
              width: 40,
              height: 40,
              child: FilledButton(
                onPressed: onCreateTicket,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: const Color(0xFF1957E6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Icon(Icons.add_rounded, size: 22),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tickets.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final ticket = tickets[index];
                final selected = ticket.id == activeTicketId;
                final count = ticket.items.length;
                return _DesktopFooterTicketChip(
                  label: ticket.label(index),
                  itemCount: count,
                  selected: selected,
                  onTap: () => onSwitchTicket(ticket.id),
                  onRename: () => onRenameTicket(ticket.id),
                  onDelete: () => onDeleteTicket(ticket.id),
                );
              },
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${tickets.length} tickets',
            style: theme.textTheme.labelMedium?.copyWith(
              color: const Color(0xFF476374),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopFooterTicketChip extends StatelessWidget {
  const _DesktopFooterTicketChip({
    required this.label,
    required this.itemCount,
    required this.selected,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final String label;
  final int itemCount;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? const Color(0xFFEAF1FF) : Colors.white;
    final border = selected ? const Color(0xFF1957E6) : const Color(0xFFD6E1E8);
    final fg = selected ? const Color(0xFF1957E6) : const Color(0xFF183548);

    final itemText = itemCount == 1 ? '1 articulo' : '$itemCount articulos';

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 180,
          height: 40,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: selected ? 0.08 : 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 2, 0),
              child: Row(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 16, color: fg),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Text(
                    itemText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF647985),
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    height: 32,
                    child: PopupMenuButton<_FooterTicketAction>(
                      tooltip: 'Opciones del ticket',
                      padding: EdgeInsets.zero,
                      color: const Color(0xFFFFFFFF),
                      iconSize: 17,
                      position: PopupMenuPosition.under,
                      onSelected: (action) {
                        switch (action) {
                          case _FooterTicketAction.rename:
                            onRename();
                            return;
                          case _FooterTicketAction.delete:
                            onDelete();
                            return;
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: _FooterTicketAction.rename,
                          child: _FooterTicketMenuEntry(
                            icon: Icons.edit_outlined,
                            label: 'Editar',
                          ),
                        ),
                        PopupMenuItem(
                          value: _FooterTicketAction.delete,
                          child: _FooterTicketMenuEntry(
                            icon: Icons.delete_outline,
                            label: 'Eliminar',
                          ),
                        ),
                      ],
                      icon: Icon(
                        Icons.more_vert_rounded,
                        color: selected
                            ? const Color(0xFF1957E6)
                            : const Color(0xFF647985),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _FooterTicketAction { rename, delete }

class _FooterTicketMenuEntry extends StatelessWidget {
  const _FooterTicketMenuEntry({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [Icon(icon, size: 18), const SizedBox(width: 10), Text(label)],
    );
  }
}

class _DesktopTicketDraft {
  const _DesktopTicketDraft({
    required this.id,
    required this.title,
    required this.items,
    required this.selectedClientId,
    required this.selectedClientName,
    required this.selectedClientPhone,
    required this.note,
    required this.includeItbis,
    required this.fiscalVoucherType,
    required this.fiscalVoucherNumber,
    required this.fiscalVoucherDueDate,
    required this.fiscalCustomerTaxId,
    required this.fiscalCustomerName,
    required this.globalDiscountAmount,
    required this.editingId,
    required this.editingCreatedAt,
    required this.selectedCategory,
    required this.searchQuery,
  });

  factory _DesktopTicketDraft.empty({
    required String id,
    required String title,
  }) {
    return _DesktopTicketDraft(
      id: id,
      title: title,
      items: const [],
      selectedClientId: null,
      selectedClientName: 'Sin cliente',
      selectedClientPhone: null,
      note: '',
      includeItbis: false,
      fiscalVoucherType: 'B01',
      fiscalVoucherNumber: '',
      fiscalVoucherDueDate: null,
      fiscalCustomerTaxId: '',
      fiscalCustomerName: '',
      globalDiscountAmount: 0,
      editingId: null,
      editingCreatedAt: null,
      selectedCategory: null,
      searchQuery: '',
    );
  }

  final String id;
  final String title;
  final List<CotizacionItem> items;
  final String? selectedClientId;
  final String selectedClientName;
  final String? selectedClientPhone;
  final String note;
  final bool includeItbis;
  final String fiscalVoucherType;
  final String fiscalVoucherNumber;
  final DateTime? fiscalVoucherDueDate;
  final String fiscalCustomerTaxId;
  final String fiscalCustomerName;
  final double globalDiscountAmount;
  final String? editingId;
  final DateTime? editingCreatedAt;
  final String? selectedCategory;
  final String searchQuery;

  _DesktopTicketDraft copyWith({
    String? id,
    String? title,
    List<CotizacionItem>? items,
    String? selectedClientId,
    String? selectedClientName,
    String? selectedClientPhone,
    String? note,
    bool? includeItbis,
    String? fiscalVoucherType,
    String? fiscalVoucherNumber,
    DateTime? fiscalVoucherDueDate,
    String? fiscalCustomerTaxId,
    String? fiscalCustomerName,
    double? globalDiscountAmount,
    String? editingId,
    DateTime? editingCreatedAt,
    String? selectedCategory,
    String? searchQuery,
  }) {
    return _DesktopTicketDraft(
      id: id ?? this.id,
      title: title ?? this.title,
      items: items ?? this.items,
      selectedClientId: selectedClientId ?? this.selectedClientId,
      selectedClientName: selectedClientName ?? this.selectedClientName,
      selectedClientPhone: selectedClientPhone ?? this.selectedClientPhone,
      note: note ?? this.note,
      includeItbis: includeItbis ?? this.includeItbis,
      fiscalVoucherType: fiscalVoucherType ?? this.fiscalVoucherType,
      fiscalVoucherNumber: fiscalVoucherNumber ?? this.fiscalVoucherNumber,
      fiscalVoucherDueDate: fiscalVoucherDueDate ?? this.fiscalVoucherDueDate,
      fiscalCustomerTaxId: fiscalCustomerTaxId ?? this.fiscalCustomerTaxId,
      fiscalCustomerName: fiscalCustomerName ?? this.fiscalCustomerName,
      globalDiscountAmount: globalDiscountAmount ?? this.globalDiscountAmount,
      editingId: editingId ?? this.editingId,
      editingCreatedAt: editingCreatedAt ?? this.editingCreatedAt,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  String label(int index) {
    final client = selectedClientName.trim();
    if (client.isNotEmpty && client != 'Sin cliente') return client;
    return title.isEmpty ? 'Ticket ${index + 1}' : title;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'items': items.map((item) => item.toMap()).toList(),
    'selectedClientId': selectedClientId,
    'selectedClientName': selectedClientName,
    'selectedClientPhone': selectedClientPhone,
    'note': note,
    'includeItbis': includeItbis,
    'fiscalVoucherType': fiscalVoucherType,
    'fiscalVoucherNumber': fiscalVoucherNumber,
    'fiscalVoucherDueDate': fiscalVoucherDueDate?.toIso8601String(),
    'fiscalCustomerTaxId': fiscalCustomerTaxId,
    'fiscalCustomerName': fiscalCustomerName,
    'globalDiscountAmount': globalDiscountAmount,
    'editingId': editingId,
    'editingCreatedAt': editingCreatedAt?.toIso8601String(),
    'selectedCategory': selectedCategory,
    'searchQuery': searchQuery,
  };

  factory _DesktopTicketDraft.fromMap(Map<String, dynamic> map) {
    final rawItems = (map['items'] as List?) ?? const [];
    return _DesktopTicketDraft(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      items: rawItems
          .whereType<Map>()
          .map((row) => CotizacionItem.fromMap(row.cast<String, dynamic>()))
          .toList(growable: false),
      selectedClientId: map['selectedClientId']?.toString(),
      selectedClientName: (map['selectedClientName'] ?? 'Sin cliente')
          .toString(),
      selectedClientPhone: map['selectedClientPhone']?.toString(),
      note: (map['note'] ?? '').toString(),
      includeItbis: map['includeItbis'] == true,
      fiscalVoucherType: (map['fiscalVoucherType'] ?? 'B01').toString(),
      fiscalVoucherNumber: (map['fiscalVoucherNumber'] ?? '').toString(),
      fiscalVoucherDueDate: DateTime.tryParse(
        (map['fiscalVoucherDueDate'] ?? '').toString(),
      ),
      fiscalCustomerTaxId: (map['fiscalCustomerTaxId'] ?? '').toString(),
      fiscalCustomerName: (map['fiscalCustomerName'] ?? '').toString(),
      globalDiscountAmount:
          (map['globalDiscountAmount'] as num?)?.toDouble() ?? 0,
      editingId: map['editingId']?.toString(),
      editingCreatedAt: DateTime.tryParse(
        (map['editingCreatedAt'] ?? '').toString(),
      ),
      selectedCategory: map['selectedCategory']?.toString(),
      searchQuery: (map['searchQuery'] ?? '').toString(),
    );
  }
}

enum _DiscountType { percent, fixed }

class _AiNoteSuggestion {
  const _AiNoteSuggestion({
    required this.corrected,
    required this.professional,
  });

  final String corrected;
  final String professional;
}

class _TicketCompactItem extends StatefulWidget {
  const _TicketCompactItem({
    required this.item,
    required this.money,
    required this.showCost,
    required this.onEditLine,
    required this.onMinus,
    required this.onPlus,
    required this.onChangeQty,
    required this.onChangePrice,
    required this.onEdit,
    required this.onRemove,
  });

  final CotizacionItem item;
  final String Function(double) money;
  final bool showCost;
  final VoidCallback onEditLine;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final ValueChanged<double> onChangeQty;
  final ValueChanged<double> onChangePrice;
  final VoidCallback? onEdit;
  final VoidCallback onRemove;

  @override
  State<_TicketCompactItem> createState() => _TicketCompactItemState();
}

class _TicketCompactItemState extends State<_TicketCompactItem> {
  late final TextEditingController _priceCtrl;
  late final TextEditingController _qtyCtrl;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(
      text: _formatAccountingInput(widget.item.unitPrice),
    );
    _qtyCtrl = TextEditingController(
      text: widget.item.qty % 1 == 0
          ? widget.item.qty.toStringAsFixed(0)
          : widget.item.qty.toStringAsFixed(2),
    );
  }

  @override
  void didUpdateWidget(covariant _TicketCompactItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.unitPrice != widget.item.unitPrice) {
      _priceCtrl.text = _formatAccountingInput(widget.item.unitPrice);
    }
    if (oldWidget.item.qty != widget.item.qty) {
      _qtyCtrl.text = widget.item.qty % 1 == 0
          ? widget.item.qty.toStringAsFixed(0)
          : widget.item.qty.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasDiscount = item.hasDiscount;
    final discountText = widget.money(item.discountAmount);
    final theme = Theme.of(context);
    final costSnapshot = item.costUnit ?? item.externalCostUnit;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 0.5),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: widget.onEditLine,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 670),
            child: SizedBox(
              height: 34,
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: (item.imageUrl ?? '').trim().isEmpty
                          ? Container(
                              color: item.isExternal
                                  ? theme.colorScheme.primaryContainer
                                  : theme.colorScheme.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: Icon(
                                item.isExternal
                                    ? Icons.edit_note_outlined
                                    : Icons.inventory_2_outlined,
                                size: 12,
                                color: item.isExternal
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            )
                          : ProductNetworkImage(
                              imageUrl: item.imageUrl!,
                              productId: item.productId,
                              productName: item.nombre,
                              originalUrl: item.imageUrl,
                              fit: BoxFit.cover,
                              loading: Container(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                              ),
                              fallback: Container(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.broken_image_outlined,
                                  size: 12,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 150,
                    child: Text(
                      item.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 10.2,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 72,
                    child: TextField(
                      controller: _priceCtrl,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 9.8,
                        fontWeight: FontWeight.w700,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Precio',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 6,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) {
                        final next = _parseAccountingInput(value);
                        if (next != null) {
                          widget.onChangePrice(next);
                          _priceCtrl.text = _formatAccountingInput(next);
                        }
                      },
                    ),
                  ),
                  if (widget.onEdit != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minHeight: 20,
                        minWidth: 20,
                      ),
                      splashRadius: 10,
                      tooltip: 'Editar producto manual',
                      onPressed: widget.onEdit,
                      icon: const Icon(Icons.edit_outlined, size: 13),
                    )
                  else
                    const SizedBox(width: 20),
                  const SizedBox(width: 4),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minHeight: 20,
                      minWidth: 20,
                    ),
                    splashRadius: 10,
                    onPressed: widget.onMinus,
                    icon: const Icon(Icons.remove_circle_outline, size: 14),
                  ),
                  SizedBox(
                    width: 36,
                    child: TextField(
                      controller: _qtyCtrl,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 9.8,
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 6,
                        ),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (value) {
                        final next = double.tryParse(value.trim());
                        if (next != null) widget.onChangeQty(next);
                      },
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minHeight: 20,
                      minWidth: 20,
                    ),
                    splashRadius: 10,
                    onPressed: widget.onPlus,
                    icon: const Icon(Icons.add_circle_outline, size: 14),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 78,
                    child: Text(
                      widget.money(item.total),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 10.3,
                        height: 1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (hasDiscount)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _TicketInlineMeta(
                        label: 'Desc',
                        value: discountText,
                        color: Colors.red.shade700,
                      ),
                    ),
                  if (widget.showCost && costSnapshot != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _TicketInlineMeta(
                        label: 'Costo',
                        value: widget.money(costSnapshot),
                      ),
                    ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minHeight: 20,
                      minWidth: 20,
                    ),
                    splashRadius: 10,
                    onPressed: widget.onRemove,
                    icon: const Icon(Icons.close, size: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TicketInlineMeta extends StatelessWidget {
  const _TicketInlineMeta({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor =
        color ?? Theme.of(context).colorScheme.onSurfaceVariant;

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: effectiveColor,
        ),
        children: [
          TextSpan(text: '$label '),
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
