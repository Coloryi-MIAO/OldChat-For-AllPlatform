import 'clipboard_media.dart';
import 'clipboard_media_service_stub.dart'
    if (dart.library.io) 'clipboard_media_service_io.dart';

export 'clipboard_media.dart';

Future<List<ClipboardMedia>> clipboardFileMedia() => readClipboardFileMedia();

Future<ClipboardMedia?> clipboardImageMedia() => readClipboardImageMedia();
