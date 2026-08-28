import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/receipt.dart';
import '../../providers/category_provider.dart';
import '../../providers/receipt_provider.dart';

class RecentReceiptsList extends ConsumerStatefulWidget {
  final List<Receipt> receipts;
  final bool isDark;

  const RecentReceiptsList({
    super.key,
    required this.receipts,
    required this.isDark,
  });

  @override
  ConsumerState<RecentReceiptsList> createState() => _RecentReceiptsListState();
}

class _RecentReceiptsListState extends ConsumerState<RecentReceiptsList> {
  String? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final fgCol = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;
    final categories = ref.watch(categoryListProvider);

    final filtered = widget.receipts.where((r) {
      if (_selectedCategory == null) return true;
      return r.category.toLowerCase() == _selectedCategory!.toLowerCase();
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Recent Transactions',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: fgCol,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: DropdownButton<String?>(
                value: _selectedCategory,
                dropdownColor: colorScheme.surface,
                underline: const SizedBox(),
                icon: Icon(Icons.filter_list, color: muted, size: 18),
                hint: Text('Filter', style: GoogleFonts.spaceGrotesk(color: muted, fontSize: 13)),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text('All', style: GoogleFonts.spaceGrotesk(color: fgCol, fontSize: 13)),
                  ),
                  ...categories.map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c, style: GoogleFonts.spaceGrotesk(color: fgCol, fontSize: 13)),
                  )),
                ],
                onChanged: (val) => setState(() => _selectedCategory = val),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.receipt_long, size: 48, color: colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('No receipts yet', style: GoogleFonts.spaceGrotesk(color: muted)),
                ],
              ),
            ),
          )
        else
          ...filtered.take(5).map((r) => _buildReceiptRow(context, r, colorScheme, fgCol, muted)),
      ],
    );
  }

  Widget _buildReceiptRow(
    BuildContext context,
    Receipt r,
    ColorScheme colorScheme,
    Color fgCol,
    Color muted,
  ) {
    return Dismissible(
      key: ValueKey(r.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: colorScheme.error,
        child: Icon(Icons.delete, color: colorScheme.onError),
      ),
      onDismissed: (_) {
        ref.read(receiptListProvider.notifier).deleteReceipt(r.id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receipt deleted')),
        );
      },
      child: InkWell(
        onTap: () => context.push('/review', extra: r),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.merchantName,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: fgCol,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('MMM dd, yyyy').format(r.date),
                    style: GoogleFonts.spaceGrotesk(fontSize: 12, color: muted),
                  ),
                ],
              ),
              Text(
                '\$${r.totalAmount.toStringAsFixed(2)}',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: fgCol,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
