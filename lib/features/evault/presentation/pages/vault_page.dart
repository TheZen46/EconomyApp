import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'dart:io';

import '../../../../core/theme/app_theme.dart';
import '../providers/asset_provider.dart';

class VaultPage extends ConsumerWidget {
  const VaultPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assets = ref.watch(assetListProvider);
    final notifier = ref.read(assetListProvider.notifier);

    final totalValue = assets.fold(0.0, (sum, item) => sum + item.price);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Digital Vault 🛡️'),
        backgroundColor: Colors.transparent,
      ),
      body: assets.isEmpty 
        ? _buildEmptyState(context)
        : Column(
            children: [
              // Summary Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF2C3E50), Color(0xFF4CA1AF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Protected Assets',
                      style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      NumberFormat.currency(symbol: '\u20AC', decimalDigits: 0).format(totalValue),
                      style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${assets.length} items with active tracking',
                      style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                    ),
                  ],
                ),
              ),
              
              // Grid
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.75,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: assets.length,
                  itemBuilder: (context, index) {
                    final asset = assets[index];
                    final expiry = asset.warrantyExpiryDate;
                    final daysLeft = expiry.difference(DateTime.now()).inDays;
                    final isExpired = daysLeft < 0;
                    
                    return Dismissible(
                      key: Key(asset.id),
                      direction: DismissDirection.endToStart,
                      onDismissed: (_) {
                        notifier.deleteAsset(asset.id);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Asset removed from Vault')),
                        );
                      },
                      background: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.error,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Image
                            Expanded(
                              flex: 3,
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                child: asset.receiptImagePath.isNotEmpty
                                  ? Image.file(
                                      File(asset.receiptImagePath),
                                      width: double.infinity,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_,__,___) => Container(
                                        color: Colors.grey[800], 
                                        child: const Center(child: Icon(Icons.image_not_supported, color: Colors.white30))
                                      ),
                                    )
                                  : Container(
                                      color: Colors.grey[800], 
                                      child: const Center(child: Icon(Icons.shield_outlined, size: 48, color: Colors.white10))
                                    ),
                              ),
                            ),
                            
                            // Info
                            Expanded(
                              flex: 2,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      asset.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textMain),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      asset.merchantName,
                                      style: const TextStyle(color: AppTheme.textDim, fontSize: 10),
                                    ),
                                    const Spacer(),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isExpired ? Colors.red.withOpacity(0.2) : Colors.green.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        isExpired ? 'Expired' : '$daysLeft days left',
                                        style: TextStyle(
                                          color: isExpired ? Colors.redAccent : Colors.greenAccent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_outlined, size: 80, color: AppTheme.textDim.withOpacity(0.3)),
          const SizedBox(height: 16),
          const Text(
            'Keep your valuables safe',
            style: TextStyle(color: AppTheme.textDim, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const SizedBox(
            width: 200,
            child: Text(
              'Swipe left on any receipt item to verify warranty and add it here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textDim, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
