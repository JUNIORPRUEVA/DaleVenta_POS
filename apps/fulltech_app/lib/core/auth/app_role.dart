import 'package:flutter/foundation.dart';

/// Single source of truth for roles on the Flutter side.
///
/// Backend uses Prisma enum-like roles (e.g. `ADMIN`, `TECNICO`).
/// Some legacy payloads may contain synonyms (e.g. `technician`, `técnico`).
/// We normalize those here so the rest of the app never compares raw strings.
enum AppRole { admin, asistente, vendedor, marketing, tecnico, unknown }

String _stripDiacritics(String input) {
  // Minimal normalization without extra deps.
  // Covers the common Spanish diacritics used in role labels.
  return input
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ñ', 'n');
}

String normalizeRoleKey(String? raw) {
  if (raw == null) return '';
  var v = raw.trim();
  if (v.isEmpty) return '';
  v = v.toLowerCase();
  v = _stripDiacritics(v);
  v = v.replaceAll('role_', '');
  v = v.replaceAll('roles_', '');
  v = v.replaceAll('-', '_').replaceAll(' ', '_');
  return v;
}

AppRole parseAppRole(String? raw) {
  final key = normalizeRoleKey(raw);
  switch (key) {
    case 'admin':
      return AppRole.admin;
    case 'asistente':
    case 'assistant':
      return AppRole.asistente;
    case 'vendedor':
    case 'sales':
    case 'seller':
      return AppRole.vendedor;
    case 'marketing':
      return AppRole.marketing;
    case 'tecnico':
    case 'tecnica':
    case 'technician':
    case 'tech':
      return AppRole.tecnico;
    default:
      return AppRole.unknown;
  }
}

String toApiRole(AppRole role) {
  switch (role) {
    case AppRole.admin:
      return 'ADMIN';
    case AppRole.asistente:
      return 'ASISTENTE';
    case AppRole.vendedor:
      return 'VENDEDOR';
    case AppRole.marketing:
      return 'MARKETING';
    case AppRole.tecnico:
      return 'TECNICO';
    case AppRole.unknown:
      return '';
  }
}

extension AppRoleX on AppRole {
  bool get isAdmin => this == AppRole.admin;
  bool get isTechnician => this == AppRole.tecnico;

  String get label {
    switch (this) {
      case AppRole.admin:
        return 'Administrador';
      case AppRole.asistente:
        return 'Asistente';
      case AppRole.vendedor:
        return 'Vendedor';
      case AppRole.marketing:
        return 'Marketing';
      case AppRole.tecnico:
        return 'Técnico';
      case AppRole.unknown:
        return kReleaseMode ? '' : 'Unknown';
    }
  }
}
