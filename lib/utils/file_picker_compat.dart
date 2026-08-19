import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' as picker;

export 'package:file_picker/file_picker.dart'
    show FilePicker, FileType, PlatformFile;

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
