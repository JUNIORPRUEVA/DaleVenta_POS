import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/utils/safe_url_launcher.dart';
import 'data/red_tecnica_repository.dart';
import 'red_tecnica_models.dart';

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
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 760),
          child: _TechnicianApplicationForm(
            title: 'Registrar tecnico manualmente',
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
              if (context.mounted) Navigator.pop(context);
              _reload();
            },
          ),
        ),
      ),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Red Tecnica'),
        actions: [
          TextButton.icon(
            onPressed: _copyPublicLink,
            icon: const Icon(Icons.link_rounded),
            label: const Text('Copiar formulario'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _openManualRegistration,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Registrar tecnico'),
          ),
          const SizedBox(width: 14),
        ],
      ),
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
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                child: _Toolbar(
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
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      icon: Icon(Icons.dashboard_outlined),
                      label: Text('Panel'),
                    ),
                    ButtonSegment(
                      value: 1,
                      icon: Icon(Icons.inbox_outlined),
                      label: Text('Solicitudes'),
                    ),
                    ButtonSegment(
                      value: 2,
                      icon: Icon(Icons.engineering_outlined),
                      label: Text('Tecnicos activos'),
                    ),
                  ],
                  selected: {_tab},
                  onSelectionChanged: (value) =>
                      setState(() => _tab = value.first),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: RefreshIndicator(
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
                        onOpen: (item) => _showApplicationDetail(item),
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
                        onOpen: (item) => _showTechnicianProfile(
                          item,
                          data.jobs
                              .where((job) => job.technicianId == item.id)
                              .toList(),
                          data.evaluations
                              .where((ev) => ev.technicianId == item.id)
                              .toList(),
                        ),
                      ),
                    },
                  ),
                ),
              ),
            ],
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
      backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.35,
      ),
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
      backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.35,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: _sent == null
                ? Card(
                    margin: const EdgeInsets.all(18),
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
                  )
                : Card(
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
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final card in cards)
              _StatCard(title: card.$1, value: '${card.$2}', icon: card.$3),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
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
      ],
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
  });

  final List<TechnicianApplication> items;
  final ValueChanged<String> onCall;
  final void Function(String phone, String name) onWhatsApp;
  final ValueChanged<TechnicianApplication> onReviewing;
  final ValueChanged<TechnicianApplication> onApprove;
  final ValueChanged<TechnicianApplication> onReject;
  final ValueChanged<TechnicianApplication> onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyState(
        icon: Icons.inbox_outlined,
        title: 'Sin solicitudes',
        message: 'Cuando un tecnico envie el formulario aparecera aqui.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        return _ApplicationCard(
          item: item,
          onCall: () => onCall(item.phone),
          onWhatsApp: () => onWhatsApp(item.whatsapp, item.fullName),
          onReviewing: () => onReviewing(item),
          onApprove: () => onApprove(item),
          onReject: () => onReject(item),
          onOpen: () => onOpen(item),
        );
      },
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
  });

  final List<Technician> items;
  final List<TechnicianJob> jobs;
  final List<TechnicianEvaluation> evaluations;
  final ValueChanged<String> onCall;
  final void Function(String phone, String name) onWhatsApp;
  final ValueChanged<Technician> onFavorite;
  final void Function(Technician tech, TechnicianStatus status) onStatus;
  final ValueChanged<Technician> onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyState(
        icon: Icons.engineering_outlined,
        title: 'Sin tecnicos activos',
        message: 'Aprueba una solicitud o registra un tecnico manualmente.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        return _TechnicianCard(
          item: item,
          onCall: () => onCall(item.phone),
          onWhatsApp: () => onWhatsApp(item.whatsapp, item.fullName),
          onFavorite: () => onFavorite(item),
          onStatus: (status) => onStatus(item, status),
          onOpen: () => onOpen(item),
        );
      },
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
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 360,
          child: TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Buscar por nombre, telefono, cedula o provincia',
              isDense: true,
            ),
          ),
        ),
        if (tab == 1)
          DropdownButton<String>(
            value: applicationStatusFilter,
            items:
                [
                      'Todos',
                      ...TechnicianApplicationStatus.values.map((e) => e.label),
                    ]
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
            onChanged: (value) => onApplicationStatusChanged(value ?? 'Todos'),
          ),
        if (tab == 2)
          DropdownButton<String>(
            value: technicianFilter,
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
                    ]
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
            onChanged: (value) => onTechnicianFilterChanged(value ?? 'Todos'),
          ),
        DropdownButton<RedTecnicaSpecialty?>(
          value: specialtyFilter,
          hint: const Text('Especialidad'),
          items: [
            const DropdownMenuItem<RedTecnicaSpecialty?>(
              value: null,
              child: Text('Todas las areas'),
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
      ],
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({
    required this.item,
    required this.onCall,
    required this.onWhatsApp,
    required this.onReviewing,
    required this.onApprove,
    required this.onReject,
    required this.onOpen,
  });

  final TechnicianApplication item;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;
  final VoidCallback onReviewing;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return _ShellCard(
      child: ListTile(
        leading: _Avatar(path: item.profilePhotoPath, name: item.fullName),
        title: Text(
          item.fullName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${item.phone} • ${item.province}, ${item.municipality}\n${item.specialty.label} • ${item.experienceLevel.label}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: Wrap(
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
                PopupMenuItem(value: 'view', child: Text('Ver solicitud')),
                PopupMenuItem(
                  value: 'review',
                  child: Text('Marcar en revision'),
                ),
                PopupMenuItem(value: 'approve', child: Text('Aprobar')),
                PopupMenuItem(value: 'reject', child: Text('Rechazar')),
              ],
            ),
          ],
        ),
        onTap: onOpen,
      ),
    );
  }
}

class _TechnicianCard extends StatelessWidget {
  const _TechnicianCard({
    required this.item,
    required this.onCall,
    required this.onWhatsApp,
    required this.onFavorite,
    required this.onStatus,
    required this.onOpen,
  });

  final Technician item;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;
  final VoidCallback onFavorite;
  final ValueChanged<TechnicianStatus> onStatus;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return _ShellCard(
      child: ListTile(
        leading: _Avatar(path: item.profilePhotoPath, name: item.fullName),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '${item.fullName} • ${item.technicianCode}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
        trailing: Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _StatusChip(
              label: item.status.label,
              color: _techStatusColor(item.status),
            ),
            Text('${item.completedJobsCount} trabajos'),
            if (item.rating > 0) Text('★ ${item.rating.toStringAsFixed(1)}'),
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
                if (value == 'available') onStatus(TechnicianStatus.available);
                if (value == 'busy') onStatus(TechnicianStatus.busy);
                if (value == 'unavailable') {
                  onStatus(TechnicianStatus.unavailable);
                }
                if (value == 'inactive') onStatus(TechnicianStatus.inactive);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'profile',
                  child: Text('Ver perfil'),
                ),
                PopupMenuItem(
                  value: 'favorite',
                  child: Text(
                    item.isFavorite ? 'Quitar favorito' : 'Marcar favorito',
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'available',
                  child: Text('Disponible'),
                ),
                const PopupMenuItem(value: 'busy', child: Text('Ocupado')),
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
  });

  final TechnicianApplication application;
  final ValueChanged<String> onCall;
  final void Function(String phone, String name) onWhatsApp;
  final ValueChanged<TechnicianApplication> onReviewing;
  final ValueChanged<TechnicianApplication> onApprove;
  final ValueChanged<TechnicianApplication> onReject;

  @override
  Widget build(BuildContext context) {
    return _DetailShell(
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

  @override
  Widget build(BuildContext context) {
    return _DetailShell(
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
        padding: const EdgeInsets.all(22),
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
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
          FilledButton.icon(
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
      decoration: InputDecoration(labelText: label),
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
      decoration: InputDecoration(labelText: label),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              for (final child in children) SizedBox(width: 260, child: child),
            ],
          ),
        ],
      ),
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
    final theme = Theme.of(context);
    return SizedBox(
      width: 220,
      child: _ShellCard(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.labelLarge),
                    Text(
                      value,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShellCard extends StatelessWidget {
  const _ShellCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: child,
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
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        Text(subtitle),
                      ],
                    ),
                  ),
                  Wrap(spacing: 6, children: actions),
                ],
              ),
              const SizedBox(height: 16),
              for (final child in children) ...[
                _ShellCard(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: child,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
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
