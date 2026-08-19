import 'package:daleventa_pos/core/auth/app_bootstrap_status.dart';
import 'package:daleventa_pos/core/auth/auth_provider.dart';
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

  test('authenticated session becomes ready immediately after auth restore', () {
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
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(appBootstrapStatusProvider),
      AppBootstrapStatus.ready,
    );
  });

  test('authenticated session without companyId becomes bootstrap error', () {
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
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(appBootstrapStatusProvider),
      AppBootstrapStatus.error,
    );
  });

  test('restoring session still waits before identity is verified', () {
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => _FixedAuthController(
            ref,
            AuthState(
              initialized: true,
              isAuthenticated: true,
              user: _user(companyId: ''),
              restoringSession: true,
              hasSessionHint: true,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(appBootstrapStatusProvider),
      AppBootstrapStatus.authenticatedLoadingCompany,
    );
  });

  test('ready bootstrap no longer depends on company settings fetch', () {
    final container = ProviderContainer(
      overrides: [
        authStateProvider.overrideWith(
          (ref) => _FixedAuthController(
            ref,
            AuthState(
              initialized: true,
              isAuthenticated: true,
              user: _user(companyName: ''),
              hasSessionHint: true,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(
      container.read(appBootstrapStatusProvider),
      AppBootstrapStatus.ready,
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
