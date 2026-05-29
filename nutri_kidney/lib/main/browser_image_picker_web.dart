import 'dart:async';
import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:typed_data';

const int _maxImageDimension = 1280;
const double _jpegQuality = 0.78;

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
  final input = html.FileUploadInputElement()
    ..accept = 'image/png,image/jpeg,image/jpg,image/webp'
    ..multiple = false
    ..style.display = 'none';
  html.document.body?.append(input);

  final completer = Completer<List<html.File>?>();
  late final StreamSubscription<html.Event> subscription;
  subscription = input.onChange.listen((_) {
    if (!completer.isCompleted) {
      completer.complete(input.files);
    }
    subscription.cancel();
  });

  List<html.File>? files;
  try {
    input.click();
    files = await completer.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        subscription.cancel();
        return null;
      },
    );
  } finally {
    input.remove();
  }

  if (files == null || files.isEmpty) return null;

  final file = files.first;
  final compressedBytes = await _resizeImageFile(file);

  return BrowserPickedImage(
    bytes: compressedBytes,
    name: _jpegName(file.name),
    mimeType: 'image/jpeg',
  );
}

Future<Uint8List> _resizeImageFile(html.File file) async {
  final objectUrl = html.Url.createObjectUrl(file);
  final image = html.ImageElement(src: objectUrl);
  final imageLoaded = Completer<void>();
  late final StreamSubscription<html.Event> loadSubscription;
  late final StreamSubscription<html.Event> errorSubscription;

  loadSubscription = image.onLoad.listen((_) {
    if (!imageLoaded.isCompleted) imageLoaded.complete();
  });
  errorSubscription = image.onError.listen((_) {
    if (!imageLoaded.isCompleted) {
      imageLoaded.completeError(Exception('Unable to load selected image.'));
    }
  });

  try {
    await imageLoaded.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        throw Exception('Selected image took too long to load.');
      },
    );
  } finally {
    await loadSubscription.cancel();
    await errorSubscription.cancel();
    html.Url.revokeObjectUrl(objectUrl);
  }

  final sourceWidth = image.naturalWidth;
  final sourceHeight = image.naturalHeight;
  if (sourceWidth <= 0 || sourceHeight <= 0) {
    return _readBlobAsBytes(file);
  }

  final scale = math.min(
    1.0,
    _maxImageDimension / math.max(sourceWidth, sourceHeight),
  );
  final targetWidth = math.max(1, (sourceWidth * scale).round());
  final targetHeight = math.max(1, (sourceHeight * scale).round());

  final canvas = html.CanvasElement(width: targetWidth, height: targetHeight);
  final context = canvas.context2D;
  context.fillStyle = 'white';
  context.fillRect(0, 0, targetWidth, targetHeight);
  context.drawImageScaled(image, 0, 0, targetWidth, targetHeight);

  return _bytesFromDataUrl(canvas.toDataUrl('image/jpeg', _jpegQuality));
}

Future<Uint8List> _readBlobAsBytes(html.Blob blob) async {
  final reader = html.FileReader();
  final loadCompleter = Completer<void>();
  late final StreamSubscription<html.ProgressEvent> loadSubscription;
  late final StreamSubscription<html.ProgressEvent> errorSubscription;

  loadSubscription = reader.onLoad.listen((_) {
    if (!loadCompleter.isCompleted) loadCompleter.complete();
  });
  errorSubscription = reader.onError.listen((_) {
    if (!loadCompleter.isCompleted) {
      loadCompleter.completeError(Exception('Unable to read selected image.'));
    }
  });

  reader.readAsArrayBuffer(blob);
  await loadCompleter.future;
  await loadSubscription.cancel();
  await errorSubscription.cancel();

  final result = reader.result;
  final bytes = result is ByteBuffer
      ? result.asUint8List()
      : result is Uint8List
          ? result
          : null;

  if (bytes == null) {
    throw Exception('Selected image could not be read by the browser.');
  }

  return bytes;
}

Uint8List _bytesFromDataUrl(String dataUrl) {
  final commaIndex = dataUrl.indexOf(',');
  if (commaIndex == -1) {
    throw Exception('Selected image could not be compressed.');
  }
  final base64Data = dataUrl.substring(commaIndex + 1);
  return Uint8List.fromList(html.window.atob(base64Data).codeUnits);
}

String _jpegName(String name) {
  final dotIndex = name.lastIndexOf('.');
  final baseName = dotIndex > 0 ? name.substring(0, dotIndex) : name;
  return '$baseName.jpg';
}
