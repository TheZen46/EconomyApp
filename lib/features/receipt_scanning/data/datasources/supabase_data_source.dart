import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/receipt.dart';

abstract class SupabaseDataSource {
  Future<void> uploadTrainingData(Receipt receipt, String imagePath);
  Future<int> getStorageUsage();
  Future<void> deleteData(List<String> ids, {List<String>? imagePaths});
  Future<void> deleteReceipts(List<String> ids) async {}
  Future<List<Map<String, dynamic>>> fetchAllReceipts({
    int pageSize = 100,
    String tableName = 'receipts',
  }) async => [];
}

class SupabaseDataSourceImpl implements SupabaseDataSource {
  final SupabaseClient client;

  SupabaseDataSourceImpl(this.client);

  /// Default batch chunk size to prevent HTTP query string / URL length overflow.
  static const int defaultBatchChunkSize = 100;

  /// Helper to partition a list into chunks of at most [chunkSize].
  static List<List<T>> chunkList<T>(List<T> items, [int chunkSize = defaultBatchChunkSize]) {
    if (items.isEmpty) return [];
    if (chunkSize <= 0) return [items];

    final chunks = <List<T>>[];
    for (int i = 0; i < items.length; i += chunkSize) {
      final end = (i + chunkSize < items.length) ? i + chunkSize : items.length;
      chunks.add(items.sublist(i, end));
    }
    return chunks;
  }

  /// Safely resolves the file extension from [imagePath].
  /// Falls back to '.jpg' if the path has no extension or an invalid one.
  static String _safeExtension(String imagePath) {
    final dotIndex = imagePath.lastIndexOf('.');
    final ext = dotIndex != -1 ? imagePath.substring(dotIndex).toLowerCase() : '';
    if (ext.isEmpty || ext.length > 5) return '.jpg';
    // Strip any non-alphanumeric chars after the dot (paranoia)
    final clean = ext.replaceAll(RegExp(r'[^a-zA-Z0-9.]'), '');
    return clean.isNotEmpty ? clean : '.jpg';
  }

  /// Builds the deterministic storage path for an image.
  /// This must match between upload and delete — single source of truth.
  static String _imagePath(String receiptId, String imagePath, {String? userId}) {
    final ext = _safeExtension(imagePath);
    if (userId != null && userId.isNotEmpty) {
      return '$userId/images/$receiptId$ext';
    }
    return 'images/$receiptId$ext';
  }

  /// Builds the deterministic storage path for a label JSON.
  static String _labelPath(String receiptId, {String? userId}) {
    if (userId != null && userId.isNotEmpty) {
      return '$userId/labels/$receiptId.json';
    }
    return 'labels/$receiptId.json';
  }

  /// Safe helper to read the current user ID without crashing if auth is unmocked or offline.
  String? get _currentUserId {
    try {
      return client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> uploadTrainingData(Receipt receipt, String imagePath) async {
    final userId = _currentUserId;

    try {
      String? publicImageUrl;
      final storagePathImage = _imagePath(receipt.id, imagePath, userId: userId);

      // 1. Upload Image -> training_data/{userId}/images/{uuid}.ext (Web + Native)
      if (imagePath.isNotEmpty) {
        Uint8List? imageBytes;
        try {
          if (!kIsWeb) {
            final file = File(imagePath);
            if (file.existsSync()) {
              imageBytes = await file.readAsBytes();
            }
          }
          if (imageBytes == null || imageBytes.isEmpty) {
            final xfile = XFile(imagePath);
            imageBytes = await xfile.readAsBytes();
          }
        } catch (e) {
          debugPrint('Supabase upload: Could not read image bytes from "$imagePath": $e');
        }

        if (imageBytes != null && imageBytes.isNotEmpty) {
          await client.storage.from('training_data').uploadBinary(
            storagePathImage,
            imageBytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
          );
          publicImageUrl = client.storage.from('training_data').getPublicUrl(storagePathImage);
          debugPrint('Supabase upload: Image successfully uploaded to $storagePathImage');
        } else {
          debugPrint('Supabase upload: Image file empty or not found at "$imagePath", proceeding with metadata.');
        }
      }

      // 2. Create and Upload Label JSON -> training_data/{userId}/labels/{uuid}.json
      final labelJson = {
        "image_id": receipt.id,
        "image_path": storagePathImage,
        if (publicImageUrl != null) "image_url": publicImageUrl,
        if (userId != null) "user_id": userId,
        "timestamp": DateTime.now().toIso8601String(),
        "ground_truth": {
          "merchant": receipt.merchantName,
          "total": receipt.totalAmount,
          "currency": receipt.currency,
          "date": receipt.date.toIso8601String().split('T').first,
          "items": receipt.items.map((e) => {
            "description": e.description,
            "unit_price": e.unitPrice,
            "quantity": e.quantity,
            "total_price": e.totalPrice,
            "category": e.category,
            "necessity": e.necessity.name,
            "is_asset": e.isAsset,
          }).toList(),
          "category": receipt.category
        },
        "meta": {
          "is_user_corrected": true,
          "original_ai_prediction_was_wrong": true
        }
      };

      final jsonString = jsonEncode(labelJson);
      final storagePathLabel = _labelPath(receipt.id, userId: userId);

      await client.storage.from('training_data').uploadBinary(
        storagePathLabel,
        Uint8List.fromList(utf8.encode(jsonString)),
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );

      // 3. Upsert into Supabase database 'receipts' table if configured
      try {
        final receiptRow = {
          'id': receipt.id,
          'merchant_name': receipt.merchantName,
          'total_amount': receipt.totalAmount,
          'currency': receipt.currency,
          'date': receipt.date.toIso8601String(),
          'box_id': receipt.boxId,
          'image_path': storagePathImage,
          'image_url': publicImageUrl ?? client.storage.from('training_data').getPublicUrl(storagePathImage),
          if (userId != null) 'user_id': userId,
          'items': receipt.items.map((e) => {
            'description': e.description,
            'unit_price': e.unitPrice,
            'quantity': e.quantity,
            'total_price': e.totalPrice,
            'category': e.category,
            'necessity': e.necessity.name,
            'is_asset': e.isAsset,
          }).toList(),
        };
        try {
          await client.from('receipts').upsert(receiptRow);
        } on PostgrestException catch (pgrst) {
          // If table schema lacks image_path/image_url (PGRST204), fallback to base schema
          if (pgrst.code == 'PGRST204') {
            final fallbackRow = Map<String, dynamic>.from(receiptRow)
              ..remove('image_path')
              ..remove('image_url');
            await client.from('receipts').upsert(fallbackRow);
          } else {
            rethrow;
          }
        }
      } catch (dbError) {
        debugPrint('Supabase database receipts table upsert notice: $dbError');
      }

    } catch (e) {
      debugPrint('Supabase upload failed: $e');
      rethrow;
    }
  }

  @override
  Future<int> getStorageUsage() async {
    try {
      final userId = _currentUserId;
      final imagePath = userId != null ? '$userId/images' : 'images';
      final labelPath = userId != null ? '$userId/labels' : 'labels';

      final images = await client.storage.from('training_data').list(path: imagePath);
      final labels = await client.storage.from('training_data').list(path: labelPath);

      int totalBytes = 0;
      for (var file in images) {
        totalBytes += file.metadata?['size'] as int? ?? 0;
      }
      for (var file in labels) {
        totalBytes += file.metadata?['size'] as int? ?? 0;
      }

      return totalBytes;
    } catch (e) {
      debugPrint('Failed to get storage usage: $e');
      return 0;
    }
  }

  /// Deletes training data for the given receipt IDs in O(1) per ID.
  /// Uses chunking of 100 paths per request to avoid payload/URL limits.
  @override
  Future<void> deleteData(List<String> ids, {List<String>? imagePaths}) async {
    if (ids.isEmpty) return;

    final userId = _currentUserId;
    final pathsToDelete = <String>[];

    for (int i = 0; i < ids.length; i++) {
      final id = ids[i];
      final imgPath = (imagePaths != null && i < imagePaths.length)
          ? imagePaths[i]
          : '$id.jpg';
      pathsToDelete.add(_imagePath(id, imgPath, userId: userId));
      pathsToDelete.add(_labelPath(id, userId: userId));
    }

    try {
      for (final chunk in chunkList(pathsToDelete, defaultBatchChunkSize)) {
        await client.storage.from('training_data').remove(chunk);
      }
    } catch (e) {
      debugPrint('Supabase delete failed: $e');
      throw Exception('Failed to delete training data: $e');
    }
  }

  /// Executes single batch deletions on the database using chunked
  /// `DELETE ... WHERE id IN (...)` queries in batches of 100 IDs.
  @override
  Future<void> deleteReceipts(List<String> ids) async {
    if (ids.isEmpty) return;

    try {
      final chunks = chunkList(ids, defaultBatchChunkSize);
      for (final chunk in chunks) {
        await client.from('receipts').delete().inFilter('id', chunk);
      }
    } catch (e) {
      debugPrint('Supabase deleteReceipts batch failed: $e');
      throw Exception('Failed to delete receipts: $e');
    }
  }

  /// Retrieves datasets larger than 100 records safely using cursor-based
  /// `.range(from, to)` pagination without hitting the 100-item default ceiling.
  @override
  Future<List<Map<String, dynamic>>> fetchAllReceipts({
    int pageSize = defaultBatchChunkSize,
    String tableName = 'receipts',
  }) async {
    final allRecords = <Map<String, dynamic>>[];
    int from = 0;

    try {
      while (true) {
        final to = from + pageSize - 1;
        final response = await client
            .from(tableName)
            .select()
            .range(from, to);

        final rows = List<Map<String, dynamic>>.from(response as List);
        allRecords.addAll(rows);

        if (rows.length < pageSize) {
          break;
        }
        from += pageSize;
      }

      return allRecords;
    } catch (e) {
      debugPrint('Supabase fetchAllReceipts pagination failed: $e');
      throw Exception('Failed to fetch paginated receipts: $e');
    }
  }
}
