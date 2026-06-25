// Conditional export for WebBlobReader.
// Selects the appropriate implementation depending on whether JS libraries are available (Web vs Native).

export 'web_blob_reader_stub.dart'
    if (dart.library.js_util) 'web_blob_reader_web.dart';
