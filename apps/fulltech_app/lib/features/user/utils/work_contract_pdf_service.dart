import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../core/company/company_settings_model.dart';
import '../../../core/models/user_model.dart';

class WorkContractClause {
  final String key;
  final String label;
  final String title;
  final String text;

  const WorkContractClause({
    required this.key,
    required this.label,
    required this.title,
    required this.text,
  });
}

class WorkContractResolvedFields {
  final DateTime startDate;
  final String salaryText;
  final String position;
  final String paymentFrequency;
  final String paymentMethod;
  final String workSchedule;
  final String workLocation;
  final String currency;
  final String additionalClauses;

  const WorkContractResolvedFields({
    required this.startDate,
    required this.salaryText,
    required this.position,
    required this.paymentFrequency,
    required this.paymentMethod,
    required this.workSchedule,
    required this.workLocation,
    required this.currency,
    required this.additionalClauses,
  });

  Map<String, dynamic> toApiPayload(UserModel employee) {
    return {
      'workContractJobTitle': position,
      'workContractSalary': salaryText,
      'workContractPaymentFrequency': paymentFrequency,
      'workContractPaymentMethod': paymentMethod,
      'workContractWorkSchedule': workSchedule,
      'workContractWorkLocation': workLocation,
      'workContractClauseOverrides': employee.workContractClauseOverrides,
      'workContractCustomClauses': additionalClauses.isEmpty
          ? null
          : additionalClauses,
      'workContractStartDate': startDate.toIso8601String(),
    };
  }
}

const _spanishMonths = <String>[
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

String _fallbackText(
  String? value, {
  String fallback = '____________________________',
}) {
  final cleaned = (value ?? '').trim();
  return cleaned.isEmpty ? fallback : cleaned;
}

String _compactRoleLabel(String? raw) {
  final cleaned = (raw ?? '').trim();
  if (cleaned.isEmpty) return 'Colaborador';

  final normalized = cleaned.toLowerCase().replaceAll('_', ' ');
  final words = normalized.split(RegExp(r'\s+'));
  final formatted = words
      .where((word) => word.isNotEmpty)
      .map((word) {
        if (word.length == 1) return word.toUpperCase();
        final firstLetter = word.substring(0, 1).toUpperCase();
        final remainder = word.substring(1);
        return '$firstLetter$remainder';
      })
      .join(' ');
  return formatted.isEmpty ? 'Colaborador' : formatted;
}

String _formatDateShort(DateTime? date) {
  if (date == null) return 'No registrado';
  return DateFormat('dd/MM/yyyy').format(date);
}

String _salaryFrequencyLabel(String? periodicidadPago) {
  final normalized = (periodicidadPago ?? '').trim().toLowerCase();
  if (normalized.isEmpty) return 'mensual';
  return normalized;
}

String _normalizeParagraph(String? raw, {String fallback = ''}) {
  final cleaned = (raw ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned.isEmpty ? fallback : cleaned;
}

String _dateToSpanishLong(DateTime date) {
  final month = _spanishMonths[(date.month - 1).clamp(0, 11)];
  return 'día ${date.day} del mes de $month del año ${date.year}';
}

String _unitsToSpanish(int n) {
  switch (n) {
    case 0:
      return 'CERO';
    case 1:
      return 'UNO';
    case 2:
      return 'DOS';
    case 3:
      return 'TRES';
    case 4:
      return 'CUATRO';
    case 5:
      return 'CINCO';
    case 6:
      return 'SEIS';
    case 7:
      return 'SIETE';
    case 8:
      return 'OCHO';
    case 9:
      return 'NUEVE';
    case 10:
      return 'DIEZ';
    case 11:
      return 'ONCE';
    case 12:
      return 'DOCE';
    case 13:
      return 'TRECE';
    case 14:
      return 'CATORCE';
    case 15:
      return 'QUINCE';
    case 16:
      return 'DIECISEIS';
    case 17:
      return 'DIECISIETE';
    case 18:
      return 'DIECIOCHO';
    case 19:
      return 'DIECINUEVE';
    case 20:
      return 'VEINTE';
    case 21:
      return 'VEINTIUNO';
    case 22:
      return 'VEINTIDOS';
    case 23:
      return 'VEINTITRES';
    case 24:
      return 'VEINTICUATRO';
    case 25:
      return 'VEINTICINCO';
    case 26:
      return 'VEINTISEIS';
    case 27:
      return 'VEINTISIETE';
    case 28:
      return 'VEINTIOCHO';
    case 29:
      return 'VEINTINUEVE';
    default:
      return '';
  }
}

String _tensToSpanish(int n) {
  if (n < 30) return _unitsToSpanish(n);
  final tens = n ~/ 10;
  final unit = n % 10;
  String tensWord;
  switch (tens) {
    case 3:
      tensWord = 'TREINTA';
      break;
    case 4:
      tensWord = 'CUARENTA';
      break;
    case 5:
      tensWord = 'CINCUENTA';
      break;
    case 6:
      tensWord = 'SESENTA';
      break;
    case 7:
      tensWord = 'SETENTA';
      break;
    case 8:
      tensWord = 'OCHENTA';
      break;
    case 9:
      tensWord = 'NOVENTA';
      break;
    default:
      tensWord = '';
  }
  if (unit == 0) return tensWord;
  return '$tensWord Y ${_unitsToSpanish(unit)}';
}

String _hundredsToSpanish(int n) {
  if (n < 100) return _tensToSpanish(n);
  if (n == 100) return 'CIEN';
  final hundreds = n ~/ 100;
  final rest = n % 100;
  String hundredsWord;
  switch (hundreds) {
    case 1:
      hundredsWord = 'CIENTO';
      break;
    case 2:
      hundredsWord = 'DOSCIENTOS';
      break;
    case 3:
      hundredsWord = 'TRESCIENTOS';
      break;
    case 4:
      hundredsWord = 'CUATROCIENTOS';
      break;
    case 5:
      hundredsWord = 'QUINIENTOS';
      break;
    case 6:
      hundredsWord = 'SEISCIENTOS';
      break;
    case 7:
      hundredsWord = 'SETECIENTOS';
      break;
    case 8:
      hundredsWord = 'OCHOCIENTOS';
      break;
    case 9:
      hundredsWord = 'NOVECIENTOS';
      break;
    default:
      hundredsWord = '';
  }
  if (rest == 0) return hundredsWord;
  return '$hundredsWord ${_tensToSpanish(rest)}';
}

String _numberToSpanishWords(int n) {
  if (n < 0) return '';
  if (n < 1000) return _hundredsToSpanish(n);
  if (n < 1000000) {
    final thousands = n ~/ 1000;
    final rest = n % 1000;
    final thousandsWord = thousands == 1
        ? 'MIL'
        : '${_hundredsToSpanish(thousands)} MIL';
    if (rest == 0) return thousandsWord;
    return '$thousandsWord ${_hundredsToSpanish(rest)}';
  }
  // Out of supported range for now.
  return '';
}

String _salaryToContractText(String salario) {
  // If salary is already a formatted string from upstream, try to extract
  // numeric value. Otherwise, fallback to the provided string.
  final numeric = salario.replaceAll(RegExp(r'[^0-9.,]'), '');
  final normalized = numeric.replaceAll(',', '');
  final value = double.tryParse(normalized);
  if (value == null) return salario.trim();

  final pesos = value.floor();
  final cents = ((value - pesos) * 100).round().clamp(0, 99);
  final words = _numberToSpanishWords(pesos);
  final centsText = cents.toString().padLeft(2, '0');
  final fmt = NumberFormat.currency(symbol: 'RS\$', decimalDigits: 2);
  return '${words.isEmpty ? '________________' : words} PESOS DOMINICANOS CON $centsText/100 (${fmt.format(value)})';
}

String _resolveClauseOverride(UserModel employee, String key, String fallback) {
  final override = (employee.workContractClauseOverrides[key] ?? '').trim();
  return override.isEmpty ? fallback : override;
}

WorkContractResolvedFields resolveWorkContractFields({
  required UserModel employee,
  CompanySettings? company,
  String? lugar,
  DateTime? fechaInicio,
  String? salario,
  String? moneda,
  String? periodicidadPago,
  String? metodoPago,
  String? puesto,
}) {
  final today = DateTime.now();
  final companyAddress = _fallbackText(company?.address);
  final startDate =
      fechaInicio ??
      employee.workContractStartDate ??
      employee.fechaIngreso ??
      today;
  final salarioRaw = (salario ?? employee.workContractSalary ?? '').trim();
  final salarioText = salarioRaw.isNotEmpty
      ? _salaryToContractText(salarioRaw)
      : '____________________________';
  final position = _fallbackText(
    puesto ?? employee.workContractJobTitle,
    fallback: _compactRoleLabel(employee.role),
  );
  final paymentFrequency = _fallbackText(
    periodicidadPago ?? employee.workContractPaymentFrequency,
    fallback: 'Mensual',
  );
  final paymentMethod = _fallbackText(
    metodoPago ?? employee.workContractPaymentMethod,
    fallback: 'Transferencia bancaria',
  );
  final currency = _fallbackText(moneda, fallback: 'DOP');
  final workSchedule = _normalizeParagraph(
    employee.workContractWorkSchedule,
    fallback:
        'de 9:00 a.m. a 6:00 p.m., con una hora de almuerzo de 1:00 p.m. a 2:00 p.m., de lunes a domingo, con un dia libre semanal',
  );
  final workLocation = _normalizeParagraph(
    employee.workContractWorkLocation ?? lugar ?? company?.address,
    fallback: companyAddress,
  );
  final additionalClauses = _normalizeParagraph(
    employee.workContractCustomClauses,
  );

  return WorkContractResolvedFields(
    startDate: startDate,
    salaryText: salarioText,
    position: position,
    paymentFrequency: paymentFrequency,
    paymentMethod: paymentMethod,
    workSchedule: workSchedule,
    workLocation: workLocation,
    currency: currency,
    additionalClauses: additionalClauses,
  );
}

List<WorkContractClause> buildWorkContractClauses({
  required UserModel employee,
  CompanySettings? company,
  String? lugar,
  DateTime? fechaInicio,
  String? salario,
  String? moneda,
  String? periodicidadPago,
  String? metodoPago,
  String? puesto,
}) {
  final draft = resolveWorkContractFields(
    employee: employee,
    company: company,
    lugar: lugar,
    fechaInicio: fechaInicio,
    salario: salario,
    moneda: moneda,
    periodicidadPago: periodicidadPago,
    metodoPago: metodoPago,
    puesto: puesto,
  );

  final firstText =
      'EL EMPLEADOR contrata los servicios personales de EL EMPLEADO para desempenarse en el cargo de ${draft.position}, prestando sus servicios en ${draft.workLocation}, en el horario ${draft.workSchedule}, obligandose EL EMPLEADO a ejecutar sus funciones con diligencia, lealtad y apego a las instrucciones razonables de EL EMPLEADOR. Por dichos servicios, EL EMPLEADO devengara un salario ${_salaryFrequencyLabel(draft.paymentFrequency)} en moneda ${draft.currency} ascendente a ${draft.salaryText}, pagadero mediante ${draft.paymentMethod}.';
  final secondText =
      'El presente contrato es por tiempo indefinido y surtira efecto a partir del ${_dateToSpanishLong(draft.startDate)}, fecha desde la cual EL EMPLEADO queda formalmente incorporado a las labores de EL EMPLEADOR.';
  final thirdText =
      'EL EMPLEADOR garantizara a EL EMPLEADO la afiliacion correspondiente al sistema de seguridad social y los beneficios laborales reconocidos por el Codigo de Trabajo de la Republica Dominicana, siempre conforme a los requisitos y plazos establecidos por la ley.';
  final thirdParagraphText =
      'Durante el periodo inicial de la relacion laboral, los beneficios adicionales o complementarios otorgados por EL EMPLEADOR podran estar sujetos a politicas internas, sin perjuicio de los derechos minimos irrenunciables consagrados en la legislacion laboral dominicana.';
  final fourthText =
      'EL EMPLEADO se compromete a cumplir la jornada, reglamentos internos, medidas de seguridad, politicas de asistencia y demas instrucciones de servicio establecidas por EL EMPLEADOR. Cualquier variacion razonable de horario, turnos o funciones conexas sera comunicada oportunamente, conforme a la necesidad operativa de la empresa y dentro de los limites de la ley.';
  final fifthText =
      'EL EMPLEADO se obliga a asistir puntualmente a sus labores, participar en reuniones, capacitaciones, eventos y actividades relacionadas con sus funciones cuando sea requerido, asi como mantener una conducta respetuosa, profesional y alineada con los intereses legitimos de EL EMPLEADOR.';
  final sixthText =
      'EL EMPLEADO tendra derecho al descanso semanal, vacaciones, salario de navidad y demas prestaciones y derechos que le correspondan conforme al tiempo laborado y a las disposiciones vigentes del Codigo de Trabajo de la Republica Dominicana.';
  final seventhText =
      'EL EMPLEADO guardara reserva sobre la informacion comercial, operativa, administrativa y tecnica a la que tenga acceso con motivo de sus funciones, y utilizara adecuadamente los equipos, materiales, documentos, sistemas y recursos puestos a su disposicion por EL EMPLEADOR.';
  final eighthText =
      'EL EMPLEADO desempenara sus funciones principalmente en ${draft.workLocation}, sin perjuicio de traslados, visitas, actividades externas, soporte, reuniones o asignaciones compatibles con la naturaleza de su cargo cuando las necesidades del servicio asi lo requieran.';
  final ninthText =
      'El incumplimiento de las obligaciones asumidas por EL EMPLEADO, asi como cualquiera de las causas previstas en el Codigo de Trabajo de la Republica Dominicana, podra dar lugar a la suspension o terminacion de la relacion laboral con las consecuencias legales correspondientes.';
  final tenthText =
      'El presente documento deja sin efecto cualquier acuerdo verbal o escrito anterior relativo al mismo objeto, salvo aquellos derechos ya adquiridos por EL EMPLEADO conforme a la ley.';
  final eleventhText =
      'Para todo lo no previsto expresamente en este contrato, las partes se remiten al Codigo de Trabajo de la Republica Dominicana, sus reglamentos complementarios y al derecho comun en caracter supletorio.';

  return [
    WorkContractClause(
      key: 'first',
      label: 'PRIMERO:',
      title: 'Objeto del Contrato',
      text: _resolveClauseOverride(employee, 'first', firstText),
    ),
    WorkContractClause(
      key: 'second',
      label: 'SEGUNDO:',
      title: 'Duracion del Contrato',
      text: _resolveClauseOverride(employee, 'second', secondText),
    ),
    WorkContractClause(
      key: 'third',
      label: 'TERCERO:',
      title: 'Beneficios y Seguridad Social',
      text: _resolveClauseOverride(employee, 'third', thirdText),
    ),
    WorkContractClause(
      key: 'third_paragraph_1',
      label: 'PARRAFO I:',
      title: 'Beneficios adicionales',
      text: _resolveClauseOverride(
        employee,
        'third_paragraph_1',
        thirdParagraphText,
      ),
    ),
    WorkContractClause(
      key: 'fourth',
      label: 'CUARTO:',
      title: 'Jornada y Disciplina',
      text: _resolveClauseOverride(employee, 'fourth', fourthText),
    ),
    WorkContractClause(
      key: 'fifth',
      label: 'QUINTO:',
      title: 'Obligaciones Generales',
      text: _resolveClauseOverride(employee, 'fifth', fifthText),
    ),
    WorkContractClause(
      key: 'sixth',
      label: 'SEXTO:',
      title: 'Descanso y Vacaciones',
      text: _resolveClauseOverride(employee, 'sixth', sixthText),
    ),
    WorkContractClause(
      key: 'seventh',
      label: 'SEPTIMO:',
      title: 'Confidencialidad y Buen Uso',
      text: _resolveClauseOverride(employee, 'seventh', seventhText),
    ),
    WorkContractClause(
      key: 'eighth',
      label: 'OCTAVO:',
      title: 'Lugar de Prestacion',
      text: _resolveClauseOverride(employee, 'eighth', eighthText),
    ),
    WorkContractClause(
      key: 'ninth',
      label: 'NOVENO:',
      title: 'Terminacion',
      text: _resolveClauseOverride(employee, 'ninth', ninthText),
    ),
    WorkContractClause(
      key: 'tenth',
      label: 'DECIMO:',
      title: 'Integridad del Contrato',
      text: _resolveClauseOverride(employee, 'tenth', tenthText),
    ),
    WorkContractClause(
      key: 'eleventh',
      label: 'DECIMO PRIMERO:',
      title: 'Ley Aplicable',
      text: _resolveClauseOverride(employee, 'eleventh', eleventhText),
    ),
  ];
}

Future<Uint8List> buildWorkContractPdf({
  required UserModel employee,
  CompanySettings? company,
  String? lugar,
  DateTime? fechaInicio,
  String? salario,
  String? moneda,
  String? periodicidadPago,
  String? metodoPago,
  String? puesto,
}) async {
  final today = DateTime.now();

  final companyName = _fallbackText(
    company?.companyName,
    fallback: 'FULLTECH, SRL',
  );
  final employerRncLine = _fallbackText(company?.rnc);
  final representativeName = _fallbackText(company?.legalRepresentativeName);
  final representativeNationality = _fallbackText(
    company?.legalRepresentativeNationality,
  );
  final representativeCivil = _fallbackText(
    company?.legalRepresentativeCivilStatus,
  );
  final representativeCedula = _fallbackText(
    company?.legalRepresentativeCedula,
  );
  final representativeRole = _fallbackText(company?.legalRepresentativeRole);
  final companyAddress = _fallbackText(company?.address);
  final companyPhone = _fallbackText(company?.phone, fallback: 'No registrado');
  final signingPlace = _fallbackText(
    lugar ?? company?.address,
    fallback: companyAddress,
  );

  final nombreEmpleado = employee.nombreCompleto.trim().isNotEmpty
      ? employee.nombreCompleto.trim()
      : '____________________________';
  final cedulaEmpleado = (employee.cedula ?? '').trim().isNotEmpty
      ? employee.cedula!.trim()
      : '____________________________';

  final draft = resolveWorkContractFields(
    employee: employee,
    company: company,
    lugar: lugar,
    fechaInicio: fechaInicio,
    salario: salario,
    moneda: moneda,
    periodicidadPago: periodicidadPago,
    metodoPago: metodoPago,
    puesto: puesto,
  );
  final clauses = buildWorkContractClauses(
    employee: employee,
    company: company,
    lugar: lugar,
    fechaInicio: fechaInicio,
    salario: salario,
    moneda: moneda,
    periodicidadPago: periodicidadPago,
    metodoPago: metodoPago,
    puesto: puesto,
  );

  final doc = pw.Document(title: 'Contrato de trabajo', author: companyName);

  pw.Widget spacedText(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.justify,
        style: const pw.TextStyle(fontSize: 12, height: 1.4),
      ),
    );
  }

  pw.Widget richLabel(String label, String rest) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.RichText(
        text: pw.TextSpan(
          style: const pw.TextStyle(fontSize: 11, height: 1.25),
          children: [
            pw.TextSpan(
              text: label,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
            pw.TextSpan(text: rest),
          ],
        ),
        textAlign: pw.TextAlign.justify,
      ),
    );
  }

  pw.Widget centeredTitle(String text) {
    return pw.Center(
      child: pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Text(
          text,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  pw.Widget signatureBlock(String leftLabel, String rightLabel) {
    return pw.Column(
      children: [
        pw.SizedBox(height: 18),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Container(height: 1, color: PdfColors.black),
                  pw.SizedBox(height: 4),
                  pw.Text(leftLabel, style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
            pw.SizedBox(width: 28),
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Container(height: 1, color: PdfColors.black),
                  pw.SizedBox(height: 4),
                  pw.Text(rightLabel, style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(22, 22, 22, 26),
      build: (context) => [
        pw.Text(
          companyName,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.Center(
          child: pw.Text(
            'RNC: $employerRncLine',
            style: const pw.TextStyle(fontSize: 11),
          ),
        ),
        pw.SizedBox(height: 10),
        centeredTitle('C O N T R A T O   D E    T R A B A J O'),
        pw.SizedBox(height: 12),
        spacedText(
          'En la ciudad de Higuey, provincia La Altagracia, Republica Dominicana, a los ${_dateToSpanishLong(today)}, se suscribe el presente contrato individual de trabajo entre, de una parte, $companyName, sociedad comercial organizada conforme a las leyes de la Republica Dominicana, inscrita en el Registro Nacional de Contribuyentes bajo el No. $employerRncLine, con domicilio social en $companyAddress, telefono $companyPhone, debidamente representada por $representativeName, de nacionalidad $representativeNationality, mayor de edad, de estado civil $representativeCivil, titular de la cedula de identidad y electoral No. $representativeCedula, quien actua en su calidad de $representativeRole, y que en lo adelante se denominara EL EMPLEADOR; y de la otra parte, $nombreEmpleado, de nacionalidad dominicana, mayor de edad, titular de la cedula de identidad y electoral No. $cedulaEmpleado, telefono ${_fallbackText(employee.telefono, fallback: 'no registrado')}, correo electronico ${_fallbackText(employee.email, fallback: 'no registrado')}, fecha de nacimiento ${_formatDateShort(employee.fechaNacimiento)}, fecha de ingreso ${_formatDateShort(draft.startDate)}, cuenta de nomina ${_fallbackText(employee.cuentaNominaPreferencial, fallback: 'no registrada')}, quien en lo adelante se denominara EL EMPLEADO.',
        ),
        spacedText(
          'Las partes, libre y voluntariamente, convienen en celebrar el presente contrato de trabajo por tiempo indefinido, de conformidad con las disposiciones del Codigo de Trabajo de la Republica Dominicana, sujeto a las clausulas que se indican a continuacion:',
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'HAN CONVENIDO LO SIGUIENTE:',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 12),

        ...clauses.map(
          (clause) => clause.label == 'PARRAFO I:'
              ? spacedText('${clause.label} ${clause.text}')
              : richLabel(
                  '${clause.label} ',
                  '${clause.title}: ${clause.text}',
                ),
        ),

        if (draft.additionalClauses.isNotEmpty)
          richLabel(
            'DECIMO SEGUNDO: ',
            'Clausulas Especiales: ${draft.additionalClauses}',
          ),

        pw.SizedBox(height: 14),
        spacedText(
          'Leido que fue el presente contrato y encontrandolo conforme con su voluntad, las partes lo firman en dos originales de un mismo tenor y efecto, en $signingPlace, a los ${_dateToSpanishLong(today)}.',
        ),

        signatureBlock('POR EL EMPLEADOR:', 'POR EL EMPLEADO:'),
        pw.SizedBox(height: 14),

        pw.SizedBox(height: 16),
        pw.Text(
          'CERTIFICACION DE FIRMAS',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 10),
        spacedText(
          'Yo, ANATACIO GUERRERO, Abogado Notario Público de los del Número de los del municipio Higüey de la provincia La Altagracia con Colegiatura del Colegio de Notarios de la República Dominicana Número 7065, CERTIFICO Y DOY FE: Que las firmas que anteceden en el presente documento, fueron puestas y escritas en mi presencia por los SEÑORES: x,x,x,x,x,x Y x,x,x,x,x,x,x,x de generales que constan la cual me han manifestado bajo fe del juramento que con esas firmas es con la que ellos acostumbran a usar en todos los actos de su vida pública y privada.  En la Calle Dionicio Arturo Troncoso N°16 Esq. Gaspar Hernández de la Ciudad de Higüey, provincia La Altagracia, República Dominicana, a los QUINCE (15) días del mes de Enero del año Dos mil Veinte y Dos (2022). DE TODO LO QUE CERTIFICO Y DOY FE-',
        ),
        pw.SizedBox(height: 18),
        pw.Container(height: 1, color: PdfColors.black),
        pw.SizedBox(height: 6),
        pw.Text(
          'DR. ANATACIO GUERRERO\nAbogado Notario Público',
          style: const pw.TextStyle(fontSize: 10),
        ),
      ],
    ),
  );

  return doc.save();
}

Future<void> shareWorkContractPdf({
  required Uint8List bytes,
  required UserModel employee,
}) async {
  final safeName = employee.nombreCompleto.trim().isEmpty
      ? 'empleado'
      : employee.nombreCompleto.trim().replaceAll(RegExp(r'\s+'), '_');
  final dateFmt = DateFormat('yyyyMMdd');
  final fileName = 'contrato_${safeName}_${dateFmt.format(DateTime.now())}.pdf';
  await Printing.sharePdf(bytes: bytes, filename: fileName);
}
