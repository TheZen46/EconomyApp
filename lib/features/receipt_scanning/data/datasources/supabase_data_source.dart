import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/receipt.dart';

abstract class SupabaseDataSource {
  Future<void> uploadTrainingData(Receipt receipt, String imagePath);
  Future<int> getStorageUsage();
  Future<void> deleteData(List<String> ids);
}

class SupabaseDataSourceImpl implements SupabaseDataSource {
  final SupabaseClient client;

  SupabaseDataSourceImpl(this.client);

  @override
  Future<void> uploadTrainingData(Receipt receipt, String imagePath) async {
    try {
      // 1. Upload Image -> training_data/images/{uuid}.jpg
      final file = File(imagePath);
      final fileExt = imagePath.split('.').last;
      final fileName = '${receipt.id}.$fileExt';
      final imageStoragePath = 'training_images/$fileName';
      // To match user request: "training_data/images/{uuid}.jpg"
      // Note: User said bucket is 'training_data'.
      // Path inside bucket: 'images/{uuid}.jpg'
      
      final storagePathImage = 'images/${receipt.id}.$fileExt';
      
      await client.storage.from('training_data').upload(
        storagePathImage,
        file,
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );

      // 2. Create and Upload Label JSON -> training_data/labels/{uuid}.json
      final labelJson = {
        "image_id": receipt.id,
        "timestamp": DateTime.now().toIso8601String(),
        "ground_truth": {
          "merchant": receipt.merchantName,
          "total": receipt.totalAmount,
          "currency": receipt.currency, // Added currency to keep it complete though user example omitted it
          "date": receipt.date.toIso8601String().split('T').first, // YYYY-MM-DD
          "items": receipt.items.map((e) => {
            "description": e.description,
            "unit_price": e.unitPrice,
            "quantity": e.quantity,
            "total_price": e.totalPrice,
            "category": e.category,
          }).toList(),
          "category": receipt.category
        },
        "meta": {
          "is_user_corrected": true,
          "original_ai_prediction_was_wrong": true // Assumption based on context (this is triggered on edit)
        }
      };

      final jsonString = jsonEncode(labelJson);
      final storagePathLabel = 'labels/${receipt.id}.json';

      await client.storage.from('training_data').uploadBinary(
        storagePathLabel,
        utf8.encode(jsonString),
        fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
      );
      
    } catch (e) {
      // Log error silently, don't crash the app for background sync
      print('Supabase upload failed: $e');
    }
  }

  @override
  Future<int> getStorageUsage() async {
    try {
      // List files in images and labels folders
      // Note: Supabase list is shallow by default, need to check if recursive is needed.
      // Usually it lists root. If we put files in subfolders, we need to search there.
      
      final images = await client.storage.from('training_data').list(path: 'images');
      final labels = await client.storage.from('training_data').list(path: 'labels');

      int totalBytes = 0;
      for (var file in images) {
        totalBytes += file.metadata?['size'] as int? ?? 0;
      }
      for (var file in labels) {
        totalBytes += file.metadata?['size'] as int? ?? 0;
      }
      
      return totalBytes;
    } catch (e) {
      print('Failed to get storage usage: $e');
      return 0;
    }
  }

  @override
  Future<void> deleteData(List<String> ids) async {
    try {
      final imagePaths = ids.map((id) => 'images/$id.jpg').toList(); // Assuming jpg as per upload
      final labelPaths = ids.map((id) => 'labels/$id.json').toList();
      
      // Note: we don't know exact extension for images unless we store it, 
      // but uploadTrainingData uses .split('.').last.
      // However, Supabase remove takes exact path.
      // Since we didn't store extension in Receipt entity properly for cloud path, this is tricky.
      // But wait! uploadTrainingData: final imageStoragePath = 'images/${receipt.id}.$fileExt';
      // To strictly delete correct file, we might need to list files first or try multiple extensions.
      // For now, let's assume jpg as default or try to delete both jpg/png if possible?
      // Actually Supabase remove accepts a list of paths.
      // Let's rely on list first to be safe?
      // Better: List all files in 'images/' filter by ID? Too slow.
      // Let's assume .jpg for now as it's most common or try to match what we upload.
      // In ScanPage image picker returns XFile, we just use path.
      // Let's implement robust deletion: List the directory and find matches.
      
      // 1. List all images
      final images = await client.storage.from('training_data').list(path: 'images');
      final imageFilesToDelete = images
          .where((f) => ids.any((id) => f.name.contains(id)))
          .map((f) => 'images/${f.name}')
          .toList();

      if (imageFilesToDelete.isNotEmpty) {
        await client.storage.from('training_data').remove(imageFilesToDelete);
      }

      // 2. Delete labels (Always json)
      if (labelPaths.isNotEmpty) {
        await client.storage.from('training_data').remove(labelPaths);
      }
      
    } catch (e) {
       print('Supabase delete failed: $e');
    }
  }
}
