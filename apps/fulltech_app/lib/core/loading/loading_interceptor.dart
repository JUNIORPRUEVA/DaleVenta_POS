import 'package:dio/dio.dart';

import 'app_loading_controller.dart';

const String _loadingRequestIdKey = '__app_loading_request_id';

class LoadingInterceptor extends Interceptor {
  final AppLoadingController controller;

  LoadingInterceptor(this.controller);

  bool _shouldTrack(RequestOptions options) {
    final extra = options.extra;
    final silent = extra['silent'];
    if (silent is bool && silent) return false;

    final skip = extra['skipLoader'];
    if (skip is bool && skip) return false;

    // Keep the global branded loader opt-in. Normal screen data requests should
    // refresh quietly so navigation feels instant and the UI never gets covered
    // by a long "Cargando..." dialog after the route is already visible.
    final show = extra['showLoader'];
    return show is bool && show;
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_shouldTrack(options)) {
      options.extra[_loadingRequestIdKey] = controller.requestStarted();
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (_shouldTrack(response.requestOptions)) {
      controller.requestEnded(_requestIdFor(response.requestOptions));
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (_shouldTrack(err.requestOptions)) {
      controller.requestEnded(_requestIdFor(err.requestOptions));
    }
    handler.next(err);
  }

  String? _requestIdFor(RequestOptions options) {
    final requestId = options.extra.remove(_loadingRequestIdKey);
    return requestId is String && requestId.isNotEmpty ? requestId : null;
  }
}
