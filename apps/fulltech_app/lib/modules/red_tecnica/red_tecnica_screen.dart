import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/routing/routes.dart';
import '../../core/utils/safe_url_launcher.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'data/red_tecnica_repository.dart';
import 'red_tecnica_models.dart';

const _rtBlue = Color(0xFF2563EB);
const _rtText = Color(0xFF0F172A);
const _rtMuted = Color(0xFF64748B);
const _rtLine = Color(0xFFE2E8F0);
const _rtSurface = Color(0xFFFFFFFF);
const _rtBackground = Color(0xFFF1F7FA);

const cameraSkills = [
  'Camaras analogicas',
  'Camaras IP',
  'DVR',
  'NVR',
  'BNC',
  'RJ45',
  'Configuracion en celulares',
  'Acceso remoto',
  'Cableado estructurado',
  'Diagnostico y mantenimiento',
];

const gateMotorSkills = [
  'Motores corredizos',
  'Motores batientes',
  'Cremalleras',
  'Programacion de controles',
  'Fotoceldas',
  'Lamparas',
  'Limites',
  'Electricidad basica',
  'Soldadura',
  'Diagnostico y mantenimiento',
];

const technicianTools = [
  'Taladro',
  'Rotomartillo',
  'Escalera',
  'Multimetro',
  'Ponchadora RJ45',
  'Herramientas manuales',
  'Pulidora',
  'Soldadora',
  'Laptop',
  'Probador de cable',
];

const transportOptions = ['Moto', 'Carro', 'Camioneta', 'No tengo transporte'];
const availabilityOptions = [
  'Disponible de lunes a sabado',
  'Disponible algunos dias',
  'Disponible fines de semana',
  'Disponible cuando sea contactado',
];

class RedTecnicaScreen extends ConsumerStatefulWidget {
  const RedTecnicaScreen({super.key});

  @override
  ConsumerState<RedTecnicaScreen> createState() => _RedTecnicaScreenState();
}

class _RedTecnicaScreenState extends ConsumerState<RedTecnicaScreen> {
  late Future<RedTecnicaSnapshot> _future;
  final _searchCtrl = TextEditingController();
  var _tab = 0;
  var _applicationStatusFilter = 'Todos';
  var _technicianFilter = 'Todos';
  RedTecnicaSpecialty? _specialtyFilter;
  var _showRegistrationPanel = false;
  String? _selectedApplicationId;
  String? _selectedTechnicianId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<RedTecnicaSnapshot> _load() {
    return ref.read(redTecnicaRepositoryProvider).snapshot();
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _copyPublicLink() async {
    final link = ref.read(redTecnicaRepositoryProvider).publicFormUrl;
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Enlace copiado: $link')));
  }

  Future<void> _openWhatsApp(String phone, String name) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;
    final message =
        'Hola, $name. Te contactamos de FullTech SRL porque tenemos un trabajo disponible. Estas disponible para recibir los detalles?';
    final uri = Uri(
      scheme: 'whatsapp',
      host: 'send',
      queryParameters: {'phone': _dominicanPhone(digits), 'text': message},
    );
    await safeOpenWhatsApp(context, uri);
  }

  Future<void> _call(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;
    await safeOpenUrl(context, Uri(scheme: 'tel', path: digits));
  }

  String _dominicanPhone(String digits) {
    if (digits.length == 10) return '1$digits';
    return digits;
  }

  Future<void> _approve(TechnicianApplication app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aprobar tecnico'),
        content: Text(
          'Deseas aprobar esta solicitud y agregar a ${app.fullName} a la Red Tecnica?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Aprobar tecnico'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final user = ref.read(authStateProvider).user;
      await ref
          .read(redTecnicaRepositoryProvider)
          .approveApplication(
            applicationId: app.id,
            reviewedBy: user?.nombreCompleto ?? user?.email ?? 'ADMIN',
          );
      _reload();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _reject(TechnicianApplication app) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rechazar solicitud'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Razon interna opcional',
            hintText: 'Informacion incompleta, duplicada, no cumple...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Rechazar'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (reason == null) return;
    try {
      final user = ref.read(authStateProvider).user;
      await ref
          .read(redTecnicaRepositoryProvider)
          .updateApplicationStatus(
            app.id,
            TechnicianApplicationStatus.rejected,
            reviewedBy: user?.nombreCompleto ?? user?.email ?? 'ADMIN',
            rejectionReason: reason,
          );
      _reload();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _setReviewing(TechnicianApplication app) async {
    try {
      final user = ref.read(authStateProvider).user;
      await ref
          .read(redTecnicaRepositoryProvider)
          .updateApplicationStatus(
            app.id,
            TechnicianApplicationStatus.reviewing,
            reviewedBy: user?.nombreCompleto ?? user?.email ?? 'ADMIN',
          );
      _reload();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _changeStatus(Technician tech, TechnicianStatus status) async {
    try {
      await ref
          .read(redTecnicaRepositoryProvider)
          .updateTechnician(tech.copyWith(status: status));
      _reload();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _toggleFavorite(Technician tech) async {
    await ref
        .read(redTecnicaRepositoryProvider)
        .updateTechnician(tech.copyWith(isFavorite: !tech.isFavorite));
    _reload();
  }

  Future<void> _openManualRegistration() async {
    final isCompact = MediaQuery.sizeOf(context).width < 980;
    if (!isCompact) {
      setState(() => _showRegistrationPanel = true);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _rtBackground,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.94,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
            ),
            child: _buildManualRegistrationForm(
              closeOnSubmit: () {
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildManualRegistrationForm({VoidCallback? closeOnSubmit}) {
    return _TechnicianApplicationForm(
      title: 'Registrar tecnico',
      submitLabel: 'Guardar tecnico',
      requireDocuments: false,
      allowStatusSelection: true,
      onSubmit: (draft, status) async {
        final now = DateTime.now();
        final technician = Technician(
          id: 'rt_${now.microsecondsSinceEpoch}',
          technicianCode: '',
          fullName: draft.fullName,
          identityNumber: draft.identityNumber,
          birthDate: draft.birthDate,
          phone: draft.phone,
          whatsapp: draft.whatsapp,
          email: draft.email,
          province: draft.province,
          municipality: draft.municipality,
          sector: draft.sector,
          specialty: draft.specialty,
          experienceLevel: draft.experienceLevel,
          experienceDescription: draft.experienceDescription,
          cameraSkills: draft.cameraSkills,
          gateMotorSkills: draft.gateMotorSkills,
          toolsAvailability: draft.toolsAvailability,
          tools: draft.tools,
          otherTools: draft.otherTools,
          transportation: draft.transportation,
          availability: draft.availability,
          availabilityNotes: draft.availabilityNotes,
          canTravel: draft.canTravel,
          canWorkWeekends: draft.canWorkWeekends,
          profilePhotoPath: draft.profilePhotoPath,
          identityDocumentPaths: [
            if ((draft.identityFrontPhotoPath ?? '').isNotEmpty)
              draft.identityFrontPhotoPath!,
            if ((draft.identityBackPhotoPath ?? '').isNotEmpty)
              draft.identityBackPhotoPath!,
          ],
          workEvidencePhotoPaths: draft.workEvidencePhotoPaths,
          status: status ?? TechnicianStatus.available,
          isFavorite: false,
          completedJobsCount: 0,
          rating: 0,
          internalNotes: draft.internalNotes,
          approvedAt: now,
          createdAt: now,
          updatedAt: now,
        );
        await ref
            .read(redTecnicaRepositoryProvider)
            .createTechnician(technician);
        closeOnSubmit?.call();
        if (mounted) setState(() => _showRegistrationPanel = false);
        _reload();
      },
    );
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString().replaceFirst('Bad state: ', ''))),
    );
  }

  List<TechnicianApplication> _filteredApplications(
    List<TechnicianApplication> items,
  ) {
    final query = _searchCtrl.text.trim().toLowerCase();
    return items.where((item) {
      final statusOk =
          _applicationStatusFilter == 'Todos' ||
          item.status.label == _applicationStatusFilter;
      final specialtyOk =
          _specialtyFilter == null || item.specialty == _specialtyFilter;
      final queryOk =
          query.isEmpty ||
          [
            item.fullName,
            item.phone,
            item.whatsapp,
            item.identityNumber,
            item.province,
            item.municipality,
          ].any((value) => value.toLowerCase().contains(query));
      return statusOk && specialtyOk && queryOk;
    }).toList();
  }

  List<Technician> _filteredTechnicians(List<Technician> items) {
    final query = _searchCtrl.text.trim().toLowerCase();
    return items.where((item) {
      final filterOk = switch (_technicianFilter) {
        'Favoritos' => item.isFavorite,
        'Disponibles' => item.status == TechnicianStatus.available,
        'Camaras' => item.specialty == RedTecnicaSpecialty.cameras,
        'Motores' => item.specialty == RedTecnicaSpecialty.gateMotors,
        'Ambas areas' => item.specialty == RedTecnicaSpecialty.both,
        'Con herramientas' => item.toolsAvailability != ToolsAvailability.no,
        'Con transporte' => item.transportation != 'No tengo transporte',
        _ => true,
      };
      final specialtyOk =
          _specialtyFilter == null || item.specialty == _specialtyFilter;
      final queryOk =
          query.isEmpty ||
          [
            item.fullName,
            item.phone,
            item.whatsapp,
            item.identityNumber,
            item.province,
            item.municipality,
          ].any((value) => value.toLowerCase().contains(query));
      return filterOk && specialtyOk && queryOk;
    }).toList();
  }

  TechnicianApplication? _selectedApplication(
    List<TechnicianApplication> items,
  ) {
    for (final item in items) {
      if (item.id == _selectedApplicationId) return item;
    }
    return null;
  }

  Technician? _selectedTechnician(List<Technician> items) {
    for (final item in items) {
      if (item.id == _selectedTechnicianId) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Red Tecnica',
        fallbackRoute: Routes.home,
        preferDrawerLeading: true,
        showLogo: false,
        showDepartmentLabel: false,
        bottom: _RedTecnicaTabBar(
          tab: _tab,
          onChanged: (value) => setState(() {
            _tab = value;
            _selectedApplicationId = null;
            _selectedTechnicianId = null;
          }),
        ),
        actions: [
          IconButton(
            tooltip: 'Copiar formulario publico',
            onPressed: _copyPublicLink,
            icon: const Icon(Icons.link_rounded),
          ),
          IconButton(
            tooltip: 'Registrar tecnico',
            onPressed: _openManualRegistration,
            icon: const Icon(Icons.person_add_alt_1_rounded),
          ),
        ],
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: FutureBuilder<RedTecnicaSnapshot>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'No se pudo cargar la Red Tecnica',
              message: snapshot.error.toString(),
              actionLabel: 'Reintentar',
              onAction: _reload,
            );
          }
          final data =
              snapshot.data ??
              const RedTecnicaSnapshot(
                applications: [],
                technicians: [],
                jobs: [],
                evaluations: [],
              );
          final applications = _filteredApplications(data.applications);
          final technicians = _filteredTechnicians(data.technicians);
          final publicLink = ref
              .read(redTecnicaRepositoryProvider)
              .publicFormUrl;
          return LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 980;
              final content = _RedTecnicaWorkspace(
                toolbar: _Toolbar(
                  controller: _searchCtrl,
                  tab: _tab,
                  applicationStatusFilter: _applicationStatusFilter,
                  technicianFilter: _technicianFilter,
                  specialtyFilter: _specialtyFilter,
                  onChanged: () => setState(() {}),
                  onApplicationStatusChanged: (value) =>
                      setState(() => _applicationStatusFilter = value),
                  onTechnicianFilterChanged: (value) =>
                      setState(() => _technicianFilter = value),
                  onSpecialtyChanged: (value) =>
                      setState(() => _specialtyFilter = value),
                ),
                body: RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: switch (_tab) {
                      0 => _DashboardTab(
                        key: const ValueKey('dashboard'),
                        data: data,
                        onCopyPublicLink: _copyPublicLink,
                        onRegister: _openManualRegistration,
                        onTab: (value) => setState(() => _tab = value),
                      ),
                      1 => _ApplicationsTab(
                        key: const ValueKey('applications'),
                        items: applications,
                        onCall: _call,
                        onWhatsApp: _openWhatsApp,
                        onReviewing: _setReviewing,
                        onApprove: _approve,
                        onReject: _reject,
                        selectedId: isWide ? _selectedApplicationId : null,
                        onOpen: (item) {
                          if (isWide) {
                            setState(() => _selectedApplicationId = item.id);
                          } else {
                            _showApplicationDetail(item);
                          }
                        },
                        detail: null,
                      ),
                      _ => _TechniciansTab(
                        key: const ValueKey('technicians'),
                        items: technicians,
                        jobs: data.jobs,
                        evaluations: data.evaluations,
                        onCall: _call,
                        onWhatsApp: _openWhatsApp,
                        onFavorite: _toggleFavorite,
                        onStatus: _changeStatus,
                        selectedId: isWide ? _selectedTechnicianId : null,
                        onOpen: (item) {
                          if (isWide) {
                            setState(() => _selectedTechnicianId = item.id);
                          } else {
                            _showTechnicianProfile(
                              item,
                              data.jobs
                                  .where((job) => job.technicianId == item.id)
                                  .toList(),
                              data.evaluations
                                  .where((ev) => ev.technicianId == item.id)
                                  .toList(),
                            );
                          }
                        },
                        detail: null,
                      ),
                    },
                  ),
                ),
              );
              final sideWidth = (constraints.maxWidth * .34).clamp(
                500.0,
                650.0,
              );
              if (!isWide) return content;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: content),
                  SizedBox(
                    width: sideWidth,
                    child: _rightPanel(
                      publicLink: publicLink,
                      applications: applications,
                      technicians: technicians,
                      jobs: data.jobs,
                      evaluations: data.evaluations,
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: _tab == 2
          ? FloatingActionButton.extended(
              onPressed: _openManualRegistration,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Registrar'),
            )
          : null,
      backgroundColor: _rtBackground,
    );
  }

  Widget _rightPanel({
    required String publicLink,
    required List<TechnicianApplication> applications,
    required List<Technician> technicians,
    required List<TechnicianJob> jobs,
    required List<TechnicianEvaluation> evaluations,
  }) {
    if (_showRegistrationPanel) {
      return _RightActionPanel(
        publicLink: publicLink,
        showForm: true,
        onCopyPublicLink: _copyPublicLink,
        onRegister: _openManualRegistration,
        onCloseForm: () => setState(() => _showRegistrationPanel = false),
        form: _buildManualRegistrationForm(),
      );
    }

    if (_tab == 1) {
      return _ApplicationSidePanel(
        application: _selectedApplication(applications),
        onCall: _call,
        onWhatsApp: _openWhatsApp,
        onReviewing: _setReviewing,
        onApprove: _approve,
        onReject: _reject,
      );
    }

    if (_tab == 2) {
      return _TechnicianSidePanel(
        technician: _selectedTechnician(technicians),
        jobs: jobs,
        evaluations: evaluations,
        onCall: _call,
        onWhatsApp: _openWhatsApp,
        onFavorite: _toggleFavorite,
        onStatus: _changeStatus,
        onAddJob: (job) async {
          await ref.read(redTecnicaRepositoryProvider).addJob(job);
          _reload();
        },
        onAddEvaluation: (evaluation) async {
          await ref
              .read(redTecnicaRepositoryProvider)
              .addEvaluation(evaluation);
          _reload();
        },
      );
    }

    return _RightActionPanel(
      publicLink: publicLink,
      showForm: false,
      onCopyPublicLink: _copyPublicLink,
      onRegister: _openManualRegistration,
      onCloseForm: () => setState(() => _showRegistrationPanel = false),
      form: _buildManualRegistrationForm(),
    );
  }

  void _showApplicationDetail(TechnicianApplication app) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _ApplicationDetailSheet(
        application: app,
        onCall: _call,
        onWhatsApp: _openWhatsApp,
        onReviewing: _setReviewing,
        onApprove: _approve,
        onReject: _reject,
      ),
    );
  }

  void _showTechnicianProfile(
    Technician technician,
    List<TechnicianJob> jobs,
    List<TechnicianEvaluation> evaluations,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _TechnicianProfileSheet(
        technician: technician,
        jobs: jobs,
        evaluations: evaluations,
        onCall: _call,
        onWhatsApp: _openWhatsApp,
        onFavorite: _toggleFavorite,
        onStatus: _changeStatus,
        onAddJob: (job) async {
          await ref.read(redTecnicaRepositoryProvider).addJob(job);
          _reload();
        },
        onAddEvaluation: (evaluation) async {
          await ref
              .read(redTecnicaRepositoryProvider)
              .addEvaluation(evaluation);
          _reload();
        },
      ),
    );
  }
}

class RedTecnicaPublicFormScreen extends ConsumerStatefulWidget {
  const RedTecnicaPublicFormScreen({super.key});

  @override
  ConsumerState<RedTecnicaPublicFormScreen> createState() =>
      _RedTecnicaPublicFormScreenState();
}

class _RedTecnicaPublicFormScreenState
    extends ConsumerState<RedTecnicaPublicFormScreen> {
  TechnicianApplication? _sent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: _rtBackground,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: _sent == null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (MediaQuery.sizeOf(context).width >= 900) ...[
                          Expanded(
                            flex: 4,
                            child: _PublicFormIntroCard(
                              onCopyLink: () async {
                                final link = ref
                                    .read(redTecnicaRepositoryProvider)
                                    .publicFormUrl;
                                await Clipboard.setData(
                                  ClipboardData(text: link),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 14),
                        ],
                        Expanded(
                          flex: 6,
                          child: _ShellCard(
                            padding: EdgeInsets.zero,
                            child: _TechnicianApplicationForm(
                              title: 'Solicitud Red Tecnica FullTech',
                              submitLabel: 'Enviar solicitud',
                              requireDocuments: true,
                              onSubmit: (draft, _) async {
                                final saved = await ref
                                    .read(redTecnicaRepositoryProvider)
                                    .submitApplication(draft);
                                if (mounted) setState(() => _sent = saved);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : _ShellCard(
                    margin: const EdgeInsets.all(18),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 64,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Solicitud recibida correctamente',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Gracias por tu interes en formar parte de la Red Tecnica FullTech. Revisaremos tus datos y nos comunicaremos contigo cuando sea necesario.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 18),
                          Chip(
                            avatar: const Icon(Icons.confirmation_number),
                            label: Text('Numero: ${_sent!.applicationCode}'),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _PublicFormIntroCard extends StatelessWidget {
  const _PublicFormIntroCard({required this.onCopyLink});

  final VoidCallback onCopyLink;

  @override
  Widget build(BuildContext context) {
    return _ShellCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.engineering_outlined, color: _rtBlue),
          ),
          const SizedBox(height: 18),
          const Text(
            'Red Tecnica FullTech',
            style: TextStyle(
              color: _rtText,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Formulario para evaluar tecnicos independientes de camaras, automatizaciones y servicios de soporte.',
            style: TextStyle(color: _rtMuted, height: 1.4),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: onCopyLink,
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar enlace'),
          ),
        ],
      ),
    );
  }
}

class _RedTecnicaWorkspace extends StatelessWidget {
  const _RedTecnicaWorkspace({required this.toolbar, required this.body});

  final Widget toolbar;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
          decoration: const BoxDecoration(
            color: _rtSurface,
            border: Border(bottom: BorderSide(color: _rtLine)),
          ),
          child: toolbar,
        ),
        Expanded(child: body),
      ],
    );
  }
}

class _RedTecnicaTabBar extends StatelessWidget implements PreferredSizeWidget {
  const _RedTecnicaTabBar({required this.tab, required this.onChanged});

  final int tab;
  final ValueChanged<int> onChanged;

  @override
  Size get preferredSize => const Size.fromHeight(46);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Container(
        height: preferredSize.height,
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: _rtLine)),
        ),
        child: Row(
          children: [
            _TopTabButton(
              selected: tab == 0,
              icon: Icons.dashboard_outlined,
              label: 'Panel',
              onTap: () => onChanged(0),
            ),
            _TopTabButton(
              selected: tab == 1,
              icon: Icons.inbox_outlined,
              label: 'Solicitudes',
              onTap: () => onChanged(1),
            ),
            _TopTabButton(
              selected: tab == 2,
              icon: Icons.engineering_outlined,
              label: 'Tecnicos activos',
              onTap: () => onChanged(2),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopTabButton extends StatelessWidget {
  const _TopTabButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: double.infinity,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF1FF) : Colors.white,
            border: Border(
              bottom: BorderSide(
                color: selected ? _rtBlue : Colors.transparent,
                width: 2,
              ),
              right: const BorderSide(color: _rtLine),
            ),
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: selected ? _rtBlue : _rtText),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? _rtBlue : _rtText,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RightActionPanel extends StatelessWidget {
  const _RightActionPanel({
    required this.publicLink,
    required this.showForm,
    required this.onCopyPublicLink,
    required this.onRegister,
    required this.onCloseForm,
    required this.form,
  });

  final String publicLink;
  final bool showForm;
  final VoidCallback onCopyPublicLink;
  final VoidCallback onRegister;
  final VoidCallback onCloseForm;
  final Widget form;

  @override
  Widget build(BuildContext context) {
    if (showForm) {
      return _RightPanelFrame(
        child: _ShellCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Row(
                  children: [
                    const Icon(Icons.person_add_alt_1_rounded, color: _rtBlue),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Nuevo tecnico',
                        style: TextStyle(
                          color: _rtText,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar formulario',
                      onPressed: onCloseForm,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: _rtLine),
              Expanded(child: form),
            ],
          ),
        ),
      );
    }

    return _RightPanelFrame(
      child: _ShellCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF1FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.hub_outlined, color: _rtBlue),
            ),
            const SizedBox(height: 14),
            const Text(
              'Formulario publico',
              style: TextStyle(
                color: _rtText,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Comparte este enlace para recibir solicitudes de tecnicos externos directamente en FullTech.',
              style: TextStyle(color: _rtMuted, height: 1.35),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _rtLine),
              ),
              child: SelectableText(
                publicLink,
                style: const TextStyle(
                  color: _rtText,
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onCopyPublicLink,
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copiar enlace'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onRegister,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Registrar manualmente'),
              ),
            ),
            const SizedBox(height: 18),
            const _PanelHint(
              icon: Icons.verified_user_outlined,
              title: 'Flujo recomendado',
              detail:
                  'Revisa cada solicitud, valida datos y aprueba solo perfiles listos para recibir trabajos.',
            ),
            const SizedBox(height: 10),
            const _PanelHint(
              icon: Icons.phone_in_talk_outlined,
              title: 'Contacto rapido',
              detail:
                  'Desde cada tarjeta puedes llamar o escribir por WhatsApp sin salir del modulo.',
            ),
          ],
        ),
      ),
    );
  }
}

class _RightPanelFrame extends StatelessWidget {
  const _RightPanelFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: double.infinity,
      decoration: const BoxDecoration(
        color: _rtBackground,
        border: Border(left: BorderSide(color: _rtLine)),
      ),
      child: SafeArea(
        left: false,
        child: Padding(padding: const EdgeInsets.all(12), child: child),
      ),
    );
  }
}

class _PanelHint extends StatelessWidget {
  const _PanelHint({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: _rtBlue),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _rtText,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: const TextStyle(
                  color: _rtMuted,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({
    super.key,
    required this.data,
    required this.onCopyPublicLink,
    required this.onRegister,
    required this.onTab,
  });

  final RedTecnicaSnapshot data;
  final VoidCallback onCopyPublicLink;
  final VoidCallback onRegister;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    final apps = data.applications;
    final techs = data.technicians;
    final cards = [
      ('Solicitudes', apps.length, Icons.inbox_outlined),
      (
        'Pendientes',
        apps
            .where((item) => item.status == TechnicianApplicationStatus.pending)
            .length,
        Icons.pending_actions_rounded,
      ),
      (
        'Tecnicos activos',
        techs.where((item) => item.status != TechnicianStatus.inactive).length,
        Icons.engineering_outlined,
      ),
      (
        'Inactivos',
        techs.where((item) => item.status == TechnicianStatus.inactive).length,
        Icons.person_off_outlined,
      ),
      (
        'Camaras',
        techs
            .where(
              (item) =>
                  item.specialty == RedTecnicaSpecialty.cameras ||
                  item.specialty == RedTecnicaSpecialty.both,
            )
            .length,
        Icons.videocam_outlined,
      ),
      (
        'Motores',
        techs
            .where(
              (item) =>
                  item.specialty == RedTecnicaSpecialty.gateMotors ||
                  item.specialty == RedTecnicaSpecialty.both,
            )
            .length,
        Icons.garage_outlined,
      ),
      (
        'Disponibles',
        techs.where((item) => item.status == TechnicianStatus.available).length,
        Icons.verified_user_outlined,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1180
            ? 4
            : width >= 840
            ? 3
            : width >= 560
            ? 2
            : 1;
        final itemWidth = (width - 32 - ((columns - 1) * 10)) / columns;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final card in cards)
                  SizedBox(
                    width: itemWidth,
                    child: _StatCard(
                      title: card.$1,
                      value: '${card.$2}',
                      icon: card.$3,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            _ShellCard(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: () => onTab(1),
                    icon: const Icon(Icons.inbox_outlined),
                    label: const Text('Ver solicitudes'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => onTab(2),
                    icon: const Icon(Icons.engineering_outlined),
                    label: const Text('Ver tecnicos activos'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onRegister,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Registrar tecnico'),
                  ),
                  OutlinedButton.icon(
                    onPressed: onCopyPublicLink,
                    icon: const Icon(Icons.link_rounded),
                    label: const Text('Copiar enlace publico'),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ApplicationsTab extends StatelessWidget {
  const _ApplicationsTab({
    super.key,
    required this.items,
    required this.onCall,
    required this.onWhatsApp,
    required this.onReviewing,
    required this.onApprove,
    required this.onReject,
    required this.onOpen,
    this.selectedId,
    this.detail,
  });

  final List<TechnicianApplication> items;
  final ValueChanged<String> onCall;
  final void Function(String phone, String name) onWhatsApp;
  final ValueChanged<TechnicianApplication> onReviewing;
  final ValueChanged<TechnicianApplication> onApprove;
  final ValueChanged<TechnicianApplication> onReject;
  final ValueChanged<TechnicianApplication> onOpen;
  final String? selectedId;
  final Widget? detail;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyState(
        icon: Icons.inbox_outlined,
        title: 'Sin solicitudes',
        message: 'Cuando un tecnico envie el formulario aparecera aqui.',
      );
    }
    final list = ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        return _ApplicationCard(
          item: item,
          selected: item.id == selectedId,
          onCall: () => onCall(item.phone),
          onWhatsApp: () => onWhatsApp(item.whatsapp, item.fullName),
          onReviewing: () => onReviewing(item),
          onApprove: () => onApprove(item),
          onReject: () => onReject(item),
          onOpen: () => onOpen(item),
        );
      },
    );
    if (detail == null) return list;
    return Row(
      children: [
        Expanded(child: list),
        SizedBox(width: 430, child: detail),
      ],
    );
  }
}

class _TechniciansTab extends StatelessWidget {
  const _TechniciansTab({
    super.key,
    required this.items,
    required this.jobs,
    required this.evaluations,
    required this.onCall,
    required this.onWhatsApp,
    required this.onFavorite,
    required this.onStatus,
    required this.onOpen,
    this.selectedId,
    this.detail,
  });

  final List<Technician> items;
  final List<TechnicianJob> jobs;
  final List<TechnicianEvaluation> evaluations;
  final ValueChanged<String> onCall;
  final void Function(String phone, String name) onWhatsApp;
  final ValueChanged<Technician> onFavorite;
  final void Function(Technician tech, TechnicianStatus status) onStatus;
  final ValueChanged<Technician> onOpen;
  final String? selectedId;
  final Widget? detail;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyState(
        icon: Icons.engineering_outlined,
        title: 'Sin tecnicos activos',
        message: 'Aprueba una solicitud o registra un tecnico manualmente.',
      );
    }
    final list = ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        return _TechnicianCard(
          item: item,
          selected: item.id == selectedId,
          onCall: () => onCall(item.phone),
          onWhatsApp: () => onWhatsApp(item.whatsapp, item.fullName),
          onFavorite: () => onFavorite(item),
          onStatus: (status) => onStatus(item, status),
          onOpen: () => onOpen(item),
        );
      },
    );
    if (detail == null) return list;
    return Row(
      children: [
        Expanded(child: list),
        SizedBox(width: 430, child: detail),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.tab,
    required this.applicationStatusFilter,
    required this.technicianFilter,
    required this.specialtyFilter,
    required this.onChanged,
    required this.onApplicationStatusChanged,
    required this.onTechnicianFilterChanged,
    required this.onSpecialtyChanged,
  });

  final TextEditingController controller;
  final int tab;
  final String applicationStatusFilter;
  final String technicianFilter;
  final RedTecnicaSpecialty? specialtyFilter;
  final VoidCallback onChanged;
  final ValueChanged<String> onApplicationStatusChanged;
  final ValueChanged<String> onTechnicianFilterChanged;
  final ValueChanged<RedTecnicaSpecialty?> onSpecialtyChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: compact ? constraints.maxWidth : 360,
              child: TextField(
                controller: controller,
                onChanged: (_) => onChanged(),
                decoration: _rtInputDecoration(
                  'Buscar',
                  hint: 'Nombre, telefono, cedula o provincia',
                  icon: Icons.search_rounded,
                ),
              ),
            ),
            if (tab == 1)
              SizedBox(
                width: compact ? (constraints.maxWidth - 10) / 2 : 190,
                child: DropdownButtonFormField<String>(
                  initialValue: applicationStatusFilter,
                  decoration: _rtInputDecoration('Estado'),
                  items:
                      [
                        'Todos',
                        ...TechnicianApplicationStatus.values.map(
                          (e) => e.label,
                        ),
                      ].map((value) {
                        return DropdownMenuItem(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                  onChanged: (value) =>
                      onApplicationStatusChanged(value ?? 'Todos'),
                ),
              ),
            if (tab == 2)
              SizedBox(
                width: compact ? (constraints.maxWidth - 10) / 2 : 190,
                child: DropdownButtonFormField<String>(
                  initialValue: technicianFilter,
                  decoration: _rtInputDecoration('Filtro'),
                  items:
                      const [
                        'Todos',
                        'Favoritos',
                        'Disponibles',
                        'Camaras',
                        'Motores',
                        'Ambas areas',
                        'Con herramientas',
                        'Con transporte',
                      ].map((value) {
                        return DropdownMenuItem(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                  onChanged: (value) =>
                      onTechnicianFilterChanged(value ?? 'Todos'),
                ),
              ),
            SizedBox(
              width: compact ? (constraints.maxWidth - 10) / 2 : 190,
              child: DropdownButtonFormField<RedTecnicaSpecialty?>(
                initialValue: specialtyFilter,
                decoration: _rtInputDecoration('Especialidad'),
                items: [
                  const DropdownMenuItem<RedTecnicaSpecialty?>(
                    value: null,
                    child: Text('Todas'),
                  ),
                  ...RedTecnicaSpecialty.values.map(
                    (item) => DropdownMenuItem<RedTecnicaSpecialty?>(
                      value: item,
                      child: Text(item.label),
                    ),
                  ),
                ],
                onChanged: onSpecialtyChanged,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({
    required this.item,
    this.selected = false,
    required this.onCall,
    required this.onWhatsApp,
    required this.onReviewing,
    required this.onApprove,
    required this.onReject,
    required this.onOpen,
  });

  final TechnicianApplication item;
  final bool selected;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;
  final VoidCallback onReviewing;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        return _ShellCard(
          padding: EdgeInsets.zero,
          highlighted: selected,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            leading: _Avatar(path: item.profilePhotoPath, name: item.fullName),
            title: Text(
              item.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              '${item.phone} • ${item.province}, ${item.municipality}\n${item.specialty.label} • ${item.experienceLevel.label}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: true,
            trailing: compact
                ? PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'view') onOpen();
                      if (value == 'call') onCall();
                      if (value == 'wa') onWhatsApp();
                      if (value == 'review') onReviewing();
                      if (value == 'approve') onApprove();
                      if (value == 'reject') onReject();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'view',
                        child: Text('Ver solicitud'),
                      ),
                      PopupMenuItem(value: 'call', child: Text('Llamar')),
                      PopupMenuItem(value: 'wa', child: Text('WhatsApp')),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'review',
                        child: Text('En revision'),
                      ),
                      PopupMenuItem(value: 'approve', child: Text('Aprobar')),
                      PopupMenuItem(value: 'reject', child: Text('Rechazar')),
                    ],
                  )
                : Wrap(
                    spacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _StatusChip(
                        label: item.status.label,
                        color: _appStatusColor(item.status),
                      ),
                      IconButton(
                        onPressed: onCall,
                        icon: const Icon(Icons.call_outlined),
                      ),
                      IconButton(
                        onPressed: onWhatsApp,
                        icon: const Icon(Icons.chat_outlined),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'view') onOpen();
                          if (value == 'review') onReviewing();
                          if (value == 'approve') onApprove();
                          if (value == 'reject') onReject();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'view',
                            child: Text('Ver solicitud'),
                          ),
                          PopupMenuItem(
                            value: 'review',
                            child: Text('Marcar en revision'),
                          ),
                          PopupMenuItem(
                            value: 'approve',
                            child: Text('Aprobar'),
                          ),
                          PopupMenuItem(
                            value: 'reject',
                            child: Text('Rechazar'),
                          ),
                        ],
                      ),
                    ],
                  ),
            onTap: onOpen,
          ),
        );
      },
    );
  }
}

class _TechnicianCard extends StatelessWidget {
  const _TechnicianCard({
    required this.item,
    this.selected = false,
    required this.onCall,
    required this.onWhatsApp,
    required this.onFavorite,
    required this.onStatus,
    required this.onOpen,
  });

  final Technician item;
  final bool selected;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;
  final VoidCallback onFavorite;
  final ValueChanged<TechnicianStatus> onStatus;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 780;
        return _ShellCard(
          padding: EdgeInsets.zero,
          highlighted: selected,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 8,
            ),
            leading: _Avatar(path: item.profilePhotoPath, name: item.fullName),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    '${item.fullName} • ${item.technicianCode}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                if (item.isFavorite)
                  const Icon(
                    Icons.star_rounded,
                    color: Color(0xFFF59E0B),
                    size: 18,
                  ),
              ],
            ),
            subtitle: Text(
              '${item.phone} • ${item.province}, ${item.municipality}\n${item.specialty.label} • ${item.toolsAvailability.label} herramientas • ${item.transportation}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            isThreeLine: true,
            trailing: compact
                ? PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'profile') onOpen();
                      if (value == 'call') onCall();
                      if (value == 'wa') onWhatsApp();
                      if (value == 'favorite') onFavorite();
                      if (value == 'available') {
                        onStatus(TechnicianStatus.available);
                      }
                      if (value == 'busy') onStatus(TechnicianStatus.busy);
                      if (value == 'unavailable') {
                        onStatus(TechnicianStatus.unavailable);
                      }
                      if (value == 'inactive') {
                        onStatus(TechnicianStatus.inactive);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'profile',
                        child: Text('Ver perfil'),
                      ),
                      const PopupMenuItem(value: 'call', child: Text('Llamar')),
                      const PopupMenuItem(value: 'wa', child: Text('WhatsApp')),
                      PopupMenuItem(
                        value: 'favorite',
                        child: Text(
                          item.isFavorite
                              ? 'Quitar favorito'
                              : 'Marcar favorito',
                        ),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'available',
                        child: Text('Disponible'),
                      ),
                      const PopupMenuItem(
                        value: 'busy',
                        child: Text('Ocupado'),
                      ),
                      const PopupMenuItem(
                        value: 'unavailable',
                        child: Text('No disponible'),
                      ),
                      const PopupMenuItem(
                        value: 'inactive',
                        child: Text('Desactivar'),
                      ),
                    ],
                  )
                : Wrap(
                    spacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _StatusChip(
                        label: item.status.label,
                        color: _techStatusColor(item.status),
                      ),
                      Text('${item.completedJobsCount} trabajos'),
                      if (item.rating > 0)
                        Text('* ${item.rating.toStringAsFixed(1)}'),
                      IconButton(
                        onPressed: onCall,
                        icon: const Icon(Icons.call_outlined),
                      ),
                      IconButton(
                        onPressed: onWhatsApp,
                        icon: const Icon(Icons.chat_outlined),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'profile') onOpen();
                          if (value == 'favorite') onFavorite();
                          if (value == 'available') {
                            onStatus(TechnicianStatus.available);
                          }
                          if (value == 'busy') onStatus(TechnicianStatus.busy);
                          if (value == 'unavailable') {
                            onStatus(TechnicianStatus.unavailable);
                          }
                          if (value == 'inactive') {
                            onStatus(TechnicianStatus.inactive);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'profile',
                            child: Text('Ver perfil'),
                          ),
                          PopupMenuItem(
                            value: 'favorite',
                            child: Text(
                              item.isFavorite
                                  ? 'Quitar favorito'
                                  : 'Marcar favorito',
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'available',
                            child: Text('Disponible'),
                          ),
                          const PopupMenuItem(
                            value: 'busy',
                            child: Text('Ocupado'),
                          ),
                          const PopupMenuItem(
                            value: 'unavailable',
                            child: Text('No disponible'),
                          ),
                          const PopupMenuItem(
                            value: 'inactive',
                            child: Text('Desactivar'),
                          ),
                        ],
                      ),
                    ],
                  ),
            onTap: onOpen,
          ),
        );
      },
    );
  }
}

class _ApplicationDetailSheet extends StatelessWidget {
  const _ApplicationDetailSheet({
    required this.application,
    required this.onCall,
    required this.onWhatsApp,
    required this.onReviewing,
    required this.onApprove,
    required this.onReject,
    this.embedded = false,
  });

  final TechnicianApplication application;
  final ValueChanged<String> onCall;
  final void Function(String phone, String name) onWhatsApp;
  final ValueChanged<TechnicianApplication> onReviewing;
  final ValueChanged<TechnicianApplication> onApprove;
  final ValueChanged<TechnicianApplication> onReject;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return _DetailShell(
      embedded: embedded,
      title: application.fullName,
      subtitle: '${application.applicationCode} • ${application.status.label}',
      actions: [
        IconButton(
          onPressed: () => onCall(application.phone),
          icon: const Icon(Icons.call_outlined),
        ),
        IconButton(
          onPressed: () =>
              onWhatsApp(application.whatsapp, application.fullName),
          icon: const Icon(Icons.chat_outlined),
        ),
        TextButton(
          onPressed: () => onReviewing(application),
          child: const Text('En revision'),
        ),
        FilledButton(
          onPressed: () => onApprove(application),
          child: const Text('Aprobar'),
        ),
        TextButton(
          onPressed: () => onReject(application),
          child: const Text('Rechazar'),
        ),
      ],
      children: [
        _InfoGrid(rows: _applicationRows(application)),
        _SkillSection(
          title: 'Conocimientos',
          cameraSkills: application.cameraSkills,
          gateMotorSkills: application.gateMotorSkills,
        ),
        _EvidenceSection(
          paths: [
            if ((application.profilePhotoPath ?? '').isNotEmpty)
              application.profilePhotoPath!,
            if ((application.identityFrontPhotoPath ?? '').isNotEmpty)
              application.identityFrontPhotoPath!,
            if ((application.identityBackPhotoPath ?? '').isNotEmpty)
              application.identityBackPhotoPath!,
            ...application.workEvidencePhotoPaths,
          ],
        ),
      ],
    );
  }
}

class _ApplicationSidePanel extends StatelessWidget {
  const _ApplicationSidePanel({
    required this.application,
    required this.onCall,
    required this.onWhatsApp,
    required this.onReviewing,
    required this.onApprove,
    required this.onReject,
  });

  final TechnicianApplication? application;
  final ValueChanged<String> onCall;
  final void Function(String phone, String name) onWhatsApp;
  final ValueChanged<TechnicianApplication> onReviewing;
  final ValueChanged<TechnicianApplication> onApprove;
  final ValueChanged<TechnicianApplication> onReject;

  @override
  Widget build(BuildContext context) {
    final item = application;
    return _SideDetailFrame(
      emptyTitle: 'Selecciona una solicitud',
      emptyMessage:
          'Al tocar una solicitud veras el expediente completo en esta columna.',
      child: item == null
          ? null
          : _ApplicationDetailSheet(
              application: item,
              embedded: true,
              onCall: onCall,
              onWhatsApp: onWhatsApp,
              onReviewing: onReviewing,
              onApprove: onApprove,
              onReject: onReject,
            ),
    );
  }
}

class _TechnicianSidePanel extends StatelessWidget {
  const _TechnicianSidePanel({
    required this.technician,
    required this.jobs,
    required this.evaluations,
    required this.onCall,
    required this.onWhatsApp,
    required this.onFavorite,
    required this.onStatus,
    required this.onAddJob,
    required this.onAddEvaluation,
  });

  final Technician? technician;
  final List<TechnicianJob> jobs;
  final List<TechnicianEvaluation> evaluations;
  final ValueChanged<String> onCall;
  final void Function(String phone, String name) onWhatsApp;
  final ValueChanged<Technician> onFavorite;
  final void Function(Technician technician, TechnicianStatus status) onStatus;
  final ValueChanged<TechnicianJob> onAddJob;
  final ValueChanged<TechnicianEvaluation> onAddEvaluation;

  @override
  Widget build(BuildContext context) {
    final item = technician;
    final techJobs = item == null
        ? <TechnicianJob>[]
        : jobs.where((job) => job.technicianId == item.id).toList();
    final techEvaluations = item == null
        ? <TechnicianEvaluation>[]
        : evaluations.where((ev) => ev.technicianId == item.id).toList();
    return _SideDetailFrame(
      emptyTitle: 'Selecciona un tecnico',
      emptyMessage:
          'El perfil, trabajos, evaluaciones y acciones quedaran fijos aqui.',
      child: item == null
          ? null
          : _TechnicianProfileSheet(
              technician: item,
              jobs: techJobs,
              evaluations: techEvaluations,
              embedded: true,
              onCall: onCall,
              onWhatsApp: onWhatsApp,
              onFavorite: onFavorite,
              onStatus: onStatus,
              onAddJob: onAddJob,
              onAddEvaluation: onAddEvaluation,
            ),
    );
  }
}

class _SideDetailFrame extends StatelessWidget {
  const _SideDetailFrame({
    required this.emptyTitle,
    required this.emptyMessage,
    required this.child,
  });

  final String emptyTitle;
  final String emptyMessage;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return _RightPanelFrame(
      child: _ShellCard(
        padding: EdgeInsets.zero,
        child:
            child ?? _SideDetailEmpty(title: emptyTitle, message: emptyMessage),
      ),
    );
  }
}

class _SideDetailEmpty extends StatelessWidget {
  const _SideDetailEmpty({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.touch_app_outlined, color: _rtBlue, size: 38),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _rtMuted, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _TechnicianProfileSheet extends StatelessWidget {
  const _TechnicianProfileSheet({
    required this.technician,
    required this.jobs,
    required this.evaluations,
    required this.onCall,
    required this.onWhatsApp,
    required this.onFavorite,
    required this.onStatus,
    required this.onAddJob,
    required this.onAddEvaluation,
    this.embedded = false,
  });

  final Technician technician;
  final List<TechnicianJob> jobs;
  final List<TechnicianEvaluation> evaluations;
  final ValueChanged<String> onCall;
  final void Function(String phone, String name) onWhatsApp;
  final ValueChanged<Technician> onFavorite;
  final void Function(Technician technician, TechnicianStatus status) onStatus;
  final ValueChanged<TechnicianJob> onAddJob;
  final ValueChanged<TechnicianEvaluation> onAddEvaluation;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return _DetailShell(
      embedded: embedded,
      title: technician.fullName,
      subtitle: '${technician.technicianCode} • ${technician.status.label}',
      actions: [
        IconButton(
          onPressed: () => onCall(technician.phone),
          icon: const Icon(Icons.call_outlined),
        ),
        IconButton(
          onPressed: () => onWhatsApp(technician.whatsapp, technician.fullName),
          icon: const Icon(Icons.chat_outlined),
        ),
        IconButton(
          onPressed: () => onFavorite(technician),
          icon: Icon(
            technician.isFavorite
                ? Icons.star_rounded
                : Icons.star_border_rounded,
          ),
        ),
        PopupMenuButton<TechnicianStatus>(
          tooltip: 'Cambiar estado',
          onSelected: (status) => onStatus(technician, status),
          itemBuilder: (_) => TechnicianStatus.values
              .map(
                (status) =>
                    PopupMenuItem(value: status, child: Text(status.label)),
              )
              .toList(),
        ),
      ],
      children: [
        _InfoGrid(rows: _technicianRows(technician)),
        _SkillSection(
          title: 'Perfil tecnico',
          cameraSkills: technician.cameraSkills,
          gateMotorSkills: technician.gateMotorSkills,
        ),
        Row(
          children: [
            FilledButton.icon(
              onPressed: () => _showJobDialog(context, technician, onAddJob),
              icon: const Icon(Icons.work_outline_rounded),
              label: const Text('Registrar trabajo'),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: () =>
                  _showEvaluationDialog(context, technician, onAddEvaluation),
              icon: const Icon(Icons.star_rate_rounded),
              label: const Text('Evaluar'),
            ),
          ],
        ),
        _HistorySection(jobs: jobs, evaluations: evaluations),
      ],
    );
  }
}

class _TechnicianApplicationForm extends StatefulWidget {
  const _TechnicianApplicationForm({
    required this.title,
    required this.submitLabel,
    required this.requireDocuments,
    required this.onSubmit,
    this.allowStatusSelection = false,
  });

  final String title;
  final String submitLabel;
  final bool requireDocuments;
  final bool allowStatusSelection;
  final Future<void> Function(
    TechnicianApplication draft,
    TechnicianStatus? status,
  )
  onSubmit;

  @override
  State<_TechnicianApplicationForm> createState() =>
      _TechnicianApplicationFormState();
}

class _TechnicianApplicationFormState
    extends State<_TechnicianApplicationForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _identity = TextEditingController();
  final _phone = TextEditingController();
  final _whatsapp = TextEditingController();
  final _email = TextEditingController();
  final _province = TextEditingController();
  final _municipality = TextEditingController();
  final _sector = TextEditingController();
  final _experience = TextEditingController();
  final _otherTools = TextEditingController();
  final _availabilityNotes = TextEditingController();
  final _referenceName = TextEditingController();
  final _referencePhone = TextEditingController();
  final _previousCompany = TextEditingController();
  final _internalNotes = TextEditingController();
  var _specialty = RedTecnicaSpecialty.cameras;
  var _experienceLevel = TechnicianExperienceLevel.oneToThreeYears;
  var _toolsAvailability = ToolsAvailability.some;
  var _transportation = transportOptions.first;
  var _availability = availabilityOptions.first;
  var _status = TechnicianStatus.available;
  final _cameraSkills = <String>{};
  final _gateMotorSkills = <String>{};
  final _tools = <String>{};
  var _canTravel = false;
  var _canWorkWeekends = false;
  var _accepted = false;
  var _submitting = false;
  String? _profilePhoto;
  String? _frontPhoto;
  String? _backPhoto;
  final _workPhotos = <String>[];

  @override
  void dispose() {
    for (final ctrl in [
      _name,
      _identity,
      _phone,
      _whatsapp,
      _email,
      _province,
      _municipality,
      _sector,
      _experience,
      _otherTools,
      _availabilityNotes,
      _referenceName,
      _referencePhone,
      _previousCompany,
      _internalNotes,
    ]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _pickSingle(ValueChanged<String> setter) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;
    setState(() => setter(path));
  }

  Future<void> _pickMultiple() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null) return;
    setState(() {
      _workPhotos.addAll(
        result.files
            .map((file) => file.path ?? '')
            .where((path) => path.trim().isNotEmpty),
      );
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_accepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes aceptar los terminos.')),
      );
      return;
    }
    if (widget.requireDocuments &&
        ((_profilePhoto ?? '').isEmpty ||
            (_frontPhoto ?? '').isEmpty ||
            (_backPhoto ?? '').isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Agrega foto personal y ambas fotos de la cedula.'),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final now = DateTime.now();
      final draft = TechnicianApplication(
        id: '',
        applicationCode: '',
        fullName: _name.text.trim(),
        identityNumber: _identity.text.trim(),
        phone: _phone.text.trim(),
        whatsapp: _whatsapp.text.trim(),
        email: _email.text.trim(),
        province: _province.text.trim(),
        municipality: _municipality.text.trim(),
        sector: _sector.text.trim(),
        specialty: _specialty,
        experienceLevel: _experienceLevel,
        experienceDescription: _experience.text.trim(),
        cameraSkills: _cameraSkills.toList(),
        gateMotorSkills: _gateMotorSkills.toList(),
        toolsAvailability: _toolsAvailability,
        tools: _tools.toList(),
        otherTools: _otherTools.text.trim(),
        transportation: _transportation,
        availability: _availability,
        availabilityNotes: _availabilityNotes.text.trim(),
        canTravel: _canTravel,
        canWorkWeekends: _canWorkWeekends,
        profilePhotoPath: _profilePhoto,
        identityFrontPhotoPath: _frontPhoto,
        identityBackPhotoPath: _backPhoto,
        workEvidencePhotoPaths: _workPhotos.toList(),
        referenceName: _referenceName.text.trim(),
        referencePhone: _referencePhone.text.trim(),
        previousCompany: _previousCompany.text.trim(),
        status: TechnicianApplicationStatus.pending,
        internalNotes: _internalNotes.text.trim(),
        submittedAt: now,
        createdAt: now,
        updatedAt: now,
      );
      await widget.onSubmit(
        draft,
        widget.allowStatusSelection ? _status : null,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Bad state: ', '')),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.title,
            style: const TextStyle(
              color: _rtText,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Completa los datos esenciales para evaluar y contactar al tecnico.',
            style: TextStyle(color: _rtMuted, height: 1.3),
          ),
          const SizedBox(height: 18),
          _FormSection(
            title: 'Informacion personal',
            children: [
              _Field(_name, 'Nombre completo', required: true),
              _Field(_identity, 'Cedula', required: true, cedula: true),
              _Field(_phone, 'Telefono', required: true, phone: true),
              _Field(_whatsapp, 'WhatsApp', required: true, phone: true),
              _Field(_province, 'Provincia', required: true),
              _Field(_municipality, 'Municipio', required: true),
              _Field(_email, 'Correo opcional', email: true),
              _Field(_sector, 'Sector opcional'),
            ],
          ),
          _FormSection(
            title: 'Especialidad y experiencia',
            children: [
              _Dropdown<RedTecnicaSpecialty>(
                label: 'Area de experiencia',
                value: _specialty,
                values: RedTecnicaSpecialty.values,
                labelOf: (item) => item.label,
                onChanged: (value) => setState(() => _specialty = value),
              ),
              _Dropdown<TechnicianExperienceLevel>(
                label: 'Nivel de experiencia',
                value: _experienceLevel,
                values: TechnicianExperienceLevel.values,
                labelOf: (item) => item.label,
                onChanged: (value) => setState(() => _experienceLevel = value),
              ),
              TextFormField(
                controller: _experience,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Cuentanos brevemente sobre tu experiencia',
                ),
              ),
            ],
          ),
          if (_specialty != RedTecnicaSpecialty.gateMotors)
            _ChipPicker(
              title: 'Conocimientos en camaras',
              options: cameraSkills,
              selected: _cameraSkills,
              onChanged: () => setState(() {}),
            ),
          if (_specialty != RedTecnicaSpecialty.cameras)
            _ChipPicker(
              title: 'Conocimientos en motores',
              options: gateMotorSkills,
              selected: _gateMotorSkills,
              onChanged: () => setState(() {}),
            ),
          _FormSection(
            title: 'Herramientas y transporte',
            children: [
              _Dropdown<ToolsAvailability>(
                label: 'Herramientas propias',
                value: _toolsAvailability,
                values: ToolsAvailability.values,
                labelOf: (item) => item.label,
                onChanged: (value) =>
                    setState(() => _toolsAvailability = value),
              ),
              _Dropdown<String>(
                label: 'Transporte',
                value: _transportation,
                values: transportOptions,
                labelOf: (item) => item,
                onChanged: (value) => setState(() => _transportation = value),
              ),
              _Field(_otherTools, 'Otras herramientas'),
            ],
          ),
          if (_toolsAvailability != ToolsAvailability.no)
            _ChipPicker(
              title: 'Herramientas disponibles',
              options: technicianTools,
              selected: _tools,
              onChanged: () => setState(() {}),
            ),
          _FormSection(
            title: 'Disponibilidad',
            children: [
              _Dropdown<String>(
                label: 'Disponibilidad',
                value: _availability,
                values: availabilityOptions,
                labelOf: (item) => item,
                onChanged: (value) => setState(() => _availability = value),
              ),
              SwitchListTile(
                value: _canTravel,
                onChanged: (value) => setState(() => _canTravel = value),
                title: const Text('Puede viajar fuera del municipio'),
              ),
              SwitchListTile(
                value: _canWorkWeekends,
                onChanged: (value) => setState(() => _canWorkWeekends = value),
                title: const Text('Puede trabajar fines de semana'),
              ),
              _Field(_availabilityNotes, 'Notas de disponibilidad'),
            ],
          ),
          _FormSection(
            title: 'Fotografias y documentos',
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _PickButton(
                    label: 'Foto personal',
                    path: _profilePhoto,
                    onTap: () => _pickSingle((path) => _profilePhoto = path),
                  ),
                  _PickButton(
                    label: 'Cedula frontal',
                    path: _frontPhoto,
                    onTap: () => _pickSingle((path) => _frontPhoto = path),
                  ),
                  _PickButton(
                    label: 'Cedula trasera',
                    path: _backPhoto,
                    onTap: () => _pickSingle((path) => _backPhoto = path),
                  ),
                  _PickButton(
                    label: 'Fotos de trabajos (${_workPhotos.length})',
                    path: _workPhotos.isEmpty ? null : _workPhotos.last,
                    onTap: _pickMultiple,
                  ),
                ],
              ),
            ],
          ),
          _FormSection(
            title: 'Referencia',
            children: [
              _Field(_referenceName, 'Nombre de referencia'),
              _Field(_referencePhone, 'Telefono de referencia', phone: true),
              _Field(_previousCompany, 'Empresa anterior'),
              if (widget.allowStatusSelection)
                _Dropdown<TechnicianStatus>(
                  label: 'Estado inicial',
                  value: _status,
                  values: TechnicianStatus.values,
                  labelOf: (item) => item.label,
                  onChanged: (value) => setState(() => _status = value),
                ),
              if (widget.allowStatusSelection)
                _Field(_internalNotes, 'Observaciones internas'),
            ],
          ),
          CheckboxListTile(
            value: _accepted,
            onChanged: (value) => setState(() => _accepted = value ?? false),
            title: const Text(
              'Declaro que la informacion suministrada es correcta y autorizo a FullTech SRL a contactarme para posibles trabajos. Entiendo que completar este formulario no representa contratacion laboral ni garantiza asignacion de trabajos.',
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text(widget.submitLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(
    this.controller,
    this.label, {
    this.required = false,
    this.phone = false,
    this.cedula = false,
    this.email = false,
  });

  final TextEditingController controller;
  final String label;
  final bool required;
  final bool phone;
  final bool cedula;
  final bool email;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: _rtInputDecoration(label),
      keyboardType: phone || cedula ? TextInputType.phone : TextInputType.text,
      validator: (value) {
        final raw = (value ?? '').trim();
        final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
        if (required && raw.isEmpty) return 'Este campo es obligatorio.';
        if (phone && raw.isNotEmpty && digits.length < 10) {
          return 'Escribe un telefono valido.';
        }
        if (cedula && digits.length != 11) return 'Escribe una cedula valida.';
        if (email && raw.isNotEmpty && !raw.contains('@')) {
          return 'Escribe un correo valido.';
        }
        return null;
      },
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: _rtInputDecoration(label),
      items: values
          .map(
            (item) => DropdownMenuItem(value: item, child: Text(labelOf(item))),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _FormSection extends StatelessWidget {
  const _FormSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 2 : 1;
        final itemWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _rtText,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  for (final child in children)
                    SizedBox(width: itemWidth, child: child),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChipPicker extends StatelessWidget {
  const _ChipPicker({
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final List<String> options;
  final Set<String> selected;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                FilterChip(
                  label: Text(option),
                  selected: selected.contains(option),
                  onSelected: (value) {
                    if (value) {
                      selected.add(option);
                    } else {
                      selected.remove(option);
                    }
                    onChanged();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PickButton extends StatelessWidget {
  const _PickButton({
    required this.label,
    required this.path,
    required this.onTap,
  });

  final String label;
  final String? path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(
        path == null ? Icons.upload_file_rounded : Icons.check_rounded,
      ),
      label: Text(label),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _ShellCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: _rtBlue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _rtText,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: _rtText,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellCard extends StatelessWidget {
  const _ShellCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.highlighted = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: _rtSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlighted ? _rtBlue : _rtLine,
          width: highlighted ? 1.4 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F0B3550),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.path, required this.name});

  final String? path;
  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty ? 'RT' : name.trim()[0].toUpperCase();
    return CircleAvatar(child: Text(initials));
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.12),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w800),
      side: BorderSide(color: color.withValues(alpha: 0.2)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        Icon(icon, size: 52, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(message, textAlign: TextAlign.center),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 14),
          Center(
            child: FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ),
        ],
      ],
    );
  }
}

class _DetailShell extends StatelessWidget {
  const _DetailShell({
    required this.title,
    required this.subtitle,
    required this.actions,
    required this.children,
    this.embedded = false,
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;
  final List<Widget> children;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      padding: EdgeInsets.fromLTRB(
        embedded ? 16 : 22,
        embedded ? 14 : 8,
        embedded ? 16 : 22,
        28,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: _rtMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Wrap(spacing: 4, runSpacing: 4, children: actions),
          ],
        ),
        const SizedBox(height: 14),
        for (final child in children) ...[
          _ShellCard(
            child: Padding(padding: const EdgeInsets.all(14), child: child),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );

    if (embedded) {
      return SizedBox.expand(child: content);
    }

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: content,
        ),
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: [
        for (final row in rows)
          SizedBox(
            width: 230,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.$1, style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(height: 3),
                Text(
                  row.$2.isEmpty ? 'No registrado' : row.$2,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SkillSection extends StatelessWidget {
  const _SkillSection({
    required this.title,
    required this.cameraSkills,
    required this.gateMotorSkills,
  });

  final String title;
  final List<String> cameraSkills;
  final List<String> gateMotorSkills;

  @override
  Widget build(BuildContext context) {
    final skills = [...cameraSkills, ...gateMotorSkills];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (skills.isEmpty)
          const Text('No hay conocimientos registrados.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [for (final skill in skills) Chip(label: Text(skill))],
          ),
      ],
    );
  }
}

class _EvidenceSection extends StatelessWidget {
  const _EvidenceSection({required this.paths});

  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Evidencias y documentos',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (paths.isEmpty)
          const Text('No hay documentos cargados.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final path in paths)
                Chip(
                  avatar: const Icon(Icons.lock_outline_rounded, size: 16),
                  label: Text(path.split(RegExp(r'[\\/]')).last),
                ),
            ],
          ),
      ],
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.jobs, required this.evaluations});

  final List<TechnicianJob> jobs;
  final List<TechnicianEvaluation> evaluations;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('dd/MM/yyyy h:mm a');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Historial basico',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (jobs.isEmpty && evaluations.isEmpty)
          const Text('No hay trabajos ni evaluaciones registrados.')
        else ...[
          for (final job in jobs.take(6))
            ListTile(
              dense: true,
              leading: const Icon(Icons.work_outline_rounded),
              title: Text(job.type.label),
              subtitle: Text('${date.format(job.date)} • ${job.location}'),
              trailing: Text(job.status.label),
            ),
          for (final evaluation in evaluations.take(4))
            ListTile(
              dense: true,
              leading: const Icon(Icons.star_rate_rounded),
              title: Text('${evaluation.rating}/5'),
              subtitle: Text(
                evaluation.note.isEmpty ? 'Sin nota' : evaluation.note,
              ),
            ),
        ],
      ],
    );
  }
}

List<(String, String)> _applicationRows(TechnicianApplication item) => [
  ('Cedula', _maskIdentity(item.identityNumber)),
  ('Telefono', item.phone),
  ('WhatsApp', item.whatsapp),
  ('Correo', item.email ?? ''),
  ('Provincia', item.province),
  ('Municipio', item.municipality),
  ('Sector', item.sector ?? ''),
  ('Especialidad', item.specialty.label),
  ('Experiencia', item.experienceLevel.label),
  ('Herramientas', item.toolsAvailability.label),
  ('Transporte', item.transportation),
  ('Disponibilidad', item.availability),
  ('Fecha solicitud', DateFormat('dd/MM/yyyy h:mm a').format(item.submittedAt)),
  ('Referencia', item.referenceName),
  ('Empresa anterior', item.previousCompany),
  ('Notas internas', item.internalNotes),
];

List<(String, String)> _technicianRows(Technician item) => [
  ('Codigo', item.technicianCode),
  ('Cedula', _maskIdentity(item.identityNumber)),
  ('Telefono', item.phone),
  ('WhatsApp', item.whatsapp),
  ('Correo', item.email ?? ''),
  ('Provincia', item.province),
  ('Municipio', item.municipality),
  ('Sector', item.sector ?? ''),
  ('Especialidad', item.specialty.label),
  ('Experiencia', item.experienceLevel.label),
  ('Herramientas', item.toolsAvailability.label),
  ('Transporte', item.transportation),
  ('Disponibilidad', item.availability),
  ('Trabajos', '${item.completedJobsCount}'),
  (
    'Calificacion',
    item.rating <= 0 ? 'Sin evaluar' : item.rating.toStringAsFixed(1),
  ),
  ('Aprobado', DateFormat('dd/MM/yyyy h:mm a').format(item.approvedAt)),
  (
    'Ultimo trabajo',
    item.lastJobAt == null
        ? ''
        : DateFormat('dd/MM/yyyy').format(item.lastJobAt!),
  ),
  ('Notas internas', item.internalNotes),
];

String _maskIdentity(String value) {
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length < 3) return '***-*******-*';
  return '${digits.substring(0, 3)}-*******-*';
}

InputDecoration _rtInputDecoration(
  String label, {
  String? hint,
  IconData? icon,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: icon == null ? null : Icon(icon, size: 19),
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _rtLine),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _rtLine),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _rtBlue, width: 1.5),
    ),
  );
}

Color _appStatusColor(TechnicianApplicationStatus status) => switch (status) {
  TechnicianApplicationStatus.pending => const Color(0xFFD97706),
  TechnicianApplicationStatus.reviewing => const Color(0xFF2563EB),
  TechnicianApplicationStatus.approved => const Color(0xFF059669),
  TechnicianApplicationStatus.rejected => const Color(0xFFDC2626),
};

Color _techStatusColor(TechnicianStatus status) => switch (status) {
  TechnicianStatus.available => const Color(0xFF059669),
  TechnicianStatus.busy => const Color(0xFFD97706),
  TechnicianStatus.unavailable => const Color(0xFF6B7280),
  TechnicianStatus.inactive => const Color(0xFF991B1B),
};

Future<void> _showJobDialog(
  BuildContext context,
  Technician technician,
  ValueChanged<TechnicianJob> onSubmit,
) async {
  final location = TextEditingController();
  final description = TextEditingController();
  final payment = TextEditingController();
  var type = TechnicianJobType.cameraInstallation;
  var status = TechnicianJobStatus.completed;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Registrar trabajo realizado'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Dropdown<TechnicianJobType>(
                label: 'Tipo',
                value: type,
                values: TechnicianJobType.values,
                labelOf: (item) => item.label,
                onChanged: (value) => setState(() => type = value),
              ),
              _Dropdown<TechnicianJobStatus>(
                label: 'Estado',
                value: status,
                values: TechnicianJobStatus.values,
                labelOf: (item) => item.label,
                onChanged: (value) => setState(() => status = value),
              ),
              TextField(
                controller: location,
                decoration: const InputDecoration(labelText: 'Ubicacion'),
              ),
              TextField(
                controller: description,
                decoration: const InputDecoration(
                  labelText: 'Descripcion breve',
                ),
              ),
              TextField(
                controller: payment,
                decoration: const InputDecoration(
                  labelText: 'Pago acordado opcional',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final now = DateTime.now();
              onSubmit(
                TechnicianJob(
                  id: 'rtj_${now.microsecondsSinceEpoch}',
                  technicianId: technician.id,
                  type: type,
                  date: now,
                  location: location.text.trim(),
                  description: description.text.trim(),
                  agreedPayment: double.tryParse(payment.text.trim()),
                  status: status,
                  createdAt: now,
                  updatedAt: now,
                ),
              );
              Navigator.pop(context);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
  location.dispose();
  description.dispose();
  payment.dispose();
}

Future<void> _showEvaluationDialog(
  BuildContext context,
  Technician technician,
  ValueChanged<TechnicianEvaluation> onSubmit,
) async {
  final note = TextEditingController();
  var rating = 5;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Evaluar tecnico'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Slider(
                value: rating.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                label: '$rating',
                onChanged: (value) => setState(() => rating = value.round()),
              ),
              TextField(
                controller: note,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Nota corta'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              onSubmit(
                TechnicianEvaluation(
                  id: 'rte_${DateTime.now().microsecondsSinceEpoch}',
                  technicianId: technician.id,
                  rating: rating,
                  note: note.text.trim(),
                  createdAt: DateTime.now(),
                ),
              );
              Navigator.pop(context);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
  note.dispose();
}
