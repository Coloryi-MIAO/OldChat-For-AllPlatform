import 'package:universal_io/io.dart';
import 'package:flutter/widgets.dart';

typedef FileHandle = File;
ImageProvider fileImage(FileHandle file) => FileImage(file);
