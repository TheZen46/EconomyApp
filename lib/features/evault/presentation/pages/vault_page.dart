import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/asset_provider.dart';

class VaultPage extends ConsumerStatefulWidget {
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
    'Expired',
    'Hardware',
    'Furniture'
  ];

  String _deriveCategory(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('macbook') ||
        lower.contains('laptop') ||
        lower.contains('phone') ||
        lower.contains('tv') ||
        lower.contains('computer') ||
        lower.contains('watch') ||
        lower.contains('airpods') ||
        lower.contains('monitor')) {
      return 'Hardware';
    }
    if (lower.contains('chair') ||
        lower.contains('desk') ||
        lower.contains('table') ||
        lower.contains('sofa') ||
        lower.contains('bed') ||
        lower.contains('couch')) {
      return 'Furniture';
    }
    return 'General';
  }

  IconData _getFilterIcon(String filter) {
    switch (filter) {
      case 'Active Warranty':
        return Icons.shield_outlined;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFAFAFA);
    final cardColor = isDark ? const Color(0xFF141414) : Colors.white;
    final borderColor =
        isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04);
    const accentColor = Color(0xFF002FA7);
    const destructiveColor = Color(0xFFD4183D);
    final textColor = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF1A1A1A);
    final mutedTextColor = isDark ? Colors.white70 : Colors.black54;

    final allAssets = ref.watch(assetListProvider);
    final notifier = ref.read(assetListProvider.notifier);

    // Calculate total value based on all assets
    final totalValue = allAssets.fold(0.0, (sum, item) => sum + item.price);

    // Filter assets
    final filteredAssets = allAssets.where((asset) {
      final matchesSearch = asset.name
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()) ||
          asset.merchantName
              .toLowerCase()
              .contains(_searchQuery.toLowerCase());
      if (!matchesSearch) return false;

      final daysLeft =
          asset.warrantyExpiryDate.difference(DateTime.now()).inDays;
      final isExpired = daysLeft <= 0;
      final cat = _deriveCategory(asset.name);

      switch (_activeFilter) {
        case 'Active Warranty':
          return !isExpired;
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
          'Digital Vault',
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
              // Hero Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [
                                accentColor.withOpacity(0.4),
                                const Color(0xFF0891B2).withOpacity(0.2)
                              ]
                            : [
                                accentColor.withOpacity(0.9),
                                const Color(0xFF0891B2).withOpacity(0.9)
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
                    child: Stack(
                      children: [
                        // Decorative glowing orb
                        Positioned(
                          top: -40,
                          right: -40,
                          child: Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.1),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withOpacity(isDark ? 0.05 : 0.2),
                                  blurRadius: 50,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PROTECTED ASSETS',
                              style: GoogleFonts.spaceGrotesk(
                                color: Colors.white.withOpacity(0.7),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              NumberFormat.currency(
                                      symbol: '\$', decimalDigits: 2)
                                  .format(totalValue),
                              style: GoogleFonts.jetBrainsMono(
                                color: Colors.white,
                                fontSize: 48,
                                fontWeight: FontWeight.w200, // thin
                              ),
                            ),
                            const SizedBox(height: 24),
                            Divider(color: Colors.white.withOpacity(0.2)),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${allAssets.length} Active Items',
                                  style: GoogleFonts.spaceGrotesk(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Icon(Icons.cloud_done_outlined,
                                        color: Colors.white.withOpacity(0.9),
                                        size: 16),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Auto-sync enabled',
                                      style: GoogleFonts.spaceGrotesk(
                                        color: Colors.white.withOpacity(0.9),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ).animate().fade(duration: 400.ms).slideY(begin: 0.1, end: 0),
              ),

              // Search & Filters
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      // Search Bar
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
                            hintText: 'Search vault...',
                            hintStyle:
                                GoogleFonts.spaceGrotesk(color: mutedTextColor),
                            prefixIcon: Icon(Icons.search, color: mutedTextColor),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.all(16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Filters
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: _filters.map((filter) {
                            final isActive = _activeFilter == filter;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () =>
                                    setState(() => _activeFilter = filter),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? accentColor
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isActive
                                          ? accentColor
                                          : borderColor,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      if (filter != 'All') ...[
                                        Icon(
                                          _getFilterIcon(filter),
                                          size: 14,
                                          color: isActive
                                              ? Colors.white
                                              : mutedTextColor,
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Text(
                                        filter,
                                        style: GoogleFonts.spaceGrotesk(
                                          color: isActive
                                              ? Colors.white
                                              : mutedTextColor,
                                          fontSize: 13,
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
                      const SizedBox(height: 24),
                    ],
                  ),
                ).animate().fade(duration: 400.ms, delay: 100.ms).slideY(begin: 0.1, end: 0),
              ),

              // Header Row
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'VAULT INVENTORY',
                        style: GoogleFonts.spaceGrotesk(
                          color: mutedTextColor,
                          fontSize: 12,
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
                ).animate().fade(duration: 400.ms, delay: 200.ms),
              ),

              // Grid or Empty State
              if (allAssets.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined,
                            size: 64, color: mutedTextColor.withOpacity(0.5)),
                        const SizedBox(height: 16),
                        Text(
                          'Your vault is empty',
                          style: GoogleFonts.spaceGrotesk(
                            color: textColor,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            'Mark items as assets in receipts to track them here.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.spaceGrotesk(
                              color: mutedTextColor,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fade(),
                )
              else if (filteredAssets.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text(
                      'No items match your criteria.',
                      style: GoogleFonts.spaceGrotesk(color: mutedTextColor),
                    ),
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
                      childAspectRatio: 0.75, // Adjusts height of cards
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

class _AssetCardWidget extends StatefulWidget {
  final dynamic asset;
  final VoidCallback onDelete;
  final Color cardColor;
  final Color borderColor;
  final Color textColor;
  final Color mutedTextColor;
  final Color destructiveColor;

  const _AssetCardWidget({
    Key? key,
    required this.asset,
    required this.onDelete,
    required this.cardColor,
    required this.borderColor,
    required this.textColor,
    required this.mutedTextColor,
    required this.destructiveColor,
  }) : super(key: key);

  @override
  State<_AssetCardWidget> createState() => _AssetCardWidgetState();
}

class _AssetCardWidgetState extends State<_AssetCardWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final expiry = widget.asset.warrantyExpiryDate;
    final daysLeft = expiry.difference(DateTime.now()).inDays;
    final isExpired = daysLeft <= 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: Dismissible(
          key: Key(widget.asset.id),
          direction: DismissDirection.endToStart,
          background: Container(
            decoration: BoxDecoration(
              color: widget.destructiveColor,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 16),
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          onDismissed: (_) {
            widget.onDelete();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Asset removed', style: GoogleFonts.spaceGrotesk()),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
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
                      if (widget.asset.receiptImagePath.isNotEmpty)
                        Image.file(
                          File(widget.asset.receiptImagePath),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _buildFallbackImage(),
                        )
                      else
                        _buildFallbackImage(),
                      
                      // Gradient Overlay
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
                              colors: [
                                Colors.black.withOpacity(0.7),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      
                      // Price
                      Positioned(
                        bottom: 8,
                        left: 12,
                        child: Text(
                          '\$${widget.asset.price.toStringAsFixed(2)}',
                          style: GoogleFonts.jetBrainsMono(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Bottom half: Info
                Expanded(
                  flex: 4,
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
                                fontSize: 14,
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
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        // Warranty chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isExpired
                                ? widget.destructiveColor
                                : const Color(0xFF10B981), // Emerald
                            borderRadius: BorderRadius.circular(12), // Pill shape
                          ),
                          child: Text(
                            isExpired
                                ? 'Warranty Expired'
                                : '$daysLeft days left on warranty',
                            style: GoogleFonts.spaceGrotesk(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
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
        ),
      ),
    ).animate().scale(duration: 300.ms, curve: Curves.easeOut);
  }

  Widget _buildFallbackImage() {
    return Container(
      color: widget.cardColor,
      child: Center(
        child: Icon(
          Icons.shield_outlined,
          size: 40,
          color: widget.mutedTextColor.withOpacity(0.3),
        ),
      ),
    );
  }
}
