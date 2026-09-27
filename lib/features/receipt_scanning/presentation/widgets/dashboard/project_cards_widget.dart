import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../../invoices/data/providers/invoices_provider.dart';
import '../../../../../core/constants/app_constants.dart';
import '../../providers/receipt_provider.dart';

/// Dashboard widget previewing active client invoices and revenue status.
class ProjectCardsWidget extends ConsumerWidget {
  final bool isDark;

  const ProjectCardsWidget({
    super.key,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final fgCol = colorScheme.onSurface;
    final muted = colorScheme.onSurfaceVariant;
    final accent = colorScheme.primary;
    final isPrivacy = ref.watch(privacyModeProvider);

    final invoices = ref.watch(invoicesProvider).take(4).toList();

    Color statusColor(String s) {
      switch (s.toLowerCase()) {
        case 'settled':
          return const Color(0xFF10B981);
        case 'sent':
          return accent;
        case 'overdue':
          return colorScheme.error;
        case 'draft':
        default:
          return muted;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'ACTIVE INVOICES',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 11,
                letterSpacing: 1.2,
                color: muted,
                fontWeight: FontWeight.w600,
              ),
            ),
            GestureDetector(
              onTap: () => context.push('/invoices'),
              child: Row(
                children: [
                  Text(
                    'View all',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      color: muted,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_outward, size: 12, color: muted),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (invoices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.receipt_long_outlined, size: 32, color: muted.withAlpha(100)),
                  const SizedBox(height: 8),
                  Text(
                    'No active invoices',
                    style: GoogleFonts.spaceGrotesk(color: muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else
          ...invoices.map((inv) {
            final statusStr = inv.status;
            final status = statusStr.isEmpty
                ? 'Draft'
                : statusStr.substring(0, 1).toUpperCase() + statusStr.substring(1);
            final amount = inv.amount;
            final color = statusColor(status);

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 18,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    inv.clientName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 13,
                                      color: fgCol,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: color.withAlpha(25),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    status,
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 10,
                                      color: color,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Row(
                              children: [
                                Text(
                                  inv.invoiceNumber,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    color: muted,
                                  ),
                                ),
                                Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 6),
                                  width: 3,
                                  height: 3,
                                  decoration: BoxDecoration(shape: BoxShape.circle, color: muted),
                                ),
                                Text(
                                  DateFormat('MMM dd').format(inv.issuedDate),
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 11,
                                    color: muted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        AppConstants.formatAmount(amount, currency: inv.currency, isPrivacy: isPrivacy),
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 13,
                          color: fgCol,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: colorScheme.outline),
              ],
            );
          }),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: fgCol,
              side: BorderSide(color: colorScheme.outline),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () => context.push('/invoices'),
            child: Text(
              'Manage Invoices',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
