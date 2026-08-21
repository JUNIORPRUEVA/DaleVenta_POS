import 'package:flutter/material.dart';

import '../sales_models.dart';

enum RecentSalesStatus { loading, success, error }

/// Panel "Ventas recientes" usado por Facturación.
///
/// Máquina de estados explícita para que el loading NUNCA quede pegado:
/// - siempre termina en success/error (el future de `loadSales` siempre
///   resuelve porque el repositorio aísla fallos de red, caché y mapeo);
/// - `_generation` descarta respuestas viejas (race / cambio de empresa);
/// - `mounted` evita setState tras cerrar el panel;
/// - el botón de refrescar ignora taps mientras ya hay un request en vuelo.
class RecentSalesPanel extends StatefulWidget {
  const RecentSalesPanel({
    super.key,
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
  State<RecentSalesPanel> createState() => _RecentSalesPanelState();
}

class _RecentSalesPanelState extends State<RecentSalesPanel> {
  RecentSalesStatus _status = RecentSalesStatus.loading;
  List<SaleModel> _sales = const <SaleModel>[];
  int _generation = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load(notify: false);
  }

  Future<void> _load({bool notify = true}) async {
    final generation = ++_generation;
    void applyLoading() {
      _status = RecentSalesStatus.loading;
      _loading = true;
    }

    if (notify) {
      setState(applyLoading);
    } else {
      applyLoading();
    }

    try {
      final result = await widget.loadSales();
      if (!mounted || generation != _generation) return; // stale response
      setState(() {
        _sales = result;
        _status = RecentSalesStatus.success;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _status = RecentSalesStatus.error;
        _loading = false;
      });
    }
  }

  void _reload() {
    // Evita lanzar requests idénticos mientras ya hay uno en vuelo.
    if (_loading) return;
    _load();
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
              Expanded(child: _buildBody(scheme)),
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

  Widget _buildBody(ColorScheme scheme) {
    switch (_status) {
      case RecentSalesStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case RecentSalesStatus.error:
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
      case RecentSalesStatus.success:
        final sales = _sales.take(12).toList(growable: false);
        if (sales.isEmpty) {
          return const Center(
            child: Text('No hay ventas recientes'),
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
                  );
                },
              ),
            ),
          ],
        );
    }
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
  });

  final SaleModel sale;
  final String Function(double value) money;
  final String Function(DateTime? date) dateLabel;
  final String Function(SaleModel sale) shortId;
  final ValueChanged<SaleModel> onViewSale;
  final ValueChanged<SaleModel> onOpenPdf;
  final ValueChanged<SaleModel> onReprintTicket;

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
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                ),
                IconButton(
                  tooltip: 'Ver PDF',
                  onPressed: () => onOpenPdf(sale),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  color: const Color(0xFFE11D48),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
                  ),
                ),
                IconButton(
                  tooltip: 'Reimprimir ticket',
                  onPressed: () => onReprintTicket(sale),
                  icon: const Icon(Icons.print_outlined, size: 18),
                  color: const Color(0xFF1957E6),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 40,
                    height: 40,
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
