import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/auth/auth_repository.dart';
import '../../../core/storage/resilient_local_database.dart';
import '../red_tecnica_models.dart';

final redTecnicaRepositoryProvider = Provider<RedTecnicaRepository>((ref) {
  return RedTecnicaRepository(dio: ref.watch(dioProvider));
});

class RedTecnicaRepository {
  RedTecnicaRepository({Dio? dio}) : _dio = dio;

  static const _dbName = 'red_tecnica_local.db';
  static const _dbVersion = 1;
  static const _applicationsTable = 'red_tecnica_applications';
  static const _techniciansTable = 'red_tecnica_technicians';
  static const _jobsTable = 'red_tecnica_jobs';
  static const _evaluationsTable = 'red_tecnica_evaluations';

  Database? _database;
  final List<TechnicianApplication> _memoryApplications = [];
  final List<Technician> _memoryTechnicians = [];
  final List<TechnicianJob> _memoryJobs = [];
  final List<TechnicianEvaluation> _memoryEvaluations = [];
  final Dio? _dio;

  String get publicFormUrl {
    final base = (_dio?.options.baseUrl ?? '').trim().replaceAll(
      RegExp(r'/$'),
      '',
    );
    return base.isEmpty
        ? '/technical-network/public-form'
        : '$base/technical-network/public-form';
  }

  Future<Database> get _db async {
    if (_database != null) return _database!;
    _database = await openResilientLocalDatabase(
      fileName: _dbName,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_applicationsTable (
            id TEXT PRIMARY KEY,
            application_code TEXT NOT NULL UNIQUE,
            full_name TEXT NOT NULL,
            identity_number TEXT NOT NULL,
            phone TEXT NOT NULL,
            whatsapp TEXT NOT NULL,
            province TEXT NOT NULL,
            municipality TEXT NOT NULL,
            specialty TEXT NOT NULL,
            status TEXT NOT NULL,
            submitted_at TEXT NOT NULL,
            reviewed_at TEXT,
            reviewed_by TEXT,
            payload TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_techniciansTable (
            id TEXT PRIMARY KEY,
            technician_code TEXT NOT NULL UNIQUE,
            application_id TEXT,
            full_name TEXT NOT NULL,
            identity_number TEXT NOT NULL,
            phone TEXT NOT NULL,
            whatsapp TEXT NOT NULL,
            province TEXT NOT NULL,
            municipality TEXT NOT NULL,
            specialty TEXT NOT NULL,
            status TEXT NOT NULL,
            is_favorite INTEGER NOT NULL DEFAULT 0,
            completed_jobs_count INTEGER NOT NULL DEFAULT 0,
            rating REAL NOT NULL DEFAULT 0,
            approved_at TEXT NOT NULL,
            last_job_at TEXT,
            payload TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_jobsTable (
            id TEXT PRIMARY KEY,
            technician_id TEXT NOT NULL,
            type TEXT NOT NULL,
            date TEXT NOT NULL,
            status TEXT NOT NULL,
            payload TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS $_evaluationsTable (
            id TEXT PRIMARY KEY,
            technician_id TEXT NOT NULL,
            rating INTEGER NOT NULL,
            created_at TEXT NOT NULL,
            payload TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_rt_app_status ON $_applicationsTable(status)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_rt_app_identity ON $_applicationsTable(identity_number)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_rt_tech_status ON $_techniciansTable(status)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_rt_jobs_tech ON $_jobsTable(technician_id)',
        );
      },
    );
    return _database!;
  }

  Future<RedTecnicaSnapshot> snapshot() async {
    final remote = await _tryRemoteSnapshot();
    if (remote != null) return remote;

    if (kIsWeb) {
      return RedTecnicaSnapshot(
        applications: _memoryApplications.toList()
          ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt)),
        technicians: _memoryTechnicians.toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName)),
        jobs: _memoryJobs.toList()..sort((a, b) => b.date.compareTo(a.date)),
        evaluations: _memoryEvaluations.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
      );
    }

    final db = await _db;
    final applicationRows = await db.query(
      _applicationsTable,
      orderBy: 'submitted_at DESC',
    );
    final technicianRows = await db.query(
      _techniciansTable,
      orderBy: 'full_name COLLATE NOCASE ASC',
    );
    final jobRows = await db.query(_jobsTable, orderBy: 'date DESC');
    final evaluationRows = await db.query(
      _evaluationsTable,
      orderBy: 'created_at DESC',
    );

    return RedTecnicaSnapshot(
      applications: applicationRows.map(_applicationFromRow).toList(),
      technicians: technicianRows.map(_technicianFromRow).toList(),
      jobs: jobRows.map(_jobFromRow).toList(),
      evaluations: evaluationRows.map(_evaluationFromRow).toList(),
    );
  }

  Future<TechnicianApplication> submitApplication(
    TechnicianApplication draft,
  ) async {
    final remote = await _tryRemoteSubmitApplication(draft);
    if (remote != null) return remote;

    await _ensureNoDuplicate(
      identityNumber: draft.identityNumber,
      phone: draft.phone,
    );

    final now = DateTime.now();
    final application = TechnicianApplication(
      id: draft.id.isEmpty ? _newId('rta') : draft.id,
      applicationCode: draft.applicationCode.isEmpty
          ? await _nextApplicationCode()
          : draft.applicationCode,
      fullName: draft.fullName.trim(),
      identityNumber: _digits(draft.identityNumber),
      birthDate: draft.birthDate,
      phone: _digits(draft.phone),
      whatsapp: _digits(draft.whatsapp),
      email: draft.email,
      province: draft.province.trim(),
      municipality: draft.municipality.trim(),
      sector: draft.sector,
      specialty: draft.specialty,
      experienceLevel: draft.experienceLevel,
      experienceDescription: draft.experienceDescription.trim(),
      cameraSkills: draft.cameraSkills,
      gateMotorSkills: draft.gateMotorSkills,
      toolsAvailability: draft.toolsAvailability,
      tools: draft.tools,
      otherTools: draft.otherTools.trim(),
      transportation: draft.transportation.trim(),
      availability: draft.availability.trim(),
      availabilityNotes: draft.availabilityNotes.trim(),
      canTravel: draft.canTravel,
      canWorkWeekends: draft.canWorkWeekends,
      profilePhotoPath: draft.profilePhotoPath,
      identityFrontPhotoPath: draft.identityFrontPhotoPath,
      identityBackPhotoPath: draft.identityBackPhotoPath,
      workEvidencePhotoPaths: draft.workEvidencePhotoPaths,
      referenceName: draft.referenceName.trim(),
      referencePhone: _digits(draft.referencePhone),
      previousCompany: draft.previousCompany.trim(),
      status: draft.status,
      rejectionReason: draft.rejectionReason,
      internalNotes: draft.internalNotes,
      submittedAt: now,
      createdAt: now,
      updatedAt: now,
    );

    if (kIsWeb) {
      _memoryApplications.add(application);
      return application;
    }

    final db = await _db;
    await db.insert(_applicationsTable, _applicationToRow(application));
    return application;
  }

  Future<Technician> createTechnician(Technician technician) async {
    final remote = await _tryRemoteCreateTechnician(technician);
    if (remote != null) return remote;

    final item = technician.technicianCode.trim().isEmpty
        ? _technicianWithCode(technician, await _nextTechnicianCode())
        : technician;
    await _ensureNoTechnicianDuplicate(
      identityNumber: item.identityNumber,
      phone: item.phone,
      ignoreId: item.id,
    );

    if (kIsWeb) {
      _memoryTechnicians.removeWhere((tech) => tech.id == item.id);
      _memoryTechnicians.add(item);
      return item;
    }

    final db = await _db;
    await db.insert(
      _techniciansTable,
      _technicianToRow(item),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return item;
  }

  Future<Technician> approveApplication({
    required String applicationId,
    required String reviewedBy,
  }) async {
    final remote = await _tryRemoteApproveApplication(applicationId);
    if (remote != null) return remote;

    final snapshotData = await snapshot();
    final application = snapshotData.applications.firstWhere(
      (item) => item.id == applicationId,
      orElse: () => throw StateError('Solicitud no encontrada.'),
    );
    final existing = snapshotData.technicians.where(
      (item) => item.applicationId == application.id,
    );
    if (application.status == TechnicianApplicationStatus.approved ||
        existing.isNotEmpty) {
      throw StateError('Esta solicitud ya fue aprobada.');
    }

    final now = DateTime.now();
    final approved = application.copyWith(
      status: TechnicianApplicationStatus.approved,
      reviewedAt: now,
      reviewedBy: reviewedBy,
    );
    final technician = Technician(
      id: _newId('rt'),
      technicianCode: await _nextTechnicianCode(),
      applicationId: application.id,
      fullName: application.fullName,
      identityNumber: application.identityNumber,
      birthDate: application.birthDate,
      phone: application.phone,
      whatsapp: application.whatsapp,
      email: application.email,
      province: application.province,
      municipality: application.municipality,
      sector: application.sector,
      specialty: application.specialty,
      experienceLevel: application.experienceLevel,
      experienceDescription: application.experienceDescription,
      cameraSkills: application.cameraSkills,
      gateMotorSkills: application.gateMotorSkills,
      toolsAvailability: application.toolsAvailability,
      tools: application.tools,
      otherTools: application.otherTools,
      transportation: application.transportation,
      availability: application.availability,
      availabilityNotes: application.availabilityNotes,
      canTravel: application.canTravel,
      canWorkWeekends: application.canWorkWeekends,
      profilePhotoPath: application.profilePhotoPath,
      identityDocumentPaths: [
        if ((application.identityFrontPhotoPath ?? '').trim().isNotEmpty)
          application.identityFrontPhotoPath!,
        if ((application.identityBackPhotoPath ?? '').trim().isNotEmpty)
          application.identityBackPhotoPath!,
      ],
      workEvidencePhotoPaths: application.workEvidencePhotoPaths,
      status: TechnicianStatus.available,
      isFavorite: false,
      completedJobsCount: 0,
      rating: 0,
      internalNotes: application.internalNotes,
      approvedAt: now,
      createdAt: now,
      updatedAt: now,
    );

    if (kIsWeb) {
      _memoryApplications.removeWhere((item) => item.id == application.id);
      _memoryApplications.add(approved);
      _memoryTechnicians.add(technician);
      return technician;
    }

    final db = await _db;
    await db.transaction((txn) async {
      await txn.update(
        _applicationsTable,
        _applicationToRow(approved),
        where: 'id = ?',
        whereArgs: [approved.id],
      );
      await txn.insert(_techniciansTable, _technicianToRow(technician));
    });
    return technician;
  }

  Future<void> updateApplicationStatus(
    String applicationId,
    TechnicianApplicationStatus status, {
    String reviewedBy = '',
    String rejectionReason = '',
  }) async {
    if (await _tryRemoteUpdateApplicationStatus(
      applicationId,
      status,
      rejectionReason: rejectionReason,
    )) {
      return;
    }

    final snapshotData = await snapshot();
    final application = snapshotData.applications.firstWhere(
      (item) => item.id == applicationId,
      orElse: () => throw StateError('Solicitud no encontrada.'),
    );
    final updated = application.copyWith(
      status: status,
      reviewedAt: status == TechnicianApplicationStatus.pending
          ? application.reviewedAt
          : DateTime.now(),
      reviewedBy: reviewedBy.isEmpty ? application.reviewedBy : reviewedBy,
      rejectionReason: rejectionReason,
    );

    if (kIsWeb) {
      _memoryApplications.removeWhere((item) => item.id == applicationId);
      _memoryApplications.add(updated);
      return;
    }

    final db = await _db;
    await db.update(
      _applicationsTable,
      _applicationToRow(updated),
      where: 'id = ?',
      whereArgs: [applicationId],
    );
  }

  Future<void> updateTechnician(Technician technician) async {
    if (await _tryRemoteUpdateTechnician(technician)) return;

    if (kIsWeb) {
      _memoryTechnicians.removeWhere((item) => item.id == technician.id);
      _memoryTechnicians.add(technician);
      return;
    }
    final db = await _db;
    await db.update(
      _techniciansTable,
      _technicianToRow(technician),
      where: 'id = ?',
      whereArgs: [technician.id],
    );
  }

  Future<void> addJob(TechnicianJob job) async {
    if (await _tryRemoteAddJob(job)) return;

    if (kIsWeb) {
      _memoryJobs.add(job);
      await _applyCompletedJob(job);
      return;
    }
    final db = await _db;
    await db.insert(_jobsTable, _jobToRow(job));
    if (job.status == TechnicianJobStatus.completed) {
      await _applyCompletedJob(job);
    }
  }

  Future<void> addEvaluation(TechnicianEvaluation evaluation) async {
    if (await _tryRemoteAddEvaluation(evaluation)) return;

    if (kIsWeb) {
      _memoryEvaluations.add(evaluation);
      await _recalculateRating(evaluation.technicianId);
      return;
    }
    final db = await _db;
    await db.insert(_evaluationsTable, _evaluationToRow(evaluation));
    await _recalculateRating(evaluation.technicianId);
  }

  Future<RedTecnicaSnapshot?> _tryRemoteSnapshot() async {
    final dio = _dio;
    if (dio == null) return null;
    try {
      final responses = await Future.wait([
        dio.get<dynamic>('/technical-network/applications'),
        dio.get<dynamic>('/technical-network/technicians'),
      ]);
      final applicationsRaw = responses[0].data;
      final techniciansRaw = responses[1].data;
      final applications = _asList(
        applicationsRaw,
      ).map(_applicationFromApi).toList(growable: false);
      final technicians = _asList(
        techniciansRaw,
      ).map(_technicianFromApi).toList(growable: false);
      final jobs = <TechnicianJob>[];
      final evaluations = <TechnicianEvaluation>[];
      for (final tech in _asList(techniciansRaw)) {
        jobs.addAll(_asList(tech['jobs']).map(_jobFromApi));
        evaluations.addAll(
          _asList(tech['evaluations']).map(_evaluationFromApi),
        );
      }
      return RedTecnicaSnapshot(
        applications: applications,
        technicians: technicians,
        jobs: jobs,
        evaluations: evaluations,
      );
    } on DioException {
      return null;
    }
  }

  Future<TechnicianApplication?> _tryRemoteSubmitApplication(
    TechnicianApplication draft,
  ) async {
    final dio = _dio;
    if (dio == null) return null;
    try {
      final response = await dio.post<dynamic>(
        '/technical-network/public/applications',
        data: _applicationApiPayload(draft),
      );
      final data = response.data is Map ? response.data as Map : const {};
      final now = DateTime.now();
      return TechnicianApplication(
        id: (data['id'] ?? '').toString(),
        applicationCode: (data['applicationCode'] ?? '').toString(),
        fullName: draft.fullName,
        identityNumber: _digits(draft.identityNumber),
        birthDate: draft.birthDate,
        phone: _digits(draft.phone),
        whatsapp: _digits(draft.whatsapp),
        email: draft.email,
        province: draft.province,
        municipality: draft.municipality,
        sector: draft.sector,
        specialty: draft.specialty,
        experienceLevel: draft.experienceLevel,
        experienceDescription: draft.experienceDescription,
        cameraSkills: draft.cameraSkills,
        gateMotorSkills: draft.gateMotorSkills,
        toolsAvailability: draft.toolsAvailability,
        tools: draft.tools,
        otherTools: draft.otherTools,
        transportation: draft.transportation,
        availability: draft.availability,
        availabilityNotes: draft.availabilityNotes,
        canTravel: draft.canTravel,
        canWorkWeekends: draft.canWorkWeekends,
        profilePhotoPath: draft.profilePhotoPath,
        identityFrontPhotoPath: draft.identityFrontPhotoPath,
        identityBackPhotoPath: draft.identityBackPhotoPath,
        workEvidencePhotoPaths: draft.workEvidencePhotoPaths,
        referenceName: draft.referenceName,
        referencePhone: draft.referencePhone,
        previousCompany: draft.previousCompany,
        status: TechnicianApplicationStatus.pending,
        internalNotes: draft.internalNotes,
        submittedAt: now,
        createdAt: now,
        updatedAt: now,
      );
    } on DioException catch (error) {
      if (error.response != null) rethrow;
      return null;
    }
  }

  Future<Technician?> _tryRemoteCreateTechnician(Technician technician) async {
    final dio = _dio;
    if (dio == null) return null;
    try {
      final response = await dio.post<dynamic>(
        '/technical-network/technicians',
        data: _technicianApiPayload(technician),
      );
      final data = response.data is Map ? response.data as Map : const {};
      return Technician(
        id: (data['id'] ?? technician.id).toString(),
        technicianCode: (data['technicianCode'] ?? technician.technicianCode)
            .toString(),
        applicationId: technician.applicationId,
        fullName: technician.fullName,
        identityNumber: technician.identityNumber,
        birthDate: technician.birthDate,
        phone: technician.phone,
        whatsapp: technician.whatsapp,
        email: technician.email,
        province: technician.province,
        municipality: technician.municipality,
        sector: technician.sector,
        specialty: technician.specialty,
        experienceLevel: technician.experienceLevel,
        experienceDescription: technician.experienceDescription,
        cameraSkills: technician.cameraSkills,
        gateMotorSkills: technician.gateMotorSkills,
        toolsAvailability: technician.toolsAvailability,
        tools: technician.tools,
        otherTools: technician.otherTools,
        transportation: technician.transportation,
        availability: technician.availability,
        availabilityNotes: technician.availabilityNotes,
        canTravel: technician.canTravel,
        canWorkWeekends: technician.canWorkWeekends,
        profilePhotoPath: technician.profilePhotoPath,
        identityDocumentPaths: technician.identityDocumentPaths,
        workEvidencePhotoPaths: technician.workEvidencePhotoPaths,
        status: technician.status,
        isFavorite: technician.isFavorite,
        completedJobsCount: technician.completedJobsCount,
        rating: technician.rating,
        internalNotes: technician.internalNotes,
        approvedAt: technician.approvedAt,
        lastJobAt: technician.lastJobAt,
        createdAt: technician.createdAt,
        updatedAt: DateTime.now(),
      );
    } on DioException catch (error) {
      if (error.response != null) rethrow;
      return null;
    }
  }

  Future<Technician?> _tryRemoteApproveApplication(String applicationId) async {
    final dio = _dio;
    if (dio == null) return null;
    try {
      await dio.post<dynamic>(
        '/technical-network/applications/$applicationId/approve',
      );
      final data = await _tryRemoteSnapshot();
      return data?.technicians
          .where((item) => item.applicationId == applicationId)
          .firstOrNull;
    } on DioException catch (error) {
      if (error.response != null) rethrow;
      return null;
    }
  }

  Future<bool> _tryRemoteUpdateApplicationStatus(
    String applicationId,
    TechnicianApplicationStatus status, {
    String rejectionReason = '',
  }) async {
    final dio = _dio;
    if (dio == null) return false;
    try {
      await dio.patch<dynamic>(
        '/technical-network/applications/$applicationId/status',
        data: {
          'status': _apiApplicationStatus(status),
          'rejectionReason': rejectionReason,
        },
      );
      return true;
    } on DioException catch (error) {
      if (error.response != null) rethrow;
      return false;
    }
  }

  Future<bool> _tryRemoteUpdateTechnician(Technician technician) async {
    final dio = _dio;
    if (dio == null) return false;
    try {
      await dio.patch<dynamic>(
        '/technical-network/technicians/${technician.id}',
        data: {
          'status': _apiTechnicianStatus(technician.status),
          'isFavorite': technician.isFavorite,
        },
      );
      return true;
    } on DioException catch (error) {
      if (error.response != null) rethrow;
      return false;
    }
  }

  Future<bool> _tryRemoteAddJob(TechnicianJob job) async {
    final dio = _dio;
    if (dio == null) return false;
    try {
      await dio.post<dynamic>(
        '/technical-network/technicians/${job.technicianId}/jobs',
        data: {
          'type': _apiJobType(job.type),
          'date': job.date.toIso8601String(),
          'location': job.location,
          'description': job.description,
          'agreedPayment': job.agreedPayment,
          'status': _apiJobStatus(job.status),
          'internalNote': job.internalNote,
        },
      );
      return true;
    } on DioException catch (error) {
      if (error.response != null) rethrow;
      return false;
    }
  }

  Future<bool> _tryRemoteAddEvaluation(TechnicianEvaluation evaluation) async {
    final dio = _dio;
    if (dio == null) return false;
    try {
      await dio.post<dynamic>(
        '/technical-network/technicians/${evaluation.technicianId}/evaluations',
        data: {'rating': evaluation.rating, 'note': evaluation.note},
      );
      return true;
    } on DioException catch (error) {
      if (error.response != null) rethrow;
      return false;
    }
  }

  Future<void> _applyCompletedJob(TechnicianJob job) async {
    final snapshotData = await snapshot();
    final technician = snapshotData.technicians.firstWhere(
      (item) => item.id == job.technicianId,
      orElse: () => throw StateError('Tecnico no encontrado.'),
    );
    await updateTechnician(
      technician.copyWith(
        completedJobsCount: technician.completedJobsCount + 1,
        lastJobAt: job.date,
      ),
    );
  }

  Future<void> _recalculateRating(String technicianId) async {
    final snapshotData = await snapshot();
    final ratings = snapshotData.evaluations
        .where((item) => item.technicianId == technicianId)
        .map((item) => item.rating)
        .toList();
    if (ratings.isEmpty) return;
    final technician = snapshotData.technicians.firstWhere(
      (item) => item.id == technicianId,
      orElse: () => throw StateError('Tecnico no encontrado.'),
    );
    final average = ratings.reduce((a, b) => a + b) / ratings.length;
    await updateTechnician(technician.copyWith(rating: average));
  }

  Future<void> _ensureNoDuplicate({
    required String identityNumber,
    required String phone,
  }) async {
    final identity = _digits(identityNumber);
    final phoneDigits = _digits(phone);
    final data = await snapshot();
    final duplicate = data.applications.any((item) {
      return item.identityNumber == identity ||
          item.phone == phoneDigits ||
          item.whatsapp == phoneDigits;
    });
    if (duplicate) {
      throw StateError(
        'Ya existe una solicitud registrada con esa cedula o telefono.',
      );
    }
  }

  Future<void> _ensureNoTechnicianDuplicate({
    required String identityNumber,
    required String phone,
    required String ignoreId,
  }) async {
    final identity = _digits(identityNumber);
    final phoneDigits = _digits(phone);
    final data = await snapshot();
    final duplicate = data.technicians.any((item) {
      return item.id != ignoreId &&
          (item.identityNumber == identity ||
              item.phone == phoneDigits ||
              item.whatsapp == phoneDigits);
    });
    if (duplicate) {
      throw StateError('Ya existe un tecnico con esa cedula o telefono.');
    }
  }

  Future<String> _nextApplicationCode() async {
    final data = await snapshot();
    final next = data.applications.length + 1;
    return 'RT-${DateTime.now().year}-${next.toString().padLeft(4, '0')}';
  }

  Future<String> _nextTechnicianCode() async {
    final data = await snapshot();
    final next = data.technicians.length + 1;
    return 'FT-${next.toString().padLeft(4, '0')}';
  }

  Technician _technicianWithCode(Technician technician, String code) {
    return Technician(
      id: technician.id,
      technicianCode: code,
      applicationId: technician.applicationId,
      fullName: technician.fullName,
      identityNumber: technician.identityNumber,
      birthDate: technician.birthDate,
      phone: technician.phone,
      whatsapp: technician.whatsapp,
      email: technician.email,
      province: technician.province,
      municipality: technician.municipality,
      sector: technician.sector,
      specialty: technician.specialty,
      experienceLevel: technician.experienceLevel,
      experienceDescription: technician.experienceDescription,
      cameraSkills: technician.cameraSkills,
      gateMotorSkills: technician.gateMotorSkills,
      toolsAvailability: technician.toolsAvailability,
      tools: technician.tools,
      otherTools: technician.otherTools,
      transportation: technician.transportation,
      availability: technician.availability,
      availabilityNotes: technician.availabilityNotes,
      canTravel: technician.canTravel,
      canWorkWeekends: technician.canWorkWeekends,
      profilePhotoPath: technician.profilePhotoPath,
      identityDocumentPaths: technician.identityDocumentPaths,
      workEvidencePhotoPaths: technician.workEvidencePhotoPaths,
      status: technician.status,
      isFavorite: technician.isFavorite,
      completedJobsCount: technician.completedJobsCount,
      rating: technician.rating,
      internalNotes: technician.internalNotes,
      approvedAt: technician.approvedAt,
      lastJobAt: technician.lastJobAt,
      createdAt: technician.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, Object?> _applicationToRow(TechnicianApplication item) {
    return {
      'id': item.id,
      'application_code': item.applicationCode,
      'full_name': item.fullName,
      'identity_number': item.identityNumber,
      'phone': item.phone,
      'whatsapp': item.whatsapp,
      'province': item.province,
      'municipality': item.municipality,
      'specialty': enumName(item.specialty),
      'status': enumName(item.status),
      'submitted_at': item.submittedAt.toIso8601String(),
      'reviewed_at': item.reviewedAt?.toIso8601String(),
      'reviewed_by': item.reviewedBy,
      'payload': jsonEncode(_applicationToJson(item)),
    };
  }

  Map<String, Object?> _technicianToRow(Technician item) {
    return {
      'id': item.id,
      'technician_code': item.technicianCode,
      'application_id': item.applicationId,
      'full_name': item.fullName,
      'identity_number': item.identityNumber,
      'phone': item.phone,
      'whatsapp': item.whatsapp,
      'province': item.province,
      'municipality': item.municipality,
      'specialty': enumName(item.specialty),
      'status': enumName(item.status),
      'is_favorite': item.isFavorite ? 1 : 0,
      'completed_jobs_count': item.completedJobsCount,
      'rating': item.rating,
      'approved_at': item.approvedAt.toIso8601String(),
      'last_job_at': item.lastJobAt?.toIso8601String(),
      'payload': jsonEncode(_technicianToJson(item)),
    };
  }

  Map<String, Object?> _jobToRow(TechnicianJob item) {
    return {
      'id': item.id,
      'technician_id': item.technicianId,
      'type': enumName(item.type),
      'date': item.date.toIso8601String(),
      'status': enumName(item.status),
      'payload': jsonEncode(_jobToJson(item)),
    };
  }

  Map<String, Object?> _evaluationToRow(TechnicianEvaluation item) {
    return {
      'id': item.id,
      'technician_id': item.technicianId,
      'rating': item.rating,
      'created_at': item.createdAt.toIso8601String(),
      'payload': jsonEncode(_evaluationToJson(item)),
    };
  }

  TechnicianApplication _applicationFromRow(Map<String, Object?> row) {
    return _applicationFromJson(_payload(row));
  }

  Technician _technicianFromRow(Map<String, Object?> row) {
    return _technicianFromJson(_payload(row));
  }

  TechnicianJob _jobFromRow(Map<String, Object?> row) {
    return _jobFromJson(_payload(row));
  }

  TechnicianEvaluation _evaluationFromRow(Map<String, Object?> row) {
    return _evaluationFromJson(_payload(row));
  }

  Map<String, dynamic> _payload(Map<String, Object?> row) {
    final raw = (row['payload'] ?? '{}').toString();
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
  }

  Map<String, dynamic> _applicationToJson(TechnicianApplication item) => {
    'id': item.id,
    'applicationCode': item.applicationCode,
    'fullName': item.fullName,
    'identityNumber': item.identityNumber,
    'birthDate': item.birthDate?.toIso8601String(),
    'phone': item.phone,
    'whatsapp': item.whatsapp,
    'email': item.email,
    'province': item.province,
    'municipality': item.municipality,
    'sector': item.sector,
    'specialty': enumName(item.specialty),
    'experienceLevel': enumName(item.experienceLevel),
    'experienceDescription': item.experienceDescription,
    'cameraSkills': item.cameraSkills,
    'gateMotorSkills': item.gateMotorSkills,
    'toolsAvailability': enumName(item.toolsAvailability),
    'tools': item.tools,
    'otherTools': item.otherTools,
    'transportation': item.transportation,
    'availability': item.availability,
    'availabilityNotes': item.availabilityNotes,
    'canTravel': item.canTravel,
    'canWorkWeekends': item.canWorkWeekends,
    'profilePhotoPath': item.profilePhotoPath,
    'identityFrontPhotoPath': item.identityFrontPhotoPath,
    'identityBackPhotoPath': item.identityBackPhotoPath,
    'workEvidencePhotoPaths': item.workEvidencePhotoPaths,
    'referenceName': item.referenceName,
    'referencePhone': item.referencePhone,
    'previousCompany': item.previousCompany,
    'status': enumName(item.status),
    'rejectionReason': item.rejectionReason,
    'internalNotes': item.internalNotes,
    'submittedAt': item.submittedAt.toIso8601String(),
    'reviewedAt': item.reviewedAt?.toIso8601String(),
    'reviewedBy': item.reviewedBy,
    'createdAt': item.createdAt.toIso8601String(),
    'updatedAt': item.updatedAt.toIso8601String(),
  };

  Map<String, dynamic> _technicianToJson(Technician item) => {
    'id': item.id,
    'technicianCode': item.technicianCode,
    'applicationId': item.applicationId,
    'fullName': item.fullName,
    'identityNumber': item.identityNumber,
    'birthDate': item.birthDate?.toIso8601String(),
    'phone': item.phone,
    'whatsapp': item.whatsapp,
    'email': item.email,
    'province': item.province,
    'municipality': item.municipality,
    'sector': item.sector,
    'specialty': enumName(item.specialty),
    'experienceLevel': enumName(item.experienceLevel),
    'experienceDescription': item.experienceDescription,
    'cameraSkills': item.cameraSkills,
    'gateMotorSkills': item.gateMotorSkills,
    'toolsAvailability': enumName(item.toolsAvailability),
    'tools': item.tools,
    'otherTools': item.otherTools,
    'transportation': item.transportation,
    'availability': item.availability,
    'availabilityNotes': item.availabilityNotes,
    'canTravel': item.canTravel,
    'canWorkWeekends': item.canWorkWeekends,
    'profilePhotoPath': item.profilePhotoPath,
    'identityDocumentPaths': item.identityDocumentPaths,
    'workEvidencePhotoPaths': item.workEvidencePhotoPaths,
    'status': enumName(item.status),
    'isFavorite': item.isFavorite,
    'completedJobsCount': item.completedJobsCount,
    'rating': item.rating,
    'internalNotes': item.internalNotes,
    'approvedAt': item.approvedAt.toIso8601String(),
    'lastJobAt': item.lastJobAt?.toIso8601String(),
    'createdAt': item.createdAt.toIso8601String(),
    'updatedAt': item.updatedAt.toIso8601String(),
  };

  Map<String, dynamic> _jobToJson(TechnicianJob item) => {
    'id': item.id,
    'technicianId': item.technicianId,
    'type': enumName(item.type),
    'date': item.date.toIso8601String(),
    'location': item.location,
    'description': item.description,
    'agreedPayment': item.agreedPayment,
    'status': enumName(item.status),
    'internalNote': item.internalNote,
    'createdAt': item.createdAt.toIso8601String(),
    'updatedAt': item.updatedAt.toIso8601String(),
  };

  Map<String, dynamic> _evaluationToJson(TechnicianEvaluation item) => {
    'id': item.id,
    'technicianId': item.technicianId,
    'rating': item.rating,
    'note': item.note,
    'createdAt': item.createdAt.toIso8601String(),
  };

  TechnicianApplication _applicationFromJson(Map<String, dynamic> json) {
    return TechnicianApplication(
      id: s(json, 'id'),
      applicationCode: s(json, 'applicationCode'),
      fullName: s(json, 'fullName'),
      identityNumber: s(json, 'identityNumber'),
      birthDate: dt(json['birthDate']),
      phone: s(json, 'phone'),
      whatsapp: s(json, 'whatsapp'),
      email: s(json, 'email'),
      province: s(json, 'province'),
      municipality: s(json, 'municipality'),
      sector: s(json, 'sector'),
      specialty: enumFromName(
        RedTecnicaSpecialty.values,
        s(json, 'specialty'),
        RedTecnicaSpecialty.cameras,
      ),
      experienceLevel: enumFromName(
        TechnicianExperienceLevel.values,
        s(json, 'experienceLevel'),
        TechnicianExperienceLevel.noExperience,
      ),
      experienceDescription: s(json, 'experienceDescription'),
      cameraSkills: list(json['cameraSkills']),
      gateMotorSkills: list(json['gateMotorSkills']),
      toolsAvailability: enumFromName(
        ToolsAvailability.values,
        s(json, 'toolsAvailability'),
        ToolsAvailability.no,
      ),
      tools: list(json['tools']),
      otherTools: s(json, 'otherTools'),
      transportation: s(json, 'transportation'),
      availability: s(json, 'availability'),
      availabilityNotes: s(json, 'availabilityNotes'),
      canTravel: b(json['canTravel']),
      canWorkWeekends: b(json['canWorkWeekends']),
      profilePhotoPath: s(json, 'profilePhotoPath'),
      identityFrontPhotoPath: s(json, 'identityFrontPhotoPath'),
      identityBackPhotoPath: s(json, 'identityBackPhotoPath'),
      workEvidencePhotoPaths: list(json['workEvidencePhotoPaths']),
      referenceName: s(json, 'referenceName'),
      referencePhone: s(json, 'referencePhone'),
      previousCompany: s(json, 'previousCompany'),
      status: enumFromName(
        TechnicianApplicationStatus.values,
        s(json, 'status'),
        TechnicianApplicationStatus.pending,
      ),
      rejectionReason: s(json, 'rejectionReason'),
      internalNotes: s(json, 'internalNotes'),
      submittedAt: dt(json['submittedAt']) ?? DateTime.now(),
      reviewedAt: dt(json['reviewedAt']),
      reviewedBy: s(json, 'reviewedBy'),
      createdAt: dt(json['createdAt']) ?? DateTime.now(),
      updatedAt: dt(json['updatedAt']) ?? DateTime.now(),
    );
  }

  Technician _technicianFromJson(Map<String, dynamic> json) {
    return Technician(
      id: s(json, 'id'),
      technicianCode: s(json, 'technicianCode'),
      applicationId: s(json, 'applicationId'),
      fullName: s(json, 'fullName'),
      identityNumber: s(json, 'identityNumber'),
      birthDate: dt(json['birthDate']),
      phone: s(json, 'phone'),
      whatsapp: s(json, 'whatsapp'),
      email: s(json, 'email'),
      province: s(json, 'province'),
      municipality: s(json, 'municipality'),
      sector: s(json, 'sector'),
      specialty: enumFromName(
        RedTecnicaSpecialty.values,
        s(json, 'specialty'),
        RedTecnicaSpecialty.cameras,
      ),
      experienceLevel: enumFromName(
        TechnicianExperienceLevel.values,
        s(json, 'experienceLevel'),
        TechnicianExperienceLevel.noExperience,
      ),
      experienceDescription: s(json, 'experienceDescription'),
      cameraSkills: list(json['cameraSkills']),
      gateMotorSkills: list(json['gateMotorSkills']),
      toolsAvailability: enumFromName(
        ToolsAvailability.values,
        s(json, 'toolsAvailability'),
        ToolsAvailability.no,
      ),
      tools: list(json['tools']),
      otherTools: s(json, 'otherTools'),
      transportation: s(json, 'transportation'),
      availability: s(json, 'availability'),
      availabilityNotes: s(json, 'availabilityNotes'),
      canTravel: b(json['canTravel']),
      canWorkWeekends: b(json['canWorkWeekends']),
      profilePhotoPath: s(json, 'profilePhotoPath'),
      identityDocumentPaths: list(json['identityDocumentPaths']),
      workEvidencePhotoPaths: list(json['workEvidencePhotoPaths']),
      status: enumFromName(
        TechnicianStatus.values,
        s(json, 'status'),
        TechnicianStatus.available,
      ),
      isFavorite: b(json['isFavorite']),
      completedJobsCount: i(json['completedJobsCount']),
      rating: d(json['rating']),
      internalNotes: s(json, 'internalNotes'),
      approvedAt: dt(json['approvedAt']) ?? DateTime.now(),
      lastJobAt: dt(json['lastJobAt']),
      createdAt: dt(json['createdAt']) ?? DateTime.now(),
      updatedAt: dt(json['updatedAt']) ?? DateTime.now(),
    );
  }

  TechnicianJob _jobFromJson(Map<String, dynamic> json) => TechnicianJob(
    id: s(json, 'id'),
    technicianId: s(json, 'technicianId'),
    type: enumFromName(
      TechnicianJobType.values,
      s(json, 'type'),
      TechnicianJobType.cameraInstallation,
    ),
    date: dt(json['date']) ?? DateTime.now(),
    location: s(json, 'location'),
    description: s(json, 'description'),
    agreedPayment: json['agreedPayment'] == null
        ? null
        : d(json['agreedPayment']),
    status: enumFromName(
      TechnicianJobStatus.values,
      s(json, 'status'),
      TechnicianJobStatus.pending,
    ),
    internalNote: s(json, 'internalNote'),
    createdAt: dt(json['createdAt']) ?? DateTime.now(),
    updatedAt: dt(json['updatedAt']) ?? DateTime.now(),
  );

  TechnicianEvaluation _evaluationFromJson(Map<String, dynamic> json) =>
      TechnicianEvaluation(
        id: s(json, 'id'),
        technicianId: s(json, 'technicianId'),
        rating: i(json['rating']),
        note: s(json, 'note'),
        createdAt: dt(json['createdAt']) ?? DateTime.now(),
      );

  static List<Map<String, dynamic>> _asList(Object? value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((item) => item.map((key, value) => MapEntry('$key', value)))
          .toList(growable: false);
    }
    return const [];
  }

  TechnicianApplication _applicationFromApi(Map<String, dynamic> json) {
    return TechnicianApplication(
      id: s(json, 'id'),
      applicationCode: s(json, 'applicationCode'),
      fullName: s(json, 'fullName'),
      identityNumber: s(json, 'identityNumber'),
      phone: s(json, 'phone'),
      whatsapp: s(json, 'whatsapp'),
      email: s(json, 'email'),
      province: s(json, 'province'),
      municipality: s(json, 'municipality'),
      sector: s(json, 'sector'),
      specialty: _specialtyFromApi(s(json, 'specialty')),
      experienceLevel: _experienceFromApi(s(json, 'experienceLevel')),
      experienceDescription: s(json, 'experienceDescription'),
      cameraSkills: list(json['cameraSkills']),
      gateMotorSkills: list(json['gateMotorSkills']),
      toolsAvailability: _toolsAvailabilityFromApi(
        s(json, 'toolsAvailability'),
      ),
      tools: list(json['tools']),
      otherTools: s(json, 'otherTools'),
      transportation: s(json, 'transportation'),
      availability: s(json, 'availability'),
      availabilityNotes: s(json, 'availabilityNotes'),
      canTravel: b(json['canTravel']),
      canWorkWeekends: b(json['canWorkWeekends']),
      profilePhotoPath: s(json, 'profilePhotoUrl'),
      identityFrontPhotoPath: s(json, 'identityFrontPhotoUrl'),
      identityBackPhotoPath: s(json, 'identityBackPhotoUrl'),
      workEvidencePhotoPaths: list(json['workEvidencePhotoUrls']),
      referenceName: s(json, 'referenceName'),
      referencePhone: s(json, 'referencePhone'),
      previousCompany: s(json, 'previousCompany'),
      status: _applicationStatusFromApi(s(json, 'status')),
      rejectionReason: s(json, 'rejectionReason'),
      internalNotes: s(json, 'internalNotes'),
      submittedAt: dt(json['submittedAt']) ?? DateTime.now(),
      reviewedAt: dt(json['reviewedAt']),
      reviewedBy: s(json, 'reviewedById'),
      createdAt: dt(json['createdAt']) ?? DateTime.now(),
      updatedAt: dt(json['updatedAt']) ?? DateTime.now(),
    );
  }

  Technician _technicianFromApi(Map<String, dynamic> json) {
    return Technician(
      id: s(json, 'id'),
      technicianCode: s(json, 'technicianCode'),
      applicationId: s(json, 'applicationId'),
      fullName: s(json, 'fullName'),
      identityNumber: s(json, 'identityNumber'),
      phone: s(json, 'phone'),
      whatsapp: s(json, 'whatsapp'),
      email: s(json, 'email'),
      province: s(json, 'province'),
      municipality: s(json, 'municipality'),
      sector: s(json, 'sector'),
      specialty: _specialtyFromApi(s(json, 'specialty')),
      experienceLevel: _experienceFromApi(s(json, 'experienceLevel')),
      experienceDescription: s(json, 'experienceDescription'),
      cameraSkills: list(json['cameraSkills']),
      gateMotorSkills: list(json['gateMotorSkills']),
      toolsAvailability: _toolsAvailabilityFromApi(
        s(json, 'toolsAvailability'),
      ),
      tools: list(json['tools']),
      otherTools: s(json, 'otherTools'),
      transportation: s(json, 'transportation'),
      availability: s(json, 'availability'),
      availabilityNotes: s(json, 'availabilityNotes'),
      canTravel: b(json['canTravel']),
      canWorkWeekends: b(json['canWorkWeekends']),
      profilePhotoPath: s(json, 'profilePhotoUrl'),
      identityDocumentPaths: list(json['identityDocumentUrls']),
      workEvidencePhotoPaths: list(json['workEvidencePhotoUrls']),
      status: _technicianStatusFromApi(s(json, 'status')),
      isFavorite: b(json['isFavorite']),
      completedJobsCount: i(json['completedJobsCount']),
      rating: d(json['rating']),
      internalNotes: s(json, 'internalNotes'),
      approvedAt: dt(json['approvedAt']) ?? DateTime.now(),
      lastJobAt: dt(json['lastJobAt']),
      createdAt: dt(json['createdAt']) ?? DateTime.now(),
      updatedAt: dt(json['updatedAt']) ?? DateTime.now(),
    );
  }

  TechnicianJob _jobFromApi(Map<String, dynamic> json) => TechnicianJob(
    id: s(json, 'id'),
    technicianId: s(json, 'technicianId'),
    type: _jobTypeFromApi(s(json, 'type')),
    date: dt(json['date']) ?? DateTime.now(),
    location: s(json, 'location'),
    description: s(json, 'description'),
    agreedPayment: json['agreedPayment'] == null
        ? null
        : d(json['agreedPayment']),
    status: _jobStatusFromApi(s(json, 'status')),
    internalNote: s(json, 'internalNote'),
    createdAt: dt(json['createdAt']) ?? DateTime.now(),
    updatedAt: dt(json['updatedAt']) ?? DateTime.now(),
  );

  TechnicianEvaluation _evaluationFromApi(Map<String, dynamic> json) =>
      TechnicianEvaluation(
        id: s(json, 'id'),
        technicianId: s(json, 'technicianId'),
        rating: i(json['rating']),
        note: s(json, 'note'),
        createdAt: dt(json['createdAt']) ?? DateTime.now(),
      );

  Map<String, Object?> _applicationApiPayload(TechnicianApplication item) => {
    'fullName': item.fullName,
    'identityNumber': item.identityNumber,
    'phone': item.phone,
    'whatsapp': item.whatsapp,
    'email': item.email,
    'province': item.province,
    'municipality': item.municipality,
    'sector': item.sector,
    'specialty': _apiSpecialty(item.specialty),
    'experienceLevel': _apiExperience(item.experienceLevel),
    'experienceDescription': item.experienceDescription,
    'cameraSkills': item.cameraSkills,
    'gateMotorSkills': item.gateMotorSkills,
    'toolsAvailability': _apiToolsAvailability(item.toolsAvailability),
    'tools': item.tools,
    'otherTools': item.otherTools,
    'transportation': item.transportation,
    'availability': item.availability,
    'availabilityNotes': item.availabilityNotes,
    'canTravel': item.canTravel,
    'canWorkWeekends': item.canWorkWeekends,
    'profilePhotoUrl': item.profilePhotoPath,
    'identityFrontPhotoUrl': item.identityFrontPhotoPath,
    'identityBackPhotoUrl': item.identityBackPhotoPath,
    'workEvidencePhotoUrls': item.workEvidencePhotoPaths,
    'referenceName': item.referenceName,
    'referencePhone': item.referencePhone,
    'previousCompany': item.previousCompany,
    'internalNotes': item.internalNotes,
  };

  Map<String, Object?> _technicianApiPayload(Technician item) => {
    ..._applicationApiPayload(
      TechnicianApplication(
        id: '',
        applicationCode: '',
        fullName: item.fullName,
        identityNumber: item.identityNumber,
        phone: item.phone,
        whatsapp: item.whatsapp,
        email: item.email,
        province: item.province,
        municipality: item.municipality,
        sector: item.sector,
        specialty: item.specialty,
        experienceLevel: item.experienceLevel,
        experienceDescription: item.experienceDescription,
        cameraSkills: item.cameraSkills,
        gateMotorSkills: item.gateMotorSkills,
        toolsAvailability: item.toolsAvailability,
        tools: item.tools,
        otherTools: item.otherTools,
        transportation: item.transportation,
        availability: item.availability,
        availabilityNotes: item.availabilityNotes,
        canTravel: item.canTravel,
        canWorkWeekends: item.canWorkWeekends,
        profilePhotoPath: item.profilePhotoPath,
        workEvidencePhotoPaths: item.workEvidencePhotoPaths,
        internalNotes: item.internalNotes,
        status: TechnicianApplicationStatus.pending,
        submittedAt: DateTime.now(),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ),
    'status': _apiTechnicianStatus(item.status),
  };

  static String _apiSpecialty(RedTecnicaSpecialty value) => switch (value) {
    RedTecnicaSpecialty.cameras => 'CAMERAS',
    RedTecnicaSpecialty.gateMotors => 'GATE_MOTORS',
    RedTecnicaSpecialty.both => 'BOTH',
  };

  static RedTecnicaSpecialty _specialtyFromApi(String value) {
    return switch (value.toUpperCase()) {
      'GATE_MOTORS' => RedTecnicaSpecialty.gateMotors,
      'BOTH' => RedTecnicaSpecialty.both,
      _ => RedTecnicaSpecialty.cameras,
    };
  }

  static String _apiApplicationStatus(TechnicianApplicationStatus value) =>
      switch (value) {
        TechnicianApplicationStatus.pending => 'PENDING',
        TechnicianApplicationStatus.reviewing => 'REVIEWING',
        TechnicianApplicationStatus.approved => 'APPROVED',
        TechnicianApplicationStatus.rejected => 'REJECTED',
      };

  static TechnicianApplicationStatus _applicationStatusFromApi(String value) {
    return switch (value.toUpperCase()) {
      'REVIEWING' => TechnicianApplicationStatus.reviewing,
      'APPROVED' => TechnicianApplicationStatus.approved,
      'REJECTED' => TechnicianApplicationStatus.rejected,
      _ => TechnicianApplicationStatus.pending,
    };
  }

  static String _apiTechnicianStatus(TechnicianStatus value) => switch (value) {
    TechnicianStatus.available => 'AVAILABLE',
    TechnicianStatus.busy => 'BUSY',
    TechnicianStatus.unavailable => 'UNAVAILABLE',
    TechnicianStatus.inactive => 'INACTIVE',
  };

  static TechnicianStatus _technicianStatusFromApi(String value) {
    return switch (value.toUpperCase()) {
      'BUSY' => TechnicianStatus.busy,
      'UNAVAILABLE' => TechnicianStatus.unavailable,
      'INACTIVE' => TechnicianStatus.inactive,
      _ => TechnicianStatus.available,
    };
  }

  static String _apiExperience(TechnicianExperienceLevel value) =>
      switch (value) {
        TechnicianExperienceLevel.noExperience => 'NO_EXPERIENCE',
        TechnicianExperienceLevel.lessThanOneYear => 'LESS_THAN_ONE_YEAR',
        TechnicianExperienceLevel.oneToThreeYears => 'ONE_TO_THREE_YEARS',
        TechnicianExperienceLevel.moreThanThreeYears => 'MORE_THAN_THREE_YEARS',
      };

  static TechnicianExperienceLevel _experienceFromApi(String value) {
    return switch (value.toUpperCase()) {
      'LESS_THAN_ONE_YEAR' => TechnicianExperienceLevel.lessThanOneYear,
      'ONE_TO_THREE_YEARS' => TechnicianExperienceLevel.oneToThreeYears,
      'MORE_THAN_THREE_YEARS' => TechnicianExperienceLevel.moreThanThreeYears,
      _ => TechnicianExperienceLevel.noExperience,
    };
  }

  static String _apiToolsAvailability(ToolsAvailability value) =>
      switch (value) {
        ToolsAvailability.yes => 'YES',
        ToolsAvailability.some => 'SOME',
        ToolsAvailability.no => 'NO',
      };

  static ToolsAvailability _toolsAvailabilityFromApi(String value) {
    return switch (value.toUpperCase()) {
      'YES' => ToolsAvailability.yes,
      'SOME' => ToolsAvailability.some,
      _ => ToolsAvailability.no,
    };
  }

  static String _apiJobType(TechnicianJobType value) => switch (value) {
    TechnicianJobType.cameraInstallation => 'CAMERA_INSTALLATION',
    TechnicianJobType.cameraMaintenance => 'CAMERA_MAINTENANCE',
    TechnicianJobType.gateMotorInstallation => 'GATE_MOTOR_INSTALLATION',
    TechnicianJobType.gateMotorMaintenance => 'GATE_MOTOR_MAINTENANCE',
  };

  static TechnicianJobType _jobTypeFromApi(String value) {
    return switch (value.toUpperCase()) {
      'CAMERA_MAINTENANCE' => TechnicianJobType.cameraMaintenance,
      'GATE_MOTOR_INSTALLATION' => TechnicianJobType.gateMotorInstallation,
      'GATE_MOTOR_MAINTENANCE' => TechnicianJobType.gateMotorMaintenance,
      _ => TechnicianJobType.cameraInstallation,
    };
  }

  static String _apiJobStatus(TechnicianJobStatus value) => switch (value) {
    TechnicianJobStatus.pending => 'PENDING',
    TechnicianJobStatus.inProgress => 'IN_PROGRESS',
    TechnicianJobStatus.completed => 'COMPLETED',
    TechnicianJobStatus.cancelled => 'CANCELLED',
  };

  static TechnicianJobStatus _jobStatusFromApi(String value) {
    return switch (value.toUpperCase()) {
      'IN_PROGRESS' => TechnicianJobStatus.inProgress,
      'COMPLETED' => TechnicianJobStatus.completed,
      'CANCELLED' => TechnicianJobStatus.cancelled,
      _ => TechnicianJobStatus.pending,
    };
  }

  static String s(Map<String, dynamic> json, String key) =>
      (json[key] ?? '').toString();

  static int i(Object? value) {
    if (value is int) return value;
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  static double d(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString()) ?? 0;
  }

  static bool b(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return value.toString().toLowerCase() == 'true';
  }

  static DateTime? dt(Object? value) {
    final raw = (value ?? '').toString().trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  static List<String> list(Object? value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList(growable: false);
    }
    return const [];
  }

  static String _newId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}';

  static String _digits(String value) =>
      value.replaceAll(RegExp(r'[^0-9]'), '');
}
