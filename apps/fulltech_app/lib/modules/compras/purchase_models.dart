import '../../core/models/product_model.dart';

double _num(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? 0}'.replaceAll(',', '.')) ?? 0;
}

String? _str(dynamic value) {
  final text = '${value ?? ''}'.trim();
  return text.isEmpty || text == 'null' ? null : text;
}

DateTime? _date(dynamic value) {
  final text = _str(value);
  return text == null ? null : DateTime.tryParse(text);
}

class SupplierModel {
  const SupplierModel({
    required this.id,
    required this.commercialName,
    this.legalName,
    this.taxId,
    this.contactName,
    this.phone,
    this.whatsapp,
    this.email,
    this.address,
    this.city,
    this.country,
    this.website,
    this.paymentTerms,
    this.estimatedDeliveryDays,
    this.notes,
    this.logo,
    this.isActive = true,
    this.ordersCount = 0,
    this.totalPurchased = 0,
  });

  final String id;
  final String commercialName;
  final String? legalName;
  final String? taxId;
  final String? contactName;
  final String? phone;
  final String? whatsapp;
  final String? email;
  final String? address;
  final String? city;
  final String? country;
  final String? website;
  final String? paymentTerms;
  final int? estimatedDeliveryDays;
  final String? notes;
  final String? logo;
  final bool isActive;
  final int ordersCount;
  final double totalPurchased;

  factory SupplierModel.fromJson(Map<String, dynamic> json) => SupplierModel(
    id: _str(json['id']) ?? '',
    commercialName:
        _str(json['commercialName'] ?? json['commercial_name']) ?? '',
    legalName: _str(json['legalName'] ?? json['legal_name']),
    taxId: _str(json['taxId'] ?? json['tax_id']),
    contactName: _str(json['contactName'] ?? json['contact_name']),
    phone: _str(json['phone']),
    whatsapp: _str(json['whatsapp']),
    email: _str(json['email']),
    address: _str(json['address']),
    city: _str(json['city']),
    country: _str(json['country']),
    website: _str(json['website']),
    paymentTerms: _str(json['paymentTerms'] ?? json['payment_terms']),
    estimatedDeliveryDays:
        (json['estimatedDeliveryDays'] ?? json['estimated_delivery_days'])
            as int?,
    notes: _str(json['notes']),
    logo: _str(json['logo']),
    isActive: json['isActive'] is bool ? json['isActive'] as bool : true,
    ordersCount: (json['ordersCount'] as num?)?.toInt() ?? 0,
    totalPurchased: _num(json['totalPurchased']),
  );

  String? _clean(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  Map<String, dynamic> toPayload() => {
    'commercialName': commercialName.trim(),
    'legalName': _clean(legalName),
    'taxId': _clean(taxId),
    'contactName': _clean(contactName),
    'phone': _clean(phone),
    'whatsapp': _clean(whatsapp),
    'email': _clean(email),
    'address': _clean(address),
    'city': _clean(city),
    'country': _clean(country),
    'website': _clean(website),
    'paymentTerms': _clean(paymentTerms),
    'estimatedDeliveryDays': estimatedDeliveryDays,
    'notes': _clean(notes),
    'logo': _clean(logo),
    'isActive': isActive,
  }..removeWhere((_, value) => value == null);
}

class PurchaseDraftItem {
  const PurchaseDraftItem({
    this.product,
    this.productId,
    required this.productName,
    this.productCode,
    this.description,
    this.image,
    required this.quantity,
    required this.unitCost,
    this.supplierId,
    this.notes,
    this.createInventoryProductOnReceipt = false,
  });

  final ProductModel? product;
  final String? productId;
  final String productName;
  final String? productCode;
  final String? description;
  final String? image;
  final double quantity;
  final double unitCost;
  final String? supplierId;
  final String? notes;
  final bool createInventoryProductOnReceipt;

  double get subtotal => quantity * unitCost;

  PurchaseDraftItem copyWith({
    double? quantity,
    double? unitCost,
    String? supplierId,
    String? notes,
    bool? createInventoryProductOnReceipt,
  }) => PurchaseDraftItem(
    product: product,
    productId: productId,
    productName: productName,
    productCode: productCode,
    description: description,
    image: image,
    quantity: quantity ?? this.quantity,
    unitCost: unitCost ?? this.unitCost,
    supplierId: supplierId ?? this.supplierId,
    notes: notes ?? this.notes,
    createInventoryProductOnReceipt:
        createInventoryProductOnReceipt ?? this.createInventoryProductOnReceipt,
  );

  Map<String, dynamic> toPayload() => {
    'productId': productId,
    'productName': productName,
    'productCode': productCode,
    'description': description,
    'image': image,
    'quantity': quantity,
    'unitCost': unitCost,
    'supplierId': supplierId,
    'notes': notes,
    'createInventoryProductOnReceipt': createInventoryProductOnReceipt,
  }..removeWhere((_, value) => value == null);

  factory PurchaseDraftItem.fromDraftJson(Map<String, dynamic> json) =>
      PurchaseDraftItem(
        productId: _str(json['productId']),
        productName: _str(json['productName']) ?? '',
        productCode: _str(json['productCode']),
        description: _str(json['description']),
        image: _str(json['image']),
        quantity: _num(json['quantity']).clamp(.0001, double.infinity),
        unitCost: _num(json['unitCost']).clamp(0, double.infinity),
        supplierId: _str(json['supplierId']),
        notes: _str(json['notes']),
        createInventoryProductOnReceipt:
            json['createInventoryProductOnReceipt'] is bool
            ? json['createInventoryProductOnReceipt'] as bool
            : false,
      );

  Map<String, dynamic> toDraftJson() => {
    'productId': productId,
    'productName': productName,
    'productCode': productCode,
    'description': description,
    'image': image,
    'quantity': quantity,
    'unitCost': unitCost,
    'supplierId': supplierId,
    'notes': notes,
    'createInventoryProductOnReceipt': createInventoryProductOnReceipt,
  }..removeWhere((_, value) => value == null);
}

class PurchaseOrderItemModel {
  const PurchaseOrderItemModel({
    required this.id,
    required this.productName,
    this.productCode,
    this.image,
    required this.quantity,
    required this.receivedQuantity,
    required this.pendingQuantity,
    required this.unitCost,
    required this.subtotal,
    this.notes,
    this.unitCodeSnapshot = 'UNIT',
    this.unitNameSnapshot = 'Unidad',
    this.unitSymbolSnapshot = 'u',
    this.unitPrecisionSnapshot = 0,
  });

  final String id;
  final String productName;
  final String? productCode;
  final String? image;
  final double quantity;
  final double receivedQuantity;
  final double pendingQuantity;
  final double unitCost;
  final double subtotal;
  final String? notes;
  final String unitCodeSnapshot;
  final String unitNameSnapshot;
  final String unitSymbolSnapshot;
  final int unitPrecisionSnapshot;

  factory PurchaseOrderItemModel.fromJson(
    Map<String, dynamic> json,
  ) => PurchaseOrderItemModel(
    id: _str(json['id']) ?? '',
    productName:
        _str(json['productNameSnapshot'] ?? json['product_name_snapshot']) ??
        '',
    productCode: _str(
      json['productCodeSnapshot'] ?? json['product_code_snapshot'],
    ),
    image: _str(json['imageSnapshot'] ?? json['image_snapshot']),
    quantity: _num(json['quantity']),
    receivedQuantity: _num(
      json['receivedQuantity'] ?? json['received_quantity'],
    ),
    pendingQuantity: _num(json['pendingQuantity'] ?? json['pending_quantity']),
    unitCost: _num(json['unitCost'] ?? json['unit_cost']),
    subtotal: _num(json['subtotal']),
    notes: _str(json['notes']),
    unitCodeSnapshot:
        _str(json['unitCodeSnapshot'] ?? json['unit_code_snapshot']) ?? 'UNIT',
    unitNameSnapshot:
        _str(json['unitNameSnapshot'] ?? json['unit_name_snapshot']) ??
        'Unidad',
    unitSymbolSnapshot:
        _str(json['unitSymbolSnapshot'] ?? json['unit_symbol_snapshot']) ?? 'u',
    unitPrecisionSnapshot: _num(
      json['unitPrecisionSnapshot'] ?? json['unit_precision_snapshot'],
    ).toInt(),
  );

  UnitOfMeasureModel get unitSnapshot => UnitOfMeasureModel(
    id: unitCodeSnapshot,
    code: unitCodeSnapshot,
    name: unitNameSnapshot,
    symbol: unitSymbolSnapshot,
    category: unitCodeSnapshot == 'UNIT' ? 'COUNT' : 'MEASURE',
    allowDecimals: unitPrecisionSnapshot > 0,
    precision: unitPrecisionSnapshot,
  );
}

class PurchaseOrderModel {
  const PurchaseOrderModel({
    required this.id,
    required this.orderNumber,
    this.supplier,
    required this.status,
    this.orderDate,
    this.expectedDeliveryDate,
    required this.subtotal,
    required this.discount,
    required this.shippingCost,
    required this.additionalCost,
    required this.tax,
    required this.total,
    this.notes,
    this.supplierInstructions,
    this.createdByName,
    this.items = const [],
  });

  final String id;
  final String orderNumber;
  final SupplierModel? supplier;
  final String status;
  final DateTime? orderDate;
  final DateTime? expectedDeliveryDate;
  final double subtotal;
  final double discount;
  final double shippingCost;
  final double additionalCost;
  final double tax;
  final double total;
  final String? notes;
  final String? supplierInstructions;
  final String? createdByName;
  final List<PurchaseOrderItemModel> items;

  factory PurchaseOrderModel.fromJson(Map<String, dynamic> json) =>
      PurchaseOrderModel(
        id: _str(json['id']) ?? '',
        orderNumber: _str(json['orderNumber'] ?? json['order_number']) ?? '',
        supplier: json['supplier'] is Map
            ? SupplierModel.fromJson(
                Map<String, dynamic>.from(json['supplier'] as Map),
              )
            : null,
        status: _str(json['status']) ?? 'DRAFT',
        orderDate: _date(json['orderDate'] ?? json['order_date']),
        expectedDeliveryDate: _date(
          json['expectedDeliveryDate'] ?? json['expected_delivery_date'],
        ),
        subtotal: _num(json['subtotal']),
        discount: _num(json['discount']),
        shippingCost: _num(json['shippingCost'] ?? json['shipping_cost']),
        additionalCost: _num(json['additionalCost'] ?? json['additional_cost']),
        tax: _num(json['tax']),
        total: _num(json['total']),
        notes: _str(json['notes']),
        supplierInstructions: _str(
          json['supplierInstructions'] ?? json['supplier_instructions'],
        ),
        createdByName: json['createdBy'] is Map
            ? _str((json['createdBy'] as Map)['nombreCompleto'])
            : null,
        items: ((json['items'] as List?) ?? const [])
            .whereType<Map>()
            .map(
              (row) => PurchaseOrderItemModel.fromJson(
                Map<String, dynamic>.from(row),
              ),
            )
            .toList(),
      );
}

class PurchaseRecommendationModel {
  const PurchaseRecommendationModel({
    required this.product,
    required this.stock,
    required this.minStock,
    required this.alreadyOrdered,
    required this.suggestedQuantity,
    required this.reason,
  });

  final ProductModel product;
  final double stock;
  final double minStock;
  final double alreadyOrdered;
  final double suggestedQuantity;
  final String reason;

  factory PurchaseRecommendationModel.fromJson(Map<String, dynamic> json) =>
      PurchaseRecommendationModel(
        product: ProductModel.fromJson(
          Map<String, dynamic>.from(json['product'] as Map),
        ),
        stock: _num(json['stock']),
        minStock: _num(json['minStock']),
        alreadyOrdered: _num(json['alreadyOrdered']),
        suggestedQuantity: _num(json['suggestedQuantity']),
        reason: _str(json['reason']) ?? 'Compra recomendada',
      );
}

class PurchaseInvoiceOrderSummary {
  const PurchaseInvoiceOrderSummary({
    required this.id,
    required this.orderNumber,
    this.total = 0,
    this.orderDate,
  });

  final String id;
  final String orderNumber;
  final double total;
  final DateTime? orderDate;

  factory PurchaseInvoiceOrderSummary.fromJson(Map<String, dynamic> json) =>
      PurchaseInvoiceOrderSummary(
        id: _str(json['id']) ?? '',
        orderNumber: _str(json['orderNumber'] ?? json['order_number']) ?? '',
        total: _num(json['total']),
        orderDate: _date(json['orderDate'] ?? json['order_date']),
      );
}

class PurchaseInvoiceModel {
  const PurchaseInvoiceModel({
    required this.id,
    required this.supplier,
    this.order,
    this.invoiceNumber,
    this.invoiceDate,
    this.amount,
    this.currency = 'DOP',
    required this.fileName,
    required this.fileUrl,
    required this.mimeType,
    required this.fileSize,
    this.notes,
    this.uploadedByName,
    this.createdAt,
  });

  final String id;
  final SupplierModel supplier;
  final PurchaseInvoiceOrderSummary? order;
  final String? invoiceNumber;
  final DateTime? invoiceDate;
  final double? amount;
  final String currency;
  final String fileName;
  final String fileUrl;
  final String mimeType;
  final int fileSize;
  final String? notes;
  final String? uploadedByName;
  final DateTime? createdAt;

  factory PurchaseInvoiceModel.fromJson(Map<String, dynamic> json) =>
      PurchaseInvoiceModel(
        id: _str(json['id']) ?? '',
        supplier: json['supplier'] is Map
            ? SupplierModel.fromJson(
                Map<String, dynamic>.from(json['supplier'] as Map),
              )
            : SupplierModel(
                id: _str(json['supplierId'] ?? json['supplier_id']) ?? '',
                commercialName: 'Sin suplidor',
              ),
        order: json['purchaseOrder'] is Map
            ? PurchaseInvoiceOrderSummary.fromJson(
                Map<String, dynamic>.from(json['purchaseOrder'] as Map),
              )
            : null,
        invoiceNumber: _str(json['invoiceNumber'] ?? json['invoice_number']),
        invoiceDate: _date(json['invoiceDate'] ?? json['invoice_date']),
        amount: json['amount'] == null ? null : _num(json['amount']),
        currency: _str(json['currency']) ?? 'DOP',
        fileName: _str(json['fileName'] ?? json['file_name']) ?? '',
        fileUrl: _str(json['fileUrl'] ?? json['file_url']) ?? '',
        mimeType: _str(json['mimeType'] ?? json['mime_type']) ?? '',
        fileSize:
            ((json['fileSize'] ?? json['file_size']) as num?)?.toInt() ?? 0,
        notes: _str(json['notes']),
        uploadedByName: json['uploadedBy'] is Map
            ? _str((json['uploadedBy'] as Map)['nombreCompleto'])
            : null,
        createdAt: _date(json['createdAt'] ?? json['created_at']),
      );
}
