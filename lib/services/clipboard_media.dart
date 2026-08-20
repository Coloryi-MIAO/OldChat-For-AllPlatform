import 'dart:typed_data';

class ClipboardMedia {
  final String name;
  final Uint8List bytes;

  const ClipboardMedia({required this.name, required this.bytes});
}
