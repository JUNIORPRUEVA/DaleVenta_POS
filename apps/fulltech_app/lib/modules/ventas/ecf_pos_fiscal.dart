import '../../features/ecf/ecf_models.dart';
import 'fiscal_voucher_options.dart' show normalizeTaxId;

/// Modo fiscal con el que se cierra una venta en el POS.
///
/// El motor NCF tradicional se retiró: no hay selector de talonarios B01/B02 en
/// ninguna empresa. Con e-CF activo se elige el comprobante (E31/E32 y, si la
/// empresa habilitó la excepción, «Normal»); sin e-CF la venta se registra sin
/// comprobante y el histórico conserva el NCF que ya tuviera.
///
/// Este archivo es **puro**: no lee estado, no hace red y no dibuja. Toda la
/// decisión de qué se ofrece y qué se preselecciona se toma con lo que recibe,
/// para poder probarla sin interfaz.
enum EcfPosFiscalMode {
  /// Factura de crédito fiscal: exige identificar al receptor (RNC + nombre).
  e31,

  /// Factura de consumo: consumidor final, sin identificar al receptor.
  e32,

  /// Venta sin comprobante. Solo aparece si la empresa habilitó la excepción.
  normal;

  String get code {
    switch (this) {
      case EcfPosFiscalMode.e31:
        return 'E31';
      case EcfPosFiscalMode.e32:
        return 'E32';
      case EcfPosFiscalMode.normal:
        return 'NORMAL';
    }
  }

  String get label {
    switch (this) {
      case EcfPosFiscalMode.e31:
        return 'E31 - Crédito fiscal';
      case EcfPosFiscalMode.e32:
        return 'E32 - Consumo';
      case EcfPosFiscalMode.normal:
        return 'Normal - sin comprobante electrónico';
    }
  }

  String get shortLabel {
    switch (this) {
      case EcfPosFiscalMode.e31:
        return 'E31';
      case EcfPosFiscalMode.e32:
        return 'E32';
      case EcfPosFiscalMode.normal:
        return 'Normal';
    }
  }

  /// `true` cuando el comprobante exige identificar al receptor.
  bool get requiresBuyer => this == EcfPosFiscalMode.e31;
}

EcfPosFiscalMode? ecfPosFiscalModeFromCode(String? code) {
  final normalized = (code ?? '').trim().toUpperCase();
  for (final mode in EcfPosFiscalMode.values) {
    if (mode.code == normalized) return mode;
  }
  return null;
}

/// Modos que se pueden ofrecer con estas capacidades.
///
/// Reglas:
///  * E31 y E32 solo si la empresa los tiene habilitados y el motor los puede
///    numerar. Sin rango asignable no se ofrece: ofrecerlo llevaría a un error
///    al cerrar la venta.
///  * E34 **nunca** se ofrece: una nota de crédito no es un comprobante de venta.
///  * «Normal» solo con la excepción habilitada por la empresa.
List<EcfPosFiscalMode> ecfPosFiscalModesFromCapabilities(
  EcfCapabilities? capabilities,
) {
  if (capabilities == null || !capabilities.enabled) return const [];
  final modes = <EcfPosFiscalMode>[];
  for (final mode in const [EcfPosFiscalMode.e31, EcfPosFiscalMode.e32]) {
    EcfDocumentTypeCapability? capability;
    for (final item in capabilities.documentTypes) {
      if (item.documentType == mode.code) {
        capability = item;
        break;
      }
    }
    // Sin entrada de capacidad no se asume que esté permitido.
    if (capability == null) continue;
    if (!capability.allowedForCompany || !capability.allocatable) continue;
    modes.add(mode);
  }
  if (capabilities.allowSalesWithoutEcf) modes.add(EcfPosFiscalMode.normal);
  return modes;
}

/// Opciones de cobro confirmadas por el servidor para la numeración actual.
/// Activar el módulo no basta para ofrecer un comprobante electrónico.
List<EcfPosFiscalMode> ecfPosCheckoutModesFromCapabilities(
  EcfCapabilities? capabilities,
) {
  return ecfPosFiscalModesFromCapabilities(capabilities).where((mode) {
    if (mode == EcfPosFiscalMode.normal) return true;
    return capabilities?.posReady == true &&
        capabilities!.posAvailableTypes.contains(mode.code);
  }).toList(growable: false);
}

/// ¿Hay datos suficientes para identificar al receptor de un E31?
///
/// Misma regla que aplica el servidor (`assertBuyerForDocumentType`): RNC o
/// cédula con al menos 9 dígitos **y** nombre o razón social. Se repite aquí, en
/// una función con nombre propio, porque el servidor la vuelve a validar y esta
/// copia solo sirve para avisar antes de cobrar.
bool ecfBuyerIdentityComplete(String? taxId, String? legalName) {
  final digits = normalizeTaxId(taxId);
  return digits.length >= 9 && (legalName ?? '').trim().isNotEmpty;
}

/// Preselección automática del comprobante.
///
/// **Decisión del propietario:** si la empresa habilitó «Permitir ventas
/// normales sin e-CF», la opción **Normal** es la preseleccionada en cada venta
/// nueva. Sigue sujeta a las reglas fiscales aplicables: el vendedor puede
/// cambiarla por E31/E32 y el servidor valida que la opción esté habilitada.
/// Normal se conserva como venta interna: no prepara ni envía un e-CF.
///
/// Con la excepción apagada, el comprobante se elige solo: con RNC/Cédula **y**
/// nombre toca E31 (crédito fiscal); sin esos datos toca E32 (consumo). Si E31 no
/// está disponible se usa E32, y al contrario. Si nada es posible devuelve `null`
/// y la venta no se cierra: preferimos no elegir antes que inventar un
/// comprobante.
EcfPosFiscalMode? defaultEcfPosFiscalMode({
  required List<EcfPosFiscalMode> available,
  required String? clientTaxId,
  required String? clientLegalName,
}) {
  if (available.isEmpty) return null;
  if (available.contains(EcfPosFiscalMode.normal)) {
    return EcfPosFiscalMode.normal;
  }
  final hasBuyer = ecfBuyerIdentityComplete(clientTaxId, clientLegalName);
  final wantsE31 = hasBuyer && available.contains(EcfPosFiscalMode.e31);
  if (wantsE31) return EcfPosFiscalMode.e31;
  if (available.contains(EcfPosFiscalMode.e32)) return EcfPosFiscalMode.e32;
  if (available.contains(EcfPosFiscalMode.e31)) return EcfPosFiscalMode.e31;
  return null;
}

/// Preselección para el POS, respetando lo que el vendedor ya decidió.
///
/// Recalcular al cambiar de cliente no puede pisar una elección manual: el
/// vendedor manda. Solo se propone cuando aún no eligió, o cuando lo que había
/// elegido dejó de estar disponible (por ejemplo, se perdió la numeración).
EcfPosFiscalMode? ecfResolvePreselection({
  required EcfPosFiscalMode? current,
  required bool chosenByUser,
  required List<EcfPosFiscalMode> available,
  required String? clientTaxId,
  required String? clientLegalName,
}) {
  if (chosenByUser && current != null && available.contains(current)) {
    return current;
  }
  return defaultEcfPosFiscalMode(
    available: available,
    clientTaxId: clientTaxId,
    clientLegalName: clientLegalName,
  );
}
