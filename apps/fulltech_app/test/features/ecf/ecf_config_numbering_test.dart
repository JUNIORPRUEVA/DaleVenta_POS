import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_authorized_sequence_models.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_config_page.dart';
import 'package:daleventa_pos/features/ecf/ui/flow/ecf_sequence_range_section.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthController {
  _Auth(super.ref, {String role = 'ADMIN'}) {
    replaceCompany('company-a', role: role);
  }

  void replaceCompany(String company, {String role = 'ADMIN'}) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel.fromJson({
        'id': 'operator',
        'companyId': company,
        'email': 'fixture@test.invalid',
        'role': role,
      }),
    );
  }
}

class _Repo extends EcfRepository {
  _Repo({this.environment = 'SANDBOX', this.enabled = true}) : super(Dio());
  final String environment;
  final bool enabled;
  int authorizationReads = 0;
  int declarations = 0;
  int registrations = 0;
  Completer<void>? declarationGate;
  final declared = <EcfAuthorizedSequence>[
    const EcfAuthorizedSequence(
      documentType: 'E31',
      authorizationNumber: 'SYNTHETIC-ALREADY-DECLARED',
      rangeFrom: 1,
      rangeTo: 20,
      approvedQuantity: 20,
      declarationVersion: 'fixture-v1',
    ),
  ];
  final ranges = <EcfSequenceInfo>[
    const EcfSequenceInfo(
      id: 'synthetic-e31',
      documentType: 'E31',
      prefix: 'E31',
      startNumber: 1,
      nextNumber: 3,
      endNumber: 20,
      active: true,
      consumed: 2,
      remaining: 18,
    ),
  ];

  @override
  Future<EcfCapabilities> capabilities() async => EcfCapabilities.fromJson({
    'enabled': enabled,
    'environment': environment,
    'certificationStatus': 'PRODUCTION_READY',
    'posReady': true,
    'canActivateProduction': false,
  });

  @override
  Future<List<EcfSequenceInfo>> sequences() async => List.of(ranges);

  @override
  Future<List<EcfEligibleOriginal>> eligibleOriginals() async => [];

  @override
  Future<EcfAuthorizedSequencesView> authorizedSequences() async {
    authorizationReads++;
    return EcfAuthorizedSequencesView(
      environment: environment,
      items: List.of(declared),
      supportedTypes: const ['E31', 'E34'],
      declarationVersion: 'fixture-v1',
      declarationText: 'Declaración sintética de esta empresa y ambiente.',
    );
  }

  @override
  Future<void> declareAuthorizedSequence({
    required String documentType,
    String? expectedEnvironment,
    required String authorizationNumber,
    required int rangeFrom,
    required int rangeTo,
    required int approvedQuantity,
    String? expiresAt,
    required bool declarationAccepted,
  }) async {
    expect(expectedEnvironment, environment);
    expect(documentType, 'E34');
    expect(declarationAccepted, isTrue);
    declarations++;
    await declarationGate?.future;
    declared.add(
      EcfAuthorizedSequence(
        documentType: documentType,
        authorizationNumber: authorizationNumber,
        rangeFrom: rangeFrom,
        rangeTo: rangeTo,
        approvedQuantity: approvedQuantity,
        declarationVersion: 'fixture-v1',
      ),
    );
  }

  @override
  Future<void> registerSequence({
    required String documentType,
    String? expectedEnvironment,
    required int startNumber,
    required int endNumber,
    String? validUntil,
  }) async {
    expect(expectedEnvironment, environment);
    expect(documentType, 'E34');
    expect(startNumber, 1);
    expect(endNumber, 20);
    registrations++;
    ranges.add(
      EcfSequenceInfo(
        id: 'synthetic-e34',
        documentType: documentType,
        prefix: documentType,
        startNumber: startNumber,
        nextNumber: startNumber,
        endNumber: endNumber,
        active: true,
        consumed: 0,
        remaining: 20,
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    final fonts = FontLoader('Manrope');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts.addFont(
        rootBundle.load('assets/fonts/manrope/Manrope-$weight.ttf'),
      );
    }
    await fonts.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  final capture = GlobalKey();
  Future<_Auth> pump(
    WidgetTester tester,
    _Repo repo, {
    String role = 'ADMIN',
    double width = 1280,
  }) async {
    tester.view.physicalSize = Size(width, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late _Auth auth;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authStateProvider.overrideWith(
            (ref) => auth = _Auth(ref, role: role),
          ),
          ecfRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: RepaintBoundary(key: capture, child: const EcfConfigPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return auth;
  }

  Future<void> fillE34(WidgetTester tester) async {
    final another = find.byKey(const ValueKey('ecf_dgii_declare_another'));
    await tester.ensureVisible(another);
    await tester.tap(another);
    await tester.pumpAndSettle();
    for (final pair in [
      ('ecf_dgii_authorization_number', 'SYNTHETIC-E34-AUTHORIZATION'),
      ('ecf_dgii_from', '1'),
      ('ecf_dgii_to', '20'),
      ('ecf_dgii_approved', '20'),
    ]) {
      final field = find.byKey(ValueKey(pair.$1));
      await tester.ensureVisible(field);
      await tester.enterText(field, pair.$2);
    }
    final check = find.byKey(const ValueKey('ecf_dgii_declaration_check'));
    await tester.ensureVisible(check);
    await tester.tap(check);
    await tester.pump();
  }

  for (final environment in ['SANDBOX', 'PRODUCTION']) {
    testWidgets(
      'ready E31 company can add E34 from configuration in $environment',
      (tester) async {
        final repo = _Repo(environment: environment);
        await pump(tester, repo);
        await fillE34(tester);
        final save = find.byKey(const ValueKey('ecf_dgii_declaration_save'));
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(repo.declarations, 1);
        expect(repo.registrations, 1);
        expect(repo.ranges.first.nextNumber, 3);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'read-only user and disabled module do not load numbering management',
    (tester) async {
      for (final disabled in [false, true]) {
        final repo = _Repo(enabled: !disabled);
        await pump(tester, repo, role: disabled ? 'ADMIN' : 'CAJERO');
        expect(find.byType(EcfSequenceRangeSection), findsNothing);
        expect(repo.authorizationReads, 0);
        expect(find.text('Rangos de numeración'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'changing company cancels second numbering write from the previous form',
    (tester) async {
      final repo = _Repo()..declarationGate = Completer<void>();
      final auth = await pump(tester, repo);
      await fillE34(tester);
      final save = find.byKey(const ValueKey('ecf_dgii_declaration_save'));
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pump();
      expect(repo.declarations, 1);
      auth.replaceCompany('company-b');
      await tester.pump();
      repo.declarationGate!.complete();
      await tester.pumpAndSettle();
      expect(repo.registrations, 0);
      expect(find.text('SYNTHETIC-E34-AUTHORIZATION'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [390.0, 1280.0]) {
    testWidgets('numbering remains accessible and readable at $width', (
      tester,
    ) async {
      await pump(tester, _Repo(), width: width);
      final another = find.byKey(const ValueKey('ecf_dgii_declare_another'));
      await tester.ensureVisible(another);
      await tester.pumpAndSettle();
      expect(another.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      final output = Platform.environment['FULLPOS_CONFIG_NUMBERING_QA'];
      if (output != null) {
        await tester.runAsync(() async {
          final picture =
              await (capture.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await picture.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await Directory(output).create(recursive: true);
          await File(
            '$output/config-numbering-${width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          picture.dispose();
        });
      }
    });
  }
}
