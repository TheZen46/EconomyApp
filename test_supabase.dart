import 'package:supabase_flutter/supabase_flutter.dart';

void main() async {
  print('Testing Supabase Connection...');
  
  // Credentials from main.dart
  const url = 'https://dodxwqwvfaicmaiedsgj.supabase.co';
  const anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRvZHh3cXd2ZmFpY21haWVkc2dqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk0MTkwNzcsImV4cCI6MjA4NDk5NTA3N30.PTKWP5TNaEjNI4YzliJAUOhHa0Vsif-57Qy9agcM-5A';

  try {
    await Supabase.initialize(url: url, anonKey: anonKey);
    final client = Supabase.instance.client;
    print('Supabase Initialized.');

    print('Attempting to access storage bucket "training_data"...');
    try {
      // Just try to list files to check bucket existence/permissions
      await client.storage.from('training_data').list();
      print('SUCCESS: Storage bucket "training_data" exists and is accessible.');
    } catch (e) {
      print('ERROR: Failed to access storage bucket "training_data".');
      print('Details: $e');
    }

    print('Attempting to access table "gold_dataset"...');
    try {
      // Try a count query
      await client.from('gold_dataset').select().limit(1);
      print('SUCCESS: Table "gold_dataset" exists and is accessible.');
    } catch (e) {
      print('ERROR: Failed to access table "gold_dataset".');
      print('Details: $e');
    }
    
  } catch (e) {
    print('CRITICAL FAILURE: Could not initialize Supabase or network error.');
    print('Details: $e');
  }
}
