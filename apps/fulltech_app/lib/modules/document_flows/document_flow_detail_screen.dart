import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../core/company/company_settings_model.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/errors/api_exception.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/pdf_file_actions.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../clientes/cliente_model.dart';
import '../cotizaciones/cotizacion_models.dart';
import '../cotizaciones/cotizaciones_screen.dart';
import '../cotizaciones/data/cotizaciones_repository.dart';
import 'data/document_flows_repository.dart';
import 'document_flow_models.dart';
import 'utils/document_flow_invoice_pdf_service.dart';
import 'utils/document_flow_warranty_pdf_service.dart';

class DocumentFlowDetailScreen extends ConsumerStatefulWidget {
  const DocumentFlowDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<DocumentFlowDetailScreen> createState() =>
      _DocumentFlowDetailScreenState();
}

class _DocumentFlowDetailScreenState
    extends ConsumerState<DocumentFlowDetailScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _lastSendPreview;
  OrderDocumentFlowModel? _flow;
  final _currencyController = TextEditingController();
  final _taxController = TextEditingController();
  final _notesController = TextEditingController();
  final _warrantyServiceTypeController = TextEditingController();
  final _serviceWarrantyDurationController = TextEditingController();
  final _productWarrantyDurationController = TextEditingController();
  final _coverageController = TextEditingController();
  final _conditionsController = TextEditingController();
  final _exclusionsController = TextEditingController();
  List<_InvoiceItemEditor> _itemEditors = const [];
  List<_WarrantyItemEditor> _warrantyItemEditors = const [];
  String _warrantyTitle = 'CARTA DE GARANTIA';
  bool? _approvalDecision;

  @override
  void initState() {
    super.initState();
    _taxController.addListener(_handleDraftValueChanged);
    _load();
  }

  @override
  void dispose() {
    _currencyController.dispose();
    _taxController.dispose();
    _notesController.dispose();
    _warrantyServiceTypeController.dispose();
    _serviceWarrantyDurationController.dispose();
    _productWarrantyDurationController.dispose();
    _coverageController.dispose();
    _conditionsController.dispose();
    _exclusionsController.dispose();
    _disposeEditors();
    _disposeWarrantyEditors();
    super.dispose();
  }

  void _disposeEditors() {
    _detachEditorListeners(_itemEditors);
    for (final editor in _itemEditors) {
      editor.dispose();
    }
  }

  void _disposeWarrantyEditors() {
    _detachWarrantyEditorListeners(_warrantyItemEditors);
    for (final editor in _warrantyItemEditors) {
      editor.dispose();
    }
  }

  void _handleDraftValueChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _attachEditorListeners(Iterable<_InvoiceItemEditor> editors) {
    for (final editor in editors) {
      editor.addListener(_handleDraftValueChanged);
    }
  }

  void _detachEditorListeners(Iterable<_InvoiceItemEditor> editors) {
    for (final editor in editors) {
      editor.removeListener(_handleDraftValueChanged);
    }
  }

  void _attachWarrantyEditorListeners(Iterable<_WarrantyItemEditor> editors) {
    for (final editor in editors) {
      editor.addListener(_handleDraftValueChanged);
    }
  }

  void _detachWarrantyEditorListeners(Iterable<_WarrantyItemEditor> editors) {
    for (final editor in editors) {
      editor.removeListener(_handleDraftValueChanged);
    }
  }

  List<DocumentFlowInvoiceItem> get _draftItems => _itemEditors
      .map((editor) => editor.toItem())
      .where((item) => item.description.trim().isNotEmpty)
      .toList(growable: false);

  double get _draftSubtotal =>
      _draftItems.fold<double>(0, (sum, item) => sum + item.lineTotal);

  double get _draftTax => double.tryParse(_taxController.text.trim()) ?? 0;

  List<DocumentFlowWarrantyPdfItem> get _draftWarrantyItems =>
      _warrantyItemEditors
          .map((editor) => editor.toPdfItem())
          .where((item) => item.product.trim().isNotEmpty)
          .toList(growable: false);

  void _applyFlow(OrderDocumentFlowModel flow) {
    _disposeEditors();
    _disposeWarrantyEditors();
    _flow = flow;
    _currencyController.text = flow.invoiceDraft.currency;
    _taxController.text = flow.invoiceDraft.tax.toStringAsFixed(2);
    _notesController.text = flow.invoiceDraft.notes;
    final warrantyForm = _WarrantyFormData.fromFlow(flow);
    _warrantyTitle = warrantyForm.title;
    _warrantyServiceTypeController.text = warrantyForm.serviceType;
    _serviceWarrantyDurationController.text =
        warrantyForm.serviceWarrantyDuration;
    _productWarrantyDurationController.text =
        warrantyForm.productWarrantyDuration;
    _coverageController.text = warrantyForm.coverage;
    _conditionsController.text = warrantyForm.conditions;
    _exclusionsController.text = warrantyForm.exclusions;
    _itemEditors = flow.invoiceDraft.items
        .map((item) => _InvoiceItemEditor.fromItem(item))
        .toList(growable: true);
    if (_itemEditors.isEmpty) {
      _itemEditors = <_InvoiceItemEditor>[_InvoiceItemEditor.empty()];
    }
    _warrantyItemEditors = warrantyForm.warrantyItems
        .map((item) => _WarrantyItemEditor.fromValue(item))
        .toList(growable: true);
    if (_warrantyItemEditors.isEmpty) {
      _warrantyItemEditors = _buildDefaultWarrantyEditors(
        flow.invoiceDraft.items,
        warrantyForm.productWarrantyDuration,
      );
    }
    if (_warrantyItemEditors.isEmpty) {
      _warrantyItemEditors = <_WarrantyItemEditor>[_WarrantyItemEditor.empty()];
    }
    _attachEditorListeners(_itemEditors);
    _attachWarrantyEditorListeners(_warrantyItemEditors);
    _approvalDecision = switch (flow.status) {
      DocumentFlowStatus.approved || DocumentFlowStatus.sent => true,
      DocumentFlowStatus.rejected => false,
      _ => null,
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final flow = await ref
          .read(documentFlowsRepositoryProvider)
          .getByOrderId(widget.orderId);
      if (!mounted) return;
      setState(() {
        _applyFlow(flow);
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el detalle documental';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveDraft() async {
    final flow = _flow;
    if (flow == null) return;
    setState(() {
      _saving = true;
    });
    try {
      final invoiceItems = _draftItems;
      final subtotal = _draftSubtotal;
      final tax = _draftTax;
      final warrantyForm = _WarrantyFormData(
        title: _warrantyTitle.trim().isEmpty
            ? 'CARTA DE GARANTIA'
            : _warrantyTitle.trim(),
        serviceType: _warrantyServiceTypeController.text.trim(),
        serviceWarrantyDuration: _serviceWarrantyDurationController.text.trim(),
        productWarrantyDuration: _productWarrantyDurationController.text.trim(),
        coverage: _coverageController.text.trim(),
        conditions: _conditionsController.text.trim(),
        exclusions: _exclusionsController.text.trim(),
        warrantyItems: _warrantyItemEditors
            .map((item) => item.toValue())
            .where((item) => item.product.trim().isNotEmpty)
            .toList(growable: false),
      );
      final updated = await ref
          .read(documentFlowsRepositoryProvider)
          .editDraft(
            id: flow.id,
            invoiceDraftJson: {
              'currency': _currencyController.text.trim().isEmpty
                  ? flow.invoiceDraft.currency
                  : _currencyController.text.trim(),
              'clientName': flow.order.client.nombre,
              'clientPhone': flow.order.client.telefono,
              'items': invoiceItems
                  .map((item) => item.toJson())
                  .toList(growable: false),
              'subtotal': subtotal,
              'tax': tax,
              'total': subtotal + tax,
              'notes': _notesController.text.trim(),
            },
            warrantyDraftJson: {
              'title': warrantyForm.title,
              'summary': warrantyForm.coverage,
              'serviceType': warrantyForm.serviceType.isEmpty
                  ? flow.warrantyDraft.serviceType
                  : warrantyForm.serviceType,
              'category': flow.order.category,
              'clientName': flow.order.client.nombre,
              'terms': warrantyForm.toTerms(),
            },
          );
      if (!mounted) return;
      setState(() {
        _applyFlow(updated);
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Borrador documental guardado')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _generateDocuments() async {
    final flow = _flow;
    if (flow == null) return;
    setState(() {
      _saving = true;
    });
    try {
      final updated = await ref
          .read(documentFlowsRepositoryProvider)
          .generate(flow.id);
      if (!mounted) return;
      setState(() {
        _applyFlow(updated);
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Documentos finales generados')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _generateAndSend() async {
    final flow = _flow;
    if (flow == null) return;
    setState(() {
      _saving = true;
    });
    try {
      final companySettings = ref.read(companySettingsProvider).valueOrNull;
      final serviceType = flow.order.serviceType;

      // Validate document sending rules based on serviceType
      final shouldSendInvoice =
          serviceType == 'instalacion' || serviceType == 'mantenimiento';
      final shouldSendWarranty = serviceType == 'instalacion';

      if (!shouldSendInvoice && !shouldSendWarranty) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Este tipo de servicio no requiere envío de documentos (factura y/o carta de garantía).',
            ),
          ),
        );
        return;
      }

      final orderId = flow.order.id.substring(0, 8);
      String? invoicePdfBase64;
      String? warrantyPdfBase64;
      final List<String> sentDocuments = [];

      // Generate and encode invoice if applicable
      if (shouldSendInvoice) {
        final invoiceBytes = await _buildInvoicePdfBytes(flow, companySettings);
        invoicePdfBase64 = base64Encode(invoiceBytes);
        sentDocuments.add('factura');
      }

      // Generate and encode warranty if applicable
      if (shouldSendWarranty) {
        final warrantyBytes = await _buildWarrantyPdfBytes(
          flow,
          companySettings,
        );
        warrantyPdfBase64 = base64Encode(warrantyBytes);
        sentDocuments.add('carta de garantía');
      }

      final result = await ref
          .read(documentFlowsRepositoryProvider)
          .send(
            flow.id,
            invoicePdfBase64: invoicePdfBase64,
            warrantyPdfBase64: warrantyPdfBase64,
            invoiceFileName: shouldSendInvoice
                ? 'factura-final-$orderId.pdf'
                : null,
            warrantyFileName: shouldSendWarranty
                ? 'warranty-final-$orderId.pdf'
                : null,
          );
      if (!mounted) return;
      setState(() {
        _applyFlow(result.flow);
        _lastSendPreview = result.messageText;
      });
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            '${sentDocuments.join(' y ')} enviadas por WhatsApp a ${result.toNumber}',
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _openPdfPreview(String title, String rawUrl) async {
    setState(() {
      _saving = true;
    });

    try {
      final bytes = await ref
          .read(documentFlowsRepositoryProvider)
          .downloadPdfBytes(rawUrl);
      if (!mounted) return;
      await _showPdfDialog(title, bytes);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<Uint8List> _buildInvoicePdfBytes(
    OrderDocumentFlowModel flow,
    CompanySettings? companySettings,
  ) {
    final subtotal = _draftSubtotal;
    final tax = _taxController.text.trim().isEmpty
        ? flow.invoiceDraft.tax
        : _draftTax;
    final total = subtotal + tax;
    final currency = _currencyController.text.trim().isEmpty
        ? flow.invoiceDraft.currency
        : _currencyController.text.trim();

    return buildDocumentFlowInvoicePdf(
      flow: flow,
      company: companySettings,
      currency: currency,
      items: _draftItems,
      tax: tax,
      subtotal: subtotal,
      total: total,
      notes: _notesController.text.trim(),
    );
  }

  Future<void> _openGeneratedInvoicePreview(
    OrderDocumentFlowModel flow,
    CompanySettings? companySettings,
  ) async {
    setState(() {
      _saving = true;
    });

    try {
      final bytes = await _buildInvoicePdfBytes(flow, companySettings);
      if (!mounted) return;
      await _showPdfDialog('Factura final', bytes);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _showPdfDialog(String title, Uint8List bytes) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final media = MediaQuery.sizeOf(dialogContext);
        final isCompact = media.width < 520;
        return Dialog(
          insetPadding: EdgeInsets.all(isCompact ? 8 : 16),
          child: SizedBox(
            width: isCompact ? media.width - 16 : 920,
            height: isCompact ? media.height * 0.92 : 760,
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(isCompact ? 10 : 14, 10, 8, 6),
                  child: Row(
                    children: [
                      const Icon(Icons.picture_as_pdf_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: isCompact ? 14 : 16,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close),
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
                    allowSharing: true,
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

  Future<void> _openPdfExternally(String rawUrl) async {
    final resolvedUrl = ref
        .read(documentFlowsRepositoryProvider)
        .resolveDocumentUrl(rawUrl);
    final uri = Uri.tryParse(resolvedUrl);
    if (uri == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('No se pudo resolver la URL del PDF')),
      );
      return;
    }
    await safeOpenUrl(
      context,
      uri,
      copiedMessage: 'No se pudo abrir el PDF. Link copiado',
    );
  }

  Future<void> _downloadPdf(String title, String rawUrl) async {
    setState(() {
      _saving = true;
    });

    try {
      final bytes = await ref
          .read(documentFlowsRepositoryProvider)
          .downloadPdfBytes(rawUrl);
      if (!mounted) return;
      final orderId = _flow?.order.id.substring(0, 8) ?? 'documento';
      final saved = await savePdfBytes(
        bytes: bytes,
        fileName: '${_slugify(title)}_$orderId.pdf',
      );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(saved ? 'PDF descargado' : 'Descarga cancelada'),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _downloadGeneratedInvoicePdf(
    OrderDocumentFlowModel flow,
    CompanySettings? companySettings,
  ) async {
    setState(() {
      _saving = true;
    });

    try {
      final bytes = await _buildInvoicePdfBytes(flow, companySettings);
      if (!mounted) return;
      final orderId = _flow?.order.id.substring(0, 8) ?? 'factura';
      final saved = await savePdfBytes(
        bytes: bytes,
        fileName: 'factura_final_$orderId.pdf',
      );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(saved ? 'PDF descargado' : 'Descarga cancelada'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _editLinkedQuotation() async {
    final flow = _flow;
    if (flow == null) return;
    final quotationId = (flow.order.quotationId ?? '').trim();
    if (quotationId.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Esta orden no tiene una cotización vinculada'),
        ),
      );
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final repository = ref.read(cotizacionesRepositoryProvider);
      final quotation = await repository.getByIdAndCache(quotationId);
      if (!mounted) return;
      final client = ClienteModel(
        id: flow.order.client.id,
        ownerId: '',
        nombre: flow.order.client.nombre,
        telefono: flow.order.client.telefono,
        direccion: flow.order.client.direccion,
      );
      final updatedQuotation = await Navigator.of(context)
          .push<CotizacionModel>(
            MaterialPageRoute(
              fullscreenDialog: true,
              builder: (_) => CotizacionesScreen(
                initialClient: client,
                initialQuotation: quotation,
                returnSavedQuotation: true,
              ),
            ),
          );
      if (!mounted || updatedQuotation == null) return;
      setState(() {
        _applyQuotationToInvoice(updatedQuotation);
      });
      await _saveDraft();
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Cotización actualizada y factura sincronizada'),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _deleteFlow() async {
    final flow = _flow;
    if (flow == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar flujo documental'),
        content: Text(
          'Se eliminará el flujo documental de la orden ${flow.order.id.substring(0, 8)} y sus PDFs generados. Esta acción no elimina la orden ni la cotización. ¿Deseas continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      await ref.read(documentFlowsRepositoryProvider).deleteFlow(flow.id);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Flujo documental eliminado')),
      );
      context.go(Routes.documentFlows);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _applyQuotationToInvoice(CotizacionModel quotation) {
    _disposeEditors();
    _itemEditors = quotation.items
        .map(
          (item) => _InvoiceItemEditor(
            descriptionController: TextEditingController(text: item.nombre),
            qtyController: TextEditingController(
              text: item.qty.toStringAsFixed(2),
            ),
            unitPriceController: TextEditingController(
              text: item.unitPrice.toStringAsFixed(2),
            ),
          ),
        )
        .toList(growable: true);
    if (_itemEditors.isEmpty) {
      _itemEditors = <_InvoiceItemEditor>[_InvoiceItemEditor.empty()];
    }
    _attachEditorListeners(_itemEditors);
    _taxController.text = quotation.itbisAmount.toStringAsFixed(2);
    _notesController.text = quotation.note;
    final productDuration =
        _productWarrantyDurationController.text.trim().isEmpty
        ? '6 meses'
        : _productWarrantyDurationController.text.trim();
    _disposeWarrantyEditors();
    _warrantyItemEditors = _buildDefaultWarrantyEditors(
      _draftItems,
      productDuration,
    );
    if (_warrantyItemEditors.isEmpty) {
      _warrantyItemEditors = <_WarrantyItemEditor>[_WarrantyItemEditor.empty()];
    }
    _attachWarrantyEditorListeners(_warrantyItemEditors);
  }

  String _slugify(String value) {
    final normalized = value.trim().toLowerCase();
    final collapsed = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return collapsed.replaceAll(RegExp(r'^_+|_+$'), '');
  }

  Future<Uint8List> _buildWarrantyPdfBytes(
    OrderDocumentFlowModel flow,
    CompanySettings? companySettings,
  ) {
    final warrantyForm = _WarrantyFormData(
      title: _warrantyTitle.trim().isEmpty
          ? 'CARTA DE GARANTIA'
          : _warrantyTitle.trim(),
      serviceType: _warrantyServiceTypeController.text.trim().isEmpty
          ? flow.order.serviceType
          : _warrantyServiceTypeController.text.trim(),
      serviceWarrantyDuration:
          _serviceWarrantyDurationController.text.trim().isEmpty
          ? '3 meses'
          : _serviceWarrantyDurationController.text.trim(),
      productWarrantyDuration:
          _productWarrantyDurationController.text.trim().isEmpty
          ? '6 meses'
          : _productWarrantyDurationController.text.trim(),
      coverage: _coverageController.text.trim(),
      conditions: _conditionsController.text.trim(),
      exclusions: _exclusionsController.text.trim(),
      warrantyItems: _warrantyItemEditors
          .map((item) => item.toValue())
          .where((item) => item.product.trim().isNotEmpty)
          .toList(growable: false),
    );

    return buildDocumentFlowWarrantyPdf(
      flow: flow,
      company: companySettings,
      title: warrantyForm.title,
      serviceType: warrantyForm.serviceType,
      serviceWarrantyDuration: warrantyForm.serviceWarrantyDuration,
      productWarrantyDuration: warrantyForm.productWarrantyDuration,
      coverage: warrantyForm.coverage,
      policyLines: warrantyForm.policyLines,
      items: _draftWarrantyItems,
    );
  }

  Future<void> _openGeneratedWarrantyPreview(
    OrderDocumentFlowModel flow,
    CompanySettings? companySettings,
  ) async {
    setState(() {
      _saving = true;
    });

    try {
      final bytes = await _buildWarrantyPdfBytes(flow, companySettings);
      if (!mounted) return;
      await _showPdfDialog('Carta de garantía', bytes);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _downloadGeneratedWarrantyPdf(
    OrderDocumentFlowModel flow,
    CompanySettings? companySettings,
  ) async {
    setState(() {
      _saving = true;
    });

    try {
      final bytes = await _buildWarrantyPdfBytes(flow, companySettings);
      if (!mounted) return;
      final orderId = _flow?.order.id.substring(0, 8) ?? 'garantia';
      final saved = await savePdfBytes(
        bytes: bytes,
        fileName: 'carta_garantia_$orderId.pdf',
      );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(saved ? 'PDF descargado' : 'Descarga cancelada'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final flow = _flow;
    double baseTax = 0;
    var baseCurrency = 'RD\$';
    if (flow != null) {
      baseTax = flow.invoiceDraft.tax;
      baseCurrency = flow.invoiceDraft.currency;
    }
    final subtotal = _draftSubtotal;
    final tax = _taxController.text.trim().isEmpty ? baseTax : _draftTax;
    final total = subtotal + tax;
    final currency = _currencyController.text.trim().isEmpty
        ? baseCurrency
        : _currencyController.text.trim();
    final companySettings = ref.watch(companySettingsProvider).valueOrNull;
    void handleBackTap() {
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
        return;
      }
      context.go(Routes.documentFlows);
    }

    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
          )
        : flow == null
        ? const Center(child: Text('No hay datos del flujo documental'))
        : Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 124),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SummaryCard(flow: flow),
                    const SizedBox(height: 12),
                    _buildManagementCard(flow),
                    const SizedBox(height: 12),
                    _buildApprovalCard(flow),
                    const SizedBox(height: 12),
                    _buildInvoiceCard(flow, companySettings),
                    const SizedBox(height: 12),
                    _buildWarrantyCard(flow, companySettings),
                    if (_lastSendPreview != null &&
                        _lastSendPreview!.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _SectionCard(
                        icon: Icons.message_outlined,
                        title: 'Mensaje enviado',
                        subtitle: 'Vista previa del texto enviado por WhatsApp',
                        child: SelectableText(_lastSendPreview!),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );

    return Scaffold(
      body: Stack(
        children: [
          body,
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.topLeft,
                child: Material(
                  color: Colors.white.withValues(alpha: 0.62),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0xFFCAD5E2).withValues(alpha: 0.72),
                      ),
                    ),
                    child: InkWell(
                      onTap: handleBackTap,
                      borderRadius: BorderRadius.circular(16),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.arrow_back_rounded,
                              size: 20,
                              color: Color(0xE024303F),
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Ir atrás',
                              style: TextStyle(
                                fontSize: 12.8,
                                fontWeight: FontWeight.w700,
                                color: Color(0xE024303F),
                              ),
                            ),
                          ],
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
      bottomNavigationBar: flow == null || _loading || _error != null
          ? null
          : _BottomActionBar(
              saving: _saving,
              currency: currency,
              subtotal: subtotal,
              tax: tax,
              total: total,
              onSaveDraft: _saveDraft,
              onGenerateDocuments: _generateDocuments,
              onGenerateAndSend: _generateAndSend,
            ),
    );
  }

  Widget _buildApprovalCard(OrderDocumentFlowModel flow) {
    return _SectionCard(
      icon: Icons.fact_check_outlined,
      title: 'Aprobación',
      subtitle: 'Validación interna del flujo documental',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Estado actual: ${flow.status.label}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Aprobar'),
                selected: _approvalDecision == true,
                onSelected: (_) {
                  setState(() {
                    _approvalDecision = true;
                  });
                },
              ),
              ChoiceChip(
                label: const Text('No aprobar'),
                selected: _approvalDecision == false,
                onSelected: (_) {
                  setState(() {
                    _approvalDecision = false;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildManagementCard(OrderDocumentFlowModel flow) {
    return _SectionCard(
      icon: Icons.settings_outlined,
      title: 'Gestión del flujo',
      subtitle:
          'Acciones administrativas sobre el flujo documental y su cotización vinculada',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final children = [
            OutlinedButton.icon(
              onPressed: _saving ? null : _editLinkedQuotation,
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('Editar cotización vinculada'),
            ),
            OutlinedButton.icon(
              onPressed: _saving ? null : _deleteFlow,
              icon: const Icon(Icons.delete_outline),
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              label: const Text('Eliminar flujo documental'),
            ),
          ];

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  children[index],
                  if (index != children.length - 1) const SizedBox(height: 8),
                ],
              ],
            );
          }

          return Wrap(spacing: 8, runSpacing: 8, children: children);
        },
      ),
    );
  }

  Widget _buildInvoiceCard(
    OrderDocumentFlowModel flow,
    CompanySettings? companySettings,
  ) {
    final subtotal = _draftSubtotal;
    final tax = _taxController.text.trim().isEmpty
        ? flow.invoiceDraft.tax
        : _draftTax;
    final total = subtotal + tax;
    final scheme = Theme.of(context).colorScheme;
    final invoiceUrl = flow.invoiceFinalUrl?.trim() ?? '';

    return _SectionCard(
      icon: Icons.receipt_long_outlined,
      title: 'Factura',
      subtitle: 'Datos comerciales y líneas facturables',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InvoicePreviewHeader(
            companySettings: companySettings,
            flow: flow,
            currency: _currencyController.text.trim().isEmpty
                ? flow.invoiceDraft.currency
                : _currencyController.text.trim(),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              if (compact) {
                return Column(
                  children: [
                    TextField(
                      controller: _currencyController,
                      decoration: _compactFieldDecoration(label: 'Moneda'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _taxController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _compactFieldDecoration(label: 'Impuesto'),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _editLinkedQuotation,
                        icon: const Icon(Icons.edit_note_outlined),
                        label: const Text('Editar cotización vinculada'),
                      ),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _currencyController,
                      decoration: _compactFieldDecoration(label: 'Moneda'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _taxController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _compactFieldDecoration(label: 'Impuesto'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _editLinkedQuotation,
                    icon: const Icon(Icons.edit_note_outlined),
                    label: const Text('Editar cotización'),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: const [
                Expanded(flex: 5, child: Text('Descripción')),
                SizedBox(
                  width: 72,
                  child: Text('Cant.', textAlign: TextAlign.center),
                ),
                SizedBox(
                  width: 92,
                  child: Text('Precio', textAlign: TextAlign.center),
                ),
                SizedBox(
                  width: 108,
                  child: Text('Importe', textAlign: TextAlign.center),
                ),
                SizedBox(width: 36),
              ],
            ),
          ),
          const SizedBox(height: 6),
          ..._itemEditors.asMap().entries.map((entry) {
            final index = entry.key;
            final editor = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _InvoiceItemEditorCard(
                editor: editor,
                canRemove: _itemEditors.length > 1,
                onRemove: () {
                  setState(() {
                    final removed = _itemEditors.removeAt(index);
                    removed.removeListener(_handleDraftValueChanged);
                    removed.dispose();
                  });
                },
              ),
            );
          }),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  final newEditor = _InvoiceItemEditor.empty();
                  newEditor.addListener(_handleDraftValueChanged);
                  _itemEditors = List<_InvoiceItemEditor>.from(_itemEditors)
                    ..add(newEditor);
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('Agregar línea'),
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: _compactFieldDecoration(
              label: 'Notas',
              hintText: 'Observaciones internas o detalles para la factura',
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: scheme.surfaceContainerLow,
            ),
            child: Text(
              'Resumen actual: subtotal ${subtotal.toStringAsFixed(2)} • impuesto ${tax.toStringAsFixed(2)} • total ${total.toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          _buildGeneratedFileRow(
            label: 'PDF de factura',
            rawUrl: invoiceUrl,
            previewTitle: 'Factura final',
            onPreview: () =>
                _openGeneratedInvoicePreview(flow, companySettings),
            onDownload: () =>
                _downloadGeneratedInvoicePdf(flow, companySettings),
          ),
        ],
      ),
    );
  }

  Widget _buildWarrantyCard(
    OrderDocumentFlowModel flow,
    CompanySettings? companySettings,
  ) {
    final policyLines = _buildWarrantyPolicyLines(
      _conditionsController.text,
      _exclusionsController.text,
    );
    final warrantyUrl = flow.warrantyFinalUrl?.trim() ?? '';

    return _SectionCard(
      icon: Icons.verified_user_outlined,
      title: 'Carta de garantía',
      subtitle: 'Cobertura, tiempos y productos incluidos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _warrantyServiceTypeController,
                  decoration: _compactFieldDecoration(label: 'Servicio'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _serviceWarrantyDurationController,
                  decoration: _compactFieldDecoration(
                    label: 'Tiempo servicio',
                    hintText: '3 meses',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _productWarrantyDurationController,
                  decoration: _compactFieldDecoration(
                    label: 'Tiempo productos',
                    hintText: '6 meses',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InputDecorator(
                  decoration: _compactFieldDecoration(label: 'Categoría'),
                  child: Text(flow.order.category),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Productos y tiempo de garantía',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          ..._warrantyItemEditors.asMap().entries.map((entry) {
            final index = entry.key;
            final editor = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _WarrantyItemEditorCard(
                editor: editor,
                canRemove: _warrantyItemEditors.length > 1,
                onRemove: () {
                  setState(() {
                    final removed = _warrantyItemEditors.removeAt(index);
                    removed.removeListener(_handleDraftValueChanged);
                    removed.dispose();
                  });
                },
              ),
            );
          }),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  final duration =
                      _productWarrantyDurationController.text.trim().isEmpty
                      ? '6 meses'
                      : _productWarrantyDurationController.text.trim();
                  final newEditor = _WarrantyItemEditor.empty(
                    duration: duration,
                  );
                  newEditor.addListener(_handleDraftValueChanged);
                  _warrantyItemEditors = List<_WarrantyItemEditor>.from(
                    _warrantyItemEditors,
                  )..add(newEditor);
                });
              },
              icon: const Icon(Icons.add),
              label: const Text('Agregar producto en garantía'),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cobertura y condiciones',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(_coverageController.text.trim()),
                const SizedBox(height: 8),
                ...policyLines.map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('• '),
                        Expanded(child: Text(line)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildGeneratedFileRow(
            label: 'PDF de carta de garantía',
            rawUrl: warrantyUrl,
            previewTitle: 'Carta de garantía',
            onPreview: () =>
                _openGeneratedWarrantyPreview(flow, companySettings),
            onDownload: () =>
                _downloadGeneratedWarrantyPdf(flow, companySettings),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratedFileRow({
    required String label,
    required String rawUrl,
    required String previewTitle,
    VoidCallback? onPreview,
    VoidCallback? onDownload,
  }) {
    final hasUrl = rawUrl.isNotEmpty;
    final canUseLocalPdf = onPreview != null && onDownload != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        if (!hasUrl && !canUseLocalPdf)
          const Text('Pendiente')
        else ...[
          if (hasUrl) ...[SelectableText(rawUrl), const SizedBox(height: 8)],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _saving
                    ? null
                    : (onPreview ??
                          () => _openPdfPreview(previewTitle, rawUrl)),
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Ver PDF'),
              ),
              if (hasUrl)
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _openPdfExternally(rawUrl),
                  icon: const Icon(Icons.open_in_new_outlined),
                  label: const Text('Abrir'),
                ),
              OutlinedButton.icon(
                onPressed: _saving
                    ? null
                    : (onDownload ?? () => _downloadPdf(previewTitle, rawUrl)),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Descargar'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.flow});

  final OrderDocumentFlowModel flow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _SectionCard(
      icon: Icons.description_outlined,
      title: 'Resumen general',
      subtitle: 'Datos principales del cliente y de la orden',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                flow.order.client.nombre,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              _StatusChip(status: flow.status),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SummaryInfoTag(
                icon: Icons.tag_outlined,
                label: 'Orden',
                value: flow.order.id,
                color: scheme.surfaceContainerHighest,
              ),
              if ((flow.order.quotationId ?? '').trim().isNotEmpty)
                _SummaryInfoTag(
                  icon: Icons.request_quote_outlined,
                  label: 'Cotización',
                  value: flow.order.quotationId!,
                  color: scheme.surfaceContainerHighest,
                ),
              _SummaryInfoTag(
                icon: Icons.build_circle_outlined,
                label: 'Estado técnico',
                value: flow.order.status,
                color: scheme.surfaceContainerHighest,
              ),
              _SummaryInfoTag(
                icon: Icons.handyman_outlined,
                label: 'Servicio',
                value: flow.order.serviceType,
                color: scheme.surfaceContainerHighest,
              ),
              _SummaryInfoTag(
                icon: Icons.category_outlined,
                label: 'Categoría',
                value: flow.order.category,
                color: scheme.surfaceContainerHighest,
              ),
              _SummaryInfoTag(
                icon: Icons.phone_outlined,
                label: 'Teléfono',
                value: flow.order.client.telefono,
                color: scheme.surfaceContainerHighest,
              ),
            ],
          ),
          if ((flow.order.client.direccion ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Dirección', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              flow.order.client.direccion!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _InvoicePreviewHeader extends StatelessWidget {
  const _InvoicePreviewHeader({
    required this.companySettings,
    required this.flow,
    required this.currency,
  });

  final CompanySettings? companySettings;
  final OrderDocumentFlowModel flow;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final company = companySettings ?? CompanySettings.empty();
    final invoiceNumber =
        'FACT-${flow.order.id.replaceAll('-', '').substring(0, 8).toUpperCase()}';
    final dateText = _formatDate(
      flow.order.finalizedAt ?? flow.order.updatedAt ?? flow.order.createdAt,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
        color: scheme.surface,
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CompanyLogo(companySettings: company),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      company.companyName.trim().isEmpty
                          ? 'FULLTECH'
                          : company.companyName.trim(),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (company.rnc.trim().isNotEmpty)
                      Text('RNC: ${company.rnc.trim()}'),
                    if (company.phone.trim().isNotEmpty)
                      Text('Tel: ${company.phone.trim()}'),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Referencia de factura',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text('Factura No.: $invoiceNumber'),
                    Text('Fecha: $dateText'),
                    Text('Moneda: $currency'),
                    Text(
                      'Cotización: ${(flow.order.quotationId ?? '').trim().isEmpty ? 'No vinculada' : flow.order.quotationId!.substring(0, flow.order.quotationId!.length >= 8 ? 8 : flow.order.quotationId!.length).toUpperCase()}',
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

  String _formatDate(DateTime? value) {
    if (value == null) return 'No disponible';
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    return '$day/$month/$year';
  }
}

class _CompanyLogo extends StatelessWidget {
  const _CompanyLogo({required this.companySettings});

  final CompanySettings companySettings;

  @override
  Widget build(BuildContext context) {
    final logo = companySettings.logoBase64?.trim() ?? '';
    final bytes = _decodeLogo(logo);
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes != null
          ? Image.memory(bytes, fit: BoxFit.contain)
          : Center(
              child: Text(
                _companyInitial(companySettings.companyName),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
    );
  }

  String _companyInitial(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return 'F';
    return normalized.substring(0, 1).toUpperCase();
  }

  Uint8List? _decodeLogo(String raw) {
    if (raw.isEmpty) return null;
    final normalized = raw.contains(',') ? raw.split(',').last : raw;
    try {
      return Uint8List.fromList(base64Decode(normalized));
    } catch (_) {
      return null;
    }
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final DocumentFlowStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (status) {
      DocumentFlowStatus.pendingPreparation => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
      DocumentFlowStatus.readyForReview => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      DocumentFlowStatus.readyForFinalization => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      DocumentFlowStatus.approved => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
      ),
      DocumentFlowStatus.rejected => (
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      DocumentFlowStatus.sent => (scheme.primary, scheme.onPrimary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text('$label: $value', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.saving,
    required this.currency,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.onSaveDraft,
    required this.onGenerateDocuments,
    required this.onGenerateAndSend,
  });

  final bool saving;
  final String currency;
  final double subtotal;
  final double tax;
  final double total;
  final VoidCallback onSaveDraft;
  final VoidCallback onGenerateDocuments;
  final VoidCallback onGenerateAndSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 980;
            final actions = Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                FilledButton.icon(
                  onPressed: saving ? null : onSaveDraft,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Guardar'),
                ),
                OutlinedButton.icon(
                  onPressed: saving ? null : onGenerateDocuments,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Generar'),
                ),
                FilledButton.tonalIcon(
                  onPressed: saving ? null : onGenerateAndSend,
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Enviar'),
                ),
              ],
            );
            final totalsPanel = _FooterTotalsPanel(
              currency: currency,
              subtotal: subtotal,
              tax: tax,
              total: total,
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  totalsPanel,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: totalsPanel),
                const SizedBox(width: 10),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _InvoiceItemEditorCard extends StatelessWidget {
  const _InvoiceItemEditorCard({
    required this.editor,
    required this.canRemove,
    required this.onRemove,
  });

  final _InvoiceItemEditor editor;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final subtotal = editor.toItem().lineTotal;
    final outline = Theme.of(context).colorScheme.outlineVariant;
    final descriptionDecoration = _compactFieldDecoration(label: 'Descripción');
    final qtyDecoration = _compactFieldDecoration(label: 'Cant.');
    final priceDecoration = _compactFieldDecoration(label: 'Precio');
    final amountDecoration = _compactFieldDecoration(label: 'Importe');

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        if (compact) {
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: outline),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                TextField(
                  controller: editor.descriptionController,
                  decoration: descriptionDecoration,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: editor.qtyController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textAlign: TextAlign.center,
                        decoration: qtyDecoration,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: editor.unitPriceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textAlign: TextAlign.right,
                        decoration: priceDecoration,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: InputDecorator(
                        decoration: amountDecoration,
                        child: Text(
                          subtotal.toStringAsFixed(2),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: canRemove ? onRemove : null,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: outline),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: TextField(
                  controller: editor.descriptionController,
                  decoration: descriptionDecoration,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 68,
                child: TextField(
                  controller: editor.qtyController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.center,
                  decoration: qtyDecoration,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 88,
                child: TextField(
                  controller: editor.unitPriceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.right,
                  decoration: priceDecoration,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 98,
                child: InputDecorator(
                  decoration: amountDecoration,
                  child: Text(
                    subtotal.toStringAsFixed(2),
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: canRemove ? onRemove : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WarrantyFormData {
  const _WarrantyFormData({
    required this.title,
    required this.serviceType,
    required this.serviceWarrantyDuration,
    required this.productWarrantyDuration,
    required this.coverage,
    required this.conditions,
    required this.exclusions,
    required this.warrantyItems,
  });

  final String title;
  final String serviceType;
  final String serviceWarrantyDuration;
  final String productWarrantyDuration;
  final String coverage;
  final String conditions;
  final String exclusions;
  final List<_WarrantyItemValue> warrantyItems;

  factory _WarrantyFormData.fromFlow(OrderDocumentFlowModel flow) {
    final draft = flow.warrantyDraft;
    String serviceWarrantyDuration = '3 meses';
    String productWarrantyDuration = '6 meses';
    String coverage = draft.summary.trim().isEmpty
        ? _defaultWarrantyCoverage(flow.order.serviceType, flow.order.category)
        : draft.summary.trim();
    final warrantyItems = <_WarrantyItemValue>[];
    final extraConditions = <String>[];
    final extraExclusions = <String>[];

    for (final term in draft.terms) {
      final value = term.trim();
      if (value.isEmpty) continue;
      if (value.toLowerCase().startsWith(
            'garantía del servicio:'.toLowerCase(),
          ) ||
          value.toLowerCase().startsWith('garantia del servicio:')) {
        serviceWarrantyDuration = value.split(':').skip(1).join(':').trim();
        continue;
      }
      if (value.toLowerCase().startsWith(
            'garantía de productos instalados:'.toLowerCase(),
          ) ||
          value.toLowerCase().startsWith('garantia de productos instalados:')) {
        productWarrantyDuration = value.split(':').skip(1).join(':').trim();
        continue;
      }
      if (value.toLowerCase().startsWith('condiciones:')) {
        extraConditions.add(value.split(':').skip(1).join(':').trim());
        continue;
      }
      if (value.toLowerCase().startsWith('exclusiones:')) {
        extraExclusions.add(value.split(':').skip(1).join(':').trim());
        continue;
      }
      final parsedItem = _WarrantyItemValue.tryParse(value);
      if (parsedItem != null) {
        warrantyItems.add(parsedItem);
        continue;
      }
      extraConditions.add(value);
    }

    final mergedConditions = extraConditions
        .where((item) => item.isNotEmpty)
        .join('\n');
    final mergedExclusions = extraExclusions
        .where((item) => item.isNotEmpty)
        .join('\n');

    return _WarrantyFormData(
      title: draft.title.trim().isEmpty
          ? 'CARTA DE GARANTIA'
          : draft.title.trim(),
      serviceType: draft.serviceType.trim().isEmpty
          ? flow.order.serviceType
          : draft.serviceType.trim(),
      serviceWarrantyDuration: serviceWarrantyDuration.isEmpty
          ? '3 meses'
          : serviceWarrantyDuration,
      productWarrantyDuration: productWarrantyDuration.isEmpty
          ? '6 meses'
          : productWarrantyDuration,
      coverage: coverage,
      conditions: mergedConditions.isEmpty
          ? _defaultWarrantyConditionsText()
          : mergedConditions,
      exclusions: mergedExclusions.isEmpty
          ? _defaultWarrantyExclusionsText()
          : mergedExclusions,
      warrantyItems: warrantyItems.isNotEmpty
          ? warrantyItems
          : flow.invoiceDraft.items
                .where((item) => item.description.trim().isNotEmpty)
                .map(
                  (item) => _WarrantyItemValue(
                    product: item.description.trim(),
                    duration: productWarrantyDuration.isEmpty
                        ? '6 meses'
                        : productWarrantyDuration,
                  ),
                )
                .toList(growable: false),
    );
  }

  List<String> toTerms() {
    return [
      if (serviceWarrantyDuration.trim().isNotEmpty)
        'Garantía del servicio: ${serviceWarrantyDuration.trim()}',
      if (productWarrantyDuration.trim().isNotEmpty)
        'Garantía de productos instalados: ${productWarrantyDuration.trim()}',
      ...conditions
          .split('\n')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .map((item) => 'Condiciones: $item'),
      ...exclusions
          .split('\n')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .map((item) => 'Exclusiones: $item'),
      ...warrantyItems
          .where((item) => item.product.trim().isNotEmpty)
          .map((item) => item.toTerm()),
    ];
  }

  List<String> get policyLines =>
      _buildWarrantyPolicyLines(conditions, exclusions);
}

List<String> _buildWarrantyPolicyLines(String conditions, String exclusions) {
  return [
    ...conditions
        .split('\n')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty),
    ...exclusions
        .split('\n')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .map((item) => 'No cubre: $item'),
  ];
}

String _defaultWarrantyCoverage(String serviceType, String category) {
  final cleanService = serviceType.trim().isEmpty
      ? 'servicio realizado'
      : serviceType.trim();
  final cleanCategory = category.trim().isEmpty
      ? 'categoría correspondiente'
      : category.trim();
  return 'Garantia correspondiente al servicio de $cleanService en la categoria $cleanCategory. El alcance exacto se detalla en la tabla inferior, donde se especifica cada producto o servicio cubierto y el tiempo de garantia aplicable.';
}

String _defaultWarrantyConditionsText() {
  return [
    'La garantia aplica exclusivamente a fallas atribuibles al servicio realizado por FULLTECH o a defectos de instalacion verificados por nuestro personal tecnico autorizado.',
    'Los siguientes productos tienen la garantia indicada en esta carta y solo dichos elementos quedan cubiertos dentro del plazo expresamente establecido.',
    'Para validar la garantia el cliente debe presentar esta carta junto con la factura, cotizacion aprobada u otro comprobante comercial vinculado a la orden intervenida.',
    'La empresa debe poder inspeccionar el equipo, instalacion o area de trabajo antes de autorizar reparacion, sustitucion o ajuste bajo garantia.',
    'La cobertura solo procede despues de una evaluacion tecnica que determine que la incidencia reportada corresponde a una falla cubierta y no a una causal de exclusion.',
    'Cuando la garantia sea procedente, la empresa podra corregir la falla mediante reparacion, ajuste, reemplazo parcial o solucion tecnica equivalente segun el caso.',
  ].join('\n');
}

String _defaultWarrantyExclusionsText() {
  return [
    'Danos por alto voltaje, bajo voltaje, picos electricos, descargas atmosfericas, cortocircuitos, apagones o inestabilidad del suministro electrico.',
    'Danos por golpes, maltrato, caidas, arrastre, vibraciones excesivas, humedad, inundacion, incendio, corrosion, salitre, suciedad extrema o exposicion ambiental inadecuada.',
    'Averias provocadas por uso indebido, uso distinto al recomendado, negligencia, descuido, sobrecarga, falta de mantenimiento o manipulacion incorrecta.',
    'Intervenciones, aperturas, reparaciones, modificaciones, instalaciones adicionales o diagnosticos realizados por terceros no autorizados por FULLTECH.',
    'Danos ocasionados por conexiones defectuosas del cliente, instalaciones electricas deficientes, ausencia de proteccion electrica o condiciones estructurales fuera del alcance contratado.',
    'Consumibles, accesorios, configuraciones adicionales, actualizaciones, ampliaciones o trabajos no incluidos de manera expresa en la orden original.',
    'Desgaste normal por uso, deterioro estetico, perdida de rendimiento por antiguedad del equipo o fallas preexistentes no detectables al momento del servicio.',
    'Danos derivados de accidente, robo, vandalismo, transporte inadecuado, animales, plagas, caso fortuito, fuerza mayor o hechos imputables al cliente o a terceros.',
  ].join('\n');
}

List<_WarrantyItemEditor> _buildDefaultWarrantyEditors(
  List<DocumentFlowInvoiceItem> items,
  String defaultDuration,
) {
  final duration = defaultDuration.trim().isEmpty
      ? '6 meses'
      : defaultDuration.trim();
  return items
      .where((item) => item.description.trim().isNotEmpty)
      .map(
        (item) => _WarrantyItemEditor(
          productController: TextEditingController(
            text: item.description.trim(),
          ),
          durationController: TextEditingController(text: duration),
        ),
      )
      .toList(growable: true);
}

class _WarrantyItemValue {
  final String product;
  final String duration;

  const _WarrantyItemValue({required this.product, required this.duration});

  String toTerm() =>
      'Producto: ${product.trim()} || Garantia: ${duration.trim()}';

  static _WarrantyItemValue? tryParse(String raw) {
    final normalized = raw.trim();
    if (!normalized.toLowerCase().startsWith('producto:')) {
      return null;
    }
    final parts = normalized.split('||');
    if (parts.isEmpty) return null;
    final product = parts.first.split(':').skip(1).join(':').trim();
    var duration = '';
    if (parts.length > 1) {
      duration = parts[1].split(':').skip(1).join(':').trim();
    }
    return _WarrantyItemValue(product: product, duration: duration);
  }
}

class _WarrantyItemEditor {
  _WarrantyItemEditor({
    required this.productController,
    required this.durationController,
  });

  factory _WarrantyItemEditor.fromValue(_WarrantyItemValue value) {
    return _WarrantyItemEditor(
      productController: TextEditingController(text: value.product),
      durationController: TextEditingController(text: value.duration),
    );
  }

  factory _WarrantyItemEditor.empty({String duration = '6 meses'}) {
    return _WarrantyItemEditor(
      productController: TextEditingController(),
      durationController: TextEditingController(text: duration),
    );
  }

  final TextEditingController productController;
  final TextEditingController durationController;

  _WarrantyItemValue toValue() {
    return _WarrantyItemValue(
      product: productController.text.trim(),
      duration: durationController.text.trim(),
    );
  }

  DocumentFlowWarrantyPdfItem toPdfItem() {
    return DocumentFlowWarrantyPdfItem(
      product: productController.text.trim(),
      duration: durationController.text.trim(),
    );
  }

  void dispose() {
    productController.dispose();
    durationController.dispose();
  }

  void addListener(VoidCallback listener) {
    productController.addListener(listener);
    durationController.addListener(listener);
  }

  void removeListener(VoidCallback listener) {
    productController.removeListener(listener);
    durationController.removeListener(listener);
  }
}

class _WarrantyItemEditorCard extends StatelessWidget {
  const _WarrantyItemEditorCard({
    required this.editor,
    required this.canRemove,
    required this.onRemove,
  });

  final _WarrantyItemEditor editor;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outlineVariant;
    final productDecoration = _compactFieldDecoration(
      label: 'Producto o elemento garantizado',
    );
    final durationDecoration = _compactFieldDecoration(
      label: 'Tiempo de garantía',
      hintText: '6 meses',
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        if (compact) {
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: outline),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                TextField(
                  controller: editor.productController,
                  decoration: productDecoration,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: editor.durationController,
                        decoration: durationDecoration,
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: canRemove ? onRemove : null,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: outline),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: TextField(
                  controller: editor.productController,
                  decoration: productDecoration,
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 132,
                child: TextField(
                  controller: editor.durationController,
                  decoration: durationDecoration,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: canRemove ? onRemove : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InvoiceItemEditor {
  _InvoiceItemEditor({
    required this.descriptionController,
    required this.qtyController,
    required this.unitPriceController,
  });

  factory _InvoiceItemEditor.fromItem(DocumentFlowInvoiceItem item) {
    return _InvoiceItemEditor(
      descriptionController: TextEditingController(text: item.description),
      qtyController: TextEditingController(text: item.qty.toStringAsFixed(2)),
      unitPriceController: TextEditingController(
        text: item.unitPrice.toStringAsFixed(2),
      ),
    );
  }

  factory _InvoiceItemEditor.empty() {
    return _InvoiceItemEditor(
      descriptionController: TextEditingController(),
      qtyController: TextEditingController(text: '1'),
      unitPriceController: TextEditingController(text: '0'),
    );
  }

  final TextEditingController descriptionController;
  final TextEditingController qtyController;
  final TextEditingController unitPriceController;

  DocumentFlowInvoiceItem toItem() {
    final qty = double.tryParse(qtyController.text.trim()) ?? 0;
    final unitPrice = double.tryParse(unitPriceController.text.trim()) ?? 0;
    return DocumentFlowInvoiceItem(
      description: descriptionController.text.trim(),
      qty: qty,
      unitPrice: unitPrice,
      lineTotal: qty * unitPrice,
    );
  }

  void dispose() {
    descriptionController.dispose();
    qtyController.dispose();
    unitPriceController.dispose();
  }

  void addListener(VoidCallback listener) {
    descriptionController.addListener(listener);
    qtyController.addListener(listener);
    unitPriceController.addListener(listener);
  }

  void removeListener(VoidCallback listener) {
    descriptionController.removeListener(listener);
    qtyController.removeListener(listener);
    unitPriceController.removeListener(listener);
  }
}

class _SummaryInfoTag extends StatelessWidget {
  const _SummaryInfoTag({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 5),
          Text('$label: $value', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _FooterTotalsPanel extends StatelessWidget {
  const _FooterTotalsPanel({
    required this.currency,
    required this.subtotal,
    required this.tax,
    required this.total,
  });

  final String currency;
  final double subtotal;
  final double tax;
  final double total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          _InfoChip(
            icon: Icons.summarize_outlined,
            label: 'Subtotal',
            value: '$currency ${subtotal.toStringAsFixed(2)}',
          ),
          _InfoChip(
            icon: Icons.receipt_outlined,
            label: 'Impuesto',
            value: '$currency ${tax.toStringAsFixed(2)}',
          ),
          _InfoChip(
            icon: Icons.payments_outlined,
            label: 'Total',
            value: '$currency ${total.toStringAsFixed(2)}',
          ),
        ],
      ),
    );
  }
}

InputDecoration _compactFieldDecoration({
  required String label,
  String? hintText,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hintText,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  );
}
