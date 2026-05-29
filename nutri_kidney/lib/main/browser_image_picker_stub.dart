import 'dart:typed_data';

class BrowserPickedImage {
  const BrowserPickedImage({
    required this.bytes,
    required this.name,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String name;
  final String mimeType;
}

Future<BrowserPickedImage?> pickBrowserImage() async {
  return null;
}
