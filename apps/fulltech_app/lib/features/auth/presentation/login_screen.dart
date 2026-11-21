import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:validators/validators.dart' as validators;

import '../../../core/auth/app_role.dart';
import '../../../core/utils/open_web_registration.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/errors/api_exception.dart';
import '../../../core/debug/app_error_reporter.dart';
import '../../../core/routing/route_access.dart';
import '../../../core/routing/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/app_feedback.dart';
import '../../../core/utils/safe_url_launcher.dart';
import '../../../core/widgets/primary_button.dart';
import '../data/remembered_login_users_storage.dart';

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
  bool _obscurePassword = true;

  final _rememberedUsersStorage = const RememberedLoginUsersStorage();
  final MenuController _savedUsersMenuController = MenuController();
  List<String> _savedUsers = const <String>[];

  /// The list of usernames used on this device is available on Windows, Android
  /// and iOS (the web deployment has no local device list).
  bool get _showsSavedUsers =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

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
    AppFeedback.dismissPersistentNotification();
    super.dispose();
  }

  void _clearNoticeOnInput() {
    AppFeedback.dismissPersistentNotification();
    AppErrorReporter.instance.clear();
  }

  Future<void> _loadSavedUsers() async {
    if (!_showsSavedUsers) return;
    final users = await _rememberedUsersStorage.loadUsers();
    if (!mounted) return;
    setState(() => _savedUsers = users);
  }

  /// Stores the username of a successful login. The password is never stored.
  Future<void> _rememberUserAfterLogin() async {
    if (!_showsSavedUsers) return;
    final users = await _rememberedUsersStorage.rememberUser(_emailCtrl.text);
    if (!mounted) return;
    setState(() => _savedUsers = users);
  }

  Future<void> _removeSavedUser(String user) async {
    final users = await _rememberedUsersStorage.removeUser(user);
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
                  emailController: _emailCtrl,
                  onSelected: _selectSavedUser,
                  onRemoved: _removeSavedUser,
                ),
            ],
      builder: (context, controller, child) {
        return IconButton(
          tooltip: 'Usuarios de este dispositivo',
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
          helpText: 'Intenta nuevamente o solicita ayuda al administrador.',
          feedbackKind: AppFeedbackKind.warning,
        );
      case ApiErrorType.forbidden:
        return _LoginNoticeData.error(
          title: 'Acceso restringido',
          message: error.message,
          helpText:
              'Si tu acceso deberia estar activo, comunicate con administracion.',
        );
      case ApiErrorType.noInternet:
        return _buildContinuityNotice();
      case ApiErrorType.dns:
        return _buildContinuityNotice();
      case ApiErrorType.tls:
        return _LoginNoticeData.error(
          title: 'Conexión segura rechazada',
          message: error.message,
          helpText:
              'Verifica la fecha y hora de la PC. Si usas antivirus o red empresarial, puede estar bloqueando la conexión.',
        );
      case ApiErrorType.network:
        return _buildContinuityNotice();
      case ApiErrorType.timeout:
        return _buildContinuityNotice();
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

  _LoginNoticeData _buildContinuityNotice() {
    return const _LoginNoticeData.error(
      title: 'Modo local',
      message: 'Puedes vender 48 h.',
      helpText: 'Sincroniza al volver.',
      feedbackKind: AppFeedbackKind.info,
    );
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (!validators.isEmail(email) || _passwordCtrl.text.isEmpty) {
      _showLoginFailureNotification(
        const _LoginNoticeData.error(
          title: 'Revisa tus datos',
          message: 'Introduce un correo válido y tu contraseña.',
          helpText: '',
          feedbackKind: AppFeedbackKind.warning,
        ),
      );
      return;
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    AppFeedback.dismissPersistentNotification();
    try {
      final user = await ref
          .read(authStateProvider.notifier)
          .login(_emailCtrl.text, _passwordCtrl.text);
      await _rememberUserAfterLogin();
      if (!mounted) return;
      AppFeedback.dismissPersistentNotification();
      final destination = RouteAccess.defaultHomeForRole(
        user?.appRole ?? AppRole.unknown,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go(destination);
      });
      return;
    } on ApiException catch (e) {
      if (mounted) {
        final notice = _buildErrorNotice(e);
        _showLoginFailureNotification(notice);
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
        _showLoginFailureNotification(notice);
      }
    }
  }

  void _showLoginFailureNotification(_LoginNoticeData notice) {
    if (!mounted) return;
    AppErrorReporter.instance.clear();
    AppFeedback.showPersistentNotification(
      context,
      AppFeedbackNotification(
        title: notice.title,
        body: '${notice.message} ${notice.helpText}',
        kind: notice.feedbackKind,
        compact: true,
        paragraph: true,
        actionLabel: notice.actionLabel,
        onAction: notice.actionUri == null
            ? null
            : () => _openHelp(notice.actionUri!),
      ),
      scope: 'LoginScreen',
    );
  }

  Future<void> _openHelp(Uri uri) async {
    if (await tryOpenUrl(uri)) return;
    try {
      await Clipboard.setData(ClipboardData(text: uri.toString()));
    } catch (_) {
      // Keep the address visible if the clipboard is unavailable.
    }
    if (!mounted) return;
    _showLoginFailureNotification(
      _LoginNoticeData.error(
        title: 'Abre el enlace de ayuda',
        message: uri.toString(),
        helpText: '',
        feedbackKind: AppFeedbackKind.info,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNativeMobile =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
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
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.headlineSmall?.copyWith(
      color: AppColors.textPrimary,
      fontSize: 26,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      height: 1.1,
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
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.25,
              height: 1.2,
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
              keyboardDismissBehavior: isNativeMobile
                  ? ScrollViewKeyboardDismissBehavior.onDrag
                  : ScrollViewKeyboardDismissBehavior.manual,
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                24,
                horizontalPadding,
                24 + (isNativeMobile ? 0 : viewInsets.bottom),
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
                                        text: 'FullPOS ',
                                        style: headerStyle,
                                        children: <InlineSpan>[
                                          TextSpan(
                                            text: 'Cloud',
                                            style: headerStyle?.copyWith(
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      'Todo tu negocio bajo control',
                                      style: TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w400,
                                        letterSpacing: 0.1,
                                        height: 1.35,
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
                                  autofillHints: isNativeMobile
                                      ? const [AutofillHints.username]
                                      : null,
                                  autocorrect: !isNativeMobile,
                                  enableSuggestions: !isNativeMobile,
                                  keyboardAppearance: isNativeMobile
                                      ? Brightness.light
                                      : null,
                                  textInputAction: TextInputAction.next,
                                  onFieldSubmitted: (_) =>
                                      FocusScope.of(context).nextFocus(),
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
                                  autofillHints: isNativeMobile
                                      ? const [AutofillHints.password]
                                      : null,
                                  autocorrect: !isNativeMobile,
                                  enableSuggestions: !isNativeMobile,
                                  keyboardAppearance: isNativeMobile
                                      ? Brightness.light
                                      : null,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) {
                                    if (!loading) unawaited(_submit());
                                  },
                                ),
                                const SizedBox(height: 16),
                                PrimaryButton(
                                  label: 'Iniciar sesión',
                                  loading: loading,
                                  onPressed: _submit,
                                ),
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.center,
                                  child: TextButton(
                                    onPressed: loading
                                        ? null
                                        : () =>
                                              context.go(Routes.forgotPassword),
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          theme.colorScheme.primary,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 2,
                                      ),
                                      minimumSize: const Size(0, 0),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      textStyle: const TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.1,
                                        height: 1.2,
                                      ),
                                    ),
                                    child: const Text(
                                      '¿Olvidaste tu contraseña?',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                if (isNativeMobile)
                                  Text(
                                    'Para usar la app, necesitas una cuenta de FullPOS Cloud previamente creada.',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                                  )
                                else
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        '¿No tienes una cuenta?',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color: AppColors.textSecondary,
                                            ),
                                      ),
                                      TextButton(
                                        onPressed: loading
                                            ? null
                                            : () =>
                                                  openWebRegistration(context),
                                        style: TextButton.styleFrom(
                                          textStyle:
                                              theme.textTheme.labelMedium,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                          ),
                                        ),
                                        child: const Text('Crear cuenta'),
                                      ),
                                    ],
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

class _LoginNoticeData {
  const _LoginNoticeData.error({
    required this.title,
    required this.message,
    required this.helpText,
    this.feedbackKind = AppFeedbackKind.error,
    this.actionLabel,
    this.actionUri,
  });

  final String title;
  final String message;
  final String helpText;
  final AppFeedbackKind feedbackKind;
  final String? actionLabel;
  final Uri? actionUri;
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
          'Aún no hay usuarios guardados en este dispositivo',
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

/// A remembered username of this device. The trailing "X" removes it from the
/// device.
class _SavedUserMenuItem extends StatefulWidget {
  const _SavedUserMenuItem({
    super.key,
    required this.user,
    required this.emailController,
    required this.onSelected,
    required this.onRemoved,
  });

  final String user;

  /// Live text of the Usuario field: the row uses it to recognise itself as the
  /// current user instead of offering a redundant selection.
  final TextEditingController emailController;

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

    // The row follows the Usuario field: the user already written there is the
    // current one, so it is labelled as such and cannot be selected again (the
    // X keeps working to forget it).
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.emailController,
      builder: (context, value, _) {
        final isCurrent =
            value.text.trim().toLowerCase() == widget.user.trim().toLowerCase();
        return MenuItemButton(
          onPressed: isCurrent ? null : () => widget.onSelected(widget.user),
          style: MenuItemButton.styleFrom(
            minimumSize: const Size(0, 40),
            padding: const EdgeInsetsDirectional.only(start: 14, end: 4),
          ),
          child: Row(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  widget.user,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isCurrent
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isCurrent) ...[
                const SizedBox(width: 8),
                const Text(
                  'Actual',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const Spacer(),
              IconButton(
                tooltip: 'Quitar usuario de este dispositivo',
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
      },
    );
  }
}
