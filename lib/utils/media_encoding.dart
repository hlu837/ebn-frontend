import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

/// Picks a photo from the gallery and returns it encoded as a
/// `data:<mime>;base64,...` string.
///
/// Why: the backend has no upload/storage route (no multer, S3,
/// Cloudinary, etc — see `sell_request_controller.dart`), and it's
/// deployed as a Vercel serverless function with no persistent disk, so
/// there's nowhere to save a plain uploaded file even if we added one
/// today. Embedding the compressed photo directly as a data URL is the
/// same approach already used for agent avatars (see
/// `agent_visibility_profile_screen.dart`) — the string is self-contained,
/// works identically on web and mobile, and needs no new infrastructure.
///
/// `maxWidth`/`maxHeight`/`imageQuality` keep the encoded size reasonable
/// (this endpoint stores the result as a plain TEXT column). Returns null
/// if the user cancelled the picker. Throws [FormatException] if the
/// resulting payload is still over [maxBytes] — callers should catch this
/// and show the message to the user.
///
/// TODO: swap this out for a real upload (returning a hosted URL) once a
/// storage backend exists — nothing else needs to change, since
/// [dataUrlOrNetworkImage] already renders plain https URLs too.
Future<String?> pickAndEncodeImage({
  ImageSource source = ImageSource.gallery,
  int maxWidth = 1200,
  int maxHeight = 1200,
  int imageQuality = 80,
  int maxBytes = 4 * 1024 * 1024,
}) async {
  final picker = ImagePicker();
  final file = await picker.pickImage(
    source: source,
    maxWidth: maxWidth.toDouble(),
    maxHeight: maxHeight.toDouble(),
    imageQuality: imageQuality,
  );
  if (file == null) return null;

  final bytes = await file.readAsBytes();
  if (bytes.length > maxBytes) {
    throw FormatException(
        'Please choose an image smaller than ${(maxBytes / (1024 * 1024)).toStringAsFixed(0)} MB.');
  }
  final mimeType = file.mimeType ?? 'image/jpeg';
  return 'data:$mimeType;base64,${base64Encode(bytes)}';
}

/// Turns a stored media reference into an [ImageProvider] that renders on
/// every platform — including Flutter Web, where `Image.file`/`dart:io`
/// isn't available at all.
///
/// Handles both shapes [ReportMediaItem.filePath] (or any similar stored
/// image string) can be:
///  - `data:<mime>;base64,<...>` — produced by [pickAndEncodeImage].
///  - a plain `http(s)://` URL, for images already hosted somewhere.
///
/// Returns null for anything else — notably including old local device
/// paths (e.g. `/data/user/0/.../img.jpg` or a web `blob:` URL) saved by
/// this app before this fix, which were never valid outside the device
/// that picked them and can't be recovered.
///
/// Caches the resulting [ImageProvider] per `filePath` string. This matters
/// for `data:` URIs: [MemoryImage] compares its `bytes` field by identity
/// (`Uint8List` has no structural `==`), so calling `base64Decode` fresh on
/// every build hands Flutter a "new" image each time — even though the
/// content is unchanged — which flickers/reloads the picture on every
/// rebuild (e.g. once a second on screens with a countdown or poll timer).
/// Reusing the same provider instance for the same string keeps `==` true
/// across rebuilds so Flutter recognizes it as already-loaded.
final Map<String, ImageProvider<Object>> _dataUrlImageCache = {};

ImageProvider<Object>? dataUrlOrNetworkImage(String? filePath) {
  if (filePath == null || filePath.isEmpty) return null;

  final cached = _dataUrlImageCache[filePath];
  if (cached != null) return cached;

  ImageProvider<Object>? provider;
  if (filePath.startsWith('data:')) {
    final comma = filePath.indexOf(',');
    if (comma != -1) {
      try {
        provider = MemoryImage(base64Decode(filePath.substring(comma + 1)));
      } catch (_) {
        provider = null;
      }
    }
  } else if (filePath.startsWith('http://') ||
      filePath.startsWith('https://')) {
    provider = NetworkImage(filePath);
  }

  if (provider != null) {
    // Keep the cache from growing without bound over a long session.
    if (_dataUrlImageCache.length > 200) _dataUrlImageCache.clear();
    _dataUrlImageCache[filePath] = provider;
  }
  return provider;
}
