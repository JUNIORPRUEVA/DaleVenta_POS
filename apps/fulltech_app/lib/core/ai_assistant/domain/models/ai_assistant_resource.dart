/// Approved library metadata. No remote URL, storage key or integration credential.
class AiAssistantResource {
  const AiAssistantResource({
    required this.id,
    required this.title,
    required this.kind,
    required this.mimeType,
    required this.fileName,
    required this.sizeBytes,
    this.version = 1,
  });
  final String id, title, kind, mimeType, fileName;
  final int sizeBytes, version;
  bool get isImage => kind == 'IMAGE';
  bool get isVideo => kind == 'VIDEO';

  static AiAssistantResource? fromMap(dynamic value) {
    if (value is! Map) return null;
    final id = value['id'], title = value['title'], mime = value['mimeType'];
    final size = value['sizeBytes'], fileName = value['fileName'];
    if (id is! String ||
        !RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ).hasMatch(id) ||
        title is! String ||
        title.trim().isEmpty ||
        fileName is! String ||
        size is! int ||
        size <= 0 ||
        size > 32 * 1024 * 1024 ||
        !const {
          'image/png',
          'image/jpeg',
          'image/webp',
          'video/mp4',
          'video/webm',
          'application/pdf',
          'text/plain',
        }.contains(mime)) {
      return null;
    }
    final type = (mime as String).startsWith('image/')
        ? 'IMAGE'
        : mime.startsWith('video/')
        ? 'VIDEO'
        : 'DOCUMENT';
    if (value['kind'] != type) return null;
    final version = value['version'];
    return AiAssistantResource(
      id: id,
      title: title,
      kind: type,
      mimeType: mime,
      fileName: fileName.replaceAll(RegExp(r'[\\/\r\n]'), '_'),
      sizeBytes: size,
      version: version is int && version > 0 ? version : 1,
    );
  }
}
