import '../../../core/models/product_model.dart';

bool areCatalogProductsEquivalent(
  List<ProductModel> previous,
  List<ProductModel> next,
) {
  if (identical(previous, next)) return true;
  if (previous.length != next.length) return false;

  final previousById = {
    for (final item in previous) item.id: item.toJson(),
  };
  for (final item in next) {
    final previousJson = previousById[item.id];
    if (previousJson == null || !_mapsEqual(previousJson, item.toJson())) {
      return false;
    }
  }
  return true;
}

bool _mapsEqual(Map<String, dynamic> left, Map<String, dynamic> right) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    if (!right.containsKey(entry.key) || right[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

List<ProductModel> mergeRecoveredCatalogImages({
  required List<ProductModel> previousItems,
  required List<ProductModel> fetchedItems,
}) {
  if (previousItems.isEmpty) return fetchedItems;

  final previousById = {for (final item in previousItems) item.id: item};

  return fetchedItems
      .map((next) {
        final previous = previousById[next.id];
        if (previous == null) return next;

        final nextHasImage =
            (next.fotoUrl ?? '').trim().isNotEmpty ||
            (next.originalFotoUrl ?? '').trim().isNotEmpty;
        final previousHasImage =
            (previous.fotoUrl ?? '').trim().isNotEmpty ||
            (previous.originalFotoUrl ?? '').trim().isNotEmpty;

        if (!previousHasImage || nextHasImage) {
          return next;
        }

        final sameUpdatedAt =
            next.updatedAt != null &&
            previous.updatedAt != null &&
            next.updatedAt!.millisecondsSinceEpoch ==
                previous.updatedAt!.millisecondsSinceEpoch;

        if (sameUpdatedAt || next.updatedAt == null) {
          return next.copyWith(
            fotoUrl: previous.fotoUrl,
            originalFotoUrl: previous.originalFotoUrl,
            imageVersion: previous.imageVersion ?? next.imageVersion,
          );
        }

        return next;
      })
      .toList(growable: false);
}
