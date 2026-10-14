import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/financial/depreciation_engine.dart';
import '../../data/models/asset_model.dart';
import '../providers/asset_provider.dart';
import '../../../receipt_scanning/domain/entities/receipt.dart';
import '../../../receipt_scanning/presentation/providers/receipt_provider.dart';
import '../../../receipt_scanning/presentation/widgets/universal_receipt_image.dart';

/// Digital Vault page for managing purchased hardware, furniture, warranties, and receipts.
///
/// Features high-value asset tracking, Section 179 / MACRS asset depreciation schedules,
/// warranty expiration countdowns, category filters, and bidirectional deep-linking to scanned receipts.
class VaultPage extends ConsumerStatefulWidget {
  /// Creates a new [VaultPage] instance.
  const VaultPage({super.key});

  @override
  ConsumerState<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends ConsumerState<VaultPage> {
  String _searchQuery = '';
  String _activeFilter = 'All';

  final List<String> _filters = [
    'All',
    'Active Warranty',
    'Expiring Soon (<30d)',
    'Expired',
    'Hardware',
    'Furniture'
  ];

  String _deriveCategory(String name) {
    final lower = name.toLowerCase();
    if (AppConstants.hardwareKeywords.any((kw) => lower.contains(kw))) {
      return 'Hardware';
    }
    if (AppConstants.furnitureKeywords.any((kw) => lower.contains(kw))) {
      return 'Furniture';
    }
    return 'General';
  }

  IconData _getFilterIcon(String filter) {
    switch (filter) {
      case 'Active Warranty':
        return Icons.shield_outlined;
      case 'Expiring Soon (<30d)':
        return Icons.warning_amber_rounded;
      case 'Expired':
        return Icons.history_outlined;
      case 'Hardware':
        return Icons.flash_on_outlined;
      case 'Furniture':
        return Icons.inventory_2_outlined;
      case 'All':
      default:
        return Icons.grid_view_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;
    final bgColor = theme.scaffoldBackgroundColor;
    final cardColor = colorScheme.surface;
    final borderColor = colorScheme.outline;
    final accentColor = colorScheme.primary;
    final destructiveColor = colorScheme.error;
    final textColor = colorScheme.onSurface;
    final mutedTextColor = colorScheme.onSurfaceVariant;

    final allAssets = ref.watch(assetListProvider);
    final isPrivacy = ref.watch(privacyModeProvider);
    final notifier = ref.read(assetListProvider.notifier);

    final taxSummary = DepreciationEngine.calculatePortfolioSummary(allAssets);

    // Filter assets
    final filteredAssets = allAssets.where((asset) {
      final matchesSearch = asset.name
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()) ||
          asset.merchantName
              .toLowerCase()
              .contains(_searchQuery.toLowerCase());
      if (!matchesSearch) return false;

      final daysLeft = asset.warrantyExpiryDate.difference(DateTime.now()).inDays;
      final isExpired = daysLeft <= 0;
      final isExpiringSoon = daysLeft > 0 && daysLeft <= 30;
      final cat = _deriveCategory(asset.name);

      switch (_activeFilter) {
        case 'Active Warranty':
          return !isExpired;
        case 'Expiring Soon (<30d)':
          return isExpiringSoon;
        case 'Expired':
          return isExpired;
        case 'Hardware':
          return cat == 'Hardware';
        case 'Furniture':
          return cat == 'Furniture';
        case 'All':
        default:
          return true;
      }
    }).toList();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: Text(
          'Digital Vault & Asset Ledger',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: textColor),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: CustomScrollView(
            slivers: [
              // Hero Section with Section 179 / Book Value Tax Breakdown
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [
                                accentColor.withOpacity(0.4),
                                colorScheme.secondary.withOpacity(0.2),
                              ]
                            : [
                                accentColor.withOpacity(0.9),
                                colorScheme.secondary.withOpacity(0.9),
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(32),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withOpacity(0.2),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'PORTFOLIO BOOK VALUE',
                              style: GoogleFonts.spaceGrotesk(
                                color: Colors.white.withOpacity(0.8),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.5,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${allAssets.length} Assets',
                                style: GoogleFonts.jetBrainsMono(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppConstants.formatAmount(taxSummary.totalCurrentBookValue, isPrivacy: isPrivacy),
                          style: GoogleFonts.jetBrainsMono(
                            color: Colors.white,
                            fontSize: 44,
                            fontWeight: FontWeight.w200,
                          ),
                        ),
                        const SizedBox(height: 16),
                        
                        // Depreciation & Section 179 Sub-bar
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'ORIGINAL COST',
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 9,
                                        letterSpacing: 1.0,
                                        color: Colors.white.withOpacity(0.7),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      AppConstants.formatAmount(taxSummary.totalAcquisitionCost, isPrivacy: isPrivacy),
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(width: 1, height: 28, color: Colors.white.withOpacity(0.2)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'SEC 179 WRITE-OFF',
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 9,
                                        letterSpacing: 1.0,
                                        color: const Color(0xFF6EE7B7),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      AppConstants.formatAmount(taxSummary.totalSection179Eligible, isPrivacy: isPrivacy),
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF6EE7B7),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(width: 1, height: 28, color: Colors.white.withOpacity(0.2)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'THIS YEAR MACRS',
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 9,
                                        letterSpacing: 1.0,
                                        color: Colors.amber.shade200,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      AppConstants.formatAmount(taxSummary.totalCurrentYearMACRS, isPrivacy: isPrivacy),
                                      style: GoogleFonts.jetBrainsMono(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber.shade200,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().fade(duration: 400.ms).slideY(begin: 0.1, end: 0),
              ),

              // Warranty Expiration Alert Banner (if any expiring in < 30 days)
              if (taxSummary.expiringSoonWarrantyCount > 0)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.amber.withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.amber.shade700, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${taxSummary.expiringSoonWarrantyCount} asset warranty expiring within 30 days!',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _activeFilter = 'Expiring Soon (<30d)'),
                            child: Text('Review', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
                          ),
                        ],
                      ),
                    ),
                  ).animate().fade(duration: 300.ms),
                ),

              // Search & Filters
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Column(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: borderColor),
                        ),
                        child: TextField(
                          onChanged: (val) => setState(() => _searchQuery = val),
                          style: GoogleFonts.spaceGrotesk(color: textColor),
                          decoration: InputDecoration(
                            hintText: 'Search vault items or merchants...',
                            hintStyle: GoogleFonts.spaceGrotesk(color: mutedTextColor),
                            prefixIcon: Icon(Icons.search, color: mutedTextColor),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _filters.map((filter) {
                            final isActive = _activeFilter == filter;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => setState(() => _activeFilter = filter),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isActive ? accentColor : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: isActive ? accentColor : borderColor),
                                  ),
                                  child: Row(
                                    children: [
                                      if (filter != 'All') ...[
                                        Icon(
                                          _getFilterIcon(filter),
                                          size: 14,
                                          color: isActive ? Colors.white : mutedTextColor,
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Text(
                                        filter,
                                        style: GoogleFonts.spaceGrotesk(
                                          color: isActive ? Colors.white : mutedTextColor,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Header Row
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'VAULT ASSET INVENTORY',
                        style: GoogleFonts.spaceGrotesk(
                          color: mutedTextColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        '${filteredAssets.length} Results',
                        style: GoogleFonts.spaceGrotesk(
                          color: mutedTextColor,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Grid of Assets
              if (allAssets.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: mutedTextColor.withOpacity(0.5)),
                        const SizedBox(height: 16),
                        Text(
                          'Your vault is empty',
                          style: GoogleFonts.spaceGrotesk(color: textColor, fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'Mark items as assets in receipts to calculate Section 179 / MACRS depreciation and track warranties.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.spaceGrotesk(color: mutedTextColor, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (filteredAssets.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text('No assets match your filter criteria.', style: GoogleFonts.spaceGrotesk(color: mutedTextColor)),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.68,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final asset = filteredAssets[index];
                        return _AssetCardWidget(
                          asset: asset,
                          onDelete: () => notifier.deleteAsset(asset.id),
                          cardColor: cardColor,
                          borderColor: borderColor,
                          textColor: textColor,
                          mutedTextColor: mutedTextColor,
                          destructiveColor: destructiveColor,
                        );
                      },
                      childCount: filteredAssets.length,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetCardWidget extends ConsumerStatefulWidget {
  final AssetModel asset;
  final VoidCallback onDelete;
  final Color cardColor;
  final Color borderColor;
  final Color textColor;
  final Color mutedTextColor;
  final Color destructiveColor;

  const _AssetCardWidget({
    required this.asset,
    required this.onDelete,
    required this.cardColor,
    required this.borderColor,
    required this.textColor,
    required this.mutedTextColor,
    required this.destructiveColor,
  });

  @override
  ConsumerState<_AssetCardWidget> createState() => _AssetCardWidgetState();
}

class _AssetCardWidgetState extends ConsumerState<_AssetCardWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final expiry = widget.asset.warrantyExpiryDate;
    final daysLeft = expiry.difference(DateTime.now()).inDays;
    final isExpired = daysLeft <= 0;
    final isExpiringSoon = daysLeft > 0 && daysLeft <= 30;
    final colorScheme = Theme.of(context).colorScheme;
    final isPrivacy = ref.watch(privacyModeProvider);

    final sched = DepreciationEngine.calculateSchedule(asset: widget.asset);

    return Dismissible(
      key: Key(widget.asset.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20.0),
        decoration: BoxDecoration(
          color: widget.destructiveColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
      ),
      confirmDismiss: (direction) async {
        return await showDestructiveConfirmationDialog(
          context: context,
          title: 'Delete Asset?',
          message: 'Are you sure you want to remove "${widget.asset.name}" from your digital vault? This action cannot be undone.',
          confirmLabel: 'Delete',
        );
      },
      onDismissed: (direction) {
        widget.onDelete();
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedScale(
        scale: _isHovered ? 1.02 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showDepreciationModal(context, widget.asset, sched, isPrivacy),
          child: Container(
            decoration: BoxDecoration(
              color: widget.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: widget.borderColor),
            ),
            clipBehavior: Clip.hardEdge,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top half: Image
                Expanded(
                  flex: 5,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      UniversalReceiptImage(
                        imagePath: widget.asset.receiptImagePath,
                        receiptId: widget.asset.id,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, stack) => _buildFallbackImage(),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 60,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        left: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Book: ${AppConstants.formatAmount(sched.currentBookValue, isPrivacy: isPrivacy)}',
                              style: GoogleFonts.jetBrainsMono(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Cost: ${AppConstants.formatAmount(widget.asset.price, isPrivacy: isPrivacy)}',
                              style: GoogleFonts.jetBrainsMono(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom half: Info
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.asset.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.spaceGrotesk(
                                color: widget.textColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.asset.merchantName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.spaceGrotesk(
                                color: widget.mutedTextColor,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                        
                        // Method tag & Current Year Write-off
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            sched.method == DepreciationMethod.macrs7Year ? 'MACRS 7-Yr' : 'MACRS 5-Yr',
                            style: GoogleFonts.jetBrainsMono(fontSize: 9, fontWeight: FontWeight.bold, color: colorScheme.primary),
                          ),
                        ),

                        // Warranty chip & Action Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: isExpired
                                    ? widget.destructiveColor.withOpacity(0.15)
                                    : (isExpiringSoon ? Colors.amber.withOpacity(0.18) : const Color(0xFF10B981).withOpacity(0.15)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isExpired
                                    ? 'Expired'
                                    : (isExpiringSoon ? '${daysLeft}d left ⚠️' : '${daysLeft}d warranty'),
                                style: GoogleFonts.jetBrainsMono(
                                  color: isExpired
                                      ? widget.destructiveColor
                                      : (isExpiringSoon ? Colors.amber.shade800 : const Color(0xFF10B981)),
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                final receipts = ref.read(receiptListProvider).valueOrNull ?? [];
                                final matchingReceipt = receipts.cast<Receipt?>().firstWhere(
                                  (r) => r?.id == widget.asset.receiptId || r?.id == widget.asset.id,
                                  orElse: () => null,
                                );
                                if (matchingReceipt != null) {
                                  context.push('/review', extra: matchingReceipt);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Linked receipt for "${widget.asset.name}"')),
                                  );
                                }
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: Icon(Icons.receipt_long_outlined, size: 16, color: widget.mutedTextColor),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }

  void _showDepreciationModal(BuildContext context, AssetModel asset, AssetDepreciationSchedule sched, bool isPrivacy) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Asset Depreciation Schedule',
                style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
              ),
              const SizedBox(height: 4),
              Text(
                '${asset.name} (${asset.merchantName}) - Purchased ${asset.purchaseDate.year}',
                style: GoogleFonts.spaceGrotesk(fontSize: 13, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              ...sched.yearlyEntries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'FY ${entry.fiscalYear} (Yr ${entry.scheduleYearIndex} - ${(entry.deductionRate * 100).toStringAsFixed(1)}%)',
                        style: GoogleFonts.spaceGrotesk(fontSize: 13, color: colorScheme.onSurface),
                      ),
                      Text(
                        'Deduction: ${AppConstants.privacyMask('\$${entry.deductionAmount.toStringAsFixed(2)}', isPrivacy: isPrivacy)}',
                        style: GoogleFonts.jetBrainsMono(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary),
                      ),
                    ],
                  ),
                );
              }),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Current Book Value:', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold)),
                  Text(
                    AppConstants.privacyMask('\$${sched.currentBookValue.toStringAsFixed(2)}', isPrivacy: isPrivacy),
                    style: GoogleFonts.jetBrainsMono(fontWeight: FontWeight.bold, color: const Color(0xFF10B981)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary, foregroundColor: colorScheme.onPrimary),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFallbackImage() {
    return Container(
      color: widget.cardColor,
      child: Center(
        child: Icon(Icons.shield_outlined, size: 40, color: widget.mutedTextColor.withOpacity(0.3)),
      ),
    );
  }
}
