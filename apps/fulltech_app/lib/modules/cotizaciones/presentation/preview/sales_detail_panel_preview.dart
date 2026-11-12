import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/company/company_settings_model.dart';
import '../../../../core/company/company_settings_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/branded_menu_button.dart';
import '../../cotizacion_models.dart';
import '../../../clientes/cliente_model.dart';
import '../../../clientes/cliente_form_screen.dart';
import '../../../clientes/application/clientes_controller.dart';
import '../../cotizaciones_screen.dart';
import '../widgets/sales_detail_header.dart';
import '../widgets/sales_auxiliary_dock.dart';
import '../widgets/sales_catalog_command_bar.dart';
import '../../../../core/models/product_model.dart';
import '../../../../core/ai_assistant/presentation/widgets/ai_assistant_dock_button.dart';
import '../widgets/sales_ticket_bar.dart';

/// Escenario aislado: usa el panel real con fixtures, sin guardar operaciones.
void main() => runApp(
  ProviderScope(
    overrides: [
      companySettingsProvider.overrideWith(
        (ref) async => CompanySettings.empty(),
      ),
      clientesControllerProvider.overrideWith(
        (ref) => SalesPreviewClientsController(ref),
      ),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const SalesDetailPanelPreview(),
    ),
  ),
);

class SalesDetailPanelPreview extends StatefulWidget {
  const SalesDetailPanelPreview({super.key});
  @override
  State<SalesDetailPanelPreview> createState() =>
      _SalesDetailPanelPreviewState();
}

/// Solo fixtures: el formulario real no escribe en red ni en almacenamiento.
class SalesPreviewClientsController extends ClientesController {
  SalesPreviewClientsController(super.ref);

  @override
  Future<void> load({String? search}) async {}
  @override
  Future<void> refresh() async {}
  @override
  Future<ClienteModel> saveCliente({
    required String nombre,
    required String telefono,
    String? direccion,
    String? locationUrl,
    String? correo,
    String? taxId,
    String? businessName,
    String? taxIdType,
    String? id,
  }) async => ClienteModel(
    id: 'preview-new-client',
    ownerId: 'preview',
    nombre: nombre.trim(),
    telefono: telefono.trim(),
    direccion: direccion,
    taxId: taxId,
  );
}

class _SalesDetailPanelPreviewState extends State<SalesDetailPanelPreview> {
  List<CotizacionItem> _items = const [
    CotizacionItem(
      productId: '00000000-0000-4000-8000-000000000001',
      nombre: 'Reloj inteligente',
      imageUrl: '',
      unitPrice: 1000,
      qty: 1,
    ),
  ];
  String _client = 'Sin cliente';
  String _fiscal = 'Factura normal';
  String? _priceList;
  bool _options = true;
  bool _note = false;
  int? _selected;
  String? _auxiliary;
  final _catalogSearch = TextEditingController();
  final _catalogFocus = FocusNode();

  @override
  void dispose() {
    _catalogSearch.dispose();
    _catalogFocus.dispose();
    super.dispose();
  }

  String _money(double value) => NumberFormat.currency(
    locale: 'en_US',
    symbol: r'RD$',
    decimalDigits: 2,
  ).format(value);
  void _notice(String value) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$value · Vista previa sin operaciones reales')),
  );

  void _quantity(int index, double qty) => setState(() {
    if (qty > 0) {
      final updated = _items[index].copyWith(qty: qty);
      _items = List.of(_items)..[index] = updated;
    }
  });

  Future<void> _pickClient() async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Seleccionar cliente'),
        children: [
          for (final name in [
            'Cliente de ejemplo',
            'Distribuidora de productos y servicios del Caribe',
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, name),
              child: Text(name),
            ),
        ],
      ),
    );
    if (mounted && value != null) setState(() => _client = value);
  }

  Future<void> _createClient() async {
    final created = await openClienteFormAdaptive(
      context,
      useRootNavigator: true,
    );
    if (mounted && created != null) setState(() => _client = created.nombre);
  }

  Future<void> _pickFiscal() async {
    final value = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Tipo de factura'),
        children: [
          for (final name in ['Factura normal', 'Fiscal · B01'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, name),
              child: Text(name),
            ),
        ],
      ),
    );
    if (mounted && value != null) setState(() => _fiscal = value);
  }

  @override
  Widget build(BuildContext context) {
    final total = _items.fold<double>(0, (sum, item) => sum + item.total);
    return Scaffold(
      drawer: const Drawer(
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Menú principal'),
          ),
        ),
      ),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 8,
        title: Builder(
          builder: (context) => BrandedMenuButton(
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: const [
          Center(child: Text('Vista previa · Detalle de venta')),
          SizedBox(width: 16),
        ],
      ),
      body: Stack(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 56,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Icon(
                      Icons.point_of_sale_outlined,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Vista previa del panel real',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Todos los datos de esta vista son ejemplos. No se crean ventas ni se consulta la empresa.',
                                ),
                                const SizedBox(height: 20),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton(
                                      onPressed: () =>
                                          setState(() => _items = []),
                                      child: const Text('Venta vacía'),
                                    ),
                                    OutlinedButton(
                                      onPressed: () => setState(
                                        () => _items = const [
                                          CotizacionItem(
                                            productId:
                                                '00000000-0000-4000-8000-000000000001',
                                            nombre:
                                                'Reloj inteligente con pantalla de alta resolución y garantía extendida',
                                            imageUrl: '',
                                            unitPrice: 1000,
                                            originalUnitPrice: 1200,
                                            qty: 2,
                                          ),
                                          CotizacionItem(
                                            productId: 'manual-demo',
                                            nombre:
                                                'Servicio técnico especializado',
                                            imageUrl: '',
                                            unitPrice: 350,
                                            qty: 1,
                                          ),
                                        ],
                                      ),
                                      child: const Text(
                                        'Productos y descuento',
                                      ),
                                    ),
                                    OutlinedButton(
                                      onPressed: () =>
                                          setState(() => _auxiliary = 'manual'),
                                      child: const Text('Venta rápida'),
                                    ),
                                    OutlinedButton(
                                      onPressed: _pickClient,
                                      child: const Text('Elegir cliente'),
                                    ),
                                    OutlinedButton(
                                      onPressed: () =>
                                          setState(() => _options = !_options),
                                      child: const Text('Alternar opciones'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: salesDetailPanelWidth(constraints.maxWidth),
                        child: DesktopSalesDetailPanel(
                          items: _items,
                          selectedCartIndex: _selected,
                          selectedClientName: _client,
                          selectedClientPhone: _client == 'Sin cliente'
                              ? null
                              : '809 555 0100',
                          includeItbis: false,
                          subtotalBeforeDiscount: total,
                          discountAmount: 0,
                          generalDiscountAmount: 0,
                          subtotal: total,
                          itbisAmount: 0,
                          total: total,
                          isAdmin: true,
                          utilityAmount: total * 0.25,
                          money: _money,
                          priceListSelector: _options
                              ? SalesDetailPriceListSelector(
                                  value: _priceList,
                                  options: const [
                                    DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('Precio general'),
                                    ),
                                    DropdownMenuItem<String?>(
                                      value: 'mayoreo',
                                      child: Text('Mayorista'),
                                    ),
                                  ],
                                  busy: false,
                                  onChanged: (value) =>
                                      setState(() => _priceList = value),
                                )
                              : const SizedBox.shrink(),
                          searchClients: (query) async =>
                              const [
                                    ClienteModel(
                                      id: 'demo-1',
                                      ownerId: 'preview',
                                      nombre: 'Cliente de ejemplo',
                                      telefono: '809 555 0100',
                                    ),
                                    ClienteModel(
                                      id: 'demo-2',
                                      ownerId: 'preview',
                                      nombre:
                                          'Distribuidora de productos y servicios del Caribe',
                                      telefono: '809 555 0100',
                                    ),
                                  ]
                                  .where(
                                    (client) =>
                                        '${client.nombre} ${client.telefono}'
                                            .toLowerCase()
                                            .contains(query.toLowerCase()),
                                  )
                                  .toList(),
                          onSelectClient: (client) =>
                              setState(() => _client = client.nombre),
                          onCreateClient: _createClient,
                          onClearClient: () =>
                              setState(() => _client = 'Sin cliente'),
                          onOpenHistory: () => _notice('Ventas'),
                          onQuote: () => _notice('Guardar cotización'),
                          onPdf: () => _notice('Ver PDF'),
                          onOpenFiscalData: _options ? _pickFiscal : null,
                          fiscalLabel: _fiscal,
                          hasNote: _note,
                          onOpenNote: () {
                            setState(() => _note = !_note);
                            _notice('Nota');
                          },
                          onClear: _items.isEmpty
                              ? null
                              : () => setState(() => _items = []),
                          onOpenCalculator: () =>
                              setState(() => _auxiliary = 'calculator'),
                          onFinalize: () => _notice('Cobrar'),
                          onApplyGeneralDiscount: () =>
                              _notice('Descuento general'),
                          onMinusQty: (index) =>
                              _quantity(index, _items[index].qty - 1),
                          onPlusQty: (index) =>
                              _quantity(index, _items[index].qty + 1),
                          onChangePrice: (_, _) {},
                          onEditLine: (_) => _notice('Editar producto'),
                          onEditExternalItem: (_) =>
                              _notice('Editar producto manual'),
                          isOutOfStock: (_) => false,
                          isItemExempt: (_) => false,
                          onRemoveItem: (index) => setState(
                            () => _items = (List.of(_items)..removeAt(index)),
                          ),
                          onSelectItem: (index) =>
                              setState(() => _selected = index),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 56,
            top: 4,
            right: salesDetailPanelWidth(MediaQuery.sizeOf(context).width - 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SalesCatalogCommandBar(
                controller: _catalogSearch,
                focusNode: _catalogFocus,
                inventoryEnabled: true,
                onSearchChanged: () {},
                onSearchSubmitted: () => _notice('Buscar productos'),
                onNewProduct: () => _notice('Nuevo producto'),
                onStock: () => _notice('Agregar stock'),
              ),
            ),
          ),
          if (_auxiliary == null)
            Positioned(
              left: 12,
              bottom: 8,
              child: AiAssistantDockButton(
                onPressed: () => _notice('Asistente IA'),
              ),
            ),
          if (_auxiliary != null)
            Positioned(
              left: 56,
              right: salesDetailPanelWidth(
                MediaQuery.sizeOf(context).width - 56,
              ),
              top: 0,
              bottom: 0,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () => setState(() => _auxiliary = null),
                      child: ColoredBox(
                        color: AppColors.overlay.withValues(alpha: 0.15),
                      ),
                    ),
                  ),
                  SalesAuxiliaryDock(
                    visible: true,
                    width: (_auxiliary == 'manual' ? 420.0 : 330.0).clamp(
                      0.0,
                      MediaQuery.sizeOf(context).width -
                          56 -
                          salesDetailPanelWidth(
                            MediaQuery.sizeOf(context).width - 56,
                          ),
                    ),
                    child: _auxiliary == 'manual'
                        ? DesktopManualItemPanel(
                            item: null,
                            money: _money,
                            parseAmount: double.tryParse,
                            formatAmount: (value) => value.toString(),
                            isAdmin: true,
                            measurementUnitsEnabled: false,
                            unitOptions: const [UnitOfMeasureModel.unit],
                            onCancel: () => setState(() => _auxiliary = null),
                            onSubmit:
                                ({
                                  required name,
                                  required qty,
                                  required unit,
                                  required unitPrice,
                                  required externalCost,
                                }) => _notice('Agregar producto de ejemplo'),
                          )
                        : DesktopCalculatorPane(
                            onClose: () => setState(() => _auxiliary = null),
                          ),
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: SalesTicketBar(
        ticketCount: 1,
        onCreateTicket: () => _notice('Nuevo ticket'),
        ticketBuilder: (_, _) => SalesTicketTab(
          label: 'Ticket 1',
          itemCount: _items.length,
          selected: true,
          onTap: () {},
          onRename: () => _notice('Editar ticket'),
          onDelete: () => _notice('Eliminar ticket'),
        ),
      ),
    );
  }
}
