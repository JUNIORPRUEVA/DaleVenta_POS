import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/auth/token_storage.dart';
import '../../../core/cache/local_json_cache.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/models/product_model.dart';
import '../../../core/offline/sync_queue_service.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/utils/is_flutter_test.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  final repository = CatalogRepository(
    ref.watch(dioProvider),
    ref.watch(tokenStorageProvider),
    ref.read(syncQueueServiceProvider.notifier),
  );
  repository.registerSyncHandlers();
  return repository;
});

class CatalogRepository {
  final Dio _dio;
  final TokenStorage _tokenStorage;
  final SyncQueueService? _syncQueue;
  final LocalJsonCache _cache = LocalJsonCache();

  static const String _createSyncType = 'catalog.products.create';
  static const String _updateSyncType = 'catalog.products.update';
  static const String _deleteSyncType = 'catalog.products.delete';
  static const String _productsCacheKeyPrefix = 'catalog.products.snapshot.v2';
  static const Duration _cacheTtl = Duration(days: 7);

  bool _handlersRegistered = false;

  CatalogRepository(this._dio, [TokenStorage? tokenStorage, this._syncQueue])
    : _tokenStorage = tokenStorage ?? TokenStorage();

  void registerSyncHandlers() {
    final syncQueue = _syncQueue;
    if (syncQueue == null) return;
    if (_handlersRegistered) return;
    _handlersRegistered = true;

    syncQueue.registerHandler(_createSyncType, (payload) async {
      await _createProductRemote(
        nombre: (payload['nombre'] ?? '').toString(),
        codigo: payload['codigo']?.toString(),
        precio: _asDouble(payload['precio']),
        costo: _asDouble(payload['costo']),
        stock: _asDouble(payload['stock']),
        fotoUrl: payload['fotoUrl']?.toString(),
        categoria: (payload['categoria'] ?? '').toString(),
        operationId: payload['operationId']?.toString(),
        skipLoader: true,
      );
    });

    syncQueue.registerHandler(_updateSyncType, (payload) async {
      await _updateProductRemote(
        id: (payload['id'] ?? '').toString(),
        nombre: (payload['nombre'] ?? '').toString(),
        codigo: payload['codigo']?.toString(),
        precio: _asDouble(payload['precio']),
        costo: _asDouble(payload['costo']),
        stock: _asDouble(payload['stock']),
        fotoUrl: payload['fotoUrl']?.toString(),
        categoria: payload['categoria']?.toString(),
        operationId: payload['operationId']?.toString(),
        skipLoader: true,
      );
    });

    syncQueue.registerHandler(_deleteSyncType, (payload) async {
      await _deleteProductRemote(
        (payload['id'] ?? '').toString(),
        skipLoader: true,
      );
    });
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().replaceAll(',', '.')) ?? 0;
  }

  bool _shouldQueueSync(ApiException error) {
    final code = error.code;
    return code == null || code >= 500;
  }

  Future<String> _activeCompanyStorageId() async {
    if (isFlutterTest) return 'default';
    try {
      final user = await _tokenStorage.getUserSnapshot();
      final companyId = user?.companyId?.trim() ?? '';
      if (companyId.isNotEmpty) return companyId;
    } catch (_) {}
    return 'default';
  }

  Future<String> _productsCacheKey() async {
    final companyId = await _activeCompanyStorageId();
    return '$_productsCacheKeyPrefix.$companyId';
  }

  Future<String> _syncScope() async {
    final companyId = await _activeCompanyStorageId();
    return 'catalog.$companyId';
  }

  List<dynamic> _extractRows(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      const keys = ['items', 'data', 'products', 'rows'];
      for (final key in keys) {
        final candidate = data[key];
        if (candidate is List) return candidate;
      }
    }
    return const [];
  }

  String _extractMessage(dynamic data, String fallback) {
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      if (message is List && message.isNotEmpty) {
        final first = message.first;
        if (first is String && first.trim().isNotEmpty) return first;
      }
    }
    return fallback;
  }

  String _formatDioError(DioException e, String fallback) {
    final status = e.response?.statusCode;
    final endpoint = e.requestOptions.path;
    final uri = e.requestOptions.uri.toString();
    final baseUrl = _dio.options.baseUrl;
    final rawMessage = _extractMessage(e.response?.data, fallback);

    if (status == null) {
      return '[NETWORK] $rawMessage\nEndpoint: $endpoint\nURI: $uri\nBaseURL: $baseUrl\nDetalle: ${e.message ?? 'Sin respuesta del servidor'}';
    }

    return '[HTTP $status] $rawMessage\nEndpoint: $endpoint\nURI: $uri';
  }

  Future<List<ProductModel>> fetchProducts({
    bool forceRefresh = false,
    bool silent = false,
  }) async {
    try {
      final res = await _dio.get(
        ApiRoutes.catalogProducts,
        queryParameters: null,
        options: Options(
          headers: {
            'Cache-Control': 'no-cache, no-store, must-revalidate',
            'Pragma': 'no-cache',
            'Expires': '0',
          },
          extra: {'silent': silent},
        ),
      );
      final rows = _extractRows(res.data);
      final products = rows
          .whereType<Map>()
          .map((row) => ProductModel.fromJson(Map<String, dynamic>.from(row)))
          .toList();
      await saveProductsSnapshot(products);
      return products;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 402 || status == 403 || status == 423) {
        throw ApiException(
          _formatDioError(e, 'No se pudieron cargar los productos'),
          status,
        );
      }
      final cached = await getCachedProducts();
      if (cached.isNotEmpty) return cached;
      throw ApiException(
        _formatDioError(e, 'No se pudieron cargar los productos'),
        e.response?.statusCode,
      );
    } catch (e) {
      throw ApiException('No se pudieron cargar los productos: $e');
    }
  }

  Future<List<ProductModel>> getCachedProducts() async {
    final cached = await _cache.readMap(
      await _productsCacheKey(),
      maxAge: _cacheTtl,
    );
    final rows = cached?['items'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => ProductModel.fromJson(row.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<void> saveProductsSnapshot(List<ProductModel> items) async {
    return _cache.writeMap(await _productsCacheKey(), {
      'items': items.map((item) => item.toJson()).toList(growable: false),
    });
  }

  Future<String> uploadImage({
    required List<int> bytes,
    required String filename,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: detectImageMime(filename),
        ),
      });
      final res = await _dio.post(
        ApiRoutes.productsUpload,
        data: formData,
        options: Options(extra: const {'skipLoader': true}),
      );
      final data = res.data;
      if (data is Map && data['key'] is String) {
        return data['key'] as String;
      }
      if (data is Map && data['objectKey'] is String) {
        return data['objectKey'] as String;
      }
      if (data is Map && data['url'] is String) {
        return data['url'] as String;
      }
      if (data is Map && data['path'] is String) {
        return data['path'] as String;
      }
      throw ApiException('No se recibió la ruta de la imagen');
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(e.response?.data, 'No se pudo subir la imagen'),
        e.response?.statusCode,
      );
    }
  }

  Future<String?> importImageFromUrl(
    String rawUrl, {
    String? productName,
  }) async {
    final url = rawUrl.trim();
    if (url.isEmpty ||
        !RegExp(r'^https?://', caseSensitive: false).hasMatch(url)) {
      return null;
    }
    try {
      final res = await _dio.post(
        ApiRoutes.productsImportImageUrl,
        data: {
          'url': url,
          if ((productName ?? '').trim().isNotEmpty)
            'productName': productName!.trim(),
        },
        options: Options(
          extra: const {'skipLoader': true},
          receiveTimeout: const Duration(seconds: 45),
          sendTimeout: const Duration(seconds: 20),
        ),
      );
      final data = res.data;
      if (data is Map && data['url'] is String) return data['url'] as String;
      if (data is Map && data['path'] is String) return data['path'] as String;
      if (data is Map && data['key'] is String) return data['key'] as String;
      if (data is Map && data['objectKey'] is String) {
        return data['objectKey'] as String;
      }
      return null;
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudo importar la imagen del producto',
        ),
        e.response?.statusCode,
      );
    }
  }

  Future<ProductModel> createProduct({
    required String nombre,
    String? codigo,
    required double precio,
    required double costo,
    required double stock,
    String? fotoUrl,
    required String categoria,
    String? operationId,
    bool skipLoader = false,
  }) async {
    final payload = _productPayload(
      nombre: nombre,
      codigo: codigo,
      precio: precio,
      costo: costo,
      stock: stock,
      fotoUrl: fotoUrl,
      categoria: categoria,
      operationId: operationId,
    );
    try {
      return await _createProductRemote(
        nombre: nombre,
        codigo: codigo,
        precio: precio,
        costo: costo,
        stock: stock,
        fotoUrl: fotoUrl,
        categoria: categoria,
        operationId: operationId,
        skipLoader: skipLoader,
      );
    } on DioException catch (e) {
      final error = ApiException(
        _extractMessage(e.response?.data, 'No se pudo crear el producto'),
        e.response?.statusCode,
      );
      if (!_shouldQueueSync(error) || _syncQueue == null) throw error;
      final queueId =
          '$_createSyncType:${operationId ?? DateTime.now().microsecondsSinceEpoch}';
      await _syncQueue.enqueue(
        id: queueId,
        type: _createSyncType,
        scope: await _syncScope(),
        payload: payload,
      );
      return ProductModel(
        id: 'local_product_${DateTime.now().microsecondsSinceEpoch}',
        nombre: nombre,
        codigo: codigo?.trim().isEmpty == true ? null : codigo?.trim(),
        precio: precio,
        costo: costo,
        costAvailable: true,
        stock: stock,
        fotoUrl: fotoUrl?.trim().isEmpty == true ? null : fotoUrl?.trim(),
        originalFotoUrl: fotoUrl?.trim().isEmpty == true
            ? null
            : fotoUrl?.trim(),
        categoria: categoria,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }
  }

  Future<ProductModel> _createProductRemote({
    required String nombre,
    String? codigo,
    required double precio,
    required double costo,
    required double stock,
    String? fotoUrl,
    required String categoria,
    String? operationId,
    bool skipLoader = false,
  }) async {
    final res = await _dio.post(
      ApiRoutes.products,
      options: skipLoader ? Options(extra: const {'skipLoader': true}) : null,
      data: _productPayload(
        nombre: nombre,
        codigo: codigo,
        precio: precio,
        costo: costo,
        stock: stock,
        fotoUrl: fotoUrl,
        categoria: categoria,
        operationId: operationId,
      ),
    );
    return ProductModel.fromJson((res.data as Map).cast<String, dynamic>());
  }

  Future<ProductModel> updateProduct({
    required String id,
    required String nombre,
    String? codigo,
    required double precio,
    required double costo,
    required double stock,
    String? fotoUrl,
    String? categoria,
    String? operationId,
    bool skipLoader = false,
  }) async {
    final payload = _productPayload(
      id: id,
      nombre: nombre,
      codigo: codigo,
      precio: precio,
      costo: costo,
      stock: stock,
      fotoUrl: fotoUrl,
      categoria: categoria,
      operationId: operationId,
    );
    try {
      return await _updateProductRemote(
        id: id,
        nombre: nombre,
        codigo: codigo,
        precio: precio,
        costo: costo,
        stock: stock,
        fotoUrl: fotoUrl,
        categoria: categoria,
        operationId: operationId,
        skipLoader: skipLoader,
      );
    } on DioException catch (e) {
      final error = ApiException(
        _extractMessage(e.response?.data, 'No se pudo actualizar el producto'),
        e.response?.statusCode,
      );
      if (!_shouldQueueSync(error) || _syncQueue == null) throw error;
      await _syncQueue.enqueue(
        id: '$_updateSyncType:$id',
        type: _updateSyncType,
        scope: await _syncScope(),
        payload: payload,
      );
      return ProductModel(
        id: id,
        nombre: nombre,
        codigo: codigo?.trim().isEmpty == true ? null : codigo?.trim(),
        precio: precio,
        costo: costo,
        stock: stock,
        fotoUrl: fotoUrl?.trim().isEmpty == true ? null : fotoUrl?.trim(),
        originalFotoUrl: fotoUrl?.trim().isEmpty == true
            ? null
            : fotoUrl?.trim(),
        categoria: categoria,
        updatedAt: DateTime.now(),
      );
    }
  }

  Future<ProductModel> _updateProductRemote({
    required String id,
    required String nombre,
    String? codigo,
    required double precio,
    required double costo,
    required double stock,
    String? fotoUrl,
    String? categoria,
    String? operationId,
    bool skipLoader = false,
  }) async {
    final res = await _dio.patch(
      ApiRoutes.updateProduct(id),
      options: skipLoader ? Options(extra: const {'skipLoader': true}) : null,
      data: _productPayload(
        nombre: nombre,
        codigo: codigo,
        precio: precio,
        costo: costo,
        stock: stock,
        fotoUrl: fotoUrl,
        categoria: categoria,
        operationId: operationId,
      ),
    );
    return ProductModel.fromJson((res.data as Map).cast<String, dynamic>());
  }

  Future<void> deleteProduct(String id, {bool skipLoader = false}) async {
    try {
      await _deleteProductRemote(id, skipLoader: skipLoader);
    } on DioException catch (e) {
      final error = ApiException(
        _extractMessage(e.response?.data, 'No se pudo eliminar el producto'),
        e.response?.statusCode,
      );
      if (!_shouldQueueSync(error) || _syncQueue == null) throw error;
      await _syncQueue.enqueue(
        id: '$_deleteSyncType:$id',
        type: _deleteSyncType,
        scope: await _syncScope(),
        payload: {'id': id},
      );
    }
  }

  Future<void> _deleteProductRemote(String id, {bool skipLoader = false}) {
    return _dio.delete(
      ApiRoutes.deleteProduct(id),
      options: skipLoader ? Options(extra: const {'skipLoader': true}) : null,
    );
  }

  Map<String, dynamic> _productPayload({
    String? id,
    required String nombre,
    String? codigo,
    required double precio,
    required double costo,
    required double stock,
    String? fotoUrl,
    String? categoria,
    String? operationId,
    String? taxTreatment,
    double? taxRate,
    String? taxPriceMode,
  }) {
    final cleanCode = codigo?.trim();
    final safeCode = cleanCode?.isEmpty == true ? null : cleanCode;
    return {
      if ((id ?? '').trim().isNotEmpty) 'id': id!.trim(),
      'nombre': nombre,
      'codigo': safeCode,
      'code': safeCode,
      'sku': safeCode,
      'barcode': safeCode,
      'precio': precio,
      'costo': costo,
      'stock': stock,
      if ((operationId ?? '').trim().isNotEmpty)
        'operationId': operationId!.trim(),
      if ((fotoUrl ?? '').trim().isNotEmpty) 'fotoUrl': fotoUrl!.trim(),
      'categoria': categoria,
      if ((taxTreatment ?? '').trim().isNotEmpty)
        'taxTreatment': taxTreatment!.trim(),
      if (taxRate != null) 'taxRate': taxRate,
      if ((taxPriceMode ?? '').trim().isNotEmpty)
        'taxPriceMode': taxPriceMode!.trim(),
    };
  }

  Future<Map<String, dynamic>> purgeAllDebug() async {
    try {
      final res = await _dio.delete(ApiRoutes.productsDebugPurge);
      return Map<String, dynamic>.from(
        (res.data as Map?) ?? const <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw ApiException(
        _extractMessage(
          e.response?.data,
          'No se pudieron limpiar los productos',
        ),
        e.response?.statusCode,
      );
    }
  }
}
