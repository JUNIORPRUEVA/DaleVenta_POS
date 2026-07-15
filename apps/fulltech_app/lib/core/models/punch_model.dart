import 'user_model.dart';

enum PunchType {
  entradaLabor,
  salidaLabor,
  salidaPermiso,
  entradaPermiso,
  salidaAlmuerzo,
  entradaAlmuerzo,
}

PunchType _fromApi(String value) {
  switch (value.toUpperCase()) {
    case 'ENTRADA_LABOR':
      return PunchType.entradaLabor;
    case 'SALIDA_LABOR':
      return PunchType.salidaLabor;
    case 'SALIDA_PERMISO':
      return PunchType.salidaPermiso;
    case 'ENTRADA_PERMISO':
      return PunchType.entradaPermiso;
    case 'SALIDA_ALMUERZO':
      return PunchType.salidaAlmuerzo;
    case 'ENTRADA_ALMUERZO':
      return PunchType.entradaAlmuerzo;
    default:
      return PunchType.entradaLabor;
  }
}

extension PunchTypeX on PunchType {
  String get apiValue {
    switch (this) {
      case PunchType.entradaLabor:
        return 'ENTRADA_LABOR';
      case PunchType.salidaLabor:
        return 'SALIDA_LABOR';
      case PunchType.salidaPermiso:
        return 'SALIDA_PERMISO';
      case PunchType.entradaPermiso:
        return 'ENTRADA_PERMISO';
      case PunchType.salidaAlmuerzo:
        return 'SALIDA_ALMUERZO';
      case PunchType.entradaAlmuerzo:
        return 'ENTRADA_ALMUERZO';
    }
  }

  String get label {
    switch (this) {
      case PunchType.entradaLabor:
        return 'Entrada jornada';
      case PunchType.salidaLabor:
        return 'Salida jornada';
      case PunchType.salidaPermiso:
        return 'Salida permiso';
      case PunchType.entradaPermiso:
        return 'Entrada permiso';
      case PunchType.salidaAlmuerzo:
        return 'Salida almuerzo';
      case PunchType.entradaAlmuerzo:
        return 'Entrada almuerzo';
    }
  }
}

class PunchModel {
  final String id;
  final PunchType type;
  final DateTime timestamp;
  final DateTime createdAt;
  final UserModel? user;

  PunchModel({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.createdAt,
    this.user,
  });

  factory PunchModel.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'];
    return PunchModel(
      id: json['id'] ?? '',
      type: _fromApi(json['type'] ?? ''),
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      createdAt:
          DateTime.tryParse(json['createdAt'] ?? json['timestamp'] ?? '') ??
          DateTime.now(),
      user: userJson is Map<String, dynamic>
          ? UserModel.fromJson(userJson)
          : null,
    );
  }
}
