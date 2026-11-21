import 'package:file_picker/file_picker.dart';

/// Only replaces OS file selection. Upload validation/transport are not mocked.
class PlansTestFilePicker extends FilePicker {
  PlansTestFilePicker(this.select);
  final Future<FilePickerResult?> Function() select;
  int calls = 0;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    calls++;
    return select();
  }
}
