// Isolated visual QA entry point. Not imported by main.dart or any app route.
// Uses the real widgets with synthetic in-memory data; never contacts an API.
import 'package:daleventa_pos/core/auth/auth_provider.dart';
import 'package:daleventa_pos/core/models/user_model.dart';
import 'package:daleventa_pos/core/theme/app_theme.dart';
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_authorized_sequence_models.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_production_activation_action.dart';
import 'package:daleventa_pos/features/ecf/ui/flow/ecf_sequence_range_section.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load();
  runApp(
    ProviderScope(
      overrides: [
        authStateProvider.overrideWith(_PreviewAuth.new),
        ecfRepositoryProvider.overrideWithValue(_Repository()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const _Page(),
      ),
    ),
  );
}

class _PreviewAuth extends AuthController {
  _PreviewAuth(super.ref) {
    state = AuthState(
      initialized: true,
      isAuthenticated: true,
      user: UserModel(
        id: 'synthetic-visual-user',
        companyId: 'synthetic-visual-company',
        email: 'visual@example.test',
        nombreCompleto: 'Administrador ficticio',
        telefono: '',
        role: 'ADMIN',
      ),
    );
  }
}

class _Repository extends EcfRepository {
  _Repository() : super(Dio());
  bool production = false;
  final authorizations = <EcfAuthorizedSequence>[];
  final ranges = <EcfSequenceInfo>[];
  @override
  Future<EcfCapabilities> capabilities() async => EcfCapabilities.fromJson({
    'enabled': true,
    'environment': production ? 'PRODUCTION' : 'SANDBOX',
    'certificationStatus': 'PRODUCTION_READY',
    'productionEnabled': production,
    'canActivateProduction': !production,
    'posReady': production && ranges.isNotEmpty,
    'posAvailableTypes': ranges.isEmpty ? <String>[] : ['E31'],
    'allowedTypes': ['E31', 'E34'],
    'emissionPathAvailable': production,
    'documentTypes': <Object>[],
    'e31SequenceDueDate': authorizations.isEmpty
        ? null
        : authorizations.first.expiresAt?.toIso8601String().substring(0, 10),
  });
  @override
  Future<void> enableProduction({required String expectedCompanyId}) async {
    production = true;
  }

  @override
  Future<EcfAuthorizedSequencesView>
  authorizedSequences() async => EcfAuthorizedSequencesView(
    environment: production ? 'PRODUCTION' : 'SANDBOX',
    items: List.of(authorizations),
    supportedTypes: const ['E31', 'E34'],
    declarationVersion: 'v1',
    declarationText:
        'Declaro que estos datos corresponden a la autorización de mi empresa.',
  );
  @override
  Future<List<EcfSequenceInfo>> sequences() async => List.of(ranges);
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
    authorizations.add(
      EcfAuthorizedSequence(
        documentType: documentType,
        authorizationNumber: authorizationNumber,
        rangeFrom: rangeFrom,
        rangeTo: rangeTo,
        approvedQuantity: approvedQuantity,
        declarationVersion: 'v1',
        expiresAt: expiresAt == null ? null : DateTime.parse(expiresAt),
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
    ranges.add(
      EcfSequenceInfo(
        id: 'synthetic-range',
        documentType: documentType,
        prefix: documentType,
        startNumber: startNumber,
        nextNumber: startNumber,
        endNumber: endNumber,
        active: true,
        consumed: 0,
        remaining: endNumber - startNumber + 1,
        validUntil: validUntil == null ? null : DateTime.parse(validUntil),
      ),
    );
  }
}

class _Page extends ConsumerWidget {
  const _Page();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(ecfCapabilitiesProvider).valueOrNull;
    final width =
        double.tryParse(Uri.base.queryParameters['width'] ?? '') ?? 700;
    return Scaffold(
      appBar: AppBar(title: const Text('Empresa ficticia · prueba local')),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Facturación electrónica',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (caps?.productionEnabled != true) ...[
                    const Text(
                      'Certificación completada. Habilita producción para registrar los comprobantes de esta empresa.',
                    ),
                    const SizedBox(height: 12),
                    const EcfProductionActivationAction(),
                  ] else ...[
                    const Text(
                      'Producción habilitada. Registra tu numeración autorizada.',
                    ),
                    const SizedBox(height: 12),
                    const EcfSequenceRangeSection(canManage: true),
                  ],
                  if (caps?.posReady == true) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Fecha E31 disponible para facturar: ${caps?.e31SequenceDueDate}',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
