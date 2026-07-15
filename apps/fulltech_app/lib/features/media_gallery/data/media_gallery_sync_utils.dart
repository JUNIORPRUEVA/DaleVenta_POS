import '../media_gallery_models.dart';

List<MediaGalleryItem> mergeMediaGalleryItems({
  required List<MediaGalleryItem> previousItems,
  required List<MediaGalleryItem> freshItems,
}) {
  return uniqueMediaGalleryItems([...previousItems, ...freshItems]);
}

List<MediaGalleryItem> uniqueMediaGalleryItems(List<MediaGalleryItem> items) {
  final dedupedByContent = <String, MediaGalleryItem>{};

  final sorted = items.toList(growable: false)
    ..sort((a, b) {
      final createdAtCompare = b.createdAt.compareTo(a.createdAt);
      if (createdAtCompare != 0) return createdAtCompare;
      return b.id.compareTo(a.id);
    });

  for (final item in sorted) {
    final key = _mediaContentKey(item);
    dedupedByContent.putIfAbsent(key, () => item);
  }

  return dedupedByContent.values.toList(growable: false)..sort((a, b) {
    final createdAtCompare = b.createdAt.compareTo(a.createdAt);
    if (createdAtCompare != 0) return createdAtCompare;
    return b.id.compareTo(a.id);
  });
}

String _mediaContentKey(MediaGalleryItem item) {
  final rawUrl = item.url.trim();
  final uri = Uri.tryParse(rawUrl);
  final normalizedPath = uri == null
      ? rawUrl.toLowerCase()
      : uri.replace(query: '', fragment: '').toString().toLowerCase();
  final assetType = item.isVideo ? 'video' : 'image';
  return '$assetType::$normalizedPath';
}
