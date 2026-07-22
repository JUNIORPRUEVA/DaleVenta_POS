import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../clientes/cliente_model.dart';
import '../cotizaciones/cotizacion_models.dart';

enum ServiceOrderCategory {
  camara,
  motorPorton,
  alarma,
  cercoElectrico,
  intercom,
  puntoVenta,
}

enum ServiceOrderType { instalacion, mantenimiento, levantamiento, garantia }

enum ServiceOrderStatus {
  pendiente,
  enProceso,
  enPausa,
  pospuesta,
  finalizado,
  cancelado,
}

enum ServiceEvidenceType {
  referenciaTexto,
  referenciaImagen,
  referenciaVideo,
  evidenciaTexto,
  evidenciaImagen,
  evidenciaVideo,
}

enum ServiceReportType { requerimientoCliente, servicioFinalizado, otros }

ServiceOrderCategory serviceOrderCategoryFromApi(String value) {
  switch (value.trim()) {
    case 'camara':
      return ServiceOrderCategory.camara;
    case 'motor_porton':
      return ServiceOrderCategory.motorPorton;
    case 'alarma':
      return ServiceOrderCategory.alarma;
    case 'cerco_electrico':
      return ServiceOrderCategory.cercoElectrico;
    case 'intercom':
      return ServiceOrderCategory.intercom;
    case 'punto_venta':
      return ServiceOrderCategory.puntoVenta;
    default:
      return ServiceOrderCategory.camara;
  }
}

ServiceOrderType serviceOrderTypeFromApi(String value) {
  switch (value.trim()) {
    case 'instalacion':
      return ServiceOrderType.instalacion;
    case 'mantenimiento':
      return ServiceOrderType.mantenimiento;
    case 'levantamiento':
      return ServiceOrderType.levantamiento;
    case 'garantia':
      return ServiceOrderType.garantia;
    default:
      return ServiceOrderType.instalacion;
  }
}

ServiceOrderStatus serviceOrderStatusFromApi(String value) {
  switch (value.trim()) {
    case 'pendiente':
      return ServiceOrderStatus.pendiente;
    case 'en_proceso':
      return ServiceOrderStatus.enProceso;
    case 'en_pausa':
      return ServiceOrderStatus.enPausa;
    case 'pospuesta':
      return ServiceOrderStatus.pospuesta;
    case 'finalizado':
      return ServiceOrderStatus.finalizado;
    case 'cancelado':
      return ServiceOrderStatus.cancelado;
    default:
      return ServiceOrderStatus.pendiente;
  }
}

ServiceEvidenceType serviceEvidenceTypeFromApi(String value) {
  switch (value.trim()) {
    case 'referencia_texto':
      return ServiceEvidenceType.referenciaTexto;
    case 'referencia_imagen':
      return ServiceEvidenceType.referenciaImagen;
    case 'referencia_video':
      return ServiceEvidenceType.referenciaVideo;
    case 'evidencia_texto':
      return ServiceEvidenceType.evidenciaTexto;
    case 'evidencia_imagen':
      return ServiceEvidenceType.evidenciaImagen;
    case 'evidencia_video':
      return ServiceEvidenceType.evidenciaVideo;
    default:
      return ServiceEvidenceType.referenciaTexto;
  }
}

ServiceReportType serviceReportTypeFromApi(String value) {
  switch (value.trim()) {
    case 'requerimiento_cliente':
      return ServiceReportType.requerimientoCliente;
    case 'servicio_finalizado':
      return ServiceReportType.servicioFinalizado;
    case 'otros':
    default:
      return ServiceReportType.otros;
  }
}

extension ServiceOrderCategoryX on ServiceOrderCategory {
  String get apiValue {
    switch (this) {
      case ServiceOrderCategory.camara:
        return 'camara';
      case ServiceOrderCategory.motorPorton:
        return 'motor_porton';
      case ServiceOrderCategory.alarma:
        return 'alarma';
      case ServiceOrderCategory.cercoElectrico:
        return 'cerco_electrico';
      case ServiceOrderCategory.intercom:
        return 'intercom';
      case ServiceOrderCategory.puntoVenta:
        return 'punto_venta';
    }
  }

  String get label {
    switch (this) {
      case ServiceOrderCategory.camara:
        return 'Cámara';
      case ServiceOrderCategory.motorPorton:
        return 'Motor portón';
      case ServiceOrderCategory.alarma:
        return 'Alarma';
      case ServiceOrderCategory.cercoElectrico:
        return 'Cerco eléctrico';
      case ServiceOrderCategory.intercom:
        return 'Intercom';
      case ServiceOrderCategory.puntoVenta:
        return 'Punto de venta';
    }
  }
}

extension ServiceOrderTypeX on ServiceOrderType {
  String get apiValue {
    switch (this) {
      case ServiceOrderType.instalacion:
        return 'instalacion';
      case ServiceOrderType.mantenimiento:
        return 'mantenimiento';
      case ServiceOrderType.levantamiento:
        return 'levantamiento';
      case ServiceOrderType.garantia:
        return 'garantia';
    }
  }

  String get label {
    switch (this) {
      case ServiceOrderType.instalacion:
        return 'Instalación';
      case ServiceOrderType.mantenimiento:
        return 'Mantenimiento';
      case ServiceOrderType.levantamiento:
        return 'Levantamiento';
      case ServiceOrderType.garantia:
        return 'Garantía';
    }
  }
}

extension ServiceOrderStatusX on ServiceOrderStatus {
  bool get requiresUpdateConfirmation {
    switch (this) {
      case ServiceOrderStatus.enProceso:
      case ServiceOrderStatus.finalizado:
        return true;
      case ServiceOrderStatus.enPausa:
      case ServiceOrderStatus.pospuesta:
      case ServiceOrderStatus.pendiente:
      case ServiceOrderStatus.cancelado:
        return false;
    }
  }

  String get confirmationLabel {
    switch (this) {
      case ServiceOrderStatus.enProceso:
        return 'en proceso';
      case ServiceOrderStatus.enPausa:
        return 'en pausa';
      case ServiceOrderStatus.pospuesta:
        return 'pospuesta';
      case ServiceOrderStatus.finalizado:
        return 'finalizado';
      case ServiceOrderStatus.pendiente:
        return 'pendiente';
      case ServiceOrderStatus.cancelado:
        return 'cancelado';
    }
  }

  String get apiValue {
    switch (this) {
      case ServiceOrderStatus.pendiente:
        return 'pendiente';
      case ServiceOrderStatus.enProceso:
        return 'en_proceso';
      case ServiceOrderStatus.enPausa:
        return 'en_pausa';
      case ServiceOrderStatus.pospuesta:
        return 'pospuesta';
      case ServiceOrderStatus.finalizado:
        return 'finalizado';
      case ServiceOrderStatus.cancelado:
        return 'cancelado';
    }
  }

  String get label {
    switch (this) {
      case ServiceOrderStatus.pendiente:
        return 'Pendiente';
      case ServiceOrderStatus.enProceso:
        return 'En proceso';
      case ServiceOrderStatus.enPausa:
        return 'En pausa';
      case ServiceOrderStatus.pospuesta:
        return 'Pospuesta';
      case ServiceOrderStatus.finalizado:
        return 'Finalizado';
      case ServiceOrderStatus.cancelado:
        return 'Cancelado';
    }
  }

  Color get color {
    switch (this) {
      case ServiceOrderStatus.pendiente:
        return const Color(0xFFD98324);
      case ServiceOrderStatus.enProceso:
        return const Color(0xFF1D5D9B);
      case ServiceOrderStatus.enPausa:
        return const Color(0xFFB7791F);
      case ServiceOrderStatus.pospuesta:
        return const Color(0xFF8A6D3B);
      case ServiceOrderStatus.finalizado:
        return const Color(0xFF2E8B57);
      case ServiceOrderStatus.cancelado:
        return const Color(0xFFB3261E);
    }
  }

  List<ServiceOrderStatus> get allowedNextStatuses {
    switch (this) {
      case ServiceOrderStatus.pendiente:
        return const [
          ServiceOrderStatus.enProceso,
          ServiceOrderStatus.pospuesta,
          ServiceOrderStatus.cancelado,
        ];
      case ServiceOrderStatus.enProceso:
        return const [
          ServiceOrderStatus.enPausa,
          ServiceOrderStatus.pospuesta,
          ServiceOrderStatus.finalizado,
          ServiceOrderStatus.cancelado,
        ];
      case ServiceOrderStatus.enPausa:
        return const [
          ServiceOrderStatus.enProceso,
          ServiceOrderStatus.pospuesta,
          ServiceOrderStatus.cancelado,
        ];
      case ServiceOrderStatus.pospuesta:
        return const [
          ServiceOrderStatus.pendiente,
          ServiceOrderStatus.cancelado,
        ];
      case ServiceOrderStatus.finalizado:
        return const [];
      case ServiceOrderStatus.cancelado:
        return const [ServiceOrderStatus.pospuesta];
    }
  }

  List<ServiceOrderStatus> nextStatusesForRole({
    required bool canFinalizeDirectly,
  }) {
    if (this == ServiceOrderStatus.pendiente && canFinalizeDirectly) {
      return const [
        ServiceOrderStatus.enProceso,
        ServiceOrderStatus.pospuesta,
        ServiceOrderStatus.finalizado,
        ServiceOrderStatus.cancelado,
      ];
    }

    return allowedNextStatuses;
  }
}

extension ServiceEvidenceTypeX on ServiceEvidenceType {
  String get apiValue {
    switch (this) {
      case ServiceEvidenceType.referenciaTexto:
        return 'referencia_texto';
      case ServiceEvidenceType.referenciaImagen:
        return 'referencia_imagen';
      case ServiceEvidenceType.referenciaVideo:
        return 'referencia_video';
      case ServiceEvidenceType.evidenciaTexto:
        return 'evidencia_texto';
      case ServiceEvidenceType.evidenciaImagen:
        return 'evidencia_imagen';
      case ServiceEvidenceType.evidenciaVideo:
        return 'evidencia_video';
    }
  }

  String get label {
    switch (this) {
      case ServiceEvidenceType.referenciaTexto:
        return 'Referencia en texto';
      case ServiceEvidenceType.referenciaImagen:
        return 'Referencia en imagen';
      case ServiceEvidenceType.referenciaVideo:
        return 'Referencia en video';
      case ServiceEvidenceType.evidenciaTexto:
        return 'Evidencia en texto';
      case ServiceEvidenceType.evidenciaImagen:
        return 'Evidencia en imagen';
      case ServiceEvidenceType.evidenciaVideo:
        return 'Evidencia en video';
    }
  }

  bool get isReference {
    return this == ServiceEvidenceType.referenciaTexto ||
        this == ServiceEvidenceType.referenciaImagen ||
        this == ServiceEvidenceType.referenciaVideo;
  }

  bool get isTechnicalEvidence => !isReference;

  bool get isText {
    return this == ServiceEvidenceType.referenciaTexto ||
        this == ServiceEvidenceType.evidenciaTexto;
  }

  bool get isImage {
    return this == ServiceEvidenceType.referenciaImagen ||
        this == ServiceEvidenceType.evidenciaImagen;
  }

  bool get isVideo {
    return this == ServiceEvidenceType.referenciaVideo ||
        this == ServiceEvidenceType.evidenciaVideo;
  }

  String get familyLabel => isReference ? 'Referencia' : 'Evidencia técnica';
}

class ServiceOrderEvidenceModel {
  final String id;
  final String serviceOrderId;
  final ServiceEvidenceType type;
  final String content;
  final String createdById;
  final DateTime createdAt;
  final String? localPath;
  final Uint8List? previewBytes;
  final String? fileName;
  final bool isPendingUpload;
  final bool hasUploadError;

  const ServiceOrderEvidenceModel({
    required this.id,
    required this.serviceOrderId,
    required this.type,
    required this.content,
    required this.createdById,
    required this.createdAt,
    this.localPath,
    this.previewBytes,
    this.fileName,
    this.isPendingUpload = false,
    this.hasUploadError = false,
  });

  factory ServiceOrderEvidenceModel.fromJson(Map<String, dynamic> json) {
    final previewBytesBase64 = (json['previewBytesBase64'] ?? '').toString();
    return ServiceOrderEvidenceModel(
      id: (json['id'] ?? '').toString(),
      serviceOrderId: (json['serviceOrderId'] ?? '').toString(),
      type: serviceEvidenceTypeFromApi((json['type'] ?? '').toString()),
      content: (json['content'] ?? '').toString(),
      createdById: (json['createdById'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      localPath: (json['localPath'] ?? '').toString().trim().isEmpty
          ? null
          : (json['localPath'] ?? '').toString(),
      previewBytes: previewBytesBase64.trim().isEmpty
          ? null
          : base64Decode(previewBytesBase64),
      fileName: (json['fileName'] ?? '').toString().trim().isEmpty
          ? null
          : (json['fileName'] ?? '').toString(),
      isPendingUpload: json['isPendingUpload'] == true,
      hasUploadError: json['hasUploadError'] == true,
    );
  }

  ServiceOrderEvidenceModel copyWith({
    String? id,
    String? serviceOrderId,
    ServiceEvidenceType? type,
    String? content,
    String? createdById,
    DateTime? createdAt,
    String? localPath,
    Uint8List? previewBytes,
    String? fileName,
    bool? isPendingUpload,
    bool? hasUploadError,
    bool clearLocalPath = false,
    bool clearPreviewBytes = false,
    bool clearFileName = false,
  }) {
    return ServiceOrderEvidenceModel(
      id: id ?? this.id,
      serviceOrderId: serviceOrderId ?? this.serviceOrderId,
      type: type ?? this.type,
      content: content ?? this.content,
      createdById: createdById ?? this.createdById,
      createdAt: createdAt ?? this.createdAt,
      localPath: clearLocalPath ? null : (localPath ?? this.localPath),
      previewBytes: clearPreviewBytes
          ? null
          : (previewBytes ?? this.previewBytes),
      fileName: clearFileName ? null : (fileName ?? this.fileName),
      isPendingUpload: isPendingUpload ?? this.isPendingUpload,
      hasUploadError: hasUploadError ?? this.hasUploadError,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'serviceOrderId': serviceOrderId,
      'type': type.apiValue,
      'content': content,
      'createdById': createdById,
      'createdAt': createdAt.toIso8601String(),
      'localPath': localPath,
      'fileName': fileName,
      'isPendingUpload': isPendingUpload,
      'hasUploadError': hasUploadError,
      if (previewBytes != null && previewBytes!.isNotEmpty)
        'previewBytesBase64': base64Encode(previewBytes!),
    };
  }
}

extension ServiceReportTypeX on ServiceReportType {
  String get apiValue {
    switch (this) {
      case ServiceReportType.requerimientoCliente:
        return 'requerimiento_cliente';
      case ServiceReportType.servicioFinalizado:
        return 'servicio_finalizado';
      case ServiceReportType.otros:
        return 'otros';
    }
  }

  String get label {
    switch (this) {
      case ServiceReportType.requerimientoCliente:
        return 'Requerimiento del cliente';
      case ServiceReportType.servicioFinalizado:
        return 'Reporte de servicio finalizado';
      case ServiceReportType.otros:
        return 'Otros';
    }
  }

  Color get color {
    switch (this) {
      case ServiceReportType.requerimientoCliente:
        return const Color(0xFFC2410C);
      case ServiceReportType.servicioFinalizado:
        return const Color(0xFF047857);
      case ServiceReportType.otros:
        return const Color(0xFF1D4ED8);
    }
  }
}

class ServiceOrderReportModel {
  final String id;
  final String serviceOrderId;
  final ServiceReportType type;
  final String report;
  final String createdById;
  final DateTime createdAt;

  const ServiceOrderReportModel({
    required this.id,
    required this.serviceOrderId,
    required this.type,
    required this.report,
    required this.createdById,
    required this.createdAt,
  });

  factory ServiceOrderReportModel.fromJson(Map<String, dynamic> json) {
    return ServiceOrderReportModel(
      id: (json['id'] ?? '').toString(),
      serviceOrderId: (json['serviceOrderId'] ?? '').toString(),
      type: serviceReportTypeFromApi((json['type'] ?? '').toString()),
      report: (json['report'] ?? '').toString(),
      createdById: (json['createdById'] ?? '').toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'serviceOrderId': serviceOrderId,
      'type': type.apiValue,
      'report': report,
      'createdById': createdById,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class ServiceOrderStatusHistoryEntry {
  final String id;
  final String serviceOrderId;
  final ServiceOrderStatus? previousStatus;
  final ServiceOrderStatus nextStatus;
  final DateTime changedAt;
  final DateTime createdAt;
  final String? changedByUserId;
  final String? changedByUserName;
  final String? note;

  const ServiceOrderStatusHistoryEntry({
    required this.id,
    required this.serviceOrderId,
    required this.previousStatus,
    required this.nextStatus,
    required this.changedAt,
    required this.createdAt,
    required this.changedByUserId,
    required this.changedByUserName,
    required this.note,
  });

  factory ServiceOrderStatusHistoryEntry.fromJson(Map<String, dynamic> json) {
    final changedBy = json['changedBy'] is Map
        ? (json['changedBy'] as Map).cast<String, dynamic>()
        : null;
    return ServiceOrderStatusHistoryEntry(
      id: (json['id'] ?? '').toString(),
      serviceOrderId: (json['serviceOrderId'] ?? '').toString(),
      previousStatus: json['previousStatus'] == null
          ? null
          : serviceOrderStatusFromApi(json['previousStatus'].toString()),
      nextStatus: serviceOrderStatusFromApi(
        (json['nextStatus'] ?? '').toString(),
      ),
      changedAt:
          DateTime.tryParse((json['changedAt'] ?? '').toString()) ??
          DateTime.now(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.tryParse((json['changedAt'] ?? '').toString()) ??
          DateTime.now(),
      changedByUserId: json['changedByUserId']?.toString(),
      changedByUserName:
          json['changedByUserName']?.toString() ??
          changedBy?['nombreCompleto']?.toString(),
      note: json['note']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'serviceOrderId': serviceOrderId,
      'previousStatus': previousStatus?.apiValue,
      'nextStatus': nextStatus.apiValue,
      'changedAt': changedAt.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'changedByUserId': changedByUserId,
      'changedByUserName': changedByUserName,
      'changedBy': changedByUserName == null
          ? null
          : {'nombreCompleto': changedByUserName},
      'note': note,
    };
  }
}

class ServiceOrderModel {
  final String id;
  final String clientId;
  final ClienteModel? client;
  final String? quotationId;
  final ServiceOrderCategory category;
  final ServiceOrderType serviceType;
  final ServiceOrderStatus status;
  final String? technicalNote;
  final String? extraRequirements;
  final String? parentOrderId;
  final String createdById;
  final String? assignedToId;
  final DateTime? scheduledFor;
  final DateTime? finalizedAt;
  final DateTime? technicianConfirmedAt;
  final String? technicianConfirmedById;
  final DateTime? lastStatusChangedAt;
  final String? lastStatusChangedByUserId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ServiceOrderStatusHistoryEntry> statusHistory;
  final List<ServiceOrderEvidenceModel> evidences;
  final List<ServiceOrderReportModel> reports;

  const ServiceOrderModel({
    required this.id,
    required this.clientId,
    this.client,
    required this.quotationId,
    required this.category,
    required this.serviceType,
    required this.status,
    required this.technicalNote,
    required this.extraRequirements,
    required this.parentOrderId,
    required this.createdById,
    required this.assignedToId,
    required this.scheduledFor,
    required this.finalizedAt,
    required this.technicianConfirmedAt,
    required this.technicianConfirmedById,
    this.lastStatusChangedAt,
    this.lastStatusChangedByUserId,
    required this.createdAt,
    required this.updatedAt,
    this.statusHistory = const [],
    this.evidences = const [],
    this.reports = const [],
  });

  bool get isCloneSourceAllowed => status == ServiceOrderStatus.finalizado;
  List<ServiceOrderEvidenceModel> get referenceItems {
    return evidences
        .where((item) => item.type.isReference)
        .toList(growable: false);
  }

  List<ServiceOrderEvidenceModel> get technicalEvidenceItems {
    return evidences
        .where((item) => item.type.isTechnicalEvidence)
        .toList(growable: false);
  }

  ServiceOrderModel copyWith({
    String? id,
    String? clientId,
    ClienteModel? client,
    String? quotationId,
    ServiceOrderCategory? category,
    ServiceOrderType? serviceType,
    ServiceOrderStatus? status,
    String? technicalNote,
    String? extraRequirements,
    String? parentOrderId,
    String? createdById,
    String? assignedToId,
    DateTime? scheduledFor,
    DateTime? finalizedAt,
    DateTime? technicianConfirmedAt,
    String? technicianConfirmedById,
    DateTime? lastStatusChangedAt,
    String? lastStatusChangedByUserId,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<ServiceOrderStatusHistoryEntry>? statusHistory,
    List<ServiceOrderEvidenceModel>? evidences,
    List<ServiceOrderReportModel>? reports,
    bool clearQuotationId = false,
    bool clearTechnicalNote = false,
    bool clearExtraRequirements = false,
    bool clearParentOrderId = false,
    bool clearAssignedToId = false,
    bool clearClient = false,
  }) {
    return ServiceOrderModel(
      id: id ?? this.id,
      clientId: clientId ?? this.clientId,
      client: clearClient ? null : (client ?? this.client),
      quotationId: clearQuotationId ? null : (quotationId ?? this.quotationId),
      category: category ?? this.category,
      serviceType: serviceType ?? this.serviceType,
      status: status ?? this.status,
      technicalNote: clearTechnicalNote
          ? null
          : (technicalNote ?? this.technicalNote),
      extraRequirements: clearExtraRequirements
          ? null
          : (extraRequirements ?? this.extraRequirements),
      parentOrderId: clearParentOrderId
          ? null
          : (parentOrderId ?? this.parentOrderId),
      createdById: createdById ?? this.createdById,
      assignedToId: clearAssignedToId
          ? null
          : (assignedToId ?? this.assignedToId),
      scheduledFor: scheduledFor ?? this.scheduledFor,
      finalizedAt: finalizedAt ?? this.finalizedAt,
      technicianConfirmedAt:
          technicianConfirmedAt ?? this.technicianConfirmedAt,
      technicianConfirmedById:
          technicianConfirmedById ?? this.technicianConfirmedById,
      lastStatusChangedAt: lastStatusChangedAt ?? this.lastStatusChangedAt,
      lastStatusChangedByUserId:
          lastStatusChangedByUserId ?? this.lastStatusChangedByUserId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      statusHistory: statusHistory ?? this.statusHistory,
      evidences: evidences ?? this.evidences,
      reports: reports ?? this.reports,
    );
  }

  factory ServiceOrderModel.fromJson(Map<String, dynamic> json) {
    final rawEvidences = (json['evidences'] as List?) ?? const [];
    final rawReports = (json['reports'] as List?) ?? const [];
    final rawStatusHistory = (json['statusHistory'] as List?) ?? const [];
    return ServiceOrderModel(
      id: (json['id'] ?? '').toString(),
      clientId: (json['clientId'] ?? '').toString(),
      client: json['client'] is Map
          ? ClienteModel.fromJson(
              (json['client'] as Map).cast<String, dynamic>(),
            )
          : null,
      quotationId: json['quotationId']?.toString(),
      category: serviceOrderCategoryFromApi(
        (json['category'] ?? '').toString(),
      ),
      serviceType: serviceOrderTypeFromApi(
        (json['serviceType'] ?? '').toString(),
      ),
      status: serviceOrderStatusFromApi((json['status'] ?? '').toString()),
      technicalNote: json['technicalNote']?.toString(),
      extraRequirements: json['extraRequirements']?.toString(),
      parentOrderId: json['parentOrderId']?.toString(),
      createdById: (json['createdById'] ?? '').toString(),
      assignedToId: json['assignedToId']?.toString(),
      scheduledFor: json['scheduledFor'] == null
          ? null
          : DateTime.tryParse(json['scheduledFor'].toString()),
      finalizedAt: json['finalizedAt'] == null
          ? null
          : DateTime.tryParse(json['finalizedAt'].toString()),
      technicianConfirmedAt: json['technicianConfirmedAt'] == null
          ? null
          : DateTime.tryParse(json['technicianConfirmedAt'].toString()),
      technicianConfirmedById: json['technicianConfirmedById']?.toString(),
      lastStatusChangedAt: json['lastStatusChangedAt'] == null
          ? null
          : DateTime.tryParse(json['lastStatusChangedAt'].toString()),
      lastStatusChangedByUserId: json['lastStatusChangedByUserId']?.toString(),
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse((json['updatedAt'] ?? '').toString()) ??
          DateTime.now(),
      statusHistory: rawStatusHistory
          .whereType<Map>()
          .map(
            (row) => ServiceOrderStatusHistoryEntry.fromJson(
              row.cast<String, dynamic>(),
            ),
          )
          .toList(growable: false),
      evidences: rawEvidences
          .whereType<Map>()
          .map(
            (row) =>
                ServiceOrderEvidenceModel.fromJson(row.cast<String, dynamic>()),
          )
          .toList(growable: false),
      reports: rawReports
          .whereType<Map>()
          .map(
            (row) =>
                ServiceOrderReportModel.fromJson(row.cast<String, dynamic>()),
          )
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clientId': clientId,
      if (client != null) 'client': client!.toJson(),
      'quotationId': quotationId,
      'category': category.apiValue,
      'serviceType': serviceType.apiValue,
      'status': status.apiValue,
      'technicalNote': technicalNote,
      'extraRequirements': extraRequirements,
      'parentOrderId': parentOrderId,
      'createdById': createdById,
      'assignedToId': assignedToId,
      'scheduledFor': scheduledFor?.toIso8601String(),
      'finalizedAt': finalizedAt?.toIso8601String(),
      'technicianConfirmedAt': technicianConfirmedAt?.toIso8601String(),
      'technicianConfirmedById': technicianConfirmedById,
      'lastStatusChangedAt': lastStatusChangedAt?.toIso8601String(),
      'lastStatusChangedByUserId': lastStatusChangedByUserId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'statusHistory': statusHistory
          .map((item) => item.toJson())
          .toList(growable: false),
      'evidences': evidences
          .map((item) => item.toJson())
          .toList(growable: false),
      'reports': reports.map((item) => item.toJson()).toList(growable: false),
    };
  }
}

class CreateServiceOrderRequest {
  final String clientId;
  final String? quotationId;
  final ServiceOrderCategory category;
  final ServiceOrderType serviceType;
  final String? technicalNote;
  final String? extraRequirements;
  final String? assignedToId;
  final DateTime? scheduledFor;

  const CreateServiceOrderRequest({
    required this.clientId,
    this.quotationId,
    required this.category,
    required this.serviceType,
    this.technicalNote,
    this.extraRequirements,
    this.assignedToId,
    this.scheduledFor,
  });

  Map<String, dynamic> toJson() {
    return {
      'clientId': clientId,
      if ((quotationId ?? '').trim().isNotEmpty)
        'quotationId': quotationId!.trim(),
      'category': category.apiValue,
      'serviceType': serviceType.apiValue,
      if ((technicalNote ?? '').trim().isNotEmpty)
        'technicalNote': technicalNote!.trim(),
      if ((extraRequirements ?? '').trim().isNotEmpty)
        'extraRequirements': extraRequirements!.trim(),
      if ((assignedToId ?? '').trim().isNotEmpty) 'assignedToId': assignedToId,
      if (scheduledFor != null) 'scheduledFor': scheduledFor!.toIso8601String(),
    };
  }
}

class UpdateServiceOrderRequest {
  final String clientId;
  final String? quotationId;
  final ServiceOrderCategory category;
  final ServiceOrderType serviceType;
  final String? technicalNote;
  final String? extraRequirements;
  final String? assignedToId;
  final DateTime? scheduledFor;

  const UpdateServiceOrderRequest({
    required this.clientId,
    this.quotationId,
    required this.category,
    required this.serviceType,
    this.technicalNote,
    this.extraRequirements,
    this.assignedToId,
    this.scheduledFor,
  });

  Map<String, dynamic> toJson() {
    return {
      'clientId': clientId,
      if ((quotationId ?? '').trim().isNotEmpty)
        'quotationId': quotationId!.trim(),
      'category': category.apiValue,
      'serviceType': serviceType.apiValue,
      'technicalNote': technicalNote?.trim().isEmpty == true
          ? null
          : technicalNote?.trim(),
      'extraRequirements': extraRequirements?.trim().isEmpty == true
          ? null
          : extraRequirements?.trim(),
      'assignedToId': assignedToId?.trim().isEmpty == true
          ? null
          : assignedToId?.trim(),
      'scheduledFor': scheduledFor?.toIso8601String(),
    };
  }
}

class CloneServiceOrderRequest {
  final ServiceOrderType serviceType;
  final String? clientId;
  final String? quotationId;
  final String? technicalNote;
  final String? extraRequirements;
  final String? assignedToId;

  const CloneServiceOrderRequest({
    required this.serviceType,
    this.clientId,
    this.quotationId,
    this.technicalNote,
    this.extraRequirements,
    this.assignedToId,
  });

  Map<String, dynamic> toJson() {
    return {
      'serviceType': serviceType.apiValue,
      if ((clientId ?? '').trim().isNotEmpty) 'clientId': clientId!.trim(),
      if ((quotationId ?? '').trim().isNotEmpty)
        'quotationId': quotationId!.trim(),
      if ((technicalNote ?? '').trim().isNotEmpty)
        'technicalNote': technicalNote!.trim(),
      if ((extraRequirements ?? '').trim().isNotEmpty)
        'extraRequirements': extraRequirements!.trim(),
      if ((assignedToId ?? '').trim().isNotEmpty) 'assignedToId': assignedToId,
    };
  }
}

class CreateServiceOrderEvidenceRequest {
  final ServiceEvidenceType type;
  final String content;

  const CreateServiceOrderEvidenceRequest({
    required this.type,
    required this.content,
  });

  Map<String, dynamic> toJson() {
    return {'type': type.apiValue, 'content': content.trim()};
  }
}

class ServiceOrderDraftReference {
  final String id;
  final ServiceEvidenceType type;
  final String content;
  final String? uploadedUrl;
  final Uint8List? previewBytes;
  final String? localPath;
  final String? fileName;
  final int? sizeBytes;
  final DateTime createdAt;

  const ServiceOrderDraftReference({
    required this.id,
    required this.type,
    required this.content,
    required this.createdAt,
    this.uploadedUrl,
    this.previewBytes,
    this.localPath,
    this.fileName,
    this.sizeBytes,
  });

  factory ServiceOrderDraftReference.text({
    required String id,
    required String content,
  }) {
    return ServiceOrderDraftReference(
      id: id,
      type: ServiceEvidenceType.referenciaTexto,
      content: content,
      createdAt: DateTime.now(),
    );
  }

  factory ServiceOrderDraftReference.video({
    required String id,
    required String uploadedUrl,
    String? localPath,
    String? fileName,
    int? sizeBytes,
  }) {
    return ServiceOrderDraftReference(
      id: id,
      type: ServiceEvidenceType.referenciaVideo,
      content: uploadedUrl,
      uploadedUrl: uploadedUrl,
      localPath: localPath,
      fileName: fileName,
      sizeBytes: sizeBytes,
      createdAt: DateTime.now(),
    );
  }

  factory ServiceOrderDraftReference.image({
    required String id,
    required String uploadedUrl,
    required String fileName,
    Uint8List? previewBytes,
    String? localPath,
    int? sizeBytes,
  }) {
    return ServiceOrderDraftReference(
      id: id,
      type: ServiceEvidenceType.referenciaImagen,
      content: uploadedUrl,
      uploadedUrl: uploadedUrl,
      previewBytes: previewBytes,
      localPath: localPath,
      fileName: fileName,
      sizeBytes: sizeBytes,
      createdAt: DateTime.now(),
    );
  }

  bool get isImage => type.isImage;
  bool get isVideo => type.isVideo;
  bool get isText => type.isText;
  bool get hasRemoteContent => (uploadedUrl ?? '').trim().isNotEmpty;
  String get referenceContent =>
      isText ? content : ((uploadedUrl ?? content).trim());
  String get previewSource {
    final path = (localPath ?? '').trim();
    if (path.isNotEmpty) return path;
    return (uploadedUrl ?? content).trim();
  }
}

class ServiceOrderCreateArgs {
  final ServiceOrderModel? cloneSource;
  final ServiceOrderModel? editSource;
  final CotizacionModel? initialQuotation;
  final String? initialClientId;

  const ServiceOrderCreateArgs({
    this.cloneSource,
    this.editSource,
    this.initialQuotation,
    this.initialClientId,
  });

  bool get isCloneMode => cloneSource != null;
  bool get isEditMode => editSource != null;
}
