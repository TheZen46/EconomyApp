import 'package:supabase/supabase.dart';
import 'dart:typed_data';
import 'dart:convert';

void main() async {
  final client = SupabaseClient(
    'https://dodxwqwvfaicmaiedsgj.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRvZHh3cXd2ZmFpY21haWVkc2dqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk0MTkwNzcsImV4cCI6MjA4NDk5NTA3N30.PTKWP5TNaEjNI4YzliJAUOhHa0Vsif-57Qy9agcM-5A'
  );
  try {
    print('Uploading test image...');
    final data = Uint8List.fromList([255, 216, 255, 224]); // fake jpeg bytes
    await client.storage.from('training_data').uploadBinary(
      'images/test.jpg',
      data,
      fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
    );
    print('Image Upload Success!');
  } catch(e) {
    print('Image Error: \$e');
  }
}
