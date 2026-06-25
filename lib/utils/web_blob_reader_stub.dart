import 'dart:typed_data';

class WebBlobReader {
  static Future<Uint8List> readBlobBytes(String url) async {
    throw UnsupportedError('readBlobBytes is only supported on Web');
  }
}
