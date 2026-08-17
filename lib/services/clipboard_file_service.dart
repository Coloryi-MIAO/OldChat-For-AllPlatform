import 'clipboard_file_service_stub.dart'
    if (dart.library.io) 'clipboard_file_service_io.dart';

class ClipboardFileService {
  static Future<List<String>> paths() => clipboardFilePaths();
}
