import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/api_exception.dart';
import 'website_product_model.dart';
import 'website_repository.dart';

class WebsiteState {
  const WebsiteState({
    this.products = const [],
    this.loading = false,
    this.saving = false,
    this.error,
  });

  final List<WebsiteProductModel> products;
  final bool loading;
  final bool saving;
  final String? error;

  WebsiteState copyWith({
    List<WebsiteProductModel>? products,
    bool? loading,
    bool? saving,
    String? error,
    bool clearError = false,
  }) {
    return WebsiteState(
      products: products ?? this.products,
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      error: clearError ? null : error ?? this.error,
    );
  }
}

final websiteControllerProvider =
    StateNotifierProvider<WebsiteController, WebsiteState>((ref) {
      return WebsiteController(ref);
    });

class WebsiteController extends StateNotifier<WebsiteState> {
  WebsiteController(this.ref) : super(const WebsiteState());

  final Ref ref;

  Future<void> load() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final products = await ref
          .read(websiteRepositoryProvider)
          .fetchProducts();
      products.sort((a, b) {
        if (a.sortOrder != b.sortOrder)
          return a.sortOrder.compareTo(b.sortOrder);
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      state = state.copyWith(products: products, loading: false);
    } catch (e) {
      final message = e is ApiException
          ? e.message
          : 'No se pudo cargar el sitio web';
      state = state.copyWith(loading: false, error: message);
    }
  }

  Future<String> uploadImage({
    required List<int> bytes,
    required String filename,
  }) {
    return ref
        .read(websiteRepositoryProvider)
        .uploadImage(bytes: bytes, filename: filename);
  }

  Future<void> updateProduct({
    required WebsiteProductModel product,
    required String title,
    required String description,
    required String category,
    required String? imageUrl,
    required bool visible,
    required bool featured,
    required int sortOrder,
    String? seoTitle,
    String? seoDescription,
  }) async {
    state = state.copyWith(saving: true, clearError: true);
    try {
      final updated = await ref
          .read(websiteRepositoryProvider)
          .updateProduct(
            productId: product.id,
            title: title,
            description: description,
            category: category,
            imageUrl: imageUrl,
            visible: visible,
            featured: featured,
            sortOrder: sortOrder,
            seoTitle: seoTitle,
            seoDescription: seoDescription,
          );
      final list = state.products
          .map((item) => item.id == product.id ? updated : item)
          .toList();
      state = state.copyWith(products: list, saving: false);
    } catch (_) {
      state = state.copyWith(saving: false);
      rethrow;
    }
  }
}
