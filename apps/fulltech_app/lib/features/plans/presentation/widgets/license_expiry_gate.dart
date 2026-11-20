import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/license/license_demo_state.dart';
import '../../../../core/license/license_repository.dart';
import '../../../../core/routing/routes.dart';
import '../../../../core/utils/safe_url_launcher.dart';
import '../plans_open_provider.dart';
import '../screens/license_expired_screen_v2.dart';
import '../screens/license_suspended_screen.dart';
import '../screens/license_trial_ended_screen.dart';

/// Capa de **plan vencido** encima de la pantalla de trabajo.
///
/// El cliente entra y ve su punto de venta, pero el cuadro se pinta encima con
/// lo que hay que decidir: plan vencido, fecha real, el importe que calcula el
/// servidor y las dos unicas salidas (pagar por transferencia o mejorar de
/// plan). Detras no se puede operar porque la capa ocupa toda la pantalla.
///
/// Cuando hay una pantalla de **Planes** abierta (resumen, catalogo, pago o
/// historial) la capa se aparta, y **vuelve sola al salir**: lo avisa
/// `PlansShell` con `plansOpenCountProvider`, no una bandera de la navegacion.
///
/// Quien decide que la licencia vencio es el **servidor** (`license.access`);
/// aqui no se repite la regla ni se calculan importes. Mientras la licencia no
/// haya cargado no se tapa nada: un fallo de red no encierra al cliente.
class LicenseExpiryGate extends ConsumerWidget {
  const LicenseExpiryGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Al volver de Planes se vuelve a pedir la licencia: si el cliente acaba de
    // pagar, la cuenta se reactiva o pasa a «en revision» al instante.
    ref.listen<int>(plansOpenCountProvider, (previous, next) {
      if ((previous ?? 0) > 0 && next == 0) {
        ref.invalidate(licenseStatusProvider);
      }
    });
    final plansOpen = ref.watch(plansOpenCountProvider) > 0;
    return _layer(context, ref, covered: plansOpen);
  }

  Widget _layer(
    BuildContext context,
    WidgetRef ref, {
    required bool covered,
  }) {
    // Hay otra pantalla encima: el cuadro estorba.
    if (covered) return child;

    final scenario = ref.watch(licenseDemoScenarioProvider);
    final license = ref.watch(licenseStatusProvider).valueOrNull;
    final level = (license?.access?.level ?? '').toUpperCase();
    final blocked = level == 'BLOCKED';
    final trialEnded = license?.isTrialExpired ?? false;
    final expired = license?.isLicenseExpired ?? false;
    // Solo la demostracion puede apartar el cuadro para recorrer la app.
    final hidden =
        scenario.isOn && ref.watch(licenseDemoOverlayHiddenProvider);

    // Fuera de la demostracion, si la licencia esta al dia o aun no cargo, la
    // pantalla de trabajo se devuelve intacta: no se envuelve en nada.
    if (!blocked && !trialEnded && !expired && !scenario.isOn) return child;

    final renewal = license?.renewal;
    final access = license?.access;
    final periodEnd =
        access?.periodEndsAt ??
        license?.licenseExpiresAt ??
        license?.trialEndsAt ??
        renewal?.dueDate;
    final daysLeft = access?.daysRemaining ?? renewal?.daysLeft;
    final inReview = renewal?.isInReview == true;
    // «Falta de pago»: hay una cuota vencida o una cuota pendiente de pagar.
    // Si no, la suspension es por otra causa y solo se ofrece soporte.
    final owesMoney = renewal != null &&
        (renewal.isOverdue || renewal.isUpcoming);
    final showNotice = (blocked || trialEnded || expired) && !hidden;

    return Stack(
      children: [
        child,
        if (showNotice && blocked)
          Positioned.fill(
            child: LicenseSuspendedScreen(
              companyName: _company(license),
              owesMoney: owesMoney,
              amount: renewal?.amount,
              currency: renewal?.currency ?? 'DOP',
              blockedAt: license?.licenseBlockedAt,
              reasonLabel: license?.blockReason,
              onPay: () => context.push('${Routes.planesPago}?paso=pagar'),
              onSupport: () => _contactSupport(
                context,
                message:
                    'Hola, mi cuenta de FullPOS Cloud esta suspendida y necesito ayuda.',
              ),
            ),
          )
        // La demo terminada va **antes** que el plan vencido: las dos son
        // RESTRICTED, pero al cliente de la prueba no se le habla de un plan
        // que nunca eligio.
        else if (showNotice && trialEnded)
          Positioned.fill(
            child: LicenseTrialEndedScreen(
              companyName: _company(license),
              endedAt: license?.trialEndsAt ?? access?.periodEndsAt,
              trialDays: _trialDays(license),
              // Catalogo completo (sin `superiores=1`): el cliente de la demo
              // elige el plan que quiera, incluso el mas pequeno.
              onSeePlans: () => context.push(Routes.planesCatalogo),
              onSupport: () => _contactSupport(
                context,
                message:
                    'Hola, mi demo de FullPOS Cloud termino y necesito ayuda para elegir un plan.',
              ),
            ),
          )
        else if (showNotice && expired)
          Positioned.fill(
            child: LicenseExpiredScreen(
              companyName: _company(license),
              planName: _planName(license),
              expiredAt: periodEnd ?? DateTime.now(),
              daysExpired: daysLeft != null && daysLeft < 0 ? -daysLeft : null,
              amount: renewal?.amount,
              currency: renewal?.currency ?? 'DOP',
              pendingEvidenceReference:
                  inReview ? renewal?.order?.reference : null,
              pendingEvidenceStatus: inReview ? 'en revision' : null,
              // Misma navegacion que la pantalla de planes: no hay flujo nuevo
              // de pago, solo la pantalla unica de transferencia y el catalogo.
              onPay: () => context.push('${Routes.planesPago}?paso=pagar'),
              onUpgrade: () =>
                  context.push('${Routes.planesCatalogo}?superiores=1'),
            ),
          ),
        if (scenario.isOn && LicenseDemoScenario.showBar)
          Positioned(
            right: 16,
            bottom: 16,
            child: SafeArea(
              child: _DemoBar(
                scenario: scenario,
                overlayVisible: showNotice,
                onToggleOverlay: () {
                  ref.read(licenseDemoOverlayHiddenProvider.notifier).state =
                      !hidden;
                },
                onScenario: (next) {
                  ref.read(licenseDemoOverlayHiddenProvider.notifier).state =
                      false;
                  ref.read(licenseDemoScenarioProvider.notifier).state = next;
                },
              ),
            ),
          ),
      ],
    );
  }

  /// WhatsApp de soporte de FullPOS Cloud (el mismo numero que ya usa la app
  /// para comprar o renovar). No se inventa ningun canal nuevo.
  void _contactSupport(BuildContext context, {required String message}) {
    safeOpenUrl(
      context,
      Uri.https('wa.me', '/18295319442', {'text': message}),
      copiedMessage: 'Numero de soporte copiado.',
    );
  }

  /// Dias que duro la prueba, segun las fechas del servidor (7 por defecto).
  int _trialDays(LicenseStatusModel? license) {
    final start = license?.trialStartedAt;
    final end = license?.trialEndsAt;
    if (start == null || end == null) return 7;
    final days = (end.difference(start).inHours / 24).round();
    return days <= 0 ? 7 : days;
  }

  String _company(LicenseStatusModel? license) {
    final name = license?.companyName.trim() ?? '';
    return name.isEmpty ? 'Tu empresa' : name;
  }

  /// Nombre del plan para el titulo: el del catalogo que envia el servidor y,
  /// si no llego, el codigo. Nunca se imprime la etiqueta heredada «Plan X»
  /// (quedaria «Tu plan Plan basico vencio»).
  String _planName(LicenseStatusModel? license) {
    final fromServer = license?.renewal?.planName?.trim() ?? '';
    if (fromServer.isNotEmpty) return fromServer;
    final code = license?.planCode?.trim() ?? '';
    if (code.isNotEmpty) {
      return '${code[0].toUpperCase()}${code.substring(1).toLowerCase()}';
    }
    final label = (license?.planLabel ?? '').trim();
    final cleaned = label.replaceFirst(
      RegExp(r'^Plan\s+', caseSensitive: false),
      '',
    );
    return cleaned.isEmpty ? 'actual' : cleaned;
  }
}

/// Barra discreta de la **demostracion** de licencia.
///
/// Solo existe en desarrollo y solo cuando hay un escenario pedido: deja
/// cambiar de estado en caliente y apartar el cuadro para recorrer el resto de
/// pantallas reales con la licencia simulada. En release no se construye nunca.
class _DemoBar extends StatelessWidget {
  const _DemoBar({
    required this.scenario,
    required this.overlayVisible,
    required this.onToggleOverlay,
    required this.onScenario,
  });

  final LicenseDemoScenario scenario;
  final bool overlayVisible;
  final VoidCallback onToggleOverlay;
  final ValueChanged<LicenseDemoScenario> onScenario;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xF20F172A),
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.science_outlined,
              size: 13,
              color: Color(0xFF93C5FD),
            ),
            const SizedBox(width: 6),
            const Text(
              'DEMO',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w800,
                color: Color(0xFF93C5FD),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              scenario.label,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
            PopupMenuButton<LicenseDemoScenario>(
              tooltip: 'Cambiar licencia simulada',
              padding: EdgeInsets.zero,
              iconSize: 16,
              color: Colors.white,
              constraints: const BoxConstraints(minWidth: 230),
              onSelected: onScenario,
              itemBuilder: (context) => [
                for (final option in LicenseDemoScenario.values)
                  PopupMenuItem<LicenseDemoScenario>(
                    value: option,
                    child: Row(
                      children: [
                        Icon(
                          option == scenario
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 16,
                          color: option == scenario
                              ? const Color(0xFF1D4ED8)
                              : const Color(0xFF94A3B8),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            option.label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            TextButton(
              onPressed: onToggleOverlay,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: Text(
                overlayVisible ? 'Ver la app' : 'Volver al cuadro',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
