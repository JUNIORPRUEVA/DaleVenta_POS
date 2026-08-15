import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/admin_authorization.dart';
import '../../core/auth/token_storage.dart';
import '../../core/auth/app_permissions.dart';
import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/errors/api_exception.dart';
import '../../core/models/user_model.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/is_flutter_test.dart';
import '../../core/utils/media_url.dart';
import '../../core/utils/string_utils.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/user_avatar.dart';
import '../user/application/users_controller.dart';
import 'utils/work_contract_preview_screen.dart';

String? _resolveUserDocUrl(String? url) {
  final resolved = resolvePublicMediaUrl(url);
  return resolved.isEmpty ? null : resolved;
}

class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const _UsersScreenBody();
  }
}

enum _UserStatusFilter { todos, activos, bloqueados }

enum _UserRoleFilter { todos, administradores, cajeros }

enum _UserSortOption { nombre, fechaCreacion, rol, estado }

AppRole _managementRole(UserModel user) {
  return user.appRole == AppRole.admin ? AppRole.admin : AppRole.cajero;
}

class _UsersScreenBody extends ConsumerStatefulWidget {
  const _UsersScreenBody();

  @override
  ConsumerState<_UsersScreenBody> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<_UsersScreenBody> {
  static const double _desktopBreakpoint = 1000;

  final TextEditingController _searchCtrl = TextEditingController();
  bool _searching = false;
  String _searchQuery = '';
  _UserStatusFilter _statusFilter = _UserStatusFilter.todos;
  final _UserRoleFilter _roleFilter = _UserRoleFilter.todos;
  final _UserSortOption _sortOption = _UserSortOption.nombre;
  String? _selectedDesktopUserId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

  List<UserModel> _filterUsers(List<UserModel> users, {required bool desktop}) {
    final filtered = users
        .where((user) {
          final matchesStatus = switch (_statusFilter) {
            _UserStatusFilter.todos => true,
            _UserStatusFilter.activos => !user.blocked,
            _UserStatusFilter.bloqueados => user.blocked,
          };

          final matchesRole = !desktop
              ? true
              : switch (_roleFilter) {
                  _UserRoleFilter.todos => true,
                  _UserRoleFilter.administradores =>
                    _managementRole(user) == AppRole.admin,
                  _UserRoleFilter.cajeros =>
                    _managementRole(user) == AppRole.cajero,
                };

          final q = _searchQuery.trim().toLowerCase();
          final matchesSearch = q.isEmpty
              ? true
              : ('${user.nombreCompleto} '
                        '${user.email} '
                        '${user.telefono} '
                        '${user.cedula ?? ''} '
                        '${user.role ?? ''} '
                        '${_managementRole(user).label}')
                    .toLowerCase()
                    .contains(q);

          return matchesStatus && matchesRole && matchesSearch;
        })
        .toList(growable: false);

    if (!desktop) return filtered;

    final sorted = [...filtered];
    sorted.sort((left, right) {
      switch (_sortOption) {
        case _UserSortOption.nombre:
          return left.nombreCompleto.toLowerCase().compareTo(
            right.nombreCompleto.toLowerCase(),
          );
        case _UserSortOption.fechaCreacion:
          final leftDate =
              left.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final rightDate =
              right.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return rightDate.compareTo(leftDate);
        case _UserSortOption.rol:
          return _managementRole(
            left,
          ).label.compareTo(_managementRole(right).label);
        case _UserSortOption.estado:
          if (left.blocked == right.blocked) {
            return left.nombreCompleto.toLowerCase().compareTo(
              right.nombreCompleto.toLowerCase(),
            );
          }
          return left.blocked ? 1 : -1;
      }
    });
    return sorted;
  }

  Future<void> _openWorkContractPreview(
    BuildContext context,
    UserModel user,
  ) async {
    try {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Abriendo contrato...')));
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => WorkContractPreviewScreen(employee: user),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo generar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    final currentUser = auth.user;

    if (currentUser?.appRole != AppRole.admin) {
      return Scaffold(
        appBar: CustomAppBar(
          title: 'FullTech',
          showLogo: true,
          trailing: currentUser == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => context.push(Routes.profile),
                    child: UserAvatar(
                      radius: 16,
                      backgroundColor: Colors.white24,
                      imageUrl: currentUser.fotoPersonalUrl,
                      child: Text(
                        getInitials(currentUser.nombreCompleto),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                const Text('Solo administradores pueden gestionar usuarios'),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.person),
                  label: const Text('Ir a mi perfil'),
                  onPressed: () => context.push(Routes.profile),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final usersState = ref.watch(usersControllerProvider);

    if (_isDesktop(context)) {
      return _buildDesktopScaffold(context, ref, currentUser, usersState);
    }

    return _buildMobileScaffold(context, ref, currentUser, usersState);
  }

  Widget _buildMobileScaffold(
    BuildContext context,
    WidgetRef ref,
    UserModel? currentUser,
    AsyncValue<List<UserModel>> usersState,
  ) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar(
        title: 'Usuarios y permisos',
        showLogo: false,
        trailing: currentUser == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => context.push(Routes.profile),
                  child: UserAvatar(
                    radius: 16,
                    backgroundColor: Colors.white24,
                    imageUrl: currentUser.fotoPersonalUrl,
                    child: Text(
                      getInitials(currentUser.nombreCompleto),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
        titleWidget: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (value) => setState(() => _searchQuery = value),
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Buscar usuario...',
                  hintStyle: const TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () {
                      setState(() {
                        _searching = false;
                        _searchQuery = '';
                        _searchCtrl.clear();
                      });
                    },
                  ),
                ),
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'PIN administrativo',
            onPressed: () => _showAdminPinDialog(context, ref),
            icon: const Icon(Icons.admin_panel_settings_outlined),
          ),
          IconButton(
            tooltip: 'Buscar',
            onPressed: () => setState(() => _searching = true),
            icon: const Icon(Icons.search),
          ),
          PopupMenuButton<_UserStatusFilter>(
            tooltip: 'Filtrar',
            initialValue: _statusFilter,
            onSelected: (value) => setState(() => _statusFilter = value),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _UserStatusFilter.todos,
                child: Text('Todos'),
              ),
              PopupMenuItem(
                value: _UserStatusFilter.activos,
                child: Text('Solo activos'),
              ),
              PopupMenuItem(
                value: _UserStatusFilter.bloqueados,
                child: Text('Solo bloqueados'),
              ),
            ],
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showUserDialog(context, ref),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(usersControllerProvider.notifier).refresh(),
        child: usersState.when(
          loading: () => ListView(
            padding: const EdgeInsets.all(16),
            children: const [Center(child: Text('Sincronizando usuarios...'))],
          ),
          error: (e, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Error al cargar usuarios: $e'),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () =>
                    ref.read(usersControllerProvider.notifier).refresh(),
                child: const Text('Reintentar'),
              ),
            ],
          ),
          data: (users) {
            final filteredUsers = _filterUsers(users, desktop: false);

            if (filteredUsers.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Center(
                    child: Text(
                      users.isEmpty
                          ? 'No hay usuarios registrados'
                          : 'No hay resultados con ese filtro',
                    ),
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredUsers.length,
              itemBuilder: (context, index) {
                final user = filteredUsers[index];
                return _UserCard(
                  user: user,
                  onView: () => _openUserDetailsScreen(context, user),
                  onEdit: () => _showUserDialog(context, ref, user),
                  onDelete: () => _showDeleteDialog(context, ref, user),
                  onToggleBlock: () => _toggleBlock(context, ref, user),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildDesktopScaffold(
    BuildContext context,
    WidgetRef ref,
    UserModel? currentUser,
    AsyncValue<List<UserModel>> usersState,
  ) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Usuarios y permisos',
        showLogo: false,
        trailing: currentUser == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => context.push(Routes.profile),
                  child: UserAvatar(
                    radius: 16,
                    backgroundColor: Colors.white24,
                    imageUrl: currentUser.fotoPersonalUrl,
                    child: Text(
                      getInitials(currentUser.nombreCompleto),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
        actions: [
          IconButton(
            tooltip: 'PIN administrativo',
            onPressed: () => _showAdminPinDialog(context, ref),
            icon: const Icon(Icons.admin_panel_settings_outlined),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1957E6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 0,
                ),
              ),
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('Nuevo usuario'),
              onPressed: () => _showUserDialog(context, ref),
            ),
          ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () =>
                ref.read(usersControllerProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      body: Container(
        color: theme.colorScheme.surfaceContainerLowest,
        child: usersState.when(
          loading: () => const Center(child: Text('Sincronizando usuarios...')),
          error: (e, _) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _DesktopUsersEmptyState(
                  icon: Icons.error_outline,
                  title: 'No se pudieron cargar los usuarios',
                  message: 'Error al cargar usuarios: $e',
                  actionLabel: 'Reintentar',
                  onAction: () =>
                      ref.read(usersControllerProvider.notifier).refresh(),
                ),
              ),
            ),
          ),
          data: (users) {
            final desktopUsers = _filterUsers(users, desktop: true)
              ..sort(
                (left, right) => left.nombreCompleto.toLowerCase().compareTo(
                  right.nombreCompleto.toLowerCase(),
                ),
              );
            final selectedUser = desktopUsers.isEmpty
                ? null
                : desktopUsers.firstWhere(
                    (user) => user.id == _selectedDesktopUserId,
                    orElse: () => desktopUsers.first,
                  );

            return Padding(
              padding: const EdgeInsets.fromLTRB(28, 22, 28, 28),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final detailWidth = constraints.maxWidth >= 1320
                      ? 430.0
                      : 380.0;

                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _UsersTable(
                          users: desktopUsers,
                          selectedUserId: selectedUser?.id,
                          onSelectUser: (user) {
                            setState(() => _selectedDesktopUserId = user.id);
                          },
                          onViewUser: (user) {
                            setState(() => _selectedDesktopUserId = user.id);
                          },
                          onEditUser: (user) =>
                              _showUserDialog(context, ref, user),
                          onDeleteUser: (user) =>
                              _showDeleteDialog(context, ref, user),
                          onToggleBlock: (user) =>
                              _toggleBlock(context, ref, user),
                          onOpenContract: (user) =>
                              _openWorkContractPreview(context, user),
                        ),
                      ),
                      const SizedBox(width: 18),
                      SizedBox(
                        width: detailWidth,
                        child: SizedBox(
                          height: constraints.maxHeight,
                          child: _UserPermissionDetailsPanel(
                            user: selectedUser,
                            onEdit: selectedUser == null
                                ? null
                                : () => _showUserDialog(
                                    context,
                                    ref,
                                    selectedUser,
                                  ),
                            onToggleBlock: selectedUser == null
                                ? null
                                : () =>
                                      _toggleBlock(context, ref, selectedUser),
                            onOpenContract: selectedUser == null
                                ? null
                                : () => _openWorkContractPreview(
                                    context,
                                    selectedUser,
                                  ),
                            onEditPermissions:
                                selectedUser == null ||
                                    _managementRole(selectedUser) ==
                                        AppRole.admin
                                ? null
                                : () => context.go(
                                    Routes.userPermissionsById(selectedUser.id),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _showAdminPinDialog(BuildContext context, WidgetRef ref) async {
    final pinCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> save() async {
              final pin = pinCtrl.text.trim();
              final confirm = confirmCtrl.text.trim();
              if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('El PIN debe tener exactamente 4 dígitos.'),
                  ),
                );
                return;
              }
              if (pin != confirm) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('Los PIN no coinciden.')),
                );
                return;
              }

              setDialogState(() => saving = true);
              try {
                await ref
                    .read(companySettingsRepositoryProvider)
                    .setAdminAuthorizationPin(pin);
                ref.invalidate(companySettingsProvider);
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN administrativo guardado.')),
                );
              } catch (error) {
                if (!dialogContext.mounted) return;
                setDialogState(() => saving = false);
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text('No se pudo guardar PIN: $error')),
                );
              }
            }

            return AlertDialog(
              title: const Text('PIN administrativo'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Configura el PIN que autoriza acciones sensibles para usuarios permitidos.',
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: pinCtrl,
                      obscureText: true,
                      obscuringCharacter: '•',
                      maxLength: 4,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      decoration: const InputDecoration(
                        counterText: '',
                        labelText: 'Nuevo PIN',
                        prefixIcon: Icon(Icons.pin_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: confirmCtrl,
                      obscureText: true,
                      obscuringCharacter: '•',
                      maxLength: 4,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      decoration: const InputDecoration(
                        counterText: '',
                        labelText: 'Confirmar PIN',
                        prefixIcon: Icon(Icons.lock_reset_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: saving ? null : save,
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(saving ? 'Guardando' : 'Guardar PIN'),
                ),
              ],
            );
          },
        );
      },
    );

    pinCtrl.dispose();
    confirmCtrl.dispose();
  }

  Future<void> _toggleBlock(
    BuildContext context,
    WidgetRef ref,
    UserModel user,
  ) async {
    final allowed = await ensureAdminAuthorization(
      context,
      ref,
      permission: AppPermission.manageUsers,
      reason: user.blocked ? 'Desbloquear usuario' : 'Bloquear usuario',
    );
    if (!allowed || !context.mounted) return;
    try {
      await ref
          .read(usersControllerProvider.notifier)
          .toggleBlock(user.id, !user.blocked);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              user.blocked ? 'Usuario desbloqueado' : 'Usuario bloqueado',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('No se pudo actualizar: $e')));
      }
    }
  }

  Future<void> _showUserDialog(
    BuildContext context,
    WidgetRef ref, [
    UserModel? user,
  ]) async {
    final allowed = await ensureAdminAuthorization(
      context,
      ref,
      permission: AppPermission.manageUsers,
      reason: user == null ? 'Crear usuario' : 'Editar usuario',
    );
    if (!allowed || !context.mounted) return;
    final scaffoldContext = context;

    void showSnack(SnackBar snackBar) {
      if (!scaffoldContext.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(scaffoldContext);
      if (messenger == null) return;
      messenger.showSnackBar(snackBar);
    }

    final nameCtrl = TextEditingController(text: user?.nombreCompleto ?? '');
    final emailCtrl = TextEditingController(text: user?.email ?? '');
    final phoneCtrl = TextEditingController(text: user?.telefono ?? '');
    final numeroFlotaCtrl = TextEditingController(
      text: user?.numeroFlota ?? '',
    );
    final cedulaCtrl = TextEditingController(text: user?.cedula ?? '');
    final familiarPhoneCtrl = TextEditingController(
      text: user?.telefonoFamiliar ?? '',
    );
    final edadCtrl = TextEditingController(text: user?.edad?.toString() ?? '');
    final cuentaNominaCtrl = TextEditingController(
      text: user?.cuentaNominaPreferencial ?? '',
    );
    final contractJobTitleCtrl = TextEditingController(
      text: user?.workContractJobTitle ?? '',
    );
    final contractSalaryCtrl = TextEditingController(
      text: user?.workContractSalary ?? '',
    );
    final contractPaymentFrequencyCtrl = TextEditingController(
      text: user?.workContractPaymentFrequency ?? '',
    );
    final contractPaymentMethodCtrl = TextEditingController(
      text: user?.workContractPaymentMethod ?? '',
    );
    final contractWorkScheduleCtrl = TextEditingController(
      text: user?.workContractWorkSchedule ?? '',
    );
    final contractWorkLocationCtrl = TextEditingController(
      text: user?.workContractWorkLocation ?? '',
    );
    final contractCustomClausesCtrl = TextEditingController(
      text: user?.workContractCustomClauses ?? '',
    );
    final passwordCtrl = TextEditingController();
    final habilidadCtrl = TextEditingController();
    String selectedRole = user?.appRole == AppRole.admin ? 'ADMIN' : 'CAJERO';
    bool blocked = user?.blocked ?? false;
    bool tieneHijos = user?.tieneHijos ?? false;
    bool estaCasado = user?.estaCasado ?? false;
    bool casaPropia = user?.casaPropia ?? false;
    bool vehiculo = user?.vehiculo ?? false;
    bool licenciaConducir = user?.licenciaConducir ?? false;
    DateTime? fechaIngreso = user?.fechaIngreso;
    DateTime? fechaNacimiento = user?.fechaNacimiento;
    DateTime? workContractStartDate = user?.workContractStartDate;
    final habilidades = [...user?.habilidades ?? const <String>[]];
    String? fotoCedulaUrl = user?.fotoCedulaUrl;
    String? fotoLicenciaUrl = user?.fotoLicenciaUrl;
    String? fotoPersonalUrl = user?.fotoPersonalUrl;
    final formScrollController = ScrollController();

    Widget sectionHeader(
      BuildContext modalContext,
      String title, {
      String? subtitle,
    }) {
      final theme = Theme.of(modalContext);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 12),
        ],
      );
    }

    Future<void> submitUser(BuildContext modalContext) async {
      final edad = int.tryParse(edadCtrl.text.trim()) ?? user?.edad ?? 0;
      final cedula = cedulaCtrl.text.trim();
      final email = emailCtrl.text.trim();
      final name = nameCtrl.text.trim();
      final password = passwordCtrl.text.trim();
      final phone = phoneCtrl.text.trim().isNotEmpty
          ? phoneCtrl.text.trim()
          : cedula;
      final securityCode = numeroFlotaCtrl.text.trim().isNotEmpty
          ? numeroFlotaCtrl.text.trim()
          : cedula.replaceAll(RegExp(r'\D'), '');

      if (name.isEmpty) {
        showSnack(
          const SnackBar(content: Text('El nombre completo es obligatorio')),
        );
        return;
      }

      if (email.isEmpty || !email.contains('@')) {
        showSnack(const SnackBar(content: Text('Ingresa un correo válido')));
        return;
      }

      if (cedula.isEmpty) {
        showSnack(const SnackBar(content: Text('La cédula es obligatoria')));
        return;
      }

      if (securityCode.isEmpty) {
        showSnack(
          const SnackBar(
            content: Text('El código de seguridad es obligatorio'),
          ),
        );
        return;
      }

      if (phone.isEmpty) {
        showSnack(const SnackBar(content: Text('El teléfono es obligatorio')));
        return;
      }

      if (fechaIngreso == null) {
        showSnack(
          const SnackBar(content: Text('La fecha de ingreso es obligatoria')),
        );
        return;
      }

      if (password.isNotEmpty && password.length < 8) {
        showSnack(
          const SnackBar(
            content: Text('La contraseña debe tener al menos 8 caracteres'),
          ),
        );
        return;
      }

      final payload = <String, dynamic>{
        'email': email,
        'password': password.isEmpty ? null : password,
        'nombreCompleto': name,
        'telefono': phone,
        'numeroFlota': securityCode,
        'telefonoFamiliar': familiarPhoneCtrl.text.trim(),
        'cedula': cedula,
        'fotoCedulaUrl': fotoCedulaUrl,
        'fotoLicenciaUrl': fotoLicenciaUrl,
        'fotoPersonalUrl': fotoPersonalUrl,
        'edad': edad,
        'fechaIngreso': fechaIngreso?.toIso8601String(),
        'fechaNacimiento': fechaNacimiento?.toIso8601String(),
        'cuentaNominaPreferencial': cuentaNominaCtrl.text.trim(),
        'workContractJobTitle': contractJobTitleCtrl.text.trim(),
        'workContractSalary': contractSalaryCtrl.text.trim(),
        'workContractPaymentFrequency': contractPaymentFrequencyCtrl.text
            .trim(),
        'workContractPaymentMethod': contractPaymentMethodCtrl.text.trim(),
        'workContractWorkSchedule': contractWorkScheduleCtrl.text.trim(),
        'workContractWorkLocation': contractWorkLocationCtrl.text.trim(),
        'workContractCustomClauses': contractCustomClausesCtrl.text.trim(),
        'workContractStartDate': workContractStartDate?.toIso8601String(),
        'habilidades': habilidades,
        'tieneHijos': tieneHijos,
        'estaCasado': estaCasado,
        'casaPropia': casaPropia,
        'vehiculo': vehiculo,
        'licenciaConducir': licenciaConducir,
        'role': selectedRole,
        'blocked': blocked,
      };
      payload.removeWhere(
        (key, value) => value == null || (value is String && value.isEmpty),
      );

      if (user == null && !payload.containsKey('password')) {
        showSnack(
          const SnackBar(
            content: Text('La contraseña es obligatoria al crear'),
          ),
        );
        return;
      }

      try {
        if (user == null) {
          await ref.read(usersControllerProvider.notifier).create(payload);
          if (!modalContext.mounted) return;
          showSnack(const SnackBar(content: Text('Usuario creado')));
        } else {
          await ref
              .read(usersControllerProvider.notifier)
              .update(user.id, payload);
          if (!modalContext.mounted) return;
          showSnack(const SnackBar(content: Text('Usuario actualizado')));
        }
        if (!modalContext.mounted) return;
        Navigator.of(modalContext).pop();
      } catch (e) {
        if (!modalContext.mounted) return;
        final message = e is ApiException ? e.message : e.toString();
        showSnack(SnackBar(content: Text('No se pudo guardar: $message')));
      }
    }

    Widget buildFormBody(
      BuildContext modalContext,
      void Function(VoidCallback fn) setModalState,
    ) {
      return Scrollbar(
        controller: formScrollController,
        thumbVisibility: true,
        child: ListView(
          controller: formScrollController,
          primary: false,
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
          children: [
            sectionHeader(
              modalContext,
              'Información principal',
              subtitle:
                  'Solo los campos importantes para alta, acceso y permisos.',
            ),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nombre completo'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: 'Correo'),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: cedulaCtrl,
              decoration: const InputDecoration(labelText: 'Número de cédula'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedRole,
              decoration: const InputDecoration(labelText: 'Rol'),
              items: const [
                DropdownMenuItem(value: 'ADMIN', child: Text('Administrador')),
                DropdownMenuItem(value: 'CAJERO', child: Text('Cajero')),
              ],
              onChanged: (val) => selectedRole = val ?? 'CAJERO',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordCtrl,
              decoration: InputDecoration(
                labelText: user == null
                    ? 'Contraseña'
                    : 'Contraseña (opcional)',
              ),
              obscureText: true,
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fecha de ingreso'),
              subtitle: Text(
                fechaIngreso == null
                    ? 'Seleccionar fecha'
                    : DateFormat('dd/MM/yyyy').format(fechaIngreso!),
              ),
              trailing: const Icon(Icons.calendar_today_outlined),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: modalContext,
                  initialDate: fechaIngreso ?? now,
                  firstDate: DateTime(1990),
                  lastDate: DateTime(now.year + 5),
                );
                if (picked != null) {
                  setModalState(() => fechaIngreso = picked);
                }
              },
            ),
            if (user != null) ...[
              const SizedBox(height: 24),
              sectionHeader(modalContext, 'Estado de acceso'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Bloqueado'),
                value: blocked,
                onChanged: (v) => setModalState(() => blocked = v),
              ),
            ],
          ],
        ),
      );
    }

    Widget buildActionBar(BuildContext modalContext) {
      return SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(22, 10, 22, 18),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(modalContext).pop(),
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => submitUser(modalContext),
                child: Text(user == null ? 'Crear usuario' : 'Guardar cambios'),
              ),
            ),
          ],
        ),
      );
    }

    Widget buildSheet(
      BuildContext modalContext,
      void Function(VoidCallback fn) setModalState, {
      required bool desktop,
    }) {
      final theme = Theme.of(modalContext);
      final title = user == null ? 'Nuevo usuario' : 'Editar usuario';

      return Material(
        color: theme.colorScheme.surface,
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: desktop
                ? const BorderRadius.horizontal(left: Radius.circular(28))
                : BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 28,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(22, 18, 14, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withValues(alpha: 0.84),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user == null
                                  ? 'Completa solo los datos esenciales para crear el acceso.'
                                  : 'Actualiza los datos principales del usuario.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onPrimary.withValues(
                                  alpha: 0.84,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(modalContext).pop(),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.18),
                          foregroundColor: theme.colorScheme.onPrimary,
                        ),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(child: buildFormBody(modalContext, setModalState)),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    top: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                ),
                child: buildActionBar(modalContext),
              ),
            ],
          ),
        ),
      );
    }

    final isDesktop = _isDesktop(context);
    final dialogFuture = isDesktop
        ? showGeneralDialog<void>(
            context: context,
            barrierDismissible: true,
            barrierLabel: user == null ? 'Crear usuario' : 'Editar usuario',
            barrierColor: Colors.black.withValues(alpha: 0.22),
            transitionDuration: const Duration(milliseconds: 260),
            pageBuilder: (dialogContext, animation, secondaryAnimation) {
              final size = MediaQuery.sizeOf(dialogContext);
              final panelWidth = size.width >= 1700
                  ? 760.0
                  : size.width >= 1440
                  ? 700.0
                  : size.width >= 1200
                  ? 640.0
                  : (size.width * 0.52).clamp(540.0, 700.0);

              return Material(
                color: Colors.transparent,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: panelWidth,
                    height: size.height,
                    child: StatefulBuilder(
                      builder: (dialogContext, setModalState) => buildSheet(
                        dialogContext,
                        setModalState,
                        desktop: true,
                      ),
                    ),
                  ),
                ),
              );
            },
            transitionBuilder: (context, animation, secondaryAnimation, child) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return FadeTransition(
                opacity: Tween<double>(begin: 0, end: 1).animate(curved),
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.08, 0),
                    end: Offset.zero,
                  ).animate(curved),
                  child: child,
                ),
              );
            },
          )
        : showDialog<void>(
            context: context,
            builder: (dialogContext) {
              final size = MediaQuery.sizeOf(dialogContext);
              return Dialog(
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                backgroundColor: Colors.transparent,
                elevation: 0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 720,
                    maxHeight: size.height * 0.94,
                  ),
                  child: StatefulBuilder(
                    builder: (dialogContext, setModalState) => buildSheet(
                      dialogContext,
                      setModalState,
                      desktop: false,
                    ),
                  ),
                ),
              );
            },
          );

    dialogFuture.whenComplete(() {
      nameCtrl.dispose();
      emailCtrl.dispose();
      phoneCtrl.dispose();
      numeroFlotaCtrl.dispose();
      cedulaCtrl.dispose();
      familiarPhoneCtrl.dispose();
      edadCtrl.dispose();
      cuentaNominaCtrl.dispose();
      contractJobTitleCtrl.dispose();
      contractSalaryCtrl.dispose();
      contractPaymentFrequencyCtrl.dispose();
      contractPaymentMethodCtrl.dispose();
      contractWorkScheduleCtrl.dispose();
      contractWorkLocationCtrl.dispose();
      contractCustomClausesCtrl.dispose();
      passwordCtrl.dispose();
      habilidadCtrl.dispose();
      formScrollController.dispose();
    });
  }

  Future<void> _showDeleteDialog(
    BuildContext context,
    WidgetRef ref,
    UserModel user,
  ) async {
    final allowed = await ensureAdminAuthorization(
      context,
      ref,
      permission: AppPermission.manageUsers,
      reason: 'Eliminar usuario',
    );
    if (!allowed || !context.mounted) return;
    final scaffoldContext = context;

    void showSnack(SnackBar snackBar) {
      if (!scaffoldContext.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(scaffoldContext);
      if (messenger == null) return;
      messenger.showSnackBar(snackBar);
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Usuario'),
        content: Text('¿Eliminar a ${user.nombreCompleto}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              try {
                await ref
                    .read(usersControllerProvider.notifier)
                    .delete(user.id);
                if (!context.mounted) return;
                Navigator.pop(context);
                showSnack(const SnackBar(content: Text('Usuario eliminado')));
              } catch (e) {
                if (!context.mounted) return;
                showSnack(SnackBar(content: Text('No se pudo eliminar: $e')));
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  void _openUserDetailsScreen(BuildContext context, UserModel user) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _UserDetailsScreen(
          user: user,
          onOpenContract: () => _openWorkContractPreview(context, user),
        ),
      ),
    );
  }
}

class _UserDetailsScreen extends StatelessWidget {
  const _UserDetailsScreen({required this.user, required this.onOpenContract});

  final UserModel user;
  final Future<void> Function() onOpenContract;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de usuario'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.tonalIcon(
              onPressed: onOpenContract,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Contrato'),
            ),
          ),
        ],
      ),
      body: Container(
        color: theme.colorScheme.surfaceContainerLowest,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    child: Row(
                      children: [
                        _UserAvatar(user: user, radius: 30),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user.nombreCompleto,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                user.email,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _UserStatusBadge(blocked: user.blocked),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _DetailSection(
                    title: 'Información principal',
                    children: [
                      _DetailRow('Nombre', user.nombreCompleto),
                      _DetailRow('Email', user.email),
                      _DetailRow('Rol', _managementRole(user).label),
                      _DetailRow('Teléfono', user.telefono),
                      _DetailRow(
                        'Teléfono familiar',
                        user.telefonoFamiliar ?? '—',
                      ),
                      _DetailRow('Cédula', user.cedula ?? '—'),
                      _DetailRow('Edad', user.edad?.toString() ?? '—'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _DetailSection(
                    title: 'Datos laborales y personales',
                    children: [
                      _DetailRow('Tiene hijos', user.tieneHijos ? 'Sí' : 'No'),
                      _DetailRow(
                        'Estado civil',
                        user.estaCasado ? 'Casado/a' : 'Soltero/a',
                      ),
                      _DetailRow('Casa propia', user.casaPropia ? 'Sí' : 'No'),
                      _DetailRow('Vehículo', user.vehiculo ? 'Sí' : 'No'),
                      _DetailRow(
                        'Licencia',
                        user.licenciaConducir ? 'Sí' : 'No',
                      ),
                      _DetailRow(
                        'Fecha de ingreso',
                        user.fechaIngreso != null
                            ? DateFormat(
                                'dd/MM/yyyy',
                              ).format(user.fechaIngreso!)
                            : '—',
                      ),
                      _DetailRow(
                        'Días en la empresa',
                        user.diasEnEmpresa?.toString() ?? '—',
                      ),
                      _DetailRow(
                        'Cuenta nómina preferencial',
                        (user.cuentaNominaPreferencial ?? '').trim().isEmpty
                            ? '—'
                            : user.cuentaNominaPreferencial!.trim(),
                      ),
                      _DetailRow(
                        'Habilidades',
                        user.habilidades.isEmpty
                            ? '—'
                            : user.habilidades.join(', '),
                      ),
                      _DetailRow(
                        'Creado',
                        user.createdAt != null
                            ? DateFormat('dd/MM/yyyy').format(user.createdAt!)
                            : '—',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _DetailSection(
                    title: 'Documentos',
                    children: [
                      _UserDocumentPreviewCard(
                        title: 'Foto de cédula',
                        imageUrl: _resolveUserDocUrl(user.fotoCedulaUrl),
                      ),
                      const SizedBox(height: 10),
                      _UserDocumentPreviewCard(
                        title: 'Foto de licencia',
                        imageUrl: _resolveUserDocUrl(user.fotoLicenciaUrl),
                      ),
                      const SizedBox(height: 10),
                      _UserDocumentPreviewCard(
                        title: 'Foto personal',
                        imageUrl: _resolveUserDocUrl(user.fotoPersonalUrl),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UserPermissionDetailsPanel extends StatelessWidget {
  const _UserPermissionDetailsPanel({
    required this.user,
    required this.onEdit,
    required this.onToggleBlock,
    required this.onOpenContract,
    required this.onEditPermissions,
  });

  final UserModel? user;
  final VoidCallback? onEdit;
  final VoidCallback? onToggleBlock;
  final VoidCallback? onOpenContract;
  final VoidCallback? onEditPermissions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedUser = user;

    return Container(
      height: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: selectedUser == null
          ? _DesktopUsersEmptyState(
              icon: Icons.manage_accounts_outlined,
              title: 'Selecciona un usuario',
              message:
                  'El detalle y los permisos por pantalla se muestran aquí.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _UserAvatar(user: selectedUser, radius: 26),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  selectedUser.nombreCompleto,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  selectedUser.email,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _UserRoleBadge(role: _managementRole(selectedUser)),
                          _UserStatusBadge(blocked: selectedUser.blocked),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _DetailRow('Teléfono', selectedUser.telefono),
                _DetailRow('Cédula', selectedUser.cedula ?? '—'),
                _DetailRow(
                  'Ingreso',
                  selectedUser.fechaIngreso == null
                      ? '—'
                      : DateFormat(
                          'dd/MM/yyyy',
                        ).format(selectedUser.fechaIngreso!),
                ),
                const SizedBox(height: 14),
                if (onEditPermissions != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onEditPermissions,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Administrar permisos'),
                    ),
                  ),
                ] else ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.successBorder),
                    ),
                    child: Text(
                      'El administrador tiene todos los permisos.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onEdit,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Editar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: selectedUser.blocked
                          ? 'Desbloquear'
                          : 'Bloquear',
                      onPressed: onToggleBlock,
                      icon: Icon(
                        selectedUser.blocked
                            ? Icons.lock_open_outlined
                            : Icons.lock_outline,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Contrato',
                      onPressed: onOpenContract,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Permisos por pantalla',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      '${_allowedPermissionCount(selectedUser)}/${_userScreenPermissions.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.separated(
                    itemCount: _userScreenPermissions.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 7),
                    itemBuilder: (context, index) {
                      final item = _userScreenPermissions[index];
                      final allowed = hasUserPermission(
                        selectedUser,
                        item.permission,
                      );
                      return _PermissionScreenTile(
                        icon: item.icon,
                        title: item.title,
                        allowed: allowed,
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

int _allowedPermissionCount(UserModel user) {
  var count = 0;
  for (final item in _userScreenPermissions) {
    if (hasUserPermission(user, item.permission)) count++;
  }
  return count;
}

class _PermissionScreenItem {
  const _PermissionScreenItem({
    required this.title,
    required this.icon,
    required this.permission,
  });

  final String title;
  final IconData icon;
  final AppPermission permission;
}

const _userScreenPermissions = <_PermissionScreenItem>[
  _PermissionScreenItem(
    title: 'Facturación',
    icon: Icons.point_of_sale_outlined,
    permission: AppPermission.viewQuotes,
  ),
  _PermissionScreenItem(
    title: 'Clientes',
    icon: Icons.group_outlined,
    permission: AppPermission.viewClients,
  ),
  _PermissionScreenItem(
    title: 'Inventario',
    icon: Icons.inventory_2_outlined,
    permission: AppPermission.viewCatalog,
  ),
  _PermissionScreenItem(
    title: 'Reportes',
    icon: Icons.bar_chart_rounded,
    permission: AppPermission.viewSalesReports,
  ),
  _PermissionScreenItem(
    title: 'Compras',
    icon: Icons.shopping_cart_checkout_outlined,
    permission: AppPermission.viewPurchases,
  ),
  _PermissionScreenItem(
    title: 'Contabilidad',
    icon: Icons.account_balance_outlined,
    permission: AppPermission.viewAccounting,
  ),
  _PermissionScreenItem(
    title: 'Nómina',
    icon: Icons.payments_outlined,
    permission: AppPermission.managePayroll,
  ),
  _PermissionScreenItem(
    title: 'Usuarios',
    icon: Icons.manage_accounts_outlined,
    permission: AppPermission.manageUsers,
  ),
  _PermissionScreenItem(
    title: 'Configuración',
    icon: Icons.settings_outlined,
    permission: AppPermission.manageSettings,
  ),
];

class _PermissionActionItem {
  const _PermissionActionItem({
    required this.title,
    required this.permission,
    required this.description,
  });

  final String title;
  final AppPermission permission;
  final String description;
}

class _PermissionModuleItem {
  const _PermissionModuleItem({
    required this.title,
    required this.icon,
    required this.viewPermission,
    required this.actions,
  });

  final String title;
  final IconData icon;
  final AppPermission viewPermission;
  final List<_PermissionActionItem> actions;
}

const _permissionModules = <_PermissionModuleItem>[
  _PermissionModuleItem(
    title: 'Facturación',
    icon: Icons.point_of_sale_outlined,
    viewPermission: AppPermission.viewQuotes,
    actions: [
      _PermissionActionItem(
        title: 'Crear cotizaciones',
        permission: AppPermission.viewQuotes,
        description: 'Permite cotizar y guardar cotizaciones.',
      ),
      _PermissionActionItem(
        title: 'Registrar ventas y caja',
        permission: AppPermission.viewSales,
        description: 'Permite vender y trabajar en el POS.',
      ),
      _PermissionActionItem(
        title: 'Aplicar descuentos',
        permission: AppPermission.applyDiscounts,
        description: 'Permite aplicar rebajas al detalle o al total.',
      ),
      _PermissionActionItem(
        title: 'Reembolsar o devolver ventas',
        permission: AppPermission.refundSales,
        description: 'Autoriza acciones de devolución y reembolso.',
      ),
      _PermissionActionItem(
        title: 'Factura fiscal e ITBIS',
        permission: AppPermission.createFiscalInvoices,
        description: 'Permite activar ITBIS y comprobantes con valor fiscal.',
      ),
      _PermissionActionItem(
        title: 'Ver reportes de ventas',
        permission: AppPermission.viewSalesReports,
        description: 'Muestra reportes, totales e histórico comercial.',
      ),
    ],
  ),
  _PermissionModuleItem(
    title: 'Clientes',
    icon: Icons.group_outlined,
    viewPermission: AppPermission.viewClients,
    actions: [
      _PermissionActionItem(
        title: 'Crear y editar clientes',
        permission: AppPermission.viewClients,
        description: 'Permite abrir la cartera, crear y editar clientes.',
      ),
    ],
  ),
  _PermissionModuleItem(
    title: 'Inventario',
    icon: Icons.inventory_2_outlined,
    viewPermission: AppPermission.viewCatalog,
    actions: [
      _PermissionActionItem(
        title: 'Agregar stock',
        permission: AppPermission.addStock,
        description: 'Autoriza entradas o ajustes de inventario.',
      ),
      _PermissionActionItem(
        title: 'Editar productos',
        permission: AppPermission.editProducts,
        description: 'Permite modificar fichas, precios y datos de producto.',
      ),
    ],
  ),
  _PermissionModuleItem(
    title: 'Compras',
    icon: Icons.shopping_cart_checkout_outlined,
    viewPermission: AppPermission.viewPurchases,
    actions: [
      _PermissionActionItem(
        title: 'Crear compras',
        permission: AppPermission.createPurchases,
        description: 'Permite registrar órdenes de compra.',
      ),
      _PermissionActionItem(
        title: 'Editar compras',
        permission: AppPermission.editPurchases,
        description: 'Permite cambiar órdenes antes de cerrarlas.',
      ),
      _PermissionActionItem(
        title: 'Aprobar compras',
        permission: AppPermission.approvePurchases,
        description: 'Autoriza aprobar órdenes y decisiones de compra.',
      ),
      _PermissionActionItem(
        title: 'Recibir mercancía',
        permission: AppPermission.receivePurchases,
        description: 'Permite recibir artículos y afectar inventario.',
      ),
    ],
  ),
  _PermissionModuleItem(
    title: 'Contabilidad',
    icon: Icons.account_balance_outlined,
    viewPermission: AppPermission.viewAccounting,
    actions: [
      _PermissionActionItem(
        title: 'Ver contabilidad',
        permission: AppPermission.viewAccounting,
        description: 'Acceso a cierres, depósitos y facturas fiscales.',
      ),
    ],
  ),
  _PermissionModuleItem(
    title: 'Nómina',
    icon: Icons.payments_outlined,
    viewPermission: AppPermission.managePayroll,
    actions: [
      _PermissionActionItem(
        title: 'Administrar nómina',
        permission: AppPermission.managePayroll,
        description: 'Permite crear, revisar y cerrar pagos de nómina.',
      ),
    ],
  ),
  _PermissionModuleItem(
    title: 'Usuarios',
    icon: Icons.manage_accounts_outlined,
    viewPermission: AppPermission.manageUsers,
    actions: [
      _PermissionActionItem(
        title: 'Crear y editar usuarios',
        permission: AppPermission.manageUsers,
        description: 'Control total sobre usuarios y permisos.',
      ),
    ],
  ),
  _PermissionModuleItem(
    title: 'Configuración',
    icon: Icons.settings_outlined,
    viewPermission: AppPermission.manageSettings,
    actions: [
      _PermissionActionItem(
        title: 'Administrar configuración',
        permission: AppPermission.manageSettings,
        description:
            'Permite abrir configuración, apps, licencias y parámetros de empresa.',
      ),
    ],
  ),
];

class UserPermissionsScreen extends ConsumerStatefulWidget {
  const UserPermissionsScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<UserPermissionsScreen> createState() =>
      _UserPermissionsScreenState();
}

class _UserPermissionsScreenState extends ConsumerState<UserPermissionsScreen> {
  Map<String, bool>? _draft;
  bool _saving = false;

  UserModel? _findUser(List<UserModel> users) {
    for (final user in users) {
      if (user.id == widget.userId) return user;
    }
    return null;
  }

  Map<String, bool> _buildInitialDraft(UserModel user) {
    final map = <String, bool>{};
    for (final module in _permissionModules) {
      map[module.viewPermission.name] = hasUserPermission(
        user,
        module.viewPermission,
      );
      for (final action in module.actions) {
        map[action.permission.name] = hasUserPermission(
          user,
          action.permission,
        );
      }
    }
    return map;
  }

  void _setPermission(AppPermission permission, bool value) {
    setState(() {
      final draft = _draft ?? <String, bool>{};
      draft[permission.name] = value;
      _draft = draft;
    });
  }

  void _setAllPermissions(UserModel user, bool value) {
    final draft = _draft ?? _buildInitialDraft(user);
    for (final permission in AppPermission.values) {
      draft[permission.name] = value;
    }
    setState(() => _draft = draft);
  }

  Future<void> _save(UserModel user) async {
    final allowed = await ensureAdminAuthorization(
      context,
      ref,
      permission: AppPermission.manageUsers,
      reason: 'Guardar permisos de usuario',
    );
    if (!allowed || !mounted) return;
    final draft = _draft ?? _buildInitialDraft(user);
    setState(() => _saving = true);
    try {
      await ref
          .read(usersControllerProvider.notifier)
          .updatePermissions(user.id, draft);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Permisos actualizados')));
      context.go(Routes.users);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usersState = ref.watch(usersControllerProvider);
    final currentUser = ref.watch(authStateProvider).user;

    return Scaffold(
      appBar: CustomAppBar(
        title: 'Editar permisos',
        showLogo: false,
        fallbackRoute: Routes.users,
        trailing: currentUser == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 12),
                child: UserAvatar(
                  radius: 16,
                  backgroundColor: Colors.white24,
                  imageUrl: currentUser.fotoPersonalUrl,
                  child: Text(
                    getInitials(currentUser.nombreCompleto),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      body: usersState.when(
        loading: () => const Center(child: Text('Sincronizando permisos...')),
        error: (e, _) => Center(child: Text('No se pudo cargar: $e')),
        data: (users) {
          final user = _findUser(users);
          if (user == null) {
            return const Center(child: Text('Usuario no encontrado'));
          }
          if (_managementRole(user) == AppRole.admin) {
            return const Center(
              child: Text('El administrador siempre tiene todos los permisos'),
            );
          }

          final draft = _draft ??= _buildInitialDraft(user);
          return Container(
            color: theme.colorScheme.surfaceContainerLowest,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(28, 22, 28, 24),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          border: Border.all(
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                        child: Row(
                          children: [
                            _UserAvatar(user: user, radius: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user.nombreCompleto,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    '${user.email}  •  Cajero',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _saving
                                  ? null
                                  : () => _setAllPermissions(user, true),
                              icon: const Icon(Icons.done_all_rounded),
                              label: const Text('Dar todos'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: _saving
                                  ? null
                                  : () => _setAllPermissions(user, false),
                              icon: const Icon(Icons.remove_done_outlined),
                              label: const Text('Quitar todos'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      for (final module in _permissionModules) ...[
                        _PermissionModuleEditor(
                          module: module,
                          draft: draft,
                          onChanged: _setPermission,
                        ),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(
                      top: BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(28, 12, 28, 16),
                    child: Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => context.go(Routes.users),
                          icon: const Icon(Icons.arrow_back_outlined),
                          label: const Text('Volver'),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          onPressed: _saving ? null : () => _save(user),
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(_saving ? 'Guardando' : 'Guardar'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PermissionModuleEditor extends StatelessWidget {
  const _PermissionModuleEditor({
    required this.module,
    required this.draft,
    required this.onChanged,
  });

  final _PermissionModuleItem module;
  final Map<String, bool> draft;
  final void Function(AppPermission permission, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final moduleEnabled = draft[module.viewPermission.name] ?? false;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          CheckboxListTile(
            value: moduleEnabled,
            onChanged: (value) =>
                onChanged(module.viewPermission, value ?? false),
            secondary: Icon(module.icon),
            title: Text(
              module.title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: const Text('Permiso para ver este módulo'),
            controlAffinity: ListTileControlAffinity.trailing,
          ),
          const Divider(height: 1),
          for (final action in module.actions)
            CheckboxListTile(
              value: draft[action.permission.name] ?? false,
              onChanged: moduleEnabled
                  ? (value) => onChanged(action.permission, value ?? false)
                  : null,
              title: Text(action.title),
              subtitle: Text(action.description),
              controlAffinity: ListTileControlAffinity.trailing,
            ),
        ],
      ),
    );
  }
}

class _PermissionScreenTile extends StatelessWidget {
  const _PermissionScreenTile({
    required this.icon,
    required this.title,
    required this.allowed,
  });

  final IconData icon;
  final String title;
  final bool allowed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = allowed ? AppColors.success : AppColors.textMuted;
    final background = allowed
        ? AppColors.successSoft
        : const Color(0xFFF1F5F9);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: allowed ? AppColors.successBorder : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground, size: 19),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Icon(
            allowed ? Icons.check_circle : Icons.remove_circle_outline,
            color: foreground,
            size: 18,
          ),
        ],
      ),
    );
  }
}

class _UsersTable extends StatelessWidget {
  const _UsersTable({
    required this.users,
    required this.selectedUserId,
    required this.onSelectUser,
    required this.onViewUser,
    required this.onEditUser,
    required this.onDeleteUser,
    required this.onToggleBlock,
    required this.onOpenContract,
  });

  final List<UserModel> users;
  final String? selectedUserId;
  final ValueChanged<UserModel> onSelectUser;
  final ValueChanged<UserModel> onViewUser;
  final ValueChanged<UserModel> onEditUser;
  final ValueChanged<UserModel> onDeleteUser;
  final ValueChanged<UserModel> onToggleBlock;
  final ValueChanged<UserModel> onOpenContract;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (users.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: _DesktopUsersEmptyState(
            icon: Icons.group_off_outlined,
            title: 'Sin empleados',
            message: 'Aún no hay empleados registrados.',
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth < 1120
            ? 1120.0
            : constraints.maxWidth;
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Scrollbar(
              thumbVisibility: constraints.maxWidth < tableWidth,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  child: Column(
                    children: [
                      const _UsersTableHeader(),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.only(bottom: 16),
                          itemCount: users.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: theme.colorScheme.outlineVariant,
                          ),
                          itemBuilder: (context, index) {
                            final user = users[index];
                            return _UserRowCard(
                              user: user,
                              selected: user.id == selectedUserId,
                              onSelect: () => onSelectUser(user),
                              onView: () => onViewUser(user),
                              onEdit: () => onEditUser(user),
                              onDelete: () => onDeleteUser(user),
                              onToggleBlock: () => onToggleBlock(user),
                              onOpenContract: () => onOpenContract(user),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _UsersTableHeader extends StatelessWidget {
  const _UsersTableHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: AppColors.textMuted,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
    );

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: AppColors.surfaceMuted,
      child: Row(
        children: [
          _UserTableHeaderCell('Nombre', flex: 20, style: style),
          _UserTableHeaderCell('Correo', flex: 24, style: style),
          _UserTableHeaderCell('Fecha ingreso', flex: 15, style: style),
          _UserTableHeaderCell('Cédula', flex: 15, style: style),
          _UserTableHeaderCell('Teléfono', flex: 14, style: style),
          _UserTableHeaderCell('Rol', flex: 12, style: style),
          _UserTableHeaderCell('Detalle', flex: 10, style: style),
        ],
      ),
    );
  }
}

class _UserTableHeaderCell extends StatelessWidget {
  const _UserTableHeaderCell(this.text, {required this.flex, this.style});

  final String text;
  final int flex;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}

class _UserRowCard extends StatefulWidget {
  const _UserRowCard({
    required this.user,
    required this.selected,
    required this.onSelect,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleBlock,
    required this.onOpenContract,
  });

  final UserModel user;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleBlock;
  final VoidCallback onOpenContract;

  @override
  State<_UserRowCard> createState() => _UserRowCardState();
}

class _UserRowCardState extends State<_UserRowCard> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_hovered == value) return;
      setState(() => _hovered = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaceColor = widget.selected
        ? AppColors.secondarySoft
        : _hovered
        ? AppColors.surfaceMuted
        : theme.colorScheme.surface;

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: Material(
        color: surfaceColor,
        borderRadius: BorderRadius.zero,
        child: InkWell(
          borderRadius: BorderRadius.zero,
          onTap: widget.onSelect,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            constraints: const BoxConstraints(minHeight: 62),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.zero,
              border: Border(
                left: BorderSide(
                  color: widget.selected
                      ? AppColors.secondary
                      : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 20,
                  child: Row(
                    children: [
                      _UserAvatar(user: widget.user, radius: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.user.nombreCompleto,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(flex: 24, child: _UserTableText(widget.user.email)),
                Expanded(
                  flex: 15,
                  child: _UserTableText(
                    widget.user.fechaIngreso == null
                        ? '—'
                        : DateFormat(
                            'dd/MM/yyyy',
                          ).format(widget.user.fechaIngreso!),
                  ),
                ),
                Expanded(
                  flex: 15,
                  child: _UserTableText(widget.user.cedula ?? '—'),
                ),
                Expanded(flex: 14, child: _UserTableText(widget.user.telefono)),
                Expanded(
                  flex: 12,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _UserRoleBadge(role: _managementRole(widget.user)),
                  ),
                ),
                Expanded(
                  flex: 10,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: PopupMenuButton<_UserMenuAction>(
                      tooltip: 'Acciones',
                      icon: const Icon(Icons.more_vert),
                      onSelected: (action) {
                        switch (action) {
                          case _UserMenuAction.ver:
                            widget.onView();
                            break;
                          case _UserMenuAction.editar:
                            widget.onEdit();
                            break;
                          case _UserMenuAction.contrato:
                            widget.onOpenContract();
                            break;
                          case _UserMenuAction.bloquear:
                            widget.onToggleBlock();
                            break;
                          case _UserMenuAction.eliminar:
                            widget.onDelete();
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: _UserMenuAction.ver,
                          child: Text('Ver detalle'),
                        ),
                        const PopupMenuItem(
                          value: _UserMenuAction.editar,
                          child: Text('Editar'),
                        ),
                        const PopupMenuItem(
                          value: _UserMenuAction.contrato,
                          child: Text('Contrato'),
                        ),
                        PopupMenuItem(
                          value: _UserMenuAction.bloquear,
                          child: Text(
                            widget.user.blocked ? 'Desbloquear' : 'Bloquear',
                          ),
                        ),
                        const PopupMenuItem(
                          value: _UserMenuAction.eliminar,
                          child: Text('Eliminar'),
                        ),
                      ],
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

class _UserTableText extends StatelessWidget {
  const _UserTableText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.trim().isEmpty ? '—' : text.trim(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppColors.textMuted,
        letterSpacing: 0,
      ),
    );
  }
}

class _UserStatusBadge extends StatelessWidget {
  const _UserStatusBadge({required this.blocked});

  final bool blocked;

  @override
  Widget build(BuildContext context) {
    final background = blocked ? AppColors.warningSoft : AppColors.successSoft;
    final foreground = blocked ? AppColors.warning : AppColors.success;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        blocked ? 'Bloqueado' : 'Activo',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _UserRoleBadge extends StatelessWidget {
  const _UserRoleBadge({required this.role});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final colors = switch (role) {
      AppRole.admin => (const Color(0xFFFCE7F3), const Color(0xFF9D174D)),
      AppRole.cajero => (const Color(0xFFE0F2FE), const Color(0xFF0369A1)),
      AppRole.asistente => (const Color(0xFFECFDF5), const Color(0xFF047857)),
      AppRole.vendedor => (AppColors.secondarySoft, const Color(0xFF1D4ED8)),
      AppRole.marketing => (const Color(0xFFF5F3FF), const Color(0xFF6D28D9)),
      AppRole.tecnico => (const Color(0xFFFFF7ED), const Color(0xFFC2410C)),
      AppRole.unknown => (const Color(0xFFF1F5F9), const Color(0xFF475569)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        role.label.isEmpty ? 'Sin rol' : role.label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.$2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.user, required this.radius});

  final UserModel user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final role = _managementRole(user);
    final background = switch (role) {
      AppRole.admin => const Color(0xFF9D174D),
      AppRole.cajero => const Color(0xFF0369A1),
      AppRole.asistente => const Color(0xFF047857),
      AppRole.vendedor => const Color(0xFF1D4ED8),
      AppRole.marketing => const Color(0xFF6D28D9),
      AppRole.tecnico => const Color(0xFFC2410C),
      AppRole.unknown => const Color(0xFF475569),
    };

    final imageUrl = (user.fotoPersonalUrl ?? '').trim();
    return UserAvatar(
      radius: radius,
      backgroundColor: background,
      imageUrl: imageUrl,
      child: Text(
        getInitials(user.nombreCompleto),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: radius * 0.72,
        ),
      ),
    );
  }
}

class _DesktopUsersEmptyState extends StatelessWidget {
  const _DesktopUsersEmptyState({
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 30, color: const Color(0xFF0284C7)),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.textMuted,
              height: 1.45,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

enum _UserMenuAction { ver, editar, contrato, bloquear, eliminar }

class _UserCard extends StatelessWidget {
  const _UserCard({
    required this.user,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleBlock,
  });

  final UserModel user;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggleBlock;

  @override
  Widget build(BuildContext context) {
    final statusText = user.blocked ? 'Bloqueado' : 'Activo';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onView,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: _getRoleColor(_managementRole(user)),
          child: Text(
            getInitials(user.nombreCompleto),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          '${user.nombreCompleto} • ${_managementRole(user).label} • $statusText',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          user.telefono,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Theme.of(context).colorScheme.outline),
        ),
        trailing: PopupMenuButton<_UserMenuAction>(
          icon: const Icon(Icons.more_vert),
          onSelected: (action) {
            switch (action) {
              case _UserMenuAction.ver:
                onView();
                break;
              case _UserMenuAction.editar:
                onEdit();
                break;
              case _UserMenuAction.contrato:
                onView();
                break;
              case _UserMenuAction.bloquear:
                onToggleBlock();
                break;
              case _UserMenuAction.eliminar:
                onDelete();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: _UserMenuAction.editar,
              child: Text('Editar'),
            ),
            PopupMenuItem(
              value: _UserMenuAction.bloquear,
              child: Text(user.blocked ? 'Desbloquear' : 'Bloquear'),
            ),
            const PopupMenuItem(
              value: _UserMenuAction.eliminar,
              child: Text('Eliminar'),
            ),
          ],
        ),
      ),
    );
  }

  Color _getRoleColor(AppRole role) {
    switch (role) {
      case AppRole.admin:
        return Colors.red;
      case AppRole.cajero:
        return Colors.lightBlue;
      case AppRole.asistente:
      case AppRole.vendedor:
      case AppRole.marketing:
      case AppRole.tecnico:
      case AppRole.unknown:
        return Colors.grey;
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// Provee el token de sesión para cargar imágenes de documentos que el
/// endpoint /media/object sirve únicamente con autenticación JWT.
class _UserDocImageCache {
  static final TokenStorage storage = TokenStorage();

  static Future<String?> token() => storage.getAccessToken();
}

class _UserDocumentPreviewCard extends StatelessWidget {
  const _UserDocumentPreviewCard({required this.title, required this.imageUrl});

  final String title;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    final outline = Theme.of(context).colorScheme.outlineVariant;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 150,
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: hasImage
                  ? FutureBuilder<String?>(
                      future: isFlutterTest
                          ? Future<String?>.value()
                          : _UserDocImageCache.token(),
                      builder: (context, snapshot) {
                        final token = snapshot.data?.trim();
                        final headers = token == null || token.isEmpty
                            ? null
                            : <String, String>{
                                'Authorization': 'Bearer $token',
                              };
                        return CachedNetworkImage(
                          imageUrl: imageUrl!,
                          httpHeaders: headers,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const _DocumentImageFallback(
                            text: 'Cargando imagen...',
                          ),
                          errorWidget: (_, __, ___) =>
                              const _DocumentImageFallback(
                                text: 'No se pudo cargar la imagen',
                              ),
                        );
                      },
                    )
                  : const _DocumentImageFallback(text: 'Sin imagen'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentImageFallback extends StatelessWidget {
  const _DocumentImageFallback({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.outline,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
