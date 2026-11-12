import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Botón de **vista previa del diseño**, exclusivo de la empresa de prueba.
///
/// Se dibuja únicamente cuando la aplicación se compila con
/// `--dart-define=ECF_FLOW_PREVIEW_RNC=<RNC de la empresa de prueba>` y la
/// empresa de la sesión tiene ese mismo RNC. Una compilación normal (sin esa
/// variable) no puede mostrar el botón: no hay forma de activarlo en producción.
///
/// No escribe nada ni altera datos: solo cambia el paso que se está mirando,
/// para poder repasar las cuatro pantallas del recorrido.
class EcfFlowPreviewButton extends StatelessWidget {
  const EcfFlowPreviewButton({
    super.key,
    required this.onPressed,
    required this.nextLabel,
  });

  final VoidCallback onPressed;

  /// Nombre del paso al que se saltará, para que el botón sea autoexplicativo.
  final String nextLabel;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        mouseCursor: SystemMouseCursors.click,
        onTap: onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
          decoration: BoxDecoration(
            color: AppColors.warningSoft,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.warningBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.skip_next_rounded,
                size: 15,
                color: Color(0xFF92400E),
              ),
              const SizedBox(width: 6),
              Text(
                'Saltar a $nextLabel',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF92400E),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
