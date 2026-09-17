import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:validators/validators.dart' as validators;

import '../../../core/auth/app_role.dart';
import '../../../core/auth/business_registration_policy.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/routing/route_access.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_feedback.dart';
import '../../../core/utils/safe_url_launcher.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/windows_login_users_storage.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _passwordFocusNode = FocusNode();
  _LoginNoticeData? _notice;
  bool _obscurePassword = true;

  final _windowsUsersStorage = const WindowsLoginUsersStorage();
  final MenuController _savedUsersMenuController = MenuController();
  List<String> _savedUsers = const <String>[];

  /// The list of usernames used on this PC is a Windows-only convenience.
  bool get _showsSavedUsers =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    _emailCtrl.addListener(_clearNoticeOnInput);
    _passwordCtrl.addListener(_clearNoticeOnInput);
    _loadSavedUsers();
  }

  @override
  void dispose() {
    _emailCtrl.removeListener(_clearNoticeOnInput);
    _passwordCtrl.removeListener(_clearNoticeOnInput);
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _clearNoticeOnInput() {
    if (_notice == null || !_notice!.isError || !mounted) {
      return;
    }
    setState(() => _notice = null);
  }

  Future<void> _loadSavedUsers() async {
    if (!_showsSavedUsers) return;
    final users = await _windowsUsersStorage.loadUsers();
    if (!mounted) return;
    setState(() => _savedUsers = users);
  }

  /// Stores the username of a successful login. The password is never stored.
  Future<void> _rememberUserAfterLogin() async {
    if (!_showsSavedUsers) return;
    final users = await _windowsUsersStorage.rememberUser(_emailCtrl.text);
    if (!mounted) return;
    setState(() => _savedUsers = users);
  }

  Future<void> _removeSavedUser(String user) async {
    final users = await _windowsUsersStorage.removeUser(user);
    if (!mounted) return;
    setState(() => _savedUsers = users);
  }

  void _selectSavedUser(String user) {
    _savedUsersMenuController.close();
    _emailCtrl.text = user;
    _passwordCtrl.clear();
    _passwordFocusNode.requestFocus();
  }

  Widget _buildSavedUsersMenu() {
    return MenuAnchor(
      controller: _savedUsersMenuController,
      alignmentOffset: const Offset(-8, 4),
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        maximumSize: const WidgetStatePropertyAll(Size(320, 320)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        side: const WidgetStatePropertyAll(
          BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      menuChildren: _savedUsers.isEmpty
          ? const <Widget>[_SavedUsersEmptyNotice()]
          : <Widget>[
              for (final user in _savedUsers)
                _SavedUserMenuItem(
                  key: ValueKey<String>(user.toLowerCase()),
                  user: user,
                  onSelected: _selectSavedUser,
                  onRemoved: _removeSavedUser,
                ),
            ],
      builder: (context, controller, child) {
        return IconButton(
          tooltip: 'Usuarios de esta PC',
          visualDensity: VisualDensity.compact,
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          icon: const Icon(Icons.arrow_drop_down_rounded),
        );
      },
    );
  }

  _LoginNoticeData _buildErrorNotice(ApiException error) {
    if (error.displayCode == 'LICENSE_INACTIVE' ||
        (error.responseBody ?? '').toLowerCase().contains('license_')) {
      return _LoginNoticeData.error(
        title: 'Licencia no activa',
        message: error.message,
        helpText:
            'La empresa está bloqueada, vencida o sin licencia vigente. Para continuar debes renovar o comprar una licencia.',
        actionLabel: 'Comprar por WhatsApp',
        actionUri: Uri.https('wa.me', '/18295319442', {
          'text':
              'Hola, necesito comprar o renovar mi licencia de FullPOS Cloud.',
        }),
      );
    }

    switch (error.type) {
      case ApiErrorType.unauthorized:
        return _LoginNoticeData.error(
          title: 'Acceso no confirmado',
          message: 'Revisa tu usuario y contrasena.',
          helpText:
              'Intenta nuevamente o solicita ayuda al administrador.',
          feedbackKind: AppFeedbackKind.warning,
          showNotification: false,
        );
      case ApiErrorType.forbidden:
        return _LoginNoticeData.error(
          title: 'Acceso restringido',
          message: error.message,
          helpText:
              'Si tu acceso deberia estar activo, comunicate con administracion.',
        );
      case ApiErrorType.noInternet:
        return _LoginNoticeData.error(
          title: 'Sin conexión',
          message: error.message,
          helpText:
              'Conecta la PC a internet y vuelve a intentar cuando la señal esté estable.',
        );
      case ApiErrorType.dns:
        return _LoginNoticeData.error(
          title: 'Servicio no encontrado',
          message: error.message,
          helpText:
              'Prueba cambiar de red o reiniciar el internet antes de intentar otra vez.',
        );
      case ApiErrorType.tls:
        return _LoginNoticeData.error(
          title: 'Conexión segura rechazada',
          message: error.message,
          helpText:
              'Verifica la fecha y hora de la PC. Si usas antivirus o red empresarial, puede estar bloqueando la conexión.',
        );
      case ApiErrorType.network:
        return _LoginNoticeData.error(
          title: 'Conexión interrumpida',
          message: error.message,
          helpText:
              'Espera unos segundos y vuelve a intentar. Si continúa, prueba otra red.',
        );
      case ApiErrorType.timeout:
        return _LoginNoticeData.error(
          title: 'Tiempo de espera agotado',
          message: error.message,
          helpText:
              'La respuesta tardó demasiado. Revisa tu conexión y vuelve a intentar.',
        );
      case ApiErrorType.config:
        return _LoginNoticeData.error(
          title: 'App no configurada',
          message: error.message,
          helpText:
              'Instala la versión más reciente o contacta a soporte para validar la instalación.',
        );
      case ApiErrorType.server:
        return _LoginNoticeData.error(
          title: 'Servicio no disponible',
          message: error.message,
          helpText:
              'El servicio tuvo un problema temporal. Intenta nuevamente en un momento.',
        );
      case ApiErrorType.badRequest:
      case ApiErrorType.notFound:
      case ApiErrorType.conflict:
      case ApiErrorType.parse:
      case ApiErrorType.cancelled:
      case ApiErrorType.unknown:
        return _LoginNoticeData.error(
          title: 'No se pudo iniciar sesion',
          message: error.message,
          helpText:
              'Corrige los datos ingresados o vuelve a intentarlo en unos segundos.',
        );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() => _notice = null);
    try {
      await ref
          .read(authStateProvider.notifier)
          .login(_emailCtrl.text, _passwordCtrl.text);
      await _rememberUserAfterLogin();
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go(
          RouteAccess.defaultHomeForRole(
            ref.read(authStateProvider).user?.appRole ?? AppRole.unknown,
          ),
        );
      });
      return;
    } on ApiException catch (e) {
      if (mounted) {
        final notice = _buildErrorNotice(e);
        setState(() => _notice = notice);
        if (notice.showNotification) {
          _showLoginFailureNotification(notice);
        }
      }
    } catch (e) {
      if (mounted) {
        const notice = _LoginNoticeData.error(
          title: 'No se pudo iniciar sesion',
          message:
              'Ocurrio un error inesperado al validar tu acceso. Intenta nuevamente.',
          helpText:
              'Si el problema persiste, informa al area tecnica para revisar el sistema.',
        );
        setState(() => _notice = notice);
        _showLoginFailureNotification(notice);
      }
    }
  }

  void _showLoginFailureNotification(_LoginNoticeData notice) {
    if (!mounted) return;
    AppFeedback.showPersistentNotification(
      context,
      AppFeedbackNotification(
        title: notice.title,
        body: '${notice.message} ${notice.helpText}',
        kind: notice.feedbackKind,
      ),
      scope: 'LoginScreen',
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading = ref.watch(authStateProvider).loading;
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final viewInsets = mediaQuery.viewInsets;
    final horizontalPadding = size.width < 420 ? 16.0 : 24.0;
    final availableCardWidth = size.width - (horizontalPadding * 2);
    final maxCompactWidth = kIsWeb && size.width < 700 ? 340.0 : 520.0;
    final cardWidth = size.width >= 900
        ? 392.0
        : availableCardWidth.clamp(0.0, maxCompactWidth);
    final businessRegistrationDisabled = ref.watch(
      businessRegistrationDisabledProvider,
    );
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.headlineSmall?.copyWith(
      color: AppColors.textPrimary,
      fontWeight: FontWeight.w900,
      letterSpacing: 0,
      height: 1.05,
    );
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.borderStrong, width: 1),
    );
    final focusedInputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.6),
    );
    final loginTheme = theme.copyWith(
      inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: focusedInputBorder,
        errorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.error, width: 1),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppColors.error, width: 1.6),
        ),
        labelStyle: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        floatingLabelStyle: TextStyle(
          color: theme.colorScheme.primary,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: theme.elevatedButtonTheme.style?.copyWith(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
          shadowColor: WidgetStatePropertyAll(
            AppColors.primary.withValues(alpha: 0.34),
          ),
          elevation: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return 0;
            if (states.contains(WidgetState.pressed)) return 2;
            return states.contains(WidgetState.hovered) ? 8 : 5;
          }),
          backgroundBuilder: (context, states, child) {
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: _loginPrimaryGradient(states),
              ),
              child: child,
            );
          },
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: theme.outlinedButtonTheme.style?.copyWith(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    );

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A3D91), Color(0xFF1273D3)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Align(
            alignment: kIsWeb && size.width < 700
                ? Alignment.centerLeft
                : Alignment.center,
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                24,
                horizontalPadding,
                24 + viewInsets.bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: cardWidth),
                child: Card(
                  color: Colors.white,
                  elevation: 8,
                  shadowColor: Colors.black.withValues(alpha: 0.18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: AppColors.border, width: 1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 26,
                    ),
                    child: CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.enter): () {
                          if (!loading) unawaited(_submit());
                        },
                        const SingleActivator(
                          LogicalKeyboardKey.numpadEnter,
                        ): () {
                          if (!loading) unawaited(_submit());
                        },
                      },
                      child: Focus(
                        autofocus: true,
                        child: Form(
                          key: _formKey,
                          child: Theme(
                            data: loginTheme,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text.rich(
                                      TextSpan(
                                        text: 'FULLPOS ',
                                        style: headerStyle,
                                        children: <InlineSpan>[
                                          TextSpan(
                                            text: 'CLOUD',
                                            style: headerStyle?.copyWith(
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Inicia sesión para continuar',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                TextFormField(
                                  controller: _emailCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Usuario',
                                    prefixIcon: const Icon(
                                      Icons.alternate_email,
                                    ),
                                    suffixIcon: _showsSavedUsers
                                        ? _buildSavedUsersMenu()
                                        : null,
                                  ),
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  onFieldSubmitted: (_) =>
                                      FocusScope.of(context).nextFocus(),
                                  validator: (v) {
                                    final value = v?.trim() ?? '';
                                    if (value.isEmpty) {
                                      return 'Ingresa tu email';
                                    }
                                    if (!validators.isEmail(value)) {
                                      return 'Email invalido';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _passwordCtrl,
                                  focusNode: _passwordFocusNode,
                                  decoration: InputDecoration(
                                    labelText: 'Contraseña',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      tooltip: _obscurePassword
                                          ? 'Mostrar contraseña'
                                          : 'Ocultar contraseña',
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                    ),
                                  ),
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) {
                                    if (!loading) unawaited(_submit());
                                  },
                                  validator: (v) => (v == null || v.isEmpty)
                                      ? 'Ingresa tu contrasena'
                                      : null,
                                ),
                                if (_notice != null) ...[
                                  const SizedBox(height: 12),
                                  _LoginNoticeCard(data: _notice!),
                                ],
                                const SizedBox(height: 16),
                                PrimaryButton(
                                  label: 'Iniciar sesión',
                                  loading: loading,
                                  onPressed: _submit,
                                ),
                                if (businessRegistrationDisabled) ...[
                                  const SizedBox(height: 14),
                                  const _ExistingBusinessAccountNotice(),
                                ] else ...[
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: loading
                                        ? null
                                        : () => context.go(Routes.register),
                                    icon: const Icon(Icons.storefront_rounded),
                                    label: const Text('Crear mi negocio'),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(48),
                                      backgroundColor: Colors.white,
                                      foregroundColor: AppColors.primaryDark,
                                      iconColor: AppColors.primary,
                                      iconSize: 20,
                                      side: const BorderSide(
                                        color: AppColors.secondaryBorder,
                                        width: 1.2,
                                      ),
                                      shadowColor: AppColors.primary
                                          .withValues(alpha: 0.12),
                                      elevation: 2,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      textStyle: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: loading
                                      ? null
                                      : () => context.go(Routes.forgotPassword),
                                  style: TextButton.styleFrom(
                                    foregroundColor: theme.colorScheme.primary,
                                    textStyle: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0,
                                    ),
                                  ),
                                  child: const Text(
                                    '¿Olvidaste tu contraseña?',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExistingBusinessAccountNotice extends StatelessWidget {
  const _ExistingBusinessAccountNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE1E8F2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '¿No tienes una cuenta?',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF1F3552),
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Solicita acceso al administrador de tu empresa.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF52667C),
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'FullPOS Cloud requiere una cuenta empresarial existente.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF52667C),
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginNoticeData {
  const _LoginNoticeData.error({
    required this.title,
    required this.message,
    required this.helpText,
    this.feedbackKind = AppFeedbackKind.error,
    this.showNotification = true,
    this.actionLabel,
    this.actionUri,
  }) : isError = true;

  final String title;
  final String message;
  final String helpText;
  final AppFeedbackKind feedbackKind;
  final bool showNotification;
  final bool isError;
  final String? actionLabel;
  final Uri? actionUri;
}

class _LoginNoticeCard extends StatelessWidget {
  const _LoginNoticeCard({required this.data});

  final _LoginNoticeData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = _loginNoticeBackground(data.feedbackKind);
    final foregroundColor = _loginNoticeForeground(data.feedbackKind);
    final accentColor = _loginNoticeAccent(data.feedbackKind);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              data.isError
                  ? Icons.error_outline_rounded
                  : Icons.check_circle_outline_rounded,
              color: accentColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: foregroundColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data.message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foregroundColor,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  data.helpText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: foregroundColor.withValues(alpha: 0.86),
                    height: 1.3,
                  ),
                ),
                if (data.actionLabel != null && data.actionUri != null) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: () => safeOpenWhatsApp(
                        context,
                        data.actionUri!,
                        copiedMessage:
                            'No se pudo abrir WhatsApp. Numero copiado.',
                      ),
                      icon: const Icon(Icons.chat_rounded, size: 18),
                      label: Text(data.actionLabel!),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1957E6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Color _loginNoticeBackground(AppFeedbackKind kind) {
  switch (kind) {
    case AppFeedbackKind.success:
      return AppColors.successSoft;
    case AppFeedbackKind.warning:
      return AppColors.warningSoft;
    case AppFeedbackKind.error:
      return AppColors.errorSoft;
    case AppFeedbackKind.info:
      return AppColors.surfaceAlt;
  }
}

Color _loginNoticeForeground(AppFeedbackKind kind) {
  switch (kind) {
    case AppFeedbackKind.success:
      return const Color(0xFF14532D);
    case AppFeedbackKind.warning:
      return const Color(0xFF7C3E00);
    case AppFeedbackKind.error:
      return const Color(0xFF7F1D1D);
    case AppFeedbackKind.info:
      return AppColors.textPrimary;
  }
}

Color _loginNoticeAccent(AppFeedbackKind kind) {
  switch (kind) {
    case AppFeedbackKind.success:
      return AppColors.success;
    case AppFeedbackKind.warning:
      return AppColors.warning;
    case AppFeedbackKind.error:
      return AppColors.error;
    case AppFeedbackKind.info:
      return AppColors.secondary;
  }
}

/// Premium brand-blue gradient used by the login action button.
///
/// Only brand tokens are used, and the state variations stay subtle so the
/// pressed / hovered feedback is still visible over the opaque gradient.
LinearGradient _loginPrimaryGradient(Set<WidgetState> states) {
  if (states.contains(WidgetState.disabled)) {
    return const LinearGradient(
      colors: [AppColors.borderStrong, AppColors.borderStrong],
    );
  }
  if (states.contains(WidgetState.pressed)) {
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.primaryDark, AppColors.primaryDark],
    );
  }
  if (states.contains(WidgetState.hovered) ||
      states.contains(WidgetState.focused)) {
    return const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [AppColors.primary, AppColors.primary],
    );
  }
  return const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, AppColors.primaryDark],
  );
}

/// Hint shown when this PC has no remembered username yet.
class _SavedUsersEmptyNotice extends StatelessWidget {
  const _SavedUsersEmptyNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: const Text(
          'Aún no hay usuarios guardados en esta PC',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}

/// A remembered username of this PC. The trailing "X" removes it from the PC.
class _SavedUserMenuItem extends StatefulWidget {
  const _SavedUserMenuItem({
    super.key,
    required this.user,
    required this.onSelected,
    required this.onRemoved,
  });

  final String user;
  final ValueChanged<String> onSelected;
  final Future<void> Function(String user) onRemoved;

  @override
  State<_SavedUserMenuItem> createState() => _SavedUserMenuItemState();
}

class _SavedUserMenuItemState extends State<_SavedUserMenuItem> {
  bool _hidden = false;

  Future<void> _remove() async {
    // The row hides itself so an open menu stays consistent with the stored
    // list even before the storage round trip finishes.
    setState(() => _hidden = true);
    await widget.onRemoved(widget.user);
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();

    return MenuItemButton(
      onPressed: () => widget.onSelected(widget.user),
      style: MenuItemButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsetsDirectional.only(start: 14, end: 4),
      ),
      child: Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              widget.user,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Quitar usuario de esta PC',
            onPressed: _remove,
            padding: EdgeInsets.zero,
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}
