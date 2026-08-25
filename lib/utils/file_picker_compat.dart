import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' as picker;

export 'package:file_picker/file_picker.dart'
    show FilePicker, FileType, PlatformFile;

Future<List<picker.PlatformFile>> pickFilesCompat({
  picker.FileType type = picker.FileType.any,
  List<String>? allowedExtensions,
  bool allowMultiple = false,
  bool withData = false,
}) => picker.FilePicker.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
      withData: withData,
    );

Future<Uri?> saveFileCompat({
  String? dialogTitle,
  required String fileName,
  String? initialDirectory,
  picker.FileType type = picker.FileType.any,
  List<String>? allowedExtensions,
  required Uint8List bytes,
}) => picker.FilePicker.saveFile(
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
}) => picker.FilePicker.getDirectoryPath(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
    );

List<picker.PlatformFile> filePickerFiles(Object? result) {
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
