import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'url_helper.dart';

class ImageSaver {
  static Future<String?> saveUrl(String url, {String? fileName}) async {
    return saveImage(url, fileName: fileName);
  }

  static Future<String?> saveImage(String imageUrl, {String? fileName}) async {
    try {
      final fullUrl = resolveMediaUrl(imageUrl);
      final response = await Dio().get(
        fullUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data as Uint8List;

      String savePath;
      if (Platform.isWindows) {
        final home = Platform.environment['USERPROFILE'];
        if (home != null && home.isNotEmpty) {
          final downloads = Directory('$home\\Downloads');
          if (!await downloads.exists()) {
            await downloads.create(recursive: true);
          }
          final name = fileName ??
              'oldchat_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final file = File('${downloads.path}\\$name');
          await file.writeAsBytes(bytes);
          savePath = file.path;
        } else {
          final docs = await getApplicationDocumentsDirectory();
          final name = fileName ??
              'oldchat_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final file = File('${docs.path}/$name');
          await file.writeAsBytes(bytes);
          savePath = file.path;
        }
      } else {
        final docs = await getApplicationDocumentsDirectory();
        final name = fileName ??
            'oldchat_image_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File('${docs.path}/$name');
        await file.writeAsBytes(bytes);
        savePath = file.path;
      }
      return savePath;
    } catch (e) {
      print('图片保存失败: $e');
      return null;
    }
  }
}
