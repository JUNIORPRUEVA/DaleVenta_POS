import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_model.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/money_formatters.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../clientes/cliente_model.dart';
import '../clientes/data/clientes_repository.dart';
import '../service_orders/create_service_order_screen.dart';
import '../service_orders/service_order_models.dart';
import '../ventas/data/ventas_repository.dart';
import 'cotizacion_models.dart';
import 'data/cotizaciones_repository.dart';
import 'utils/cotizacion_pdf_service.dart';

enum _QuotePdfShareAction {
  sharePdf('Compartir PDF', Icons.picture_as_pdf_outlined),
  shareClient('Compartir con cliente', Icons.person_outline),
  save('Guardar en descargas', Icons.download_outlined),
  admin('Enviar admin', Icons.verified_user_outlined);

  const _QuotePdfShareAction(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _HistorialFilterState {
  const _HistorialFilterState({
    this.clientKey,
    this.quoteTag,
    this.fromDate,
    this.toDate,
  });

  const _HistorialFilterState.clear()
    : clientKey = null,
      quoteTag = null,
      fromDate = null,
      toDate = null;

  final String? clientKey;
  final String? quoteTag;
  final DateTime? fromDate;
  final DateTime? toDate;
}

class CotizacionesHistorialScreen extends ConsumerStatefulWidget {
  final String? customerPhone;
  final bool pickForEditor;
  final String? quoteId;

  const CotizacionesHistorialScreen({
    super.key,
    this.customerPhone,
    this.pickForEditor = true,
    this.quoteId,
  });

  @override
  ConsumerState<CotizacionesHistorialScreen> createState() =>
      _CotizacionesHistorialScreenState();
}

class _CotizacionesHistorialScreenState
    extends ConsumerState<CotizacionesHistorialScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  List<CotizacionModel> _items = const [];
  List<ClienteModel> _knownClients = const [];
  Map<String, String> _categoryByProductId = const {};
  Set<String> _ownedClientIds = const {};
  Set<String> _ownedClientPhones = const {};
  bool _autoOpened = false;
  String _searchQuery = '';
  String? _selectedClientKey;
  String? _selectedQuoteTag;
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _ownOnly = false;
  String? _selectedQuotationId;

  String _money(double value) => formatRdCurrencyAccounting(value);

  String _normalizeText(String? value) {
    return (value ?? '').trim().toLowerCase();
  }

  bool _canEditOrDelete(CotizacionModel item) {
    final user = ref.read(authStateProvider).user;
    if (user == null) return false;
    if (user.appRole == AppRole.admin) return true;

    final userId = user.id.trim();
    final createdByUserId = (item.createdByUserId ?? '').trim();
    if (createdByUserId.isNotEmpty && createdByUserId == userId) {
      return true;
    }

    final createdByUserName = _normalizeText(item.createdByUserName);
    if (createdByUserName.isEmpty) return false;

    return createdByUserName == _normalizeText(user.nombreCompleto) ||
        createdByUserName == _normalizeText(user.email);
  }

  Future<void> _editQuotation(CotizacionModel item) async {
    if (!_canEditOrDelete(item)) return;

    if (widget.pickForEditor) {
      Navigator.pop(
        context,
        CotizacionEditorPayload(source: item, duplicate: false),
      );
      return;
    }

    final quotationId = Uri.encodeQueryComponent(item.id);
    await context.push('${Routes.cotizaciones}?quotationId=$quotationId');
  }

  Future<void> _sendToServiceOrder(CotizacionModel item) async {
    final customerId = (item.customerId ?? '').trim();
    if (customerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La cotización no tiene cliente asociado.'),
        ),
      );
      return;
    }

    if (item.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La cotización no tiene productos para crear la orden.',
          ),
        ),
      );
      return;
    }

    final opened = await openCreateServiceOrderAdaptive(
      context,
      args: ServiceOrderCreateArgs(
        initialQuotation: item,
        initialClientId: customerId,
      ),
    );

    if (!mounted || opened != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Orden de servicio creada desde la cotización.'),
      ),
    );
  }

  void _selectQuotation(CotizacionModel item) {
    setState(() => _selectedQuotationId = item.id);
  }

  CotizacionModel? _selectedQuotationFrom(List<CotizacionModel> visibleItems) {
    if (visibleItems.isEmpty) return null;
    final selectedId = (_selectedQuotationId ?? '').trim();
    if (selectedId.isNotEmpty) {
      for (final item in visibleItems) {
        if (item.id == selectedId) return item;
      }
    }
    return visibleItems.first;
  }

  void _openAsSalesTicket(CotizacionModel item) {
    if (widget.pickForEditor && Navigator.of(context).canPop()) {
      Navigator.pop(
        context,
        CotizacionEditorPayload(source: item, duplicate: false),
      );
      return;
    }

    final quotationId = Uri.encodeQueryComponent(item.id);
    context.go('${Routes.cotizaciones}?quotationId=$quotationId');
  }

  void _duplicateQuotation(CotizacionModel item) {
    if (widget.pickForEditor && Navigator.of(context).canPop()) {
      Navigator.pop(
        context,
        CotizacionEditorPayload(source: item, duplicate: true),
      );
      return;
    }

    final quotationId = Uri.encodeQueryComponent(item.id);
    context.go('${Routes.cotizaciones}?quotationId=$quotationId&duplicate=1');
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_handleSearchChanged);
    _loadSupportData();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_handleSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final next = _searchCtrl.text.trim();
    if (next == _searchQuery) return;
    setState(() => _searchQuery = next);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _refreshing = false;
      _error = null;
    });
    final repo = ref.read(cotizacionesRepositoryProvider);
    try {
      final cached = await repo.getCachedList(
        customerPhone: widget.customerPhone,
      );
      if (!mounted) return;
      if (cached.isNotEmpty) {
        setState(() {
          _items = cached;
          _loading = false;
          _refreshing = true;
        });
      }

      final rows = await repo.listAndCache(customerPhone: widget.customerPhone);
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
        _refreshing = false;
      });

      await _maybeAutoOpenQuote();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _refreshing = false;
      });
    }
  }

  Future<void> _loadSupportData() async {
    final user = ref.read(authStateProvider).user;
    if (user == null) return;

    final clientsRepo = ref.read(clientesRepositoryProvider);
    final salesRepo = ref.read(ventasRepositoryProvider);

    try {
      final cachedClients = await clientsRepo.getCachedClients(
        ownerId: user.id,
      );
      final products = await salesRepo.fetchProducts(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _applyKnownClients(cachedClients, userId: user.id);
        _categoryByProductId = {
          for (final product in products)
            if ((product.categoria ?? '').trim().isNotEmpty)
              product.id: product.categoria!.trim(),
        };
      });

      final remoteClients = await clientsRepo.listClients(
        ownerId: user.id,
        pageSize: 300,
        skipLoader: true,
      );
      if (!mounted) return;
      setState(() {
        _applyKnownClients(remoteClients, userId: user.id);
      });
    } catch (_) {
      // Never block the screen if support metadata cannot be hydrated.
    }
  }

  void _applyKnownClients(
    List<ClienteModel> clients, {
    required String userId,
  }) {
    final active = clients
        .where((client) => !client.isDeleted)
        .toList(growable: false);
    _knownClients = active;
    _ownedClientIds = {
      for (final client in active)
        if (client.ownerId.trim() == userId.trim() &&
            client.id.trim().isNotEmpty)
          client.id.trim(),
    };
    _ownedClientPhones = {
      for (final client in active)
        if (client.ownerId.trim() == userId.trim())
          _normalizePhone(client.telefono),
    }..remove('');
  }

  Future<void> _maybeAutoOpenQuote() async {
    if (_autoOpened) return;
    final id = (widget.quoteId ?? '').trim();
    if (id.isEmpty) return;

    _autoOpened = true;

    try {
      CotizacionModel? found;
      for (final item in _items) {
        if (item.id.trim() == id) {
          found = item;
          break;
        }
      }

      final selected =
          found ??
          await ref.read(cotizacionesRepositoryProvider).getCachedById(id) ??
          await ref.read(cotizacionesRepositoryProvider).getByIdAndCache(id);
      if (!mounted) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _viewDetail(selected);
      });
    } catch (_) {
      // Ignore: deep-link should never block screen rendering.
    }
  }

  Future<void> _delete(CotizacionModel item) async {
    if (!_canEditOrDelete(item)) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar cotización'),
        content: Text('¿Eliminar la cotización de ${item.customerName}?'),
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
      ),
    );
    if (ok != true) return;

    try {
      await ref.read(cotizacionesRepositoryProvider).deleteOrQueue(item.id);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Cotización eliminada.')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<CompanySettings> _getCompanySettingsForPdf() async {
    final repository = ref.read(companySettingsRepositoryProvider);
    try {
      return await repository.getSettings();
    } catch (_) {
      final cached = await repository.getCachedSettings();
      return cached ?? CompanySettings.empty();
    }
  }

  String _buildAdminApprovalMessage(CotizacionModel item) {
    final sellerName = (item.createdByUserName ?? '').trim();
    final safeSellerName = sellerName.isEmpty ? 'El vendedor' : sellerName;
    return '$safeSellerName quiere que confirme esta cotización y que esté en orden.';
  }

  Future<void> _sendPdfToAdmin(CotizacionModel item, Uint8List bytes) {
    return ref
        .read(cotizacionesRepositoryProvider)
        .sendWhatsAppQuotation(
          quotationId: item.id,
          destinationType: 'admin',
          pdfBytes: bytes,
          fileName: buildCotizacionPdfFileName(item),
          messageText: _buildAdminApprovalMessage(item),
        );
  }

  Future<void> _sendPdfToClient(CotizacionModel item, Uint8List bytes) {
    return _openClientWhatsAppPdfLink(item, bytes);
  }

  Future<void> _openClientWhatsAppPdfLink(
    CotizacionModel item,
    Uint8List bytes,
  ) async {
    final phone = _normalizeWhatsAppLinkPhone(item.customerPhone);
    if (phone.isEmpty) {
      throw Exception(
        'El cliente no tiene teléfono válido para abrir WhatsApp.',
      );
    }

    final pdfUrl = await ref
        .read(cotizacionesRepositoryProvider)
        .createPdfShareLink(
          quotationId: item.id,
          pdfBytes: bytes,
          fileName: buildCotizacionPdfFileName(item),
        );

    final uri = Uri.https('wa.me', '/$phone', {
      'text': _buildClientWhatsAppLinkMessage(item, pdfUrl),
    });

    if (!mounted) return;
    await safeOpenWhatsApp(
      context,
      uri,
      copiedMessage: 'No se pudo abrir WhatsApp. Enlace de cotización copiado.',
    );
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

  String _buildClientWhatsAppLinkMessage(CotizacionModel item, String pdfUrl) {
    final customerName = item.customerName.trim().isEmpty
        ? 'cliente'
        : item.customerName.trim();
    return 'Hola $customerName, te compartimos tu cotización.\n'
        'Cotización: ${item.id}\n'
        'Total: ${_money(item.total)}\n'
        'PDF: $pdfUrl';
  }

  Future<void> _openPdfPreview(CotizacionModel item) async {
    final company = await _getCompanySettingsForPdf();
    final bytes = await buildCotizacionPdf(cotizacion: item, company: company);
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        var busy = false;
        String? dialogNotification;
        bool dialogNotificationIsError = false;
        final media = MediaQuery.sizeOf(context);
        final compact = media.width < 560;
        return StatefulBuilder(
          builder: (context, setDialogState) {
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

            Future<void> runBusy(Future<void> Function() action) async {
              setDialogState(() => busy = true);
              try {
                await action();
              } on TimeoutException {
                showDialogNotification(
                  'Tiempo de espera agotado. Intenta nuevamente.',
                  isError: true,
                );
              } catch (e) {
                showDialogNotification('$e', isError: true);
              } finally {
                if (context.mounted) {
                  setDialogState(() => busy = false);
                }
              }
            }

            Future<void> downloadPdf() async {
              await runBusy(() async {
                final saved = await saveCotizacionPdfToDownloads(
                  bytes: bytes,
                  cotizacion: item,
                );
                showDialogNotification(
                  saved
                      ? 'Cotización descargada en la carpeta Descargas.'
                      : 'No se pudo descargar la cotización.',
                  isError: !saved,
                );
              });
            }

            Future<void> runShareAction(_QuotePdfShareAction action) async {
              if (!context.mounted) return;
              switch (action) {
                case _QuotePdfShareAction.sharePdf:
                  await shareCotizacionPdf(bytes: bytes, cotizacion: item);
                  break;
                case _QuotePdfShareAction.shareClient:
                  await runBusy(() async {
                    await _sendPdfToClient(
                      item,
                      bytes,
                    ).timeout(const Duration(seconds: 25));
                    showDialogNotification(
                      'WhatsApp abierto con el enlace del PDF.',
                    );
                  });
                  break;
                case _QuotePdfShareAction.save:
                  await downloadPdf();
                  break;
                case _QuotePdfShareAction.admin:
                  await runBusy(() async {
                    await _sendPdfToAdmin(
                      item,
                      bytes,
                    ).timeout(const Duration(seconds: 25));
                    showDialogNotification(
                      'Cotización enviada a administradores correctamente.',
                    );
                  });
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
                      child: Row(
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
                              for (final action in _QuotePdfShareAction.values)
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
                                  if (busy)
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

  String _normalizePhone(String? value) {
    return (value ?? '').replaceAll(RegExp(r'[^0-9]'), '').trim();
  }

  String _clientKey({
    String? customerId,
    String? customerPhone,
    required String customerName,
  }) {
    final id = (customerId ?? '').trim();
    if (id.isNotEmpty) return 'id:$id';
    final phone = _normalizePhone(customerPhone);
    if (phone.isNotEmpty) return 'phone:$phone';
    return 'name:${customerName.trim().toLowerCase()}';
  }

  bool _isOwnClient(CotizacionModel item) {
    final customerId = (item.customerId ?? '').trim();
    if (customerId.isNotEmpty && _ownedClientIds.contains(customerId)) {
      return true;
    }
    final phone = _normalizePhone(item.customerPhone);
    return phone.isNotEmpty && _ownedClientPhones.contains(phone);
  }

  Set<String> _quoteTags(CotizacionModel item) {
    final tags = <String>{};
    for (final line in item.items) {
      final category = _categoryByProductId[line.productId]?.trim();
      if (category != null && category.isNotEmpty) {
        tags.add(category);
      }
    }

    final keywordTag = _inferKeywordTag(
      [
        item.note,
        item.customerName,
        for (final line in item.items) line.nombre,
      ].join(' '),
    );
    if (keywordTag != null) {
      tags.add(keywordTag);
    }

    if (tags.isEmpty) {
      tags.add('General');
    }
    return tags;
  }

  String? _inferKeywordTag(String source) {
    final text = source.toLowerCase();
    const groups = <String, List<String>>{
      'Camaras': ['camara', 'cctv', 'dvr', 'nvr'],
      'Alarmas': ['alarma', 'sensor', 'sirena'],
      'Redes': ['router', 'wifi', 'red', 'switch', 'network'],
      'Control de acceso': ['acceso', 'biometr', 'huella', 'cerradura'],
      'Intercom': ['intercom', 'videoportero', 'portero'],
      'Portones': ['porton', 'motor'],
      'Electricidad': ['inversor', 'bateria', 'panel', 'electr'],
    };

    for (final entry in groups.entries) {
      for (final token in entry.value) {
        if (text.contains(token)) {
          return entry.key;
        }
      }
    }
    return null;
  }

  bool _matchesSearch(CotizacionModel item) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return true;

    final createdDate = DateFormat(
      'dd/MM/yyyy h:mm a',
      'es_DO',
    ).format(item.createdAt);
    final haystack = [
      item.id,
      item.customerName,
      item.customerPhone ?? '',
      item.createdByUserName ?? '',
      item.note,
      createdDate,
      ..._quoteTags(item),
      for (final line in item.items) ...[line.nombre, line.productId],
    ].join(' ').toLowerCase();

    return haystack.contains(query);
  }

  List<_ClientFilterOption> get _clientOptions {
    final options = <String, _ClientFilterOption>{};

    for (final client in _knownClients) {
      final key = _clientKey(
        customerId: client.id,
        customerPhone: client.telefono,
        customerName: client.nombre,
      );
      options[key] = _ClientFilterOption(
        key: key,
        label: client.nombre.trim().isEmpty
            ? 'Cliente sin nombre'
            : client.nombre.trim(),
        subtitle: client.telefono.trim(),
        owned:
            client.ownerId.trim().isNotEmpty &&
            client.ownerId.trim() ==
                ref.read(authStateProvider).user?.id.trim(),
      );
    }

    for (final item in _items) {
      final key = _clientKey(
        customerId: item.customerId,
        customerPhone: item.customerPhone,
        customerName: item.customerName,
      );
      options.putIfAbsent(
        key,
        () => _ClientFilterOption(
          key: key,
          label: item.customerName,
          subtitle: (item.customerPhone ?? '').trim(),
          owned: _isOwnClient(item),
        ),
      );
    }

    final values = options.values.toList(growable: false);
    values.sort((a, b) {
      if (a.owned != b.owned) return a.owned ? -1 : 1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return values;
  }

  List<String> get _availableTags {
    final values = {for (final item in _items) ..._quoteTags(item)}.toList(
      growable: false,
    )..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return values;
  }

  int get _activeFilterCount {
    var count = 0;
    if (_selectedClientKey != null) count++;
    if (_selectedQuoteTag != null) count++;
    if (_fromDate != null || _toDate != null) count++;
    return count;
  }

  List<CotizacionModel> get _visibleItems {
    final filtered = _items
        .where((item) {
          if (!_matchesSearch(item)) return false;
          if (_ownOnly && !_isOwnClient(item)) return false;
          if (_selectedClientKey != null &&
              _clientKey(
                    customerId: item.customerId,
                    customerPhone: item.customerPhone,
                    customerName: item.customerName,
                  ) !=
                  _selectedClientKey) {
            return false;
          }
          if (_selectedQuoteTag != null &&
              !_quoteTags(item).contains(_selectedQuoteTag)) {
            return false;
          }
          if (_fromDate != null) {
            final start = DateTime(
              _fromDate!.year,
              _fromDate!.month,
              _fromDate!.day,
            );
            if (item.createdAt.isBefore(start)) return false;
          }
          if (_toDate != null) {
            final end = DateTime(
              _toDate!.year,
              _toDate!.month,
              _toDate!.day,
              23,
              59,
              59,
              999,
            );
            if (item.createdAt.isAfter(end)) return false;
          }
          return true;
        })
        .toList(growable: false);

    filtered.sort((a, b) {
      final aOwned = _isOwnClient(a);
      final bOwned = _isOwnClient(b);
      if (aOwned != bOwned) return aOwned ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return filtered;
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<_HistorialFilterState>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        var clientKey = _selectedClientKey;
        var quoteTag = _selectedQuoteTag;
        var fromDate = _fromDate;
        var toDate = _toDate;

        Future<DateTime?> pickDate(DateTime? initialDate) async {
          final now = DateTime.now();
          return showDatePicker(
            context: context,
            initialDate: initialDate ?? now,
            firstDate: DateTime(now.year - 5),
            lastDate: DateTime(now.year + 2),
            locale: const Locale('es', 'DO'),
          );
        }

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final compactDecoration = InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            );

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  14,
                  6,
                  14,
                  MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String?>(
                        isExpanded: true,
                        initialValue: clientKey,
                        decoration: compactDecoration.copyWith(
                          hintText: 'Cliente',
                          prefixIcon: const Icon(Icons.person_search_outlined),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text(
                              'Todos los clientes',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          ..._clientOptions.map(
                            (option) => DropdownMenuItem<String?>(
                              value: option.key,
                              child: Text(
                                option.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setSheetState(() => clientKey = value),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String?>(
                        isExpanded: true,
                        initialValue: quoteTag,
                        decoration: compactDecoration.copyWith(
                          hintText: 'Categoria / tipo de servicio',
                          prefixIcon: const Icon(Icons.category_outlined),
                        ),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text(
                              'Todas las categorias',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          ..._availableTags.map(
                            (tag) => DropdownMenuItem<String?>(
                              value: tag,
                              child: Text(
                                tag,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setSheetState(() => quoteTag = value),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await pickDate(fromDate);
                                if (picked == null) return;
                                setSheetState(() {
                                  fromDate = picked;
                                  if (toDate != null &&
                                      toDate!.isBefore(picked)) {
                                    toDate = picked;
                                  }
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                minimumSize: const Size(0, 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                              icon: const Icon(Icons.event_outlined, size: 18),
                              label: Text(
                                fromDate == null
                                    ? 'Desde'
                                    : DateFormat(
                                        'dd/MM/yy',
                                        'es_DO',
                                      ).format(fromDate!),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await pickDate(toDate);
                                if (picked == null) return;
                                setSheetState(() {
                                  toDate = picked;
                                  if (fromDate != null &&
                                      fromDate!.isAfter(picked)) {
                                    fromDate = picked;
                                  }
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                minimumSize: const Size(0, 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                              icon: const Icon(
                                Icons.event_available_outlined,
                                size: 18,
                              ),
                              label: Text(
                                toDate == null
                                    ? 'Hasta'
                                    : DateFormat(
                                        'dd/MM/yy',
                                        'es_DO',
                                      ).format(toDate!),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(
                                context,
                                const _HistorialFilterState.clear(),
                              );
                            },
                            child: const Text('Limpiar filtros'),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(
                                context,
                                _HistorialFilterState(
                                  clientKey: clientKey,
                                  quoteTag: quoteTag,
                                  fromDate: fromDate,
                                  toDate: toDate,
                                ),
                              );
                            },
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('Aplicar'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || result == null) return;
    setState(() {
      _selectedClientKey = result.clientKey;
      _selectedQuoteTag = result.quoteTag;
      _fromDate = result.fromDate;
      _toDate = result.toDate;
    });
  }

  void _clearFilters() {
    setState(() {
      _selectedClientKey = null;
      _selectedQuoteTag = null;
      _fromDate = null;
      _toDate = null;
      _ownOnly = false;
    });
  }

  Future<void> _openSummaryPanel() async {
    final visibleItems = _visibleItems;
    final totalAmount = visibleItems.fold<double>(
      0,
      (sum, item) => sum + item.total,
    );
    final totalLines = visibleItems.fold<int>(
      0,
      (sum, item) => sum + item.items.length,
    );
    final clientsCount = {
      for (final item in visibleItems)
        _clientKey(
          customerId: item.customerId,
          customerPhone: item.customerPhone,
          customerName: item.customerName,
        ),
    }.length;
    final ownClientsCount = visibleItems.where(_isOwnClient).length;

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.dashboard_customize_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Panel rapido',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Cerrar',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _SummaryRow(
                label: 'Cotizaciones visibles',
                value: '${visibleItems.length}',
              ),
              _SummaryRow(label: 'Clientes unicos', value: '$clientsCount'),
              _SummaryRow(label: 'Lineas totales', value: '$totalLines'),
              _SummaryRow(label: 'Total acumulado', value: _money(totalAmount)),
              _SummaryRow(
                label: 'Mi cliente en lista',
                value: '$ownClientsCount',
              ),
              if (_activeFilterCount > 0 || _searchQuery.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Vista con filtros activos',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleBack() async {
    final popped = await Navigator.of(context).maybePop();
    if (!popped && mounted) {
      context.go(Routes.cotizaciones);
    }
  }

  Widget _buildToolbar(BuildContext context, {required bool isMobile}) {
    final theme = Theme.of(context);

    final searchField = TextField(
      controller: _searchCtrl,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: 'Buscar cliente, telefono o fecha',
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                onPressed: () => _searchCtrl.clear(),
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Row(
        children: [
          if (isMobile) ...[
            IconButton(
              tooltip: 'Regresar',
              onPressed: _handleBack,
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(child: searchField),
          const SizedBox(width: 8),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'Filtros',
                onPressed: _openFilters,
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: 0.10,
                  ),
                  foregroundColor: theme.colorScheme.primary,
                ),
                icon: const Icon(Icons.tune_rounded),
              ),
              if (_activeFilterCount > 0)
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$_activeFilterCount',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (!isMobile) ...[
            const SizedBox(width: 6),
            OutlinedButton.icon(
              onPressed: _openSummaryPanel,
              icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
              label: const Text('Panel'),
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
            ),
            if (_activeFilterCount > 0 || _searchQuery.isNotEmpty) ...[
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Limpiar',
                onPressed: () {
                  _searchCtrl.clear();
                  _clearFilters();
                },
                icon: const Icon(Icons.restart_alt_rounded),
              ),
            ],
          ],
        ],
      ),
    );
  }

  void _viewDetail(CotizacionModel item) {
    final canEditOrDelete = _canEditOrDelete(item);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Detalle de cotización'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Cliente: ${item.customerName}'),
                if ((item.customerPhone ?? '').trim().isNotEmpty)
                  Text('Teléfono: ${item.customerPhone}'),
                Text(
                  'Fecha: ${DateFormat('dd/MM/yyyy h:mm a', 'es_DO').format(item.createdAt)}',
                ),
                if ((item.createdByUserName ?? '').trim().isNotEmpty)
                  Text('Creada por: ${item.createdByUserName}'),
                if (item.note.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Nota: ${item.note}'),
                ],
                const Divider(height: 18),
                ...item.items.map(
                  (line) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
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
                Row(
                  children: [
                    const Expanded(child: Text('Subtotal')),
                    Text(_money(item.subtotal)),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'ITBIS ${item.includeItbis ? '(18%)' : '(no aplicado)'}',
                      ),
                    ),
                    Text(_money(item.itbisAmount)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Total',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      _money(item.total),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          if (canEditOrDelete)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _editQuotation(item);
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Editar'),
            ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _openPdfPreview(item);
            },
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Ver PDF'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _buildListContent(
    BuildContext context,
    List<CotizacionModel> visibleItems,
  ) {
    final isMobile = MediaQuery.sizeOf(context).width < 860;
    final phone = (widget.customerPhone ?? '').trim();
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          phone.isEmpty
              ? 'No hay cotizaciones guardadas'
              : 'Este cliente no tiene cotizaciones',
        ),
      );
    }
    if (visibleItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 42,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 10),
              Text(
                'Sin resultados con los filtros activos.',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Limpiar filtros'),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
        itemCount: visibleItems.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final item = visibleItems[index];
          final canEditOrDelete = _canEditOrDelete(item);
          final canDuplicate = true;
          final quoteTag = _quoteTags(item).firstOrNull ?? 'General';
          final isOwnClient = _isOwnClient(item);
          final selected =
              !isMobile &&
              (_selectedQuotationId == item.id ||
                  (_selectedQuotationId == null &&
                      visibleItems.isNotEmpty &&
                      visibleItems.first.id == item.id));
          final dateFmt = DateFormat(
            'dd/MM/yy · h:mm a',
            'es_DO',
          ).format(item.createdAt);
          return _HistorialListCard(
            item: item,
            selected: selected,
            dateFmt: dateFmt,
            quoteTag: quoteTag,
            isOwnClient: isOwnClient,
            money: _money(item.total),
            canEdit: canEditOrDelete,
            canDuplicate: canDuplicate,
            onTap: () => isMobile ? _viewDetail(item) : _selectQuotation(item),
            onView: () => _viewDetail(item),
            onPdf: () => _openPdfPreview(item),
            onSendToServiceOrder: () => _sendToServiceOrder(item),
            onEdit: canEditOrDelete ? () => _editQuotation(item) : null,
            onDuplicate: () => _duplicateQuotation(item),
            onDelete: canEditOrDelete ? () => _delete(item) : null,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final phone = (widget.customerPhone ?? '').trim();
    final visibleItems = _visibleItems;
    final isMobile = MediaQuery.of(context).size.width < 860;

    if (!isMobile) {
      // ── Desktop: AppBar + Row(list | sidebar) ──────────────────────────
      final totalVisible = visibleItems.fold<double>(0, (s, i) => s + i.total);
      final uniqueClients = {
        for (final item in visibleItems)
          _clientKey(
            customerId: item.customerId,
            customerPhone: item.customerPhone,
            customerName: item.customerName,
          ),
      }.length;
      final selectedQuotation = _selectedQuotationFrom(visibleItems);

      return Scaffold(
        appBar: CustomAppBar(
          title: phone.isEmpty
              ? 'Historial cotizaciones'
              : 'Cotizaciones · $phone',
          fallbackRoute: Routes.cotizaciones,
          showLogo: false,
          showDepartmentLabel: false,
        ),
        body: SafeArea(
          bottom: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Left: search bar + list ──────────────────────────────────
              Expanded(
                child: Column(
                  children: [
                    _buildToolbar(context, isMobile: false),
                    if (_refreshing)
                      const LinearProgressIndicator(minHeight: 2),
                    Expanded(child: _buildListContent(context, visibleItems)),
                  ],
                ),
              ),
              // ── Right: fixed sidebar ────────────────────────────────────
              Container(
                width: 1,
                color: Theme.of(
                  context,
                ).colorScheme.outlineVariant.withValues(alpha: 0.40),
              ),
              SizedBox(
                width: MediaQuery.sizeOf(context).width >= 1280 ? 430 : 380,
                child: selectedQuotation == null
                    ? _HistorialDesktopSidebar(
                        totalCount: visibleItems.length,
                        totalAmount: totalVisible,
                        uniqueClients: uniqueClients,
                        ownOnly: _ownOnly,
                        selectedTag: _selectedQuoteTag,
                        availableTags: _availableTags,
                        fromDate: _fromDate,
                        toDate: _toDate,
                        hasActiveFilters:
                            _activeFilterCount > 0 ||
                            _searchQuery.isNotEmpty ||
                            _ownOnly,
                        onToggleOwn: (v) => setState(() {
                          _ownOnly = v;
                          _selectedClientKey = null;
                        }),
                        onSelectTag: (tag) =>
                            setState(() => _selectedQuoteTag = tag),
                        onPickFrom: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _fromDate ?? now,
                            firstDate: DateTime(now.year - 5),
                            lastDate: DateTime(now.year + 2),
                            locale: const Locale('es', 'DO'),
                          );
                          if (picked != null) {
                            setState(() => _fromDate = picked);
                          }
                        },
                        onPickTo: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _toDate ?? now,
                            firstDate: DateTime(now.year - 5),
                            lastDate: DateTime(now.year + 2),
                            locale: const Locale('es', 'DO'),
                          );
                          if (picked != null) setState(() => _toDate = picked);
                        },
                        onClearFilters: _clearFilters,
                      )
                    : _QuotationDetailSidePanel(
                        item: selectedQuotation,
                        money: _money,
                        canEdit: _canEditOrDelete(selectedQuotation),
                        onEdit: () => _editQuotation(selectedQuotation),
                        onDuplicate: () =>
                            _duplicateQuotation(selectedQuotation),
                        onPdf: () => _openPdfPreview(selectedQuotation),
                        onServiceOrder: () =>
                            _sendToServiceOrder(selectedQuotation),
                        onSalesTicket: () =>
                            _openAsSalesTicket(selectedQuotation),
                      ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Mobile ────────────────────────────────────────────────────────────
    return Scaffold(
      body: SafeArea(
        top: true,
        bottom: false,
        child: Column(
          children: [
            _buildToolbar(context, isMobile: true),
            if (_refreshing) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    )
                  : _items.isEmpty
                  ? Center(
                      child: Text(
                        phone.isEmpty
                            ? 'No hay cotizaciones guardadas'
                            : 'Este cliente no tiene cotizaciones',
                      ),
                    )
                  : visibleItems.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 42,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'No encontramos cotizaciones con esos filtros.',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Prueba cambiando la busqueda o quitando algun filtro activo.',
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
                        itemCount: visibleItems.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = visibleItems[index];
                          final canEditOrDelete = _canEditOrDelete(item);
                          final canEdit = canEditOrDelete;
                          final canDuplicate = true;
                          final quoteTag =
                              _quoteTags(item).firstOrNull ?? 'General';
                          final isOwnClient = _isOwnClient(item);
                          final dateFmt = DateFormat(
                            'dd/MM/yy · h:mm a',
                            'es_DO',
                          ).format(item.createdAt);

                          return _HistorialListCard(
                            item: item,
                            selected: false,
                            dateFmt: dateFmt,
                            quoteTag: quoteTag,
                            isOwnClient: isOwnClient,
                            money: _money(item.total),
                            canEdit: canEdit,
                            canDuplicate: canDuplicate,
                            onTap: () => _viewDetail(item),
                            onView: () => _viewDetail(item),
                            onPdf: () => _openPdfPreview(item),
                            onSendToServiceOrder: () =>
                                _sendToServiceOrder(item),
                            onEdit: canEdit ? () => _editQuotation(item) : null,
                            onDuplicate: () => _duplicateQuotation(item),
                            onDelete: canEditOrDelete
                                ? () => _delete(item)
                                : null,
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Desktop quotation detail
// ═══════════════════════════════════════════════════════════════════════════

class _QuotationDetailSidePanel extends StatelessWidget {
  const _QuotationDetailSidePanel({
    required this.item,
    required this.money,
    required this.canEdit,
    required this.onEdit,
    required this.onDuplicate,
    required this.onPdf,
    required this.onServiceOrder,
    required this.onSalesTicket,
  });

  final CotizacionModel item;
  final String Function(double value) money;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onPdf;
  final VoidCallback onServiceOrder;
  final VoidCallback onSalesTicket;

  String _qty(double value) =>
      value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final customerPhone = (item.customerPhone ?? '').trim();
    final createdBy = (item.createdByUserName ?? '').trim();
    final note = item.note.trim();

    return Container(
      color: theme.colorScheme.surface,
      child: SafeArea(
        left: false,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.08),
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.55,
                    ),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.description_outlined, color: primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.customerName.trim().isEmpty
                                  ? 'Cliente sin nombre'
                                  : item.customerName.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              DateFormat(
                                'dd/MM/yyyy · h:mm a',
                                'es_DO',
                              ).format(item.createdAt),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    money(item.total),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${item.items.length} lineas · ITBIS ${item.includeItbis ? 'aplicado' : 'no aplicado'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                children: [
                  _DetailInfoRow(
                    icon: Icons.person_outline,
                    label: 'Cliente',
                    value: item.customerName.trim().isEmpty
                        ? 'Sin nombre'
                        : item.customerName.trim(),
                  ),
                  if (customerPhone.isNotEmpty)
                    _DetailInfoRow(
                      icon: Icons.call_outlined,
                      label: 'Telefono',
                      value: customerPhone,
                    ),
                  if (createdBy.isNotEmpty)
                    _DetailInfoRow(
                      icon: Icons.badge_outlined,
                      label: 'Creada por',
                      value: createdBy,
                    ),
                  if (note.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _DetailNote(note: note),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    'Productos',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final line in item.items)
                    _DetailProductLine(
                      title: line.nombre,
                      subtitle: '${_qty(line.qty)} x ${money(line.unitPrice)}',
                      total: money(line.total),
                    ),
                  const SizedBox(height: 12),
                  _DetailTotalRow(
                    label: 'Subtotal',
                    value: money(item.subtotal),
                  ),
                  _DetailTotalRow(
                    label: item.includeItbis ? 'ITBIS 18%' : 'ITBIS',
                    value: money(item.itbisAmount),
                  ),
                  if (item.globalDiscountAmount > 0)
                    _DetailTotalRow(
                      label: 'Descuento',
                      value: '-${money(item.globalDiscountAmount)}',
                    ),
                  const Divider(height: 20),
                  _DetailTotalRow(
                    label: 'Total',
                    value: money(item.total),
                    strong: true,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                border: Border(
                  top: BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.55,
                    ),
                  ),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onSalesTicket,
                          icon: const Icon(Icons.point_of_sale_outlined),
                          label: const Text('Pasar a ticket'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onDuplicate,
                          icon: const Icon(Icons.content_copy_outlined),
                          label: const Text('Duplicar'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onServiceOrder,
                          icon: const Icon(Icons.assignment_add),
                          label: const Text('Orden'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: 'Ver PDF',
                        onPressed: onPdf,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                      ),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        tooltip: 'Editar',
                        onPressed: canEdit ? onEdit : null,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailInfoRow extends StatelessWidget {
  const _DetailInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
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

class _DetailNote extends StatelessWidget {
  const _DetailNote({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(note, style: theme.textTheme.bodyMedium),
    );
  }
}

class _DetailProductLine extends StatelessWidget {
  const _DetailProductLine({
    required this.title,
    required this.subtitle,
    required this.total,
  });

  final String title;
  final String subtitle;
  final String total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            total,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailTotalRow extends StatelessWidget {
  const _DetailTotalRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

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
                fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: strong ? theme.colorScheme.primary : null,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Desktop sidebar
// ═══════════════════════════════════════════════════════════════════════════

class _HistorialDesktopSidebar extends StatelessWidget {
  const _HistorialDesktopSidebar({
    required this.totalCount,
    required this.totalAmount,
    required this.uniqueClients,
    required this.ownOnly,
    required this.selectedTag,
    required this.availableTags,
    required this.fromDate,
    required this.toDate,
    required this.hasActiveFilters,
    required this.onToggleOwn,
    required this.onSelectTag,
    required this.onPickFrom,
    required this.onPickTo,
    required this.onClearFilters,
  });

  final int totalCount;
  final double totalAmount;
  final int uniqueClients;
  final bool ownOnly;
  final String? selectedTag;
  final List<String> availableTags;
  final DateTime? fromDate;
  final DateTime? toDate;
  final bool hasActiveFilters;
  final ValueChanged<bool> onToggleOwn;
  final ValueChanged<String?> onSelectTag;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onClearFilters;

  String _fmt(double v) => formatRdCurrencyAccounting(v);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
        children: [
          // ── Stats ────────────────────────────────────────────────────────
          _HSidebarSection(
            label: 'Panel',
            icon: Icons.dashboard_customize_outlined,
            child: Column(
              children: [
                _HSidebarStat(
                  icon: Icons.receipt_long_outlined,
                  label: 'Cotizaciones',
                  value: '$totalCount',
                  theme: theme,
                ),
                const SizedBox(height: 8),
                _HSidebarStat(
                  icon: Icons.people_outline,
                  label: 'Clientes únicos',
                  value: '$uniqueClients',
                  theme: theme,
                ),
                const SizedBox(height: 8),
                _HSidebarStat(
                  icon: Icons.payments_outlined,
                  label: 'Total acumulado',
                  value: _fmt(totalAmount),
                  theme: theme,
                  accent: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // ── Owner ─────────────────────────────────────────────────────────
          _HSidebarSection(
            label: 'Clientes',
            icon: Icons.person_pin_outlined,
            child: Row(
              children: [
                Expanded(
                  child: _HOwnerChip(
                    label: 'Todos',
                    selected: !ownOnly,
                    onTap: () => onToggleOwn(false),
                    theme: theme,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _HOwnerChip(
                    label: 'Mis clientes',
                    selected: ownOnly,
                    onTap: () => onToggleOwn(true),
                    theme: theme,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // ── Category tags ─────────────────────────────────────────────────
          if (availableTags.isNotEmpty) ...[
            _HSidebarSection(
              label: 'Categoría',
              icon: Icons.category_outlined,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _HTagChip(
                    label: 'Todas',
                    selected: selectedTag == null,
                    onTap: () => onSelectTag(null),
                    theme: theme,
                  ),
                  ...availableTags.map(
                    (tag) => _HTagChip(
                      label: tag,
                      selected: selectedTag == tag,
                      onTap: () => onSelectTag(selectedTag == tag ? null : tag),
                      theme: theme,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          // ── Date range ────────────────────────────────────────────────────
          _HSidebarSection(
            label: 'Fecha',
            icon: Icons.date_range_outlined,
            child: Column(
              children: [
                _HDateButton(
                  label: 'Desde',
                  date: fromDate,
                  onTap: onPickFrom,
                  theme: theme,
                ),
                const SizedBox(height: 8),
                _HDateButton(
                  label: 'Hasta',
                  date: toDate,
                  onTap: onPickTo,
                  theme: theme,
                ),
              ],
            ),
          ),
          // ── Clear ─────────────────────────────────────────────────────────
          if (hasActiveFilters) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onClearFilters,
              icon: const Icon(Icons.restart_alt_rounded, size: 16),
              label: const Text('Limpiar filtros'),
              style: OutlinedButton.styleFrom(
                foregroundColor: primary,
                side: BorderSide(color: primary.withValues(alpha: 0.40)),
                minimumSize: const Size(double.infinity, 40),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HSidebarSection extends StatelessWidget {
  const _HSidebarSection({
    required this.label,
    required this.icon,
    required this.child,
  });
  final String label;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 5),
            Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _HSidebarStat extends StatelessWidget {
  const _HSidebarStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
    this.accent = false,
  });
  final IconData icon;
  final String label;
  final String value;
  final ThemeData theme;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final color = accent
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accent
              ? theme.colorScheme.primary.withValues(alpha: 0.25)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.50),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color.withValues(alpha: 0.65)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _HOwnerChip extends StatelessWidget {
  const _HOwnerChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _HTagChip extends StatelessWidget {
  const _HTagChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.60)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.50),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _HDateButton extends StatelessWidget {
  const _HDateButton({
    required this.label,
    required this.date,
    required this.onTap,
    required this.theme,
  });
  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final hasDate = date != null;
    final text = hasDate
        ? DateFormat('dd/MM/yyyy', 'es_DO').format(date!)
        : label;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasDate
                ? theme.colorScheme.primary.withValues(alpha: 0.45)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.50),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.event_outlined,
              size: 14,
              color: hasDate
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: hasDate ? FontWeight.w700 : FontWeight.w500,
                  color: hasDate
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// List card (shared by mobile and desktop list)
// ═══════════════════════════════════════════════════════════════════════════

class _HistorialListCard extends StatefulWidget {
  const _HistorialListCard({
    required this.item,
    required this.selected,
    required this.dateFmt,
    required this.quoteTag,
    required this.isOwnClient,
    required this.money,
    required this.canEdit,
    required this.canDuplicate,
    required this.onTap,
    required this.onView,
    required this.onPdf,
    required this.onSendToServiceOrder,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
  });

  final CotizacionModel item;
  final bool selected;
  final String dateFmt;
  final String quoteTag;
  final bool isOwnClient;
  final String money;
  final bool canEdit;
  final bool canDuplicate;
  final VoidCallback onTap;
  final VoidCallback onView;
  final VoidCallback onPdf;
  final VoidCallback onSendToServiceOrder;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;

  @override
  State<_HistorialListCard> createState() => _HistorialListCardState();
}

class _HistorialListCardState extends State<_HistorialListCard> {
  bool _active = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final clientName = item.customerName.trim().isEmpty
        ? 'Cliente sin nombre'
        : item.customerName.trim();
    final secondary = [
      widget.dateFmt,
      '${item.items.length} líneas',
      widget.quoteTag,
      if ((item.customerPhone ?? '').trim().isNotEmpty)
        item.customerPhone!.trim(),
      if (widget.isOwnClient) 'Mi cliente',
    ].join(' · ');
    final activeColor = widget.selected
        ? theme.colorScheme.primary.withValues(alpha: 0.10)
        : theme.colorScheme.surfaceContainerHigh;
    final activeBorder = theme.colorScheme.outlineVariant.withValues(
      alpha: 0.45,
    );
    final idleBorder = theme.colorScheme.outlineVariant.withValues(alpha: 0.45);
    final iconBg = _active
        ? theme.colorScheme.primary.withValues(alpha: 0.18)
        : theme.colorScheme.primary.withValues(alpha: 0.10);

    return Material(
      color: Colors.transparent,
      child: MouseRegion(
        onEnter: (_) => setState(() => _active = true),
        onExit: (_) => setState(() => _active = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          decoration: const BoxDecoration(),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: widget.onTap,
            onFocusChange: (focused) => setState(() => _active = focused),
            child: Ink(
              decoration: BoxDecoration(
                color: _active || widget.selected
                    ? activeColor
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: widget.selected
                      ? theme.colorScheme.primary.withValues(alpha: 0.55)
                      : _active
                      ? activeBorder
                      : idleBorder,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: iconBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.description_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  clientName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                widget.money,
                                maxLines: 1,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            secondary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Acciones',
                      onSelected: (value) {
                        if (value == 'view') widget.onView();
                        if (value == 'pdf') widget.onPdf();
                        if (value == 'service_order') {
                          widget.onSendToServiceOrder();
                        }
                        if (value == 'edit') widget.onEdit?.call();
                        if (value == 'duplicate') widget.onDuplicate?.call();
                        if (value == 'delete') widget.onDelete?.call();
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'view',
                          child: Text('Ver detalle'),
                        ),
                        const PopupMenuItem(
                          value: 'pdf',
                          child: Text('Ver PDF'),
                        ),
                        const PopupMenuItem(
                          value: 'service_order',
                          child: Text('Pasar a orden de servicio'),
                        ),
                        if (widget.canEdit)
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Editar'),
                          ),
                        if (widget.canDuplicate)
                          const PopupMenuItem(
                            value: 'duplicate',
                            child: Text('Duplicar'),
                          ),
                        if (widget.onDelete != null)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Eliminar'),
                          ),
                      ],
                      icon: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.more_horiz_rounded, size: 16),
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

class _ClientFilterOption {
  const _ClientFilterOption({
    required this.key,
    required this.label,
    required this.subtitle,
    required this.owned,
  });

  final String key;
  final String label;
  final String subtitle;
  final bool owned;
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
