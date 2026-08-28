import 'dart:io';
import 'package:supabase/supabase.dart';
import 'package:uuid/uuid.dart';

void main() async {
  stdout.writeln('===============================================================');
  stdout.writeln(' tAIdy Supabase Dummy Data Generator & Live Seeder');
  stdout.writeln('===============================================================');

  final envFile = File('.env');
  if (!envFile.existsSync()) {
    stdout.writeln('Error: .env file not found.');
    exit(1);
  }

  final envLines = envFile.readAsLinesSync();
  final envMap = <String, String>{};
  for (final line in envLines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final idx = trimmed.indexOf('=');
    if (idx != -1) {
      final key = trimmed.substring(0, idx).trim();
      final val = trimmed.substring(idx + 1).trim();
      envMap[key] = val;
    }
  }

  final supabaseUrl = envMap['SUPABASE_URL']!;
  final supabaseAnonKey = envMap['SUPABASE_ANON_KEY']!;

  stdout.writeln('Connecting to: $supabaseUrl');
  final client = SupabaseClient(supabaseUrl, supabaseAnonKey);
  const uuid = Uuid();

  // Generate a distinct test user per run if needed
  final uniqueSuffix = DateTime.now().millisecondsSinceEpoch % 100000;
  final fakeEmail = 'tester$uniqueSuffix@taidy-demo.io';
  const fakePassword = 'SuperSecretPassword2026!';
  String userId = '';

  stdout.writeln('Creating/Authenticating demo user: $fakeEmail...');
  try {
    final signUpRes = await client.auth.signUp(
      email: fakeEmail,
      password: fakePassword,
    );
    if (signUpRes.user != null) {
      userId = signUpRes.user!.id;
      stdout.writeln('✓ Successfully registered demo user: $fakeEmail (UUID: $userId)');
    }
  } catch (e) {
    stdout.writeln('SignUp notice: $e');
  }

  if (userId.isEmpty) {
    try {
      final signInRes = await client.auth.signInWithPassword(
        email: fakeEmail,
        password: fakePassword,
      );
      if (signInRes.user != null) {
        userId = signInRes.user!.id;
        stdout.writeln('✓ Successfully signed in user: $fakeEmail (UUID: $userId)');
      }
    } catch (e) {
      stdout.writeln('SignIn notice: $e');
    }
  }

  if (userId.isEmpty) {
    stdout.writeln('Fatal: Could not obtain authenticated user UUID.');
    exit(1);
  }

  stdout.writeln('\n───────────────────────────────────────────────────────────────');
  stdout.writeln(' 1. Seeding Contextual Box (Tier 2 Vault)');
  stdout.writeln('───────────────────────────────────────────────────────────────');
  final boxId = 'box-${uuid.v4()}';
  final boxData = {
    'id': boxId,
    'user_id': userId,
    'name': 'Hardware & Gear',
    'budget': 5000.00,
    'spent': 3598.99,
    'currency': 'USD',
    'color_hex': 0x002FA7, // Positive 24-bit RGB value: 12199
    'icon_identifier': 'Briefcase',
    'auto_categorize': true,
    'keywords': 'Apple, Sony, Dell, Hardware',
    'is_private': false,
    'version': 1,
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  await client.from('boxes').upsert(boxData);
  stdout.writeln('✓ Successfully created Box: "${boxData['name']}" (Budget: \$${boxData['budget']}, ID: $boxId)');

  stdout.writeln('\n───────────────────────────────────────────────────────────────');
  stdout.writeln(' 2. Seeding Receipt & Line Items (Tier 2 Vault)');
  stdout.writeln('───────────────────────────────────────────────────────────────');
  final receiptId = 'rec-${uuid.v4()}';
  final receiptData = {
    'id': receiptId,
    'user_id': userId,
    'merchant_name': 'Apple Store - Fifth Avenue',
    'total_amount': 3598.99,
    'currency': 'USD',
    'scanned_date': DateTime.now().toUtc().toIso8601String(),
    'image_path': '$userId/receipts/$receiptId.jpg',
    'vat_number': 'US-998877665',
    'merchant_address': '767 5th Ave, New York, NY 10153',
    'transaction_time': '14:45',
    'box_id': boxId,
    'is_synced': true,
    'version': 1,
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  await client.from('receipts').upsert(receiptData);
  stdout.writeln('✓ Successfully created Receipt: "${receiptData['merchant_name']}" (Total: \$${receiptData['total_amount']})');

  final items = [
    {
      'id': 'item-${uuid.v4()}',
      'receipt_id': receiptId,
      'user_id': userId,
      'description': 'MacBook Pro 16" M3 Max 36GB/1TB Space Black',
      'quantity': 1,
      'unit_price': 3499.00,
      'total_price': 3499.00,
      'main_category': 'Electronics',
      'sub_category': 'Computers & Laptops',
      'necessity': 'essential',
      'is_asset': true,
      'box_id': boxId,
      'is_user_corrected': false,
      'confidence_score': 0.9950,
      'version': 1,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    },
    {
      'id': 'item-${uuid.v4()}',
      'receipt_id': receiptId,
      'user_id': userId,
      'description': 'Apple 140W USB-C Power Adapter with Braided Cable',
      'quantity': 1,
      'unit_price': 99.99,
      'total_price': 99.99,
      'main_category': 'Electronics',
      'sub_category': 'Accessories & Chargers',
      'necessity': 'essential',
      'is_asset': false,
      'box_id': boxId,
      'is_user_corrected': false,
      'confidence_score': 0.9820,
      'version': 1,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    },
  ];

  for (final item in items) {
    await client.from('receipt_items').upsert(item);
    stdout.writeln('  • Inserted Line Item: "${item['description']}" (\$${item['total_price']})');
  }

  stdout.writeln('\n───────────────────────────────────────────────────────────────');
  stdout.writeln(' 3. Seeding eVault Protected Asset (Tier 2 Vault)');
  stdout.writeln('───────────────────────────────────────────────────────────────');
  final assetId = 'asset-${uuid.v4()}';
  final assetData = {
    'id': assetId,
    'user_id': userId,
    'receipt_id': receiptId,
    'name': 'MacBook Pro 16" M3 Max',
    'merchant_name': 'Apple Store - Fifth Avenue',
    'purchase_date': DateTime.now().toUtc().toIso8601String(),
    'warranty_months': 36,
    'price': 3499.00,
    'receipt_image_path': '$userId/images/$receiptId.jpg',
    'document_path': '$userId/documents/applecare_warranty.pdf',
    'version': 1,
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  await client.from('vault_assets').upsert(assetData);
  stdout.writeln('✓ Successfully created eVault Asset: "${assetData['name']}" (Warranty: 36 Months, Price: \$${assetData['price']})');

  stdout.writeln('\n───────────────────────────────────────────────────────────────');
  stdout.writeln(' 4. Seeding Business Invoice (Tier 2 Vault)');
  stdout.writeln('───────────────────────────────────────────────────────────────');
  final invoiceId = 'inv-${uuid.v4()}';
  final invoiceData = {
    'id': invoiceId,
    'user_id': userId,
    'invoice_number': 'INV-2026-888',
    'client_name': 'Stripe Global Payments Inc.',
    'amount': 4850.00,
    'currency': 'USD',
    'status': 'Sent',
    'issued_date': DateTime.now().toUtc().toIso8601String(),
    'due_date': DateTime.now().add(const Duration(days: 30)).toUtc().toIso8601String(),
    'notes': 'Q3 Fintech Infrastructure Consultation & Smart Auditing',
    'version': 1,
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  await client.from('invoices').upsert(invoiceData);
  stdout.writeln('✓ Successfully created Invoice: #${invoiceData['invoice_number']} to "${invoiceData['client_name']}" (\$${invoiceData['amount']})');

  stdout.writeln('\n───────────────────────────────────────────────────────────────');
  stdout.writeln(' 5. Seeding User Profile & Gamification Preferences');
  stdout.writeln('───────────────────────────────────────────────────────────────');
  final profileData = {
    'id': userId,
    'monthly_budget': 4500.00,
    'default_currency': 'USD',
    'theme_mode': 'dark',
    'biometric_enabled': true,
    'google_drive_sync_enabled': false,
    'gamification_xp': 1850,
    'gamification_streak': 15,
    'version': 2,
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  await client.from('user_profiles').upsert(profileData);
  stdout.writeln('✓ Successfully created User Profile: Monthly Budget: \$${profileData['monthly_budget']}, XP: ${profileData['gamification_xp']}, Streak: ${profileData['gamification_streak']} days');

  stdout.writeln('\n───────────────────────────────────────────────────────────────');
  stdout.writeln(' 6. Validating Receiving in Supabase via Select Queries');
  stdout.writeln('───────────────────────────────────────────────────────────────');
  final receipts = await client.from('receipts').select().eq('id', receiptId);
  stdout.writeln('✓ Confirmed Receipt in database: ${receipts.first['merchant_name']} (Total: \$${receipts.first['total_amount']})');

  final boxes = await client.from('boxes').select().eq('id', boxId);
  stdout.writeln('✓ Confirmed Box in database: "${boxes.first['name']}" (Budget: \$${boxes.first['budget']})');

  final invoices = await client.from('invoices').select().eq('id', invoiceId);
  stdout.writeln('✓ Confirmed Invoice in database: #${invoices.first['invoice_number']} for ${invoices.first['client_name']} (\$${invoices.first['amount']})');

  final assets = await client.from('vault_assets').select().eq('id', assetId);
  stdout.writeln('✓ Confirmed eVault Asset in database: "${assets.first['name']}" (\$${assets.first['price']})');

  final profiles = await client.from('user_profiles').select().eq('id', userId);
  stdout.writeln('✓ Confirmed User Profile in database: Budget = \$${profiles.first['monthly_budget']}, XP = ${profiles.first['gamification_xp']}, Streak = ${profiles.first['gamification_streak']}');

  final trainingLabels = await client.from('receipt_training_labels').select().eq('receipt_id', receiptId);
  stdout.writeln('✓ Tier 1 AI Training Labels auto-populated via trigger: ${trainingLabels.length} samples');
  for (final s in trainingLabels) {
    stdout.writeln('  -> Description: "${s['anonymized_description']}" | Price: \$${s['total_price']} | Necessity: ${s['necessity']}');
  }

  stdout.writeln('\n===============================================================');
  stdout.writeln(' DUMMY DATA SEEDING COMPLETE & VERIFIED IN SUPABASE!');
  stdout.writeln('===============================================================');
  exit(0);
}
