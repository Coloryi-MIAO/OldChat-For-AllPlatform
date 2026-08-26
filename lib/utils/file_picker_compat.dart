import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

export 'package:file_picker/file_picker.dart'
    show FilePicker, FileType, PlatformFile;

Future<FilePickerResult?> pickFilesCompat({
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  bool allowMultiple = false,
  bool withData = false,
}) => FilePicker.pickFiles(
      type: type,
      allowedExtensions: allowedExtensions,
      allowMultiple: allowMultiple,
      withData: withData,
    );

Future<String?> saveFileCompat({
  String? dialogTitle,
  String? fileName,
  String? initialDirectory,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  Uint8List? bytes,
}) async {
  final String fileNameNonNull = fileName ?? '';
  Uri? uri;
  if (bytes != null) {
    uri = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileNameNonNull,
      initialDirectory: initialDirectory,
      type: type,
      allowedExtensions: allowedExtensions,
      bytes: bytes,
    );
  } else {
    uri = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileNameNonNull,
      initialDirectory: initialDirectory,
      type: type,
      allowedExtensions: allowedExtensions,
    );
  }
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
  if (result is FilePickerResult) return result.files;
  if (result is PlatformFile) return <PlatformFile>[result];
  if (result is Iterable) {
    return List<PlatformFile>.unmodifiable(
      result.whereType<PlatformFile>(),
    );
  }
  return const <PlatformFile>[];
}

Future<Uint8List?> filePickerBytes(PlatformFile file) async {
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
  if (result is PlatformFile) return _clean(result.path);
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