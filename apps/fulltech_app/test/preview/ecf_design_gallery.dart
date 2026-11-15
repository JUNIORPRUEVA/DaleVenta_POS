// Local-only gallery of existing fiscal widgets. Synthetic data; no real IO.
import 'package:daleventa_pos/features/ecf/data/ecf_repository.dart';
import 'package:daleventa_pos/features/ecf/ecf_authorized_sequence_models.dart';
import 'package:daleventa_pos/features/ecf/ecf_dosa_activation_models.dart';
import 'package:daleventa_pos/features/ecf/ecf_models.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_config_page.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_documents_page.dart';
import 'package:daleventa_pos/features/ecf/ui/ecf_production_activation_action.dart';
import 'package:daleventa_pos/features/ecf/ui/flow/ecf_authorization_step.dart';
import 'package:daleventa_pos/features/ecf/ui/flow/ecf_completed_view.dart';
import 'package:daleventa_pos/features/ecf/ui/flow/ecf_dosa_activation_status.dart';
import 'package:daleventa_pos/features/ecf/ui/flow/ecf_dosa_tracking_step.dart';
import 'package:daleventa_pos/features/ecf/ui/flow/ecf_flow_kit.dart';
import 'package:daleventa_pos/features/ecf/ui/flow/ecf_sequence_range_section.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum FiscalPreviewScene {
  request('4. Seguimiento · solicitud'),
  tests('5. Seguimiento · pruebas'),
  certified('6. Seguimiento · certificación'),
  connectionError('7. Seguimiento · sin conexión'),
  authorization('8. Autorización · por firmar'),
  signed('9. Autorización · registrada'),
  production('10. Habilitar producción'),
  numbering('11. Numeración · agregar'),
  activeNumbering('12. Numeración · registrada'),
  expiredNumbering('13. Numeración · vencida'),
  completed('14. Proceso completado'),
  incomplete('15. Cierre · falta numeración'),
  documents('16. Comprobantes · con datos'),
  emptyDocuments('17. Comprobantes · vacíos'),
  documentError('18. Comprobantes · error'),
  configuration('19. Configuración fiscal');

  const FiscalPreviewScene(this.label);
  final String label;
}

class FiscalPreviewRepository extends EcfRepository {
  FiscalPreviewRepository(super.dio, this.scene);
  final FiscalPreviewScene scene;
  int localAuthorizations = 0;
  String get _environment =>
      {
        FiscalPreviewScene.numbering,
        FiscalPreviewScene.activeNumbering,
        FiscalPreviewScene.expiredNumbering,
        FiscalPreviewScene.configuration,
    FiscalPreviewScene.incomplete,
      }.contains(scene)
      ? 'PRODUCTION'
      : 'SANDBOX';
  bool get _hasNumbering => {
    FiscalPreviewScene.activeNumbering,
    FiscalPreviewScene.expiredNumbering,
    FiscalPreviewScene.configuration,
  }.contains(scene);
  DateTime get _expiry => scene == FiscalPreviewScene.expiredNumbering
      ? DateTime(2020)
      : DateTime.now().add(const Duration(days: 365));

  @override
  Future<EcfCapabilities> capabilities() async => EcfCapabilities.fromJson({
    'enabled': true,
    'environment': _environment,
    'certificationStatus': 'CERTIFIED',
    'productionEnabled': _environment == 'PRODUCTION',
    'canActivateProduction': scene == FiscalPreviewScene.production,
    'allowedTypes': ['E31', 'E32', 'E34'],
    'emissionPathAvailable': false,
    'documentTypes': <Object>[],
  });

  @override
  Future<EcfDosaActivationOutcome> attemptDosaActivation() async {
    if (scene == FiscalPreviewScene.connectionError) {
      throw StateError('Fallo de conexión simulado.');
    }
    final certified = scene == FiscalPreviewScene.certified;
    return EcfDosaActivationOutcome.fromJson({
      'ok': certified,
      'companyId': 'synthetic-design-company',
      'certificationStatus': certified ? 'AUTHORIZED_SANDBOX' : 'IN_PROGRESS',
      'changed': false,
      'environments': [
        {
          'environment': 'test',
          'status': certified ? 'ACTIVE' : 'PENDING_CONFIRMATION',
          'activated': false,
          'blockingReasons': certified
              ? <String>[]
              : ['ECF_DOSA_ACTIVATION_DGII_NOT_APPROVED'],
        },
      ],
    });
  }

  @override
  Future<void> recordDgiiAuthorization({
    required String source,
    String? evidenceId,
    String? externalId,
  }) async {
    localAuthorizations++;
  }

  @override
  Future<List<EcfEligibleOriginal>> eligibleOriginals() async => const [
    EcfEligibleOriginal(
      id: 'synthetic-invoice',
      documentType: 'E31',
      encf: 'E310000000001',
      availableAmount: '1180.00',
    ),
  ];

  @override
  Future<EcfAuthorizedSequencesView> authorizedSequences() async =>
      EcfAuthorizedSequencesView(
        environment: _environment,
        supportedTypes: const ['E31', 'E32', 'E34'],
        declarationVersion: 'preview-v1',
        declarationText:
            'Datos ficticios de revisión visual. Sin validez fiscal.',
        items: !_hasNumbering
            ? const []
            : [
                EcfAuthorizedSequence(
                  documentType: 'E31',
                  authorizationNumber: 'DEMO-VISUAL',
                  rangeFrom: 1,
                  rangeTo: 100,
                  approvedQuantity: 100,
                  declarationVersion: 'preview-v1',
                  expiresAt: _expiry,
                ),
              ],
      );

  @override
  Future<List<EcfSequenceInfo>> sequences() async => !_hasNumbering
      ? []
      : [
          EcfSequenceInfo(
            id: 'synthetic-sequence',
            documentType: 'E31',
            prefix: 'E31',
            startNumber: 1,
            nextNumber: 4,
            endNumber: 100,
            active: true,
            consumed: 3,
            remaining: 97,
            validUntil: _expiry,
          ),
        ];

  static Map<String, dynamic> documentJson(String id) {
    final credit = id == 'synthetic-credit';
    final rejected = id == 'synthetic-rejected';
    return {
      'id': id,
      'documentType': credit ? 'E34' : 'E31',
      'status': rejected ? 'DGII_REJECTED' : 'DGII_ACCEPTED',
      'statusGroup': rejected ? 'REJECTED' : 'ACCEPTED',
      'encf': credit
          ? 'E340000000001'
          : rejected
          ? 'E310000000002'
          : 'E310000000001',
      'createdAt': '2026-11-14T14:30:00Z',
      'total': credit ? '118.00' : '1180.00',
      'currency': 'DOP',
      'receiverName': 'Cliente ficticio · demostración',
      'receiverTaxId': '101000001',
      if (credit) 'originalEncf': 'E310000000001',
      if (rejected)
        'safeErrorMessage': 'Rechazo ficticio para revisar el diseño.',
      'statusLogs': <Object>[],
      'attempts': <Object>[],
    };
  }

  @override
  Future<EcfDocumentPage> listDocumentsPage({
    EcfDocumentFilter filter = EcfDocumentFilter.all,
    int take = 25,
    int skip = 0,
  }) async {
    if (scene == FiscalPreviewScene.documentError) {
      throw StateError('Consulta no disponible en este escenario ficticio.');
    }
    final items = scene == FiscalPreviewScene.emptyDocuments
        ? <EcfDocumentSummary>[]
        : ['synthetic-invoice', 'synthetic-credit', 'synthetic-rejected']
              .map(documentJson)
              .map(EcfDocumentSummary.fromJson)
              .where(
                (item) =>
                    (filter.documentType == null ||
                        item.documentType == filter.documentType) &&
                    (filter.group == null ||
                        filter.group!.apiValue.isEmpty ||
                        item.statusGroup.apiValue == filter.group!.apiValue) &&
                    (filter.search == null ||
                        '${item.encf} ${item.receiverName}'
                            .toLowerCase()
                            .contains(filter.search!.toLowerCase())),
              )
              .toList();
    return EcfDocumentPage(
      items: items.skip(skip).take(take).toList(),
      total: items.length,
      take: take,
      skip: skip,
    );
  }

  @override
  Future<EcfCounters> summary() async => EcfCounters.fromJson({
    'total': scene == FiscalPreviewScene.emptyDocuments ? 0 : 3,
    'byStatus': <String, int>{},
    'byGroup': {
      'ACCEPTED': scene == FiscalPreviewScene.emptyDocuments ? 0 : 2,
      'REJECTED': scene == FiscalPreviewScene.emptyDocuments ? 0 : 1,
    },
  });

  @override
  Future<EcfDocumentDetail> documentDetail(String id) async =>
      EcfDocumentDetail.fromJson(documentJson(id));
}

class EcfDesignGallery extends StatefulWidget {
  const EcfDesignGallery({super.key, required this.blockedDio});
  final Dio blockedDio;
  @override
  State<EcfDesignGallery> createState() => _EcfDesignGalleryState();
}

class _EcfDesignGalleryState extends State<EcfDesignGallery> {
  FiscalPreviewScene _scene = FiscalPreviewScene.request;
  late FiscalPreviewRepository _repository;
  @override
  void initState() {
    super.initState();
    _repository = FiscalPreviewRepository(widget.blockedDio, _scene);
  }

  void _select(FiscalPreviewScene scene) => setState(() {
    _scene = scene;
    _repository = FiscalPreviewRepository(widget.blockedDio, scene);
  });
  void _localAction() => ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Demostración local: no se abre ningún servicio real.'),
    ),
  );

  Widget _content() => switch (_scene) {
    FiscalPreviewScene.request ||
    FiscalPreviewScene.tests ||
    FiscalPreviewScene.certified ||
    FiscalPreviewScene.connectionError => EcfDosaTrackingStep(
      milestone: _scene == FiscalPreviewScene.request
          ? 0
          : _scene == FiscalPreviewScene.certified
          ? 2
          : 1,
      statusLabel: _scene == FiscalPreviewScene.certified
          ? 'Certificación completada'
          : 'En proceso',
      statusMessage:
          'Escenario ficticio para revisar el seguimiento de tu postulación.',
      official: _scene == FiscalPreviewScene.certified,
      activation: const EcfDosaActivationStatus(canManage: true),
      next: EcfPrimaryAction(
        label: 'Continuar a autorización',
        icon: Icons.arrow_forward_rounded,
        onPressed: () => _select(FiscalPreviewScene.authorization),
      ),
    ),
    FiscalPreviewScene.authorization ||
    FiscalPreviewScene.signed => SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: EcfAuthorizationStep(
        canAuthorize: true,
        alreadySigned: _scene == FiscalPreviewScene.signed,
        onSigned: () {},
      ),
    ),
    FiscalPreviewScene.production => const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: EcfProductionActivationAction(),
    ),
    FiscalPreviewScene.numbering ||
    FiscalPreviewScene.activeNumbering ||
    FiscalPreviewScene.expiredNumbering => const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: EcfSequenceRangeSection(canManage: true),
    ),
    FiscalPreviewScene.completed ||
    FiscalPreviewScene.incomplete => EcfCompletedView(
      invoicingReady: _scene == FiscalPreviewScene.completed,
      onGoToSales: _localAction,
      onViewDocuments: () => _select(FiscalPreviewScene.documents),
      numbering: const EcfSequenceRangeSection(canManage: true, embedded: true),
    ),
    FiscalPreviewScene.documents ||
    FiscalPreviewScene.emptyDocuments ||
    FiscalPreviewScene.documentError => const EcfDocumentsPage(),
    FiscalPreviewScene.configuration => const EcfConfigPage(),
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Revisión de pantallas fiscales')),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Pantalla anterior',
                onPressed: _scene.index == 0
                    ? null
                    : () =>
                          _select(FiscalPreviewScene.values[_scene.index - 1]),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: DropdownButton<FiscalPreviewScene>(
                  key: const ValueKey('fiscal_gallery_scene'),
                  isExpanded: true,
                  value: _scene,
                  items: [
                    for (final scene in FiscalPreviewScene.values)
                      DropdownMenuItem(value: scene, child: Text(scene.label)),
                  ],
                  onChanged: (value) {
                    if (value != null) _select(value);
                  },
                ),
              ),
              IconButton(
                tooltip: 'Pantalla siguiente',
                onPressed: _scene.index == FiscalPreviewScene.values.length - 1
                    ? null
                    : () =>
                          _select(FiscalPreviewScene.values[_scene.index + 1]),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        Expanded(
          child: ProviderScope(
            key: ValueKey(_repository),
            overrides: [
              ecfRepositoryProvider.overrideWithValue(_repository),
              ecfCapabilitiesProvider.overrideWith(
                (ref) => _repository.capabilities(),
              ),
              ecfSequencesProvider.overrideWith(
                (ref) => _repository.sequences(),
              ),
              ecfEligibleOriginalsProvider.overrideWith(
                (ref) => _repository.eligibleOriginals(),
              ),
              ecfCountersProvider.overrideWith((ref) => _repository.summary()),
              ecfDocumentsProvider.overrideWith(
                (ref, filter) => _repository.listDocumentsPage(filter: filter),
              ),
              ecfDocumentDetailProvider.overrideWith(
                (ref, id) => _repository.documentDetail(id),
              ),
            ],
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 940),
                    child: KeyedSubtree(
                      key: ValueKey(_scene),
                      child: _content(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
