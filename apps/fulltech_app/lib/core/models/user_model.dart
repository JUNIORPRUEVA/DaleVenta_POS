import '../auth/app_role.dart';

class UserModel {
  final String id;
  final String email;
  final String nombreCompleto;
  final String telefono;
  final String? numeroFlota;
  final String? cedula;
  final String? telefonoFamiliar;
  final String? fotoCedulaUrl;
  final String? fotoLicenciaUrl;
  final String? fotoPersonalUrl;
  final String? workContractSignatureUrl;
  final DateTime? workContractSignedAt;
  final String? workContractVersion;
  final String? workContractJobTitle;
  final String? workContractSalary;
  final String? workContractPaymentFrequency;
  final String? workContractPaymentMethod;
  final String? workContractWorkSchedule;
  final String? workContractWorkLocation;
  final Map<String, String> workContractClauseOverrides;
  final String? workContractCustomClauses;
  final DateTime? workContractStartDate;
  final String? experienciaLaboral;
  final DateTime? fechaIngreso;
  final DateTime? fechaNacimiento;
  final String? cuentaNominaPreferencial;
  final List<String> habilidades;
  final Map<String, bool> userPermissions;
  final String? role;
  final bool blocked;
  final int? edad;
  final bool tieneHijos;
  final bool estaCasado;
  final bool casaPropia;
  final bool vehiculo;
  final bool licenciaConducir;
  final DateTime? createdAt;

  UserModel({
    required this.id,
    required this.email,
    required this.nombreCompleto,
    required this.telefono,
    this.numeroFlota,
    this.cedula,
    this.telefonoFamiliar,
    this.fotoCedulaUrl,
    this.fotoLicenciaUrl,
    this.fotoPersonalUrl,
    this.workContractSignatureUrl,
    this.workContractSignedAt,
    this.workContractVersion,
    this.workContractJobTitle,
    this.workContractSalary,
    this.workContractPaymentFrequency,
    this.workContractPaymentMethod,
    this.workContractWorkSchedule,
    this.workContractWorkLocation,
    this.workContractClauseOverrides = const {},
    this.workContractCustomClauses,
    this.workContractStartDate,
    this.experienciaLaboral,
    this.fechaIngreso,
    this.fechaNacimiento,
    this.cuentaNominaPreferencial,
    this.habilidades = const [],
    this.userPermissions = const {},
    this.role,
    this.blocked = false,
    this.edad,
    this.tieneHijos = false,
    this.estaCasado = false,
    this.casaPropia = false,
    this.vehiculo = false,
    this.licenciaConducir = false,
    this.createdAt,
  });

  /// Normalized, typed role for consistent permission checks.
  /// Avoid comparing [role] raw strings across the app.
  AppRole get appRole => parseAppRole(role);

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final habilidadesRaw = json['habilidades'];
    final habilidades = habilidadesRaw is List
        ? habilidadesRaw
              .whereType<String>()
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    final clauseOverridesRaw = json['workContractClauseOverrides'];
    final clauseOverrides = clauseOverridesRaw is Map
        ? clauseOverridesRaw.entries
              .where((entry) => entry.key is String && entry.value is String)
              .map(
                (entry) => MapEntry(
                  entry.key as String,
                  (entry.value as String).trim(),
                ),
              )
              .where(
                (entry) =>
                    entry.key.trim().isNotEmpty && entry.value.isNotEmpty,
              )
              .fold<Map<String, String>>(<String, String>{}, (map, entry) {
                map[entry.key.trim()] = entry.value;
                return map;
              })
        : <String, String>{};
    final permissionsRaw = json['userPermissions'];
    final permissions = permissionsRaw is Map
        ? permissionsRaw.map(
            (key, value) => MapEntry(key.toString(), value == true),
          )
        : <String, bool>{};

    return UserModel(
      id: json['id'] ?? '',
      email: json['email'] ?? '',
      nombreCompleto: json['nombreCompleto'] ?? json['nombre'] ?? '',
      telefono: json['telefono'] ?? '',
      numeroFlota: json['numeroFlota'],
      cedula: json['cedula'],
      telefonoFamiliar: json['telefonoFamiliar'],
      fotoCedulaUrl: json['fotoCedulaUrl'],
      fotoLicenciaUrl: json['fotoLicenciaUrl'],
      fotoPersonalUrl: json['fotoPersonalUrl'],
      workContractSignatureUrl: json['workContractSignatureUrl'],
      workContractSignedAt: json['workContractSignedAt'] != null
          ? DateTime.tryParse(json['workContractSignedAt'])
          : null,
      workContractVersion: json['workContractVersion'],
      workContractJobTitle: json['workContractJobTitle'],
      workContractSalary: json['workContractSalary'],
      workContractPaymentFrequency: json['workContractPaymentFrequency'],
      workContractPaymentMethod: json['workContractPaymentMethod'],
      workContractWorkSchedule: json['workContractWorkSchedule'],
      workContractWorkLocation: json['workContractWorkLocation'],
      workContractClauseOverrides: clauseOverrides,
      workContractCustomClauses: json['workContractCustomClauses'],
      workContractStartDate: json['workContractStartDate'] != null
          ? DateTime.tryParse(json['workContractStartDate'])
          : null,
      experienciaLaboral: json['experienciaLaboral'],
      fechaIngreso: json['fechaIngreso'] != null
          ? DateTime.tryParse(json['fechaIngreso'])
          : null,
      fechaNacimiento: json['fechaNacimiento'] != null
          ? DateTime.tryParse(json['fechaNacimiento'])
          : null,
      cuentaNominaPreferencial: json['cuentaNominaPreferencial'],
      habilidades: habilidades,
      userPermissions: permissions,
      role: json['role'] ?? json['rol'] ?? 'CAJERO',
      blocked: json['blocked'] ?? false,
      edad: json['edad'],
      tieneHijos: json['tieneHijos'] ?? false,
      estaCasado: json['estaCasado'] ?? false,
      casaPropia: json['casaPropia'] ?? false,
      vehiculo: json['vehiculo'] ?? false,
      licenciaConducir: json['licenciaConducir'] ?? false,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'])
          : null,
    );
  }

  int? get diasEnEmpresa {
    if (fechaIngreso == null) return null;
    final start = DateTime(
      fechaIngreso!.year,
      fechaIngreso!.month,
      fechaIngreso!.day,
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(start).inDays;
    return diff < 0 ? 0 : diff;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'nombreCompleto': nombreCompleto,
      'telefono': telefono,
      'numeroFlota': numeroFlota,
      'cedula': cedula,
      'telefonoFamiliar': telefonoFamiliar,
      'fotoCedulaUrl': fotoCedulaUrl,
      'fotoLicenciaUrl': fotoLicenciaUrl,
      'fotoPersonalUrl': fotoPersonalUrl,
      'workContractSignatureUrl': workContractSignatureUrl,
      'workContractSignedAt': workContractSignedAt?.toIso8601String(),
      'workContractVersion': workContractVersion,
      'workContractJobTitle': workContractJobTitle,
      'workContractSalary': workContractSalary,
      'workContractPaymentFrequency': workContractPaymentFrequency,
      'workContractPaymentMethod': workContractPaymentMethod,
      'workContractWorkSchedule': workContractWorkSchedule,
      'workContractWorkLocation': workContractWorkLocation,
      'workContractClauseOverrides': workContractClauseOverrides,
      'workContractCustomClauses': workContractCustomClauses,
      'workContractStartDate': workContractStartDate?.toIso8601String(),
      'experienciaLaboral': experienciaLaboral,
      'fechaIngreso': fechaIngreso?.toIso8601String(),
      'fechaNacimiento': fechaNacimiento?.toIso8601String(),
      'cuentaNominaPreferencial': cuentaNominaPreferencial,
      'habilidades': habilidades,
      'userPermissions': userPermissions,
      'role': role,
      'blocked': blocked,
      'edad': edad,
      'tieneHijos': tieneHijos,
      'estaCasado': estaCasado,
      'casaPropia': casaPropia,
      'vehiculo': vehiculo,
      'licenciaConducir': licenciaConducir,
      'createdAt': createdAt?.toIso8601String(),
    };
  }
}
