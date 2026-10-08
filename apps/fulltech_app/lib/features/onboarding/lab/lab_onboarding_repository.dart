import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/onboarding_repository.dart';

final labOnboardingControllerProvider =
    ChangeNotifierProvider<LabOnboardingController>(
      (ref) => LabOnboardingController(),
    );

enum LabOnboardingEntryPoint { welcome, company, billing, product, ready }

class LabOnboardingController extends ChangeNotifier {
  LabOnboardingController() {
    reset();
  }

  late OnboardingStateModel _state;

  OnboardingStateModel get state => _state;

  void reset({
    LabOnboardingEntryPoint entry = LabOnboardingEntryPoint.welcome,
  }) {
    _state = _stateFor(entry);
    notifyListeners();
  }

  void updateCompany({
    required String name,
    required String phone,
    required String address,
    required String rnc,
  }) {
    _state = _state.copyWith(
      company: _state.company.copyWith(
        name: name,
        commercialName: name,
        phone: phone,
        address: address,
        rnc: rnc,
      ),
    );
    notifyListeners();
  }

  void updateBilling({required bool taxEnabled, required bool ncfEnabled}) {
    _state = _state.copyWith(
      company: _state.company.copyWith(
        taxEnabled: taxEnabled,
        ncfEnabled: ncfEnabled,
      ),
    );
    notifyListeners();
  }

  OnboardingStateModel start() {
    _state = _state.copyWith(
      required: true,
      shouldShowWelcome: false,
      status: 'IN_PROGRESS',
    );
    notifyListeners();
    return _state;
  }

  OnboardingStateModel skipAll() {
    _state = _state.copyWith(
      required: false,
      shouldShowWelcome: false,
      status: 'SKIPPED',
      steps: const {
        'company': 'SKIPPED',
        'billing': 'SKIPPED',
        'product': 'SKIPPED',
        'ready': 'SKIPPED',
      },
      tutorialStatus: 'SKIPPED',
    );
    notifyListeners();
    return _state;
  }

  OnboardingStateModel setStep(
    String step,
    String status, {
    bool completeFlow = false,
  }) {
    final nextSteps = Map<String, String>.from(_state.steps);
    if (nextSteps.containsKey(step)) {
      nextSteps[step] = status;
    }
    _state = _state.copyWith(
      required: completeFlow ? false : true,
      shouldShowWelcome: false,
      status: completeFlow ? 'COMPLETED' : 'IN_PROGRESS',
      steps: nextSteps,
      productCount: step == 'product' && status == 'COMPLETED'
          ? 1
          : _state.productCount,
    );
    notifyListeners();
    return _state;
  }

  OnboardingStateModel setTutorial(String status) {
    _state = _state.copyWith(tutorialStatus: status);
    notifyListeners();
    return _state;
  }

  OnboardingStateModel _stateFor(LabOnboardingEntryPoint entry) {
    const pendingSteps = {
      'company': 'PENDING',
      'billing': 'PENDING',
      'product': 'PENDING',
      'ready': 'PENDING',
    };
    const mockCompany = OnboardingCompanyModel(
      name: 'Negocio de Prueba',
      commercialName: 'Negocio de Prueba',
      rnc: '',
      phone: '8090000000',
      address: 'Direccion de prueba',
      taxEnabled: false,
      pricesIncludeTax: false,
      ncfEnabled: false,
    );
    final base = OnboardingStateModel(
      required: true,
      shouldShowWelcome: entry == LabOnboardingEntryPoint.welcome,
      status: entry == LabOnboardingEntryPoint.welcome
          ? 'WELCOME_PENDING'
          : 'IN_PROGRESS',
      tutorialStatus: 'PENDING',
      steps: pendingSteps,
      company: mockCompany,
      productCount: 0,
      trialEndsAt: DateTime.now().add(const Duration(days: 7)),
    );
    return switch (entry) {
      LabOnboardingEntryPoint.welcome => base,
      LabOnboardingEntryPoint.company => base.copyWith(
        shouldShowWelcome: false,
      ),
      LabOnboardingEntryPoint.billing => base.copyWith(
        shouldShowWelcome: false,
        steps: const {
          'company': 'COMPLETED',
          'billing': 'PENDING',
          'product': 'PENDING',
          'ready': 'PENDING',
        },
      ),
      LabOnboardingEntryPoint.product => base.copyWith(
        shouldShowWelcome: false,
        steps: const {
          'company': 'COMPLETED',
          'billing': 'COMPLETED',
          'product': 'PENDING',
          'ready': 'PENDING',
        },
      ),
      LabOnboardingEntryPoint.ready => base.copyWith(
        shouldShowWelcome: false,
        productCount: 1,
        steps: const {
          'company': 'COMPLETED',
          'billing': 'COMPLETED',
          'product': 'COMPLETED',
          'ready': 'PENDING',
        },
      ),
    };
  }
}

class LabOnboardingRepository implements OnboardingRepository {
  LabOnboardingRepository(this._controller);

  final LabOnboardingController _controller;

  @override
  Future<OnboardingStateModel> getState() async => _controller.state;

  @override
  Future<OnboardingStateModel> setStep(
    String step,
    String status, {
    bool completeFlow = false,
  }) async {
    return _controller.setStep(step, status, completeFlow: completeFlow);
  }

  @override
  Future<OnboardingStateModel> setTutorial(String status) async {
    return _controller.setTutorial(status);
  }

  @override
  Future<OnboardingStateModel> skipAll() async => _controller.skipAll();

  @override
  Future<OnboardingStateModel> start() async => _controller.start();
}
