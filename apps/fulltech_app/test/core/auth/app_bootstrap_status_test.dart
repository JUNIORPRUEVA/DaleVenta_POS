import 'dart:async';

import 'package:daleventa_pos/core/auth/app_bootstrap_status.dart';
import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/company/company_settings_model.dart';
import 'package:daleventa_pos/core/company/company_settings_repository.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedAuthController extends AuthController {
  _FixedAuthController(super.ref, AuthState fixedState) {
    state = fixedState;
  }
}

UserModel _user({
  String id = 'user-a',
  String companyId = 'company-a',
  String companyName = 'FULLTECH, SRL',
}) {
  return UserModel(
    id: id,
    email: '$id@test.local',
    nombreCompleto: 'Test User',
    telefono: '',
    role: 'ADMIN',
    companyId: companyId,
    companyName: companyName,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'authenticated session is not ready until active company resolves',
    () async {
      final companyCompleter = Completer<CompanySettings>();
      final container = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => _FixedAuthController(
              ref,
              AuthState(
                initialized: true,
                isAuthenticated: true,
                user: _user(),
                hasSessionHint: true,
              ),
            ),
          ),
          companySettingsProvider.overrideWith(
            (ref) => companyCompleter.future,
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(appBootstrapStatusProvider),
        AppBootstrapStatus.authenticatedLoadingCompany,
      );

      companyCompleter.complete(
        CompanySettings.empty().copyWith(companyName: 'FULLTECH, SRL'),
      );
      await container.read(companySettingsProvider.future);

      expect(
        container.read(appBootstrapStatusProvider),
        AppBootstrapStatus.ready,
      );
    },
  );

  test('authenticated session without companyId becomes recoverable error', () {
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => _FixedAuthController(
            ref,
            AuthState(
              initialized: true,
              isAuthenticated: true,
              user: _user(companyId: ''),
              hasSessionHint: true,
            ),
          ),
        ),
        companySettingsProvider.overrideWith(
          (ref) async =>
              CompanySettings.empty().copyWith(companyName: 'FULLTECH, SRL'),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(appBootstrapStatusProvider),
      AppBootstrapStatus.error,
    );
  });

  test('logout state resets bootstrap to unauthenticated', () {
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => _FixedAuthController(
            ref,
            AuthState(
              initialized: true,
              isAuthenticated: false,
              user: null,
              hasSessionHint: false,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(appBootstrapStatusProvider),
      AppBootstrapStatus.unauthenticated,
    );
  });
}
