import 'dart:typed_data';
import 'dart:html' as html;

class WebBlobReader {
  static Future<Uint8List> readBlobBytes(String url) async {
    final request = await html.HttpRequest.request(
      url,
      method: 'GET',
      responseType: 'arraybuffer',
    );
    
    final response = request.response;
    if (response is ByteBuffer) {
      return response.asUint8List();
    }
    if (response is List<int>) {
      return Uint8List.fromList(response);
    }
    throw StateError('Response is not a ByteBuffer or List<int>: ${response.runtimeType}');
  }
}
