import 'dart:io';

Future<List<String>> clipboardFilePaths() async {
  if (!Platform.isWindows) return const <String>[];
  return const <String>[];
}
