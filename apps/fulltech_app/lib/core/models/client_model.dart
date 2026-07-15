class ClientModel {
  final String id;
  final String nombre;
  final String telefono;
  final String? email;
  final String? direccion;
  final String? locationUrl;
  final String? notas;

  const ClientModel({
    required this.id,
    required this.nombre,
    required this.telefono,
    this.email,
    this.direccion,
    this.locationUrl,
    this.notas,
  });

  factory ClientModel.fromJson(Map<String, dynamic> json) {
    return ClientModel(
      id: json['id'] ?? '',
      nombre: json['nombre'] ?? json['name'] ?? '',
      telefono: json['telefono'] ?? '',
      email: json['email'] as String?,
      direccion: json['direccion'] as String? ?? json['address'] as String?,
      locationUrl:
          json['locationUrl'] as String? ?? json['location_url'] as String?,
      notas: json['notas'] as String? ?? json['notes'] as String?,
    );
  }
}
