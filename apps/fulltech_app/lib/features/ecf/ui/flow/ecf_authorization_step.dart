import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/ecf_repository.dart';
import 'ecf_flow_kit.dart';

/// Último paso del recorrido: la empresa autoriza a FullPOS Cloud a emitir.
///
/// Por qué existe
/// -------------
/// Cuando DOSA cierra la postulación, la DGII ya aprobó la empresa: pedirle
/// además un documento que el trámite no entrega dejaba al cliente bloqueado sin
/// nada que subir. Lo que sí falta —y sí es del cliente— es su propia
/// autorización para que el sistema emita en su nombre.
///
/// Esa autorización se registra como decisión auditada con usuario y fecha (la
/// misma vía que usa el backend para la autorización administrativa), así que
/// queda trazable y revocable. La aprobación de la DGII no se toca aquí.
class EcfAuthorizationStep extends ConsumerStatefulWidget {
  const EcfAuthorizationStep({
    super.key,
    required this.canAuthorize,
    required this.alreadySigned,
    required this.onSigned,
  });

  /// Mismo permiso que exige el backend (`recordEcfDgiiOfficialVerification`).
  final bool canAuthorize;

  /// La empresa ya registró su autorización.
  final bool alreadySigned;

  /// Se avisa a la pantalla para que recargue el expediente y el estado.
  final VoidCallback onSigned;

  @override
  ConsumerState<EcfAuthorizationStep> createState() =>
      _EcfAuthorizationStepState();
}

class _EcfAuthorizationStepState extends ConsumerState<EcfAuthorizationStep> {
  bool _accepted = false;
  bool _busy = false;
  bool _signedHere = false;
  String? _error;

  Future<void> _sign() async {
    if (_busy || !_accepted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(ecfRepositoryProvider).recordDgiiAuthorization(
        source: 'MANUAL_OPERATOR_DECLARATION',
      );
      if (!mounted) return;
      setState(() => _signedHere = true);
      widget.onSigned();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.alreadySigned || _signedHere) {
      return const EcfSection(
        title: 'Autorización para emitir',
        icon: Icons.verified_outlined,
        child: EcfInlineNote(
          tone: EcfTone.done,
          text: 'Tu empresa autorizó a FullPOS Cloud a emitir comprobantes '
              'electrónicos con la numeración autorizada por la DGII.',
        ),
      );
    }

    return EcfSection(
      title: 'Autorización para emitir',
      subtitle: 'La DGII ya aprobó tu postulación. Solo falta que tu empresa '
          'autorice al sistema a emitir en su nombre.',
      icon: Icons.verified_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Autorizo a FullPOS Cloud a emitir comprobantes de facturación '
            'electrónica con la numeración que la DGII autorizó a mi empresa, '
            'y respondo por la exactitud de los datos registrados. Entiendo que '
            'cada comprobante emitido consume un número de forma definitiva.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                key: const ValueKey('ecf_authorization_check'),
                value: _accepted,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: _busy
                    ? null
                    : (value) => setState(() {
                        _accepted = value ?? false;
                        _error = null;
                      }),
              ),
              const SizedBox(width: 2),
              const Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'He leído y acepto esta autorización.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            EcfInlineNote(tone: EcfTone.warning, text: _error!),
          ],
          const SizedBox(height: 12),
          EcfPrimaryAction(
            label: 'Autorizar emisión',
            icon: Icons.check_circle_outline,
            busy: _busy,
            onPressed: !widget.canAuthorize || !_accepted || _busy ? null : _sign,
            buttonKey: const ValueKey('ecf_authorization_sign'),
          ),
          if (!widget.canAuthorize) ...[
            const SizedBox(height: 8),
            const Text(
              'Solo un administrador de la empresa puede firmar esta '
              'autorización.',
              style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
