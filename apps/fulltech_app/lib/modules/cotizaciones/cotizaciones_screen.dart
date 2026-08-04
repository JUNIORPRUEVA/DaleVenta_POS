import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/api/env.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/app_role.dart';
import '../../core/cache/fulltech_cache_manager.dart';
import '../../core/cache/local_json_cache.dart';
import '../../core/company/company_settings_model.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/design_system/icons/app_icon.dart';
import '../../core/design_system/icons/app_icons.dart';
import '../../core/errors/api_exception.dart';
import '../../core/models/user_model.dart';
import '../../core/models/product_model.dart';
import '../../core/printing/unified_ticket_printer.dart';
import '../../core/realtime/catalog_realtime_service.dart';
import '../../core/routing/app_route_observer.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/fulltech_dialog.dart';
import '../../core/widgets/fulltech_page_header.dart';
import '../../core/widgets/pdf_action_menu.dart';
import '../../core/widgets/responsive_shell.dart';
import '../../core/widgets/product_network_image.dart';
import '../../features/catalogo/application/catalog_controller.dart';
import '../../features/catalogo/data/catalog_repository.dart';
import '../../features/products/ui/inventory_module_pages.dart';
import '../cash/cash_repository.dart';
import '../cash/cash_turn_menu_button.dart';
import '../clientes/cliente_model.dart';
import '../clientes/cliente_form_screen.dart';
import '../ventas/data/ventas_repository.dart';
import '../ventas/application/ventas_controller.dart';
import '../ventas/sales_credit_screen.dart';
import '../ventas/sales_models.dart';
import '../ventas/utils/sales_pdf_service.dart';
import 'ai/application/quotation_ai_controller.dart';
import 'ai/domain/models/ai_warning.dart';
import 'ai/domain/models/quotation_context.dart';
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
  final Set<String> _selectedCategories = <String>{};

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
  bool _showDesktopCalculator = false;
  bool _showMobileTicketDropdown = false;
  bool _mobileSearchOpen = false;

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
    final qp = _safeRouteUri()?.queryParameters;
    if (qp == null) return;
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

    final qp = _safeRouteUri()?.queryParameters;
    if (qp == null) return;
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

    if (_productos.isEmpty) {
      final cached = await ref
          .read(catalogRepositoryProvider)
          .getCachedProducts();
      if (cached.isNotEmpty && mounted) {
        final catalogVersion = buildCatalogSyncVersion(cached);
        final syncedRows = applyCatalogSyncVersion(cached, catalogVersion);
        setState(() {
          _productos = syncedRows;
          _loadingProducts = false;
          _error = null;
        });
        Future<void>.microtask(
          () => FulltechImageCacheManager.warmImageUrls(
            syncedRows.map((item) => item.displayFotoUrl),
          ),
        );
      }
    }

    if (!silent && _productos.isEmpty) {
      setState(() {
        _loadingProducts = true;
        _error = null;
      });
    }

    try {
      final rows = await ref
          .read(catalogRepositoryProvider)
          .fetchProducts(forceRefresh: forceRemote, silent: true);
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

  bool get _hasCategoryFilter => _selectedCategories.isNotEmpty;

  bool _setEquals(Set<String> left, Set<String> right) {
    if (left.length != right.length) return false;
    for (final value in left) {
      if (!right.contains(value)) return false;
    }
    return true;
  }

  String? get _selectedCategoryLabel {
    if (_selectedCategories.isEmpty) return null;
    return _selectedCategories.join(', ');
  }

  List<ProductModel> get _visibleProducts {
    final query = _searchCtrl.text.trim().toLowerCase();
    return _productos.where((product) {
      if (_selectedCategories.isNotEmpty &&
          !_selectedCategories.contains(product.categoriaLabel)) {
        return false;
      }
      if (query.isEmpty) return true;
      final code = (product.codigo ?? '').trim().toLowerCase();
      return product.nombre.toLowerCase().contains(query) ||
          product.categoriaLabel.toLowerCase().contains(query) ||
          code.contains(query);
    }).toList();
  }

  void _submitSearchAndAddFirstVisibleProduct() {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      for (final product in _productos) {
        final code = (product.codigo ?? '').trim().toLowerCase();
        if (code.isNotEmpty && code == query) {
          _addProduct(product);
          _searchCtrl.clear();
          _commitEditorChange(() {});
          return;
        }
      }
    }

    final visible = _visibleProducts;
    if (visible.isEmpty) {
      return;
    }
    _addProduct(visible.first);
    _searchCtrl.clear();
    _commitEditorChange(() {});
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
      selectedCategories: _selectedCategories.toList(growable: false),
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
    _selectedCategories
      ..clear()
      ..addAll(draft.selectedCategories);
    _searchCtrl.text = draft.searchQuery;
  }

  void _resetEditorState() {
    _items.clear();
    _searchCtrl.clear();
    _selectedCategories.clear();
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
        _selectedCategories.isNotEmpty;
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

  void _toggleMobileItbis() {
    if (_includeItbis) {
      _commitEditorChange(() => _setItbisEnabled(false));
      return;
    }
    unawaited(_openMobileFiscalInvoicePanel());
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
      _showMobileTicketDropdown = false;
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
      _showMobileTicketDropdown = false;
      _replaceEditorStateFromDraft(next);
    });
    _schedulePersistEditorDraft();
    unawaited(_syncQuotationAi());
  }

  Future<void> _renameDesktopTicket(String id) async {
    final ticket = _findDesktopTicket(id);
    if (ticket == null) return;
    if (_showMobileTicketDropdown) {
      setState(() => _showMobileTicketDropdown = false);
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
    }
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
    if (_showMobileTicketDropdown) {
      setState(() => _showMobileTicketDropdown = false);
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
    }
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
      _commitEditorChange(() {
        _showMobileTicketDropdown = false;
        _resetEditorState();
      });
      return;
    }

    setState(() {
      _writeActiveDesktopDraft();
      final index = _desktopTickets.indexWhere((ticket) => ticket.id == id);
      if (index < 0) return;
      final nextTickets = [..._desktopTickets]..removeAt(index);
      _desktopTickets = nextTickets;
      _showMobileTicketDropdown = nextTickets.length > 1
          ? _showMobileTicketDropdown
          : false;
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

  void _toggleDesktopCalculator() {
    setState(() {
      final next = !_showDesktopCalculator;
      _showDesktopCalculator = next;
      if (next) {
        _showDesktopManualItemForm = false;
        _desktopManualEditIndex = null;
      }
    });
  }

  void _publishDesktopShellFooter() {
    final signature = _desktopFooterSignature();
    if (_lastPublishedDesktopFooterSignature == signature) return;
    _lastPublishedDesktopFooterSignature = signature;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = _safeRouteUri()?.toString();
      if (route == null) return;
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

  Uri? _safeRouteUri() {
    try {
      return GoRouterState.of(context).uri;
    } catch (_) {
      return null;
    }
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

  Future<void> _openMobileActionsDrawer() async {
    final action = await showGeneralDialog<_MobileQuickAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Menu de acciones',
      barrierColor: Colors.black.withValues(alpha: 0.22),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) {
        final theme = Theme.of(context);
        Widget actionTile({
          required IconData icon,
          required String label,
          required _MobileQuickAction value,
          Color? color,
          bool showDot = false,
        }) {
          return ListTile(
            minTileHeight: 58,
            dense: true,
            visualDensity: VisualDensity.standard,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            title: Text(
              label,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: color ?? const Color(0xFF17263A),
                letterSpacing: 0,
              ),
            ),
            leading: showDot
                ? Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  )
                : null,
            trailing: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: (color ?? theme.colorScheme.primary).withValues(
                  alpha: 0.08,
                ),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: (color ?? theme.colorScheme.primary).withValues(
                    alpha: 0.18,
                  ),
                ),
              ),
              child: Icon(
                icon,
                color: color ?? theme.colorScheme.primary,
                size: 18,
              ),
            ),
            onTap: () => Navigator.of(context).pop(value),
          );
        }

        return Align(
          alignment: Alignment.centerRight,
          child: SafeArea(
            child: Material(
              color: theme.colorScheme.surface,
              child: SizedBox(
                width: (MediaQuery.sizeOf(context).width * 0.72).clamp(
                  270.0,
                  318.0,
                ),
                height: double.infinity,
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
                          child: Row(
                            children: [
                              Icon(
                                Icons.keyboard_double_arrow_left_rounded,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Acciones',
                                  textAlign: TextAlign.right,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Cerrar',
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(6, 8, 6, 82),
                            children: [
                              actionTile(
                                icon: Icons.add_circle_outline_rounded,
                                label: 'Nuevo ticket',
                                value: _MobileQuickAction.newTicket,
                                showDot: _desktopTickets.length > 1,
                              ),
                              actionTile(
                                icon: Icons.person_outline,
                                label: 'Cliente',
                                value: _MobileQuickAction.client,
                                showDot: (_selectedClientId ?? '')
                                    .trim()
                                    .isNotEmpty,
                              ),
                              actionTile(
                                icon: Icons.add_box_outlined,
                                label: 'Venta rapida',
                                value: _MobileQuickAction.externalItem,
                              ),
                              actionTile(
                                icon: Icons.request_quote_outlined,
                                label: 'Cotizar',
                                value: _MobileQuickAction.quote,
                              ),
                              actionTile(
                                icon: Icons.list_alt_outlined,
                                label: 'Lista de cotizaciones',
                                value: _MobileQuickAction.quoteHistory,
                              ),
                              actionTile(
                                icon: Icons.picture_as_pdf_outlined,
                                label: 'Ver PDF',
                                value: _MobileQuickAction.pdf,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: _AnimatedCalculatorFab(
                        compact: true,
                        filled: true,
                        open: false,
                        onTap: () => Navigator.of(
                          context,
                        ).pop(_MobileQuickAction.calculator),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
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
          child: child,
        );
      },
    );

    if (action == null || !mounted) return;
    await _handleMobileQuickAction(action);
  }

  Future<void> _openMobileCalculator() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Calculadora',
      barrierColor: Colors.black.withValues(alpha: 0.24),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final width = (MediaQuery.sizeOf(dialogContext).width * 0.92).clamp(
          320.0,
          420.0,
        );
        return SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: width,
              height: double.infinity,
              child: _DesktopCalculatorPane(
                onClose: () => Navigator.of(dialogContext).pop(),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
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
          child: child,
        );
      },
    );
  }

  Future<void> _openMobileFiscalInvoicePanel() async {
    _commitEditorChange(() => _setItbisEnabled(true));
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Configurar ITBIS',
      barrierColor: Colors.black.withValues(alpha: 0.24),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final width = (MediaQuery.sizeOf(dialogContext).width * 0.92).clamp(
          320.0,
          430.0,
        );
        return SafeArea(
          child: Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: Colors.white,
              child: SizedBox(
                width: width,
                height: double.infinity,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.receipt_long_outlined,
                            color: Color(0xFF1957E6),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'ITBIS y factura fiscal',
                              style: Theme.of(dialogContext)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w900),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
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
                        onVoucherNumberChanged: (value) => _commitEditorChange(
                          () => _fiscalVoucherNumber = value,
                        ),
                        onCustomerTaxIdChanged: (value) => _commitEditorChange(
                          () => _fiscalCustomerTaxId = value,
                        ),
                        onCustomerNameChanged: (value) => _commitEditorChange(
                          () => _fiscalCustomerName = value,
                        ),
                        onPickDueDate: _pickFiscalVoucherDueDate,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          style: FilledButton.styleFrom(
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.zero,
                            ),
                          ),
                          child: const Text('Listo'),
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
      transitionBuilder: (context, animation, secondaryAnimation, child) {
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
          child: child,
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
      case _MobileQuickAction.calculator:
        await _openMobileCalculator();
        return;
      case _MobileQuickAction.newTicket:
        _createNewDesktopTicket();
        return;
      case _MobileQuickAction.pdf:
        await _openPdfPreview();
        return;
      case _MobileQuickAction.quote:
        await _saveCurrentAsQuotation();
        return;
      case _MobileQuickAction.quoteHistory:
        if (!mounted) return;
        context.go(Routes.cotizacionesHistorial);
        return;
      case _MobileQuickAction.clear:
        if (!_hasEditorContent) return;
        await _confirmAndClearSale();
        return;
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
      if (widget.returnSavedQuotation) {
        final savedQuotation = editingId.isNotEmpty && _isUuid(editingId)
            ? await repository.update(editingId, draft)
            : await repository.create(draft.copyWith(id: ''));

        if (!mounted) return;
        Navigator.of(context).pop(savedQuotation);
        return;
      }

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
                _selectedCategoryLabel ??
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
      productType: _selectedCategoryLabel,
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
        _showDesktopCalculator = false;
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
    final selected = await showGeneralDialog<Set<String>>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Filtros de categorias',
      barrierColor: Colors.black.withValues(alpha: 0.22),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) {
        final categories = _categories;
        final theme = Theme.of(context);
        final draft = Set<String>.from(_selectedCategories);

        return Align(
          alignment: Alignment.centerRight,
          child: StatefulBuilder(
            builder: (context, setModalState) {
              void toggleCategory(String category) {
                setModalState(() {
                  if (!draft.remove(category)) draft.add(category);
                });
              }

              return SafeArea(
                child: Material(
                  color: theme.colorScheme.surface,
                  child: SizedBox(
                    width: (MediaQuery.sizeOf(context).width * 0.84).clamp(
                      292.0,
                      380.0,
                    ),
                    height: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
                          child: Row(
                            children: [
                              Icon(
                                Icons.filter_alt_outlined,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Categorias',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Cerrar',
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: Icon(
                            draft.isEmpty
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            color: draft.isEmpty
                                ? theme.colorScheme.primary
                                : null,
                          ),
                          title: const Text('Todas las categorias'),
                          onTap: () => setModalState(draft.clear),
                        ),
                        Expanded(
                          child: ListView.separated(
                            padding: const EdgeInsets.only(bottom: 10),
                            itemCount: categories.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final category = categories[index];
                              final selectedOption = draft.contains(category);
                              return CheckboxListTile(
                                value: selectedOption,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: Text(
                                  category,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: selectedOption
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                                ),
                                onChanged: (_) => toggleCategory(category),
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () =>
                                      Navigator.pop(context, <String>{}),
                                  style: OutlinedButton.styleFrom(
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.zero,
                                    ),
                                  ),
                                  child: const Text('Todas'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  onPressed: () => Navigator.pop(
                                    context,
                                    Set<String>.from(draft),
                                  ),
                                  style: FilledButton.styleFrom(
                                    shape: const RoundedRectangleBorder(
                                      borderRadius: BorderRadius.zero,
                                    ),
                                  ),
                                  child: Text(
                                    draft.isEmpty
                                        ? 'Aplicar'
                                        : 'Aplicar (${draft.length})',
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
              );
            },
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
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
          child: child,
        );
      },
    );

    if (!mounted || selected == null) return;
    if (_setEquals(selected, _selectedCategories)) return;
    _commitEditorChange(() {
      _selectedCategories
        ..clear()
        ..addAll(selected);
    });
  }

  Future<void> _openNoteDialog() async {
    final controller = TextEditingController(text: _note);

    String? nextNote;
    try {
      nextNote = await showDialog<String>(
        context: context,
        barrierColor: FullTechDialogTokens.overlayColor,
        builder: (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 28,
            vertical: 32,
          ),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Material(
              color: Colors.white,
              elevation: 24,
              shadowColor: Colors.black26,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: const BorderSide(color: Color(0xFFD6E5EE)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF3FF),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: const Color(0xFFCFE0FF)),
                          ),
                          child: const Icon(
                            Icons.sticky_note_2_outlined,
                            color: Color(0xFF1957E6),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Nota de cotización',
                            style: TextStyle(
                              color: Color(0xFF0F2233),
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Cerrar',
                          onPressed: () => Navigator.pop(dialogContext),
                          icon: const Icon(Icons.close_rounded),
                          color: const Color(0xFF52677A),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: controller,
                      autofocus: true,
                      minLines: 6,
                      maxLines: 8,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      textCapitalization: TextCapitalization.sentences,
                      autocorrect: true,
                      enableSuggestions: true,
                      decoration: InputDecoration(
                        hintText: 'Escribe la nota para esta cotización',
                        filled: true,
                        fillColor: const Color(0xFFF7FAFC),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(
                            color: Color(0xFFC6D8E3),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(
                            color: Color(0xFFC6D8E3),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(5),
                          borderSide: const BorderSide(
                            color: Color(0xFF1957E6),
                            width: 1.35,
                          ),
                        ),
                        hintStyle: const TextStyle(color: Color(0xFF6D8194)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Se ordenan espacios, puntuación básica y algunas palabras frecuentes al guardar.',
                      style: TextStyle(color: Color(0xFF64798C), fontSize: 12),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF0E5F6D),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          child: const Text('Cancelar'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: () => Navigator.pop(
                            dialogContext,
                            _autocorrectNoteText(controller.text),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1957E6),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 26,
                              vertical: 13,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(5),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
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
          ),
        ),
      );
    } finally {
      await _disposeControllersSafely([controller]);
    }

    if (nextNote == null || !mounted) return;
    _commitEditorChange(() => _note = _autocorrectNoteText(nextNote!));
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
    bool openingClient = false;
    String? openingClientId;
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
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          final size = MediaQuery.sizeOf(dialogContext);
          final isDesktop = size.width >= _desktopBreakpoint;
          final panelWidth = isDesktop
              ? size.width >= 1600
                    ? 560.0
                    : size.width >= 1280
                    ? 520.0
                    : (size.width * 0.42).clamp(440.0, 540.0)
              : (size.width * 0.90).clamp(320.0, 430.0);

          return StatefulBuilder(
            builder: (context, setStateDialog) {
              Future<ClienteModel?> openClientFormDrawer({
                String? clienteId,
              }) async {
                if (isDesktop) {
                  return openClienteFormAdaptive(
                    context,
                    clienteId: clienteId,
                    useRootNavigator: true,
                  );
                }

                return showGeneralDialog<ClienteModel>(
                  context: context,
                  barrierDismissible: true,
                  barrierLabel: clienteId == null
                      ? 'Crear cliente'
                      : 'Editar cliente',
                  barrierColor: Colors.black.withValues(alpha: 0.22),
                  transitionDuration: const Duration(milliseconds: 240),
                  pageBuilder:
                      (formContext, formAnimation, formSecondaryAnimation) {
                        final width =
                            (MediaQuery.sizeOf(formContext).width * 0.92).clamp(
                              320.0,
                              430.0,
                            );
                        return SafeArea(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: SizedBox(
                              width: width,
                              height: double.infinity,
                              child: ClienteFormScreen(
                                clienteId: clienteId,
                                returnSavedClient: true,
                                compactDialog: true,
                              ),
                            ),
                          ),
                        );
                      },
                  transitionBuilder:
                      (context, animation, secondaryAnimation, child) {
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
                          child: child,
                        );
                      },
                );
              }

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

              Future<void> openClientDetail(ClienteModel client) async {
                final clientId = client.id.trim();
                final clientName = client.nombre.trim();
                final startedAt = DateTime.now();

                if (openingClient) {
                  debugPrint(
                    '[CLIENT_DETAIL] Ignored duplicate open while processing clientId=$openingClientId',
                  );
                  return;
                }

                if (clientId.isEmpty || client.isDeleted) {
                  debugPrint(
                    '[CLIENT_DETAIL] Invalid client. id="$clientId" deleted=${client.isDeleted} name="$clientName"',
                  );
                  if (screenContext.mounted) {
                    ScaffoldMessenger.maybeOf(screenContext)?.showSnackBar(
                      const SnackBar(
                        content: Text(
                          'No se pudo abrir la información del cliente.',
                        ),
                      ),
                    );
                  }
                  return;
                }

                setStateDialog(() {
                  openingClient = true;
                  openingClientId = clientId;
                });

                debugPrint(
                  '[CLIENT_DETAIL] Opening clientId=$clientId name="$clientName"',
                );

                try {
                  searchDebounce?.cancel();
                  debugPrint('[CLIENT_DETAIL] Closing client panel');

                  final navigator = Navigator.of(context);
                  dialogOpen = false;
                  await navigator.maybePop();

                  if (!mounted || !screenContext.mounted) return;

                  final route = Routes.clienteDetail(clientId);
                  debugPrint('[CLIENT_DETAIL] Navigating route=$route');
                  await screenContext.push(route);

                  final elapsedMs = DateTime.now()
                      .difference(startedAt)
                      .inMilliseconds;
                  debugPrint(
                    '[CLIENT_DETAIL] Completed clientId=$clientId elapsedMs=$elapsedMs',
                  );
                } catch (error, stackTrace) {
                  debugPrint(
                    '[CLIENT_DETAIL] Error opening clientId=$clientId: $error',
                  );
                  debugPrintStack(stackTrace: stackTrace);
                  if (!mounted || !screenContext.mounted) return;
                  ScaffoldMessenger.maybeOf(screenContext)?.showSnackBar(
                    const SnackBar(
                      content: Text(
                        'No se pudo abrir la información del cliente. Inténtalo nuevamente.',
                      ),
                    ),
                  );

                  if (dialogOpen) {
                    setStateDialog(() {
                      openingClient = false;
                      openingClientId = null;
                    });
                  }
                }
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
                          final created = await openClientFormDrawer();
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
                                  trailing: openingClientId == client.id
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                          ),
                                        )
                                      : TextButton.icon(
                                          onPressed: openingClient
                                              ? null
                                              : () => unawaited(
                                                  openClientDetail(client),
                                                ),
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
                                  trailing: openingClientId == client.id
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.4,
                                          ),
                                        )
                                      : IconButton(
                                          tooltip: 'Ver cliente',
                                          onPressed: openingClient
                                              ? null
                                              : () => unawaited(
                                                  openClientDetail(client),
                                                ),
                                          icon: const Icon(
                                            Icons.open_in_new_rounded,
                                          ),
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
                      final updated = await openClientFormDrawer(
                        clienteId: clientId,
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

              Widget closeOnEscape({required Widget child}) {
                return CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.escape): () =>
                        Navigator.maybePop(context),
                  },
                  child: Focus(autofocus: true, child: child),
                );
              }

              final panel = SizedBox(
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
                          padding: const EdgeInsets.fromLTRB(20, 18, 16, 14),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                          padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
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
              );

              return Material(
                color: Colors.transparent,
                child: closeOnEscape(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        right: panelWidth,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => Navigator.maybePop(context),
                          child: ClipRect(
                            child: BackdropFilter(
                              filter: ui.ImageFilter.blur(
                                sigmaX: 1.1,
                                sigmaY: 1.1,
                              ),
                              child: Container(
                                color: Colors.white.withValues(alpha: 0.06),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Align(alignment: Alignment.centerRight, child: panel),
                    ],
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

  String _formatDominicanPhone(String? value) {
    final normalized = _normalizeWhatsAppLinkPhone(value);
    if (normalized.length == 11 && normalized.startsWith('1')) {
      final area = normalized.substring(1, 4);
      final first = normalized.substring(4, 7);
      final last = normalized.substring(7, 11);
      return '+1($area)$first-$last';
    }
    return (value ?? '').trim();
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

  String _buildClientInvoiceWhatsAppMessage(SaleModel sale, String pdfUrl) {
    final customerName = (sale.customerName ?? '').trim().isEmpty
        ? 'cliente'
        : sale.customerName!.trim();
    return 'Hola $customerName, te compartimos tu factura en PDF.\n'
        'Este documento corresponde a tu compra en FULLTECH.\n'
        'Puedes abrir el enlace para ver o descargar tu factura.\n'
        'Factura: ${_saleShortId(sale)}\n'
        'Total: ${_money(sale.totalSold)}\n'
        'PDF: $pdfUrl';
  }

  Future<void> _shareRecentSaleInvoiceWithClient({
    required BuildContext launchContext,
    required SaleModel sale,
    required List<int> bytes,
    required String filename,
  }) async {
    try {
      final pdfUrl = await ref
          .read(ventasRepositoryProvider)
          .createInvoicePdfShareLink(
            saleId: sale.id,
            pdfBytes: bytes,
            fileName: filename,
          );

      final uri = Uri(
        scheme: 'whatsapp',
        host: 'send',
        queryParameters: {
          'text': _buildClientInvoiceWhatsAppMessage(sale, pdfUrl),
        },
      );
      if (!launchContext.mounted) return;
      await safeOpenWhatsApp(
        launchContext,
        uri,
        copiedMessage: 'No se pudo abrir WhatsApp. Enlace de factura copiado.',
      );
      if (!launchContext.mounted) return;
      ScaffoldMessenger.maybeOf(launchContext)?.showSnackBar(
        const SnackBar(content: Text('WhatsApp abierto con la factura.')),
      );
    } catch (e) {
      if (!launchContext.mounted) return;
      ScaffoldMessenger.maybeOf(launchContext)?.showSnackBar(
        SnackBar(
          content: Text('No se pudo preparar la factura para WhatsApp: $e'),
        ),
      );
    }
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

  Future<void> _openInventoryFloatingActions() async {
    final action = await showGeneralDialog<_InventoryFloatingAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Acciones de inventario',
      barrierColor: Colors.black.withValues(alpha: 0.16),
      transitionDuration: const Duration(milliseconds: 190),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final width = MediaQuery.sizeOf(dialogContext).width;
        final panelWidth = (width * 0.74).clamp(252.0, 320.0);
        return Align(
          alignment: Alignment.centerRight,
          child: SafeArea(
            child: Material(
              color: Colors.white,
              child: SizedBox(
                width: panelWidth,
                height: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.inventory_2_outlined,
                            color: Color(0xFF0E5261),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Inventario',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Cerrar',
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    _InventoryActionDrawerTile(
                      icon: Icons.add_box_outlined,
                      title: 'Agregar producto',
                      subtitle: 'Crear producto nuevo',
                      onTap: () => Navigator.of(
                        dialogContext,
                      ).pop(_InventoryFloatingAction.addProduct),
                    ),
                    _InventoryActionDrawerTile(
                      icon: Icons.tune_outlined,
                      title: 'Ajustar stock',
                      subtitle: 'Sumar o disminuir existencia',
                      onTap: () => Navigator.of(
                        dialogContext,
                      ).pop(_InventoryFloatingAction.adjustStock),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
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

    if (!mounted || action == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    switch (action) {
      case _InventoryFloatingAction.addProduct:
        await _openInventoryCatalog();
      case _InventoryFloatingAction.adjustStock:
        await _openStockAdjustments();
    }
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
                        onShareWithClient: (menuContext) =>
                            _shareRecentSaleInvoiceWithClient(
                              launchContext: menuContext,
                              sale: sale,
                              bytes: bytes,
                              filename: filename,
                            ),
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
        (_safeRouteUri()?.queryParameters['popOnSave'] ?? '').trim() == '1';

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
            customerId: _selectedClientId,
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

  Widget _buildMobileAppBarSearchField() {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        cursorColor: Colors.white,
        textInputAction: TextInputAction.search,
        onChanged: (_) => _commitEditorChange(() {}),
        onSubmitted: (_) => _submitSearchAndAddFirstVisibleProduct(),
        decoration: InputDecoration(
          hintText: 'Buscar producto',
          hintStyle: TextStyle(
            color: Colors.white.withValues(alpha: .75),
            fontWeight: FontWeight.w600,
          ),
          prefixIcon: const Icon(Icons.search_rounded, color: Colors.white),
          suffixIcon: _searchCtrl.text.trim().isEmpty
              ? null
              : IconButton(
                  tooltip: 'Limpiar',
                  onPressed: () => _commitEditorChange(_searchCtrl.clear),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: .14),
          contentPadding: EdgeInsets.zero,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: .28)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: .28)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.white),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildMobileAppBar(QuotationAiState aiState) {
    final showAiBanner = _shouldShowAiBanner(aiState);
    return CustomAppBar(
      title: 'Facturación',
      titleWidget: _mobileSearchOpen
          ? _buildMobileAppBarSearchField()
          : const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Facturación',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Realiza facturas y cotizacion',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
      fallbackRoute: Routes.ventas,
      preferDrawerLeading: true,
      showLogo: false,
      showDepartmentLabel: false,
      trailing: const SizedBox.shrink(),
      actions: [
        _BorderedAppBarAction(
          tooltip: _mobileSearchOpen ? 'Cerrar búsqueda' : 'Buscar',
          onPressed: () => setState(() {
            _mobileSearchOpen = !_mobileSearchOpen;
            if (!_mobileSearchOpen) {
              _searchCtrl.clear();
            }
          }),
          icon: Icon(
            _mobileSearchOpen ? Icons.close_rounded : Icons.search_rounded,
          ),
        ),
        if (!_mobileSearchOpen) ...[
          Badge(
            isLabelVisible: _hasCategoryFilter,
            smallSize: 8,
            child: _BorderedAppBarAction(
              tooltip: _hasCategoryFilter
                  ? 'Categorías: $_selectedCategoryLabel'
                  : 'Filtrar categorías',
              onPressed: _pickCategory,
              icon: const Icon(Icons.category_outlined),
            ),
          ),
          if (showAiBanner)
            _BorderedAppBarAction(
              tooltip: 'Cerrar alerta',
              onPressed: _closeAiBanner,
              icon: const Icon(Icons.close_rounded),
            ),
          _BorderedAppBarAction(
            tooltip: 'Acciones',
            onPressed: _openMobileActionsDrawer,
            icon: const Icon(Icons.menu_open_rounded),
          ),
        ],
      ],
    );
  }

  Widget _buildProductStrip({double? height}) {
    final resolvedHeight = (height ?? 338).clamp(170.0, 338.0);
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 0),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: SizedBox(
        height: resolvedHeight,
        child: _visibleProducts.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    _searchCtrl.text.trim().isNotEmpty || _hasCategoryFilter
                        ? 'No hay productos con este filtro'
                        : 'El catálogo se mostrará aquí cuando haya productos disponibles',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final columns = width < 340 ? 2 : 3;
                  const spacing = 7.0;
                  final cellWidth =
                      (width - (spacing * (columns - 1))) / columns;
                  final visibleRows = resolvedHeight < 245 ? 2.0 : 3.0;
                  final cellHeight =
                      (constraints.maxHeight - (spacing * (visibleRows - 1))) /
                      visibleRows;
                  return GridView.builder(
                    padding: EdgeInsets.zero,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: spacing,
                      mainAxisSpacing: spacing,
                      childAspectRatio: cellWidth / cellHeight,
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
                  );
                },
              ),
      ),
    );
  }

  Widget _buildTicketLine({
    required CotizacionItem item,
    required int index,
    required bool isAdmin,
    VoidCallback? onAfterCommit,
  }) {
    final official = item.isExternal
        ? null
        : _findOfficialProduct(item.productId);
    final outOfStock =
        official != null && (official.stock == null || official.stock! <= 0);
    return _TicketCompactItem(
      item: item,
      money: _money,
      showCost: isAdmin,
      outOfStock: outOfStock,
      onEditLine: () => _openLineEditor(index),
      onChangePrice: (value) => _setUnitPrice(index, value),
      onEdit: item.isExternal
          ? () => _openExternalItemDialog(editIndex: index)
          : null,
      onRemove: () {
        if (index < 0 || index >= _items.length) return;
        _commitEditorChange(() => _items.removeAt(index));
        onAfterCommit?.call();
      },
    );
  }

  Widget _buildExpandTicketDetailsButton() {
    return SizedBox(
      height: 34,
      child: OutlinedButton.icon(
        onPressed: _items.isEmpty ? null : _openMobileTicketDetails,
        icon: const Icon(Icons.open_in_full_rounded, size: 14),
        label: const Text('Expandir'),
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
      ),
    );
  }

  Widget _buildTicketPanelActionBar() {
    return Container(
      height: 50,
      padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.68),
          ),
        ),
      ),
      child: Row(
        children: [
          _InventoryFloatingButton(onPressed: _openInventoryFloatingActions),
          const Spacer(),
          _buildExpandTicketDetailsButton(),
        ],
      ),
    );
  }

  Widget _buildTicketPanel(UserModel? currentUser) {
    final isAdmin = currentUser?.appRole == AppRole.admin;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.zero,
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
                    padding: const EdgeInsets.fromLTRB(10, 2, 10, 8),
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
                      return _buildTicketLine(
                        item: item,
                        index: index,
                        isAdmin: isAdmin,
                      );
                    },
                  ),
          ),
          _buildTicketPanelActionBar(),
          _buildMobileTotalsFooter(isAdmin: isAdmin),
        ],
      ),
    );
  }

  Widget _buildMobileTotalsFooter({
    required bool isAdmin,
    bool fullscreen = false,
  }) {
    final shouldShowSubtotal = _includeItbis || _discountAmount > 0;
    return Container(
      padding: EdgeInsets.fromLTRB(12, fullscreen ? 6 : 4, 12, 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (shouldShowSubtotal)
            Row(
              children: [
                Text(
                  'Sub ${_money(_subtotalBeforeDiscount)}',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_includeItbis) ...[
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => unawaited(_openMobileFiscalInvoicePanel()),
                    child: Text(
                      'ITBIS ${_money(_itbisAmount)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (_discountAmount > 0)
                  Text(
                    'Desc -${_money(_discountAmount)}',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          if (shouldShowSubtotal) const SizedBox(height: 2),
          GestureDetector(
            onTap: _applyGeneralDiscount,
            behavior: HitTestBehavior.opaque,
            child: Row(
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
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF1957E6),
                            ),
                          )
                        : (_effectiveGeneralDiscountAmount > 0
                              ? Text(
                                  'Rebaja ${_money(_effectiveGeneralDiscountAmount)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
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
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      _money(_total),
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (isAdmin && _effectiveGeneralDiscountAmount > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  'Rebaja ${_money(_effectiveGeneralDiscountAmount)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              SizedBox(
                height: 44,
                child: OutlinedButton.icon(
                  onPressed: _toggleMobileItbis,
                  icon: Icon(
                    _includeItbis
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 20,
                  ),
                  label: const Text('ITBIS'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.standard,
                    minimumSize: const Size(80, 44),
                    tapTargetSize: MaterialTapTargetSize.padded,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    foregroundColor: _includeItbis
                        ? const Color(0xFF1957E6)
                        : Theme.of(context).colorScheme.onSurface,
                    side: BorderSide(
                      color: _includeItbis
                          ? const Color(0xFF1957E6)
                          : Theme.of(context).colorScheme.outlineVariant,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              if (fullscreen) ...[
                SizedBox(
                  width: 38,
                  height: 38,
                  child: IconButton(
                    tooltip: 'Volver',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              SizedBox(
                width: 42,
                height: 38,
                child: IconButton(
                  tooltip: 'Cancelar venta',
                  visualDensity: VisualDensity.standard,
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    disabledForegroundColor: const Color(
                      0xFFDC2626,
                    ).withValues(alpha: 0.34),
                    backgroundColor: const Color(
                      0xFFDC2626,
                    ).withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  onPressed: !_hasEditorContent
                      ? null
                      : () => unawaited(_confirmAndClearSale()),
                  icon: const Icon(Icons.delete_sweep_outlined, size: 22),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: fullscreen ? 140 : 156,
                child: FilledButton.icon(
                  onPressed: _openCheckoutDialog,
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Text(
                    'Cobrar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(142, 38),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    backgroundColor: const Color(0xFF1957E6),
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openMobileTicketDetails() async {
    final isAdmin = ref.read(authStateProvider).user?.appRole == AppRole.admin;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (routeContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              return Scaffold(
                backgroundColor: Theme.of(context).colorScheme.surface,
                body: SafeArea(
                  bottom: false,
                  child: _items.isEmpty
                      ? const Center(child: Text('No hay productos agregados'))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                          itemCount: _items.length,
                          separatorBuilder: (context, index) => Divider(
                            height: 6,
                            thickness: 0.6,
                            color: Theme.of(context).colorScheme.outlineVariant
                                .withValues(alpha: 0.42),
                          ),
                          itemBuilder: (context, index) {
                            if (index < 0 || index >= _items.length) {
                              return const SizedBox.shrink();
                            }
                            final item = _items[index];
                            return _buildTicketLine(
                              item: item,
                              index: index,
                              isAdmin: isAdmin,
                              onAfterCommit: () => setDialogState(() {}),
                            );
                          },
                        ),
                ),
                bottomNavigationBar: SafeArea(
                  top: false,
                  child: _buildMobileTotalsFooter(
                    isAdmin: isAdmin,
                    fullscreen: true,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }

  Widget _buildMobileTicketInfoBar() {
    final ticketNumber = _desktopTickets.indexWhere(
      (ticket) => ticket.id == _activeDesktopTicketId,
    );
    final clientLabel = _selectedClientName.trim().isEmpty
        ? 'Sin cliente'
        : _selectedClientName.trim();
    final ticketLabel = _activeTicketLabel;
    final hasClient = clientLabel != 'Sin cliente';
    final primaryLabel = ticketLabel.isEmpty
        ? 'Ticket ${ticketNumber < 0 ? 1 : ticketNumber + 1}'
        : ticketLabel;
    final canExpandTickets = _desktopTickets.length > 1;
    final clientPhone = (_selectedClientPhone ?? '').trim();
    final formattedClientPhone = _formatDominicanPhone(clientPhone);
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.32),
        ),
      ),
      child: InkWell(
        onTap: canExpandTickets
            ? () => setState(
                () => _showMobileTicketDropdown = !_showMobileTicketDropdown,
              )
            : null,
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      hasClient ? 'Cliente: $clientLabel' : primaryLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  if (hasClient && formattedClientPhone.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Tel: $formattedClientPhone',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          color: const Color(0xFF52667C),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (canExpandTickets) ...[
              const _TicketActivityDot(),
              const SizedBox(width: 5),
              Icon(
                _showMobileTicketDropdown
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 18,
              ),
            ],
            if (!hasClient) ...[
              const SizedBox(width: 6),
              Text(
                '${_items.length}',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 9.5),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMobileTicketDropdownOverlay() {
    final theme = Theme.of(context);

    Widget ticketRow(_DesktopTicketDraft ticket, int index) {
      final selected = ticket.id == _activeDesktopTicketId;
      final lines = ticket.items.length;
      final ticketClient = ticket.selectedClientName.trim();
      final subtitle = [
        '$lines articulo(s)',
        if (ticketClient.isNotEmpty && ticketClient != 'Sin cliente')
          ticketClient,
      ].join(' · ');

      return InkWell(
        onTap: () => _switchDesktopTicket(ticket.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? const Color(0xFF1957E6) : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ticket.label(index),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              PopupMenuButton<_FooterTicketAction>(
                tooltip: 'Opciones del ticket',
                padding: EdgeInsets.zero,
                iconSize: 18,
                onSelected: (action) {
                  switch (action) {
                    case _FooterTicketAction.rename:
                      unawaited(_renameDesktopTicket(ticket.id));
                      return;
                    case _FooterTicketAction.delete:
                      unawaited(_deleteDesktopTicket(ticket.id));
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
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Positioned(
      left: 10,
      right: 10,
      top: 42,
      child: Material(
        color: Colors.white,
        elevation: 14,
        shadowColor: Colors.black.withValues(alpha: 0.18),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 178),
          child: ListView.separated(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount: _desktopTickets.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22),
            ),
            itemBuilder: (context, index) =>
                ticketRow(_desktopTickets[index], index),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileBody(QuotationAiState aiState, UserModel? currentUser) {
    final showAiBanner = _shouldShowAiBanner(aiState);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final productHeight = keyboardOpen
            ? (constraints.maxHeight * 0.42).clamp(170.0, 238.0)
            : (constraints.maxHeight * 0.48).clamp(260.0, 338.0);
        return Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
                    _buildProductStrip(height: productHeight),
                  ],
                ),
                if (_showMobileTicketDropdown && _desktopTickets.length > 1)
                  _buildMobileTicketDropdownOverlay(),
              ],
            ),
            const SizedBox(height: 2),
            Expanded(child: _buildTicketPanel(currentUser)),
          ],
        );
      },
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
                final sidePaneWidth = quotePaneWidth;
                final catalogOverlayWidth =
                    constraints.maxWidth - sidePaneWidth;
                final calculatorPaneWidth = catalogOverlayWidth
                    .clamp(292.0, 330.0)
                    .toDouble();
                final manualPaneWidth = catalogOverlayWidth
                    .clamp(360.0, 420.0)
                    .toDouble();
                final overlayOpen =
                    _showDesktopCalculator || _showDesktopManualItemForm;
                final overlayPaneWidth = _showDesktopManualItemForm
                    ? manualPaneWidth
                    : calculatorPaneWidth;

                return Stack(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _DesktopCatalogPane(
                            searchController: _searchCtrl,
                            selectedCategories: _selectedCategories,
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
                            onToggleCategory: (category) =>
                                _commitEditorChange(() {
                                  if (!_selectedCategories.remove(category)) {
                                    _selectedCategories.add(category);
                                  }
                                }),
                            onClearCategories: () =>
                                _commitEditorChange(_selectedCategories.clear),
                            onAddProduct: _addProduct,
                            onAddExternalItem: () => _openExternalItemDialog(),
                            onOpenNewProduct: _openInventoryCatalog,
                            onOpenStockAdjustments: _openStockAdjustments,
                          ),
                        ),
                        SizedBox(
                          width: sidePaneWidth,
                          child: _DesktopQuotePanel(
                            items: _items,
                            selectedClientName: _selectedClientName,
                            selectedClientPhone: _selectedClientPhone,
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
                            onClearClient: () => _commitEditorChange(() {
                              _selectedClientId = null;
                              _selectedClientName = 'Sin cliente';
                              _selectedClientPhone = null;
                            }),
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
                            onRemoveItem: (index) {
                              if (index < 0 || index >= _items.length) return;
                              _commitEditorChange(() => _items.removeAt(index));
                            },
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: fiscalPaneWidth,
                      child: IgnorePointer(
                        ignoring: !_includeItbis || overlayOpen,
                        child: AnimatedSlide(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          offset: _includeItbis && !overlayOpen
                              ? Offset.zero
                              : const Offset(-1.04, 0),
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            opacity: _includeItbis && !overlayOpen ? 1 : 0,
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
                              onCustomerNameChanged: (value) =>
                                  _commitEditorChange(
                                    () => _fiscalCustomerName = value,
                                  ),
                              onPickDueDate: _pickFiscalVoucherDueDate,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: catalogOverlayWidth,
                      child: IgnorePointer(
                        ignoring: !overlayOpen,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOutCubic,
                                opacity: overlayOpen ? 1 : 0,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => setState(() {
                                    _showDesktopCalculator = false;
                                    _showDesktopManualItemForm = false;
                                    _desktopManualEditIndex = null;
                                  }),
                                  child: ClipRect(
                                    child: BackdropFilter(
                                      filter: ui.ImageFilter.blur(
                                        sigmaX: 2.6,
                                        sigmaY: 2.6,
                                      ),
                                      child: Container(
                                        color: const Color(
                                          0xFFF8FBFF,
                                        ).withValues(alpha: 0.38),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                              left: overlayOpen ? 0 : -overlayPaneWidth,
                              top: 0,
                              bottom: 0,
                              width: overlayPaneWidth,
                              child: _showDesktopManualItemForm
                                  ? _DesktopManualItemPanel(
                                      key: ValueKey(
                                        'manual-${_desktopManualEditIndex ?? 'new'}',
                                      ),
                                      item:
                                          _desktopManualEditIndex != null &&
                                              _desktopManualEditIndex! >= 0 &&
                                              _desktopManualEditIndex! <
                                                  _items.length
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
                                              editIndex:
                                                  _desktopManualEditIndex,
                                            );
                                          },
                                    )
                                  : _DesktopCalculatorPane(
                                      onClose: _toggleDesktopCalculator,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (!overlayOpen)
                      Positioned(
                        left: 12,
                        bottom: 12,
                        child: _AnimatedCalculatorFab(
                          open: _showDesktopCalculator,
                          onTap: _toggleDesktopCalculator,
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
      backgroundColor: isDesktop ? null : AppColors.background,
      appBar: isDesktop
          ? _buildDesktopAppBar(aiState)
          : _buildMobileAppBar(aiState),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: SafeArea(
        top: false,
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
  calculator,
  newTicket,
  pdf,
  quote,
  quoteHistory,
  clear,
}

enum _InventoryFloatingAction { addProduct, adjustStock }

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

class _InventoryFloatingButton extends StatefulWidget {
  const _InventoryFloatingButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_InventoryFloatingButton> createState() =>
      _InventoryFloatingButtonState();
}

class _InventoryFloatingButtonState extends State<_InventoryFloatingButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF1957E6);
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final glow = 0.12 + (_pulse.value * 0.14);
        final scale = 1.0 + (_pulse.value * 0.035);
        return Transform.scale(
          scale: scale,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: glow),
                  blurRadius: 10 + (_pulse.value * 10),
                  spreadRadius: _pulse.value * 1.5,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: Material(
        color: Colors.white.withValues(alpha: 0.82),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: const BorderSide(color: accent, width: 1.25),
        ),
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(7),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: const [
                  Icon(Icons.inventory_2_outlined, size: 22, color: accent),
                  Positioned(
                    right: -5,
                    bottom: -5,
                    child: Icon(Icons.add_circle, size: 15, color: accent),
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

class _InventoryActionDrawerTile extends StatelessWidget {
  const _InventoryActionDrawerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF1FF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: const Color(0xFF1957E6), size: 19),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

class _QuotationTopbarMenu extends StatelessWidget {
  const _QuotationTopbarMenu({
    required this.onQuote,
    required this.onHistory,
    required this.onPdf,
  });

  final VoidCallback onQuote;
  final VoidCallback onHistory;
  final VoidCallback onPdf;

  void _runAfterMenuCloses(VoidCallback action) {
    Future<void>.delayed(const Duration(milliseconds: 120), action);
  }

  void _activateMenuItem(BuildContext menuContext, VoidCallback action) {
    Navigator.of(menuContext).pop();
    _runAfterMenuCloses(action);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: PopupMenuButton<String>(
        tooltip: 'Cotizaciones',
        offset: const Offset(0, 42),
        elevation: 8,
        color: Colors.white,
        shadowColor: Colors.black.withValues(alpha: 0.10),
        constraints: const BoxConstraints(minWidth: 282),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFDDE7EE)),
        ),
        itemBuilder: (menuContext) => [
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _QuotationMenuItem(
              icon: Icons.request_quote_outlined,
              title: 'Cotizar',
              onTap: () => _activateMenuItem(menuContext, onQuote),
              helpText:
                  'Guarda el ticket actual como cotización para poder retomarlo, compartirlo o convertirlo en una venta más adelante sin perder los productos agregados.',
            ),
          ),
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _QuotationMenuItem(
              icon: Icons.history_edu_outlined,
              title: 'Lista de cotizaciones',
              onTap: () => _activateMenuItem(menuContext, onHistory),
              helpText:
                  'Abre el historial de cotizaciones guardadas para buscar, revisar, reutilizar o dar seguimiento a propuestas anteriores.',
            ),
          ),
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _QuotationMenuItem(
              icon: Icons.picture_as_pdf_outlined,
              title: 'Ver PDF',
              onTap: () => _activateMenuItem(menuContext, onPdf),
              helpText:
                  'Genera una vista previa del documento PDF del ticket actual para revisarlo, imprimirlo o compartirlo con el cliente.',
            ),
          ),
        ],
        child: const _TopbarActionShell(
          icon: Icons.request_quote_outlined,
          label: 'Cotizaciones',
          hasChevron: true,
        ),
      ),
    );
  }
}

class _TopbarActionShell extends StatefulWidget {
  const _TopbarActionShell({
    required this.icon,
    required this.label,
    this.leading,
    this.hasChevron = false,
    this.primary = false,
    this.minWidth,
  });

  final IconData icon;
  final String label;
  final Widget? leading;
  final bool hasChevron;
  final bool primary;
  final double? minWidth;

  @override
  State<_TopbarActionShell> createState() => _TopbarActionShellState();
}

class _TopbarActionShellState extends State<_TopbarActionShell> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _pressed;
    final foreground = widget.primary
        ? Colors.white
        : (active ? const Color(0xFF1957E6) : const Color(0xFF123A75));
    final iconBg = widget.primary
        ? Colors.white.withValues(alpha: active ? 0.20 : 0.14)
        : const Color(0xFFEAF1FF);
    final borderColor = widget.primary
        ? const Color(0xFF7DA2FF)
        : (active ? const Color(0xFF9FBCFF) : const Color(0xFFCFE0FF));

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
            height: 40,
            constraints: BoxConstraints(minWidth: widget.minWidth ?? 0),
            padding: const EdgeInsets.fromLTRB(10, 5, 11, 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.primary
                    ? (active
                          ? const [Color(0xFF2E6BFF), Color(0xFF164ED6)]
                          : const [Color(0xFF1F62FF), Color(0xFF1957E6)])
                    : (active
                          ? const [Color(0xFFFFFFFF), Color(0xFFEAF1FF)]
                          : const [Color(0xFFFFFFFF), Color(0xFFF7FAFC)]),
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor),
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFF1957E6,
                  ).withValues(alpha: widget.primary ? 0.22 : 0.10),
                  blurRadius: active ? 18 : 10,
                  offset: Offset(0, active ? 7 : 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(6),
                    border: widget.primary
                        ? Border.all(color: Colors.white24)
                        : null,
                  ),
                  clipBehavior: Clip.antiAlias,
                  child:
                      widget.leading ??
                      Icon(widget.icon, size: 16, color: foreground),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                    letterSpacing: 0,
                  ),
                ),
                if (widget.hasChevron) ...[
                  const SizedBox(width: 5),
                  AnimatedRotation(
                    turns: _pressed ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 18,
                      color: foreground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedDrawerButton extends StatefulWidget {
  const _AnimatedDrawerButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_AnimatedDrawerButton> createState() => _AnimatedDrawerButtonState();
}

class _AnimatedDrawerButtonState extends State<_AnimatedDrawerButton>
    with SingleTickerProviderStateMixin {
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
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 0.94 : (_hovered ? 1.035 : 1),
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: active
                    ? const [Color(0xFFEAF1FF), Color(0xFFFFFFFF)]
                    : const [Color(0xFFFFFFFF), Color(0xFFF4F8FF)],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active
                    ? const Color(0xFF8FB4FF)
                    : const Color(0xFFC7D9FF),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFF1957E6,
                  ).withValues(alpha: active ? 0.20 : 0.08),
                  blurRadius: active ? 18 : 10,
                  offset: Offset(0, active ? 7 : 3),
                ),
              ],
            ),
            child: AnimatedRotation(
              turns: _pressed ? 0.03 : 0,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              child: Icon(
                Icons.menu_rounded,
                size: 23,
                color: const Color(0xFF1957E6),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileActionsButton extends StatefulWidget {
  const _MobileActionsButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_MobileActionsButton> createState() => _MobileActionsButtonState();
}

class _MobileActionsButtonState extends State<_MobileActionsButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      lowerBound: 0,
      upperBound: 0.12,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    await _controller.forward();
    if (mounted) {
      _controller.reverse();
      widget.onPressed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Acciones',
      child: InkWell(
        onTap: _handleTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = _controller.value;
              return Transform.translate(
                offset: Offset(-18 * t, 0),
                child: Transform.scale(
                  scale: 1 + t,
                  child: Transform.rotate(angle: t * 1.4, child: child),
                ),
              );
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1957E6).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                      color: const Color(0xFF1957E6).withValues(alpha: 0.18),
                    ),
                  ),
                ),
                const Icon(
                  Icons.keyboard_double_arrow_left_rounded,
                  size: 22,
                  color: Color(0xFF1957E6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompanyAccountMenu extends ConsumerWidget {
  const _CompanyAccountMenu();

  void _runAfterMenuCloses(VoidCallback action) {
    Future<void>.delayed(const Duration(milliseconds: 120), action);
  }

  void _activateMenuItem(BuildContext menuContext, VoidCallback action) {
    Navigator.of(menuContext).pop();
    _runAfterMenuCloses(action);
  }

  void _openSidePanel(BuildContext context, Widget child) {
    _runAfterMenuCloses(() {
      if (!context.mounted) return;
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Cerrar panel',
        barrierColor: Colors.black.withValues(alpha: 0.18),
        transitionDuration: const Duration(milliseconds: 230),
        pageBuilder: (context, animation, secondaryAnimation) => child,
        transitionBuilder: (context, animation, secondaryAnimation, child) {
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
    });
  }

  void _logout(BuildContext context, WidgetRef ref) {
    _runAfterMenuCloses(() async {
      await ref.read(authStateProvider.notifier).logout();
      if (context.mounted) context.go(Routes.login);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(companySettingsProvider);
    final companyName = company.maybeWhen(
      data: (settings) => _compactCompanyDisplayName(settings.companyName),
      orElse: () => 'Empresa',
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
        elevation: 8,
        color: Colors.white,
        surfaceTintColor: Colors.white,
        shadowColor: Colors.black.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFDDE7EE)),
        ),
        constraints: const BoxConstraints(minWidth: 302),
        itemBuilder: (menuContext) => [
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _CompanyMenuItem(
              icon: Icons.person_outline_rounded,
              label: 'Perfil',
              onTap: () => _activateMenuItem(
                menuContext,
                () => context.go(Routes.profile),
              ),
              helpText:
                  'Muestra la información del usuario conectado, sus datos principales y el acceso para revisar su cuenta dentro de DaleVenta POS.',
            ),
          ),
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _CompanyMenuItem(
              icon: Icons.groups_2_outlined,
              label: 'Equipos',
              onTap: () => _activateMenuItem(
                menuContext,
                () => context.go(Routes.users),
              ),
              helpText:
                  'Administra los usuarios de la empresa, sus roles y permisos para controlar quién puede vender, configurar o consultar información.',
            ),
          ),
          const PopupMenuDivider(height: 8),
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _CompanyMenuItem(
              icon: Icons.apps_rounded,
              label: 'Apps',
              onTap: () {
                Navigator.of(menuContext).pop();
                _openSidePanel(context, const _CompanyAppsSidePanel());
              },
              helpText:
                  'Centraliza los accesos para usar la cuenta desde Android, web y escritorio, manteniendo la misma empresa y permisos del usuario.',
            ),
          ),
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _CompanyMenuItem(
              icon: Icons.verified_user_outlined,
              label: 'Licencias',
              onTap: () {
                Navigator.of(menuContext).pop();
                _openSidePanel(context, const _CompanyLicensesSidePanel());
              },
              helpText:
                  'Resume el estado de la empresa activa, el plan disponible y la preparación del sistema para trabajo multiempresa.',
            ),
          ),
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _CompanyMenuItem(
              icon: Icons.system_update_alt_rounded,
              label: 'Actualizaciones',
              onTap: () => _activateMenuItem(
                menuContext,
                () => context.go(Routes.actualizaciones),
              ),
              helpText:
                  'Permite revisar la versión instalada, buscar nuevas versiones y confirmar si hay releases disponibles para este equipo.',
            ),
          ),
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _CompanyMenuItem(
              icon: Icons.settings_outlined,
              label: 'Configuración',
              onTap: () => _activateMenuItem(
                menuContext,
                () => context.go(Routes.configuracion),
              ),
              helpText:
                  'Abre el centro de control de la empresa con datos comerciales, documentos, impresión, backend y parámetros operativos.',
            ),
          ),
          const PopupMenuDivider(height: 8),
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _CompanyMenuItem(
              icon: Icons.logout_rounded,
              label: 'Cerrar sesión',
              danger: true,
              onTap: () {
                Navigator.of(menuContext).pop();
                _logout(context, ref);
              },
              helpText:
                  'Cierra la sesión del usuario actual en este equipo y vuelve a la pantalla de inicio para proteger el acceso de la empresa.',
            ),
          ),
        ],
        child: _TopbarActionShell(
          icon: Icons.storefront_rounded,
          label: companyName,
          leading: _CompanyLogoBox(logoBase64: logoBase64, size: 26),
          hasChevron: true,
          primary: true,
          minWidth: 132,
        ),
      ),
    );
  }
}

String _compactCompanyDisplayName(String value) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (normalized.isEmpty) return 'Empresa';
  if (normalized.length <= 18) return normalized;
  final firstSegment = normalized.split(' ').first.trim();
  if (firstSegment.length >= 3) return firstSegment;
  return normalized.substring(0, 18);
}

class _CompanyAppsSidePanel extends StatelessWidget {
  const _CompanyAppsSidePanel();

  @override
  Widget build(BuildContext context) {
    return _CompanySidePanelScaffold(
      icon: Icons.apps_rounded,
      title: 'Apps',
      subtitle: 'Accesos para trabajar desde distintos dispositivos.',
      children: [
        _CompanySideActionTile(
          icon: Icons.android_rounded,
          title: 'App Android',
          status: 'Preparada para móviles y tablets',
          description:
              'Permite entrar a la cuenta de la empresa desde Android para consultar ventas, clientes, inventario y operaciones autorizadas.',
          actionLabel: 'Ver acceso',
          onPressed: () => safeOpenUrl(context, Uri.parse(Env.appBaseUrl)),
        ),
        _CompanySideActionTile(
          icon: Icons.language_rounded,
          title: 'App web',
          status: 'Acceso desde navegador',
          description:
              'Abre la versión web para trabajar desde cualquier computador autorizado usando las mismas credenciales de la empresa.',
          actionLabel: 'Abrir web',
          onPressed: () => safeOpenUrl(context, Uri.parse(Env.appBaseUrl)),
        ),
        _CompanySideActionTile(
          icon: Icons.desktop_windows_rounded,
          title: 'Windows POS',
          status: 'Punto de venta instalado',
          description:
              'Aplicación de escritorio para caja, facturación, impresión y trabajo diario del punto de venta.',
          actionLabel: 'Actualizaciones',
          onPressed: () {
            Navigator.of(context).maybePop();
            context.go(Routes.actualizaciones);
          },
        ),
      ],
    );
  }
}

class _CompanyLicensesSidePanel extends ConsumerWidget {
  const _CompanyLicensesSidePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(companySettingsProvider);
    final user = ref.watch(authStateProvider).user;
    final companyName = company.maybeWhen(
      data: (settings) => settings.companyName.trim().isEmpty
          ? 'DaleVenta POS'
          : settings.companyName.trim(),
      orElse: () => 'DaleVenta POS',
    );

    return _CompanySidePanelScaffold(
      icon: Icons.verified_user_outlined,
      title: 'Licencias',
      subtitle: 'Estado de uso, empresa activa y alcance contratado.',
      children: [
        _CompanySideInfoTile(
          icon: Icons.business_rounded,
          title: 'Empresa activa',
          value: companyName,
        ),
        _CompanySideInfoTile(
          icon: Icons.person_outline_rounded,
          title: 'Usuario actual',
          value: user?.email ?? 'Usuario conectado',
        ),
        _CompanySideInfoTile(
          icon: Icons.workspace_premium_outlined,
          title: 'Plan profesional POS',
          value: 'Activo',
          highlighted: true,
        ),
        const _CompanySideDetailsCard(
          title: 'Alcance de la licencia',
          rows: [
            ('Empresas preparadas', 'Multiempresa'),
            ('Usuarios', 'Según permisos de la empresa'),
            ('Módulos incluidos', 'Ventas, clientes, inventario y caja'),
            ('Soporte', 'Operación y actualizaciones del sistema'),
          ],
        ),
      ],
    );
  }
}

class _CompanySidePanelScaffold extends StatelessWidget {
  const _CompanySidePanelScaffold({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final width = screenWidth < 620 ? screenWidth : 560.0;

    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          width: width,
          height: double.infinity,
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            border: Border(left: BorderSide(color: Color(0xFFD3E0E7))),
            boxShadow: [
              BoxShadow(
                color: Color(0x1F0F172A),
                blurRadius: 24,
                offset: Offset(-8, 0),
              ),
            ],
          ),
          child: SafeArea(
            left: false,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 10, 13),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFDDE7EE)),
                    ),
                  ),
                  child: Row(
                    children: [
                      _CompanySideIcon(icon: icon, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF52667C),
                                fontSize: 12.5,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close_rounded),
                        color: const Color(0xFF334155),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemBuilder: (context, index) => children[index],
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemCount: children.length,
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

class _CompanySideActionTile extends StatelessWidget {
  const _CompanySideActionTile({
    required this.icon,
    required this.title,
    required this.status,
    required this.description,
    required this.actionLabel,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String status;
  final String description;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _CompanySideSurface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CompanySideIcon(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _companySideTitleStyle(15)),
                const SizedBox(height: 3),
                Text(status, style: _companySideStrongStyle()),
                const SizedBox(height: 8),
                Text(description, style: _companySideBodyStyle()),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onPressed,
                  icon: const Icon(Icons.open_in_new_rounded, size: 17),
                  label: Text(actionLabel),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1957E6),
                    side: const BorderSide(color: Color(0xFF9DB9F8)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
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

class _CompanySideInfoTile extends StatelessWidget {
  const _CompanySideInfoTile({
    required this.icon,
    required this.title,
    required this.value,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return _CompanySideSurface(
      child: Row(
        children: [
          _CompanySideIcon(
            icon: icon,
            color: highlighted
                ? const Color(0xFF16A34A)
                : const Color(0xFF1957E6),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _companySideBodyStyle()),
                const SizedBox(height: 3),
                Text(value, style: _companySideTitleStyle(15)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanySideDetailsCard extends StatelessWidget {
  const _CompanySideDetailsCard({required this.title, required this.rows});

  final String title;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return _CompanySideSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _companySideTitleStyle(15)),
          const SizedBox(height: 10),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Expanded(child: Text(row.$1, style: _companySideBodyStyle())),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      row.$2,
                      textAlign: TextAlign.end,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _companySideStrongStyle(),
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

class _CompanySideSurface extends StatelessWidget {
  const _CompanySideSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE7EE)),
      ),
      child: child,
    );
  }
}

class _CompanySideIcon extends StatelessWidget {
  const _CompanySideIcon({
    required this.icon,
    this.color = const Color(0xFF1957E6),
    this.size = 34,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7FF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFDDEAFF)),
      ),
      child: Icon(icon, size: size * 0.48, color: color),
    );
  }
}

TextStyle _companySideTitleStyle(double size) {
  return TextStyle(
    color: const Color(0xFF0F172A),
    fontSize: size,
    fontWeight: FontWeight.w900,
    letterSpacing: 0,
  );
}

TextStyle _companySideBodyStyle() {
  return const TextStyle(
    color: Color(0xFF52667C),
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );
}

TextStyle _companySideStrongStyle() {
  return const TextStyle(
    color: Color(0xFF183548),
    fontSize: 13,
    fontWeight: FontWeight.w900,
    letterSpacing: 0,
  );
}

class _CompanyLogoBox extends StatelessWidget {
  const _CompanyLogoBox({required this.logoBase64, this.size = 28});

  final String? logoBase64;
  final double size;

  @override
  Widget build(BuildContext context) {
    final logoBytes = _decodeLogo(logoBase64);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FF),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      clipBehavior: Clip.antiAlias,
      child: logoBytes == null
          ? Icon(
              Icons.storefront_rounded,
              size: size * 0.58,
              color: const Color(0xFF1957E6),
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

class _CompanyMenuItem extends StatefulWidget {
  const _CompanyMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.helpText,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String helpText;
  final bool danger;

  @override
  State<_CompanyMenuItem> createState() => _CompanyMenuItemState();
}

class _CompanyMenuItemState extends State<_CompanyMenuItem> {
  bool _showHelp = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.danger
        ? const Color(0xFFDC2626)
        : const Color(0xFF1957E6);
    final textColor = widget.danger
        ? const Color(0xFFB91C1C)
        : const Color(0xFF27364A);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: widget.danger
                            ? const Color(0xFFFFF1F1)
                            : const Color(0xFFF3F7FF),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: widget.danger
                              ? const Color(0xFFFECACA)
                              : const Color(0xFFDDEAFF),
                        ),
                      ),
                      child: Icon(widget.icon, size: 17, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: _showHelp ? 'Ocultar ayuda' : 'Ayuda',
                      onPressed: () => setState(() => _showHelp = !_showHelp),
                      icon: Icon(
                        _showHelp
                            ? Icons.help_rounded
                            : Icons.help_outline_rounded,
                      ),
                      iconSize: 17,
                      color: _showHelp
                          ? const Color(0xFF1957E6)
                          : const Color(0xFF7C8DA1),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 30,
                        height: 30,
                      ),
                      splashRadius: 17,
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: widget.danger
                          ? const Color(0xFFF87171)
                          : const Color(0xFF9AA8B6),
                    ),
                  ],
                ),
              ),
              AnimatedCrossFade(
                firstChild: const SizedBox.shrink(),
                secondChild: _InlineMenuHelp(text: widget.helpText),
                crossFadeState: _showHelp
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 150),
                sizeCurve: Curves.easeOutCubic,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuotationMenuItem extends StatefulWidget {
  const _QuotationMenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
    required this.helpText,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final String helpText;

  @override
  State<_QuotationMenuItem> createState() => _QuotationMenuItemState();
}

class _QuotationMenuItemState extends State<_QuotationMenuItem> {
  bool _showHelp = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 282,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 31,
                      height: 31,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7FAFC),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFDDE7EE)),
                      ),
                      child: Icon(
                        widget.icon,
                        color: const Color(0xFF1957E6),
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF183548),
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                    Tooltip(
                      message: _showHelp ? 'Ocultar ayuda' : 'Ayuda',
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: IconButton(
                          onPressed: () =>
                              setState(() => _showHelp = !_showHelp),
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          style: IconButton.styleFrom(
                            foregroundColor: _showHelp
                                ? const Color(0xFF1957E6)
                                : const Color(0xFF64748B),
                            hoverColor: const Color(0xFFEFF4F8),
                            highlightColor: const Color(0xFFDDE7EE),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          icon: Icon(
                            _showHelp
                                ? Icons.help_rounded
                                : Icons.help_outline_rounded,
                            size: 17,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: _InlineMenuHelp(text: widget.helpText),
                  crossFadeState: _showHelp
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 150),
                  sizeCurve: Curves.easeOutCubic,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineMenuHelp extends StatelessWidget {
  const _InlineMenuHelp({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(42, 0, 4, 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FF),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFDDEAFF)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF52667C),
          fontSize: 11.6,
          height: 1.25,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
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
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onPressed,
          borderRadius: BorderRadius.circular(8),
          child: _TopbarActionShell(
            icon: widget.hasClient
                ? Icons.person_rounded
                : Icons.person_add_alt_1_rounded,
            label: 'Cliente',
            minWidth: 108,
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
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isMobile ? 6 : 8),
            side: const BorderSide(color: Color(0xFFDDE7EE)),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isMobile ? 430 : 780,
              maxHeight: media.height - (isMobile ? 24 : 40),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 14 : 24,
                    isMobile ? 11 : 16,
                    isMobile ? 10 : 16,
                    isMobile ? 10 : 14,
                  ),
                  child: Row(
                    children: [
                      if (!isMobile) ...[
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF1FF),
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: const Color(0xFFDDEAFF)),
                          ),
                          child: const Icon(
                            Icons.point_of_sale_rounded,
                            color: Color(0xFF1957E6),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isMobile ? 'Cobrar' : 'Cobrar venta',
                              style: TextStyle(
                                fontSize: isMobile ? 17 : 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                                letterSpacing: 0,
                              ),
                            ),
                            if (!isMobile) ...[
                              const SizedBox(height: 2),
                              const Text(
                                'Confirma el pago y genera la factura',
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0,
                                ),
                              ),
                            ],
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
                      isMobile ? 14 : 16,
                      isMobile ? 16 : 24,
                      isMobile ? 14 : 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: EdgeInsets.all(isMobile ? 14 : 16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFCFEFF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFDDE7EE)),
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
                                            letterSpacing: 0,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          widget.money(widget.total),
                                          style: const TextStyle(
                                            fontSize: 30,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF0F172A),
                                            letterSpacing: 0,
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
                                            letterSpacing: 0,
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          widget.money(widget.total),
                                          style: const TextStyle(
                                            fontSize: 31,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF0F172A),
                                            letterSpacing: 0,
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
                        const SizedBox(height: 14),
                        Text(
                          'Método de pago',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF0F172A),
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (isMobile)
                          Column(
                            children: [
                              for (final method
                                  in _CheckoutPaymentMethod.values) ...[
                                _PaymentMethodTile(
                                  method: method,
                                  selected: _method == method,
                                  onTap: () => _selectMethod(method),
                                  compact: true,
                                ),
                                if (method !=
                                    _CheckoutPaymentMethod.values.last)
                                  const SizedBox(height: 7),
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
                    isMobile ? 10 : 12,
                    isMobile ? 16 : 24,
                    isMobile ? 12 : 16,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    border: Border(top: BorderSide(color: Color(0xFFDDE7EE))),
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
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0,
                              ),
                            ),
                            const SizedBox(height: 9),
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
                                  vertical: 13,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF1957E6),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                              ),
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
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF1957E6),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0,
                                ),
                              ),
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
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0,
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
              letterSpacing: 0,
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
              letterSpacing: 0,
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
        fontSize: 14,
        letterSpacing: 0,
      ),
      decoration: InputDecoration(
        prefixText: r'RD$  ',
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD5E2EC)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD5E2EC)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF1957E6), width: 1.4),
        ),
        prefixStyle: const TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
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
      padding: const EdgeInsets.symmetric(horizontal: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F9FC),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFE3EBF2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 17, color: const Color(0xFF64748B)),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: strong ? const Color(0xFF1957E6) : const Color(0xFF64748B),
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
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
    this.compact = false,
  });

  final _CheckoutPaymentMethod method;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF1957E6) : const Color(0xFFFFFFFF),
      borderRadius: BorderRadius.circular(compact ? 6 : 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 6 : 8),
        child: Container(
          height: compact ? 46 : 52,
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 6 : 8),
            border: Border.all(
              color: selected
                  ? const Color(0xFF1957E6)
                  : const Color(0xFFD5E2EC),
            ),
          ),
          child: Row(
            children: [
              Icon(
                method.icon,
                size: compact ? 18 : 19,
                color: selected ? Colors.white : const Color(0xFF1957E6),
              ),
              SizedBox(width: compact ? 9 : 10),
              Text(
                method.label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                  fontSize: compact ? 13.5 : null,
                  letterSpacing: 0,
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
    final stockValue = product.stock;
    final outOfStock = stockValue == null || stockValue <= 0;
    final stockText = stockValue == null
        ? '0'
        : stockValue == stockValue.roundToDouble()
        ? stockValue.toStringAsFixed(0)
        : stockValue.toStringAsFixed(2);
    return Material(
      borderRadius: BorderRadius.circular(8),
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
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
                left: 2,
                top: 2,
                child: outOfStock
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.55),
                            width: 0.6,
                          ),
                        ),
                        child: const Text(
                          'SIN STOCK',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 7,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.3,
                            height: 1,
                          ),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.6),
                            width: 0.7,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'DISP',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 7,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Text(
                              stockText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                height: 1.0,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              Positioned(
                right: 2,
                top: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.6),
                      width: 0.7,
                    ),
                  ),
                  child: Text(
                    money(product.precio),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1957E6),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  child: const Icon(
                    Icons.add_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
              Positioned(
                left: 5,
                right: 28,
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
                        fontSize: 10.8,
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
                          fontSize: 8.8,
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
    );
  }
}

class _DesktopCatalogPane extends StatefulWidget {
  const _DesktopCatalogPane({
    required this.searchController,
    required this.selectedCategories,
    required this.categories,
    required this.managedCategories,
    required this.allProducts,
    required this.visibleProducts,
    required this.loadingProducts,
    required this.error,
    required this.money,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onToggleCategory,
    required this.onClearCategories,
    required this.onAddProduct,
    required this.onAddExternalItem,
    required this.onOpenNewProduct,
    required this.onOpenStockAdjustments,
  });

  final TextEditingController searchController;
  final Set<String> selectedCategories;
  final List<String> categories;
  final List<InventoryCategoryModel> managedCategories;
  final List<ProductModel> allProducts;
  final List<ProductModel> visibleProducts;
  final bool loadingProducts;
  final String? error;
  final String Function(double) money;
  final VoidCallback onSearchChanged;
  final VoidCallback onSearchSubmitted;
  final ValueChanged<String> onToggleCategory;
  final VoidCallback onClearCategories;
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
                    height: 44,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: const Color(0xFFD4E0E8)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF0B2A3A,
                            ).withValues(alpha: 0.05),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            margin: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1957E6),
                              borderRadius: BorderRadius.circular(6),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF1957E6,
                                  ).withValues(alpha: 0.18),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.search_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          Container(
                            width: 1,
                            height: 24,
                            color: const Color(0xFFE2EBF0),
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
                                    widget.searchController.text
                                        .trim()
                                        .isNotEmpty
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
                                fillColor: Colors.transparent,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 0,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _CatalogLineActionButton(
                  icon: AppIcons.productAdd,
                  label: 'Nuevo producto',
                  onPressed: widget.onOpenNewProduct,
                ),
                const SizedBox(width: 8),
                _CatalogLineActionButton(
                  icon: AppIcons.stockAdd,
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
              selectedCategories: widget.selectedCategories,
              onToggleCategory: widget.onToggleCategory,
              onClearCategories: widget.onClearCategories,
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
                  final manualHeight = cardHeight * 2 + spacing;
                  final firstRowsCapacity = (columns - 1) * 2;
                  var maxRow = 1;
                  if (widget.visibleProducts.length > firstRowsCapacity) {
                    final remaining =
                        widget.visibleProducts.length - firstRowsCapacity;
                    maxRow += (remaining / columns).ceil();
                  }
                  final contentHeight =
                      (maxRow + 1) * cardHeight + maxRow * spacing;

                  return Scrollbar(
                    controller: _gridScrollController,
                    thumbVisibility: true,
                    interactive: true,
                    child: SingleChildScrollView(
                      controller: _gridScrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: contentHeight.clamp(
                          constraints.maxHeight,
                          double.infinity,
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              left: 0,
                              top: 0,
                              width: cardWidth,
                              height: manualHeight,
                              child: _DesktopExternalProductCard(
                                onTap: widget.onAddExternalItem,
                              ),
                            ),
                            for (
                              var index = 0;
                              index < widget.visibleProducts.length;
                              index++
                            )
                              Positioned(
                                left:
                                    _desktopCatalogProductColumn(
                                      index,
                                      columns,
                                    ) *
                                    (cardWidth + spacing),
                                top:
                                    _desktopCatalogProductRow(index, columns) *
                                    (cardHeight + spacing),
                                width: cardWidth,
                                height: cardHeight,
                                child: _DesktopProductCard(
                                  product: widget.visibleProducts[index],
                                  money: widget.money,
                                  onTap: () => widget.onAddProduct(
                                    widget.visibleProducts[index],
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
    );
  }
}

int _desktopCatalogProductColumn(int index, int columns) {
  final firstRowsCapacity = (columns - 1) * 2;
  if (index < firstRowsCapacity) {
    return (index % (columns - 1)) + 1;
  }
  return (index - firstRowsCapacity) % columns;
}

int _desktopCatalogProductRow(int index, int columns) {
  final firstRowsCapacity = (columns - 1) * 2;
  if (index < firstRowsCapacity) {
    return index ~/ (columns - 1);
  }
  return 2 + ((index - firstRowsCapacity) ~/ columns);
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
  final FocusNode _nameFocus = FocusNode();
  final FocusNode _qtyFocus = FocusNode();
  final FocusNode _costFocus = FocusNode();
  final FocusNode _priceFocus = FocusNode();

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _nameFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _costCtrl.dispose();
    _priceCtrl.dispose();
    _nameFocus.dispose();
    _qtyFocus.dispose();
    _costFocus.dispose();
    _priceFocus.dispose();
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

  List<FocusNode> get _fieldFocusOrder => [
    _nameFocus,
    _qtyFocus,
    _costFocus,
    _priceFocus,
  ];

  void _moveFieldFocus(FocusNode current, int direction) {
    final fields = _fieldFocusOrder;
    final index = fields.indexOf(current);
    if (index < 0) return;
    final nextIndex = (index + direction).clamp(0, fields.length - 1);
    fields[nextIndex].requestFocus();
  }

  KeyEventResult _handleFieldKey(FocusNode current, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveFieldFocus(current, 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveFieldFocus(current, -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _keyboardField({
    required FocusNode focusNode,
    required TextEditingController controller,
    required InputDecoration decoration,
    TextInputType? keyboardType,
    TextInputAction textInputAction = TextInputAction.next,
    ValueChanged<String>? onChanged,
  }) {
    return Focus(
      onKeyEvent: (_, event) => _handleFieldKey(focusNode, event),
      child: TextField(
        focusNode: focusNode,
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        onChanged: onChanged,
        onSubmitted: (_) => _submit(),
        decoration: decoration,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.item != null;
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFD3E0E7))),
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
            _keyboardField(
              focusNode: _nameFocus,
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              decoration: _decoration('Nombre producto o servicio'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _keyboardField(
                    focusNode: _qtyFocus,
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
                  child: _keyboardField(
                    focusNode: _costFocus,
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
            _keyboardField(
              focusNode: _priceFocus,
              controller: _priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
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

class _DesktopCalculatorPane extends StatefulWidget {
  const _DesktopCalculatorPane({required this.onClose});

  final VoidCallback onClose;

  @override
  State<_DesktopCalculatorPane> createState() => _DesktopCalculatorPaneState();
}

class _DesktopCalculatorPaneState extends State<_DesktopCalculatorPane> {
  final FocusNode _focusNode = FocusNode();
  String _expression = '';
  String _result = '0';
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _append(String value) {
    setState(() {
      _error = null;
      _expression += value;
      _previewResult();
    });
  }

  void _clear() {
    setState(() {
      _expression = '';
      _result = '0';
      _error = null;
    });
  }

  void _backspace() {
    if (_expression.isEmpty) return;
    setState(() {
      _expression = _expression.substring(0, _expression.length - 1);
      _error = null;
      _previewResult();
    });
  }

  void _calculate() {
    if (_expression.trim().isEmpty) return;
    try {
      final value = _ExpressionEvaluator(_expression).parse();
      setState(() {
        _result = _formatCalculatorNumber(value);
        _expression = _result;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = 'Revisa la operación');
    }
  }

  void _previewResult() {
    if (_expression.trim().isEmpty) {
      _result = '0';
      return;
    }
    try {
      _result = _formatCalculatorNumber(
        _ExpressionEvaluator(_expression).parse(),
      );
    } catch (_) {
      _result = '...';
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final label = key.keyLabel;
    final numpadDigits = {
      LogicalKeyboardKey.numpad0: '0',
      LogicalKeyboardKey.numpad1: '1',
      LogicalKeyboardKey.numpad2: '2',
      LogicalKeyboardKey.numpad3: '3',
      LogicalKeyboardKey.numpad4: '4',
      LogicalKeyboardKey.numpad5: '5',
      LogicalKeyboardKey.numpad6: '6',
      LogicalKeyboardKey.numpad7: '7',
      LogicalKeyboardKey.numpad8: '8',
      LogicalKeyboardKey.numpad9: '9',
    };
    final numpadOperators = {
      LogicalKeyboardKey.numpadAdd: '+',
      LogicalKeyboardKey.numpadSubtract: '-',
      LogicalKeyboardKey.numpadMultiply: '*',
      LogicalKeyboardKey.numpadDivide: '/',
    };

    final numpadDigit = numpadDigits[key];
    if (numpadDigit != null) {
      _append(numpadDigit);
      return KeyEventResult.handled;
    }
    final numpadOperator = numpadOperators[key];
    if (numpadOperator != null) {
      _append(numpadOperator);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.numpadDecimal) {
      _append('.');
      return KeyEventResult.handled;
    }

    if (RegExp(r'^[0-9]$').hasMatch(label)) {
      _append(label);
      return KeyEventResult.handled;
    }
    if (label == '.' || label == ',') {
      _append('.');
      return KeyEventResult.handled;
    }
    if (label == '+' || label == '-' || label == '*' || label == '/') {
      _append(label);
      return KeyEventResult.handled;
    }
    if (label == '(' || label == ')') {
      _append(label);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        label == '=') {
      _calculate();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace) {
      _backspace();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete || label.toLowerCase() == 'c') {
      _clear();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final buttons = [
      'C',
      '(',
      ')',
      '÷',
      '7',
      '8',
      '9',
      '×',
      '4',
      '5',
      '6',
      '-',
      '1',
      '2',
      '3',
      '+',
      '0',
      '.',
      '⌫',
      '=',
    ];

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Container(
        height: double.infinity,
        decoration: const BoxDecoration(
          color: Color(0xFFF8FBFF),
          border: Border(right: BorderSide(color: Color(0xFFD3E0E7))),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD3E0E7)),
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
                        Icons.calculate_outlined,
                        color: Color(0xFF1957E6),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Calculadora',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF132337),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Teclado y mouse',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF647985),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar calculadora',
                      onPressed: widget.onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD3E0E7)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _expression.isEmpty ? '0' : _expression,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF52657A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _error ?? _result,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: _error == null ? 34 : 18,
                        fontWeight: FontWeight.w900,
                        color: _error == null
                            ? const Color(0xFF111827)
                            : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: buttons.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.45,
                  ),
                  itemBuilder: (context, index) {
                    final label = buttons[index];
                    final isOperator = [
                      '÷',
                      '×',
                      '-',
                      '+',
                      '=',
                    ].contains(label);
                    final isUtility = label == 'C' || label == '⌫';
                    return _CalculatorButton(
                      label: label,
                      filled: label == '=',
                      operator: isOperator,
                      utility: isUtility,
                      onPressed: () {
                        if (label == 'C') return _clear();
                        if (label == '⌫') return _backspace();
                        if (label == '=') return _calculate();
                        _append(
                          label == '×'
                              ? '*'
                              : label == '÷'
                              ? '/'
                              : label,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalculatorButton extends StatelessWidget {
  const _CalculatorButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.operator = false,
    this.utility = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool filled;
  final bool operator;
  final bool utility;

  @override
  Widget build(BuildContext context) {
    final background = filled
        ? const Color(0xFF1957E6)
        : operator
        ? const Color(0xFFEAF1FF)
        : utility
        ? const Color(0xFFFFF4E8)
        : Colors.white;
    final foreground = filled
        ? Colors.white
        : operator
        ? const Color(0xFF1957E6)
        : utility
        ? const Color(0xFF9A5A00)
        : const Color(0xFF132337);

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: filled ? const Color(0xFF1957E6) : const Color(0xFFD3E0E7),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

String _formatCalculatorNumber(double value) {
  if (!value.isFinite) throw const FormatException('Invalid number');
  final fixed = value.toStringAsFixed(8);
  return fixed
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

class _ExpressionEvaluator {
  _ExpressionEvaluator(String source)
    : _source = source
          .replaceAll(',', '.')
          .replaceAll('×', '*')
          .replaceAll('÷', '/');

  final String _source;
  int _index = 0;

  double parse() {
    final value = _parseExpression();
    _skipSpaces();
    if (_index != _source.length) throw const FormatException('Invalid input');
    return value;
  }

  double _parseExpression() {
    var value = _parseTerm();
    while (true) {
      _skipSpaces();
      if (_match('+')) {
        value += _parseTerm();
      } else if (_match('-')) {
        value -= _parseTerm();
      } else {
        return value;
      }
    }
  }

  double _parseTerm() {
    var value = _parseFactor();
    while (true) {
      _skipSpaces();
      if (_match('*')) {
        value *= _parseFactor();
      } else if (_match('/')) {
        final divisor = _parseFactor();
        if (divisor == 0) throw const FormatException('Division by zero');
        value /= divisor;
      } else {
        return value;
      }
    }
  }

  double _parseFactor() {
    _skipSpaces();
    if (_match('+')) return _parseFactor();
    if (_match('-')) return -_parseFactor();
    if (_match('(')) {
      final value = _parseExpression();
      if (!_match(')')) throw const FormatException('Missing parenthesis');
      return value;
    }
    return _parseNumber();
  }

  double _parseNumber() {
    _skipSpaces();
    final start = _index;
    while (_index < _source.length) {
      final char = _source[_index];
      if (!RegExp(r'[0-9.]').hasMatch(char)) break;
      _index++;
    }
    if (start == _index) throw const FormatException('Number expected');
    final raw = _source.substring(start, _index);
    final value = double.tryParse(raw);
    if (value == null) throw const FormatException('Invalid number');
    return value;
  }

  bool _match(String char) {
    _skipSpaces();
    if (_index >= _source.length || _source[_index] != char) return false;
    _index++;
    return true;
  }

  void _skipSpaces() {
    while (_index < _source.length && _source[_index].trim().isEmpty) {
      _index++;
    }
  }
}

class _DesktopQuotePanel extends StatelessWidget {
  const _DesktopQuotePanel({
    required this.items,
    required this.selectedClientName,
    required this.selectedClientPhone,
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
    required this.onClearClient,
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
  final String? selectedClientPhone;
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
  final VoidCallback onClearClient;
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
    final clientPhone = (selectedClientPhone ?? '').trim();
    final itemCountText = items.length == 1
        ? '1 producto'
        : '${items.length} productos';
    final shouldShowTotalsBreakdown =
        discountAmount > 0 ||
        generalDiscountAmount > 0 ||
        includeItbis ||
        isAdmin;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: Color(0xFFD3E0E7))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasClient) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Material(
                  color: const Color(0xFFFCFEFF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: const BorderSide(color: Color(0xFFEAF0F4)),
                  ),
                  child: InkWell(
                    onTap: onPickClient,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF2F7FF),
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: const Color(0xFFDDEAFF),
                              ),
                            ),
                            child: const Icon(
                              Icons.person_outline_rounded,
                              size: 18,
                              color: Color(0xFF1957E6),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final showInlinePhone =
                                    clientPhone.isNotEmpty &&
                                    constraints.maxWidth >= 260;
                                final nameStyle = theme.textTheme.titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w900,
                                      color: const Color(0xFF183548),
                                      letterSpacing: 0,
                                    );
                                final phoneStyle = theme.textTheme.bodySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF5E7180),
                                      letterSpacing: 0,
                                    );

                                if (showInlinePhone) {
                                  return Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          selectedClientName.trim(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: nameStyle,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        clientPhone,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: phoneStyle,
                                      ),
                                    ],
                                  );
                                }

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      selectedClientName.trim(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: nameStyle,
                                    ),
                                    if (clientPhone.isNotEmpty)
                                      Text(
                                        clientPhone,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: phoneStyle,
                                      ),
                                  ],
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          Tooltip(
                            message: 'Quitar cliente',
                            child: SizedBox(
                              width: 28,
                              height: 28,
                              child: IconButton(
                                onPressed: onClearClient,
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  foregroundColor: const Color(0xFF64748B),
                                  hoverColor: const Color(0xFFEFF4F8),
                                  highlightColor: const Color(0xFFDDE7EE),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ),
                                icon: const Icon(Icons.close_rounded, size: 17),
                              ),
                            ),
                          ),
                        ],
                      ),
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
                          const SizedBox.shrink(),
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
              if (shouldShowTotalsBreakdown) ...[
                const SizedBox(height: 3),
                Container(
                  width: double.infinity,
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(color: const Color(0xFFE2EAF0)),
                      bottom: BorderSide(color: const Color(0xFFE2EAF0)),
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
              ],
              const SizedBox(height: 4),
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
                          minimumSize: const Size.fromHeight(64),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(3),
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
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: SizedBox(
                      width: 70,
                      height: 64,
                      child: OutlinedButton(
                        onPressed: onOpenHistory,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1957E6),
                          side: const BorderSide(
                            color: Color(0xFFBFD0DD),
                            width: 1.35,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(3),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                        ),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.receipt_long_outlined),
                            SizedBox(height: 2),
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
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Container(
                width: double.infinity,
                margin: EdgeInsets.zero,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: const Color(0xFFE2EAF0)),
                    bottom: BorderSide(color: const Color(0xFFE2EAF0)),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF1FF),
                        borderRadius: BorderRadius.circular(3),
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
                        _DesktopPanelSwitchAction(
                          icon: Icons.receipt_long_outlined,
                          label: 'ITBIS',
                          value: includeItbis,
                          helpTitle: 'ITBIS y factura fiscal',
                          helpMessage:
                              'Al activar este switch se muestra el panel de factura fiscal en el lado izquierdo. Ahí se configura el tipo de comprobante, NCF, vencimiento, RNC o cédula y razón social del cliente. Cuando termines, toca de nuevo el switch ITBIS para ocultar ese panel.',
                          onTap: () => onToggleItbis(!includeItbis),
                        ),
                        const SizedBox(width: 6),
                        _DesktopPanelSwitchAction(
                          icon: Icons.sticky_note_2_outlined,
                          label: 'Notas',
                          value: hasNote,
                          helpTitle: 'Notas de la venta',
                          helpMessage:
                              'Al tocar este switch se abre el editor de notas para escribir información adicional de la venta. Sirve para dejar observaciones internas o detalles para el comprobante. Si ya no necesitas verla o editarla, vuelve a tocar Notas y cierra el editor al finalizar.',
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
        border: Border(right: BorderSide(color: Color(0xFFD3E0E7))),
        boxShadow: [
          BoxShadow(
            color: Color(0x260B2A3A),
            blurRadius: 28,
            offset: Offset(10, 0),
          ),
        ],
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

class _DesktopPanelSwitchAction extends StatefulWidget {
  const _DesktopPanelSwitchAction({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
    required this.helpTitle,
    required this.helpMessage,
  });

  final IconData icon;
  final String label;
  final bool value;
  final VoidCallback onTap;
  final String helpTitle;
  final String helpMessage;

  @override
  State<_DesktopPanelSwitchAction> createState() =>
      _DesktopPanelSwitchActionState();
}

class _DesktopPanelSwitchActionState extends State<_DesktopPanelSwitchAction> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.value;
    final interactive = _hovered || _pressed;
    final foreground = active
        ? const Color(0xFF1957E6)
        : const Color(0xFF52697A);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
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
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap,
              child: AnimatedScale(
                scale: _pressed ? 0.97 : (_hovered ? 1.015 : 1),
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOutCubic,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 170),
                  curve: Curves.easeOutCubic,
                  height: 30,
                  padding: const EdgeInsets.fromLTRB(7, 4, 6, 4),
                  decoration: BoxDecoration(
                    color: active
                        ? const Color(0xFFEAF1FF)
                        : (interactive
                              ? const Color(0xFFF7FAFC)
                              : Colors.white),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: active
                          ? const Color(0xFFB8CCFF)
                          : const Color(0xFFE1EAF0),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(
                          0xFF1957E6,
                        ).withValues(alpha: active ? 0.10 : 0.035),
                        blurRadius: interactive ? 10 : 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.icon, size: 13.5, color: foreground),
                      const SizedBox(width: 5),
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: foreground,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(width: 7),
                      _DesktopMiniTechToggle(value: active),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 3),
        _DesktopSwitchHelpButton(
          title: widget.helpTitle,
          message: widget.helpMessage,
        ),
      ],
    );
  }
}

class _DesktopSwitchHelpButton extends StatelessWidget {
  const _DesktopSwitchHelpButton({required this.title, required this.message});

  final String title;
  final String message;

  Future<void> _showHelp(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Ayuda',
      child: SizedBox(
        width: 22,
        height: 30,
        child: IconButton(
          onPressed: () => _showHelp(context),
          padding: EdgeInsets.zero,
          iconSize: 15,
          color: const Color(0xFF647985),
          icon: const Icon(Icons.help_outline_rounded),
        ),
      ),
    );
  }
}

class _DesktopMiniTechToggle extends StatelessWidget {
  const _DesktopMiniTechToggle({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 190),
      curve: Curves.easeOutCubic,
      width: 34,
      height: 18,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: value
              ? const [Color(0xFF2F6BFF), Color(0xFF0E7490)]
              : const [Color(0xFFE7EEF3), Color(0xFFD6E0E7)],
        ),
        border: Border.all(
          color: value ? const Color(0xFF8FB2FF) : const Color(0xFFB7C5CE),
        ),
        boxShadow: [
          BoxShadow(
            color: (value ? const Color(0xFF1957E6) : const Color(0xFF0F2633))
                .withValues(alpha: value ? 0.18 : 0.08),
            blurRadius: value ? 8 : 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutCubic,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 190),
          curve: Curves.easeOutCubic,
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: value ? 0.18 : 0.12),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 160),
            opacity: value ? 1 : 0,
            child: const Icon(
              Icons.check_rounded,
              size: 10,
              color: Color(0xFF1957E6),
            ),
          ),
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

  final AppIconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = filled ? const Color(0xFF1957E6) : Colors.white;
    final foreground = filled ? Colors.white : const Color(0xFF174EA6);
    final borderColor = filled
        ? const Color(0xFF1957E6)
        : const Color(0xFFC7D7FF);

    return SizedBox(
      height: 42,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: const Color(
                0xFF123A6F,
              ).withValues(alpha: filled ? 0.14 : 0.06),
              blurRadius: filled ? 14 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: AppIcon(icon, size: 17.5, color: foreground, strokeWidth: 2),
          label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          style: OutlinedButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            side: BorderSide(color: borderColor, width: 1.1),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: 12.4,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
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
    required this.selectedCategories,
    required this.onToggleCategory,
    required this.onClearCategories,
  });

  final List<String> categories;
  final List<ProductModel> allProducts;
  final List<InventoryCategoryModel> managedCategories;
  final Set<String> selectedCategories;
  final ValueChanged<String> onToggleCategory;
  final VoidCallback onClearCategories;

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
    final hasFilter = selectedCategories.isNotEmpty;

    return SizedBox(
      height: 40,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 6.0;
          const clearWidth = 78.0;
          const moreWidth = 42.0;
          final visible = <String>[];
          final hidden = <String>[];
          final available = constraints.maxWidth;
          var used = hasFilter ? clearWidth + gap : 0.0;

          for (final category in categories) {
            final nextWidth = _DesktopCategoryStripItem.widthFor(category);
            final nextUsed = used + (visible.isEmpty ? 0 : gap) + nextWidth;
            if (nextUsed <= available) {
              visible.add(category);
              used = nextUsed;
            } else {
              hidden.add(category);
            }
          }

          if (hidden.isNotEmpty) {
            while (visible.isNotEmpty && used + gap + moreWidth > available) {
              final removed = visible.removeLast();
              hidden.insert(0, removed);
              used -= _DesktopCategoryStripItem.widthFor(removed);
              if (visible.isNotEmpty) used -= gap;
            }
          }

          return Row(
            children: [
              if (hasFilter) ...[
                _DesktopCategoryClearButton(onTap: onClearCategories),
                const SizedBox(width: gap),
              ],
              for (final category in visible) ...[
                if (category != visible.first) const SizedBox(width: gap),
                _DesktopCategoryStripItem(
                  label: category,
                  product: _thumbnailProduct(category),
                  managedCategory: _managedCategory(category),
                  selected: selectedCategories.contains(category),
                  onTap: () => onToggleCategory(category),
                ),
              ],
              if (hidden.isNotEmpty) ...[
                if (visible.isNotEmpty) const SizedBox(width: gap),
                _DesktopCategoryOverflowButton(
                  categories: hidden,
                  selectedCategories: selectedCategories,
                  onToggleCategory: onToggleCategory,
                ),
              ],
              const Spacer(),
            ],
          );
        },
      ),
    );
  }
}

class _DesktopCategoryClearButton extends StatelessWidget {
  const _DesktopCategoryClearButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 78,
      height: 38,
      child: Material(
        color: const Color(0xFF1957E6),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: Text(
              'Limpiar',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 11.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DesktopCategoryOverflowButton extends StatelessWidget {
  const _DesktopCategoryOverflowButton({
    required this.categories,
    required this.selectedCategories,
    required this.onToggleCategory,
  });

  final List<String> categories;
  final Set<String> selectedCategories;
  final ValueChanged<String> onToggleCategory;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 42,
      height: 38,
      child: PopupMenuButton<String>(
        tooltip: 'Más categorías',
        padding: EdgeInsets.zero,
        color: Colors.white,
        surfaceTintColor: Colors.white,
        position: PopupMenuPosition.under,
        onSelected: onToggleCategory,
        itemBuilder: (context) => [
          for (final category in categories)
            PopupMenuItem(
              value: category,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selectedCategories.contains(category))
                    const AppIcon(
                      AppIcons.success,
                      size: 16,
                      color: Color(0xFF1957E6),
                    )
                  else
                    const SizedBox(width: 16),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD3E0E7)),
          ),
          child: const Center(
            child: AppIcon(AppIcons.more, size: 19, color: Color(0xFF50697A)),
          ),
        ),
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

  static double widthFor(String label) {
    final normalizedLabel = label.trim();
    return (normalizedLabel.length * 7.2 + 56).clamp(112.0, 420.0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imageUrl = product?.displayFotoUrl?.trim() ?? '';
    final categoryImageBytes = _decodeManagedCategoryImage(
      managedCategory?.imageBase64,
    );
    final normalizedLabel = label.trim().toUpperCase();
    final tileWidth = widthFor(label);

    return SizedBox(
      width: tileWidth,
      height: 38,
      child: Material(
        color: selected ? const Color(0xFFEAF1FF) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
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
                  width: 32,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F8FC),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: selected
                          ? const Color(0xFF9FC0FF)
                          : const Color(0xFFD2E2EC),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0B2A3A).withValues(alpha: 0.10),
                        blurRadius: 7,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: categoryImageBytes != null
                      ? Transform.scale(
                          scale: 1.08,
                          child: Image.memory(
                            categoryImageBytes,
                            width: 32,
                            height: 30,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                          ),
                        )
                      : imageUrl.isEmpty || product == null
                      ? const Icon(
                          Icons.inventory_2_outlined,
                          color: Color(0xFF8DA2B4),
                          size: 15,
                        )
                      : Transform.scale(
                          scale: 1.08,
                          child: ProductNetworkImage(
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
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    normalizedLabel,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: const Color(0xFF152238),
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
                      fontSize: 10.8,
                      height: 1,
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

class _DesktopExternalProductCard extends StatefulWidget {
  const _DesktopExternalProductCard({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_DesktopExternalProductCard> createState() =>
      _DesktopExternalProductCardState();
}

class _DesktopExternalProductCardState
    extends State<_DesktopExternalProductCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final helpText =
        'Usa venta manual para facturar productos o servicios que no están registrados en inventario. Es útil para cargos especiales, reparaciones, ajustes rápidos o artículos únicos sin afectar el stock.';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _hovered ? 0.975 : 1,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _hovered
                      ? const Color(0xFF1957E6)
                      : const Color(0xFF8FB3FF),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(
                      0xFF1957E6,
                    ).withValues(alpha: _hovered ? 0.14 : 0.08),
                    blurRadius: _hovered ? 18 : 14,
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
                        height: 92,
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
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Tooltip(
                      message: helpText,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () {
                          showDialog<void>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Venta manual'),
                              content: Text(helpText),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.of(dialogContext).pop(),
                                  child: const Text('Entendido'),
                                ),
                              ],
                            ),
                          );
                        },
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF1FF),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFCFE0FF)),
                          ),
                          child: const Icon(
                            Icons.help_outline_rounded,
                            color: Color(0xFF1957E6),
                            size: 17,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 74,
                            height: 74,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF1FF),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: const Color(0xFFCFE0FF),
                              ),
                            ),
                            child: const Icon(
                              Icons.add_shopping_cart_rounded,
                              color: Color(0xFF1957E6),
                              size: 40,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Sin inventario',
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xFF152238),
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 7),
                          const Text(
                            'Venta rápida fuera de catálogo',
                            maxLines: 1,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xFF5C7184),
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1957E6),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Agregar',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                                height: 1,
                              ),
                            ),
                          ),
                        ],
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.nombre,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF142033),
                            height: 1.25,
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
  Future<void> _showFullProductName() async {
    final name = widget.item.nombre.trim();
    if (name.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Producto'),
        content: SelectableText(name),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFullPrice() async {
    final price = _formatAccountingInput(widget.item.unitPrice);
    if (price.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Precio'),
        content: SelectableText(price),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
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
        onDoubleTap: widget.onEditLine,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(5, 7, 2, 7),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: Color(0xFFE2EAF0), width: 1),
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
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: _showFullProductName,
                      child: Text(
                        item.nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
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
              const SizedBox(width: 4),
              SizedBox(
                width: 56,
                child: InkWell(
                  onTap: _showFullPrice,
                  child: Text(
                    _formatAccountingInput(item.unitPrice),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: const Color(0xFF52677C),
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),

              if (hasDiscount)
                Padding(
                  padding: const EdgeInsets.only(left: 3),
                  child: Text(
                    widget.money(item.effectiveOriginalUnitPrice),
                    style: theme.textTheme.bodySmall?.copyWith(
                      decoration: TextDecoration.lineThrough,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ),
              const SizedBox(width: 2),
              _DesktopTicketQtyButton(
                tooltip: 'Restar unidad',
                onPressed: widget.onMinus,
                icon: AppIcons.remove,
              ),
              SizedBox(
                width: 30,
                height: 30,
                child: Center(
                  child: Text(
                    qtyText,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF183548),
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              _DesktopTicketQtyButton(
                tooltip: 'Sumar unidad',
                onPressed: widget.onPlus,
                icon: AppIcons.add,
              ),
              const SizedBox(width: 2),
              SizedBox(
                width: 72,
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
              const SizedBox(width: 2),
              _DesktopTicketRemoveButton(
                tooltip: 'Eliminar producto',
                onPressed: widget.onRemove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopTicketQtyButton extends StatelessWidget {
  const _DesktopTicketQtyButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final AppIconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 30,
        height: 30,
        child: IconButton(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: const Color(0xFF1957E6),
            hoverColor: const Color(0xFFEAF1FF),
            highlightColor: const Color(0xFFDCE8FF),
            shape: const CircleBorder(),
          ),
          icon: AppIcon(icon, size: 20, strokeWidth: 2.5),
        ),
      ),
    );
  }
}

class _DesktopTicketRemoveButton extends StatelessWidget {
  const _DesktopTicketRemoveButton({
    required this.tooltip,
    required this.onPressed,
  });

  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 30,
        height: 30,
        child: IconButton(
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: const Color(0xFF111827),
            hoverColor: const Color(0xFFEFF4F8),
            highlightColor: const Color(0xFFDDE7EE),
            shape: const CircleBorder(),
          ),
          icon: const AppIcon(AppIcons.delete, size: 18, strokeWidth: 2.3),
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

class _AnimatedCalculatorFab extends StatefulWidget {
  const _AnimatedCalculatorFab({
    required this.open,
    required this.onTap,
    this.compact = false,
    this.filled = false,
  });

  final bool open;
  final VoidCallback onTap;
  final bool compact;
  final bool filled;

  @override
  State<_AnimatedCalculatorFab> createState() => _AnimatedCalculatorFabState();
}

class _AnimatedCalculatorFabState extends State<_AnimatedCalculatorFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 56.0;
    final isPrimary = widget.open || widget.filled;
    return Tooltip(
      message: widget.open ? 'Cerrar calculadora' : 'Abrir calculadora',
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final t = _pulse.value;
          final glow = 0.34 * (1 - t);
          final halo = size * (1.0 + 0.16 * t);
          return SizedBox(
            width: halo + 12,
            height: halo + 12,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: halo,
                  height: halo,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1957E6).withValues(alpha: glow),
                    shape: BoxShape.circle,
                  ),
                ),
                child!,
              ],
            ),
          );
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(widget.compact ? 14 : 28),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: isPrimary ? const Color(0xFF1957E6) : Colors.white,
                shape: widget.compact ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: widget.compact ? BorderRadius.circular(14) : null,
                border: Border.all(
                  color: isPrimary
                      ? const Color(0xFF1957E6)
                      : const Color(0xFFD3E0E7),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F2742).withValues(alpha: 0.18),
                    blurRadius: 20,
                    offset: const Offset(0, 9),
                  ),
                ],
              ),
              child: Icon(
                Icons.calculate_outlined,
                size: widget.compact ? 26 : 27,
                color: isPrimary ? Colors.white : const Color(0xFF1957E6),
              ),
            ),
          ),
        ),
      ),
    );
  }
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
      height: 42,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FBFD),
        border: Border(
          top: BorderSide(color: Color(0xFFC9D8E2)),
          bottom: BorderSide(color: Color(0xFFE4EDF2)),
        ),
      ),
      child: Row(
        children: [
          Tooltip(
            message: 'Nuevo ticket',
            child: SizedBox(
              width: 34,
              height: 34,
              child: FilledButton(
                onPressed: onCreateTicket,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: const Color(0xFF1957E6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Icon(Icons.add_rounded, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const _TicketFooterSeparator(),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: tickets.length,
              separatorBuilder: (_, __) => const _TicketFooterSeparator(),
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
          const _TicketFooterSeparator(),
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
    final bg = selected ? const Color(0xFFEAF1FF) : const Color(0xFFF8FBFD);
    final border = selected ? const Color(0xFF1957E6) : Colors.transparent;
    final fg = selected ? const Color(0xFF1957E6) : const Color(0xFF183548);
    final hasItems = itemCount > 0;

    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 148,
          height: 42,
          child: DecoratedBox(
            decoration: BoxDecoration(border: Border.all(color: border)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 2, 0),
              child: Row(
                children: [
                  AppIcon(AppIcons.ticket, size: 16.5, color: fg),
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
                  if (hasItems) const _TicketActivityDot(),
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
                      icon: AppIcon(
                        AppIcons.moreVertical,
                        size: 17,
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

class _TicketFooterSeparator extends StatelessWidget {
  const _TicketFooterSeparator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Container(width: 1, height: 28, color: const Color(0xFFD8E5EC)),
    );
  }
}

class _TicketActivityDot extends StatefulWidget {
  const _TicketActivityDot();

  @override
  State<_TicketActivityDot> createState() => _TicketActivityDotState();
}

class _TicketActivityDotState extends State<_TicketActivityDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.82, end: 1.18).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
    _opacity = Tween<double>(begin: 0.58, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: FadeTransition(
        opacity: _opacity,
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: const Color(0xFF1D6BFF),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1D6BFF).withValues(alpha: 0.36),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
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
    this.selectedCategories = const [],
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
      selectedCategories: const [],
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
  final List<String> selectedCategories;
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
    List<String>? selectedCategories,
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
      selectedCategories: selectedCategories ?? this.selectedCategories,
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
    'selectedCategory': selectedCategories.isEmpty
        ? null
        : selectedCategories.first,
    'selectedCategories': selectedCategories,
    'searchQuery': searchQuery,
  };

  factory _DesktopTicketDraft.fromMap(Map<String, dynamic> map) {
    final rawItems = (map['items'] as List?) ?? const [];
    final rawCategories = (map['selectedCategories'] as List?) ?? const [];
    final selectedCategories = rawCategories
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList(growable: false);
    final selectedCategory = map['selectedCategory']?.toString().trim();
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
      selectedCategories: selectedCategories.isNotEmpty
          ? selectedCategories
          : [
              if (selectedCategory != null && selectedCategory.isNotEmpty)
                selectedCategory,
            ],
      searchQuery: (map['searchQuery'] ?? '').toString(),
    );
  }
}

enum _DiscountType { percent, fixed }

class _TicketCompactItem extends StatefulWidget {
  const _TicketCompactItem({
    required this.item,
    required this.money,
    required this.showCost,
    required this.outOfStock,
    required this.onEditLine,
    required this.onChangePrice,
    required this.onEdit,
    required this.onRemove,
  });

  final CotizacionItem item;
  final String Function(double) money;
  final bool showCost;
  final bool outOfStock;
  final VoidCallback onEditLine;
  final ValueChanged<double> onChangePrice;
  final VoidCallback? onEdit;
  final VoidCallback onRemove;

  @override
  State<_TicketCompactItem> createState() => _TicketCompactItemState();
}

class _TicketCompactItemState extends State<_TicketCompactItem> {
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final editAction = widget.onEdit ?? widget.onEditLine;

    String formatNoDecimals(num value) {
      final v = value.toDouble();
      return v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    }

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.zero,
      child: InkWell(
        borderRadius: BorderRadius.zero,
        onTap: editAction,
        onDoubleTap: widget.onEditLine,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 36,
                  height: 36,
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
                            size: 15,
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
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                          fallback: Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.broken_image_outlined,
                              size: 12,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.nombre,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (widget.outOfStock) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'SIN STOCK',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 7,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                                height: 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Flexible(
                          child: Text(
                            '${formatNoDecimals(item.qty)} x ${widget.money(item.unitPrice)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 10.5,
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    widget.money(item.total),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(
                    width: 72,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E4E9),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.12),
                            ),
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: 'Editar',
                            iconSize: 18,
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: Colors.black,
                            ),
                            onPressed: editAction,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E4E9),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.12),
                            ),
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: 'Eliminar',
                            iconSize: 18,
                            icon: const Icon(Icons.close, color: Colors.black),
                            onPressed: widget.onRemove,
                          ),
                        ),
                      ],
                    ),
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

class _BorderedAppBarAction extends StatelessWidget {
  const _BorderedAppBarAction({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.22),
            width: 1,
          ),
        ),
        child: IconButton(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          tooltip: tooltip,
          onPressed: onPressed,
          icon: IconTheme.merge(
            data: const IconThemeData(color: Colors.white, size: 19),
            child: icon,
          ),
        ),
      ),
    );
  }
}
