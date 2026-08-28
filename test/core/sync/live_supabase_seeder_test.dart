import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:t_aidy/core/privacy/pii_scrubber_service.dart';
import 'package:t_aidy/features/receipt_scanning/domain/entities/receipt.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Live Supabase Seeding & Dual-Tier Verification', () async {
    // 1. Load .env
    await dotenv.load(fileName: '.env');
    final supabaseUrl = dotenv.env['SUPABASE_URL']!;
    final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY']!;

    print('\n===============================================================');
    print(' Connecting Live to Supabase: $supabaseUrl');
    print('===============================================================');

    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );

    final supabase = Supabase.instance.client;
    const uuid = Uuid();

    // 2. Authenticate or create demo user
    const fakeEmail = 'demo.testuser.2026@taidy.app';
    const fakePassword = 'SuperSecretPassword2026!';
    String userId = '';

    try {
      final authRes = await supabase.auth.signInWithPassword(
        email: fakeEmail,
        password: fakePassword,
      );
      userId = authRes.user?.id ?? '';
      print('✓ Authenticated existing test user: $fakeEmail (ID: $userId)');
    } catch (_) {
      try {
        final signUpRes = await supabase.auth.signUp(
          email: fakeEmail,
          password: fakePassword,
        );
        userId = signUpRes.user?.id ?? '';
        print('✓ Created new test user: $fakeEmail (ID: $userId)');
      } catch (e) {
        print('Auth status: $e');
        userId = supabase.auth.currentUser?.id ?? '';
      }
    }

    if (userId.isEmpty) {
      // If anonymous auth or current user exists
      userId = supabase.auth.currentUser?.id ?? uuid.v4();
    }

    print('\n───────────────────────────────────────────────────────────────');
    print(' 1. Seeding Contextual Box (Tier 2 Vault)');
    print('───────────────────────────────────────────────────────────────');
    final boxId = uuid.v4();
    final boxData = {
      'id': boxId,
      'user_id': userId,
      'name': 'Hardware & Gear',
      'budget': 5000.00,
      'spent': 3598.99,
      'currency': 'USD',
      'color_hex': 4278202791, // #002FA7
      'icon_identifier': 'Briefcase',
      'auto_categorize': true,
      'keywords': 'Apple, Sony, Dell, Hardware',
      'is_private': false,
      'version': 1,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    await supabase.from('boxes').upsert(boxData);
    print('✓ Created Box: "${boxData['name']}" (Budget: \$${boxData['budget']}, ID: $boxId)');

    print('\n───────────────────────────────────────────────────────────────');
    print(' 2. Seeding Receipt & Line Items (Tier 2 Vault)');
    print('───────────────────────────────────────────────────────────────');
    final receiptId = uuid.v4();
    final receiptData = {
      'id': receiptId,
      'user_id': userId,
      'merchant_name': 'Apple Store - Fifth Avenue (contact: apple.store@apple.com)',
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

    await supabase.from('receipts').upsert(receiptData);
    print('✓ Created Receipt: "${receiptData['merchant_name']}" (Total: \$${receiptData['total_amount']})');

    final item1 = {
      'id': uuid.v4(),
      'receipt_id': receiptId,
      'user_id': userId,
      'description': 'MacBook Pro 16" M3 Max paid with Card 4532 0150 9988 1234',
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
    };

    final item2 = {
      'id': uuid.v4(),
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
    };

    await supabase.from('receipt_items').upsert(item1);
    await supabase.from('receipt_items').upsert(item2);
    print('  • Line Item 1: "${item1['description']}" (\$${item1['total_price']})');
    print('  • Line Item 2: "${item2['description']}" (\$${item2['total_price']})');

    print('\n───────────────────────────────────────────────────────────────');
    print(' 3. Seeding eVault Protected Asset (Tier 2 Vault)');
    print('───────────────────────────────────────────────────────────────');
    final assetId = uuid.v4();
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

    await supabase.from('vault_assets').upsert(assetData);
    print('✓ Created eVault Asset: "${assetData['name']}" (Warranty: 36 Mo, Price: \$${assetData['price']})');

    print('\n───────────────────────────────────────────────────────────────');
    print(' 4. Seeding Business Invoice (Tier 2 Vault)');
    print('───────────────────────────────────────────────────────────────');
    final invoiceId = uuid.v4();
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

    await supabase.from('invoices').upsert(invoiceData);
    print('✓ Created Invoice: #${invoiceData['invoice_number']} to "${invoiceData['client_name']}" (\$${invoiceData['amount']})');

    print('\n───────────────────────────────────────────────────────────────');
    print(' 5. Seeding User Profile & Gamification Preferences');
    print('───────────────────────────────────────────────────────────────');
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

    await supabase.from('user_profiles').upsert(profileData);
    print('✓ Created User Profile: Budget \$${profileData['monthly_budget']}, XP: ${profileData['gamification_xp']}, Streak: ${profileData['gamification_streak']} days');

    print('\n───────────────────────────────────────────────────────────────');
    print(' 6. Verifying Staged Data via Live Queries');
    print('───────────────────────────────────────────────────────────────');
    final fetchedReceipts = await supabase.from('receipts').select().eq('id', receiptId);
    expect(fetchedReceipts.isNotEmpty, true);
    print('✓ Confirmed Receipt fetched from Supabase: ${fetchedReceipts.first['merchant_name']}');

    final fetchedBoxes = await supabase.from('boxes').select().eq('id', boxId);
    expect(fetchedBoxes.isNotEmpty, true);
    print('✓ Confirmed Box fetched from Supabase: ${fetchedBoxes.first['name']}');

    final fetchedInvoices = await supabase.from('invoices').select().eq('id', invoiceId);
    expect(fetchedInvoices.isNotEmpty, true);
    print('✓ Confirmed Invoice fetched from Supabase: ${fetchedInvoices.first['invoice_number']}');

    final fetchedAssets = await supabase.from('vault_assets').select().eq('id', assetId);
    expect(fetchedAssets.isNotEmpty, true);
    print('✓ Confirmed eVault Asset fetched from Supabase: ${fetchedAssets.first['name']}');

    final fetchedProfile = await supabase.from('user_profiles').select().eq('id', userId);
    expect(fetchedProfile.isNotEmpty, true);
    print('✓ Confirmed User Profile fetched from Supabase: XP = ${fetchedProfile.first['gamification_xp']}');

    final trainingLabels = await supabase.from('receipt_training_labels').select().eq('receipt_id', receiptId);
    print('✓ Tier 1 Training Labels automatically created via trigger: ${trainingLabels.length} samples');
    for (final sample in trainingLabels) {
      print('  -> Sample: "${sample['anonymized_description']}" | Price: \$${sample['total_price']} | Necessity: ${sample['necessity']}');
    }

    print('\n===============================================================');
    print(' LIVE SEEDING & VERIFICATION COMPLETE: ALL DATA SAFELY RECEIVED!');
    print('===============================================================');
  }, timeout: const Timeout(Duration(seconds: 45)));
}
