/// Error del respaldo previo a una migración de esquema.
///
/// Vive en su propio fichero para estar disponible en TODAS las plataformas:
/// el respaldo real solo existe con almacenamiento nativo (`dart:io`), pero la
/// app y las pruebas necesitan el tipo también fuera de esa condición.
///
/// Contrato: cuando se lanza esta excepción, la base ORIGINAL no se ha
/// modificado ni eliminado; solo pueden quedar restos temporales, que se
/// intentan limpiar antes de propagar el error.
class LocalMigrationBackupException implements Exception {
  const LocalMigrationBackupException(
    this.fileName,
    this.reason, {
    this.details,
  });

  final String fileName;
  final String reason;
  final String? details;

  @override
  String toString() {
    final suffix = details == null ? '' : ' ($details)';
    return 'LocalMigrationBackupException($fileName): $reason$suffix';
  }
}
