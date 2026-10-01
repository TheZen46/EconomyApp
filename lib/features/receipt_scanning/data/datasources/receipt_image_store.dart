import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Keeps receipt images in the application documents directory.
///
/// image_picker returns captures in the cache or temporary directory, which
/// the operating system may purge, so the path it returns cannot be stored
/// as the receipt's image. Images are copied to `receipt_images/<receipt id>`
/// with their original extension, which the cloud upload also uses.
class ReceiptImageStore {
  static const String folderName = 'receipt_images';

  final Future<Directory> Function() _documentsDirectory;

  ReceiptImageStore({@visibleForTesting Future<Directory> Function()? documentsDirectory})
      : _documentsDirectory = documentsDirectory ?? getApplicationDocumentsDirectory;

  /// Copies the image at [sourcePath] into the store under [receiptId] and
  /// returns the stored path.
  ///
  /// Returns [sourcePath] unchanged when it is empty, remote (http, blob),
  /// already in the store, unreadable, or on web, where there is no file
  /// system to copy to.
  Future<String> persist(String receiptId, String sourcePath) async {
    if (kIsWeb || sourcePath.isEmpty || sourcePath.contains('://') || sourcePath.startsWith('blob:')) {
      return sourcePath;
    }
    try {
      final folder = await _folder();
      if (_isInside(sourcePath, folder)) return sourcePath;

      final source = File(sourcePath);
      if (!await source.exists()) return sourcePath;

      final dot = sourcePath.lastIndexOf('.');
      final slash = sourcePath.lastIndexOf(Platform.pathSeparator);
      final extension = dot > slash && sourcePath.length - dot <= 6 ? sourcePath.substring(dot).toLowerCase() : '.jpg';
      final target = File('${folder.path}${Platform.pathSeparator}$receiptId$extension');
      await source.copy(target.path);
      return target.path;
    } catch (e) {
      debugPrint('ReceiptImageStore: could not keep the image of $receiptId: $e');
      return sourcePath;
    }
  }

  /// Deletes [path] if it is an image in the store. Paths outside the store
  /// (picker files, remote URLs) are left alone.
  Future<void> delete(String? path) async {
    if (kIsWeb || path == null || path.isEmpty) return;
    try {
      final folder = await _folder();
      if (!_isInside(path, folder)) return;
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('ReceiptImageStore: could not delete $path: $e');
    }
  }

  Future<Directory> _folder() async {
    final docs = await _documentsDirectory();
    final folder = Directory('${docs.path}${Platform.pathSeparator}$folderName');
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder;
  }

  static bool _isInside(String path, Directory folder) =>
      File(path).absolute.path.startsWith('${folder.absolute.path}${Platform.pathSeparator}');
}
