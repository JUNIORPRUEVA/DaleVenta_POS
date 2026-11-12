import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/admin_authorization.dart';
import '../../core/auth/app_permissions.dart';
import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/errors/api_exception.dart';
import '../../core/errors/user_safe_error_text.dart';
import '../../core/models/user_model.dart';
import '../../core/pagination/paged_load_more_footer.dart';
import '../../core/routing/app_navigator.dart';
import '../../core/routing/routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/app_feedback.dart';
import '../../core/utils/string_utils.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/user_avatar.dart';
import '../user/application/users_controller.dart';

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

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _isDesktop(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= _desktopBreakpoint;

  void _showModuleNotification(
    BuildContext context, {
    required String title,
    required String body,
    AppFeedbackKind kind = AppFeedbackKind.success,
  }) {
    AppFeedback.showPersistentNotification(
      context,
      AppFeedbackNotification(title: title, body: body, kind: kind),
      scope: 'users',
    );
  }

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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: OutlinedButton(
              onPressed: () => _showAdminPinDialog(context, ref),
              style: _pinButtonStyle(),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [_AdminPinIcon(), SizedBox(width: 6), Text('PIN')],
              ),
            ),
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
              Text(
                userSafeErrorMessage(
                  e,
                  fallback: 'No se pudieron cargar los usuarios.',
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () =>
                    ref.read(usersControllerProvider.notifier).refresh(),
                child: const Text('Reintentar'),
              ),
            ],
          ),
          data: (users) {
            final controller = ref.read(usersControllerProvider.notifier);
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
                  if (controller.hasMore || controller.loadingMore) ...[
                    const SizedBox(height: 16),
                    LoadMoreFooter(
                      loading: controller.loadingMore,
                      hasMore: true,
                      label: 'Ver más',
                      onLoadMore: () =>
                          ref.read(usersControllerProvider.notifier).loadMore(),
                    ),
                  ],
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount:
                  filteredUsers.length +
                  (controller.hasMore || controller.loadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= filteredUsers.length) {
                  return LoadMoreFooter(
                    loading: controller.loadingMore,
                    hasMore: true,
                    label: 'Ver más',
                    onLoadMore: () =>
                        ref.read(usersControllerProvider.notifier).loadMore(),
                  );
                }
                final user = filteredUsers[index];
                return _UserCard(
                  user: user,
                  onView: () => _showUserDetailDialog(
                    context,
                    ref,
                    user,
                    filteredUsers,
                    currentUser,
                  ),
                  onEdit: () => _showUserDialog(context, ref, user),
                  onDelete: () => _showDeleteDialog(context, ref, user),
                  onToggleBlock:
                      _blockDisabledReason(user, filteredUsers, currentUser) ==
                          null
                      ? () => _toggleBlock(
                          context,
                          ref,
                          user,
                          filteredUsers,
                          currentUser,
                        )
                      : null,
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
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Usuarios y permisos',
        showLogo: false,
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
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: OutlinedButton(
              onPressed: () => _showAdminPinDialog(context, ref),
              style: _pinButtonStyle(),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [_AdminPinIcon(), SizedBox(width: 6), Text('PIN')],
              ),
            ),
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
        ],
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: currentUser),
      body: Container(
        color: AppColors.background,
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
                  message: userSafeErrorMessage(
                    e,
                    fallback:
                        'No pudimos cargar los usuarios. Inténtalo nuevamente.',
                  ),
                  actionLabel: 'Reintentar',
                  onAction: () =>
                      ref.read(usersControllerProvider.notifier).refresh(),
                ),
              ),
            ),
          ),
          data: (users) {
            final controller = ref.read(usersControllerProvider.notifier);
            final desktopUsers = _filterUsers(users, desktop: true)
              ..sort(
                (left, right) => left.nombreCompleto.toLowerCase().compareTo(
                  right.nombreCompleto.toLowerCase(),
                ),
              );

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: _UsersPanelCard(
                      users: desktopUsers,
                      hasMore: controller.hasMore,
                      loadingMore: controller.loadingMore,
                      onLoadMore: () =>
                          ref.read(usersControllerProvider.notifier).loadMore(),
                      onOpenUser: (user) => _showUserDetailDialog(
                        context,
                        ref,
                        user,
                        desktopUsers,
                        currentUser,
                      ),
                      onEditUser: (user) => _showUserDialog(context, ref, user),
                      onDeleteUser: (user) =>
                          _showDeleteDialog(context, ref, user),
                      onToggleBlock: (user) => _toggleBlock(
                        context,
                        ref,
                        user,
                        desktopUsers,
                        currentUser,
                      ),
                      blockDisabledReason: (user) =>
                          _blockDisabledReason(user, desktopUsers, currentUser),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Abre el detalle del usuario en el panel lateral derecho.
  ///
  /// Sustituye al antiguo panel permanente: misma información, mismas acciones
  /// y mismos permisos, mostrados solo cuando se piden. El panel se desliza
  /// desde el borde derecho, se dibuja por encima del contenido (incluido el
  /// AppBar) y NO desplaza la pantalla de fondo.
  Future<void> _showUserDetailDialog(
    BuildContext context,
    WidgetRef ref,
    UserModel user,
    List<UserModel> allUsers,
    UserModel? currentUser,
  ) async {
    final blockReason = _blockDisabledReason(user, allUsers, currentUser);
    final isAdmin = _managementRole(user) == AppRole.admin;

    await showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: 'Cerrar detalle de usuario',
      barrierColor: Colors.black.withValues(alpha: 0.24),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, _, __) => _UserDetailPanel(
        user: user,
        blockDisabledReason: blockReason,
        onEdit: () {
          Navigator.of(dialogContext).pop();
          _showUserDialog(context, ref, user);
        },
        onToggleBlock: blockReason == null
            ? () {
                Navigator.of(dialogContext).pop();
                _toggleBlock(context, ref, user, allUsers, currentUser);
              }
            : null,
        onEditPermissions: isAdmin
            ? null
            : () {
                Navigator.of(dialogContext).pop();
                _openPermissionsPanel(user);
              },
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  /// Abre el editor de permisos del usuario como panel lateral izquierdo.
  ///
  /// Reutiliza `UserPermissionsScreen` (mismos controladores, draft, acciones y
  /// guardado); solo cambia el contenedor de navegación.
  Future<void> _openPermissionsPanel(UserModel user) async {
    await showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: 'Editar permisos',
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (dialogContext, _, __) {
        final size = MediaQuery.sizeOf(dialogContext);
        final width = size.width < 700
            ? size.width
            : (size.width * 0.82).clamp(560.0, 1180.0);

        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: width,
            height: double.infinity,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                border: Border(right: BorderSide(color: AppColors.border)),
              ),
              child: UserPermissionsScreen(userId: user.id, embedded: true),
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
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  Future<void> _showAdminPinDialog(BuildContext context, WidgetRef ref) async {
    final settingsRepository = ref.read(companySettingsRepositoryProvider);
    final pinCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool saving = false;
    bool obscurePin = true;

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
                await settingsRepository.setAdminAuthorizationPin(pin);
                if (!mounted) return;
                ref.invalidate(companySettingsProvider);
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                if (!mounted) return;
                _showModuleNotification(
                  context,
                  title: 'PIN administrativo guardado',
                  body:
                      'El código de autorización quedó actualizado y se usará para confirmar acciones sensibles del módulo.',
                );
              } catch (error) {
                if (!dialogContext.mounted) return;
                setDialogState(() => saving = false);
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(
                      userSafeErrorMessage(
                        error,
                        fallback:
                            'No se pudo guardar el PIN. Inténtalo nuevamente.',
                      ),
                    ),
                  ),
                );
              }
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 24,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.shadow,
                      blurRadius: 26,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 448),
                  child: Material(
                    color: Colors.white,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: AppColors.border),
                    ),
                    child: SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Encabezado compacto
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 14, 8, 12),
                            child: Row(
                              children: [
                                Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: AppColors.secondarySoft,
                                    borderRadius: BorderRadius.circular(7),
                                    border: Border.all(
                                      color: const Color(0xFFDDEAFF),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.lock_outline_rounded,
                                    size: 16,
                                    color: AppColors.secondary,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'PIN administrativo',
                                        style: TextStyle(
                                          color: AppColors.textPrimary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0,
                                        ),
                                      ),
                                      SizedBox(height: 2),
                                      Text(
                                        'Protege las acciones sensibles del sistema',
                                        style: TextStyle(
                                          color: AppColors.textMuted,
                                          fontSize: 11.5,
                                          height: 1.2,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Cerrar',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: saving
                                      ? null
                                      : () => Navigator.pop(dialogContext),
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 20,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: AppColors.border,
                          ),
                          // Campos
                          Flexible(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                14,
                                20,
                                14,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _AdminPinField(
                                    label: 'Nuevo PIN',
                                    controller: pinCtrl,
                                    obscure: obscurePin,
                                    onToggleObscure: () => setDialogState(
                                      () => obscurePin = !obscurePin,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  _AdminPinField(
                                    label: 'Confirmar PIN',
                                    controller: confirmCtrl,
                                    obscure: obscurePin,
                                    onToggleObscure: () => setDialogState(
                                      () => obscurePin = !obscurePin,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Este PIN se utilizará para autorizar operaciones administrativas protegidas',
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 11.5,
                                      height: 1.3,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Divider(
                            height: 1,
                            thickness: 1,
                            color: AppColors.border,
                          ),
                          // Footer compacto
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton(
                                  onPressed: saving
                                      ? null
                                      : () => Navigator.pop(dialogContext),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.secondary,
                                    side: const BorderSide(
                                      color: Color(0xFF9DB9F8),
                                    ),
                                    minimumSize: const Size(0, 36),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                  child: const Text('Cancelar'),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.icon(
                                  onPressed: saving ? null : save,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.secondary,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(0, 36),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    textStyle: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                  icon: saving
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.save_outlined,
                                          size: 16,
                                        ),
                                  label: Text(
                                    saving ? 'Guardando' : 'Guardar PIN',
                                  ),
                                ),
                              ],
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
      },
    );

    pinCtrl.dispose();
    confirmCtrl.dispose();
  }

  Future<void> _toggleBlock(
    BuildContext context,
    WidgetRef ref,
    UserModel user,
    List<UserModel> users,
    UserModel? currentUser,
  ) async {
    final disabledReason = _blockDisabledReason(user, users, currentUser);
    if (disabledReason != null) {
      _showModuleNotification(
        context,
        title: 'Acción no disponible',
        body: disabledReason,
        kind: AppFeedbackKind.warning,
      );
      return;
    }
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
        _showModuleNotification(
          context,
          title: user.blocked ? 'Usuario desbloqueado' : 'Usuario bloqueado',
          body: user.blocked
              ? '${user.nombreCompleto} puede iniciar sesión y trabajar nuevamente según sus permisos.'
              : '${user.nombreCompleto} quedó bloqueado y no podrá acceder hasta que se reactive su cuenta.',
        );
      }
    } catch (e) {
      if (context.mounted) {
        _showModuleNotification(
          context,
          title: 'No se pudo actualizar el usuario',
          body: userSafeErrorMessage(
            e,
            fallback: 'No se pudo actualizar. Inténtalo nuevamente.',
          ),
          kind: AppFeedbackKind.error,
        );
      }
    }
  }

  bool _isOperationalAdmin(UserModel user) {
    return !user.blocked && _managementRole(user) == AppRole.admin;
  }

  String? _blockDisabledReason(
    UserModel user,
    List<UserModel> users,
    UserModel? currentUser,
  ) {
    if (user.blocked) return null;
    if (currentUser != null && user.id == currentUser.id) {
      return 'No puedes bloquear tu propia cuenta.';
    }
    if (_isOperationalAdmin(user)) {
      final remainingAdmins = users
          .where((candidate) => candidate.id != user.id)
          .where(_isOperationalAdmin)
          .length;
      if (remainingAdmins == 0) {
        return 'No puedes dejar la empresa sin un administrador operativo.';
      }
    }
    return null;
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
    DateTime? fechaNacimiento = user?.fechaNacimiento;
    DateTime? workContractStartDate = user?.workContractStartDate;
    final habilidades = [...user?.habilidades ?? const <String>[]];
    String? fotoCedulaUrl = user?.fotoCedulaUrl;
    String? fotoLicenciaUrl = user?.fotoLicenciaUrl;
    String? fotoPersonalUrl = user?.fotoPersonalUrl;
    final formScrollController = ScrollController();

    // ---- Piezas del formulario (identidad visual de «Datos de empresa») ----
    // Rótulo pequeño sobre cada control, campos densos, bordes finos y radios
    // discretos. No se define un sistema de estilos nuevo: se reutilizan los
    // tokens de color del módulo (AppColors).
    const fieldLabelStyle = TextStyle(
      fontSize: 12,
      height: 1.1,
      fontWeight: FontWeight.w600,
      color: Color(0xFF5B6B7C),
    );

    InputDecoration formInputDecoration() {
      final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.border),
      );
      return InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 11,
          vertical: 12,
        ),
        border: border,
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
        ),
        disabledBorder: border,
      );
    }

    Widget sectionLabel(String text, {bool first = false}) {
      return Padding(
        padding: EdgeInsets.only(top: first ? 0 : 16, bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      );
    }

    Widget formField({
      required String label,
      required TextEditingController controller,
      String? hint,
      bool obscure = false,
      TextInputType? keyboardType,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: fieldLabelStyle),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            autocorrect: keyboardType == TextInputType.emailAddress
                ? false
                : true,
            style: const TextStyle(fontSize: 14, height: 1.15),
            decoration: formInputDecoration().copyWith(hintText: hint),
          ),
        ],
      );
    }

    Future<void> submitUser(BuildContext modalContext) async {
      // El formulario administrativo solicita únicamente los datos del acceso:
      // nombre, correo, rol y contraseña. Cédula, teléfono, número de flota y
      // fecha de ingreso ya no se piden aquí. Como el payload NO incluye esas
      // claves, el backend hace actualización parcial y conserva intactos los
      // valores históricos de los usuarios existentes.
      final edad = int.tryParse(edadCtrl.text.trim()) ?? user?.edad ?? 0;
      final email = emailCtrl.text.trim();
      final name = nameCtrl.text.trim();
      final password = passwordCtrl.text.trim();

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
        'telefonoFamiliar': familiarPhoneCtrl.text.trim(),
        'fotoCedulaUrl': fotoCedulaUrl,
        'fotoLicenciaUrl': fotoLicenciaUrl,
        'fotoPersonalUrl': fotoPersonalUrl,
        'edad': edad,
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
        late final String successTitle;
        late final String successBody;
        if (user == null) {
          await ref.read(usersControllerProvider.notifier).create(payload);
          if (!modalContext.mounted) return;
          successTitle = 'Usuario creado';
          successBody =
              '$name fue agregado correctamente. Ya aparece en la lista de usuarios y permisos de la empresa.';
        } else {
          await ref
              .read(usersControllerProvider.notifier)
              .update(user.id, payload);
          if (!modalContext.mounted) return;
          successTitle = 'Usuario editado correctamente';
          successBody =
              'Los cambios de $name fueron guardados y ya están disponibles en el módulo de usuarios y permisos.';
        }
        if (!modalContext.mounted) return;
        Navigator.of(modalContext).pop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!scaffoldContext.mounted) return;
          _showModuleNotification(
            scaffoldContext,
            title: successTitle,
            body: successBody,
          );
        });
      } catch (e) {
        if (!modalContext.mounted) return;
        final message = e is ApiException ? e.message : e.toString();
        _showModuleNotification(
          scaffoldContext,
          title: 'No se pudo guardar el usuario',
          body: message,
          kind: AppFeedbackKind.error,
        );
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
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
          children: [
            sectionLabel('Datos de acceso', first: true),
            formField(
              label: 'Nombre completo',
              controller: nameCtrl,
              hint: 'Ej. Ana Pérez',
            ),
            const SizedBox(height: 10),
            formField(
              label: 'Correo electrónico',
              controller: emailCtrl,
              hint: 'usuario@empresa.com',
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rol', style: fieldLabelStyle),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  isDense: true,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.15,
                    color: AppColors.textPrimary,
                  ),
                  decoration: formInputDecoration(),
                  items: const [
                    DropdownMenuItem(
                      value: 'ADMIN',
                      child: Text('Administrador'),
                    ),
                    DropdownMenuItem(value: 'CAJERO', child: Text('Cajero')),
                  ],
                  onChanged: (val) =>
                      setModalState(() => selectedRole = val ?? 'CAJERO'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            formField(
              label: user == null ? 'Contraseña' : 'Contraseña (opcional)',
              controller: passwordCtrl,
              hint: user == null
                  ? 'Mínimo 8 caracteres'
                  : 'Dejar vacío para conservarla',
              obscure: true,
            ),
            if (user != null) ...[
              sectionLabel('Estado de acceso'),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSubtle,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text(
                    'Bloqueado',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    blocked
                        ? 'No puede iniciar sesión'
                        : 'Puede iniciar sesión',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                  value: blocked,
                  onChanged: (v) => setModalState(() => blocked = v),
                ),
              ),
            ],
          ],
        ),
      );
    }

    Widget buildActionBar(BuildContext modalContext) {
      return SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(modalContext).pop(),
                style: _usersOutlinedButtonStyle(),
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 10),
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
      final title = user == null ? 'Nuevo usuario' : 'Editar usuario';
      final subtitle = user == null
          ? 'Datos mínimos para crear el acceso.'
          : 'Actualiza los datos principales del usuario.';

      final content = Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 6, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: _usersTitleStyle),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF52667C),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.of(modalContext).pop(),
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.border),
          Expanded(child: buildFormBody(modalContext, setModalState)),
          DecoratedBox(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: buildActionBar(modalContext),
          ),
        ],
      );

      if (!desktop) {
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: SafeArea(child: content),
        );
      }

      return Material(
        color: Colors.white,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AppColors.border)),
            boxShadow: [
              BoxShadow(
                color: AppColors.shadow,
                blurRadius: 28,
                offset: Offset(-8, 0),
              ),
            ],
          ),
          child: SafeArea(left: false, right: false, child: content),
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
              final panelWidth = size.width >= 1200
                  ? 520.0
                  : (size.width * 0.46).clamp(400.0, 520.0);

              // Sin Material a pantalla completa: así el resto de la ventana
              // queda libre y el toque fuera de la columna llega a la barrera
              // y cierra el panel.
              return Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: panelWidth,
                  height: size.height,
                  child: StatefulBuilder(
                    builder: (dialogContext, setModalState) =>
                        buildSheet(dialogContext, setModalState, desktop: true),
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
                    maxWidth: 520,
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
                _showModuleNotification(
                  scaffoldContext,
                  title: 'Usuario eliminado',
                  body:
                      '${user.nombreCompleto} fue retirado de la lista de usuarios activos de la empresa.',
                );
              } catch (e) {
                if (!context.mounted) return;
                _showModuleNotification(
                  scaffoldContext,
                  title: 'No se pudo eliminar el usuario',
                  body: userSafeErrorMessage(
                    e,
                    fallback: 'No se pudo eliminar. Inténtalo nuevamente.',
                  ),
                  kind: AppFeedbackKind.error,
                );
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }
}

/// Modal de detalle y permisos de un usuario.
///
/// Sustituye al panel permanente de la derecha: misma información, mismas
/// acciones y mismos permisos, mostrados solo cuando se solicitan. No consulta
/// endpoints nuevos ni altera las reglas de permisos existentes.
/// Ancho del panel lateral: 38% de la ventana, con mínimo y máximo legibles.
///
/// Por debajo de 700 px el porcentaje dejaría una columna inutilizable, así que
/// ahí el panel ocupa todo el ancho (comportamiento de móvil).
double _userDetailPanelWidth(double screenWidth) {
  if (screenWidth < 700) return screenWidth;
  final target = screenWidth * 0.38;
  if (target < 440) return 440;
  if (target > 760) return 760;
  return target;
}

const TextStyle _panelLabelStyle = TextStyle(
  color: AppColors.textMuted,
  fontSize: 11.5,
  fontWeight: FontWeight.w800,
  letterSpacing: 0.2,
);

const TextStyle _panelValueStyle = TextStyle(
  color: AppColors.textPrimary,
  fontSize: 12.5,
  height: 1.3,
  fontWeight: FontWeight.w600,
  letterSpacing: 0,
);

Widget _panelRow(String label, Widget value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      children: [
        SizedBox(width: 88, child: Text(label, style: _panelLabelStyle)),
        Expanded(child: value),
      ],
    ),
  );
}

class _PanelSectionLabel extends StatelessWidget {
  const _PanelSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: _panelLabelStyle);
}

/// Panel lateral de detalle y permisos.
///
/// Se desliza desde el borde derecho, ocupa el 38% del ancho (con mínimo y
/// máximo legibles), cubre toda la altura de la ventana —incluido el AppBar— y
/// se dibuja POR ENCIMA del contenido sin desplazarlo. Se cierra tocando fuera.
class _UserDetailPanel extends StatelessWidget {
  const _UserDetailPanel({
    required this.user,
    required this.blockDisabledReason,
    required this.onEdit,
    required this.onToggleBlock,
    required this.onEditPermissions,
  });

  final UserModel user;
  final String? blockDisabledReason;
  final VoidCallback onEdit;
  final VoidCallback? onToggleBlock;
  final VoidCallback? onEditPermissions;

  @override
  Widget build(BuildContext context) {
    final width = _userDetailPanelWidth(MediaQuery.sizeOf(context).width);
    final allowed = _allowedPermissionCount(user);

    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: width,
        height: double.infinity,
        child: Material(
          color: Colors.white,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: AppColors.border)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 28,
                  offset: Offset(-8, 0),
                ),
              ],
            ),
            child: SafeArea(
              left: false,
              right: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.border,
                  ),
                  Expanded(
                    child: Scrollbar(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _PanelSectionLabel('Información'),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceSubtle,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                children: [
                                  _panelRow(
                                    'Rol',
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: _UserRoleBadge(
                                        role: _managementRole(user),
                                        dense: true,
                                      ),
                                    ),
                                  ),
                                  _panelRow(
                                    'Estado',
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: _UserStatusBadge(
                                        blocked: user.blocked,
                                        dense: true,
                                      ),
                                    ),
                                  ),
                                  if (user.telefono.trim().isNotEmpty)
                                    _panelRow(
                                      'Teléfono',
                                      Text(
                                        user.telefono.trim(),
                                        style: _panelValueStyle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  if ((user.cedula ?? '').trim().isNotEmpty)
                                    _panelRow(
                                      'Cédula',
                                      Text(
                                        user.cedula!.trim(),
                                        style: _panelValueStyle,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  if (user.fechaIngreso != null)
                                    _panelRow(
                                      'Ingreso',
                                      Text(
                                        DateFormat(
                                          'dd/MM/yyyy',
                                        ).format(user.fechaIngreso!),
                                        style: _panelValueStyle,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            const _PanelSectionLabel('Acciones'),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: onEdit,
                                    style: _usersOutlinedButtonStyle(),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                    ),
                                    label: const Text('Editar'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  tooltip:
                                      blockDisabledReason ??
                                      (user.blocked
                                          ? 'Desbloquear'
                                          : 'Bloquear'),
                                  onPressed: onToggleBlock,
                                  icon: Icon(
                                    user.blocked
                                        ? Icons.lock_open_outlined
                                        : Icons.lock_outline,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                const Expanded(
                                  child: _PanelSectionLabel(
                                    'Permisos por pantalla',
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.secondarySoft,
                                    borderRadius: BorderRadius.circular(7),
                                    border: Border.all(
                                      color: const Color(0xFFDDEAFF),
                                    ),
                                  ),
                                  child: Text(
                                    '$allowed/${_userScreenPermissions.length}',
                                    style: const TextStyle(
                                      color: AppColors.secondary,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (final item in _userScreenPermissions)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: _PermissionScreenTile(
                                  icon: item.icon,
                                  title: item.title,
                                  allowed: hasUserPermission(
                                    user,
                                    item.permission,
                                  ),
                                  dense: true,
                                ),
                              ),
                            const SizedBox(height: 8),
                            if (onEditPermissions == null)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.successSoft,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: AppColors.successBorder,
                                  ),
                                ),
                                child: const Text(
                                  'El administrador tiene todos los permisos.',
                                  style: TextStyle(
                                    color: AppColors.success,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      child: Row(
        children: [
          _UserAvatar(user: user, radius: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  user.nombreCompleto,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user.email.trim().isEmpty ? '—' : user.email.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          if (onEditPermissions != null) ...[
            OutlinedButton.icon(
              onPressed: onEditPermissions,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.secondary,
                backgroundColor: AppColors.secondarySoft,
                side: const BorderSide(color: Color(0xFFDDEAFF)),
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                textStyle: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              icon: const _PermissionsKeyIcon(size: 19),
              label: const Text('Permisos'),
            ),
            const SizedBox(width: 4),
          ],
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded, size: 20),
            color: AppColors.textMuted,
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

/// Icono del botón «Permisos» del panel de detalle.
///
/// Usa el recurso gráfico aportado por el responsable del proyecto
/// (`assets/image/cerrar-con-llave.png`) y lo tiñe al color de marca para que
/// mantenga contraste sobre el fondo tonal del botón.
class _PermissionsKeyIcon extends StatelessWidget {
  const _PermissionsKeyIcon({this.size = 19});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/image/cerrar-con-llave.png',
      width: size,
      height: size,
      color: AppColors.secondary,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Permisos',
      errorBuilder: (context, error, stackTrace) =>
          Icon(Icons.key_outlined, size: size, color: AppColors.secondary),
    );
  }
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
  const UserPermissionsScreen({
    super.key,
    required this.userId,
    this.embedded = false,
  });

  final String userId;

  /// Cuando es `true` el editor se presenta como panel lateral: sin AppBar ni
  /// drawer, con encabezado propio y cierre por botón. La lógica no cambia.
  final bool embedded;

  @override
  ConsumerState<UserPermissionsScreen> createState() =>
      _UserPermissionsScreenState();
}

class _UserPermissionsScreenState extends ConsumerState<UserPermissionsScreen> {
  Map<String, bool>? _draft;
  bool _saving = false;

  void _showPermissionNotification({
    required String title,
    required String body,
    AppFeedbackKind kind = AppFeedbackKind.success,
  }) {
    AppFeedback.showPersistentNotification(
      context,
      AppFeedbackNotification(title: title, body: body, kind: kind),
      scope: 'user_permissions',
    );
  }

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
      _showPermissionNotification(
        title: 'Permisos actualizados',
        body:
            'Los accesos de ${user.nombreCompleto} se guardaron correctamente y estarán disponibles en su próxima navegación.',
      );
      if (widget.embedded) {
        Navigator.of(context).maybePop();
      } else {
        AppNavigator.go(context, Routes.users);
      }
    } catch (e) {
      if (!mounted) return;
      _showPermissionNotification(
        title: 'No se pudieron guardar los permisos',
        body: userSafeErrorMessage(
          e,
          fallback: 'No se pudo guardar. Inténtalo nuevamente.',
        ),
        kind: AppFeedbackKind.error,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _closeEditor() {
    if (widget.embedded) {
      Navigator.of(context).maybePop();
    } else {
      AppNavigator.goBack(context, fallbackRoute: Routes.users);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final usersState = ref.watch(usersControllerProvider);
    final currentUser = ref.watch(authStateProvider).user;

    return Scaffold(
      appBar: widget.embedded
          ? null
          : CustomAppBar(
              title: 'Editar permisos',
              showLogo: false,
              leading: IconButton(
                tooltip: 'Volver',
                onPressed: () =>
                    AppNavigator.goBack(context, fallbackRoute: Routes.users),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
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
      drawer: widget.embedded
          ? null
          : buildAdaptiveDrawer(context, currentUser: currentUser),
      body: usersState.when(
        loading: () => const Center(child: Text('Sincronizando permisos...')),
        error: (e, _) => Center(
          child: Text(
            userSafeErrorMessage(
              e,
              fallback: 'No se pudieron cargar los usuarios.',
            ),
          ),
        ),
        data: (users) {
          final user = _findUser(users);
          if (user == null) {
            return const Center(child: Text('Usuario no encontrado'));
          }
          final compact = MediaQuery.sizeOf(context).width < 640;
          if (_managementRole(user) == AppRole.admin) {
            return Container(
              color: theme.colorScheme.surfaceContainerLowest,
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  compact ? 14 : 28,
                  compact ? 14 : 22,
                  compact ? 14 : 28,
                  24,
                ),
                children: [
                  _UserPermissionsHeader(
                    user: user,
                    compact: compact,
                    saving: true,
                    showBulkActions: false,
                    onAllowAll: () {},
                    onDenyAll: () {},
                    onClose: _closeEditor,
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.successBorder),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.verified_user_outlined,
                          color: AppColors.success,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'El administrador siempre tiene todos los permisos. Puedes ver sus detalles, pero sus permisos no se editan desde aquí.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          final draft = _draft ??= _buildInitialDraft(user);
          return Container(
            color: theme.colorScheme.surfaceContainerLowest,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 14 : 28,
                      compact ? 14 : 22,
                      compact ? 14 : 28,
                      24,
                    ),
                    children: [
                      _UserPermissionsHeader(
                        user: user,
                        compact: compact,
                        saving: _saving,
                        onAllowAll: () => _setAllPermissions(user, true),
                        onDenyAll: () => _setAllPermissions(user, false),
                        onClose: _closeEditor,
                      ),
                      const SizedBox(height: 12),
                      _PermissionModulesGrid(
                        draft: draft,
                        onChanged: _setPermission,
                      ),
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
                    minimum: EdgeInsets.fromLTRB(
                      compact ? 14 : 28,
                      12,
                      compact ? 14 : 28,
                      16,
                    ),
                    child: Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _saving ? null : _closeEditor,
                          icon: Icon(
                            widget.embedded
                                ? Icons.close_rounded
                                : Icons.arrow_back_outlined,
                          ),
                          label: Text(widget.embedded ? 'Cancelar' : 'Volver'),
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

class _PermissionModuleEditor extends StatefulWidget {
  const _PermissionModuleEditor({
    required this.module,
    required this.draft,
    required this.onChanged,
  });

  final _PermissionModuleItem module;
  final Map<String, bool> draft;
  final void Function(AppPermission permission, bool value) onChanged;

  @override
  State<_PermissionModuleEditor> createState() =>
      _PermissionModuleEditorState();
}

class _PermissionModuleEditorState extends State<_PermissionModuleEditor> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final module = widget.module;
    final draft = widget.draft;
    final moduleEnabled = draft[module.viewPermission.name] ?? false;
    final total = module.actions.length;
    var allowed = moduleEnabled ? 1 : 0;
    for (final action in module.actions) {
      if (draft[action.permission.name] ?? false) allowed++;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            mouseCursor: SystemMouseCursors.click,
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
              child: Row(
                children: [
                  Icon(module.icon, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          module.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0,
                          ),
                        ),
                        Text(
                          '$allowed de ${total + 1} permisos',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Checkbox(
                    value: moduleEnabled,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (value) =>
                        widget.onChanged(module.viewPermission, value ?? false),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 8, 8),
              child: Column(
                children: [
                  for (final action in module.actions)
                    _PermissionRow(
                      title: action.title,
                      description: action.description,
                      value: draft[action.permission.name] ?? false,
                      onChanged: moduleEnabled
                          ? (value) =>
                                widget.onChanged(action.permission, value)
                          : null,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PermissionModulesGrid extends StatelessWidget {
  const _PermissionModulesGrid({required this.draft, required this.onChanged});

  final Map<String, bool> draft;
  final void Function(AppPermission permission, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 900;
        if (!twoColumns) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final module in _permissionModules)
                _PermissionModuleEditor(
                  module: module,
                  draft: draft,
                  onChanged: onChanged,
                ),
            ],
          );
        }

        final half = (_permissionModules.length + 1) ~/ 2;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final module in _permissionModules.take(half))
                    _PermissionModuleEditor(
                      module: module,
                      draft: draft,
                      onChanged: onChanged,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final module in _permissionModules.skip(half))
                    _PermissionModuleEditor(
                      module: module,
                      draft: draft,
                      onChanged: onChanged,
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

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;

  /// `null` desactiva la fila (módulo desactivado); no altera el valor guardado.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      mouseCursor: SystemMouseCursors.click,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onChanged == null
                          ? AppColors.textMuted
                          : AppColors.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0,
                    ),
                  ),
                  if (description.trim().isNotEmpty)
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                        letterSpacing: 0,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Checkbox(
            value: value,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: onChanged == null
                ? null
                : (next) => onChanged!(next ?? false),
          ),
        ],
      ),
    );
  }
}

class _UserPermissionsHeader extends StatelessWidget {
  const _UserPermissionsHeader({
    required this.user,
    required this.compact,
    required this.saving,
    required this.onAllowAll,
    required this.onDenyAll,
    required this.onClose,
    this.showBulkActions = true,
  });

  final UserModel user;
  final bool compact;
  final bool saving;
  final VoidCallback onAllowAll;
  final VoidCallback onDenyAll;
  final VoidCallback onClose;
  final bool showBulkActions;

  @override
  Widget build(BuildContext context) {
    final role = _managementRole(user);
    final identity = Row(
      children: [
        _UserAvatar(user: user, radius: compact ? 18 : 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Editar permisos',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${user.nombreCompleto} · ${role.label} · '
                '${user.blocked ? 'Bloqueado' : 'Activo'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final actions = <Widget>[
      if (showBulkActions) ...[
        _MiniButton(
          icon: Icons.done_all_rounded,
          label: 'Dar todos',
          tonal: true,
          onPressed: saving ? null : onAllowAll,
        ),
        _MiniButton(
          icon: Icons.remove_done_outlined,
          label: 'Quitar todos',
          onPressed: saving ? null : onDenyAll,
        ),
      ],
      IconButton(
        tooltip: 'Cerrar',
        onPressed: onClose,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        icon: const Icon(
          Icons.close_rounded,
          size: 20,
          color: AppColors.textMuted,
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: identity),
                const SizedBox(width: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: actions,
                ),
              ],
            ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tonal = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    const textStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
    );
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 15), const SizedBox(width: 6), Text(label)],
    );

    if (tonal) {
      return FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: textStyle,
        ),
        child: child,
      );
    }

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        side: const BorderSide(color: AppColors.border),
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: textStyle,
      ),
      child: child,
    );
  }
}

ButtonStyle _pinButtonStyle() => OutlinedButton.styleFrom(
  foregroundColor: AppColors.secondary,
  side: const BorderSide(color: Color(0xFF9DB9F8)),
  minimumSize: const Size(0, 34),
  padding: const EdgeInsets.symmetric(horizontal: 12),
  visualDensity: VisualDensity.compact,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  textStyle: const TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w900,
    letterSpacing: 0,
  ),
);

/// Icono del botón «PIN» de la barra superior.
///
/// PENDIENTE: sustituir por el archivo gráfico definitivo cuando se añada a
/// `assets/image/` (ya declarado en `pubspec.yaml`). Hasta entonces se usa el
/// icono del sistema con el mismo significado, para no inventar una ruta.
class _AdminPinIcon extends StatelessWidget {
  const _AdminPinIcon();

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.verified_user_outlined,
      size: 16,
      color: AppColors.secondary,
    );
  }
}

class _PermissionScreenTile extends StatelessWidget {
  const _PermissionScreenTile({
    required this.icon,
    required this.title,
    required this.allowed,
    this.dense = false,
  });

  final IconData icon;
  final String title;
  final bool allowed;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = allowed ? AppColors.success : AppColors.textMuted;
    final background = allowed
        ? AppColors.successSoft
        : const Color(0xFFF1F5F9);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 10 : 12,
        vertical: dense ? 7 : 10,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(dense ? 8 : 12),
        border: Border.all(
          color: allowed ? AppColors.successBorder : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground, size: dense ? 16 : 19),
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

class _UsersPanelCard extends StatelessWidget {
  const _UsersPanelCard({
    required this.users,
    required this.hasMore,
    required this.loadingMore,
    required this.onLoadMore,
    required this.onOpenUser,
    required this.onEditUser,
    required this.onDeleteUser,
    required this.onToggleBlock,
    required this.blockDisabledReason,
  });

  final List<UserModel> users;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback onLoadMore;
  final ValueChanged<UserModel> onOpenUser;
  final ValueChanged<UserModel> onEditUser;
  final ValueChanged<UserModel> onDeleteUser;
  final ValueChanged<UserModel> onToggleBlock;
  final String? Function(UserModel user) blockDisabledReason;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Usuarios', style: _usersTitleStyle),
                      const SizedBox(height: 4),
                      Text(
                        'Administra los usuarios y sus permisos de acceso.',
                        style: _usersBodyStyle,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _UsersCountPill(count: users.length),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.border),
          Expanded(
            child: users.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.group_off_outlined,
                          size: 26,
                          color: AppColors.textMuted,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'No hay usuarios para mostrar.',
                          textAlign: TextAlign.center,
                          style: _usersBodyStyle,
                        ),
                        if (hasMore || loadingMore) ...[
                          const SizedBox(height: 14),
                          LoadMoreFooter(
                            loading: loadingMore,
                            hasMore: true,
                            label: 'Ver más',
                            onLoadMore: onLoadMore,
                          ),
                        ],
                      ],
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final showBadges = constraints.maxWidth >= 620;
                      return Column(
                        children: [
                          if (showBadges) const _UsersListHeaderRow(),
                          Expanded(
                            child: Scrollbar(
                              child: ListView.separated(
                                padding: const EdgeInsets.only(bottom: 8),
                                itemCount:
                                    users.length +
                                    (hasMore || loadingMore ? 1 : 0),
                                separatorBuilder: (_, __) => const Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: AppColors.border,
                                ),
                                itemBuilder: (context, index) {
                                  if (index >= users.length) {
                                    return LoadMoreFooter(
                                      loading: loadingMore,
                                      hasMore: true,
                                      label: 'Ver más',
                                      onLoadMore: onLoadMore,
                                    );
                                  }
                                  final user = users[index];
                                  return _UserRowCard(
                                    user: user,
                                    showBadges: showBadges,
                                    onOpen: () => onOpenUser(user),
                                    onEdit: () => onEditUser(user),
                                    onDelete: () => onDeleteUser(user),
                                    onToggleBlock:
                                        blockDisabledReason(user) == null
                                        ? () => onToggleBlock(user)
                                        : null,
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Estilos compartidos del módulo, alineados con «Datos de empresa».
const TextStyle _usersTitleStyle = TextStyle(
  color: AppColors.textPrimary,
  fontSize: 16,
  fontWeight: FontWeight.w900,
  letterSpacing: 0,
);

const TextStyle _usersBodyStyle = TextStyle(
  color: Color(0xFF52667C),
  fontSize: 13,
  height: 1.3,
  fontWeight: FontWeight.w600,
  letterSpacing: 0,
);

const TextStyle _usersCaptionStyle = TextStyle(
  color: AppColors.textMuted,
  fontSize: 11.5,
  fontWeight: FontWeight.w800,
  letterSpacing: 0,
);

ButtonStyle _usersOutlinedButtonStyle() {
  return OutlinedButton.styleFrom(
    foregroundColor: AppColors.secondary,
    side: const BorderSide(color: Color(0xFF9DB9F8)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    textStyle: const TextStyle(
      fontWeight: FontWeight.w900,
      fontSize: 13,
      letterSpacing: 0,
    ),
  );
}

/// Anchos fijos de las columnas de rol, estado y acciones. Se comparten entre
/// la cabecera y las filas para que las columnas queden alineadas sin tabla.
const double _usersRoleColumnWidth = 112;
const double _usersStatusColumnWidth = 96;
const double _usersActionsColumnWidth = 48;

class _UsersCountPill extends StatelessWidget {
  const _UsersCountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.secondarySoft,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFDDEAFF)),
      ),
      child: Text(
        count == 1 ? '1 usuario' : '$count usuarios',
        style: const TextStyle(
          color: AppColors.secondary,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _UsersListHeaderRow extends StatelessWidget {
  const _UsersListHeaderRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.surfaceSubtle,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: const [
          Expanded(child: Text('Usuario', style: _usersCaptionStyle)),
          SizedBox(
            width: _usersRoleColumnWidth,
            child: Text('Rol', style: _usersCaptionStyle),
          ),
          SizedBox(
            width: _usersStatusColumnWidth,
            child: Text('Estado', style: _usersCaptionStyle),
          ),
          SizedBox(width: _usersActionsColumnWidth),
        ],
      ),
    );
  }
}

class _UserRowCard extends StatefulWidget {
  const _UserRowCard({
    required this.user,
    required this.showBadges,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleBlock,
  });

  final UserModel user;
  final bool showBadges;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onToggleBlock;

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
    final surfaceColor = _hovered ? AppColors.surfaceSubtle : Colors.white;

    return MouseRegion(
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: Material(
        color: surfaceColor,
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          onTap: widget.onOpen,
          hoverColor: AppColors.surfaceSubtle,
          focusColor: AppColors.secondarySoft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: surfaceColor,
            child: Row(
              children: [
                _UserAvatar(user: widget.user, radius: 17),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.user.nombreCompleto,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.user.email.trim().isEmpty
                            ? '—'
                            : widget.user.email.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.showBadges) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: _usersRoleColumnWidth,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _UserRoleBadge(
                        role: _managementRole(widget.user),
                        dense: true,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: _usersStatusColumnWidth,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _UserStatusBadge(
                        blocked: widget.user.blocked,
                        dense: true,
                      ),
                    ),
                  ),
                ] else
                  const SizedBox(width: 8),
                SizedBox(
                  width: _usersActionsColumnWidth,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: PopupMenuButton<_UserMenuAction>(
                      tooltip: 'Acciones',
                      padding: EdgeInsets.zero,
                      color: Colors.white,
                      elevation: 8,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      icon: const Icon(
                        Icons.more_vert,
                        size: 18,
                        color: AppColors.textMuted,
                      ),
                      onSelected: (action) {
                        switch (action) {
                          case _UserMenuAction.permisos:
                          case _UserMenuAction.ver:
                            widget.onOpen();
                            break;
                          case _UserMenuAction.editar:
                            widget.onEdit();
                            break;
                          case _UserMenuAction.bloquear:
                            widget.onToggleBlock?.call();
                            break;
                          case _UserMenuAction.eliminar:
                            widget.onDelete();
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        _userMenuItem(
                          value: _UserMenuAction.ver,
                          icon: Icons.visibility_outlined,
                          label: 'Ver detalle',
                        ),
                        _userMenuItem(
                          value: _UserMenuAction.editar,
                          icon: Icons.edit_outlined,
                          label: 'Editar',
                        ),
                        if (widget.onToggleBlock != null)
                          _userMenuItem(
                            value: _UserMenuAction.bloquear,
                            icon: widget.user.blocked
                                ? Icons.lock_open_outlined
                                : Icons.lock_outline,
                            label: widget.user.blocked
                                ? 'Desbloquear'
                                : 'Bloquear',
                          ),
                        _userMenuItem(
                          value: _UserMenuAction.eliminar,
                          icon: Icons.delete_outline,
                          label: 'Eliminar',
                          danger: true,
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

class _UserStatusBadge extends StatelessWidget {
  const _UserStatusBadge({required this.blocked, this.dense = false});

  final bool blocked;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final background = blocked ? AppColors.warningSoft : AppColors.successSoft;
    final foreground = blocked ? AppColors.warning : AppColors.success;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 6,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        blocked ? 'Bloqueado' : 'Activo',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
          fontSize: dense ? 11 : null,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _UserRoleBadge extends StatelessWidget {
  const _UserRoleBadge({required this.role, this.dense = false});

  final AppRole role;
  final bool dense;

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
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 6,
      ),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        role.label.isEmpty ? 'Sin rol' : role.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: colors.$2,
          fontWeight: FontWeight.w700,
          fontSize: dense ? 11 : null,
          letterSpacing: 0,
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

enum _UserMenuAction { permisos, ver, editar, bloquear, eliminar }

/// Ítem de menú compacto, con tipografía algo mayor y icono pequeno.
///
/// Solo presentación: el valor y la acción asociada no cambian.
PopupMenuItem<_UserMenuAction> _userMenuItem({
  required _UserMenuAction value,
  required IconData icon,
  required String label,
  bool danger = false,
}) {
  final color = danger ? AppColors.error : AppColors.textPrimary;
  return PopupMenuItem<_UserMenuAction>(
    value: value,
    height: 38,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 17,
          color: danger ? AppColors.error : AppColors.textMuted,
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 14,
            height: 1.1,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ],
    ),
  );
}

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
  final VoidCallback? onToggleBlock;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.white,
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          onTap: onView,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _UserAvatar(user: user, radius: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        user.nombreCompleto,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        user.email.trim().isEmpty ? '—' : user.email.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _UserRoleBadge(
                            role: _managementRole(user),
                            dense: true,
                          ),
                          _UserStatusBadge(blocked: user.blocked, dense: true),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<_UserMenuAction>(
                  tooltip: 'Acciones',
                  padding: EdgeInsets.zero,
                  color: Colors.white,
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: AppColors.border),
                  ),
                  icon: const Icon(
                    Icons.more_vert,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                  onSelected: (action) {
                    switch (action) {
                      case _UserMenuAction.permisos:
                      case _UserMenuAction.ver:
                        onView();
                        break;
                      case _UserMenuAction.editar:
                        onEdit();
                        break;
                      case _UserMenuAction.bloquear:
                        onToggleBlock?.call();
                        break;
                      case _UserMenuAction.eliminar:
                        onDelete();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    _userMenuItem(
                      value: _UserMenuAction.permisos,
                      icon: Icons.fact_check_outlined,
                      label: 'Permisos',
                    ),
                    _userMenuItem(
                      value: _UserMenuAction.editar,
                      icon: Icons.edit_outlined,
                      label: 'Editar',
                    ),
                    if (onToggleBlock != null)
                      _userMenuItem(
                        value: _UserMenuAction.bloquear,
                        icon: user.blocked
                            ? Icons.lock_open_outlined
                            : Icons.lock_outline,
                        label: user.blocked ? 'Desbloquear' : 'Bloquear',
                      ),
                    _userMenuItem(
                      value: _UserMenuAction.eliminar,
                      icon: Icons.delete_outline,
                      label: 'Eliminar',
                      danger: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Campo compacto del modal «PIN administrativo».
///
/// Solo presentación: conserva longitud máxima, teclado numérico, caracteres
/// ocultos y el controller que usa la lógica existente del PIN.
class _AdminPinField extends StatelessWidget {
  const _AdminPinField({
    required this.label,
    required this.controller,
    required this.obscure,
    required this.onToggleObscure,
  });

  final String label;
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggleObscure;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.border),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            height: 1.1,
            fontWeight: FontWeight.w600,
            color: Color(0xFF5B6B7C),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          obscureText: obscure,
          obscuringCharacter: '•',
          maxLength: 4,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(4),
          ],
          style: const TextStyle(fontSize: 14, height: 1.15),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 12,
            ),
            border: border,
            enabledBorder: border,
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.4,
              ),
            ),
            suffixIcon: IconButton(
              tooltip: obscure ? 'Mostrar PIN' : 'Ocultar PIN',
              onPressed: onToggleObscure,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
