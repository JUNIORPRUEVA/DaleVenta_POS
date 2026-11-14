import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/utils/app_feedback.dart';
import '../../../core/debug/app_error_reporter.dart';
import '../data/ecf_repository.dart';

/// Final company action after its own certification; never emits an invoice.
class EcfProductionActivationAction extends ConsumerStatefulWidget {
  const EcfProductionActivationAction({super.key});
  @override
  ConsumerState<EcfProductionActivationAction> createState() =>
      _ProductionActionState();
}

class _ProductionActionState
    extends ConsumerState<EcfProductionActivationAction> {
  bool _busy = false;

  void _refreshFiscalEnvironment() {
    ref.invalidate(ecfCapabilitiesProvider);
    ref.invalidate(ecfSequencesProvider);
    ref.invalidate(ecfEligibleOriginalsProvider);
    ref.invalidate(ecfOnboardingProvider);
    ref.invalidate(ecfDocumentsProvider);
    ref.invalidate(ecfDocumentDetailProvider);
    ref.invalidate(ecfCountersProvider);
  }

  Future<void> _activate() async {
    if (_busy) return;
    final companyId = ref.read(authStateProvider).user?.companyId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Habilitar producción'),
        content: const Text(
          'Esta empresa utilizará sus credenciales y rangos de producción. Después registra los comprobantes autorizados por la DGII. Esta acción no emite facturas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Habilitar'),
          ),
        ],
      ),
    );
    if (confirmed != true ||
        !mounted ||
        companyId == null ||
        companyId != ref.read(authStateProvider).user?.companyId) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(ecfRepositoryProvider).enableProduction(expectedCompanyId: companyId);
      _refreshFiscalEnvironment();
      if (mounted) {
        AppFeedback.showToast(
          context,
          title: 'Producción habilitada',
          body: 'Registra la numeración autorizada de esta empresa.',
          kind: AppFeedbackKind.info,
          duration: const Duration(seconds: 4),
        );
      }
    } catch (error, stack) {
      AppErrorReporter.instance.record(
        error,
        stack,
        context: 'Activación productiva e-CF',
        notifyUser: false,
      );
      _refreshFiscalEnvironment();
      if (mounted) {
        AppFeedback.showToast(
          context,
          title: 'No se habilitó producción',
          body:
              'Revisa la certificación, las credenciales y los resultados pendientes.',
          kind: AppFeedbackKind.warning,
          duration: const Duration(seconds: 4),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(ecfCapabilitiesProvider).valueOrNull;
    final user = ref.watch(authStateProvider).user;
    if (caps?.canActivateProduction != true ||
        !hasUserPermission(user, AppPermission.manageEcfConfig)) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: _busy ? null : _activate,
        icon: const Icon(Icons.verified_outlined),
        label: Text(_busy ? 'Habilitando…' : 'Habilitar producción'),
      ),
    );
  }
}
