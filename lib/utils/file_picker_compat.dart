import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' as picker;

export 'package:file_picker/file_picker.dart'
    show FilePicker, FileType, PlatformFile;

Future<picker.FilePickerResult?> pickFilesCompat({
  picker.FileType type = picker.FileType.any,
  List<String>? allowedExtensions,
  bool allowMultiple = false,
  bool withData = false,
}) => picker.FilePicker.platform.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
      withData: withData,
    );

Future<String?> saveFileCompat({
  String? dialogTitle,
  String? fileName,
  String? initialDirectory,
  picker.FileType type = picker.FileType.any,
  List<String>? allowedExtensions,
  Uint8List? bytes,
}) => picker.FilePicker.platform.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      initialDirectory: initialDirectory,
      type: type,
      allowedExtensions: allowedExtensions,
      bytes: bytes,
    );

Future<String?> getDirectoryPathCompat({
  String? dialogTitle,
  String? initialDirectory,
}) => picker.FilePicker.platform.getDirectoryPath(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
    );

List<picker.PlatformFile> filePickerFiles(Object? result) {
  if (result is picker.FilePickerResult) return result.files;
  if (result is picker.PlatformFile) return <picker.PlatformFile>[result];
  if (result is Iterable) {
    return List<picker.PlatformFile>.unmodifiable(
      result.whereType<picker.PlatformFile>(),
    );
  }
  return const <picker.PlatformFile>[];
}

Future<Uint8List?> filePickerBytes(picker.PlatformFile file) async {
  if (file.bytes != null) return file.bytes;
  final path = file.path;
  if (path == null || path.isEmpty) return null;
  try {
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

String? filePickerPath(Object? result) {
  if (result == null) return null;
  if (result is picker.PlatformFile) return _clean(result.path);
  if (result is Uri) {
    final value = result.scheme == 'file'
        ? result.toFilePath()
        : result.toString();
    return _clean(value);
  }
  return _clean(result.toString());
}

String? _clean(String? value) {
  final normalized = value?.trim() ?? '';
  return normalized.isEmpty ? null : normalized;
}
