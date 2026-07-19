enum RedTecnicaSpecialty { cameras, gateMotors, both }

enum TechnicianApplicationStatus { pending, reviewing, approved, rejected }

enum TechnicianStatus { available, busy, unavailable, inactive }

enum TechnicianExperienceLevel {
  noExperience,
  lessThanOneYear,
  oneToThreeYears,
  moreThanThreeYears,
}

enum ToolsAvailability { yes, some, no }

enum TechnicianJobType {
  cameraInstallation,
  cameraMaintenance,
  gateMotorInstallation,
  gateMotorMaintenance,
}

enum TechnicianJobStatus { pending, inProgress, completed, cancelled }

String enumName(Object value) => value.toString().split('.').last;

T enumFromName<T>(List<T> values, String? name, T fallback) {
  final normalized = (name ?? '').trim();
  for (final value in values) {
    if (enumName(value as Object) == normalized) return value;
  }
  return fallback;
}

extension RedTecnicaSpecialtyLabel on RedTecnicaSpecialty {
  String get label {
    switch (this) {
      case RedTecnicaSpecialty.cameras:
        return 'Cámaras';
      case RedTecnicaSpecialty.gateMotors:
        return 'Motores de portones';
      case RedTecnicaSpecialty.both:
        return 'Cámaras y motores';
    }
  }
}

extension TechnicianApplicationStatusLabel on TechnicianApplicationStatus {
  String get label {
    switch (this) {
      case TechnicianApplicationStatus.pending:
        return 'Pendiente';
      case TechnicianApplicationStatus.reviewing:
        return 'En revisión';
      case TechnicianApplicationStatus.approved:
        return 'Aprobado';
      case TechnicianApplicationStatus.rejected:
        return 'Rechazado';
    }
  }
}

extension TechnicianStatusLabel on TechnicianStatus {
  String get label {
    switch (this) {
      case TechnicianStatus.available:
        return 'Disponible';
      case TechnicianStatus.busy:
        return 'Ocupado';
      case TechnicianStatus.unavailable:
        return 'No disponible';
      case TechnicianStatus.inactive:
        return 'Inactivo';
    }
  }
}

extension TechnicianExperienceLevelLabel on TechnicianExperienceLevel {
  String get label {
    switch (this) {
      case TechnicianExperienceLevel.noExperience:
        return 'Sin experiencia, deseo aprender';
      case TechnicianExperienceLevel.lessThanOneYear:
        return 'Menos de un año';
      case TechnicianExperienceLevel.oneToThreeYears:
        return 'De uno a tres años';
      case TechnicianExperienceLevel.moreThanThreeYears:
        return 'Más de tres años';
    }
  }
}

extension ToolsAvailabilityLabel on ToolsAvailability {
  String get label {
    switch (this) {
      case ToolsAvailability.yes:
        return 'Sí';
      case ToolsAvailability.some:
        return 'Algunas';
      case ToolsAvailability.no:
        return 'No';
    }
  }
}

extension TechnicianJobTypeLabel on TechnicianJobType {
  String get label {
    switch (this) {
      case TechnicianJobType.cameraInstallation:
        return 'Instalación de cámaras';
      case TechnicianJobType.cameraMaintenance:
        return 'Mantenimiento de cámaras';
      case TechnicianJobType.gateMotorInstallation:
        return 'Instalación de motor';
      case TechnicianJobType.gateMotorMaintenance:
        return 'Mantenimiento de motor';
    }
  }
}

extension TechnicianJobStatusLabel on TechnicianJobStatus {
  String get label {
    switch (this) {
      case TechnicianJobStatus.pending:
        return 'Pendiente';
      case TechnicianJobStatus.inProgress:
        return 'En proceso';
      case TechnicianJobStatus.completed:
        return 'Completado';
      case TechnicianJobStatus.cancelled:
        return 'Cancelado';
    }
  }
}

class TechnicianApplication {
  const TechnicianApplication({
    required this.id,
    required this.applicationCode,
    required this.fullName,
    required this.identityNumber,
    required this.phone,
    required this.whatsapp,
    required this.province,
    required this.municipality,
    required this.specialty,
    required this.experienceLevel,
    required this.toolsAvailability,
    required this.transportation,
    required this.availability,
    required this.status,
    required this.submittedAt,
    required this.createdAt,
    required this.updatedAt,
    this.birthDate,
    this.email,
    this.sector,
    this.manualAddress = '',
    this.formattedAddress = '',
    this.latitude,
    this.longitude,
    this.locationAccuracy,
    this.locationCapturedAt,
    this.locationSource = '',
    this.experienceDescription = '',
    this.cameraSkills = const [],
    this.gateMotorSkills = const [],
    this.tools = const [],
    this.otherTools = '',
    this.availabilityNotes = '',
    this.canTravel = false,
    this.canWorkWeekends = false,
    this.profilePhotoPath,
    this.identityFrontPhotoPath,
    this.identityBackPhotoPath,
    this.workEvidencePhotoPaths = const [],
    this.resumePath,
    this.resumeOriginalName = '',
    this.resumeMimeType = '',
    this.resumeSizeBytes,
    this.referenceName = '',
    this.referencePhone = '',
    this.previousCompany = '',
    this.rejectionReason = '',
    this.internalNotes = '',
    this.reviewedAt,
    this.reviewedBy,
    this.consentAccepted = false,
    this.consentAcceptedAt,
  });

  final String id;
  final String applicationCode;
  final String fullName;
  final String identityNumber;
  final DateTime? birthDate;
  final String phone;
  final String whatsapp;
  final String? email;
  final String province;
  final String municipality;
  final String? sector;
  final String manualAddress;
  final String formattedAddress;
  final double? latitude;
  final double? longitude;
  final double? locationAccuracy;
  final DateTime? locationCapturedAt;
  final String locationSource;
  final RedTecnicaSpecialty specialty;
  final TechnicianExperienceLevel experienceLevel;
  final String experienceDescription;
  final List<String> cameraSkills;
  final List<String> gateMotorSkills;
  final ToolsAvailability toolsAvailability;
  final List<String> tools;
  final String otherTools;
  final String transportation;
  final String availability;
  final String availabilityNotes;
  final bool canTravel;
  final bool canWorkWeekends;
  final String? profilePhotoPath;
  final String? identityFrontPhotoPath;
  final String? identityBackPhotoPath;
  final List<String> workEvidencePhotoPaths;
  final String? resumePath;
  final String resumeOriginalName;
  final String resumeMimeType;
  final int? resumeSizeBytes;
  final String referenceName;
  final String referencePhone;
  final String previousCompany;
  final TechnicianApplicationStatus status;
  final String rejectionReason;
  final String internalNotes;
  final DateTime submittedAt;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final bool consentAccepted;
  final DateTime? consentAcceptedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  TechnicianApplication copyWith({
    TechnicianApplicationStatus? status,
    String? rejectionReason,
    String? internalNotes,
    DateTime? reviewedAt,
    String? reviewedBy,
  }) {
    return TechnicianApplication(
      id: id,
      applicationCode: applicationCode,
      fullName: fullName,
      identityNumber: identityNumber,
      birthDate: birthDate,
      phone: phone,
      whatsapp: whatsapp,
      email: email,
      province: province,
      municipality: municipality,
      sector: sector,
      manualAddress: manualAddress,
      formattedAddress: formattedAddress,
      latitude: latitude,
      longitude: longitude,
      locationAccuracy: locationAccuracy,
      locationCapturedAt: locationCapturedAt,
      locationSource: locationSource,
      specialty: specialty,
      experienceLevel: experienceLevel,
      experienceDescription: experienceDescription,
      cameraSkills: cameraSkills,
      gateMotorSkills: gateMotorSkills,
      toolsAvailability: toolsAvailability,
      tools: tools,
      otherTools: otherTools,
      transportation: transportation,
      availability: availability,
      availabilityNotes: availabilityNotes,
      canTravel: canTravel,
      canWorkWeekends: canWorkWeekends,
      profilePhotoPath: profilePhotoPath,
      identityFrontPhotoPath: identityFrontPhotoPath,
      identityBackPhotoPath: identityBackPhotoPath,
      workEvidencePhotoPaths: workEvidencePhotoPaths,
      resumePath: resumePath,
      resumeOriginalName: resumeOriginalName,
      resumeMimeType: resumeMimeType,
      resumeSizeBytes: resumeSizeBytes,
      referenceName: referenceName,
      referencePhone: referencePhone,
      previousCompany: previousCompany,
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      internalNotes: internalNotes ?? this.internalNotes,
      submittedAt: submittedAt,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      consentAccepted: consentAccepted,
      consentAcceptedAt: consentAcceptedAt,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

class Technician {
  const Technician({
    required this.id,
    required this.technicianCode,
    required this.fullName,
    required this.identityNumber,
    required this.phone,
    required this.whatsapp,
    required this.province,
    required this.municipality,
    required this.specialty,
    required this.experienceLevel,
    required this.toolsAvailability,
    required this.transportation,
    required this.availability,
    required this.status,
    required this.isFavorite,
    required this.completedJobsCount,
    required this.rating,
    required this.approvedAt,
    required this.createdAt,
    required this.updatedAt,
    this.applicationId,
    this.birthDate,
    this.email,
    this.sector,
    this.manualAddress = '',
    this.formattedAddress = '',
    this.latitude,
    this.longitude,
    this.locationAccuracy,
    this.locationCapturedAt,
    this.locationSource = '',
    this.experienceDescription = '',
    this.cameraSkills = const [],
    this.gateMotorSkills = const [],
    this.tools = const [],
    this.otherTools = '',
    this.availabilityNotes = '',
    this.canTravel = false,
    this.canWorkWeekends = false,
    this.profilePhotoPath,
    this.identityDocumentPaths = const [],
    this.workEvidencePhotoPaths = const [],
    this.resumePath,
    this.resumeOriginalName = '',
    this.resumeMimeType = '',
    this.resumeSizeBytes,
    this.internalNotes = '',
    this.lastJobAt,
  });

  final String id;
  final String technicianCode;
  final String? applicationId;
  final String fullName;
  final String identityNumber;
  final DateTime? birthDate;
  final String phone;
  final String whatsapp;
  final String? email;
  final String province;
  final String municipality;
  final String? sector;
  final String manualAddress;
  final String formattedAddress;
  final double? latitude;
  final double? longitude;
  final double? locationAccuracy;
  final DateTime? locationCapturedAt;
  final String locationSource;
  final RedTecnicaSpecialty specialty;
  final TechnicianExperienceLevel experienceLevel;
  final String experienceDescription;
  final List<String> cameraSkills;
  final List<String> gateMotorSkills;
  final ToolsAvailability toolsAvailability;
  final List<String> tools;
  final String otherTools;
  final String transportation;
  final String availability;
  final String availabilityNotes;
  final bool canTravel;
  final bool canWorkWeekends;
  final String? profilePhotoPath;
  final List<String> identityDocumentPaths;
  final List<String> workEvidencePhotoPaths;
  final String? resumePath;
  final String resumeOriginalName;
  final String resumeMimeType;
  final int? resumeSizeBytes;
  final TechnicianStatus status;
  final bool isFavorite;
  final int completedJobsCount;
  final double rating;
  final String internalNotes;
  final DateTime approvedAt;
  final DateTime? lastJobAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Technician copyWith({
    TechnicianStatus? status,
    bool? isFavorite,
    int? completedJobsCount,
    double? rating,
    String? internalNotes,
    DateTime? lastJobAt,
  }) {
    return Technician(
      id: id,
      technicianCode: technicianCode,
      applicationId: applicationId,
      fullName: fullName,
      identityNumber: identityNumber,
      birthDate: birthDate,
      phone: phone,
      whatsapp: whatsapp,
      email: email,
      province: province,
      municipality: municipality,
      sector: sector,
      manualAddress: manualAddress,
      formattedAddress: formattedAddress,
      latitude: latitude,
      longitude: longitude,
      locationAccuracy: locationAccuracy,
      locationCapturedAt: locationCapturedAt,
      locationSource: locationSource,
      specialty: specialty,
      experienceLevel: experienceLevel,
      experienceDescription: experienceDescription,
      cameraSkills: cameraSkills,
      gateMotorSkills: gateMotorSkills,
      toolsAvailability: toolsAvailability,
      tools: tools,
      otherTools: otherTools,
      transportation: transportation,
      availability: availability,
      availabilityNotes: availabilityNotes,
      canTravel: canTravel,
      canWorkWeekends: canWorkWeekends,
      profilePhotoPath: profilePhotoPath,
      identityDocumentPaths: identityDocumentPaths,
      workEvidencePhotoPaths: workEvidencePhotoPaths,
      resumePath: resumePath,
      resumeOriginalName: resumeOriginalName,
      resumeMimeType: resumeMimeType,
      resumeSizeBytes: resumeSizeBytes,
      status: status ?? this.status,
      isFavorite: isFavorite ?? this.isFavorite,
      completedJobsCount: completedJobsCount ?? this.completedJobsCount,
      rating: rating ?? this.rating,
      internalNotes: internalNotes ?? this.internalNotes,
      approvedAt: approvedAt,
      lastJobAt: lastJobAt ?? this.lastJobAt,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

class TechnicianJob {
  const TechnicianJob({
    required this.id,
    required this.technicianId,
    required this.type,
    required this.date,
    required this.location,
    required this.description,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.agreedPayment,
    this.internalNote = '',
  });

  final String id;
  final String technicianId;
  final TechnicianJobType type;
  final DateTime date;
  final String location;
  final String description;
  final double? agreedPayment;
  final TechnicianJobStatus status;
  final String internalNote;
  final DateTime createdAt;
  final DateTime updatedAt;
}

class TechnicianEvaluation {
  const TechnicianEvaluation({
    required this.id,
    required this.technicianId,
    required this.rating,
    required this.note,
    required this.createdAt,
  });

  final String id;
  final String technicianId;
  final int rating;
  final String note;
  final DateTime createdAt;
}

class RedTecnicaSnapshot {
  const RedTecnicaSnapshot({
    required this.applications,
    required this.technicians,
    required this.jobs,
    required this.evaluations,
  });

  final List<TechnicianApplication> applications;
  final List<Technician> technicians;
  final List<TechnicianJob> jobs;
  final List<TechnicianEvaluation> evaluations;
}
