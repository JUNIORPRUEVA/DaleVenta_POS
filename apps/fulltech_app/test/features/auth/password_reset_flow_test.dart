import 'package:daleventa_pos/core/auth/auth_repository.dart';
import 'package:daleventa_pos/core/auth/token_storage.dart';
import 'package:daleventa_pos/features/auth/presentation/forgot_password_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super(dio: Dio(), storage: TokenStorage());

  String? requestedEmail;
  String? resetToken;
  String? resetPasswordValue;

  @override
  Future<String> requestPasswordReset(String email) async {
    requestedEmail = email;
    return 'Si tu cuenta permite recuperación por correo, recibirás las instrucciones correspondientes. De lo contrario, contacta al administrador de tu empresa.';
  }

  @override
  Future<void> resetPassword({
    required String token,
    required String password,
  }) async {
    resetToken = token;
    resetPasswordValue = password;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('forgot password requests email and shows neutral confirmation', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: ForgotPasswordScreen()),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Correo electrónico'),
      'owner@test.local',
    );
    await tester.tap(find.text('Enviar instrucciones'));
    await tester.pumpAndSettle();

    expect(repository.requestedEmail, 'owner@test.local');
    expect(
      find.textContaining('Si tu cuenta permite recuperación por correo'),
      findsOneWidget,
    );
  });

  testWidgets('reset password submits token and matching password', (
    tester,
  ) async {
    final repository = _FakeAuthRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: ResetPasswordScreen(token: 'reset-token'),
        ),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nueva contraseña'),
      'new-password-123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirmar contraseña'),
      'new-password-123',
    );
    await tester.tap(find.text('Actualizar contraseña'));
    await tester.pumpAndSettle();

    expect(repository.resetToken, 'reset-token');
    expect(repository.resetPasswordValue, 'new-password-123');
    expect(find.text('Contraseña actualizada'), findsOneWidget);
  });
}
