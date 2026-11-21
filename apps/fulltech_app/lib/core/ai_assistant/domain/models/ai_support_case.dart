class AiSupportCase {
  const AiSupportCase({required this.id, required this.reference});
  final String id;
  final String reference;

  static AiSupportCase? fromMap(dynamic value) {
    if (value is! Map || value['id'] is! String || value['reference'] is! String) return null;
    final id = value['id'] as String;
    final reference = value['reference'] as String;
    if (!RegExp(r'^[\w-]{1,80}$').hasMatch(id) || reference.isEmpty) return null;
    return AiSupportCase(id: id, reference: reference);
  }
}
