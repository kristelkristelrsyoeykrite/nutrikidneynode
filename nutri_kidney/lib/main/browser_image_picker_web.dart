import 'dart:async';
import 'dart:html' as html;
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

  reader.readAsArrayBuffer(file);
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

  return BrowserPickedImage(
    bytes: bytes,
    name: file.name,
    mimeType: file.type.isNotEmpty ? file.type : _mimeTypeFromName(file.name),
  );
}

String _mimeTypeFromName(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  return 'image/jpeg';
}
