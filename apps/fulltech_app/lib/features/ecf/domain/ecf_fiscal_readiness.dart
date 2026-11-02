import '../../../core/company/company_settings_model.dart';

/// Exigencia de cada dato fiscal para poder emitir un comprobante.
///
/// `blocking` reproduce literalmente la comprobación del backend
/// (`assertIssuerComplete` en `apps/api/src/ecf/pos/ecf-sale-fiscal.policy.ts`):
/// sin nombre, RNC y dirección la emisión se rechaza con
/// `ECF_ISSUER_DATA_INCOMPLETE`. Además, esos tres campos son los que la venta
/// congela en `issuerNameSnapshot` / `issuerTaxIdSnapshot` /
/// `issuerAddressSnapshot`, y los que el esquema del proveedor marca como
/// obligatorios en `sender`.
///
/// `recommended` son datos que también viajan en el comprobante o que la DGII
/// pide durante la postulación, pero que hoy no bloquean la emisión. Se marcan
/// como recomendados y no como obligatorios para no inventar bloqueos que el
/// sistema no aplica.
enum EcfFiscalRequirement { blocking, recommended }

/// Un dato fiscal de la empresa con su estado real, sin valores simulados.
class EcfFiscalItem {
  const EcfFiscalItem({
    required this.key,
    required this.label,
    required this.value,
    required this.requirement,
    required this.ok,
    required this.hint,
  });

  /// Identificador estable (clave del campo), útil para pruebas y para las
  /// claves de los widgets del formulario.
  final String key;
  final String label;

  /// Valor tal como está guardado o se está editando.
  final String value;
  final EcfFiscalRequirement requirement;
  final bool ok;

  /// Qué se espera del dato, en lenguaje del negocio.
  final String hint;

  bool get blocking => requirement == EcfFiscalRequirement.blocking;
}

/// Deja solo dígitos: el RNC y el teléfono se guardan con o sin guiones y
/// espacios, y eso no debe cambiar el resultado de la validación.
String ecfDigitsOnly(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

/// RNC dominicano (9 dígitos) o cédula (11). El esquema del proveedor limita el
/// campo `sender.rnc` a 11 caracteres, así que nada fuera de eso puede viajar.
bool isEcfTaxIdValid(String value) {
  final digits = ecfDigitsOnly(value);
  return digits.length == 9 || digits.length == 11;
}

/// Los números de RD tienen 10 dígitos (809/829/849 + 7). Se exige al menos esa
/// longitud porque el teléfono se imprime en el comprobante.
bool isEcfPhoneValid(String value) => ecfDigitsOnly(value).length >= 10;

bool isEcfCedulaValid(String value) {
  final digits = ecfDigitsOnly(value);
  return digits.length == 9 || digits.length == 11;
}

/// Construye la lista de comprobaciones a partir de una configuración, guardada
/// o en edición. Una sola fuente para el formulario fiscal y para la guía de
/// puesta en marcha.
List<EcfFiscalItem> buildEcfFiscalItems(CompanySettings settings) {
  final name = settings.companyName.trim();
  final rnc = settings.rnc.trim();
  final address = settings.address.trim();
  final phone = settings.phone.trim();
  final legalName = settings.legalRepresentativeName.trim();
  final legalCedula = settings.legalRepresentativeCedula.trim();

  return [
    EcfFiscalItem(
      key: 'companyName',
      label: 'Nombre o razón social',
      value: name,
      requirement: EcfFiscalRequirement.blocking,
      ok: name.isNotEmpty,
      hint: 'Es el nombre que sale impreso como emisor. Debe coincidir con el '
          'registrado en la DGII.',
    ),
    EcfFiscalItem(
      key: 'rnc',
      label: 'RNC',
      value: rnc,
      requirement: EcfFiscalRequirement.blocking,
      ok: isEcfTaxIdValid(rnc),
      hint: '9 dígitos para RNC u 11 para cédula. Se aceptan guiones.',
    ),
    EcfFiscalItem(
      key: 'address',
      label: 'Dirección fiscal',
      value: address,
      requirement: EcfFiscalRequirement.blocking,
      ok: address.isNotEmpty,
      hint: 'Calle, número, sector y municipio, como figura en el registro.',
    ),
    EcfFiscalItem(
      key: 'phone',
      label: 'Teléfono',
      value: phone,
      requirement: EcfFiscalRequirement.recommended,
      ok: isEcfPhoneValid(phone),
      hint: 'Al menos 10 dígitos. Aparece en la representación impresa.',
    ),
    EcfFiscalItem(
      key: 'legalRepresentativeName',
      label: 'Representante legal',
      value: legalName,
      requirement: EcfFiscalRequirement.recommended,
      ok: legalName.isNotEmpty,
      hint: 'Lo solicita la DGII durante la postulación de la empresa.',
    ),
    EcfFiscalItem(
      key: 'legalRepresentativeCedula',
      label: 'Cédula del representante',
      value: legalCedula,
      requirement: EcfFiscalRequirement.recommended,
      ok: isEcfCedulaValid(legalCedula),
      hint: '11 dígitos, o 9 si está registrado con RNC.',
    ),
  ];
}

/// Cuántos datos que el backend exige siguen sin cumplirse.
int ecfBlockingMissingCount(CompanySettings settings) => buildEcfFiscalItems(
  settings,
).where((item) => item.blocking && !item.ok).length;

/// Cuántos datos recomendados siguen sin cumplirse.
int ecfRecommendedMissingCount(CompanySettings settings) =>
    buildEcfFiscalItems(
      settings,
    ).where((item) => !item.blocking && !item.ok).length;

/// `true` cuando la empresa ya puede emitir sin `ECF_ISSUER_DATA_INCOMPLETE`.
bool ecfIssuerDataReady(CompanySettings settings) =>
    ecfBlockingMissingCount(settings) == 0;
