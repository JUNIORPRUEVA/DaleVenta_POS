import '../../core/models/product_model.dart';

class SalesSummaryModel {
  final int totalSales;
  final double totalSold;
  final double totalCost;
  final double totalProfit;
  final double totalCommission;

  const SalesSummaryModel({
    required this.totalSales,
    required this.totalSold,
    required this.totalCost,
    required this.totalProfit,
    required this.totalCommission,
  });

  factory SalesSummaryModel.empty() => const SalesSummaryModel(
    totalSales: 0,
    totalSold: 0,
    totalCost: 0,
    totalProfit: 0,
    totalCommission: 0,
  );

  factory SalesSummaryModel.fromJson(Map<String, dynamic> json) {
    return SalesSummaryModel(
      totalSales: (json['totalSales'] as num?)?.toInt() ?? 0,
      totalSold: _toDouble(json['totalSold']),
      totalCost: _toDouble(json['totalCost']),
      totalProfit: _toDouble(json['totalProfit']),
      totalCommission: _toDouble(json['totalCommission']),
    );
  }
}

class AdminSalesUserSummary {
  final String userId;
  final String userName;
  final String userEmail;
  final int totalSales;
  final double totalSold;
  final double totalProfit;
  final double totalCommission;

  const AdminSalesUserSummary({
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.totalSales,
    required this.totalSold,
    required this.totalProfit,
    required this.totalCommission,
  });

  String get displayName {
    final normalizedName = userName.trim();
    if (normalizedName.isNotEmpty) return normalizedName;
    final normalizedEmail = userEmail.trim();
    if (normalizedEmail.isNotEmpty) return normalizedEmail;
    return userId;
  }

  factory AdminSalesUserSummary.fromJson(Map<String, dynamic> json) {
    return AdminSalesUserSummary(
      userId: (json['userId'] ?? '').toString(),
      userName: (json['userName'] ?? '').toString(),
      userEmail: (json['userEmail'] ?? '').toString(),
      totalSales: (json['totalSales'] as num?)?.toInt() ?? 0,
      totalSold: _toDouble(json['totalSold']),
      totalProfit: _toDouble(json['totalProfit']),
      totalCommission: _toDouble(json['totalCommission']),
    );
  }
}

class AdminSalesUsersSummary {
  final List<AdminSalesUserSummary> items;
  final SalesSummaryModel totals;
  final double commissionRate;

  const AdminSalesUsersSummary({
    required this.items,
    required this.totals,
    required this.commissionRate,
  });

  factory AdminSalesUsersSummary.empty() => AdminSalesUsersSummary(
    items: const <AdminSalesUserSummary>[],
    totals: SalesSummaryModel.empty(),
    commissionRate: 0,
  );

  factory AdminSalesUsersSummary.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    return AdminSalesUsersSummary(
      items: rawItems
          .whereType<Map>()
          .map(
            (item) =>
                AdminSalesUserSummary.fromJson(item.cast<String, dynamic>()),
          )
          .toList(growable: false),
      totals: SalesSummaryModel.fromJson(
        ((json['totals'] as Map?) ?? const <String, dynamic>{})
            .cast<String, dynamic>(),
      ),
      commissionRate: _toDouble(json['commissionRate']),
    );
  }
}

class SaleItemModel {
  final String id;
  final String? productId;
  final String productNameSnapshot;
  final String? productImageSnapshot;
  final double qty;
  final double priceSoldUnit;
  final double costUnitSnapshot;
  final double subtotalSold;
  final double subtotalCost;
  final double profit;
  final String? category;
  final double grossAmount;
  final double lineDiscountAmount;
  final double taxableBase;
  final double taxRate;
  final double taxAmount;
  final double exemptAmount;
  final bool taxIncluded;
  final bool taxExempt;

  const SaleItemModel({
    required this.id,
    required this.productId,
    required this.productNameSnapshot,
    required this.productImageSnapshot,
    required this.qty,
    required this.priceSoldUnit,
    required this.costUnitSnapshot,
    required this.subtotalSold,
    required this.subtotalCost,
    required this.profit,
    required this.category,
    this.grossAmount = 0,
    this.lineDiscountAmount = 0,
    this.taxableBase = 0,
    this.taxRate = 0,
    this.taxAmount = 0,
    this.exemptAmount = 0,
    this.taxIncluded = false,
    this.taxExempt = true,
  });

  factory SaleItemModel.fromJson(Map<String, dynamic> json) {
    final product = json['product'];
    String? category;
    if (product is Map) {
      category =
          product['categoria']?.toString() ??
          product['categoriaNombre']?.toString() ??
          product['category']?.toString();
    }
    category ??=
        json['categoria']?.toString() ??
        json['categoriaNombre']?.toString() ??
        json['category']?.toString();
    return SaleItemModel(
      id: (json['id'] ?? '').toString(),
      productId: json['productId']?.toString(),
      productNameSnapshot: (json['productNameSnapshot'] ?? '').toString(),
      productImageSnapshot: json['productImageSnapshot']?.toString(),
      qty: _toDouble(json['qty']),
      priceSoldUnit: _toDouble(json['priceSoldUnit']),
      costUnitSnapshot: _toDouble(json['costUnitSnapshot']),
      subtotalSold: _toDouble(json['subtotalSold']),
      subtotalCost: _toDouble(json['subtotalCost']),
      profit: _toDouble(json['profit']),
      category: category?.trim().isEmpty ?? true ? null : category!.trim(),
      grossAmount: _toDouble(json['grossAmount']),
      lineDiscountAmount: _toDouble(json['lineDiscountAmount']),
      taxableBase: _toDouble(json['taxableBase']),
      taxRate: _toDouble(json['taxRate']),
      taxAmount: _toDouble(json['taxAmount']),
      exemptAmount: _toDouble(json['exemptAmount']),
      taxIncluded: json['taxIncluded'] == true,
      taxExempt: json['taxExempt'] != false,
    );
  }

  String get categoryLabel => category ?? 'Sin categoria';
}

class SaleModel {
  final String id;
  final String userId;
  final String? userName;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final DateTime? saleDate;
  final String? note;
  final double totalSold;
  final double totalCost;
  final double totalProfit;
  final double commissionAmount;
  final String paymentMethod;
  final double paymentCashAmount;
  final double paymentTransferAmount;
  final double creditAmount;
  final double creditPaidAmount;
  final double creditBalance;
  final String creditStatus;
  final String kind;
  final bool isDeleted;
  final DateTime? deletedAt;
  final bool fiscalTaxEnabled;
  final String fiscalPriceMode;
  final double taxableBase;
  final double taxAmount;
  final double exemptAmount;
  final double discountAmount;
  final String? fiscalVoucherType;
  final String? ncf;
  final DateTime? ncfExpirationDate;
  final String? issuerNameSnapshot;
  final String? issuerTaxIdSnapshot;
  final String? issuerAddressSnapshot;
  final String? issuerPhoneSnapshot;
  final String? issuerEmailSnapshot;
  final String? fiscalCustomerTaxId;
  final String? fiscalCustomerName;
  final String? customerAddressSnapshot;
  final String? customerPhoneSnapshot;
  final List<SaleItemModel> items;

  const SaleModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.saleDate,
    required this.note,
    required this.totalSold,
    required this.totalCost,
    required this.totalProfit,
    required this.commissionAmount,
    required this.paymentMethod,
    required this.paymentCashAmount,
    required this.paymentTransferAmount,
    required this.creditAmount,
    required this.creditPaidAmount,
    required this.creditBalance,
    required this.creditStatus,
    required this.isDeleted,
    required this.deletedAt,
    this.kind = 'invoice',
    this.fiscalTaxEnabled = false,
    this.fiscalPriceMode = 'NO_TAX',
    this.taxableBase = 0,
    this.taxAmount = 0,
    this.exemptAmount = 0,
    this.discountAmount = 0,
    this.fiscalVoucherType,
    this.ncf,
    this.ncfExpirationDate,
    this.issuerNameSnapshot,
    this.issuerTaxIdSnapshot,
    this.issuerAddressSnapshot,
    this.issuerPhoneSnapshot,
    this.issuerEmailSnapshot,
    this.fiscalCustomerTaxId,
    this.fiscalCustomerName,
    this.customerAddressSnapshot,
    this.customerPhoneSnapshot,
    required this.items,
  });

  factory SaleModel.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    final customer = json['customer'];
    String? customerName;
    String? customerId;
    String? customerPhone;
    if (customer is Map) {
      customerName = customer['nombre']?.toString();
      customerId = customer['id']?.toString();
      customerPhone =
          customer['telefono']?.toString() ??
          customer['phone']?.toString() ??
          customer['celular']?.toString();
    }
    final user = json['user'];
    String? userName;
    if (user is Map) {
      userName =
          user['nombreCompleto']?.toString() ??
          user['fullName']?.toString() ??
          user['name']?.toString() ??
          user['email']?.toString();
    }
    userName ??=
        json['userName']?.toString() ??
        json['cashierName']?.toString() ??
        json['cashierNameSnapshot']?.toString() ??
        json['sellerName']?.toString() ??
        json['createdByUserName']?.toString() ??
        json['createdByName']?.toString();

    return SaleModel(
      id: (json['id'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      userName: userName,
      customerId: json['customerId']?.toString() ?? customerId,
      customerName: customerName,
      customerPhone:
          json['customerPhone']?.toString() ??
          json['customerTelefono']?.toString() ??
          json['telefono']?.toString() ??
          customerPhone,
      saleDate: json['saleDate'] != null
          ? DateTime.tryParse(json['saleDate'].toString())
          : null,
      note: json['note']?.toString(),
      totalSold: _toDouble(json['totalSold']),
      totalCost: _toDouble(json['totalCost']),
      totalProfit: _toDouble(json['totalProfit']),
      commissionAmount: _toDouble(json['commissionAmount']),
      paymentMethod: (json['paymentMethod'] ?? '').toString(),
      paymentCashAmount: _toDouble(json['paymentCashAmount']),
      paymentTransferAmount: _toDouble(json['paymentTransferAmount']),
      creditAmount: _toDouble(json['creditAmount']),
      creditPaidAmount: _toDouble(json['creditPaidAmount']),
      creditBalance: _toDouble(json['creditBalance']),
      creditStatus: (json['creditStatus'] ?? '').toString(),
      kind: (json['kind'] ?? 'invoice').toString(),
      isDeleted: json['isDeleted'] == true,
      deletedAt: json['deletedAt'] != null
          ? DateTime.tryParse(json['deletedAt'].toString())
          : null,
      fiscalTaxEnabled: json['fiscalTaxEnabled'] == true,
      fiscalPriceMode: (json['fiscalPriceMode'] ?? 'NO_TAX').toString(),
      taxableBase: _toDouble(json['taxableBase']),
      taxAmount: _toDouble(json['taxAmount']),
      exemptAmount: _toDouble(json['exemptAmount']),
      discountAmount: _toDouble(json['discountAmount']),
      fiscalVoucherType: json['fiscalVoucherType']?.toString(),
      ncf: json['ncf']?.toString(),
      ncfExpirationDate: json['ncfExpirationDate'] != null
          ? DateTime.tryParse(json['ncfExpirationDate'].toString())
          : json['ncf_expiration_date'] != null
          ? DateTime.tryParse(json['ncf_expiration_date'].toString())
          : null,
      issuerNameSnapshot: json['issuerNameSnapshot']?.toString(),
      issuerTaxIdSnapshot: json['issuerTaxIdSnapshot']?.toString(),
      issuerAddressSnapshot: json['issuerAddressSnapshot']?.toString(),
      issuerPhoneSnapshot: json['issuerPhoneSnapshot']?.toString(),
      issuerEmailSnapshot: json['issuerEmailSnapshot']?.toString(),
      fiscalCustomerTaxId: json['fiscalCustomerTaxId']?.toString(),
      fiscalCustomerName: json['fiscalCustomerName']?.toString(),
      customerAddressSnapshot: json['customerAddressSnapshot']?.toString(),
      customerPhoneSnapshot: json['customerPhoneSnapshot']?.toString(),
      items: rawItems
          .whereType<Map>()
          .map((item) => SaleItemModel.fromJson(item.cast<String, dynamic>()))
          .toList(),
    );
  }
}

class SaleDraftItem {
  final ProductModel? product;
  final String? productId;
  final String name;
  final String? imageUrl;
  final bool isExternal;
  final double qty;
  final double priceSoldUnit;
  final double? originalUnitPrice;
  final double costUnitSnapshot;
  final String? taxTreatment;
  final double? taxRate;
  final String? taxPriceMode;

  const SaleDraftItem({
    this.product,
    this.productId,
    required this.name,
    required this.imageUrl,
    required this.isExternal,
    required this.qty,
    required this.priceSoldUnit,
    this.originalUnitPrice,
    required this.costUnitSnapshot,
    this.taxTreatment,
    this.taxRate,
    this.taxPriceMode,
  });

  double get subtotalSold => qty * priceSoldUnit;
  double get subtotalCost => qty * costUnitSnapshot;
  double get profit => subtotalSold - subtotalCost;
  String get effectiveTaxTreatment =>
      product?.taxTreatment ?? taxTreatment ?? 'INHERIT';
  double? get effectiveTaxRate => product?.taxRate ?? taxRate;
  String? get effectiveTaxPriceMode => product?.taxPriceMode ?? taxPriceMode;

  SaleDraftItem copyWith({
    ProductModel? product,
    String? productId,
    String? name,
    String? imageUrl,
    bool? isExternal,
    double? qty,
    double? priceSoldUnit,
    double? originalUnitPrice,
    double? costUnitSnapshot,
    String? taxTreatment,
    double? taxRate,
    String? taxPriceMode,
  }) {
    return SaleDraftItem(
      product: product ?? this.product,
      productId: productId ?? this.productId,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      isExternal: isExternal ?? this.isExternal,
      qty: qty ?? this.qty,
      priceSoldUnit: priceSoldUnit ?? this.priceSoldUnit,
      originalUnitPrice: originalUnitPrice ?? this.originalUnitPrice,
      costUnitSnapshot: costUnitSnapshot ?? this.costUnitSnapshot,
      taxTreatment: taxTreatment ?? this.taxTreatment,
      taxRate: taxRate ?? this.taxRate,
      taxPriceMode: taxPriceMode ?? this.taxPriceMode,
    );
  }

  Map<String, dynamic> toPayload() {
    return {
      if (productId != null) 'productId': productId,
      if (productId == null) 'productName': name,
      'qty': qty,
      'priceSoldUnit': priceSoldUnit,
      if (originalUnitPrice != null && originalUnitPrice != priceSoldUnit)
        'originalUnitPriceSnapshot': originalUnitPrice,
      if (productId == null) 'costUnitSnapshot': costUnitSnapshot,
    };
  }

  factory SaleDraftItem.fromPayload(Map<String, dynamic> json) {
    final productId = json['productId']?.toString();
    return SaleDraftItem(
      productId: productId?.trim().isEmpty == true ? null : productId,
      name: (json['productName'] ?? json['productNameSnapshot'] ?? 'Producto')
          .toString(),
      imageUrl: json['productImageSnapshot']?.toString(),
      isExternal: productId == null || productId.trim().isEmpty,
      qty: _toDouble(json['qty']),
      priceSoldUnit: _toDouble(json['priceSoldUnit']),
      originalUnitPrice: _nullableDouble(
        json['originalUnitPriceSnapshot'] ?? json['originalUnitPrice'],
      ),
      costUnitSnapshot: _toDouble(json['costUnitSnapshot']),
      taxTreatment: json['taxTreatment']?.toString(),
      taxRate: _nullableDouble(json['taxRate']),
      taxPriceMode: json['taxPriceMode']?.toString(),
    );
  }
}

class SalesDateRange {
  final DateTime from;
  final DateTime to;

  const SalesDateRange({required this.from, required this.to});
}

double _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value == null) return 0;
  return double.tryParse(value.toString()) ?? 0;
}

double? _nullableDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
