import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// **Simulacion local de una empresa con licencia vencida** (solo desarrollo).
///
/// No toca la base de datos, ni el servidor, ni la licencia de nadie: sustituye
/// la respuesta de `GET /license` por una empresa ficticia para poder recorrer
/// **todas las pantallas reales** en cada estado. Se enciende al arrancar:
///
/// ```powershell
/// flutter run -d windows --dart-define=LICENSE_DEMO_STATE=OVERDUE
/// ```
///
/// En un build de release `kDebugMode` es `false`, asi que el valor se ignora:
/// no existe ninguna forma de saltarse la licencia en lo que se publica.
enum LicenseDemoScenario {
  off('', 'Sin simular'),
  active('ACTIVE', 'Plan al dia'),
  trialEnded('TRIAL_EXPIRED', 'Demo de 7 dias terminada'),
  overdue('OVERDUE', 'Plan vencido'),
  inReview('IN_REVIEW', 'Comprobante en revision'),
  blocked('BLOCKED', 'Suspendida por falta de pago'),
  blockedOther('BLOCKED_OTHER', 'Suspendida por otra causa');

  const LicenseDemoScenario(this.raw, this.label);

  /// Valor que se acepta en `--dart-define=LICENSE_DEMO_STATE=...`.
  final String raw;

  /// Texto que se muestra en el selector de la barra de demostracion.
  final String label;

  bool get isOn => this != LicenseDemoScenario.off;

  static const String _env = String.fromEnvironment(
    'LICENSE_DEMO_STATE',
    defaultValue: '',
  );

  /// Escenario pedido al arrancar. En release siempre `off`.
  static LicenseDemoScenario get fromEnvironment =>
      kDebugMode ? fromRaw(_env) : LicenseDemoScenario.off;

  /// La barra flotante de la demostracion se puede quitar:
  ///
  ///   --dart-define=LICENSE_DEMO_STATE=TRIAL_EXPIRED \
  ///   --dart-define=LICENSE_DEMO_BAR=false
  ///
  /// Sirve para ensenar la demo (o tomar capturas) sin ninguna etiqueta
  /// encima del punto de venta. En release la barra no existe nunca.
  static const bool showBar = kDebugMode &&
      bool.fromEnvironment('LICENSE_DEMO_BAR', defaultValue: true);

  /// Acepta `OVERDUE` (y `VENCIDA`), `TRIAL_EXPIRED` (y `DEMO_FINALIZADA`),
  /// `IN_REVIEW`, `ACTIVE`, `BLOCKED` y `BLOCKED_OTHER`; lo demas es `off`.
  static LicenseDemoScenario fromRaw(String raw) {
    switch (raw.trim().toUpperCase()) {
      case 'ACTIVE':
        return LicenseDemoScenario.active;
      case 'TRIAL_EXPIRED':
      case 'TRIAL_ENDED':
      case 'DEMO_FINALIZADA':
      case 'DEMO_TERMINADA':
        return LicenseDemoScenario.trialEnded;
      case 'OVERDUE':
      case 'VENCIDA':
        return LicenseDemoScenario.overdue;
      case 'IN_REVIEW':
        return LicenseDemoScenario.inReview;
      case 'BLOCKED':
      case 'SUSPENDIDA':
        return LicenseDemoScenario.blocked;
      case 'BLOCKED_OTHER':
      case 'SUSPENDIDA_OTRA':
      case 'SUSPENDED_OTHER':
        return LicenseDemoScenario.blockedOther;
      default:
        return LicenseDemoScenario.off;
    }
  }
}

/// Escenario activo. Cambiarlo en caliente cambia la licencia que ve toda la
/// app (punto de venta incluido) sin recompilar y sin llamar al servidor.
final licenseDemoScenarioProvider = StateProvider<LicenseDemoScenario>(
  (ref) => LicenseDemoScenario.fromEnvironment,
);

/// `true` cuando en la demostracion se aparto el cuadro para poder navegar.
/// Nunca oculta nada fuera del modo demostracion.
final licenseDemoOverlayHiddenProvider = StateProvider<bool>((ref) => false);

/// Licencia ficticia con la **misma forma** que responde `GET /license`.
///
/// Se devuelve como JSON y no como modelo para que el camino que se ejercita
/// sea el real: `LicenseStatusModel.fromJson` sigue siendo el unico que
/// interpreta la licencia.
Map<String, dynamic> demoLicenseJson(LicenseDemoScenario scenario) {
  final now = DateTime.now();
  String at(int days) =>
      now.add(Duration(days: days)).toUtc().toIso8601String();

  final base = <String, dynamic>{
    'companyId': 'demo-company',
    'companyName': 'Comercial Demo SRL',
    'plan': 'ENTERPRISE',
    'planCode': 'empresa',
    'licenseType': 'ENTERPRISE',
    'licenseTypeLabel': 'Plan enterprise',
    'limits': {'maxUsers': 7, 'maxProducts': 5000, 'maxWarehouses': 10},
    'usage': {'users': 3, 'products': 320},
  };

  switch (scenario) {
    case LicenseDemoScenario.active:
      return {
        ...base,
        'status': 'ACTIVE',
        'isUsable': true,
        'periodStartedAt': at(-10),
        'licenseActivatedAt': at(-375),
        'licenseExpiresAt': at(20),
        'periodEndsAt': at(20),
        'daysRemaining': 20,
        'access': {
          'level': 'FULL',
          'reason': 'ACTIVE',
          'daysRemaining': 20,
          'periodEndsAt': at(20),
          'effectiveStatus': 'ACTIVE',
        },
        'renewal': {
          'state': 'CURRENT',
          'dueDate': at(20),
          'daysLeft': 20,
          'amount': 5000,
          'currency': 'DOP',
          'planCode': 'empresa',
          'planName': 'FullPOS Empresa',
          'windowDays': 10,
        },
      };
    case LicenseDemoScenario.inReview:
      return {
        ...base,
        'status': 'EXPIRED',
        'isUsable': false,
        'periodStartedAt': at(-37),
        'licenseActivatedAt': at(-402),
        'licenseExpiresAt': at(-7),
        'periodEndsAt': at(-7),
        'daysRemaining': -7,
        'access': {
          'level': 'RESTRICTED',
          'reason': 'EXPIRED',
          'daysRemaining': -7,
          'periodEndsAt': at(-7),
          'effectiveStatus': 'EXPIRED',
        },
        'renewal': {
          'state': 'IN_REVIEW',
          'dueDate': at(-7),
          'daysLeft': -7,
          'amount': 5000,
          'currency': 'DOP',
          'planCode': 'empresa',
          'planName': 'FullPOS Empresa',
          'windowDays': 10,
          'order': {
            'id': 'demo-order-1',
            'reference': 'FP-2026-000777',
            'amount': 5000,
            'currency': 'DOP',
            'status': 'UNCONFIRMED',
            'months': 1,
          },
        },
      };
    case LicenseDemoScenario.trialEnded:
      // Empresa de prueba que nunca paso a un plan: sin plan y sin deuda. El
      // servidor marca `TRIAL_EXPIRED` y deja el acceso en RESTRICTED.
      return {
        ...base,
        'plan': 'STANDARD',
        'planCode': null,
        'licenseType': 'TRIAL',
        'licenseTypeLabel': 'Plan demo',
        'limits': {'maxUsers': 2, 'maxProducts': 100, 'maxWarehouses': 1},
        'usage': {'users': 1, 'products': 37},
        'status': 'EXPIRED',
        'rawStatus': 'TRIAL',
        'isUsable': false,
        'trialStartedAt': at(-10),
        'trialEndsAt': at(-3),
        'licenseActivatedAt': null,
        'licenseExpiresAt': null,
        'periodStartedAt': at(-10),
        'periodEndsAt': at(-3),
        'daysRemaining': -3,
        'access': {
          'level': 'RESTRICTED',
          'reason': 'TRIAL_EXPIRED',
          'daysRemaining': -3,
          'periodEndsAt': at(-3),
          'effectiveStatus': 'EXPIRED',
        },
        'renewal': {
          'state': 'CURRENT',
          'dueDate': null,
          'daysLeft': null,
          'amount': null,
          'currency': 'DOP',
          'planCode': null,
          'planName': null,
          'windowDays': 10,
        },
      };
    case LicenseDemoScenario.overdue:
      return {
        ...base,
        'status': 'EXPIRED',
        'isUsable': false,
        'periodStartedAt': at(-37),
        'licenseActivatedAt': at(-402),
        'licenseExpiresAt': at(-7),
        'periodEndsAt': at(-7),
        'daysRemaining': -7,
        'access': {
          'level': 'RESTRICTED',
          'reason': 'EXPIRED',
          'daysRemaining': -7,
          'periodEndsAt': at(-7),
          'effectiveStatus': 'EXPIRED',
        },
        'renewal': {
          'state': 'OVERDUE',
          'dueDate': at(-7),
          'daysLeft': -7,
          'amount': 5000,
          'currency': 'DOP',
          'planCode': 'empresa',
          'planName': 'FullPOS Empresa',
          'windowDays': 10,
        },
      };
    case LicenseDemoScenario.blocked:
      return {
        ...base,
        'status': 'SUSPENDED',
        'isUsable': false,
        'licenseBlockedAt': at(-2),
        'blockReason': 'Falta de pago: la cuota vencio y no se recibio el comprobante.',
        'periodStartedAt': at(-37),
        'licenseExpiresAt': at(-7),
        'periodEndsAt': at(-7),
        'daysRemaining': -7,
        'access': {
          'level': 'BLOCKED',
          'reason': 'BLOCKED',
          'daysRemaining': -7,
          'periodEndsAt': at(-7),
          'effectiveStatus': 'BLOCKED',
        },
        'renewal': {
          'state': 'OVERDUE',
          'dueDate': at(-7),
          'daysLeft': -7,
          'amount': 5000,
          'currency': 'DOP',
          'planCode': 'empresa',
          'planName': 'FullPOS Empresa',
          'windowDays': 10,
        },
      };
    case LicenseDemoScenario.blockedOther:
      return {
        ...base,
        'status': 'SUSPENDED',
        'isUsable': false,
        'licenseBlockedAt': at(-3),
        'blockReason': 'Revision de la cuenta por un uso indebido del sistema.',
        'periodStartedAt': at(-12),
        'licenseExpiresAt': at(18),
        'periodEndsAt': at(18),
        'daysRemaining': 18,
        'access': {
          'level': 'BLOCKED',
          'reason': 'BLOCKED',
          'daysRemaining': 18,
          'periodEndsAt': at(18),
          'effectiveStatus': 'BLOCKED',
        },
        'renewal': {
          'state': 'CURRENT',
          'dueDate': at(18),
          'daysLeft': 18,
          'amount': 5000,
          'currency': 'DOP',
          'planCode': 'empresa',
          'planName': 'FullPOS Empresa',
          'windowDays': 10,
        },
      };
    case LicenseDemoScenario.off:
      break;
  }
  // Sin escenario no hay licencia simulada: quien llama debe usar el servidor.
  throw StateError('Sin escenario de demostracion no se fabrica una licencia.');
}
