import 'dart:io';
import 'package:flutter/widgets.dart';

typedef FileHandle = File;
ImageProvider fileImage(FileHandle file) => FileImage(file);
