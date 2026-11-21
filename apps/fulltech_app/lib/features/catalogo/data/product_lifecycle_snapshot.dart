class ProductLifecycleSnapshot {
  const ProductLifecycleSnapshot(this.data);
  final Map<String, dynamic> data;
  String get productId => '${data['productId']}';
  String get status => '${data['status']}';
  int get version => (data['lifecycleVersion'] as num).toInt();
  bool get canDelete => data['canDelete'] == true;
  bool get canArchive => data['canArchive'] == true;
  bool get canRestore => data['canRestore'] == true;
  bool get canAnnul => data['canAnnul'] == true;
  String get reason => (data['reason'] ?? '').toString();
  String get stock => (data['stock'] ?? '0').toString();
}

/// A pending local document is protected even when it needs intervention.
/// Match complete identifiers, never substrings or another company's queue.
bool payloadReferencesProduct(Object? payload, String productId) {
  if (payload is Map) {
    return payload.values.any(
      (value) => payloadReferencesProduct(value, productId),
    );
  }
  if (payload is List) {
    return payload.any((value) => payloadReferencesProduct(value, productId));
  }
  return payload is String && payload == productId;
}
