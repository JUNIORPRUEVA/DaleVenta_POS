import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/ecf_repository.dart';
import '../../ecf_models.dart';
import 'ecf_flow_kit.dart';

/// Declaración del rango de numeración de comprobantes (e-NCF).
///
/// Por qué existe
/// -------------
/// El backend no inventa la numeración: cada comprobante consume el siguiente
/// número de un rango que la DGII asignó a la empresa. Si no hay rango activo,
/// preparar un documento falla con `ECF_SEQUENCE_EXHAUSTED`, un mensaje que no
/// explica nada porque en realidad nunca se declaró el rango. Hasta ahora no
/// existía ninguna pantalla que permitiera declararlo, así que el cliente quedaba
/// autorizado pero incapaz de facturar.
///
/// Decisiones de diseño
/// --------------------
/// * **Se oculta sola.** Si ya hay un rango activo con números disponibles, no
///   muestra nada: no se pide dos veces el mismo dato.
/// * **Solo dos números.** El prefijo lo deriva el backend del tipo de
///   comprobante, así que no se le pide al cliente.
/// * **Fail-closed en la interfaz.** No deja enviar «desde» mayor que «hasta» ni
///   valores no numéricos; el servidor lo rechazaría igual, pero el mensaje local
///   es más claro.
/// * **Sin permiso no se muestra**, igual que en el resto del módulo.
class EcfSequenceRangeSection extends ConsumerStatefulWidget {
  const EcfSequenceRangeSection({super.key, required this.canManage});

  /// Mismo permiso que exige el backend (`manageEcfSequences`).
  final bool canManage;

  @override
  ConsumerState<EcfSequenceRangeSection> createState() =>
      _EcfSequenceRangeSectionState();
}

class _EcfSequenceRangeSectionState
    extends ConsumerState<EcfSequenceRangeSection> {
  final _from = TextEditingController();
  final _to = TextEditingController();

  List<EcfSequenceInfo> _sequences = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    if (widget.canManage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  /// ¿Ya hay numeración utilizable para facturas (E31)?
  bool get _hasUsableRange => _sequences.any(
    (sequence) =>
        sequence.active &&
        sequence.documentType == 'E31' &&
        sequence.remaining > 0,
  );

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref.read(ecfRepositoryProvider).sequences();
      if (!mounted) return;
      setState(() => _sequences = rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo consultar tu numeración.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    final from = int.tryParse(_from.text.trim());
    final to = int.tryParse(_to.text.trim());
    if (from == null || to == null || from < 1 || to < from) {
      setState(() {
        _error = 'Escribe el número inicial y el final (el final no puede ser '
            'menor que el inicial).';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(ecfRepositoryProvider)
          .registerSequence(
            documentType: 'E31',
            startNumber: from,
            endNumber: to,
          );
      if (!mounted) return;
      setState(() => _done = true);
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _describeSaveError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Traduce los códigos del backend: son los que el cliente puede corregir.
  String _describeSaveError(Object error) {
    final text = error.toString();
    if (text.contains('ECF_SEQUENCE_ALREADY_EXISTS')) {
      return 'Ya tienes una numeración activa para ese tipo de comprobante.';
    }
    if (text.contains('ECF_SEQUENCE_REUSE_BLOCKED')) {
      return 'No puedes empezar por debajo de un número que ya usaste.';
    }
    if (text.contains('ECF_SEQUENCE_RANGE_INVALID')) {
      return 'El rango no es válido: revisa el número inicial y el final.';
    }
    return 'No se pudo guardar la numeración. Inténtalo de nuevo.';
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.canManage) return const SizedBox.shrink();
    if (_loading) return const SizedBox.shrink();
    // Con numeración disponible no hay nada que pedir.
    if (_hasUsableRange) return const SizedBox.shrink();

    if (_done && !_hasUsableRange) {
      return const EcfInlineNote(
        tone: EcfTone.warning,
        text: 'La numeración se guardó, pero todavía no aparece disponible. '
            'Pulsa actualizar para comprobarlo.',
      );
    }

    return EcfSection(
      title: 'Numeración de facturas',
      subtitle:
          'Los números que te asignó la DGII. Hacen falta para poder emitir.',
      icon: Icons.pin_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('ecf_sequence_from'),
                  controller: _from,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Desde',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  key: const ValueKey('ecf_sequence_to'),
                  controller: _to,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Hasta',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Escribe solo los números. El prefijo lo agrega el sistema.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(fontSize: 12, color: AppColors.error),
            ),
          ],
          const SizedBox(height: 12),
          EcfPrimaryAction(
            label: 'Guardar numeración',
            icon: Icons.save_outlined,
            busy: _saving,
            onPressed: _saving ? null : _save,
            buttonKey: const ValueKey('ecf_sequence_save'),
          ),
        ],
      ),
    );
  }
}
