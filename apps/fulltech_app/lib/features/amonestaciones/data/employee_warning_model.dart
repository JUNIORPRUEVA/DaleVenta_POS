// ignore_for_file: non_constant_identifier_names

class EmployeeWarning {
  final String id;
  final String companyId;
  final String employeeUserId;
  final String createdByUserId;
  final String warningNumber;
  final DateTime warningDate;
  final DateTime incidentDate;
  final String title;
  final String? warningType;
  final String? reason;
  final String? details;
  final String? incidentTime;
  final String? incidentPlace;
  final String? issuedByUserId;
  final String? issuedByNameSnapshot;
  final String? issuedByPositionSnapshot;
  final String? internalNotes;
  final String? generatedText;
  final String? employeeNameSnapshot;
  final String? employeeCedulaSnapshot;
  final String? employeePositionSnapshot;
  final String? employeeDepartmentSnapshot;
  final String? employeePhoneSnapshot;
  final String? companyNameSnapshot;
  final String? companyRncSnapshot;
  final String? companyAddressSnapshot;
  final String category;
  final String severity;
  final String? legalBasis;
  final String? internalRuleReference;
  final String description;
  final String? employeeExplanation;
  final String? correctiveAction;
  final String? consequenceNote;
  final String? evidenceNotes;
  final String status;
  final String? pdfUrl;
  final String? signedPdfUrl;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? submittedAt;
  final DateTime? signedAt;
  final DateTime? refusedAt;
  final DateTime? annulledAt;
  final String? annulledByUserId;
  final String? annulmentReason;
  final EmployeeWarningUser? employeeUser;
  final EmployeeWarningUser? createdByUser;
  final EmployeeWarningUser? annulledByUser;
  final List<EmployeeWarningEvidence> evidences;
  final List<EmployeeWarningSignature> signatures;
  final List<EmployeeWarningAuditLog> auditLogs;

  const EmployeeWarning({
    required this.id,
    required this.companyId,
    required this.employeeUserId,
    required this.createdByUserId,
    required this.warningNumber,
    required this.warningDate,
    required this.incidentDate,
    required this.title,
    this.warningType,
    this.reason,
    this.details,
    this.incidentTime,
    this.incidentPlace,
    this.issuedByUserId,
    this.issuedByNameSnapshot,
    this.issuedByPositionSnapshot,
    this.internalNotes,
    this.generatedText,
    this.employeeNameSnapshot,
    this.employeeCedulaSnapshot,
    this.employeePositionSnapshot,
    this.employeeDepartmentSnapshot,
    this.employeePhoneSnapshot,
    this.companyNameSnapshot,
    this.companyRncSnapshot,
    this.companyAddressSnapshot,
    required this.category,
    required this.severity,
    this.legalBasis,
    this.internalRuleReference,
    required this.description,
    this.employeeExplanation,
    this.correctiveAction,
    this.consequenceNote,
    this.evidenceNotes,
    required this.status,
    this.pdfUrl,
    this.signedPdfUrl,
    required this.createdAt,
    required this.updatedAt,
    this.submittedAt,
    this.signedAt,
    this.refusedAt,
    this.annulledAt,
    this.annulledByUserId,
    this.annulmentReason,
    this.employeeUser,
    this.createdByUser,
    this.annulledByUser,
    this.evidences = const [],
    this.signatures = const [],
    this.auditLogs = const [],
  });

  factory EmployeeWarning.fromJson(Map<String, dynamic> j) => EmployeeWarning(
    id: j['id'] as String,
    companyId: j['companyId'] as String,
    employeeUserId: j['employeeUserId'] as String,
    createdByUserId: j['createdByUserId'] as String,
    warningNumber: j['warningNumber'] as String,
    warningDate: DateTime.parse(j['warningDate'] as String),
    incidentDate: DateTime.parse(j['incidentDate'] as String),
    title: j['title'] as String,
    warningType: j['warningType'] as String?,
    reason: j['reason'] as String?,
    details: j['details'] as String?,
    incidentTime: j['incidentTime'] as String?,
    incidentPlace: j['incidentPlace'] as String?,
    issuedByUserId: j['issuedByUserId'] as String?,
    issuedByNameSnapshot: j['issuedByNameSnapshot'] as String?,
    issuedByPositionSnapshot: j['issuedByPositionSnapshot'] as String?,
    internalNotes: j['internalNotes'] as String?,
    generatedText: j['generatedText'] as String?,
    employeeNameSnapshot: j['employeeNameSnapshot'] as String?,
    employeeCedulaSnapshot: j['employeeCedulaSnapshot'] as String?,
    employeePositionSnapshot: j['employeePositionSnapshot'] as String?,
    employeeDepartmentSnapshot: j['employeeDepartmentSnapshot'] as String?,
    employeePhoneSnapshot: j['employeePhoneSnapshot'] as String?,
    companyNameSnapshot: j['companyNameSnapshot'] as String?,
    companyRncSnapshot: j['companyRncSnapshot'] as String?,
    companyAddressSnapshot: j['companyAddressSnapshot'] as String?,
    category: j['category'] as String,
    severity: j['severity'] as String,
    legalBasis: j['legalBasis'] as String?,
    internalRuleReference: j['internalRuleReference'] as String?,
    description: j['description'] as String,
    employeeExplanation: j['employeeExplanation'] as String?,
    correctiveAction: j['correctiveAction'] as String?,
    consequenceNote: j['consequenceNote'] as String?,
    evidenceNotes: j['evidenceNotes'] as String?,
    status: j['status'] as String,
    pdfUrl: j['pdfUrl'] as String?,
    signedPdfUrl: j['signedPdfUrl'] as String?,
    createdAt: DateTime.parse(j['createdAt'] as String),
    updatedAt: DateTime.parse(j['updatedAt'] as String),
    submittedAt: j['submittedAt'] != null
        ? DateTime.parse(j['submittedAt'] as String)
        : null,
    signedAt: j['signedAt'] != null
        ? DateTime.parse(j['signedAt'] as String)
        : null,
    refusedAt: j['refusedAt'] != null
        ? DateTime.parse(j['refusedAt'] as String)
        : null,
    annulledAt: j['annulledAt'] != null
        ? DateTime.parse(j['annulledAt'] as String)
        : null,
    annulledByUserId: j['annulledByUserId'] as String?,
    annulmentReason: j['annulmentReason'] as String?,
    employeeUser: j['employeeUser'] != null
        ? EmployeeWarningUser.fromJson(
            j['employeeUser'] as Map<String, dynamic>,
          )
        : null,
    createdByUser: j['createdByUser'] != null
        ? EmployeeWarningUser.fromJson(
            j['createdByUser'] as Map<String, dynamic>,
          )
        : null,
    annulledByUser: j['annulledByUser'] != null
        ? EmployeeWarningUser.fromJson(
            j['annulledByUser'] as Map<String, dynamic>,
          )
        : null,
    evidences: (j['evidences'] as List<dynamic>? ?? [])
        .map((e) => EmployeeWarningEvidence.fromJson(e as Map<String, dynamic>))
        .toList(),
    signatures: (j['signatures'] as List<dynamic>? ?? [])
        .map(
          (e) => EmployeeWarningSignature.fromJson(e as Map<String, dynamic>),
        )
        .toList(),
    auditLogs: (j['auditLogs'] as List<dynamic>? ?? [])
        .map((e) => EmployeeWarningAuditLog.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class EmployeeWarningUser {
  final String id;
  final String nombreCompleto;
  final String? email;
  final String? telefono;
  final String? cedula;
  final String? workContractJobTitle;

  const EmployeeWarningUser({
    required this.id,
    required this.nombreCompleto,
    this.email,
    this.telefono,
    this.cedula,
    this.workContractJobTitle,
  });

  factory EmployeeWarningUser.fromJson(Map<String, dynamic> j) =>
      EmployeeWarningUser(
        id: j['id'] as String,
        nombreCompleto: j['nombreCompleto'] as String,
        email: j['email'] as String?,
        telefono: j['telefono'] as String?,
        cedula: j['cedula'] as String?,
        workContractJobTitle: j['workContractJobTitle'] as String?,
      );
}

class EmployeeWarningEvidence {
  final String id;
  final String warningId;
  final String fileUrl;
  final String fileName;
  final String fileType;
  final DateTime createdAt;

  const EmployeeWarningEvidence({
    required this.id,
    required this.warningId,
    required this.fileUrl,
    required this.fileName,
    required this.fileType,
    required this.createdAt,
  });

  factory EmployeeWarningEvidence.fromJson(Map<String, dynamic> j) =>
      EmployeeWarningEvidence(
        id: j['id'] as String,
        warningId: j['warningId'] as String,
        fileUrl: j['fileUrl'] as String,
        fileName: j['fileName'] as String,
        fileType: j['fileType'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

class EmployeeWarningSignature {
  final String id;
  final String warningId;
  final String employeeUserId;
  final String signatureType; // SIGNED | REFUSED
  final String? signatureImageUrl;
  final String typedName;
  final String? comment;
  final DateTime signedAt;

  const EmployeeWarningSignature({
    required this.id,
    required this.warningId,
    required this.employeeUserId,
    required this.signatureType,
    this.signatureImageUrl,
    required this.typedName,
    this.comment,
    required this.signedAt,
  });

  factory EmployeeWarningSignature.fromJson(Map<String, dynamic> j) =>
      EmployeeWarningSignature(
        id: j['id'] as String,
        warningId: j['warningId'] as String,
        employeeUserId: j['employeeUserId'] as String,
        signatureType: j['signatureType'] as String,
        signatureImageUrl: j['signatureImageUrl'] as String?,
        typedName: j['typedName'] as String,
        comment: j['comment'] as String?,
        signedAt: DateTime.parse(j['signedAt'] as String),
      );
}

class EmployeeWarningAuditLog {
  final String id;
  final String warningId;
  final String action;
  final String? actorUserId;
  final String? oldStatus;
  final String? newStatus;
  final DateTime createdAt;
  final EmployeeWarningUser? actorUser;

  const EmployeeWarningAuditLog({
    required this.id,
    required this.warningId,
    required this.action,
    this.actorUserId,
    this.oldStatus,
    this.newStatus,
    required this.createdAt,
    this.actorUser,
  });

  factory EmployeeWarningAuditLog.fromJson(Map<String, dynamic> j) =>
      EmployeeWarningAuditLog(
        id: j['id'] as String,
        warningId: j['warningId'] as String,
        action: j['action'] as String,
        actorUserId: j['actorUserId'] as String?,
        oldStatus: j['oldStatus'] as String?,
        newStatus: j['newStatus'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
        actorUser: j['actorUser'] != null
            ? EmployeeWarningUser.fromJson(
                j['actorUser'] as Map<String, dynamic>,
              )
            : null,
      );
}

class EmployeeWarningsPage {
  final List<EmployeeWarning> items;
  final int total;
  final int page;
  final int limit;

  const EmployeeWarningsPage({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });

  factory EmployeeWarningsPage.fromJson(Map<String, dynamic> j) =>
      EmployeeWarningsPage(
        items: (j['items'] as List<dynamic>)
            .map((e) => EmployeeWarning.fromJson(e as Map<String, dynamic>))
            .toList(),
        total: j['total'] as int,
        page: j['page'] as int,
        limit: j['limit'] as int,
      );
}
