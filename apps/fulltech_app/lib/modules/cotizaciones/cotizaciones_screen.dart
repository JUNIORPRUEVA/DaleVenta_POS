import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../../core/app_access/app_access_links.dart';
import '../../core/auth/admin_authorization.dart';
import '../../core/auth/admin_authorization_session.dart';
import '../../core/auth/app_permissions.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/auth/app_role.dart';
import '../../core/cache/fulltech_cache_manager.dart';
import '../../core/cache/local_json_cache.dart';
import '../../core/company/company_settings_model.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/design_system/icons/app_icon.dart';
import '../../core/design_system/icons/app_icons.dart';
import '../../core/errors/api_exception.dart';
import '../../core/license/license_repository.dart';
import '../../core/models/user_model.dart';
import '../../core/models/product_model.dart';
import '../../core/printing/unified_ticket_printer.dart';
import '../../core/realtime/catalog_realtime_service.dart';
import '../../core/routing/app_route_observer.dart';
import '../../core/routing/route_access.dart';
import '../../core/routing/routes.dart';
import '../../core/tax/product_tax_preview_calculator.dart';
import '../../core/tax/product_tax_options_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/fulltech_dialog.dart';
import '../../core/widgets/fulltech_page_header.dart';
import '../../core/widgets/pdf_action_menu.dart';
import '../../core/widgets/responsive_shell.dart';
import '../../core/widgets/product_network_image.dart';
import '../../core/widgets/user_avatar.dart';
import '../../features/catalogo/application/catalog_controller.dart';
import '../../features/catalogo/data/catalog_repository.dart';
import '../../features/catalogo/data/catalog_sync_utils.dart';
import '../../features/account/delete_account_dialog.dart';
import '../../features/products/ui/inventory_module_pages.dart';
import '../cash/cash_repository.dart';
import '../cash/cash_models.dart';
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
import 'data/open_sales_tickets_repository.dart';
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

class _QuoteTaxSummary {
  const _QuoteTaxSummary({
    required this.taxEnabled,
    required this.taxableBase,
    required this.taxAmount,
    required this.exemptAmount,
    required this.total,
    required this.defaultRate,
  });

  final bool taxEnabled;
  final double taxableBase;
  final double taxAmount;
  final double exemptAmount;
  final double total;
  final double defaultRate;
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

CotizacionItem buildBillingItemFromProduct(ProductModel product) {
  return CotizacionItem(
    productId: product.id,
    nombre: product.nombre,
    imageUrl: product.displayFotoUrl,
    originalUnitPrice: product.precio,
    unitPrice: product.precio,
    qty: 1,
    costUnit: product.costo,
    taxTreatment: product.taxTreatment,
    taxRate: product.taxRate ?? 0,
    taxPriceMode: product.taxPriceMode ?? 'NO_TAX',
  );
}

CotizacionItem syncBillingItemFiscalFromProduct(
  CotizacionItem item,
  ProductModel product,
) {
  return item.copyWith(
    taxTreatment: product.taxTreatment,
    taxRate: product.taxRate ?? 0,
    taxPriceMode: product.taxPriceMode ?? 'NO_TAX',
  );
}

List<CotizacionItem> syncBillingItemsFiscalFromProducts({
  required Iterable<CotizacionItem> items,
  required Map<String, ProductModel> productsById,
}) {
  return items
      .map((item) {
        final product = productsById[item.productId];
        if (product == null) return item;
        return syncBillingItemFiscalFromProduct(item, product);
      })
      .toList(growable: false);
}

bool _areBillingItemsFiscalEquivalent(
  List<CotizacionItem> previous,
  List<CotizacionItem> next,
) {
  if (previous.length != next.length) return false;
  for (var index = 0; index < previous.length; index++) {
    final left = previous[index];
    final right = next[index];
    if (left.taxTreatment != right.taxTreatment ||
        left.taxRate != right.taxRate ||
        left.taxPriceMode != right.taxPriceMode) {
      return false;
    }
  }
  return true;
}

bool shouldShowBillingItbis({
  required bool taxEnabled,
  required double taxAmount,
}) {
  return taxEnabled && taxAmount > 0;
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
  final FocusNode _mobileSearchFocusNode = FocusNode();

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
  bool _openingBarcodeScanner = false;
  bool _finalizingCheckout = false;
  bool _barcodeCatalogRefreshInFlight = false;
  DateTime? _lastBarcodeCatalogRefreshAt;
  double _mobileCartExtent = 0;
  bool _mobileCartExtentInitialized = false;

  String? _lastRoutePrefillUri;
  bool _routeObserverSubscribed = false;
  RouteObserver<ModalRoute<dynamic>>? _routeObserver;
  String? _lastLoadedRouteQuotationId;
  bool _loadingRouteQuotation = false;
  bool _remoteRefreshInFlight = false;
  DateTime? _lastSuccessfulRemoteSyncAt;
  DateTime? _lastAutoSyncAt;
  Timer? _liveSyncTimer;
  StreamSubscription<CatalogRealtimeMessage>? _realtimeSubscription;
  late final OpenSalesTicketsRepository _openTicketsRepository;
  String _sessionCompanyId = '';
  String? _sessionUserId;
  String? _sessionUserName;
  static const Duration _liveSyncInterval = Duration(minutes: 2);
  static const Duration _silentRefreshMinInterval = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    _openTicketsRepository = ref.read(openSalesTicketsRepositoryProvider);
    final user = ref.read(authStateProvider).user;
    _sessionCompanyId = (user?.companyId ?? '').trim();
    _sessionUserId = user?.id;
    _sessionUserName = user?.nombreCompleto;
    final initialDraft = _DesktopTicketDraft.empty(
      id: _newId(),
      title: 'Ticket 1',
      companyId: _sessionCompanyId.isEmpty ? null : _sessionCompanyId,
      createdByUserId: _sessionUserId,
      createdByUserName: _sessionUserName,
    );
    _desktopTickets = [initialDraft];
    _activeDesktopTicketId = initialDraft.id;
    ref.listenManual<AuthState>(authStateProvider, (previous, next) {
      final previousCompanyId = (previous?.user?.companyId ?? '').trim();
      final nextCompanyId = (next.user?.companyId ?? '').trim();
      if (previousCompanyId == nextCompanyId) return;
      _handleCompanyChanged(nextCompanyId, next.user);
    });
    ref.listenManual<CatalogState>(catalogControllerProvider, (previous, next) {
      _applyCatalogControllerProducts(next.items);
    });
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

    final routeUri = _safeRouteUri()?.toString() ?? '';
    if (_lastRoutePrefillUri == routeUri) return;
    _lastRoutePrefillUri = routeUri;

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

  void _handleCompanyChanged(String companyId, UserModel? user) {
    if (!mounted) return;
    _sessionCompanyId = companyId;
    _sessionUserId = user?.id;
    _sessionUserName = user?.nombreCompleto;
    final initialDraft = _DesktopTicketDraft.empty(
      id: _newId(),
      title: 'Ticket 1',
      companyId: companyId.isEmpty ? null : companyId,
      createdByUserId: _sessionUserId,
      createdByUserName: _sessionUserName,
    );
    setState(() {
      _desktopTickets = [initialDraft];
      _activeDesktopTicketId = initialDraft.id;
      _resetEditorState();
    });
    ref.invalidate(productTaxUiConfigProvider);
    ref.invalidate(catalogControllerProvider);
    ref.invalidate(cotizacionesRepositoryProvider);
    ref.invalidate(ventasControllerProvider);
    _schedulePersistEditorDraft(immediate: true);
    unawaited(_bootstrapCatalog());
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
    _generalDiscountAmount = quotation.globalDiscountAmount;
    _editingId = quotation.id;
    _editingCreatedAt = quotation.createdAt;
  }

  _DesktopTicketDraft _ticketDraftFromQuotation(
    CotizacionModel quotation, {
    required bool duplicate,
  }) {
    final user = ref.read(authStateProvider).user;
    final cleanCustomer = quotation.customerName.trim();
    return _DesktopTicketDraft.empty(
      id: _newId(),
      title: cleanCustomer.isEmpty || cleanCustomer == 'Sin cliente'
          ? _nextDesktopTicketTitle()
          : cleanCustomer,
      companyId: user?.companyId,
      createdByUserId: user?.id,
      createdByUserName: user?.nombreCompleto,
    ).copyWith(
      items: quotation.items.map((item) => item.copyWith()).toList(),
      selectedClientId: quotation.customerId,
      selectedClientName: cleanCustomer.isEmpty ? 'Sin cliente' : cleanCustomer,
      selectedClientPhone: quotation.customerPhone,
      note: quotation.note,
      includeItbis: quotation.includeItbis,
      globalDiscountAmount: quotation.globalDiscountAmount,
      editingId: duplicate ? null : quotation.id,
      editingCreatedAt: duplicate ? null : quotation.createdAt,
    );
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

  void _applyCatalogControllerProducts(List<ProductModel> rows) {
    if (!mounted || rows.isEmpty) return;
    final catalogVersion = buildCatalogSyncVersion(rows);
    final syncedRows = applyCatalogSyncVersion(rows, catalogVersion);
    final productsChanged = !areCatalogProductsEquivalent(
      _productos,
      syncedRows,
    );
    final productsById = {
      for (final product in syncedRows) product.id: product,
    };
    var itemsChanged = false;
    final nextItems = syncBillingItemsFiscalFromProducts(
      items: _items,
      productsById: productsById,
    );
    itemsChanged = !_areBillingItemsFiscalEquivalent(_items, nextItems);

    if (!productsChanged && !itemsChanged && !_loadingProducts) return;

    setState(() {
      if (productsChanged) {
        _productos = syncedRows;
      }
      if (itemsChanged) {
        _items
          ..clear()
          ..addAll(nextItems);
        _writeActiveDesktopDraft();
      }
      _loadingProducts = false;
      _error = null;
    });
    if (itemsChanged) {
      _schedulePersistEditorDraft();
      unawaited(_syncQuotationAi());
    }
  }

  bool _syncEditorItemsFiscalWithLoadedProducts() {
    if (_productos.isEmpty || _items.isEmpty) return false;
    final productsById = {
      for (final product in _productos) product.id: product,
    };
    final nextItems = syncBillingItemsFiscalFromProducts(
      items: _items,
      productsById: productsById,
    );
    if (_areBillingItemsFiscalEquivalent(_items, nextItems)) return false;
    _items
      ..clear()
      ..addAll(nextItems);
    _writeActiveDesktopDraft();
    return true;
  }

  void _startLiveSync() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = Timer.periodic(_liveSyncInterval, (_) {
      if (!mounted) return;
      _loadProducts(silent: true);
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
      _loadProducts(silent: true);
    });
  }

  void _syncProductsOnEnter() {
    if (!mounted) return;
    _clearMobileSearchFocus();
    _loadProducts(silent: true);
  }

  void _clearMobileSearchFocus() {
    final width = MediaQuery.maybeSizeOf(context)?.width;
    if (width == null || width >= _desktopBreakpoint) return;
    _mobileSearchFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
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
      _loadProducts(silent: true);
      return;
    }

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _writeActiveDesktopDraft();
      _schedulePersistEditorDraft(immediate: true);
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
    final openInNewTicket = (qp['newTicket'] ?? '').trim() == '1';
    final ticketSeed = (qp['ticketSeed'] ?? '').trim();
    if (quotationId.isEmpty) return;
    final routeQuotationKey =
        '$quotationId:${duplicate ? 'duplicate' : 'source'}:${openInNewTicket ? 'new' : 'current'}:$ticketSeed';
    if (!openInNewTicket &&
        !duplicate &&
        (_editingId ?? '').trim() == quotationId) {
      return;
    }
    if (_lastLoadedRouteQuotationId == routeQuotationKey) return;

    _loadingRouteQuotation = true;
    try {
      final repository = ref.read(cotizacionesRepositoryProvider);
      final cached = await repository.getCachedById(quotationId);
      final quotation = cached ?? await repository.getByIdAndCache(quotationId);
      if (!mounted) return;

      setState(() {
        if (openInNewTicket) {
          _writeActiveDesktopDraft();
          final ticket = _ticketDraftFromQuotation(
            quotation,
            duplicate: duplicate,
          );
          _desktopTickets = [ticket, ..._desktopTickets];
          _activeDesktopTicketId = ticket.id;
          _showMobileTicketDropdown = false;
          _replaceEditorStateFromDraft(ticket);
          _writeActiveDesktopDraft();
        } else {
          _applyQuotationToEditor(quotation);
          if (duplicate) {
            _editingId = null;
            _editingCreatedAt = null;
          }
          _writeActiveDesktopDraft();
        }
      });
      _lastLoadedRouteQuotationId = routeQuotationKey;
      _schedulePersistEditorDraft(immediate: true);
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
    _writeActiveDesktopDraft(readTaxProvider: false);
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
    _mobileSearchFocusNode.dispose();
    super.dispose();
  }

  String _editorDraftCacheKey() {
    final companyId = _sessionCompanyId.trim();
    if (companyId.isNotEmpty) {
      return '${_editorDraftCachePrefix}company:$companyId';
    }
    final ownerId = (_sessionUserId ?? 'anon').trim();
    return '${_editorDraftCachePrefix}user:$ownerId';
  }

  String _activeCompanyId() => _sessionCompanyId.trim();

  bool _belongsToActiveCompany(_DesktopTicketDraft ticket) {
    final companyId = _activeCompanyId();
    final ticketCompanyId = (ticket.companyId ?? '').trim();
    return companyId.isEmpty ||
        ticketCompanyId.isEmpty ||
        ticketCompanyId == companyId;
  }

  int _compareDesktopTickets(
    _DesktopTicketDraft left,
    _DesktopTicketDraft right,
  ) {
    final byDate = right.createdAt.compareTo(left.createdAt);
    if (byDate != 0) return byDate;
    return right.id.compareTo(left.id);
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
    try {
      final map = <String, dynamic>{
        'v': 2,
        'companyId': _activeCompanyId(),
        'activeId': _activeDesktopTicketId,
        'tickets': ([
          ..._desktopTickets,
        ]..sort(_compareDesktopTickets)).map((t) => t.toMap()).toList(),
      };
      await _editorDraftCache.writeMap(_editorDraftCacheKey(), map);
      await _openTicketsRepository.replace(
        activeId: _activeDesktopTicketId,
        tickets: (map['tickets'] as List)
            .whereType<Map>()
            .map((row) => row.cast<String, dynamic>())
            .toList(growable: false),
      );
    } catch (_) {
      // Best-effort.
    }
  }

  Future<void> _restorePersistedEditorDraftIfAny() async {
    if (!mounted) return;
    _restoringEditorDraft = true;
    try {
      final remote = await ref.read(openSalesTicketsRepositoryProvider).fetch();
      final cached =
          remote ?? await _editorDraftCache.readMap(_editorDraftCacheKey());
      if (!mounted) return;
      if (cached == null) return;

      final rawTickets = (cached['tickets'] as List?) ?? const [];
      final tickets =
          rawTickets
              .whereType<Map>()
              .map(
                (row) =>
                    _DesktopTicketDraft.fromMap(row.cast<String, dynamic>()),
              )
              .where(_belongsToActiveCompany)
              .toList()
            ..sort(_compareDesktopTickets);

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
        _syncEditorItemsFiscalWithLoadedProducts();
        _writeActiveDesktopDraft();
      });
      _applyClientPrefillFromRoute(force: true);
      unawaited(_applyQuotationPrefillFromRoute());
      if (remote == null) {
        _schedulePersistEditorDraft(immediate: true);
      }
      unawaited(_syncQuotationAi(triggerAi: false));
    } catch (_) {
      try {
        final cached = await _editorDraftCache.readMap(_editorDraftCacheKey());
        if (!mounted || cached == null) return;
        final rawTickets = (cached['tickets'] as List?) ?? const [];
        final tickets =
            rawTickets
                .whereType<Map>()
                .map(
                  (row) =>
                      _DesktopTicketDraft.fromMap(row.cast<String, dynamic>()),
                )
                .where(_belongsToActiveCompany)
                .toList()
              ..sort(_compareDesktopTickets);
        if (tickets.isEmpty) return;
        final activeId = tickets.first.id;
        setState(() {
          _desktopTickets = tickets;
          _activeDesktopTicketId = activeId;
          _replaceEditorStateFromDraft(tickets.first);
          _syncEditorItemsFiscalWithLoadedProducts();
          _writeActiveDesktopDraft();
        });
        unawaited(_applyQuotationPrefillFromRoute());
      } catch (_) {
        // Ignore invalid cache entries.
      }
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

    final requestCompanyId =
        ref.read(authStateProvider).user?.companyId?.trim() ?? '';
    if (requestCompanyId.isEmpty) return;

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
      if (ref.read(authStateProvider).user?.companyId?.trim() !=
          requestCompanyId) {
        return;
      }
      final catalogVersion = buildCatalogSyncVersion(rows);
      final syncedRows = applyCatalogSyncVersion(rows, catalogVersion);
      final syncedAt = DateTime.now();

      if (!mounted) return;
      final productsById = {
        for (final product in syncedRows) product.id: product,
      };
      var itemsChanged = false;
      final nextItems = syncBillingItemsFiscalFromProducts(
        items: _items,
        productsById: productsById,
      );
      itemsChanged = !_areBillingItemsFiscalEquivalent(_items, nextItems);
      if (!areCatalogProductsEquivalent(_productos, syncedRows) ||
          itemsChanged) {
        setState(() {
          _productos = syncedRows;
          if (itemsChanged) {
            _items
              ..clear()
              ..addAll(nextItems);
            _writeActiveDesktopDraft();
          }
          _loadingProducts = false;
          _error = null;
        });
        if (itemsChanged) {
          _schedulePersistEditorDraft();
          unawaited(_syncQuotationAi());
        }
      } else if (_loadingProducts) {
        setState(() {
          _loadingProducts = false;
          _error = null;
        });
      }
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
    await _loadProducts();
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

  ProductModel? _findProductByExactCode(
    Iterable<ProductModel> products,
    String rawCode,
  ) {
    final code = rawCode.trim();
    if (code.isEmpty) return null;
    for (final product in products) {
      if (!product.activo) continue;
      final productCode = (product.codigo ?? '').trim();
      if (productCode.isNotEmpty && productCode == code) return product;
    }
    return null;
  }

  Future<ProductModel?> _resolveProductByBarcode(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) return null;

    final localMatch = _findProductByExactCode(_productos, code);
    if (localMatch != null) return localMatch;

    final lastRefresh = _lastBarcodeCatalogRefreshAt;
    if (_barcodeCatalogRefreshInFlight ||
        (lastRefresh != null &&
            DateTime.now().difference(lastRefresh) <
                const Duration(seconds: 20))) {
      return null;
    }

    _barcodeCatalogRefreshInFlight = true;
    try {
      final rows = await ref
          .read(catalogRepositoryProvider)
          .fetchProducts(forceRefresh: true, silent: true);
      final catalogVersion = buildCatalogSyncVersion(rows);
      final syncedRows = applyCatalogSyncVersion(rows, catalogVersion);
      _lastBarcodeCatalogRefreshAt = DateTime.now();
      if (!mounted) return null;
      setState(() {
        _productos = syncedRows;
        _loadingProducts = false;
        _error = null;
      });
      return _findProductByExactCode(_productos, code);
    } finally {
      _barcodeCatalogRefreshInFlight = false;
    }
  }

  Future<_BarcodeScanResult> _handleScannedBarcode(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) {
      return const _BarcodeScanResult.ignored();
    }

    try {
      final product = await _resolveProductByBarcode(code);
      if (product == null) {
        return _BarcodeScanResult.notFound(code);
      }

      if (!mounted) {
        return const _BarcodeScanResult.ignored();
      }
      _addProduct(product);
      await HapticFeedback.lightImpact();
      return _BarcodeScanResult.added(product.nombre);
    } catch (_) {
      return _BarcodeScanResult.error(code);
    }
  }

  Future<void> _openBarcodeScanner() async {
    if (_openingBarcodeScanner) return;
    _openingBarcodeScanner = true;
    try {
      if (kIsWeb ||
          !(defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS)) {
        _showSalesNotice(
          title: 'Scanner no disponible',
          message:
              'El scanner con cámara está disponible en teléfonos Android o iPhone.',
          icon: Icons.qr_code_scanner_rounded,
          accent: const Color(0xFFF59E0B),
        );
        return;
      }

      FocusScope.of(context).unfocus();
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) =>
              _MobileBarcodeScannerPage(onBarcode: _handleScannedBarcode),
        ),
      );
    } finally {
      _openingBarcodeScanner = false;
    }
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

  ProductTaxUiConfig? get _currentTaxConfig =>
      ref.read(productTaxUiConfigProvider).valueOrNull;

  _QuoteTaxSummary get _quoteTaxSummary {
    final config = _currentTaxConfig;
    final settings = config?.settings;
    final taxEnabled = settings?.taxEnabled == true;
    final defaultRate = config?.defaultRate ?? settings?.defaultTaxRate ?? 0.18;
    final pricesIncludeTax = settings?.pricesIncludeTax ?? true;

    final summary = ProductTaxPreviewCalculator.calculateCart(
      lines: [
        for (final item in _items)
          ProductCartTaxLineInput(
            price: item.unitPrice,
            quantity: item.qty,
            taxTreatment: item.taxTreatment,
            taxRate: item.taxRate > 0 ? item.taxRate : null,
            taxPriceMode: item.taxPriceMode,
          ),
      ],
      companyTaxEnabled: taxEnabled,
      companyPricesIncludeTax: pricesIncludeTax,
      companyDefaultTaxRate: defaultRate,
      globalDiscountAmount: _effectiveGeneralDiscountAmount,
    );
    return _QuoteTaxSummary(
      taxEnabled: taxEnabled,
      taxableBase: summary.taxableBase,
      taxAmount: summary.taxAmount,
      exemptAmount: summary.exemptAmount,
      total: summary.total,
      defaultRate: defaultRate,
    );
  }

  bool get _quoteTaxEnabled => _quoteTaxSummary.taxEnabled;

  double get _subtotal {
    final summary = _quoteTaxSummary;
    if (!summary.taxEnabled) {
      return _subtotalAfterLineDiscount;
    }
    return _subtotalAfterLineDiscount;
  }

  double get _subtotalBeforeDiscount => _items.fold(
    0,
    (sum, item) => sum + (item.effectiveOriginalUnitPrice * item.qty),
  );
  double get _lineDiscountAmount =>
      _items.fold(0, (sum, item) => sum + item.discountAmount);
  double get _subtotalAfterLineDiscount =>
      _roundCurrency(_items.fold(0, (sum, item) => sum + item.total));
  double get _grossTotalBeforeGeneralDiscount =>
      _roundCurrency(_subtotalAfterLineDiscount + _quoteTaxSummary.taxAmount);
  double get _effectiveGeneralDiscountAmount {
    final maxDiscount = _subtotalAfterLineDiscount;
    if (_generalDiscountAmount <= 0) return 0;
    return _generalDiscountAmount > maxDiscount
        ? maxDiscount
        : _generalDiscountAmount;
  }

  double get _discountAmount =>
      _lineDiscountAmount + _effectiveGeneralDiscountAmount;
  double get _taxAmount => _quoteTaxSummary.taxAmount;
  bool get _shouldShowItbis => shouldShowBillingItbis(
    taxEnabled: _quoteTaxEnabled,
    taxAmount: _taxAmount,
  );
  double get _totalCost =>
      _items.fold(0, (sum, item) => sum + item.subtotalCost);
  double get _total => _quoteTaxSummary.total;
  double get _utilityAmount =>
      _subtotal - _totalCost - _effectiveGeneralDiscountAmount;

  String _money(double value) => formatRdCurrencyAccounting(value);

  double _roundCurrency(double value) => double.parse(value.toStringAsFixed(2));

  double _roundUnitPrice(double value) =>
      double.parse(value.toStringAsFixed(6));

  List<SaleDraftItem> _buildCheckoutSaleItems() {
    return [
      for (final item in _items)
        SaleDraftItem(
          productId: item.isExternal ? null : item.productId,
          name: item.nombre,
          imageUrl: item.imageUrl,
          isExternal: item.isExternal,
          qty: item.qty,
          priceSoldUnit: _roundUnitPrice(item.unitPrice),
          costUnitSnapshot: item.tracedCostUnit ?? 0,
          taxTreatment: item.taxTreatment,
          taxRate: item.taxRate > 0 ? item.taxRate : null,
          taxPriceMode: item.taxPriceMode,
        ),
    ];
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

  _DesktopTicketDraft _snapshotCurrentDesktopDraft({
    required String id,
    required String title,
    _DesktopTicketDraft? base,
    bool? includeItbis,
  }) {
    return _DesktopTicketDraft(
      id: id,
      title: title,
      createdAt: base?.createdAt ?? DateTime.now(),
      companyId:
          base?.companyId ??
          (_sessionCompanyId.isEmpty ? null : _sessionCompanyId),
      createdByUserId: base?.createdByUserId ?? _sessionUserId,
      createdByUserName: base?.createdByUserName ?? _sessionUserName,
      items: _items.map((item) => item.copyWith()).toList(),
      selectedClientId: _selectedClientId,
      selectedClientName: _selectedClientName,
      selectedClientPhone: _selectedClientPhone,
      note: _note,
      includeItbis: includeItbis ?? _quoteTaxEnabled,
      fiscalVoucherType: '',
      fiscalVoucherNumber: '',
      fiscalVoucherDueDate: null,
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

  void _writeActiveDesktopDraft({bool readTaxProvider = true}) {
    final activeId = _activeDesktopTicketId;
    if (activeId == null || _desktopTickets.isEmpty) return;
    final index = _desktopTickets.indexWhere((ticket) => ticket.id == activeId);
    if (index < 0) return;
    final current = _desktopTickets[index];
    _desktopTickets[index] = _snapshotCurrentDesktopDraft(
      id: current.id,
      title: current.title,
      base: current,
      includeItbis: readTaxProvider ? null : current.includeItbis,
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
        _fiscalCustomerTaxId.trim().isNotEmpty ||
        _fiscalCustomerName.trim().isNotEmpty ||
        _generalDiscountAmount != 0 ||
        (_editingId ?? '').trim().isNotEmpty ||
        _selectedCategories.isNotEmpty;
  }

  bool get _hasFiscalVoucherReady {
    return _fiscalVoucherValidationMessage == null;
  }

  String? get _fiscalVoucherValidationMessage => null;

  Future<bool> _ensurePosActionPermission(
    AppPermission permission,
    String reason,
  ) {
    return ensureAdminAuthorization(
      context,
      ref,
      permission: permission,
      reason: reason,
    );
  }

  Future<bool> _ensureFiscalInvoicePermission() {
    return _ensurePosActionPermission(
      AppPermission.createFiscalInvoices,
      'Completar datos fiscales de la cotización',
    );
  }

  Future<bool> _ensureDiscountPermission() async {
    final user = ref.read(authStateProvider).user;
    if (user == null) return false;
    if (user.appRole == AppRole.admin ||
        hasUserPermission(user, AppPermission.applyDiscounts)) {
      return true;
    }
    final allowed = await ensureAdminAuthorization(
      context,
      ref,
      permission: AppPermission.applyDiscounts,
      forceAdminAuthorization: true,
      reason: 'Aplicar descuento a la venta',
    );
    if (allowed && mounted) {
      ref
          .read(adminAuthorizationProvider.notifier)
          .consumeActionAuthorization();
    }
    return allowed;
  }

  List<String> _fiscalSaleNoteLines() {
    if (!_quoteTaxEnabled) return const [];
    return [
      'Cotización con impuestos automáticos',
      if (_fiscalCustomerTaxId.trim().isNotEmpty)
        'RNC/Cédula: ${_fiscalCustomerTaxId.trim()}',
      if (_fiscalCustomerName.trim().isNotEmpty)
        'Razón social: ${_fiscalCustomerName.trim()}',
      if (_shouldShowItbis)
        'ITBIS ${(_quoteTaxSummary.defaultRate * 100).toStringAsFixed(0)}%: ${_money(_taxAmount)}',
    ];
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
      final user = ref.read(authStateProvider).user;
      final ticket = _DesktopTicketDraft.empty(
        id: _newId(),
        title: _nextDesktopTicketTitle(),
        companyId: user?.companyId,
        createdByUserId: user?.id,
        createdByUserName: user?.nombreCompleto,
      );
      _desktopTickets = [ticket, ..._desktopTickets];
      _activeDesktopTicketId = ticket.id;
      _showMobileTicketDropdown = false;
      _replaceEditorStateFromDraft(ticket);
      _writeActiveDesktopDraft();
    });
    _schedulePersistEditorDraft(immediate: true);
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
      _syncEditorItemsFiscalWithLoadedProducts();
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
      barrierColor: Colors.black.withValues(alpha: 0.40),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) {
        Widget actionTile({
          required IconData icon,
          required String title,
          required String subtitle,
          required _MobileQuickAction value,
        }) {
          return Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.of(context).pop(value),
              child: Container(
                height: 84,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE8EEF5)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.025),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF4FF),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        icon,
                        color: const Color(0xFF2563EB),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFF2563EB),
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final panelWidth = (MediaQuery.sizeOf(context).width * 0.72).clamp(
          268.0,
          330.0,
        );
        final hasNote = _note.trim().isNotEmpty;

        return Align(
          alignment: Alignment.centerRight,
          child: SafeArea(
            child: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: panelWidth,
                height: double.infinity,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(28),
                      bottomLeft: Radius.circular(28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x260B2A3A),
                        blurRadius: 28,
                        offset: Offset(-10, 0),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(28),
                      bottomLeft: Radius.circular(28),
                    ),
                    child: Stack(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: 58,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(18, 0, 8, 0),
                                child: Row(
                                  children: [
                                    const Expanded(
                                      child: Center(
                                        child: Text(
                                          'Acciones',
                                          style: TextStyle(
                                            color: Color(0xFF0F172A),
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Cerrar',
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        color: Color(0xFF334155),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              child: ListView(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  84,
                                ),
                                children: [
                                  actionTile(
                                    icon: Icons.add_circle_outline_rounded,
                                    title: 'Nuevo ticket',
                                    subtitle: 'Crear otra venta',
                                    value: _MobileQuickAction.newTicket,
                                  ),
                                  const SizedBox(height: 11),
                                  actionTile(
                                    icon: Icons.storefront_outlined,
                                    title: 'Venta rápida',
                                    subtitle: 'Cobro rápido',
                                    value: _MobileQuickAction.externalItem,
                                  ),
                                  const SizedBox(height: 11),
                                  actionTile(
                                    icon: Icons.picture_as_pdf_outlined,
                                    title: 'Ver PDF',
                                    subtitle: 'Abrir documento actual',
                                    value: _MobileQuickAction.pdf,
                                  ),
                                  const SizedBox(height: 11),
                                  actionTile(
                                    icon: hasNote
                                        ? Icons.sticky_note_2_outlined
                                        : Icons.note_alt_outlined,
                                    title: 'Agregar nota',
                                    subtitle: hasNote
                                        ? 'Nota agregada'
                                        : 'Añadir nota a la factura',
                                    value: _MobileQuickAction.note,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        Positioned(
                          right: 16,
                          bottom: 16,
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

  Future<void> _openMobileFiscalInvoicePanel({bool authorized = false}) async {
    if (!_quoteTaxEnabled) return;
    if (!authorized) {
      final allowed = await _ensureFiscalInvoicePermission();
      if (!allowed || !mounted) return;
    }
    if (_fiscalCustomerName.trim().isEmpty) {
      _commitEditorChange(() {
        final clientName = _selectedClientName.trim();
        _fiscalCustomerName = clientName == 'Sin cliente' ? '' : clientName;
      });
    }
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Datos fiscales',
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
                        customerTaxId: _fiscalCustomerTaxId,
                        customerName: _fiscalCustomerName,
                        onCustomerTaxIdChanged: (value) => _commitEditorChange(
                          () => _fiscalCustomerTaxId = value,
                        ),
                        onCustomerNameChanged: (value) => _commitEditorChange(
                          () => _fiscalCustomerName = value,
                        ),
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
        await _openQuotationHistory();
        return;
      case _MobileQuickAction.inventory:
        await _openInventoryFloatingActions();
        return;
      case _MobileQuickAction.clear:
        if (!_hasEditorContent) return;
        await _confirmAndClearSale();
        return;
    }
  }

  bool _isPermissionDenied(Object error) {
    if (error is ApiException) {
      return error.type == ApiErrorType.forbidden ||
          error.code == 403 ||
          error.message.toLowerCase().contains('no tienes permiso');
    }
    return error.toString().toLowerCase().contains('no tienes permiso');
  }

  Future<bool> _ensureQuotePermission(String reason, {String? route}) {
    return ensureAdminAuthorization(
      context,
      ref,
      permission: AppPermission.viewQuotes,
      reason: reason,
      routeLocation: route,
    );
  }

  Future<bool> _requestQuoteAdminOverride(String reason) async {
    final shouldAuthorize = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('No tienes permiso'),
        content: const Text(
          'No tienes permiso para esta acción. Puedes pedir autorización administrativa para continuar.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.admin_panel_settings_outlined),
            label: const Text('Autorizar'),
          ),
        ],
      ),
    );
    if (shouldAuthorize != true || !mounted) return false;
    return ensureAdminAuthorization(
      context,
      ref,
      permission: AppPermission.viewQuotes,
      reason: reason,
      forceAdminAuthorization: true,
    );
  }

  Future<T> _runQuoteApiAction<T>(
    String reason,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } catch (error) {
      if (!_isPermissionDenied(error) || !mounted) rethrow;
      final authorized = await _requestQuoteAdminOverride(reason);
      if (!authorized || !mounted) {
        throw ApiException('No tienes permiso para esta acción.', 403);
      }
      return action();
    }
  }

  Future<void> _openQuotationHistory() async {
    final allowed = await _ensureQuotePermission(
      'Entrar a lista de cotizaciones',
      route: Routes.cotizacionesHistorial,
    );
    if (!allowed || !mounted) return;
    context.go(Routes.cotizacionesHistorial);
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
    final allowed = await _ensureQuotePermission('Guardar cotización');
    if (!allowed || !mounted) return;

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
            ? await _runQuoteApiAction(
                'Guardar cotización',
                () => repository.update(editingId, draft),
              )
            : await _runQuoteApiAction(
                'Guardar cotización',
                () => repository.create(draft.copyWith(id: '')),
              );

        if (!mounted) return;
        Navigator.of(context).pop(savedQuotation);
        return;
      }

      final wasQueued = editingId.isNotEmpty && _isUuid(editingId)
          ? await _runQuoteApiAction(
              'Guardar cotización',
              () => repository.updateOrQueue(editingId, draft),
            )
          : await _runQuoteApiAction(
              'Guardar cotización',
              () => repository.createOrQueue(draft.copyWith(id: '')),
            );

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
        'taxEnabled': _quoteTaxEnabled,
        'subtotal': _subtotal,
        'taxAmount': _taxAmount,
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
    final allowed = await _ensureDiscountPermission();
    if (!allowed || !mounted) return;
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
    final addingNewLine = index < 0;
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
        _items[index] = syncBillingItemFiscalFromProduct(
          current.copyWith(qty: current.qty + 1),
          product,
        );
      } else {
        _items.add(buildBillingItemFromProduct(product));
      }
    });
    final isMobile =
        MediaQuery.maybeSizeOf(context)?.width != null &&
        MediaQuery.maybeSizeOf(context)!.width < _desktopBreakpoint;
    if (isMobile && addingNewLine && _items.length <= 2) {
      setState(() => _mobileCartExtentInitialized = false);
    }
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
                  color: Color(0xFF1957E6),
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
                            backgroundColor: const Color(0xFF1957E6),
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
    if (result.discountValue > 0) {
      final allowed = await _ensureDiscountPermission();
      if (!allowed || !mounted) return;
    }
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
        barrierColor: Colors.black.withValues(alpha: 0.38),
        builder: (dialogContext) {
          final size = MediaQuery.sizeOf(dialogContext);
          final insets = MediaQuery.viewInsetsOf(dialogContext);
          final hasNote = _note.trim().isNotEmpty;
          final isMobile = size.width < 640;
          final horizontalInset = isMobile ? 12.0 : 24.0;
          final verticalInset = isMobile ? 12.0 : 24.0;
          final availableHeight =
              size.height - insets.bottom - (verticalInset * 2);
          final dialogMaxHeight = availableHeight >= 220.0
              ? availableHeight
              : (size.height - insets.bottom - 8.0).clamp(
                  180.0,
                  double.infinity,
                );

          return AnimatedPadding(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: insets.bottom),
            child: Dialog(
              insetPadding: EdgeInsets.symmetric(
                horizontal: horizontalInset,
                vertical: verticalInset,
              ),
              backgroundColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  maxHeight: dialogMaxHeight.toDouble(),
                ),
                child: Material(
                  color: Colors.white,
                  elevation: 24,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(18),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Agregar nota',
                                style: TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Cerrar',
                              onPressed: () => Navigator.pop(dialogContext),
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Color(0xFF334155),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Nota para esta factura',
                          style: TextStyle(
                            color: Color(0xFF334155),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: controller,
                          autofocus: true,
                          minLines: 3,
                          maxLines: 5,
                          maxLength: 500,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          textCapitalization: TextCapitalization.sentences,
                          autocorrect: true,
                          enableSuggestions: true,
                          decoration: InputDecoration(
                            hintText: 'Escribe una nota para esta factura...',
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFD7E2EE),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFFD7E2EE),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF1957E6),
                                width: 1.35,
                              ),
                            ),
                            hintStyle: const TextStyle(
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            if (hasNote)
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, ''),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFFDC2626),
                                ),
                                child: const Text('Eliminar nota'),
                              ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => Navigator.pop(dialogContext),
                              child: const Text('Cancelar'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: () => Navigator.pop(
                                dialogContext,
                                _autocorrectNoteText(controller.text),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF1957E6),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Guardar nota'),
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
        },
      );
    } finally {
      FocusManager.instance.primaryFocus?.unfocus();
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
    final repo = ref.read(ventasRepositoryProvider);
    final searchCtrl = TextEditingController();

    List<ClienteModel> clients = const [];
    Timer? searchDebounce;
    int requestId = 0;
    bool loading = true;
    bool dialogOpen = true;
    bool initialLoadQueued = false;
    ClienteModel? detailClient;
    String? error;

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

              final filteredClients = clients;

              final selectedDetailClient = detailClient;
              final content = selectedDetailClient != null
                  ? _QuoteClientInlineDetail(
                      client: selectedDetailClient,
                      onBack: () => setStateDialog(() {
                        detailClient = null;
                      }),
                      onUse: () {
                        _commitEditorChange(() {
                          _selectedClientId = selectedDetailClient.id;
                          _selectedClientName = selectedDetailClient.nombre;
                          _selectedClientPhone = selectedDetailClient.telefono;
                        });
                        Navigator.pop(context);
                      },
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        SizedBox(
                          height: isDesktop ? 48 : 46,
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: searchCtrl,
                                  textInputAction: TextInputAction.search,
                                  decoration: InputDecoration(
                                    hintText: 'Buscar cliente',
                                    prefixIcon: const Icon(
                                      Icons.search_rounded,
                                      size: 19,
                                    ),
                                    prefixIconConstraints: const BoxConstraints(
                                      minWidth: 40,
                                      minHeight: 40,
                                    ),
                                    suffixIcon:
                                        searchCtrl.text.trim().isNotEmpty
                                        ? IconButton(
                                            onPressed: () {
                                              searchCtrl.clear();
                                              detailClient = null;
                                              scheduleLoadClients();
                                              setStateDialog(() {});
                                            },
                                            icon: const Icon(Icons.close),
                                          )
                                        : null,
                                    isDense: true,
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFD7E2EE),
                                      ),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFD7E2EE),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF2563EB),
                                        width: 1.35,
                                      ),
                                    ),
                                  ),
                                  onChanged: (_) {
                                    detailClient = null;
                                    setStateDialog(() {});
                                    scheduleLoadClients();
                                  },
                                  onSubmitted: (_) {
                                    unawaited(loadClients());
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
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
                                icon: const Icon(
                                  Icons.person_add_alt_1_outlined,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        if ((_selectedClientId ?? '').trim().isNotEmpty) ...[
                          Material(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                _commitEditorChange(() {
                                  _selectedClientId = null;
                                  _selectedClientName = 'Sin cliente';
                                  _selectedClientPhone = null;
                                });
                                Navigator.pop(context);
                              },
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.person_remove_alt_1_outlined,
                                      color: Color(0xFFDC2626),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Quitar cliente de esta factura',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: const Color(0xFFB91C1C),
                                              fontWeight: FontWeight.w800,
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
                                      final createdAt = client.createdAt
                                          ?.toLocal();
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
                                            _selectedClientPhone =
                                                client.telefono;
                                          });
                                          Navigator.pop(context);
                                        },
                                        trailing: TextButton.icon(
                                          onPressed: () => setStateDialog(() {
                                            detailClient = client;
                                          }),
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
                                      final createdAt = client.createdAt
                                          ?.toLocal();
                                      final createdLabel = createdAt == null
                                          ? null
                                          : DateFormat(
                                              'dd/MM/yyyy',
                                            ).format(createdAt);
                                      return ListTile(
                                        dense: true,
                                        visualDensity: VisualDensity.compact,
                                        minVerticalPadding: 5,
                                        contentPadding: const EdgeInsets.only(
                                          left: 0,
                                          right: 2,
                                        ),
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
                                            _selectedClientPhone =
                                                client.telefono;
                                          });
                                          Navigator.pop(context);
                                        },
                                        trailing: IconButton(
                                          tooltip: 'Ver cliente',
                                          onPressed: () => setStateDialog(() {
                                            detailClient = client;
                                          }),
                                          iconSize: 20,
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
      includeItbis: _shouldShowItbis,
      itbisRate: _quoteTaxSummary.defaultRate,
      fiscalTaxEnabled: _quoteTaxEnabled,
      fiscalPriceMode: _quoteTaxEnabled
          ? (_currentTaxConfig?.settings.pricesIncludeTax == true
                ? 'TAX_INCLUDED'
                : 'TAX_ADDED')
          : 'NO_TAX',
      taxableBase: _quoteTaxSummary.taxableBase,
      taxAmount: _quoteTaxSummary.taxAmount,
      exemptAmount: _quoteTaxSummary.exemptAmount,
      fiscalDiscountAmount: _effectiveGeneralDiscountAmount,
      totalSnapshot: _total,
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

    await _runQuoteApiAction(
      'Enviar PDF de cotización',
      () => ref
          .read(cotizacionesRepositoryProvider)
          .sendWhatsAppQuotation(
            quotationId: cotizacion.id,
            destinationType: 'admin',
            pdfBytes: bytes,
            fileName: fileName,
            messageText: _buildAdminApprovalMessage(cotizacion),
          ),
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

    final pdfUrl = await _runQuoteApiAction(
      'Crear enlace PDF de cotización',
      () => ref
          .read(cotizacionesRepositoryProvider)
          .createPdfShareLink(
            quotationId: cotizacion.id,
            pdfBytes: pdfBytes,
            fileName: buildCotizacionPdfFileName(cotizacion),
          ),
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
        ? await _runQuoteApiAction(
            'Preparar PDF de cotización',
            () => repository.update(_editingId!, draft),
          )
        : await _runQuoteApiAction(
            'Preparar PDF de cotización',
            () => repository.create(draft),
          );

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
    final allowed = await _ensureQuotePermission('Ver PDF de cotización');
    if (!allowed || !mounted) return;

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
                width: compact
                    ? media.width - 12
                    : (media.width * 0.58).clamp(760.0, 1120.0),
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
                        color: const Color(0xFFE8EEF5),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 960),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.10),
                                    blurRadius: 18,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: SfPdfViewer.memory(
                                bytes,
                                canShowScrollHead: true,
                                canShowPaginationDialog: true,
                              ),
                            ),
                          ),
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
    final allowed = await _ensurePosActionPermission(
      AppPermission.editProducts,
      'Crear nuevo producto',
    );
    if (!allowed || !mounted) return;
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
    final allowed = await _ensurePosActionPermission(
      AppPermission.addStock,
      'Agregar o ajustar stock',
    );
    if (!allowed || !mounted) return;
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
            onReprintTicket: _reprintRecentSaleTicket,
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

  Future<void> _reprintRecentSaleTicket(SaleModel sale) async {
    final result = await ref
        .read(unifiedTicketPrinterProvider)
        .reprintSale(sale: sale, items: sale.items);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
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
            'Revisa los datos fiscales informativos antes de cobrar con ITBIS.',
        icon: Icons.fact_check_outlined,
        accent: const Color(0xFFF59E0B),
      );
      return false;
    }

    return true;
  }

  String _checkoutPaymentLabel(_CheckoutPaymentMethod method) => method.label;

  Future<void> _openCheckoutDialog() async {
    if (_finalizingCheckout) return;
    if (!_validateCheckoutReady()) return;

    final cashState = await _cashStateWithAuthorizationFallback();
    if (cashState == null) return;
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
        hasCreditCustomer:
            (_selectedClientId ?? '').trim().isNotEmpty &&
            _selectedClientName.trim() != 'Sin cliente',
        onConfirm: (method) => Navigator.of(context).pop(method),
      ),
    );
    if (result == null) return;

    if (!mounted) return;
    setState(() => _finalizingCheckout = true);
    try {
      await _finalizeCotizacion(checkout: result);
    } finally {
      if (mounted) setState(() => _finalizingCheckout = false);
    }
  }

  Future<void> _finalizeCotizacion({_CheckoutResult? checkout}) async {
    if (!_validateCheckoutReady()) return;

    final popOnSave =
        (_safeRouteUri()?.queryParameters['popOnSave'] ?? '').trim() == '1';

    if (checkout != null) {
      final cashState = await _cashStateWithAuthorizationFallback();
      if (cashState == null) return;
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

      final createdSale = await _createSaleWithAuthorizationFallback(
        checkout: checkout,
        saleNote: saleNote,
        saleItems: saleItems,
      );
      if (createdSale == null) {
        if (!mounted) return;
        _showSalesNotice(
          title: 'Cobro no autorizado',
          message:
              'La venta no se guardó porque falta autorización para cobrar.',
          icon: Icons.admin_panel_settings_outlined,
          accent: const Color(0xFFF59E0B),
        );
        return;
      }

      if (checkout != null) {
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

  Future<CashGateState?> _cashStateWithAuthorizationFallback() async {
    try {
      return await ref.read(cashRepositoryProvider).state();
    } catch (error) {
      if (!_isPermissionDenied(error) || !mounted) rethrow;
      final allowed = await ensureAdminAuthorization(
        context,
        ref,
        permission: AppPermission.viewSales,
        forceAdminAuthorization: true,
        reason: 'Autorizar caja para facturar',
      );
      if (!mounted || !allowed) return null;
      try {
        return await ref.read(cashRepositoryProvider).state();
      } catch (retryError) {
        if (!_isPermissionDenied(retryError) || !mounted) rethrow;
        _showSalesNotice(
          title: 'Autorización requerida',
          message:
              'No tienes permiso para esta acción. Verifica los permisos del usuario o autoriza nuevamente.',
          icon: Icons.admin_panel_settings_outlined,
          accent: const Color(0xFFF59E0B),
        );
        return null;
      }
    }
  }

  Future<SaleModel?> _createSaleWithAuthorizationFallback({
    required _CheckoutResult? checkout,
    required String saleNote,
    required List<SaleDraftItem> saleItems,
  }) async {
    try {
      return await _createSaleForCheckout(
        checkout: checkout,
        saleNote: saleNote,
        saleItems: saleItems,
      );
    } catch (error) {
      if (!_isPermissionDenied(error) || !mounted) rethrow;
      final allowed = await ensureAdminAuthorization(
        context,
        ref,
        permission: AppPermission.viewSales,
        forceAdminAuthorization: true,
        reason: 'Autorizar cobro de factura',
      );
      if (!mounted || !allowed) return null;
      return _createSaleForCheckout(
        checkout: checkout,
        saleNote: saleNote,
        saleItems: saleItems,
      );
    }
  }

  Future<SaleModel?> _createSaleForCheckout({
    required _CheckoutResult? checkout,
    required String saleNote,
    required List<SaleDraftItem> saleItems,
  }) {
    return ref
        .read(ventasRepositoryProvider)
        .createSale(
          sourceQuotationId: (_editingId ?? '').trim().isEmpty
              ? null
              : _editingId,
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
          globalDiscountAmount: _effectiveGeneralDiscountAmount,
          items: saleItems,
        );
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

  PreferredSizeWidget _buildMobileAppBar() {
    return AppBar(
      toolbarHeight: 44,
      elevation: 0,
      centerTitle: true,
      leadingWidth: 50,
      titleSpacing: 0,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      foregroundColor: const Color(0xFF0F172A),
      shadowColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      shape: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      leading: Builder(
        builder: (context) => Center(
          child: _AnimatedDrawerButton(
            onPressed: () => Scaffold.maybeOf(context)?.openDrawer(),
          ),
        ),
      ),
      title: const Text(
        'Facturación',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 19.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0,
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Escanear producto',
          onPressed: _openBarcodeScanner,
          constraints: const BoxConstraints.tightFor(width: 38, height: 40),
          icon: const Icon(Icons.qr_code_scanner_rounded, size: 21),
        ),
        IconButton(
          tooltip: 'Acciones',
          onPressed: _openMobileActionsDrawer,
          constraints: const BoxConstraints.tightFor(width: 38, height: 40),
          icon: const Icon(Icons.more_vert_rounded, size: 22),
        ),
        const SizedBox(width: 2),
      ],
    );
  }

  Widget _buildProductStrip() {
    return _visibleProducts.isEmpty
        ? Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _searchCtrl.text.trim().isNotEmpty || _hasCategoryFilter
                    ? 'No hay productos con este filtro'
                    : 'El catálogo se mostrará aquí cuando haya productos disponibles',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
        : GridView.builder(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.98,
            ),
            itemCount: _visibleProducts.length,
            itemBuilder: (context, index) {
              final product = _visibleProducts[index];
              return _ProductThumbCard(
                product: product,
                onTap: () => _addProduct(product),
                onImageTap: () => _openProductImagePreview(product),
                money: _money,
              );
            },
          );
  }

  void _openProductImagePreview(ProductModel product) {
    final user = ref.read(authStateProvider).user;
    final isMobile = MediaQuery.sizeOf(context).width < _desktopBreakpoint;
    final showAdminCost =
        isMobile && user?.appRole == AppRole.admin && product.costAvailable;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _ProductImagePreviewScreen(
          product: product,
          money: _money,
          showAdminCost: showAdminCost,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      child: Row(
        children: [
          Expanded(
            child: _MobileSelectorButton(
              icon: Icons.receipt_long_outlined,
              overline: 'Ticket',
              label: primaryLabel,
              showDot: canExpandTickets,
              onTap: canExpandTickets
                  ? () => setState(
                      () => _showMobileTicketDropdown =
                          !_showMobileTicketDropdown,
                    )
                  : _createNewDesktopTicket,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _MobileSelectorButton(
              icon: Icons.person_outline_rounded,
              overline: 'Cliente actual',
              label: hasClient ? clientLabel : 'Cliente general',
              onTap: _openClientDialog,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.zero,
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        clipBehavior: Clip.antiAlias,
        child: TextField(
          controller: _searchCtrl,
          focusNode: _mobileSearchFocusNode,
          textInputAction: TextInputAction.search,
          canRequestFocus: true,
          onTapOutside: (_) => _mobileSearchFocusNode.unfocus(),
          onChanged: (_) => _commitEditorChange(() {}),
          onSubmitted: (_) => _submitSearchAndAddFirstVisibleProduct(),
          style: const TextStyle(
            color: Color(0xFF1E293B),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            hintText: 'Buscar productos...',
            hintStyle: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: Color(0xFF334155),
              size: 20,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 38,
              minHeight: 38,
            ),
            suffixIcon: Badge(
              isLabelVisible: _hasCategoryFilter,
              smallSize: 8,
              child: IconButton(
                tooltip: _hasCategoryFilter
                    ? 'Categorias: $_selectedCategoryLabel'
                    : 'Filtrar productos',
                onPressed: _pickCategory,
                icon: const Icon(Icons.tune_rounded, color: Color(0xFF2563EB)),
              ),
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 38,
              minHeight: 38,
            ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 8,
            ),
          ),
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
      top: 62,
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

  Future<void> _animateMobileCartTo(double extent) async {
    if (mounted) setState(() => _mobileCartExtent = extent);
  }

  Widget _buildMobileDraggableCartSheet(
    UserModel? currentUser, {
    required double collapsedSize,
    required double mediumSize,
    required double expandedSize,
    required double availableHeight,
    required bool keyboardVisible,
  }) {
    final isAdmin = currentUser?.appRole == AppRole.admin;
    final itemCount = _items.fold<double>(0, (sum, item) => sum + item.qty);
    final itemCountLabel = itemCount == 1
        ? '1 artículo'
        : '${itemCount % 1 == 0 ? itemCount.toStringAsFixed(0) : itemCount.toStringAsFixed(2)} artículos';
    final hasItems = _items.isNotEmpty;
    final currentExtent = _mobileCartExtent
        .clamp(collapsedSize, expandedSize)
        .toDouble();
    final panelHeight = availableHeight * currentExtent;
    final compactForKeyboard = keyboardVisible && panelHeight < 210;

    void dragCartBy(double delta) {
      if (!hasItems) return;
      final nextExtent = (_mobileCartExtent - delta / availableHeight)
          .clamp(collapsedSize, expandedSize)
          .toDouble();
      if ((nextExtent - _mobileCartExtent).abs() < 0.001) return;
      setState(() => _mobileCartExtent = nextExtent);
    }

    Widget cartDragHandle(double nextExtent) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: hasItems
            ? (details) => dragCartBy(details.primaryDelta ?? 0)
            : null,
        onVerticalDragEnd: hasItems
            ? (_) {
                setState(() {
                  _mobileCartExtent = _mobileCartExtent
                      .clamp(collapsedSize, expandedSize)
                      .toDouble();
                });
              }
            : null,
        onTap: hasItems
            ? () => unawaited(_animateMobileCartTo(nextExtent))
            : null,
        child: SizedBox(
          width: 96,
          height: compactForKeyboard ? 18 : 20,
          child: Center(
            child: Container(
              width: compactForKeyboard ? 38 : 48,
              height: 4,
              decoration: BoxDecoration(
                color: hasItems
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
        ),
      );
    }

    Widget cartHeader() {
      final isCollapsed = _mobileCartExtent <= collapsedSize + 0.04;
      final isExpanded = _mobileCartExtent >= expandedSize - 0.04;
      final nextExtent = isExpanded
          ? mediumSize
          : isCollapsed
          ? mediumSize
          : expandedSize;

      return Padding(
        padding: EdgeInsets.fromLTRB(14, compactForKeyboard ? 2 : 3, 12, 4),
        child: Column(
          children: [
            Center(child: cartDragHandle(nextExtent)),
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.shopping_cart_outlined,
                    size: 18,
                    color: Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    itemCountLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isCollapsed || compactForKeyboard)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        _money(_total),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_down_rounded
                      : Icons.keyboard_arrow_up_rounded,
                  color: hasItems
                      ? const Color(0xFF0F172A)
                      : const Color(0xFF94A3B8),
                ),
              ],
            ),
          ],
        ),
      );
    }

    Widget cartProductsList() {
      if (!hasItems) {
        return const Center(
          child: Text(
            'Toca un producto para agregarlo',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      }

      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 2),
        itemCount: _items.length,
        separatorBuilder: (context, index) =>
            const Divider(height: 6, thickness: 1, color: Color(0xFFE8EEF5)),
        itemBuilder: (context, index) => _buildTicketLine(
          item: _items[index],
          index: index,
          isAdmin: isAdmin,
          onAfterCommit: () {
            if (_items.length <= 2) {
              setState(() => _mobileCartExtentInitialized = false);
            }
          },
        ),
      );
    }

    Widget checkoutFooter() {
      if (compactForKeyboard) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 38,
                  child: OutlinedButton(
                    onPressed: hasItems ? _saveCurrentAsQuotation : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF2563EB),
                      side: const BorderSide(color: Color(0xFF2563EB)),
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('Cotizar'),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                flex: 7,
                child: FilledButton.icon(
                  onPressed: hasItems ? _openCheckoutDialog : null,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Cobrar'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(38),
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFF93C5FD),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 1),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _applyGeneralDiscount,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isAdmin) ...[
                          const Text(
                            'Utilidad (i)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 10,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          Text(
                            _money(_utilityAmount),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF2563EB),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ] else if (_effectiveGeneralDiscountAmount > 0)
                          Text(
                            'Rebaja ${_money(_effectiveGeneralDiscountAmount)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF2563EB),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        if (_discountAmount > 0)
                          Text(
                            'Descuento ${_money(_discountAmount)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_shouldShowItbis)
                  GestureDetector(
                    onTap: () => unawaited(
                      _openMobileFiscalInvoicePanel(authorized: true),
                    ),
                    child: Text(
                      'ITBIS ${_money(_taxAmount)}',
                      style: const TextStyle(
                        color: Color(0xFF2563EB),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _applyGeneralDiscount,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Total',
                        style: TextStyle(
                          color: Color(0xFF334155),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Text(
                          _money(_total),
                          key: ValueKey(_money(_total)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton(
                      onPressed: hasItems ? _saveCurrentAsQuotation : null,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF2563EB),
                        side: const BorderSide(color: Color(0xFF2563EB)),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Cotizar'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 7,
                  child: FilledButton.icon(
                    onPressed: hasItems ? _openCheckoutDialog : null,
                    icon: const Icon(Icons.check_rounded, size: 20),
                    label: const Text('Cobrar'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF93C5FD),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
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

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: panelHeight,
      child: Material(
        color: Colors.white,
        elevation: 18,
        shadowColor: Colors.black.withValues(alpha: 0.22),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              cartHeader(),
              Expanded(child: cartProductsList()),
              checkoutFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileBody(QuotationAiState aiState, UserModel? currentUser) {
    final showAiBanner = _shouldShowAiBanner(aiState);
    return LayoutBuilder(
      builder: (context, constraints) {
        final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;
        final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
        final lineCount = _items.length;
        final defaultVisibleRows = lineCount <= 2 ? lineCount : 2;
        const cartLineHeight = 58.0;
        final collapsedBaseHeight = keyboardVisible ? 112.0 : 168.0;
        final collapsedMaxRatio = keyboardVisible ? 0.24 : 0.28;
        final maxCollapsedCartHeight =
            constraints.maxHeight * collapsedMaxRatio;
        final minCollapsedCartHeight =
            maxCollapsedCartHeight < collapsedBaseHeight
            ? maxCollapsedCartHeight
            : collapsedBaseHeight;
        final collapsedCartHeight = (collapsedBaseHeight + bottomSafe)
            .clamp(minCollapsedCartHeight, maxCollapsedCartHeight)
            .toDouble();
        final collapsedSize = (collapsedCartHeight / constraints.maxHeight)
            .clamp(0.20, 0.36)
            .toDouble();
        final mediumCartHeight =
            collapsedCartHeight + (defaultVisibleRows * cartLineHeight);
        final expandedCartHeight =
            collapsedCartHeight + (lineCount * cartLineHeight);
        final mediumSize = (mediumCartHeight / constraints.maxHeight)
            .clamp(collapsedSize, 0.58)
            .toDouble();
        final expandedSize = (expandedCartHeight / constraints.maxHeight)
            .clamp(collapsedSize, 0.82)
            .toDouble();
        if (!_mobileCartExtentInitialized) {
          _mobileCartExtent = lineCount > 0 ? mediumSize : collapsedSize;
          _mobileCartExtentInitialized = true;
        } else if (_mobileCartExtent < collapsedSize ||
            _mobileCartExtent > expandedSize) {
          _mobileCartExtent = _mobileCartExtent
              .clamp(collapsedSize, expandedSize)
              .toDouble();
        }

        return Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFFF8FBFF),
                    Color(0xFFF4F8FF),
                    Color(0xFFEEF5FF),
                  ],
                ),
              ),
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildMobileTicketInfoBar(),
                          _buildMobileSearchBar(),
                          if (showAiBanner)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                              child: AiWarningBanner(
                                warnings: aiState.visibleWarnings,
                                analyzing:
                                    aiState.analyzing || aiState.loadingRules,
                                onOpenRule: (warning) => _openAiRelatedRule(
                                  warning.relatedRuleId,
                                  warning.relatedRuleTitle,
                                ),
                                onAskAi: _askAiAboutWarning,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  Expanded(
                    child: AnimatedPadding(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.only(bottom: collapsedCartHeight),
                      child: _buildProductStrip(),
                    ),
                  ),
                ],
              ),
            ),
            if (_showMobileTicketDropdown && _desktopTickets.length > 1)
              _buildMobileTicketDropdownOverlay(),
            _buildMobileDraggableCartSheet(
              currentUser,
              collapsedSize: collapsedSize,
              mediumSize: mediumSize,
              expandedSize: expandedSize,
              availableHeight: constraints.maxHeight,
              keyboardVisible: keyboardVisible,
            ),
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
                            includeItbis: _shouldShowItbis,
                            subtotalBeforeDiscount: _subtotalBeforeDiscount,
                            discountAmount: _lineDiscountAmount,
                            generalDiscountAmount:
                                _effectiveGeneralDiscountAmount,
                            subtotal: _subtotal,
                            itbisAmount: _taxAmount,
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
                            onOpenFiscalData: _shouldShowItbis
                                ? () => unawaited(
                                    _openMobileFiscalInvoicePanel(
                                      authorized: true,
                                    ),
                                  )
                                : null,
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
                            isOutOfStock: (item) {
                              if (item.isExternal) return false;
                              final official = _findOfficialProduct(
                                item.productId,
                              );
                              return official != null &&
                                  (official.stock == null ||
                                      official.stock! <= 0);
                            },
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
      appBar: isDesktop ? _buildDesktopAppBar(aiState) : _buildMobileAppBar(),
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

enum _BarcodeScanStatus { ignored, added, notFound, error }

class _BarcodeScanResult {
  const _BarcodeScanResult._({
    required this.status,
    this.productName,
    this.code,
  });

  const _BarcodeScanResult.ignored()
    : this._(status: _BarcodeScanStatus.ignored);

  const _BarcodeScanResult.added(String productName)
    : this._(status: _BarcodeScanStatus.added, productName: productName);

  const _BarcodeScanResult.notFound(String code)
    : this._(status: _BarcodeScanStatus.notFound, code: code);

  const _BarcodeScanResult.error(String code)
    : this._(status: _BarcodeScanStatus.error, code: code);

  final _BarcodeScanStatus status;
  final String? productName;
  final String? code;
}

class _MobileBarcodeScannerPage extends StatefulWidget {
  const _MobileBarcodeScannerPage({required this.onBarcode});

  final Future<_BarcodeScanResult> Function(String code) onBarcode;

  @override
  State<_MobileBarcodeScannerPage> createState() =>
      _MobileBarcodeScannerPageState();
}

class _MobileBarcodeScannerPageState extends State<_MobileBarcodeScannerPage> {
  static const _duplicateWindow = Duration(milliseconds: 1100);
  static const _feedbackDuration = Duration(milliseconds: 1100);

  late final MobileScannerController _controller;
  final Map<String, DateTime> _lastScannedAtByCode = {};
  final Set<String> _processingCodes = <String>{};
  Timer? _feedbackTimer;
  bool _handlingScan = false;
  String _feedbackTitle = 'Listo para escanear';
  String _feedbackMessage = 'Coloca el código dentro del recuadro';
  Color _frameColor = const Color(0xFF2563EB);
  int _addedCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      facing: CameraFacing.back,
      detectionSpeed: DetectionSpeed.normal,
      detectionTimeoutMs: 850,
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.itf14,
        BarcodeFormat.itf2of5,
        BarcodeFormat.qrCode,
      ],
    );
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    if (_controller.value.torchState == TorchState.on) {
      unawaited(_controller.toggleTorch());
    }
    _controller.dispose();
    super.dispose();
  }

  bool _isDuplicateAccidental(String code, DateTime now) {
    final previous = _lastScannedAtByCode[code];
    if (previous == null) return false;
    return now.difference(previous) < _duplicateWindow;
  }

  void _showFeedback({
    required String title,
    required String message,
    required Color color,
  }) {
    _feedbackTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _feedbackTitle = title;
      _feedbackMessage = message;
      _frameColor = color;
    });
    _feedbackTimer = Timer(_feedbackDuration, () {
      if (!mounted) return;
      setState(() {
        _feedbackTitle = 'Listo para escanear';
        _feedbackMessage = 'Coloca el código dentro del recuadro';
        _frameColor = const Color(0xFF2563EB);
      });
    });
  }

  Future<void> _handleCapture(BarcodeCapture capture) async {
    if (_handlingScan) return;

    for (final barcode in capture.barcodes) {
      final code = (barcode.rawValue ?? '').trim();
      if (code.isEmpty) continue;

      final now = DateTime.now();
      if (_processingCodes.contains(code) ||
          _isDuplicateAccidental(code, now)) {
        return;
      }

      _lastScannedAtByCode[code] = now;
      _processingCodes.add(code);
      _handlingScan = true;
      _showFeedback(
        title: 'Leyendo código',
        message: code,
        color: const Color(0xFF2563EB),
      );

      try {
        final result = await widget.onBarcode(code);
        if (!mounted) return;

        switch (result.status) {
          case _BarcodeScanStatus.ignored:
            return;
          case _BarcodeScanStatus.added:
            _addedCount += 1;
            unawaited(SystemSound.play(SystemSoundType.click));
            _showFeedback(
              title: 'Agregado a la venta',
              message: result.productName ?? code,
              color: const Color(0xFF16A34A),
            );
            return;
          case _BarcodeScanStatus.notFound:
            _showFeedback(
              title: 'Producto no encontrado',
              message: result.code ?? code,
              color: const Color(0xFFDC2626),
            );
            return;
          case _BarcodeScanStatus.error:
            _showFeedback(
              title: 'No se pudo consultar',
              message: 'Verifica tu conexión y vuelve a intentar.',
              color: const Color(0xFFF59E0B),
            );
            return;
        }
      } finally {
        _processingCodes.remove(code);
        _handlingScan = false;
      }
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
    } catch (_) {
      _showFeedback(
        title: 'Linterna no disponible',
        message: 'Este dispositivo no permite controlar el flash.',
        color: const Color(0xFFF59E0B),
      );
    }
  }

  Future<void> _switchCamera() async {
    try {
      await _controller.switchCamera();
    } catch (_) {
      _showFeedback(
        title: 'Cámara no disponible',
        message: 'No se pudo cambiar de cámara en este dispositivo.',
        color: const Color(0xFFF59E0B),
      );
    }
  }

  Widget _cameraError(BuildContext context, MobileScannerException error) {
    final permissionDenied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              permissionDenied
                  ? Icons.no_photography_outlined
                  : Icons.videocam_off_outlined,
              color: Colors.white,
              size: 48,
            ),
            const SizedBox(height: 14),
            Text(
              permissionDenied
                  ? 'Necesitamos acceso a la cámara para escanear códigos de barras.'
                  : 'La cámara no está disponible en este dispositivo.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton(
                  onPressed: () => unawaited(_controller.start()),
                  child: const Text('Reintentar'),
                ),
                if (permissionDenied)
                  OutlinedButton(
                    onPressed: permissions.openAppSettings,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                    ),
                    child: const Text('Configuración'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Cancelar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020617),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Volver',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: Colors.white,
                  ),
                  const Expanded(
                    child: Text(
                      'Escanear producto',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<MobileScannerState>(
                    valueListenable: _controller,
                    builder: (context, state, _) {
                      final torchOn = state.torchState == TorchState.on;
                      return IconButton(
                        tooltip: torchOn
                            ? 'Apagar linterna'
                            : 'Encender linterna',
                        onPressed: state.torchState == TorchState.unavailable
                            ? null
                            : _toggleTorch,
                        icon: Icon(
                          torchOn
                              ? Icons.flashlight_on_rounded
                              : Icons.flashlight_off_rounded,
                        ),
                        color: torchOn ? const Color(0xFFFACC15) : Colors.white,
                      );
                    },
                  ),
                  IconButton(
                    tooltip: 'Cambiar cámara',
                    onPressed: _switchCamera,
                    icon: const Icon(Icons.cameraswitch_rounded),
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scanWidth = constraints.maxWidth * 0.78;
                  final scanHeight = (scanWidth * 0.46).clamp(118.0, 170.0);
                  final scanWindow = Rect.fromCenter(
                    center: Offset(
                      constraints.maxWidth / 2,
                      constraints.maxHeight * 0.42,
                    ),
                    width: scanWidth,
                    height: scanHeight,
                  );

                  return Stack(
                    children: [
                      MobileScanner(
                        controller: _controller,
                        scanWindow: scanWindow,
                        fit: BoxFit.cover,
                        onDetect: _handleCapture,
                        errorBuilder: _cameraError,
                        placeholderBuilder: (_) => const ColoredBox(
                          color: Color(0xFF020617),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _ScannerFramePainter(
                            scanWindow: scanWindow,
                            color: _frameColor,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 18,
                        right: 18,
                        bottom: 24,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                            child: Row(
                              children: [
                                Icon(
                                  _frameColor == const Color(0xFF16A34A)
                                      ? Icons.check_circle_rounded
                                      : _frameColor == const Color(0xFFDC2626)
                                      ? Icons.error_outline_rounded
                                      : Icons.qr_code_scanner_rounded,
                                  color: _frameColor,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _feedbackTitle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF0F172A),
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _addedCount > 0
                                            ? '$_feedbackMessage · $_addedCount agregados'
                                            : _feedbackMessage,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF64748B),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
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
                    ],
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

class _ScannerFramePainter extends CustomPainter {
  const _ScannerFramePainter({required this.scanWindow, required this.color});

  final Rect scanWindow;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Paint()..color = Colors.black.withValues(alpha: 0.46);
    final fullPath = Path()..addRect(Offset.zero & size);
    final cutoutPath = Path()
      ..addRRect(RRect.fromRectAndRadius(scanWindow, const Radius.circular(8)));
    canvas.drawPath(
      Path.combine(PathOperation.difference, fullPath, cutoutPath),
      overlay,
    );

    final cornerPaint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const corner = 30.0;
    final rect = scanWindow;
    canvas
      ..drawLine(
        rect.topLeft,
        rect.topLeft + const Offset(corner, 0),
        cornerPaint,
      )
      ..drawLine(
        rect.topLeft,
        rect.topLeft + const Offset(0, corner),
        cornerPaint,
      )
      ..drawLine(
        rect.topRight,
        rect.topRight + const Offset(-corner, 0),
        cornerPaint,
      )
      ..drawLine(
        rect.topRight,
        rect.topRight + const Offset(0, corner),
        cornerPaint,
      )
      ..drawLine(
        rect.bottomLeft,
        rect.bottomLeft + const Offset(corner, 0),
        cornerPaint,
      )
      ..drawLine(
        rect.bottomLeft,
        rect.bottomLeft + const Offset(0, -corner),
        cornerPaint,
      )
      ..drawLine(
        rect.bottomRight,
        rect.bottomRight + const Offset(-corner, 0),
        cornerPaint,
      )
      ..drawLine(
        rect.bottomRight,
        rect.bottomRight + const Offset(0, -corner),
        cornerPaint,
      );
  }

  @override
  bool shouldRepaint(covariant _ScannerFramePainter oldDelegate) {
    return oldDelegate.scanWindow != scanWindow || oldDelegate.color != color;
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
  inventory,
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
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: AnimatedScale(
              scale: _pressed ? 0.94 : (_hovered ? 1.03 : 1),
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: 38,
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: active
                        ? const [Color(0xFFEAF1FF), Color(0xFFFFFFFF)]
                        : const [Color(0xFFFFFFFF), Color(0xFFF6F9FF)],
                  ),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: active
                        ? const Color(0xFF9FBCFF)
                        : const Color(0xFFD5E2FF),
                    width: 0.8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(
                        0xFF1957E6,
                      ).withValues(alpha: active ? 0.14 : 0.05),
                      blurRadius: active ? 12 : 7,
                      offset: Offset(0, active ? 4 : 2),
                    ),
                  ],
                ),
                child: AnimatedRotation(
                  turns: _pressed ? 0.03 : 0,
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOutCubic,
                  child: const Icon(
                    Icons.menu_rounded,
                    size: 21,
                    color: Color(0xFF1957E6),
                  ),
                ),
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

  Future<void> _activateProtectedRoute(
    BuildContext context,
    WidgetRef ref,
    BuildContext menuContext, {
    required String route,
    required String label,
  }) async {
    final allowed = await ensureAdminAuthorization(
      context,
      ref,
      permission: RouteAccess.permissionForLocation(route),
      reason: 'Entrar a $label',
      routeLocation: route,
    );
    if (!allowed || !context.mounted || !menuContext.mounted) return;
    Navigator.of(menuContext).pop();
    _runAfterMenuCloses(() {
      if (context.mounted) context.go(route);
    });
  }

  Future<void> _activateProtectedPanel(
    BuildContext context,
    WidgetRef ref,
    BuildContext menuContext, {
    required AppPermission permission,
    required String label,
    required Widget child,
  }) async {
    final allowed = await ensureAdminAuthorization(
      context,
      ref,
      permission: permission,
      reason: 'Abrir $label',
    );
    if (!allowed || !context.mounted || !menuContext.mounted) return;
    Navigator.of(menuContext).pop();
    _runAfterMenuCloses(() {
      if (context.mounted) _openSidePanel(context, child);
    });
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
    final authController = ref.read(authStateProvider.notifier);
    _runAfterMenuCloses(() async {
      await authController.logout();
      if (context.mounted) context.go(Routes.login);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(companySettingsProvider);
    final user = ref.watch(authStateProvider).user;
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
        constraints: const BoxConstraints(minWidth: 340, maxWidth: 340),
        itemBuilder: (menuContext) => [
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _CompanyUserMenuHeader(
              user: user,
              onTap: () => _activateMenuItem(
                menuContext,
                () => context.go(Routes.profile),
              ),
            ),
          ),
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _CompanyMenuItem(
              icon: Icons.groups_2_outlined,
              label: 'Usuarios',
              onTap: () => _activateProtectedRoute(
                context,
                ref,
                menuContext,
                route: Routes.users,
                label: 'Usuarios',
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
              onTap: () => _activateProtectedPanel(
                context,
                ref,
                menuContext,
                permission: AppPermission.manageSettings,
                label: 'Apps',
                child: const _CompanyAppsSidePanel(),
              ),
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
              onTap: () => _activateProtectedPanel(
                context,
                ref,
                menuContext,
                permission: AppPermission.manageSettings,
                label: 'Licencias',
                child: const _CompanyLicensesSidePanel(),
              ),
              helpText:
                  'Resume el estado de la empresa activa, el plan disponible y la preparación del sistema para trabajo multiempresa.',
            ),
          ),
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _CompanyMenuItem(
              icon: Icons.business_center_outlined,
              label: 'Empresa',
              onTap: () => _activateProtectedRoute(
                context,
                ref,
                menuContext,
                route: Routes.configuracionEmpresa,
                label: 'Empresa',
              ),
              helpText:
                  'Configura el nombre comercial, RNC, teléfonos, dirección, logo y datos principales usados por la empresa.',
            ),
          ),
          if (!kIsWeb)
            PopupMenuItem(
              enabled: false,
              padding: EdgeInsets.zero,
              child: _CompanyMenuItem(
                icon: Icons.print_outlined,
                label: 'Impresora',
                onTap: () => _activateProtectedRoute(
                  context,
                  ref,
                  menuContext,
                  route: Routes.configuracionImpresora,
                  label: 'Impresora',
                ),
                helpText:
                    'Ajusta la impresora, copias, tamaño del papel, datos visibles y formato del ticket.',
              ),
            ),
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _CompanyMenuItem(
              icon: Icons.cloud_sync_outlined,
              label: 'Backup',
              onTap: () => _activateProtectedRoute(
                context,
                ref,
                menuContext,
                route: Routes.configuracionBackup,
                label: 'Backup',
              ),
              helpText:
                  'Descarga un respaldo local de la empresa y valida archivos ZIP para recuperación asistida.',
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
          PopupMenuItem(
            enabled: false,
            padding: EdgeInsets.zero,
            child: _CompanyMenuItem(
              icon: Icons.delete_forever_outlined,
              label: 'Eliminar mi cuenta',
              danger: true,
              onTap: () {
                final authRepository = ref.read(authRepositoryProvider);
                final authController = ref.read(authStateProvider.notifier);
                Navigator.of(menuContext).pop();
                _runAfterMenuCloses(() {
                  if (context.mounted) {
                    showDeleteAccountDialogWithDependencies(
                      context,
                      authRepository: authRepository,
                      authController: authController,
                    );
                  }
                });
              },
              helpText:
                  'Solicita contraseña y confirmación antes de eliminar una cuenta o empresa.',
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

@visibleForTesting
Widget buildCompanyAccountMenuForTesting() => const _CompanyAccountMenu();

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
        for (final channel in AppAccessLinks.visibleChannels())
          _CompanySideActionTile(
            icon: channel.icon,
            title: channel.title,
            status: channel.status,
            description: channel.description,
            actionLabel: channel.actionLabel,
            actionIcon: channel.actionIcon,
            onPressed: () => safeOpenUrl(context, channel.uri),
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
    final licenseAsync = ref.watch(licenseStatusProvider);
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
        _LicenseAccountCard(companyName: companyName),
        ...licenseAsync.when(
          loading: () => const [_LicenseLoadingTile()],
          error: (error, _) => [_LicenseErrorTile(message: '$error')],
          data: (license) => [_LicenseDetailsCard(license: license)],
        ),
        _LicenseUpgradeCard(onPressed: () => _openUpgradeWhatsApp(context)),
      ],
    );
  }
}

void _openUpgradeWhatsApp(BuildContext context) {
  safeOpenWhatsApp(
    context,
    Uri(
      scheme: 'https',
      host: 'wa.me',
      path: '18295344286',
      queryParameters: {'text': 'Quiero hacer un upgrade'},
    ),
  );
}

String _licenseStatusLabel(String status) {
  return switch (status) {
    'ACTIVE' => 'Activa',
    'TRIAL' => 'Prueba',
    'BLOCKED' => 'Bloqueada',
    'EXPIRED' => 'Expirada',
    _ => status,
  };
}

(Color, Color) _licenseStatusColors(String status) {
  return switch (status) {
    'ACTIVE' => (const Color(0xFF15803D), const Color(0xFFE7F6EC)),
    'TRIAL' => (const Color(0xFFB45309), const Color(0xFFFDF1E0)),
    'BLOCKED' ||
    'EXPIRED' => (const Color(0xFFDC2626), const Color(0xFFFDEBEA)),
    _ => (const Color(0xFF52667C), const Color(0xFFEEF2F6)),
  };
}

String _licenseDateLabel(DateTime? value) {
  if (value == null) return 'Sin configuración';
  final local = value.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/${local.year}';
}

String _licenseRemainingLabel(LicenseStatusModel license) {
  if (license.daysRemaining == null) return 'Sin fecha de cierre';
  if (license.daysRemaining! < 0) return 'Periodo vencido';
  if (license.daysRemaining == 0) return 'Vence hoy';
  return 'Quedan ${license.daysRemaining} días';
}

class _LicenseLoadingTile extends StatelessWidget {
  const _LicenseLoadingTile();

  @override
  Widget build(BuildContext context) {
    return _CompanySideSurface(
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.4,
              color: Color(0xFF1957E6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Cargando los datos de tu licencia…',
              style: _companySideBodyStyle(),
            ),
          ),
        ],
      ),
    );
  }
}

class _LicenseErrorTile extends StatelessWidget {
  const _LicenseErrorTile({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _CompanySideSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFDC2626),
                size: 20,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No se pudo cargar la licencia',
                  style: TextStyle(
                    color: Color(0xFFDC2626),
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: _companySideBodyStyle(),
          ),
        ],
      ),
    );
  }
}

class _LicenseAccountCard extends StatelessWidget {
  const _LicenseAccountCard({required this.companyName});

  final String companyName;

  @override
  Widget build(BuildContext context) {
    return _CompanySideSurface(
      child: Column(
        children: [
          Row(
            children: [
              _CompanySideIcon(icon: Icons.business_rounded, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Empresa activa', style: _companySideBodyStyle()),
                    const SizedBox(height: 2),
                    Text(
                      companyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _companySideTitleStyle(15),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LicenseDetailsCard extends StatefulWidget {
  const _LicenseDetailsCard({required this.license});

  final LicenseStatusModel license;

  @override
  State<_LicenseDetailsCard> createState() => _LicenseDetailsCardState();
}

class _LicenseDetailsCardState extends State<_LicenseDetailsCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final license = widget.license;
    final statusLabel = _licenseStatusLabel(license.status);
    final (fg, bg) = _licenseStatusColors(license.status);
    final hasKey =
        license.licenseKey != null && license.licenseKey!.trim().isNotEmpty;
    final hasNotes = license.notes != null && license.notes!.trim().isNotEmpty;
    final account = license.account;
    final responsible = account?.responsibleName?.trim();
    final whatsapp = account?.responsibleWhatsapp?.trim();
    final businessPhone = account?.businessPhone?.trim();
    final taxId = account?.taxId?.trim();
    final businessAddress = account?.businessAddress?.trim();
    final legalRole = account?.legalRepresentativeRole?.trim();
    final usersExceeded =
        license.maxUsers > 0 && license.users > license.maxUsers;
    final productsExceeded =
        license.maxProducts > 0 && license.products > license.maxProducts;

    return _CompanySideSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PLAN CONTRATADO', style: _licenseSectionStyle()),
                    const SizedBox(height: 4),
                    Text(
                      license.planLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _companySideTitleStyle(17),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _LicenseStatusPill(label: statusLabel, fg: fg, bg: bg),
            ],
          ),
          const SizedBox(height: 14),
          const _CompanySideDivider(),
          const SizedBox(height: 12),
          Text('DATOS DE LA CUENTA', style: _licenseSectionStyle()),
          const SizedBox(height: 6),
          _LicenseInfoRow(
            label: 'Negocio',
            value: account?.businessName?.trim().isNotEmpty == true
                ? account!.businessName!
                : license.companyName,
          ),
          if (responsible != null && responsible.isNotEmpty)
            _LicenseInfoRow(label: 'Responsable', value: responsible),
          if (legalRole != null && legalRole.isNotEmpty)
            _LicenseInfoRow(label: 'Cargo', value: legalRole),
          if (whatsapp != null && whatsapp.isNotEmpty)
            _LicenseInfoRow(label: 'WhatsApp', value: whatsapp),
          if (businessPhone != null &&
              businessPhone.isNotEmpty &&
              businessPhone != whatsapp)
            _LicenseInfoRow(label: 'Teléfono negocio', value: businessPhone),
          if (taxId != null && taxId.isNotEmpty)
            _LicenseInfoRow(label: 'RNC/Cédula', value: taxId),
          const SizedBox(height: 14),
          const _CompanySideDivider(),
          const SizedBox(height: 12),
          Text('VIGENCIA', style: _licenseSectionStyle()),
          const SizedBox(height: 6),
          _LicenseInfoRow(label: 'Tipo', value: license.typeLabel),
          if (license.acquiredAt != null)
            _LicenseInfoRow(
              label: 'Inicio',
              value: _licenseDateLabel(license.acquiredAt),
            ),
          if (license.periodEndsAt != null)
            _LicenseInfoRow(
              label: 'Vence',
              value: _licenseDateLabel(license.periodEndsAt),
            ),
          if (license.daysRemaining != null)
            _LicenseInfoRow(
              label: 'Tiempo restante',
              value: _licenseRemainingLabel(license),
              valueColor: _licenseRemainingColor(license),
            ),
          const SizedBox(height: 14),
          const _CompanySideDivider(),
          const SizedBox(height: 12),
          Text('USO DE LA LICENCIA', style: _licenseSectionStyle()),
          const SizedBox(height: 10),
          _LicenseMeter(
            icon: Icons.people_outline_rounded,
            title: 'Usuarios',
            used: license.users,
            max: license.maxUsers,
          ),
          const SizedBox(height: 14),
          _LicenseMeter(
            icon: Icons.inventory_2_outlined,
            title: 'Productos',
            used: license.products,
            max: license.maxProducts,
          ),
          if (usersExceeded || productsExceeded) ...[
            const SizedBox(height: 12),
            _LicenseLimitBanner(
              message: [
                if (usersExceeded)
                  'Usuarios: ${license.users} de ${license.maxUsers}',
                if (productsExceeded)
                  'Productos: ${license.products} de ${license.maxProducts}',
              ].join(' · '),
            ),
          ],
          if ((businessAddress != null && businessAddress.isNotEmpty) ||
              hasKey ||
              hasNotes) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                ),
                label: Text(_expanded ? 'Ver menos' : 'Ver más'),
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 6),
              const _CompanySideDivider(),
              const SizedBox(height: 12),
              if (businessAddress != null && businessAddress.isNotEmpty)
                _LicenseInfoRow(label: 'Dirección', value: businessAddress),
              if (hasKey)
                _LicenseInfoRow(label: 'Clave', value: license.licenseKey!),
              if (hasNotes)
                _LicenseInfoRow(label: 'Notas', value: license.notes!),
            ],
          ],
        ],
      ),
    );
  }
}

class _LicenseLimitBanner extends StatelessWidget {
  const _LicenseLimitBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFD97706),
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Esta cuenta superó el alcance contratado. $message. El servidor no permitirá crear más hasta aumentar el plan o liberar uso.',
              style: const TextStyle(
                color: Color(0xFF92400E),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.25,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LicenseInfoRow extends StatelessWidget {
  const _LicenseInfoRow({
    required this.label,
    required this.value,
    this.valueColor = const Color(0xFF183548),
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: _companySideBodyStyle())),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: valueColor,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LicenseMeter extends StatelessWidget {
  const _LicenseMeter({
    required this.icon,
    required this.title,
    required this.used,
    required this.max,
  });

  final IconData icon;
  final String title;
  final int used;
  final int max;

  @override
  Widget build(BuildContext context) {
    final hasLimit = max > 0;
    final fraction = hasLimit ? (used / max).clamp(0.0, 1.0).toDouble() : 0.0;
    final percent = hasLimit ? (fraction * 100).round() : 100;
    final exceeded = hasLimit && used > max;
    final Color barColor = !hasLimit
        ? const Color(0xFF1957E6)
        : exceeded
        ? const Color(0xFFDC2626)
        : fraction >= 0.8
        ? const Color(0xFFD97706)
        : const Color(0xFF1957E6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF64748B)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _companySideBodyStyle(),
              ),
            ),
            Text(
              hasLimit ? '$used de $max' : '$used',
              style: const TextStyle(
                color: Color(0xFF183548),
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            if (hasLimit) ...[
              const SizedBox(width: 8),
              Text(
                '$percent%',
                style: const TextStyle(
                  color: Color(0xFF7A8B9F),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: const Color(0xFFE9F0F6),
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
      ],
    );
  }
}

class _LicenseStatusPill extends StatelessWidget {
  const _LicenseStatusPill({
    required this.label,
    required this.fg,
    required this.bg,
  });

  final String label;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _LicenseUpgradeCard extends StatelessWidget {
  const _LicenseUpgradeCard({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC9DCFB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _CompanySideIcon(icon: Icons.upgrade_rounded, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Solicitar upgrade',
                      style: _companySideTitleStyle(15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Más usuarios, más productos o un plan superior.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _companySideBodyStyle(),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.chat_rounded, size: 18),
              label: const Text('Solicitar upgrade'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanySideDivider extends StatelessWidget {
  const _CompanySideDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: const Color(0xFFE8EEF4));
  }
}

TextStyle _licenseSectionStyle() {
  return const TextStyle(
    color: Color(0xFF7A8B9F),
    fontSize: 11,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.8,
    height: 1.2,
  );
}

Color _licenseRemainingColor(LicenseStatusModel license) {
  if (license.daysRemaining == null) return const Color(0xFF183548);
  if (license.daysRemaining! <= 0) return const Color(0xFFDC2626);
  return const Color(0xFF183548);
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
    this.actionLabel,
    this.actionIcon,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String status;
  final String description;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onPressed;

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
                if (actionLabel != null && onPressed != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: onPressed,
                    icon: Icon(
                      actionIcon ?? Icons.open_in_new_rounded,
                      size: 17,
                    ),
                    label: Text(actionLabel!),
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
  const _CompanySideIcon({required this.icon, this.size = 34});

  final IconData icon;
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
      child: Icon(icon, size: size * 0.48, color: const Color(0xFF1957E6)),
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

class _CompanyUserMenuHeader extends StatefulWidget {
  const _CompanyUserMenuHeader({required this.user, required this.onTap});

  final UserModel? user;
  final VoidCallback onTap;

  @override
  State<_CompanyUserMenuHeader> createState() => _CompanyUserMenuHeaderState();
}

class _CompanyUserMenuHeaderState extends State<_CompanyUserMenuHeader> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final name = (user?.nombreCompleto ?? '').trim().isEmpty
        ? 'Usuario'
        : user!.nombreCompleto.trim();
    final email = (user?.email ?? '').trim();
    final role = user?.appRole.label ?? AppRole.unknown.label;
    final details = email.isEmpty ? role : '$role · $email';
    final photoUrl = (user?.fotoPersonalUrl ?? '').trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _hovered
                    ? const Color(0xFFF3F7FF)
                    : const Color(0xFFF8FBFF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _hovered
                      ? const Color(0xFFBFD1FF)
                      : const Color(0xFFDCE7F3),
                ),
              ),
              child: Row(
                children: [
                  UserAvatar(
                    radius: 17,
                    imageUrl: photoUrl,
                    backgroundColor: const Color(0xFFEAF1FF),
                    child: Text(
                      _companyUserInitials(name),
                      style: const TextStyle(
                        color: Color(0xFF1957E6),
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF13243A),
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          details,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF5B708A),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _hovered
                          ? const Color(0xFFE8EFFF)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 12,
                      color: Color(0xFF8AA0B8),
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

String _companyUserInitials(String name) {
  final initials = name
      .split(' ')
      .map((part) => part.isEmpty ? '' : part[0].toUpperCase())
      .join();
  if (initials.isEmpty) return 'U';
  return initials.length > 1 ? initials.substring(0, 2) : initials;
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
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FF),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFDDEAFF)),
      ),
      child: Text(
        text,
        softWrap: true,
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
    required this.hasCreditCustomer,
    required this.onConfirm,
  });

  final double total;
  final String Function(double value) money;
  final bool hasCreditCustomer;
  final ValueChanged<_CheckoutResult> onConfirm;

  @override
  State<_CheckoutPaymentDialog> createState() => _CheckoutPaymentDialogState();
}

class _CheckoutPaymentDialogState extends State<_CheckoutPaymentDialog> {
  _CheckoutPaymentMethod _method = _CheckoutPaymentMethod.cash;
  late final TextEditingController _cashController;
  late final TextEditingController _transferController;
  bool _confirming = false;

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
      if (!widget.hasCreditCustomer) return false;
      return _coveredAmount >= 0 && _coveredAmount <= widget.total + 0.0001;
    }
    if (_method == _CheckoutPaymentMethod.mixed) {
      return _cashAmount > 0 &&
          _transferAmount > 0 &&
          (_coveredAmount - widget.total).abs() < 0.01;
    }
    return _coveredAmount + 0.0001 >= widget.total;
  }

  bool get _showCashShortcuts => _method == _CheckoutPaymentMethod.cash;

  double get _remainingAmount {
    return (widget.total - _coveredAmount).clamp(0, double.infinity);
  }

  List<double> get _quickCashAmounts {
    final total = widget.total;
    final suggestions = <double>[];

    void add(double value) {
      final rounded = double.parse(value.toStringAsFixed(2));
      if (rounded + 0.0001 < total) return;
      if (suggestions.any((item) => (item - rounded).abs() < 0.01)) return;
      suggestions.add(rounded);
    }

    double nextMultiple(double step) {
      final exact = (total / step).ceil() * step;
      return exact <= total + 0.0001 ? exact + step : exact;
    }

    if (total <= 2500) {
      final first = nextMultiple(500);
      add(first);
      add(first + 500);
      add(first + 1000);
    } else if (total <= 5000) {
      add(nextMultiple(500));
      add(nextMultiple(1000));
      add(nextMultiple(5000));
    } else if (total <= 10000) {
      add(nextMultiple(500));
      add(nextMultiple(5000));
      add(nextMultiple(5000) + 5000);
    } else {
      add(nextMultiple(1000));
      add(nextMultiple(5000));
      add(nextMultiple(10000));
    }

    return suggestions.take(3).toList(growable: false);
  }

  String _quickAmountLabel(double value) {
    return NumberFormat('#,##0', 'en_US').format(value.round());
  }

  void _applyCashAmount(double value) {
    setState(() {
      _cashController.text = _formatAccountingInput(value);
      _cashController.selection = TextSelection.collapsed(
        offset: _cashController.text.length,
      );
    });
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
    if (!_canConfirm || _confirming) return;
    setState(() => _confirming = true);
    widget.onConfirm(_result());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.sizeOf(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final isMobile = media.width < 640;
    final isTransfer = _method == _CheckoutPaymentMethod.transfer;
    final isMixed = _method == _CheckoutPaymentMethod.mixed;
    final isCredit = _method == _CheckoutPaymentMethod.credit;
    final blockedMessage = _canConfirm
        ? null
        : isCredit
        ? !widget.hasCreditCustomer
              ? 'Selecciona un cliente para registrar crédito'
              : 'El abono no puede superar el total'
        : 'Monto recibido insuficiente';

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
            vertical: isMobile ? 8 : 20,
          ),
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isMobile ? 6 : 8),
            side: const BorderSide(color: Color(0xFFDDE7EE)),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isMobile ? 430 : 780,
              maxHeight:
                  media.height - viewInsets.bottom - (isMobile ? 20 : 40),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 14 : 24,
                    isMobile ? 9 : 16,
                    isMobile ? 10 : 16,
                    isMobile ? 7 : 14,
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
                                fontSize: isMobile ? 18 : 18,
                                fontWeight: isMobile
                                    ? FontWeight.w600
                                    : FontWeight.w900,
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
                      isMobile ? 12 : 24,
                      isMobile ? 10 : 16,
                      isMobile ? 12 : 24,
                      isMobile ? 10 : 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 12 : 16,
                            vertical: isMobile ? 12 : 16,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFCFEFF),
                            borderRadius: BorderRadius.circular(
                              isMobile ? 10 : 8,
                            ),
                            border: Border.all(color: const Color(0xFFDCE5F0)),
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
                                            fontSize: 12,
                                            color: Color(0xFF64748B),
                                            fontWeight: FontWeight.w500,
                                            letterSpacing: 0,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          widget.money(widget.total),
                                          style: const TextStyle(
                                            fontSize: 29,
                                            fontWeight: FontWeight.w700,
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
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0,
                                          ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          widget.money(widget.total),
                                          style: const TextStyle(
                                            fontSize: 31,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF0F172A),
                                            letterSpacing: 0,
                                          ),
                                        ),
                                      ],
                                    ),
                              const Divider(
                                height: 22,
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
                                if (_showCashShortcuts) ...[
                                  const SizedBox(height: 8),
                                  _QuickCashAmountRow(
                                    amounts: _quickCashAmounts,
                                    amountLabel: _quickAmountLabel,
                                    onExact: () =>
                                        _applyCashAmount(widget.total),
                                    onAmount: _applyCashAmount,
                                  ),
                                ],
                                const SizedBox(height: 9),
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
                                const SizedBox(height: 9),
                              ] else if (isTransfer) ...[
                                _ReadonlyPaymentLine(
                                  icon: Icons.account_balance_outlined,
                                  label: 'Transferencia',
                                  value: widget.money(widget.total),
                                ),
                                const SizedBox(height: 4),
                              ],
                              if (isCredit) ...[
                                _ReadonlyPaymentLine(
                                  icon: Icons.credit_score_outlined,
                                  label: 'Queda a crédito',
                                  value: widget.money(_creditAmount),
                                  strong: _creditAmount > 0,
                                ),
                                const SizedBox(height: 4),
                              ],
                              if (!isTransfer && !isCredit)
                                _ReadonlyPaymentLine(
                                  icon: _remainingAmount > 0
                                      ? Icons.error_outline_rounded
                                      : Icons.keyboard_return_rounded,
                                  label: _remainingAmount > 0
                                      ? 'Faltan'
                                      : 'Devuelta',
                                  value: widget.money(
                                    _remainingAmount > 0
                                        ? _remainingAmount
                                        : _changeAmount,
                                  ),
                                  strong:
                                      _changeAmount > 0 || _remainingAmount > 0,
                                  danger: _remainingAmount > 0,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 11),
                        Text(
                          'Método de pago',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0F172A),
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 7),
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
                                  const SizedBox(height: 6),
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
                    isMobile ? 12 : 24,
                    isMobile ? 8 : 12,
                    isMobile ? 12 : 24,
                    isMobile ? 10 : 16,
                  ),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    border: Border(top: BorderSide(color: Color(0xFFDDE7EE))),
                  ),
                  child: isMobile
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (blockedMessage != null) ...[
                              Text(
                                blockedMessage,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0,
                                ),
                              ),
                              const SizedBox(height: 7),
                            ],
                            FilledButton.icon(
                              onPressed: _canConfirm && !_confirming
                                  ? _confirmCheckout
                                  : null,
                              icon: _confirming
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.receipt_long_outlined,
                                      size: 18,
                                    ),
                              label: Text(
                                _confirming
                                    ? 'Procesando...'
                                    : _method == _CheckoutPaymentMethod.credit
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
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: _confirming
                                  ? null
                                  : () => Navigator.of(context).pop(),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF1957E6),
                                textStyle: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
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
                                    : blockedMessage ??
                                          'Monto recibido insuficiente',
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
                              onPressed: _canConfirm && !_confirming
                                  ? _confirmCheckout
                                  : null,
                              icon: _confirming
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.receipt_long_outlined),
                              label: Text(
                                _confirming
                                    ? 'Procesando...'
                                    : _method == _CheckoutPaymentMethod.credit
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

class _QuickCashAmountRow extends StatelessWidget {
  const _QuickCashAmountRow({
    required this.amounts,
    required this.amountLabel,
    required this.onExact,
    required this.onAmount,
  });

  final List<double> amounts;
  final String Function(double value) amountLabel;
  final VoidCallback onExact;
  final ValueChanged<double> onAmount;

  @override
  Widget build(BuildContext context) {
    final entries = <Widget>[
      _QuickCashAmountButton(label: 'Exacto', onTap: onExact),
      for (final amount in amounts)
        _QuickCashAmountButton(
          label: amountLabel(amount),
          onTap: () => onAmount(amount),
        ),
    ];

    return Wrap(spacing: 6, runSpacing: 6, children: entries);
  }
}

class _QuickCashAmountButton extends StatelessWidget {
  const _QuickCashAmountButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1E293B),
          side: const BorderSide(color: Color(0xFFDCE5F0)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
        child: Text(label),
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
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF0F172A),
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 5),
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
              fontWeight: FontWeight.w600,
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
        fontWeight: FontWeight.w600,
        fontSize: 15,
        letterSpacing: 0,
      ),
      decoration: InputDecoration(
        prefixText: r'RD$  ',
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFDCE5F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFDCE5F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF1957E6), width: 1.4),
        ),
        prefixStyle: const TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w500,
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
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool strong;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
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
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: danger
                  ? const Color(0xFFDC2626)
                  : strong
                  ? const Color(0xFF1957E6)
                  : const Color(0xFF64748B),
              fontSize: 16,
              fontWeight: FontWeight.w600,
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
      color: selected ? const Color(0xFF2563EB) : const Color(0xFFFFFFFF),
      borderRadius: BorderRadius.circular(compact ? 7 : 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(compact ? 7 : 8),
        child: Container(
          height: compact ? 44 : 50,
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 7 : 8),
            border: Border.all(
              color: selected
                  ? const Color(0xFF2563EB)
                  : const Color(0xFFDCE5F0),
            ),
          ),
          child: Row(
            children: [
              Icon(
                method.icon,
                size: compact ? 18 : 19,
                color: selected ? Colors.white : const Color(0xFF2563EB),
              ),
              SizedBox(width: compact ? 9 : 10),
              Text(
                method.label,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF1E293B),
                  fontWeight: FontWeight.w500,
                  fontSize: compact ? 13.5 : 14,
                  letterSpacing: 0,
                ),
              ),
              const Spacer(),
              if (selected)
                const Icon(Icons.check_rounded, color: Colors.white, size: 18),
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
    required this.onReprintTicket,
    required this.onClose,
    required this.onOpenFullHistory,
  });

  final Future<List<SaleModel>> Function() loadSales;
  final String Function(double value) money;
  final String Function(DateTime? date) dateLabel;
  final String Function(SaleModel sale) shortId;
  final ValueChanged<SaleModel> onViewSale;
  final ValueChanged<SaleModel> onOpenPdf;
  final ValueChanged<SaleModel> onReprintTicket;
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
                              SizedBox(width: 126),
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
                                onReprintTicket: widget.onReprintTicket,
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
    required this.onReprintTicket,
    required this.onOpenFullHistory,
  });

  final SaleModel sale;
  final String Function(double value) money;
  final String Function(DateTime? date) dateLabel;
  final String Function(SaleModel sale) shortId;
  final ValueChanged<SaleModel> onViewSale;
  final ValueChanged<SaleModel> onOpenPdf;
  final ValueChanged<SaleModel> onReprintTicket;
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
            width: 126,
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
                IconButton(
                  tooltip: 'Reimprimir ticket',
                  onPressed: () => onReprintTicket(sale),
                  icon: const Icon(Icons.print_outlined, size: 18),
                  color: const Color(0xFF1957E6),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuoteClientInlineDetail extends StatelessWidget {
  const _QuoteClientInlineDetail({
    required this.client,
    required this.onBack,
    required this.onUse,
  });

  final ClienteModel client;
  final VoidCallback onBack;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = client.nombre.trim().isEmpty
        ? 'Cliente sin nombre'
        : client.nombre.trim();
    final phone = client.telefono.trim();
    final email = (client.correo ?? '').trim();
    final address = (client.direccion ?? '').trim();
    final gps = (client.locationUrl ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Volver a clientes',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                'Detalle del cliente',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: ListView(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD8E5EC)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: client.isDeleted
                                ? theme.colorScheme.error
                                : const Color(0xFF059669),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          client.isDeleted ? 'Eliminado' : 'Activo',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: client.isDeleted
                                ? theme.colorScheme.error
                                : const Color(0xFF059669),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (phone.isNotEmpty)
                _QuoteClientDetailLine(
                  icon: Icons.call_outlined,
                  label: 'Teléfono',
                  value: phone,
                ),
              if (email.isNotEmpty)
                _QuoteClientDetailLine(
                  icon: Icons.email_outlined,
                  label: 'Correo',
                  value: email,
                ),
              if (address.isNotEmpty)
                _QuoteClientDetailLine(
                  icon: Icons.place_outlined,
                  label: 'Dirección',
                  value: address,
                  maxLines: 3,
                ),
              if (gps.isNotEmpty)
                const _QuoteClientDetailLine(
                  icon: Icons.map_outlined,
                  label: 'Ubicación',
                  value: 'GPS disponible',
                ),
              if (client.createdAt != null)
                _QuoteClientDetailLine(
                  icon: Icons.calendar_today_outlined,
                  label: 'Creado',
                  value: DateFormat(
                    'dd/MM/yyyy',
                  ).format(client.createdAt!.toLocal()),
                ),
              if (client.updatedAt != null)
                _QuoteClientDetailLine(
                  icon: Icons.update_rounded,
                  label: 'Actualizado',
                  value: DateFormat(
                    'dd/MM/yyyy',
                  ).format(client.updatedAt!.toLocal()),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: client.isDeleted ? null : onUse,
          icon: const Icon(Icons.check_rounded),
          label: const Text('Usar este cliente'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF1957E6),
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuoteClientDetailLine extends StatelessWidget {
  const _QuoteClientDetailLine({
    required this.icon,
    required this.label,
    required this.value,
    this.maxLines = 1,
  });

  final IconData icon;
  final String label;
  final String value;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FF),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xFFCFE0FF)),
            ),
            child: Icon(icon, color: const Color(0xFF1957E6), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF64748B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: maxLines,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.15,
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

class _MobileSelectorButton extends StatelessWidget {
  const _MobileSelectorButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.overline,
    this.showDot = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? overline;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF2563EB), size: 17),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((overline ?? '').trim().isNotEmpty)
                      Text(
                        overline!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 9,
                          height: 1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF334155),
                        fontSize: 12.2,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (showDot) ...[
                const SizedBox(width: 4),
                const _TicketActivityDot(),
              ],
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF64748B),
                size: 17,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductThumbCard extends StatelessWidget {
  const _ProductThumbCard({
    required this.product,
    required this.onTap,
    required this.onImageTap,
    required this.money,
  });

  final ProductModel product;
  final VoidCallback onTap;
  final VoidCallback onImageTap;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final stockValue = product.stock;
    final outOfStock = stockValue == null || stockValue <= 0;
    final stockText = _formatProductStock(stockValue);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE9EEF5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.025),
                blurRadius: 7,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 38,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onImageTap,
                    child: Hero(
                      tag: 'product-image-preview-${product.id}',
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: (product.displayFotoUrl ?? '').trim().isEmpty
                              ? const Center(
                                  child: Icon(
                                    Icons.inventory_2_outlined,
                                    size: 32,
                                    color: Color(0xFF94A3B8),
                                  ),
                                )
                              : ProductNetworkImage(
                                  imageUrl: product.displayFotoUrl!,
                                  productId: product.id,
                                  productName: product.nombre,
                                  originalUrl: product.originalFotoUrl,
                                  fit: BoxFit.contain,
                                  loading: const Center(
                                    child: Icon(
                                      Icons.inventory_2_outlined,
                                      size: 28,
                                      color: Color(0xFFCBD5E1),
                                    ),
                                  ),
                                  fallback: const Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      size: 28,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Expanded(
                  flex: 62,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.nombre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF1E293B),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        money(product.precio),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF2563EB),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: outOfStock
                                    ? const Color(0xFFFEF2F2)
                                    : const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                stockText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: outOfStock
                                      ? const Color(0xFFDC2626)
                                      : const Color(0xFF15803D),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF6FF),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: Color(0xFF2563EB),
                              size: 22,
                            ),
                          ),
                        ],
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

class _ProductImagePreviewScreen extends StatelessWidget {
  const _ProductImagePreviewScreen({
    required this.product,
    required this.money,
    required this.showAdminCost,
  });

  final ProductModel product;
  final String Function(double) money;
  final bool showAdminCost;

  @override
  Widget build(BuildContext context) {
    final imageUrl = (product.displayFotoUrl ?? '').trim();
    final hasImage = imageUrl.isNotEmpty;
    final bottomSafe = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FBFF),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF8FBFF), Color(0xFFF4F8FF), Color(0xFFEEF5FF)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: IconButton(
                        tooltip: 'Cerrar',
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.nombre,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              height: 1.12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  money(product.precio),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF2563EB),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (showAdminCost) ...[
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    'COSTE ${money(product.costo)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFDC2626),
                                      fontSize: 12.5,
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
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(14, 8, 14, 18 + bottomSafe),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Hero(
                        tag: 'product-image-preview-${product.id}',
                        child: InteractiveViewer(
                          minScale: 1,
                          maxScale: 4,
                          clipBehavior: Clip.none,
                          child: Center(
                            child: hasImage
                                ? ProductNetworkImage(
                                    imageUrl: imageUrl,
                                    productId: product.id,
                                    productName: product.nombre,
                                    originalUrl: product.originalFotoUrl,
                                    fit: BoxFit.contain,
                                    loading: const Center(
                                      child: SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.4,
                                          color: Color(0xFF2563EB),
                                        ),
                                      ),
                                    ),
                                    fallback: const _ProductPreviewPlaceholder(
                                      icon: Icons.broken_image_outlined,
                                      label: 'Imagen no disponible',
                                    ),
                                  )
                                : const _ProductPreviewPlaceholder(
                                    icon: Icons.inventory_2_outlined,
                                    label: 'Producto sin imagen',
                                  ),
                          ),
                        ),
                      ),
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

class _ProductPreviewPlaceholder extends StatelessWidget {
  const _ProductPreviewPlaceholder({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 54, color: const Color(0xFF94A3B8)),
        const SizedBox(height: 12),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
                              textAlignVertical: TextAlignVertical.center,
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
                                filled: true,
                                fillColor: Colors.transparent,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 11,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                              ),
                            ),
                          ),
                          if (widget.searchController.text.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: IconButton(
                                tooltip: 'Limpiar búsqueda',
                                onPressed: () {
                                  widget.searchController.clear();
                                  widget.onSearchChanged();
                                },
                                icon: const Icon(
                                  Icons.close_rounded,
                                  size: 18,
                                  color: Color(0xFF617383),
                                ),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 32,
                                  height: 32,
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
  String? _manualError;

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
        borderSide: const BorderSide(color: Color(0xFF1957E6), width: 1.4),
      ),
    );
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _manualError = 'Completa el nombre del producto.');
      _nameFocus.requestFocus();
      return;
    }
    if (_qty <= 0) {
      setState(() => _manualError = 'La cantidad debe ser mayor que cero.');
      _qtyFocus.requestFocus();
      return;
    }
    if (_price <= 0) {
      setState(
        () => _manualError = 'El precio unitario debe ser mayor que cero.',
      );
      _priceFocus.requestFocus();
      return;
    }
    setState(() => _manualError = null);
    widget.onSubmit(
      name: name,
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
        onChanged: (value) {
          if (_manualError != null) setState(() => _manualError = null);
          onChanged?.call(value);
        },
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
            if (_manualError != null) ...[
              const SizedBox(height: 10),
              Text(
                _manualError!,
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
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
                      backgroundColor: const Color(0xFF1957E6),
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
    required this.onOpenFiscalData,
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
    required this.isOutOfStock,
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
  final VoidCallback? onOpenFiscalData;
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
  final bool Function(CotizacionItem item) isOutOfStock;
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
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Text(
                                              'Cliente',
                                              style: theme.textTheme.labelSmall
                                                  ?.copyWith(
                                                    color: const Color(
                                                      0xFF6B7F90,
                                                    ),
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: 0,
                                                  ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                selectedClientName.trim(),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: nameStyle,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        constraints: const BoxConstraints(
                                          maxWidth: 128,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF6FAFF),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(
                                            color: const Color(0xFFDDEAFF),
                                          ),
                                        ),
                                        child: Text(
                                          'Tel: $clientPhone',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: phoneStyle,
                                        ),
                                      ),
                                    ],
                                  );
                                }

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Cliente',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: const Color(0xFF6B7F90),
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0,
                                          ),
                                    ),
                                    Text(
                                      selectedClientName.trim(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: nameStyle,
                                    ),
                                    if (clientPhone.isNotEmpty)
                                      Text(
                                        'Tel: $clientPhone',
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
                          outOfStock: isOutOfStock(item),
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
                        if (includeItbis) ...[
                          IconButton(
                            tooltip: 'Datos fiscales',
                            onPressed: onOpenFiscalData,
                            icon: const Icon(Icons.receipt_long_outlined),
                            color: const Color(0xFF1957E6),
                          ),
                          const SizedBox(width: 6),
                        ],
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
    required this.customerTaxId,
    required this.customerName,
    required this.onCustomerTaxIdChanged,
    required this.onCustomerNameChanged,
  });

  final String customerTaxId;
  final String customerName;
  final ValueChanged<String> onCustomerTaxIdChanged;
  final ValueChanged<String> onCustomerNameChanged;

  @override
  State<_DesktopFiscalInvoicePanel> createState() =>
      _DesktopFiscalInvoicePanelState();
}

class _DesktopFiscalInvoicePanelState
    extends State<_DesktopFiscalInvoicePanel> {
  late final TextEditingController _taxIdCtrl;
  late final TextEditingController _customerNameCtrl;

  @override
  void initState() {
    super.initState();
    _taxIdCtrl = TextEditingController(text: widget.customerTaxId);
    _customerNameCtrl = TextEditingController(text: widget.customerName);
  }

  @override
  void didUpdateWidget(covariant _DesktopFiscalInvoicePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    _taxIdCtrl.dispose();
    _customerNameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                          'Datos fiscales',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF132337),
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'La cotización no emite NCF',
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
                    const Text(
                      'El NCF se asigna únicamente al convertir y emitir la venta desde el backend.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF647985),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _taxIdCtrl,
                      onChanged: widget.onCustomerTaxIdChanged,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'RNC / Cédula (opcional)',
                        border: OutlineInputBorder(),
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
                              insetPadding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 24,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              title: const Row(
                                children: [
                                  Icon(
                                    Icons.add_shopping_cart_rounded,
                                    color: Color(0xFF1957E6),
                                  ),
                                  SizedBox(width: 10),
                                  Text('Venta manual'),
                                ],
                              ),
                              content: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 520,
                                ),
                                child: Text(helpText),
                              ),
                              actions: [
                                FilledButton(
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
                          const SizedBox(height: 12),
                          const Text(
                            'Venta manual',
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
                          const SizedBox(height: 6),
                          const Text(
                            'Fuera de inventario',
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
    required this.outOfStock,
    required this.onEditLine,
    required this.onMinus,
    required this.onPlus,
    required this.onChangePrice,
    required this.onEdit,
    required this.onRemove,
  });

  final CotizacionItem item;
  final String Function(double) money;
  final bool outOfStock;
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
    final outOfStock = widget.outOfStock;
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
                    if (outOfStock)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 2),
                        child: Text(
                          'Sin stock',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Color(0xFFDC2626),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w900,
                            height: 1,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
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
                tooltip: 'Quitar de la venta',
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
          icon: const Icon(Icons.remove_circle_outline_rounded, size: 19),
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
    duration: const Duration(milliseconds: 2800),
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
          final glow = 0.20 * (1 - t);
          final halo = size * (1.0 + 0.03 * t);
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
              duration: const Duration(milliseconds: 340),
              curve: Curves.easeInOutCubic,
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: isPrimary ? const Color(0xFF1957E6) : Colors.white,
                shape: widget.compact ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: widget.compact ? BorderRadius.circular(14) : null,
                border: Border.all(
                  color: const Color(0xFF1957E6),
                  width: isPrimary ? 2 : 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1957E6).withValues(alpha: 0.28),
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
    required this.createdAt,
    required this.companyId,
    required this.createdByUserId,
    required this.createdByUserName,
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
    DateTime? createdAt,
    String? companyId,
    String? createdByUserId,
    String? createdByUserName,
  }) {
    return _DesktopTicketDraft(
      id: id,
      title: title,
      createdAt: createdAt ?? DateTime.now(),
      companyId: companyId,
      createdByUserId: createdByUserId,
      createdByUserName: createdByUserName,
      items: const [],
      selectedClientId: null,
      selectedClientName: 'Sin cliente',
      selectedClientPhone: null,
      note: '',
      includeItbis: false,
      fiscalVoucherType: '',
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
  final DateTime createdAt;
  final String? companyId;
  final String? createdByUserId;
  final String? createdByUserName;
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
    DateTime? createdAt,
    String? companyId,
    String? createdByUserId,
    String? createdByUserName,
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
      createdAt: createdAt ?? this.createdAt,
      companyId: companyId ?? this.companyId,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      createdByUserName: createdByUserName ?? this.createdByUserName,
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
    'createdAt': createdAt.toIso8601String(),
    'companyId': companyId,
    'createdByUserId': createdByUserId,
    'createdByUserName': createdByUserName,
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
      createdAt:
          DateTime.tryParse((map['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      companyId: map['companyId']?.toString(),
      createdByUserId: map['createdByUserId']?.toString(),
      createdByUserName: map['createdByUserName']?.toString(),
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
      fiscalVoucherType: (map['fiscalVoucherType'] ?? '').toString(),
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
    final editAction = widget.onEdit ?? widget.onEditLine;

    String formatNoDecimals(num value) {
      final v = value.toDouble();
      return v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: editAction,
        onDoubleTap: widget.onEditLine,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: (item.imageUrl ?? '').trim().isEmpty
                      ? Container(
                          color: const Color(0xFFF1F5F9),
                          alignment: Alignment.center,
                          child: Icon(
                            item.isExternal
                                ? Icons.edit_note_outlined
                                : Icons.inventory_2_outlined,
                            size: 17,
                            color: const Color(0xFF64748B),
                          ),
                        )
                      : ProductNetworkImage(
                          imageUrl: item.imageUrl!,
                          productId: item.productId,
                          productName: item.nombre,
                          originalUrl: item.imageUrl,
                          fit: BoxFit.contain,
                          loading: const ColoredBox(color: Color(0xFFF1F5F9)),
                          fallback: Container(
                            color: const Color(0xFFF1F5F9),
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.broken_image_outlined,
                              size: 16,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 7),
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
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        if (widget.outOfStock) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Sin stock',
                              style: TextStyle(
                                color: Color(0xFFDC2626),
                                fontSize: 8.5,
                                fontWeight: FontWeight.w500,
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
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    widget.money(item.total),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(
                    width: 70,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: 'Editar',
                            iconSize: 16,
                            icon: const Icon(
                              Icons.edit_outlined,
                              color: Color(0xFF334155),
                            ),
                            onPressed: editAction,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFEE2E2)),
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            tooltip: 'Eliminar',
                            iconSize: 16,
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Color(0xFFEF4444),
                            ),
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
