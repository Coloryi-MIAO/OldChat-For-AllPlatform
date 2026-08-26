import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

export 'package:file_picker/file_picker.dart'
    show FilePicker, FileType, PlatformFile;

Future<List<PlatformFile>> pickFilesCompat({
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  bool allowMultiple = false,
  bool withData = false,
}) async {
  if (!allowMultiple) {
    final file = await FilePicker.pickFile(
      type: type,
      allowedExtensions: allowedExtensions,
    );
    return file != null ? [file] : [];
  }
  return FilePicker.pickFiles(
    type: type,
    allowedExtensions: allowedExtensions,
    allowMultiple: true,
    withData: withData,
  );
}

Future<String?> saveFileCompat({
  String? dialogTitle,
  String? fileName,
  String? initialDirectory,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  Uint8List? bytes,
}) async {
  final uri = await FilePicker.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName ?? '',
    initialDirectory: initialDirectory,
    type: type,
    allowedExtensions: allowedExtensions,
    bytes: bytes ?? Uint8List(0),
  );
  return uri?.toFilePath();
}

Future<String?> getDirectoryPathCompat({
  String? dialogTitle,
  String? initialDirectory,
}) => FilePicker.getDirectoryPath(
      dialogTitle: dialogTitle,
      initialDirectory: initialDirectory,
    );

List<PlatformFile> filePickerFiles(Object? result) {
  if (result is List<PlatformFile>) return result;
  if (result is PlatformFile) return <PlatformFile>[result];
  if (result is Iterable) {
    return List<PlatformFile>.unmodifiable(
      result.whereType<PlatformFile>(),
    );
  }
  return const <PlatformFile>[];
}

Future<Uint8List?> filePickerBytes(PlatformFile file) async {
  try {
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

String? filePickerPath(Object? result) {
  if (result == null) return null;
  if (result is PlatformFile) return _clean(result.path);
  if (result is List<PlatformFile> && result.isNotEmpty) {
    return _clean(result.first.path);
  }
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