import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_routes.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/errors/api_exception.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository(ref.watch(dioProvider));
});

class OnboardingRepository {
  OnboardingRepository(this._dio);

  final Dio _dio;
  static const _timeout = Duration(seconds: 18);

  Future<OnboardingStateModel> getState() async {
    try {
      final res = await _dio
          .get(
            ApiRoutes.onboarding,
            options: Options(extra: const {'skipLoader': true}),
          )
          .timeout(_timeout);
      return OnboardingStateModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on TimeoutException {
      throw ApiException('La preparacion inicial tardo demasiado.');
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo cargar la preparacion inicial'),
        e.response?.statusCode,
      );
    }
  }

  Future<OnboardingStateModel> start() => _post(ApiRoutes.onboardingStart);

  Future<OnboardingStateModel> skipAll() => _post(ApiRoutes.onboardingSkipAll);

  Future<OnboardingStateModel> setStep(
    String step,
    String status, {
    bool completeFlow = false,
  }) {
    return _patch(ApiRoutes.onboardingStep(step), {
      'status': status,
      'completeFlow': completeFlow,
    });
  }

  Future<OnboardingStateModel> setTutorial(String status) {
    return _patch(ApiRoutes.onboardingTutorial, {'status': status});
  }

  Future<OnboardingStateModel> _post(String route) async {
    try {
      final res = await _dio
          .post(route, options: Options(extra: const {'skipLoader': true}))
          .timeout(_timeout);
      return OnboardingStateModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo actualizar el onboarding'),
        e.response?.statusCode,
      );
    }
  }

  Future<OnboardingStateModel> _patch(
    String route,
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await _dio
          .patch(
            route,
            data: payload,
            options: Options(extra: const {'skipLoader': true}),
          )
          .timeout(_timeout);
      return OnboardingStateModel.fromJson(
        (res.data as Map).cast<String, dynamic>(),
      );
    } on DioException catch (e) {
      throw ApiException(
        _message(e.response?.data, 'No se pudo guardar el avance'),
        e.response?.statusCode,
      );
    }
  }

  String _message(dynamic data, String fallback) {
    if (data is String && data.trim().isNotEmpty) return data;
    if (data is Map && data['message'] is String) {
      return (data['message'] as String).trim();
    }
    return fallback;
  }
}

class OnboardingStateModel {
  const OnboardingStateModel({
    required this.required,
    required this.shouldShowWelcome,
    required this.status,
    required this.tutorialStatus,
    required this.steps,
    required this.company,
    required this.productCount,
    this.trialEndsAt,
  });

  final bool required;
  final bool shouldShowWelcome;
  final String status;
  final String tutorialStatus;
  final Map<String, String> steps;
  final OnboardingCompanyModel company;
  final int productCount;
  final DateTime? trialEndsAt;

  int get reviewedSteps => steps.values
      .where((value) => value == 'COMPLETED' || value == 'SKIPPED')
      .length;

  bool get allReviewed => reviewedSteps >= 4;

  factory OnboardingStateModel.fromJson(Map<String, dynamic> json) {
    final stepsRaw = json['steps'];
    final trialRaw = json['trial'];
    final companyRaw = json['company'];
    final trial = trialRaw is Map ? trialRaw.cast<String, dynamic>() : {};
    final stepsMap = stepsRaw is Map
        ? stepsRaw.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          )
        : const <String, String>{};
    return OnboardingStateModel(
      required: json['required'] == true,
      shouldShowWelcome: json['shouldShowWelcome'] == true,
      status: (json['status'] ?? 'NOT_REQUIRED').toString(),
      tutorialStatus: (json['tutorialStatus'] ?? 'NOT_REQUIRED').toString(),
      steps: {
        'company': stepsMap['company'] ?? 'PENDING',
        'billing': stepsMap['billing'] ?? 'PENDING',
        'product': stepsMap['product'] ?? 'PENDING',
        'ready': stepsMap['ready'] ?? 'PENDING',
      },
      company: OnboardingCompanyModel.fromJson(
        companyRaw is Map ? companyRaw.cast<String, dynamic>() : const {},
      ),
      productCount: (json['productCount'] as num?)?.toInt() ?? 0,
      trialEndsAt: DateTime.tryParse((trial['endsAt'] ?? '').toString()),
    );
  }
}

class OnboardingCompanyModel {
  const OnboardingCompanyModel({
    required this.name,
    required this.commercialName,
    required this.rnc,
    required this.phone,
    required this.address,
    required this.taxEnabled,
    required this.pricesIncludeTax,
    required this.ncfEnabled,
  });

  final String name;
  final String commercialName;
  final String rnc;
  final String phone;
  final String address;
  final bool taxEnabled;
  final bool pricesIncludeTax;
  final bool ncfEnabled;

  factory OnboardingCompanyModel.fromJson(Map<String, dynamic> json) {
    return OnboardingCompanyModel(
      name: (json['name'] ?? '').toString(),
      commercialName: (json['commercialName'] ?? json['name'] ?? '').toString(),
      rnc: (json['rnc'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      taxEnabled: json['taxEnabled'] == true,
      pricesIncludeTax: json['pricesIncludeTax'] == true,
      ncfEnabled: json['ncfEnabled'] == true,
    );
  }
}
