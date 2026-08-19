import 'package:flutter/widgets.dart';

typedef FileHandle = Object;
ImageProvider fileImage(FileHandle file) =>
    throw UnsupportedError('File images are unavailable on web');
