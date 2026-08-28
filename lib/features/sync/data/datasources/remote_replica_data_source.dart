import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Metadata representing a remote storage file in the sync catalog.
class RemoteFileEntry {
  final String name;
  final String path;
  final int size;
  final String? updatedAt;
  final String? eTag;

  const RemoteFileEntry({
    required this.name,
    required this.path,
    required this.size,
    this.updatedAt,
    this.eTag,
  });

  factory RemoteFileEntry.fromFileObject(FileObject file, String parentPath) {
    return RemoteFileEntry(
      name: file.name,
      path: parentPath.isEmpty ? file.name : '$parentPath/${file.name}',
      size: (file.metadata?['size'] as int?) ?? 0,
      updatedAt: file.updatedAt,
      eTag: (file.metadata?['eTag'] as String?) ?? file.id,
    );
  }
}

/// Abstract remote replica data source interface for cloud synchronization.
abstract class RemoteReplicaDataSource {
  /// Lists all files in the user's remote storage folders (images and labels).
  Future<List<RemoteFileEntry>> listRemoteFiles(String userId);

  /// Downloads binary bytes of a single remote file from the training_data bucket.
  Future<Uint8List> downloadFile(String path);

  /// Fetches all receipts belonging to the user from the Supabase database.
  Future<List<Map<String, dynamic>>> fetchReceipts(String userId);

  /// Fetches all digital vault assets belonging to the user.
  Future<List<Map<String, dynamic>>> fetchAssets(String userId);

  /// Fetches all custom boxes belonging to the user.
  Future<List<Map<String, dynamic>>> fetchBoxes(String userId);

  /// Fetches all invoices belonging to the user.
  Future<List<Map<String, dynamic>>> fetchInvoices(String userId);

  /// Fetches custom taxonomy configurations.
  Future<List<Map<String, dynamic>>> fetchTaxonomies(String userId);
}

/// Production implementation of [RemoteReplicaDataSource] powered by Supabase.
class RemoteReplicaDataSourceImpl implements RemoteReplicaDataSource {
  final SupabaseClient client;
  static const String bucketName = 'training_data';

  RemoteReplicaDataSourceImpl(this.client);

  @override
  Future<List<RemoteFileEntry>> listRemoteFiles(String userId) async {
    final results = <RemoteFileEntry>[];
    try {
      final imagePath = '$userId/images';
      final labelPath = '$userId/labels';

      // 1. List Images
      try {
        final imageFiles = await client.storage
            .from(bucketName)
            .list(path: imagePath)
            .timeout(const Duration(seconds: 12));
        for (final f in imageFiles) {
          if (f.name != '.emptyFolderPlaceholder') {
            results.add(RemoteFileEntry.fromFileObject(f, imagePath));
          }
        }
      } catch (e) {
        debugPrint('RemoteReplica: Notice listing images folder: $e');
      }

      // 2. List Labels
      try {
        final labelFiles = await client.storage
            .from(bucketName)
            .list(path: labelPath)
            .timeout(const Duration(seconds: 12));
        for (final f in labelFiles) {
          if (f.name != '.emptyFolderPlaceholder') {
            results.add(RemoteFileEntry.fromFileObject(f, labelPath));
          }
        }
      } catch (e) {
        debugPrint('RemoteReplica: Notice listing labels folder: $e');
      }
    } catch (e) {
      debugPrint('RemoteReplica: Error listing remote files: $e');
    }
    return results;
  }

  @override
  Future<Uint8List> downloadFile(String path) async {
    try {
      final bytes = await client.storage
          .from(bucketName)
          .download(path)
          .timeout(const Duration(seconds: 20));
      return bytes;
    } catch (e) {
      debugPrint('RemoteReplica: Failed to download $path: $e');
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchReceipts(String userId) async {
    try {
      final response = await client
          .from('receipts')
          .select()
          .eq('user_id', userId)
          .timeout(const Duration(seconds: 12));
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('RemoteReplica: Error fetching receipts table: $e');
      return [];
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAssets(String userId) async {
    try {
      final response = await client
          .from('vault_assets')
          .select()
          .eq('user_id', userId)
          .timeout(const Duration(seconds: 12));
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      try {
        final fallbackResponse = await client
            .from('assets')
            .select()
            .eq('user_id', userId)
            .timeout(const Duration(seconds: 12));
        return List<Map<String, dynamic>>.from(fallbackResponse);
      } catch (e2) {
        debugPrint('RemoteReplica: Notice fetching assets/vault_assets table: $e2');
        return [];
      }
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchBoxes(String userId) async {
    try {
      final response = await client
          .from('boxes')
          .select()
          .eq('user_id', userId)
          .timeout(const Duration(seconds: 12));
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('RemoteReplica: Notice fetching boxes table: $e');
      return [];
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchInvoices(String userId) async {
    try {
      final response = await client
          .from('invoices')
          .select()
          .eq('user_id', userId)
          .timeout(const Duration(seconds: 12));
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('RemoteReplica: Notice fetching invoices table: $e');
      return [];
    }
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTaxonomies(String userId) async {
    try {
      final response = await client
          .from('taxonomies')
          .select()
          .eq('user_id', userId)
          .timeout(const Duration(seconds: 12));
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('RemoteReplica: Notice fetching taxonomies table: $e');
      return [];
    }
  }
}
