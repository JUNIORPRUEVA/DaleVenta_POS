import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

class AiAssistantDockButton extends StatelessWidget {
  const AiAssistantDockButton({
    super.key,
    required this.onPressed,
    this.isActive = false,
    this.compact = false,
  });

  static const imageAsset = 'assets/image/asistente-ia.png';

  final VoidCallback onPressed;
  final bool isActive;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 64.0 : 72.0;
    final label = isActive
        ? 'Asistente de IA, abierto. Cerrar el asistente'
        : 'Abrir el asistente de IA';

    return Semantics(
      button: true,
      label: label,
      // SIN `Tooltip` a propósito, igual que en `LicensePurchaseOverlay` y en el
      // banner de errores: este botón vive en el `Stack` del `builder` de
      // MaterialApp, POR ENCIMA del Navigator, donde no existe ningún `Overlay`.
      // `RawTooltip` lo exige y lanzaba `No Overlay widget found` en cada build,
      // que el manejador global convertía en un aviso de error. La etiqueta
      // accesible se conserva en `Semantics` y el `InkWell` mantiene el realce
      // al pasar el ratón.
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: isActive
              ? Border.all(color: AppColors.primary, width: 2)
              : null,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryDark.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onPressed,
            child: Ink.image(
              image: const AssetImage(imageAsset),
              width: size,
              height: size,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
