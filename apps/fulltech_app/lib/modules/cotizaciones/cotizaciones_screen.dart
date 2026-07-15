import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/auth/app_role.dart';
import '../../core/cache/fulltech_cache_manager.dart';
import '../../core/cache/local_json_cache.dart';
import '../../core/company/company_settings_model.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/debug/debug_admin_action.dart';
import '../../core/errors/api_exception.dart';
import '../../core/models/user_model.dart';
import '../../core/models/product_model.dart';
import '../../core/realtime/catalog_realtime_service.dart';
import '../../core/routing/app_route_observer.dart';
import '../../core/routing/route_access.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/responsive_shell.dart';
import '../../core/widgets/product_network_image.dart';
import '../clientes/cliente_model.dart';
import '../clientes/cliente_form_screen.dart';
import '../service_orders/service_order_models.dart';
import '../ventas/data/ventas_repository.dart';
import 'ai/application/quotation_ai_controller.dart';
import 'ai/domain/models/ai_warning.dart';
import 'ai/domain/models/quotation_context.dart';
import 'ai/domain/services/quotation_ai_service.dart';
import 'ai/presentation/widgets/ai_chat_sheet.dart';
import 'ai/presentation/widgets/ai_warning_banner.dart';
import 'ai/presentation/widgets/quotation_rule_detail_sheet.dart';
import 'cotizacion_models.dart';
import 'data/cotizacion_catalog_local_data_source.dart';
import 'data/cotizaciones_repository.dart';
import 'utils/cotizacion_pdf_service.dart';

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
  bool _restoringEditorDraft = false;
  bool _purgingAllDebug = false;

  final TextEditingController _searchCtrl = TextEditingController();

  final List<CotizacionItem> _items = [];
  List<ProductModel> _productos = const [];

  bool _loadingProducts = false;
  String? _error;
  String? _selectedCategory;
  bool _dismissAiBanner = false;

  String? _selectedClientId;
  String _selectedClientName = 'Sin cliente';
  String? _selectedClientPhone;
  String _note = '';

  bool _includeItbis = false;
  static const double _itbisRate = 0.18;
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
  static const Duration _catalogCacheFreshFor = Duration(minutes: 10);

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
    if (quotationId.isEmpty) return;
    if ((_editingId ?? '').trim() == quotationId) return;
    if (_lastLoadedRouteQuotationId == quotationId) return;

    _loadingRouteQuotation = true;
    try {
      final repository = ref.read(cotizacionesRepositoryProvider);
      final cached = await repository.getCachedById(quotationId);
      final quotation = cached ?? await repository.getByIdAndCache(quotationId);
      if (!mounted) return;

      setState(() {
        _applyQuotationToEditor(quotation);
        _writeActiveDesktopDraft();
      });
      _schedulePersistEditorDraft();
      _lastLoadedRouteQuotationId = quotationId;
      unawaited(_syncQuotationAi(triggerAi: false));
    } catch (_) {
      _lastLoadedRouteQuotationId = quotationId;
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
      final cachedRows = applyCatalogSyncVersion(rows, catalogVersion);
      final syncedAt = DateTime.now();

      unawaited(
        ref
            .read(cotizacionCatalogLocalDataSourceProvider)
            .saveSnapshot(
              cachedRows,
              syncedAt: syncedAt,
              catalogVersion: catalogVersion,
            ),
      );

      if (!mounted) return;
      setState(() {
        _productos = cachedRows;
        _loadingProducts = false;
        _error = null;
      });
      unawaited(_syncQuotationAi(triggerAi: false));
      Future<void>.microtask(
        () => FulltechImageCacheManager.warmImageUrls(
          cachedRows.map((item) => item.displayFotoUrl),
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
    try {
      final localDataSource = ref.read(
        cotizacionCatalogLocalDataSourceProvider,
      );
      final cacheSnapshot = await localDataSource.readSnapshot();
      final uiState = await localDataSource.readUiState();
      if (!mounted) return;

      final hasCachedProducts = cacheSnapshot.items.isNotEmpty;
      setState(() {
        if (hasCachedProducts) {
          _productos = cacheSnapshot.items;
          _loadingProducts = false;
          _error = null;
        }
        if (_searchCtrl.text.trim().isEmpty &&
            uiState.searchQuery.trim().isNotEmpty) {
          _searchCtrl.text = uiState.searchQuery;
        }
        if (_selectedCategory == null &&
            (uiState.selectedCategory ?? '').trim().isNotEmpty) {
          _selectedCategory = uiState.selectedCategory;
        }
      });

      if (hasCachedProducts) {
        unawaited(_syncQuotationAi(triggerAi: false));
        Future<void>.microtask(
          () => FulltechImageCacheManager.warmImageUrls(
            cacheSnapshot.items.map((item) => item.displayFotoUrl),
          ),
        );
      }

      final shouldRefresh =
          !hasCachedProducts ||
          cacheSnapshot.lastSyncedAt == null ||
          DateTime.now().difference(cacheSnapshot.lastSyncedAt!) >
              _catalogCacheFreshFor;

      if (shouldRefresh) {
        unawaited(_loadProducts(forceRemote: true, silent: true));
      }
    } catch (_) {
      if (!mounted) return;
      unawaited(_loadProducts(forceRemote: true, silent: true));
    }
  }

  void _persistCatalogUiState() {
    unawaited(
      ref
          .read(cotizacionCatalogLocalDataSourceProvider)
          .saveUiState(
            selectedCategory: _selectedCategory,
            searchQuery: _searchCtrl.text,
          ),
    );
  }

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
    _generalDiscountAmount = 0;
    _editingId = null;
    _editingCreatedAt = null;
  }

  bool get _hasEditorContent {
    return _items.isNotEmpty ||
        _searchCtrl.text.trim().isNotEmpty ||
        (_selectedClientId ?? '').trim().isNotEmpty ||
        _selectedClientName.trim() != 'Sin cliente' ||
        (_selectedClientPhone ?? '').trim().isNotEmpty ||
        _note.trim().isNotEmpty ||
        _includeItbis ||
        _generalDiscountAmount != 0 ||
        (_editingId ?? '').trim().isNotEmpty ||
        (_selectedCategory ?? '').trim().isNotEmpty;
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

  bool _hasAiBannerContent(QuotationAiState aiState) {
    return aiState.visibleWarnings.isNotEmpty ||
        aiState.analyzing ||
        aiState.loadingRules;
  }

  bool _shouldShowAiBanner(QuotationAiState aiState) {
    return _hasAiBannerContent(aiState) && !_dismissAiBanner;
  }

  void _closeAiBanner() {
    if (!mounted) return;
    setState(() => _dismissAiBanner = true);
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
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Editar ticket'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nombre del ticket'),
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Guardar'),
            ),
          ],
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

  void _deleteDesktopTicket(String id) {
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
          onRenameTicket: _renameDesktopTicket,
          onDeleteTicket: _deleteDesktopTicket,
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

  void _handleMobileBack() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    final role = ref.read(authStateProvider).user?.appRole ?? AppRole.unknown;
    context.go(RouteAccess.defaultHomeForRole(role));
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
        _commitEditorChange(_resetEditorState);
        return;
      case _MobileQuickAction.debugPurge:
        await _purgeAllDebug();
        return;
    }
  }

  Future<void> _sendQuotationToServiceOrder() async {
    if ((_selectedClientId ?? '').trim().isEmpty ||
        _selectedClientName.trim() == 'Sin cliente') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona o crea un cliente primero')),
      );
      return;
    }

    if ((_selectedClientPhone ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El cliente debe tener teléfono')),
      );
      return;
    }

    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un producto al ticket')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is ApiException
                ? error.message
                : 'No se pudo preparar la cotización para crear la orden',
          ),
        ),
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

    final opened = await context.push<bool>(
      Routes.serviceOrderCreate,
      extra: ServiceOrderCreateArgs(
        initialQuotation: savedQuotation,
        initialClientId: savedQuotation.customerId,
      ),
    );

    if (!mounted) return;
    if (opened == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Orden de servicio creada desde la cotización'),
        ),
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

  Future<_DiscountInput?> _openDiscountDialog({
    required String title,
    required String subtitle,
    _DiscountType initialType = _DiscountType.percent,
    bool allowTypeChange = true,
  }) async {
    final amountCtrl = TextEditingController();
    var type = initialType;

    try {
      return await showDialog<_DiscountInput>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(subtitle),
                  const SizedBox(height: 14),
                  if (allowTypeChange)
                    SegmentedButton<_DiscountType>(
                      segments: const [
                        ButtonSegment<_DiscountType>(
                          value: _DiscountType.percent,
                          label: Text('%'),
                          icon: Icon(Icons.percent),
                        ),
                        ButtonSegment<_DiscountType>(
                          value: _DiscountType.fixed,
                          label: Text('Monto'),
                          icon: Icon(Icons.attach_money),
                        ),
                      ],
                      selected: <_DiscountType>{type},
                      onSelectionChanged: (selection) {
                        setDialogState(() => type = selection.first);
                      },
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          dialogContext,
                        ).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            type == _DiscountType.percent
                                ? Icons.percent
                                : Icons.attach_money,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            type == _DiscountType.percent
                                ? 'Descuento porcentual'
                                : 'Descuento por monto',
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: amountCtrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: type == _DiscountType.percent
                          ? 'Porcentaje'
                          : 'Monto a descontar',
                      hintText: type == _DiscountType.percent ? '10' : '500',
                    ),
                    onSubmitted: (_) {
                      final amount = double.tryParse(amountCtrl.text.trim());
                      if (amount == null || amount <= 0) return;
                      Navigator.pop(
                        dialogContext,
                        _DiscountInput(type: type, amount: amount),
                      );
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final amount = double.tryParse(amountCtrl.text.trim());
                  if (amount == null || amount <= 0) return;
                  Navigator.pop(
                    dialogContext,
                    _DiscountInput(type: type, amount: amount),
                  );
                },
                child: const Text('Aplicar'),
              ),
            ],
          ),
        ),
      );
    } finally {
      await _disposeControllersSafely([amountCtrl]);
    }
  }

  Future<void> _applyGeneralDiscount() async {
    if (_items.isEmpty || _grossTotalBeforeGeneralDiscount <= 0) return;
    var type = _DiscountType.fixed;
    final amountCtrl = TextEditingController(
      text: _effectiveGeneralDiscountAmount > 0
          ? _effectiveGeneralDiscountAmount.toStringAsFixed(2)
          : '',
    );

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            titlePadding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    'Descuento general',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<_DiscountType>(
                    initialValue: type,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'Tipo',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: _DiscountType.fixed,
                        child: Text('Monto (RD\$)'),
                      ),
                      DropdownMenuItem(
                        value: _DiscountType.percent,
                        child: Text('Porcentaje (%)'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() => type = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: amountCtrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: type == _DiscountType.fixed
                          ? 'Monto'
                          : 'Porcentaje',
                      hintText: type == _DiscountType.fixed ? '500' : '10',
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) {
                      final raw = amountCtrl.text.trim().replaceAll(',', '.');
                      final amount = double.tryParse(raw);
                      if (amount == null || amount <= 0) {
                        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                          const SnackBar(
                            content: Text('Ingresa un valor válido'),
                          ),
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
                    },
                  ),
                ],
              ),
            ),
            actions: [
              if (_effectiveGeneralDiscountAmount > 0)
                TextButton.icon(
                  onPressed: () {
                    _commitEditorChange(() {
                      _generalDiscountAmount = 0;
                    });
                    Navigator.pop(dialogContext);
                  },
                  icon: const Icon(Icons.undo_rounded, size: 16),
                  label: const Text('Quitar'),
                ),
              FilledButton(
                onPressed: () {
                  final raw = amountCtrl.text.trim().replaceAll(',', '.');
                  final amount = double.tryParse(raw);
                  if (amount == null || amount <= 0) {
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(content: Text('Ingresa un valor válido')),
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
                },
                child: const Text('Aplicar'),
              ),
            ],
          ),
        ),
      );
    } finally {
      await _disposeControllersSafely([amountCtrl]);
    }
  }

  Future<void> _openItemDiscountMenu(int index, Offset globalPosition) async {
    if (index < 0 || index >= _items.length) return;
    final item = _items[index];
    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    final overlayObject = overlayState?.context.findRenderObject();
    if (overlayObject is! RenderBox) return;
    final overlay = overlayObject;

    final selected = await showMenu<_ItemDiscountAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem<_ItemDiscountAction>(
          value: _ItemDiscountAction.percent,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.percent),
            title: Text('Descuento %'),
          ),
        ),
        const PopupMenuItem<_ItemDiscountAction>(
          value: _ItemDiscountAction.fixed,
          child: ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.attach_money),
            title: Text('Descuento monto'),
          ),
        ),
        if (item.hasDiscount)
          const PopupMenuItem<_ItemDiscountAction>(
            value: _ItemDiscountAction.clear,
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.undo_rounded),
              title: Text('Quitar descuento'),
            ),
          ),
      ],
    );

    if (selected == null || !mounted) return;

    if (selected == _ItemDiscountAction.clear) {
      final basePrice = item.effectiveOriginalUnitPrice;
      _commitEditorChange(() {
        _items[index] = item.copyWith(
          originalUnitPrice: basePrice,
          unitPrice: basePrice,
        );
      });
      return;
    }

    final forcedType = selected == _ItemDiscountAction.percent
        ? _DiscountType.percent
        : _DiscountType.fixed;
    final input = await _openDiscountDialog(
      title: 'Descuento en ${item.nombre}',
      subtitle: 'Se aplicará solo a esta línea de la cotización.',
      initialType: forcedType,
      allowTypeChange: false,
    );
    if (input == null || !mounted) return;

    final basePrice = item.effectiveOriginalUnitPrice;
    final nextDiscount = input.type == _DiscountType.percent
        ? basePrice * (input.amount / 100)
        : input.amount;
    final boundedDiscount = nextDiscount.clamp(0, basePrice).toDouble();
    final nextUnitPrice = (basePrice - boundedDiscount)
        .clamp(0, basePrice)
        .toDouble();

    _commitEditorChange(() {
      _items[index] = item.copyWith(
        originalUnitPrice: basePrice,
        unitPrice: nextUnitPrice,
      );
    });
  }

  void _addProduct(ProductModel product) {
    final index = _items.indexWhere((item) => item.productId == product.id);
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
      text: editingItem?.externalCostUnit?.toStringAsFixed(2) ?? '',
    );
    final priceCtrl = TextEditingController(
      text: editingItem?.unitPrice.toStringAsFixed(2) ?? '',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          editingItem == null
              ? 'Agregar producto fuera de inventario'
              : 'Editar producto fuera de inventario',
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(dialogContext).nextFocus(),
                decoration: const InputDecoration(
                  labelText: 'Nombre producto o servicio',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(dialogContext).nextFocus(),
                decoration: const InputDecoration(labelText: 'Cantidad'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: costCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(dialogContext).nextFocus(),
                decoration: const InputDecoration(labelText: 'Costo unitario'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => Navigator.pop(dialogContext, true),
                decoration: const InputDecoration(labelText: 'Precio unitario'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(editingItem == null ? 'Agregar' : 'Guardar'),
          ),
        ],
      ),
    );

    final name = nameCtrl.text.trim();
    final qty = double.tryParse(qtyCtrl.text.trim()) ?? 0;
    final externalCost = costCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(costCtrl.text.trim());
    final unitPrice = double.tryParse(priceCtrl.text.trim()) ?? -1;

    await _disposeControllersSafely([nameCtrl, qtyCtrl, costCtrl, priceCtrl]);

    if (ok != true) return;

    if (name.isEmpty || qty <= 0 || unitPrice < 0 || (externalCost ?? 0) < 0) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Completa datos válidos: nombre, cantidad mayor que 0, costo y precio no negativos',
          ),
        ),
      );
      return;
    }

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
        ScaffoldMessenger.maybeOf(dialogContext)?.showSnackBar(
          const SnackBar(content: Text('Escribe una nota antes de usar IA')),
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
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Nota de cotización'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: controller,
                  minLines: 3,
                  maxLines: 5,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    hintText: 'Escribe una nota para esta cotización',
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
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(
                  dialogContext,
                  _autocorrectNoteText(controller.text),
                ),
                child: const Text('Guardar'),
              ),
            ],
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

  Future<void> enviarPdfCotizacionACliente({
    required CotizacionModel cotizacion,
    required Uint8List pdfBytes,
  }) async {
    final customerPhone = (cotizacion.customerPhone ?? '').trim();
    if (customerPhone.isEmpty) {
      throw ApiException(
        'El cliente no tiene teléfono válido para enviar la cotización.',
        null,
      );
    }

    final dateFmt = DateFormat('yyyyMMdd_HHmm');
    final fileName =
        'cotizacion_${dateFmt.format(cotizacion.createdAt)}_${cotizacion.id.substring(0, 6)}.pdf';

    await ref
        .read(cotizacionesRepositoryProvider)
        .sendWhatsAppQuotation(
          quotationId: cotizacion.id,
          destinationType: 'client',
          pdfBytes: pdfBytes,
          fileName: fileName,
          messageText: _buildCustomerDeliveryMessage(cotizacion: cotizacion),
        );
  }

  String _buildCustomerDeliveryMessage({required CotizacionModel cotizacion}) {
    final safeRecipient = cotizacion.customerName.trim().isEmpty
        ? 'Hola'
        : 'Hola ${cotizacion.customerName.trim()}';
    final quoteCode = _buildQuotationCode(cotizacion.id);
    final total = formatRdCurrencyAccounting(cotizacion.total);

    return [
      '$safeRecipient, te compartimos tu cotización en PDF.',
      'Cotización: $quoteCode',
      'Cliente: ${cotizacion.customerName}',
      'Total: $total',
    ].join('\n');
  }

  String _customerDeliveryButtonLabel(bool compact) {
    return compact ? 'A cliente' : 'Enviar al cliente';
  }

  String _tinyCustomerPhoneHint(CotizacionModel cotizacion) {
    final phone = (cotizacion.customerPhone ?? '').trim();
    if (phone.isEmpty) return '';
    return 'Cliente: $phone';
  }

  String _customerDeliverySuccessMessage() {
    return 'Cotización enviada al cliente correctamente.';
  }

  String _customerDeliveryTimeoutMessage() {
    return 'Tiempo de espera agotado enviando el PDF al cliente.';
  }

  String _customerDeliveryErrorPrefix() {
    return 'No se pudo enviar el PDF al cliente';
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

  String _buildAdminApprovalMessage(CotizacionModel cotizacion) {
    final sellerName = (cotizacion.createdByUserName ?? '').trim();
    final safeSellerName = sellerName.isEmpty ? 'El vendedor' : sellerName;
    return '$safeSellerName quiere que confirme esta cotización y que esté en orden.';
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

  String _buildQuotationCode(String id) {
    final normalized = id.replaceAll('-', '').trim().toUpperCase();
    if (normalized.isEmpty) {
      return 'COT-MANUAL';
    }
    final token = normalized.length > 8
        ? normalized.substring(0, 8)
        : normalized;
    return 'COT-$token';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega productos para generar PDF')),
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
        var sendingWhatsApp = false;
        var sendingAdminApproval = false;
        String? dialogNotification;
        bool dialogNotificationIsError = false;
        final media = MediaQuery.sizeOf(context);
        final compact = media.width < 560;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canSend = !sendingWhatsApp;
            final canSendAdmin = !sendingAdminApproval;

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

            Future<void> sendWhatsApp() async {
              setDialogState(() => sendingWhatsApp = true);
              try {
                showDialogNotification('Enviando cotización al cliente...');
                final persisted = await _ensurePersistedQuotationForSend(
                  cotizacion,
                );
                await enviarPdfCotizacionACliente(
                  cotizacion: persisted,
                  pdfBytes: bytes,
                ).timeout(const Duration(seconds: 25));
                showDialogNotification(_customerDeliverySuccessMessage());
              } on TimeoutException {
                showDialogNotification(
                  _customerDeliveryTimeoutMessage(),
                  isError: true,
                );
              } on ApiException catch (e) {
                showDialogNotification(
                  _formatWhatsAppSendError(e, toAdmin: false),
                  isError: true,
                );
              } catch (e) {
                showDialogNotification(
                  '${_customerDeliveryErrorPrefix()}: $e',
                  isError: true,
                );
              } finally {
                if (context.mounted) {
                  setDialogState(() => sendingWhatsApp = false);
                }
              }
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
                              TextButton.icon(
                                onPressed: canSend ? sendWhatsApp : null,
                                icon: sendingWhatsApp
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.chat_outlined),
                                label: Text(
                                  _customerDeliveryButtonLabel(compact),
                                ),
                              ),
                              const SizedBox(width: 6),
                              TextButton.icon(
                                onPressed: canSendAdmin
                                    ? sendAdminApproval
                                    : null,
                                icon: sendingAdminApproval
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.verified_user_outlined),
                                label: Text(
                                  compact ? 'A admin' : 'Enviar a admin',
                                ),
                              ),
                              const SizedBox(width: 6),
                              TextButton.icon(
                                onPressed: () => shareCotizacionPdf(
                                  bytes: bytes,
                                  cotizacion: cotizacion,
                                ),
                                icon: const Icon(Icons.download_outlined),
                                label: const Text('Descargar'),
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
                          allowPrinting: true,
                          allowSharing: true,
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

  Future<void> _openHistory() async {
    final payload = await context.push<CotizacionEditorPayload>(
      Routes.cotizacionesHistorial,
    );

    if (payload == null || !mounted) return;

    _commitEditorChange(() {
      _items
        ..clear()
        ..addAll(payload.source.items.map((item) => item.copyWith()));
      _selectedClientId = payload.source.customerId;
      _selectedClientName = payload.source.customerName;
      _selectedClientPhone = payload.source.customerPhone;
      _note = payload.source.note;
      _includeItbis = payload.source.includeItbis;
      _editingId = payload.duplicate ? null : payload.source.id;
      _editingCreatedAt = payload.duplicate ? null : payload.source.createdAt;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          payload.duplicate
              ? 'Cotización duplicada en editor'
              : 'Cotización cargada para editar',
        ),
      ),
    );
  }

  void _openInventoryCatalog() {
    context.go('${Routes.catalogo}?tab=catalog');
  }

  void _openStockAdjustments() {
    context.go('${Routes.catalogo}?tab=stock');
  }

  void _openSalesList() {
    context.go(Routes.ventasLista);
  }

  Future<void> _finalizeCotizacion() async {
    if (_selectedClientId == null || _selectedClientName == 'Sin cliente') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona o crea un cliente primero')),
      );
      return;
    }

    if ((_selectedClientPhone ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El cliente debe tener teléfono')),
      );
      return;
    }

    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agrega al menos un producto al ticket')),
      );
      return;
    }

    final wasEditing = (_editingId ?? '').trim().isNotEmpty;
    final cotizacion = _buildDraftCotizacion();
    CotizacionModel? savedQuotation;
    var queued = false;
    try {
      final repository = ref.read(cotizacionesRepositoryProvider);
      if (widget.returnSavedQuotation) {
        savedQuotation = (_editingId ?? '').trim().isEmpty
            ? await repository.create(cotizacion)
            : await repository.update(_editingId!, cotizacion);
      } else {
        queued = (_editingId ?? '').trim().isEmpty
            ? await repository.createOrQueue(cotizacion)
            : await repository.updateOrQueue(_editingId!, cotizacion);
      }

      if (!mounted) return;

      if (!widget.returnSavedQuotation) {
        _commitEditorChange(_resetEditorState);
        _schedulePersistEditorDraft(immediate: true);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.returnSavedQuotation
                ? wasEditing
                      ? 'Cotización actualizada'
                      : 'Cotización creada'
                : queued
                ? 'Cotización guardada localmente. Se sincronizará en segundo plano.'
                : wasEditing
                ? 'Cotización actualizada en nube'
                : 'Cotización guardada en nube',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is ApiException ? e.message : '$e')),
      );
      return;
    }

    if (widget.returnSavedQuotation && mounted) {
      context.pop(savedQuotation);
      return;
    }

    final qp = GoRouterState.of(context).uri.queryParameters;
    final popOnSave = (qp['popOnSave'] ?? '').trim() == '1';
    if (popOnSave && mounted) {
      context.pop(true);
    }
  }

  Future<void> _purgeAllDebug() async {
    final confirmed = await confirmDebugAdminPurge(
      context,
      moduleLabel: 'cotizaciones',
      impactLabel:
          'todas las cotizaciones guardadas y su historial relacionado',
    );
    if (!confirmed || !mounted) return;

    setState(() => _purgingAllDebug = true);
    try {
      final result = await ref
          .read(cotizacionesRepositoryProvider)
          .purgeAllDebug();
      if (!mounted) return;

      _commitEditorChange(_resetEditorState);
      _schedulePersistEditorDraft(immediate: true);

      final deleted = (result['deletedQuotes'] as num?)?.toInt() ?? 0;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Se limpiaron $deleted cotizaciones.')),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e is ApiException ? e.message : '$e';
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() => _purgingAllDebug = false);
      }
    }
  }

  AppBar _buildDesktopAppBar(QuotationAiState aiState) {
    final currentUser = ref.read(authStateProvider).user;
    final showAiBanner = _shouldShowAiBanner(aiState);
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF111827),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: const Border(bottom: BorderSide(color: Color(0xFFD3E0E7))),
      leading: Builder(
        builder: (context) => Padding(
          padding: const EdgeInsets.only(left: 10, top: 8, bottom: 8),
          child: IconButton(
            tooltip: 'Menú',
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(Icons.menu_rounded),
            color: const Color(0xFF1957E6),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFEAF1FF),
              side: const BorderSide(color: Color(0xFFCFE0FF)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ),
      title: const Text(
        'Ventas TPV',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      actions: [
        _DesktopTopbarAction(
          icon: Icons.person_outline_rounded,
          label: 'Cliente',
          onPressed: _openClientDialog,
        ),
        _DesktopTopbarAction(
          icon: _note.trim().isEmpty
              ? Icons.sticky_note_2_outlined
              : Icons.sticky_note_2,
          label: 'Notas',
          onPressed: _openNoteDialog,
        ),
        _DesktopTopbarAction(
          icon: Icons.picture_as_pdf_outlined,
          label: 'PDF',
          onPressed: _openPdfPreview,
        ),
        _DesktopTopbarAction(
          icon: Icons.assignment_turned_in_outlined,
          label: 'Orden',
          onPressed: _sendQuotationToServiceOrder,
        ),
        if (showAiBanner)
          IconButton(
            tooltip: 'Cerrar comentario IA',
            onPressed: _closeAiBanner,
            icon: const Icon(Icons.close_rounded),
          ),
        DebugAdminActionButton(
          user: currentUser,
          busy: _purgingAllDebug,
          tooltip: 'Limpiar módulo (debug)',
          onPressed: _purgeAllDebug,
        ),
        const SizedBox(width: 8),
      ],
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
                        onRequestDiscount: (position) =>
                            _openItemDiscountMenu(index, position),
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
                            _commitEditorChange(() => _includeItbis = value),
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
                        onPressed: _finalizeCotizacion,
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

  Widget _buildMobileTopBar(
    UserModel? currentUser, {
    required bool showAiBanner,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Row(
        children: [
          Material(
            color: Colors.white.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: _handleMobileBack,
              borderRadius: BorderRadius.circular(14),
              child: const Padding(
                padding: EdgeInsets.all(10),
                child: Icon(Icons.arrow_back_rounded, size: 20),
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
              if (currentUser?.appRole == AppRole.admin)
                PopupMenuItem(
                  height: 52,
                  value: _MobileQuickAction.debugPurge,
                  child: _MobileQuickMenuEntry(
                    icon: Icons.cleaning_services_outlined,
                    label: 'Purge debug',
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
        _buildMobileTopBar(currentUser, showAiBanner: showAiBanner),
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

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _DesktopCatalogPane(
                        searchController: _searchCtrl,
                        selectedCategory: _selectedCategory,
                        categories: _categories,
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
                      child: _DesktopQuotePanel(
                        items: _items,
                        selectedClientName: _selectedClientName,
                        includeItbis: _includeItbis,
                        subtotalBeforeDiscount: _subtotalBeforeDiscount,
                        discountAmount: _discountAmount,
                        generalDiscountAmount: _effectiveGeneralDiscountAmount,
                        subtotal: _subtotal,
                        itbisAmount: _itbisAmount,
                        total: _total,
                        isAdmin: isAdmin,
                        utilityAmount: _utilityAmount,
                        money: _money,
                        onPickClient: _openClientDialog,
                        onOpenHistory: _openSalesList,
                        onToggleItbis: (value) =>
                            _commitEditorChange(() => _includeItbis = value),
                        onClear: !_hasEditorContent
                            ? null
                            : () {
                                _commitEditorChange(_resetEditorState);
                              },
                        onFinalize: _finalizeCotizacion,
                        onMinusQty: (index) =>
                            _setQty(index, _items[index].qty - 1),
                        onPlusQty: (index) =>
                            _setQty(index, _items[index].qty + 1),
                        onChangePrice: _setUnitPrice,
                        onEditExternalItem: (index) =>
                            _openExternalItemDialog(editIndex: index),
                        onRemoveItem: (index) =>
                            _commitEditorChange(() => _items.removeAt(index)),
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
  debugPurge,
}

class _DesktopTopbarAction extends StatelessWidget {
  const _DesktopTopbarAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF123A75),
          backgroundColor: const Color(0xFFF3F7FF),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          minimumSize: const Size(0, 34),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 0,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFCFE0FF)),
          ),
        ),
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
            const SizedBox(height: 8),
            _DesktopCategoryStrip(
              categories: widget.categories,
              allProducts: widget.allProducts,
              selectedCategory: widget.selectedCategory,
              onSelectCategory: widget.onSelectCategory,
            ),
            const SizedBox(height: 8),
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
    required this.onClear,
    required this.onFinalize,
    required this.onMinusQty,
    required this.onPlusQty,
    required this.onChangePrice,
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
  final VoidCallback? onClear;
  final VoidCallback onFinalize;
  final ValueChanged<int> onMinusQty;
  final ValueChanged<int> onPlusQty;
  final void Function(int index, double value) onChangePrice;
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
                        label: 'Rebaja',
                        value: '-${money(generalDiscountAmount)}',
                        valueColor: const Color(0xFF1957E6),
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
                    if (includeItbis || onClear != null)
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
    required this.selectedCategory,
    required this.onSelectCategory,
  });

  final List<String> categories;
  final List<ProductModel> allProducts;
  final String? selectedCategory;
  final ValueChanged<String?> onSelectCategory;

  ProductModel? _thumbnailProduct(String category) {
    for (final product in allProducts) {
      if (product.categoriaLabel == category) return product;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hasFilter = selectedCategory != null;
    final totalItems = categories.length + (hasFilter ? 1 : 0);

    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: totalItems,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (hasFilter && index == 0) {
            return SizedBox(
              width: 88,
              child: Material(
                color: const Color(0xFF1957E6),
                borderRadius: BorderRadius.circular(9),
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
                        fontSize: 12,
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
          return _DesktopCategoryStripItem(
            label: category,
            product: product,
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
    required this.selected,
    required this.onTap,
  });

  final String label;
  final ProductModel? product;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = product?.displayFotoUrl?.trim() ?? '';
    final normalizedLabel = label.trim().toUpperCase();
    final tileWidth = (normalizedLabel.length * 7.2 + 64).clamp(132.0, 280.0);

    return SizedBox(
      width: tileWidth,
      child: Material(
        color: selected ? const Color(0xFFEAF1FF) : Colors.white,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
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
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFCFE0FF)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0B2A3A).withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: imageUrl.isEmpty || product == null
                      ? const Icon(
                          Icons.inventory_2_outlined,
                          color: Color(0xFF8DA2B4),
                          size: 18,
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
                            size: 18,
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    normalizedLabel,
                    maxLines: 2,
                    softWrap: true,
                    overflow: TextOverflow.visible,
                    style: TextStyle(
                      color: const Color(0xFF152238),
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                      fontSize: 11.2,
                      height: 1.05,
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

class _DesktopTicketItem extends StatefulWidget {
  const _DesktopTicketItem({
    required this.item,
    required this.money,
    required this.onMinus,
    required this.onPlus,
    required this.onChangePrice,
    required this.onEdit,
    required this.onRemove,
  });

  final CotizacionItem item;
  final String Function(double) money;
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
      text: widget.item.unitPrice.toStringAsFixed(2),
    );
  }

  @override
  void didUpdateWidget(covariant _DesktopTicketItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.unitPrice != widget.item.unitPrice) {
      _priceCtrl.text = widget.item.unitPrice.toStringAsFixed(2);
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
        onTap: null,
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
                              _buildTicketTag(
                                label: 'Desc. -$discountText',
                                backgroundColor: Colors.red.shade50,
                                foregroundColor: Colors.red.shade700,
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
                    final parsed = double.tryParse(value.trim());
                    if (parsed != null) widget.onChangePrice(parsed);
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

class _DiscountInput {
  const _DiscountInput({required this.type, required this.amount});

  final _DiscountType type;
  final double amount;
}

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
    required this.onRequestDiscount,
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
  final ValueChanged<Offset> onRequestDiscount;
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
  Offset? _lastDoubleTapGlobalPosition;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(
      text: widget.item.unitPrice.toStringAsFixed(2),
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
      _priceCtrl.text = widget.item.unitPrice.toStringAsFixed(2);
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
        onDoubleTapDown: (details) {
          _lastDoubleTapGlobalPosition = details.globalPosition;
        },
        onDoubleTap: () {
          final position = _lastDoubleTapGlobalPosition;
          if (position != null) {
            widget.onRequestDiscount(position);
          }
        },
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
                        final next = double.tryParse(value.trim());
                        if (next != null) widget.onChangePrice(next);
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

enum _ItemDiscountAction { percent, fixed, clear }

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
