import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tokens visuales centralizados para todos los diálogos de FullTech.
class FullTechDialogTokens {
  const FullTechDialogTokens._();

  // Radio de bordes
  static const double borderRadius = 18.0;
  static const double borderRadiusSmall = 14.0;

  // Padding
  static const EdgeInsets padding = EdgeInsets.fromLTRB(28, 24, 28, 20);
  static const EdgeInsets paddingCompact = EdgeInsets.fromLTRB(24, 20, 24, 18);
  static const EdgeInsets contentPadding = EdgeInsets.symmetric(vertical: 8);
  static const EdgeInsets actionsPadding = EdgeInsets.only(top: 16);

  // Dimensiones
  static const double maxWidthSmall = 420;
  static const double maxWidthMedium = 520;
  static const double maxWidthLarge = 680;
  static const double maxWidthXLarge = 800;

  // Colores
  static const Color overlayColor = Color(0x80000000);
  static const Color surfaceColor = Colors.white;
  static const Color titleColor = Color(0xFF0F172A);
  static const Color subtitleColor = Color(0xFF52667C);
  static const Color dividerColor = Color(0xFFE8EDF2);
  static const Color primaryButtonColor = Color(0xFF1957E6);
  static const Color primaryButtonHover = Color(0xFF1547C4);
  static const Color secondaryButtonColor = Colors.white;
  static const Color secondaryButtonBorder = Color(0xFFD0D5DD);
  static const Color secondaryButtonText = Color(0xFF344054);
  static const Color closeButtonColor = Color(0xFF98A2B3);
  static const Color inputBorderColor = Color(0xFFD0D5DD);
  static const Color inputFocusedBorderColor = Color(0xFF1957E6);
  static const Color inputLabelColor = Color(0xFF344054);
  static const Color errorColor = Color(0xFFEF4444);

  // Sombras
  static List<BoxShadow> get shadow => [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.08),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  // Tipografía
  static const TextStyle titleStyle = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: titleColor,
    height: 1.3,
  );

  static const TextStyle titleStyleSmall = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w700,
    color: titleColor,
    height: 1.3,
  );

  static const TextStyle messageStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: subtitleColor,
    height: 1.5,
  );

  static const TextStyle labelStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: titleColor,
  );
}

/// Botón principal azul para diálogos.
class DialogPrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final Color? backgroundColor;

  const DialogPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.backgroundColor,
  });

  @override
  State<DialogPrimaryButton> createState() => _DialogPrimaryButtonState();
}

class _DialogPrimaryButtonState extends State<DialogPrimaryButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        child: ElevatedButton(
          onPressed: widget.isLoading ? null : widget.onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isHovered
                ? (widget.backgroundColor ??
                      FullTechDialogTokens.primaryButtonHover)
                : (widget.backgroundColor ??
                      FullTechDialogTokens.primaryButtonColor),
            foregroundColor: Colors.white,
            disabledBackgroundColor: FullTechDialogTokens.primaryButtonColor
                .withValues(alpha: 0.5),
            disabledForegroundColor: Colors.white70,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          child: widget.isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 18),
                      const SizedBox(width: 8),
                    ],
                    Text(widget.label),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Botón secundario (blanco con borde) para diálogos.
class DialogSecondaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;

  const DialogSecondaryButton({super.key, required this.label, this.onPressed});

  @override
  State<DialogSecondaryButton> createState() => _DialogSecondaryButtonState();
}

class _DialogSecondaryButtonState extends State<DialogSecondaryButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        child: OutlinedButton(
          onPressed: widget.onPressed,
          style: OutlinedButton.styleFrom(
            backgroundColor: _isHovered
                ? const Color(0xFFF9FAFB)
                : Colors.white,
            foregroundColor: FullTechDialogTokens.secondaryButtonText,
            side: BorderSide(
              color: _isHovered
                  ? FullTechDialogTokens.secondaryButtonBorder
                  : FullTechDialogTokens.secondaryButtonBorder,
              width: 1.5,
            ),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
          child: Text(widget.label),
        ),
      ),
    );
  }
}

/// Barra de acciones para diálogos.
class DialogActionBar extends StatelessWidget {
  final List<Widget> actions;
  final EdgeInsetsGeometry? padding;

  const DialogActionBar({super.key, required this.actions, this.padding});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? FullTechDialogTokens.actionsPadding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          ...actions.expand(
            (action) => [
              action,
              if (action != actions.last) const SizedBox(width: 12),
            ],
          ),
        ],
      ),
    );
  }
}

/// Diálogo base reutilizable con el estilo visual unificado de FullTech.
///
/// Proporciona:
/// - Overlay oscuro semitransparente
/// - Contenedor blanco con bordes redondeados y sombra
/// - Título con línea divisoria
/// - Área de contenido flexible
/// - Barra de acciones con botones estilizados
class FullTechDialog extends StatelessWidget {
  /// Título del diálogo.
  final String title;

  /// Widget de contenido.
  final Widget child;

  /// Acciones a mostrar en la barra inferior.
  final List<Widget>? actions;

  /// Ancho máximo del diálogo.
  final double maxWidth;

  /// Si se muestra el botón de cerrar (X).
  final bool showCloseButton;

  /// Callback al cerrar.
  final VoidCallback? onClose;

  /// Subtítulo opcional debajo del título.
  final String? subtitle;

  /// Padding personalizado.
  final EdgeInsetsGeometry? padding;

  /// Acción ejecutada con Enter / Numpad Enter.
  final VoidCallback? onShortcutSubmit;

  /// Acción ejecutada con Escape.
  final VoidCallback? onShortcutCancel;

  const FullTechDialog({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.maxWidth = FullTechDialogTokens.maxWidthMedium,
    this.showCloseButton = false,
    this.onClose,
    this.subtitle,
    this.padding,
    this.onShortcutSubmit,
    this.onShortcutCancel,
  });

  /// Muestra este diálogo usando showDialog.
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget child,
    List<Widget>? actions,
    double maxWidth = FullTechDialogTokens.maxWidthMedium,
    bool showCloseButton = false,
    VoidCallback? onClose,
    String? subtitle,
    EdgeInsetsGeometry? padding,
    bool barrierDismissible = true,
    VoidCallback? onShortcutSubmit,
    VoidCallback? onShortcutCancel,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: FullTechDialogTokens.overlayColor,
      builder: (ctx) => FullTechDialog(
        title: title,
        actions: actions,
        maxWidth: maxWidth,
        showCloseButton: showCloseButton,
        onClose: onClose ?? () => Navigator.of(ctx).pop(),
        subtitle: subtitle,
        padding: padding,
        onShortcutSubmit: onShortcutSubmit,
        onShortcutCancel: onShortcutCancel ?? () => Navigator.of(ctx).pop(),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      child: CallbackShortcuts(
        bindings: {
          if (onShortcutSubmit != null)
            const SingleActivator(LogicalKeyboardKey.enter): onShortcutSubmit!,
          if (onShortcutSubmit != null)
            const SingleActivator(LogicalKeyboardKey.numpadEnter):
                onShortcutSubmit!,
          if (onShortcutCancel != null)
            const SingleActivator(LogicalKeyboardKey.escape): onShortcutCancel!,
        },
        child: Focus(
          autofocus: true,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: BoxConstraints(maxWidth: maxWidth),
                margin: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 40,
                ),
                decoration: BoxDecoration(
                  color: FullTechDialogTokens.surfaceColor,
                  borderRadius: BorderRadius.circular(
                    maxWidth <= FullTechDialogTokens.maxWidthSmall
                        ? FullTechDialogTokens.borderRadiusSmall
                        : FullTechDialogTokens.borderRadius,
                  ),
                  boxShadow: FullTechDialogTokens.shadow,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(context),
                    _buildDivider(),
                    Flexible(
                      child: Padding(
                        padding: padding ?? FullTechDialogTokens.contentPadding,
                        child: child,
                      ),
                    ),
                    if (actions != null && actions!.isNotEmpty) ...[
                      _buildDivider(),
                      Padding(
                        padding: padding ?? FullTechDialogTokens.padding,
                        child: DialogActionBar(actions: actions!),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: padding ?? FullTechDialogTokens.padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: maxWidth <= FullTechDialogTokens.maxWidthSmall
                      ? FullTechDialogTokens.titleStyleSmall
                      : FullTechDialogTokens.titleStyle,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: FullTechDialogTokens.messageStyle),
                ],
              ],
            ),
          ),
          if (showCloseButton)
            SizedBox(
              height: 32,
              width: 32,
              child: IconButton(
                onPressed: onClose,
                icon: Icon(
                  Icons.close_rounded,
                  size: 20,
                  color: FullTechDialogTokens.closeButtonColor,
                ),
                padding: EdgeInsets.zero,
                splashRadius: 18,
                tooltip: 'Cerrar',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(height: 1, color: FullTechDialogTokens.dividerColor);
  }
}

/// Diálogo de confirmación compacto y elegante.
///
/// Uso típico: confirmar acciones como cancelar venta, eliminar, etc.
class FullTechConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmText;
  final String cancelText;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final IconData? icon;
  final Color? iconColor;
  final bool isDestructive;
  final bool isLoading;

  const FullTechConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    this.confirmText = 'Aceptar',
    this.cancelText = 'Cancelar',
    this.onConfirm,
    this.onCancel,
    this.icon,
    this.iconColor,
    this.isDestructive = false,
    this.isLoading = false,
  });

  /// Muestra el diálogo de confirmación.
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Aceptar',
    String cancelText = 'Cancelar',
    VoidCallback? onConfirm,
    VoidCallback? onCancel,
    IconData? icon,
    Color? iconColor,
    bool isDestructive = false,
    bool isLoading = false,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: FullTechDialogTokens.overlayColor,
      builder: (ctx) => FullTechConfirmDialog(
        title: title,
        message: message,
        confirmText: confirmText,
        cancelText: cancelText,
        onConfirm:
            onConfirm ??
            () {
              Navigator.of(ctx).pop(true);
            },
        onCancel: onCancel ?? () => Navigator.of(ctx).pop(false),
        icon: icon,
        iconColor: iconColor,
        isDestructive: isDestructive,
        isLoading: isLoading,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FullTechDialog(
      title: title,
      maxWidth: FullTechDialogTokens.maxWidthSmall,
      showCloseButton: false,
      onShortcutSubmit: isLoading ? null : onConfirm,
      onShortcutCancel: isLoading ? null : onCancel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: (iconColor ?? FullTechDialogTokens.primaryButtonColor)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                size: 28,
                color: iconColor ?? FullTechDialogTokens.primaryButtonColor,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            message,
            style: FullTechDialogTokens.messageStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: DialogSecondaryButton(
                  label: cancelText,
                  onPressed: isLoading ? null : onCancel,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DialogPrimaryButton(
                  label: confirmText,
                  onPressed: isLoading ? null : onConfirm,
                  isLoading: isLoading,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Diálogo para formularios con estructura consistente.
///
/// Uso típico: crear/editar productos, clientes, categorías, etc.
class FullTechFormDialog extends StatelessWidget {
  final String title;
  final Widget content;
  final String? subtitle;
  final String confirmText;
  final String cancelText;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final bool isLoading;
  final double maxWidth;
  final bool showCloseButton;

  const FullTechFormDialog({
    super.key,
    required this.title,
    required this.content,
    this.subtitle,
    this.confirmText = 'Guardar',
    this.cancelText = 'Cancelar',
    this.onConfirm,
    this.onCancel,
    this.isLoading = false,
    this.maxWidth = FullTechDialogTokens.maxWidthLarge,
    this.showCloseButton = true,
  });

  /// Muestra el diálogo de formulario.
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget content,
    String? subtitle,
    String confirmText = 'Guardar',
    String cancelText = 'Cancelar',
    VoidCallback? onConfirm,
    VoidCallback? onCancel,
    bool isLoading = false,
    double maxWidth = FullTechDialogTokens.maxWidthLarge,
    bool showCloseButton = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: !isLoading,
      barrierColor: FullTechDialogTokens.overlayColor,
      builder: (ctx) => FullTechFormDialog(
        title: title,
        content: content,
        subtitle: subtitle,
        confirmText: confirmText,
        cancelText: cancelText,
        onConfirm: onConfirm,
        onCancel: onCancel ?? () => Navigator.of(ctx).pop(),
        isLoading: isLoading,
        maxWidth: maxWidth,
        showCloseButton: showCloseButton,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FullTechDialog(
      title: title,
      subtitle: subtitle,
      maxWidth: maxWidth,
      showCloseButton: showCloseButton,
      onClose: isLoading ? null : onCancel,
      onShortcutSubmit: isLoading ? null : onConfirm,
      onShortcutCancel: isLoading ? null : onCancel,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            content,
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: DialogSecondaryButton(
                    label: cancelText,
                    onPressed: isLoading ? null : onCancel,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DialogPrimaryButton(
                    label: confirmText,
                    onPressed: isLoading ? null : onConfirm,
                    isLoading: isLoading,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget helper para crear inputs estilizados consistentes en diálogos.
class FullTechDialogField extends StatelessWidget {
  final String label;
  final String? hintText;
  final TextEditingController? controller;
  final String? initialValue;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? errorText;
  final int? maxLines;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final TextInputAction? textInputAction;
  final FormFieldValidator<String>? validator;
  final bool enabled;

  const FullTechDialogField({
    super.key,
    required this.label,
    this.hintText,
    this.controller,
    this.initialValue,
    this.keyboardType,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.errorText,
    this.maxLines = 1,
    this.autofocus = false,
    this.onChanged,
    this.onFieldSubmitted,
    this.textInputAction,
    this.validator,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        initialValue: initialValue,
        keyboardType: keyboardType,
        obscureText: obscureText,
        maxLines: maxLines,
        autofocus: autofocus,
        enabled: enabled,
        onChanged: onChanged,
        onFieldSubmitted: onFieldSubmitted,
        textInputAction: textInputAction,
        validator: validator,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: FullTechDialogTokens.titleColor,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          labelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: FullTechDialogTokens.inputLabelColor,
          ),
          floatingLabelStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: FullTechDialogTokens.primaryButtonColor,
          ),
          prefixIcon: prefixIcon,
          suffixIcon: suffixIcon,
          errorText: errorText,
          errorStyle: const TextStyle(
            fontSize: 12,
            color: FullTechDialogTokens.errorColor,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: FullTechDialogTokens.inputBorderColor,
              width: 1.5,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: FullTechDialogTokens.inputBorderColor,
              width: 1.5,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: FullTechDialogTokens.inputFocusedBorderColor,
              width: 2,
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: FullTechDialogTokens.errorColor,
              width: 1.5,
            ),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
              color: FullTechDialogTokens.errorColor,
              width: 2,
            ),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
    );
  }
}
