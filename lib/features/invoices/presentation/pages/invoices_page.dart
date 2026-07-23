import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../data/models/invoice_model.dart';
import '../../data/providers/invoices_provider.dart';
import '../widgets/create_invoice_sheet.dart';

class InvoicesPage extends ConsumerStatefulWidget {
  const InvoicesPage({super.key});

  @override
  ConsumerState<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends ConsumerState<InvoicesPage> {
  bool _showBetaBanner = true;
  String _searchQuery = '';
  String _statusFilter = 'All';

  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showCreateSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CreateInvoiceSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final invoices = ref.watch(invoicesProvider);
    final notifier = ref.watch(invoicesProvider.notifier);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0A0A0A) : const Color(0xFFFAFAFA);
    final textCol = isDark ? const Color(0xFFF5F5F5) : const Color(0xFF1A1A1A);
    final cardBg = isDark ? const Color(0xFF0F0F0F) : const Color(0xFFFFFFFF);
    final borderCol = isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04);
    final accent = const Color(0xFF002FA7);

    // Filter invoices
    final filtered = invoices.where((i) {
      if (_statusFilter != 'All' && i.status != _statusFilter) return false;
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        return i.clientName.toLowerCase().contains(q) ||
               i.invoiceNumber.toLowerCase().contains(q);
      }
      return true;
    }).toList();

    // Stats
    final totalOutstanding = notifier.totalOutstanding;
    final totalOverdue = notifier.totalOverdue;
    final totalDraft = notifier.totalDraft;
    final awaitingCount = invoices.where((i) => i.status == InvoiceStatus.sent || i.status == InvoiceStatus.overdue).length;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_showBetaBanner)
              Container(
                color: Colors.amber,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Row(
                  children: [
                    const Text('⚠️', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'BETA FEATURE — Invoice tracking is in beta. Data is stored locally only. Cloud sync coming soon.',
                        style: GoogleFonts.spaceGrotesk(color: const Color(0xFF1A1A1A), fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _showBetaBanner = false),
                      child: Text('Dismiss', style: GoogleFonts.spaceGrotesk(color: const Color(0xFF1A1A1A), fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ).animate().fadeIn().slideY(begin: -0.5),

            // Header (sticky inside column)
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: textCol),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'All Invoices',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: textCol,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.download, color: textCol),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: Icon(Icons.filter_list, color: textCol),
                    onPressed: () {},
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _showCreateSheet,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New Invoice'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      textStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: CustomScrollView(
                slivers: [
                  // KPI + Charts Grid
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth > 800;
                          final leftCol = Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildCard(
                                cardBg, borderCol,
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Outstanding Balance', style: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),
                                    const SizedBox(height: 8),
                                    Text(
                                      NumberFormat.currency(symbol: '\$').format(totalOutstanding),
                                      style: GoogleFonts.jetBrainsMono(color: textCol, fontSize: 32, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: accent.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text('$awaitingCount Invoices awaiting payment', style: GoogleFonts.spaceGrotesk(color: accent, fontSize: 12, fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildCard(cardBg, borderCol, Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Overdue', style: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white70 : Colors.black87, fontSize: 12)),
                                        const SizedBox(height: 4),
                                        Text(NumberFormat.currency(symbol: '\$').format(totalOverdue), style: GoogleFonts.jetBrainsMono(color: const Color(0xFFD4183D), fontSize: 18, fontWeight: FontWeight.bold)),
                                      ],
                                    )),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildCard(cardBg, borderCol, Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Drafts', style: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white70 : Colors.black87, fontSize: 12)),
                                        const SizedBox(height: 4),
                                        Text(NumberFormat.currency(symbol: '\$').format(totalDraft), style: GoogleFonts.jetBrainsMono(color: textCol, fontSize: 18, fontWeight: FontWeight.bold)),
                                      ],
                                    )),
                                  ),
                                ],
                              ),
                            ],
                          );

                          final rightCol = _buildCard(
                            cardBg, borderCol,
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Revenue Velocity', style: GoogleFonts.spaceGrotesk(color: textCol, fontSize: 16, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 16),
                                SizedBox(
                                  height: 150,
                                  child: _buildChart(invoices, isDark, accent),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(width: 12, height: 12, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text('Invoiced', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: textCol)),
                                    const SizedBox(width: 16),
                                    Container(width: 12, height: 12, color: accent),
                                    const SizedBox(width: 4),
                                    Text('Settled', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: textCol)),
                                  ],
                                ),
                              ],
                            ),
                          );

                          if (isWide) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 1, child: leftCol),
                                const SizedBox(width: 16),
                                Expanded(flex: 2, child: rightCol),
                              ],
                            );
                          } else {
                            return Column(
                              children: [
                                leftCol,
                                const SizedBox(height: 16),
                                rightCol,
                              ],
                            );
                          }
                        },
                      ),
                    ),
                  ),

                  // Filters & Search
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  style: GoogleFonts.spaceGrotesk(color: textCol),
                                  onChanged: (v) => setState(() => _searchQuery = v),
                                  decoration: InputDecoration(
                                    hintText: 'Search invoices...',
                                    hintStyle: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white54 : Colors.black54),
                                    prefixIcon: Icon(Icons.search, color: isDark ? Colors.white54 : Colors.black54),
                                    suffixIcon: _searchQuery.isNotEmpty 
                                        ? IconButton(
                                            icon: const Icon(Icons.clear), 
                                            onPressed: () {
                                              _searchController.clear();
                                              setState(() => _searchQuery = '');
                                            }
                                          ) 
                                        : null,
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: borderCol),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide(color: borderCol),
                                    ),
                                    filled: true,
                                    fillColor: cardBg,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: ['All', InvoiceStatus.sent, InvoiceStatus.settled, InvoiceStatus.overdue, InvoiceStatus.draft].map((s) {
                                final isSelected = _statusFilter == s;
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: ChoiceChip(
                                    label: Text(s),
                                    selected: isSelected,
                                    onSelected: (_) => setState(() => _statusFilter = s),
                                    selectedColor: accent,
                                    backgroundColor: cardBg,
                                    labelStyle: GoogleFonts.spaceGrotesk(
                                      color: isSelected ? Colors.white : textCol,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    ),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: borderCol)),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Invoice List
                  filtered.isEmpty
                      ? SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(48.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.insert_drive_file_outlined, size: 64, color: isDark ? Colors.white24 : Colors.black26),
                                const SizedBox(height: 16),
                                Text('No invoices found', style: GoogleFonts.spaceGrotesk(color: textCol, fontSize: 16, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ).animate().fadeIn(),
                        )
                      : SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final inv = filtered[index];
                                return _buildInvoiceRow(inv, isDark, cardBg, borderCol, textCol)
                                    .animate()
                                    .fadeIn(duration: 300.ms)
                                    .slideY(begin: 0.2, duration: 300.ms);
                              },
                              childCount: filtered.length,
                            ),
                          ),
                        ),
                  
                  const SliverToBoxAdapter(child: SizedBox(height: 100)), // FAB space
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        backgroundColor: accent,
        shape: const CircleBorder(),
        child: const Icon(Icons.camera_alt, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildCard(Color bg, Color borderCol, Widget child) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderCol),
      ),
      child: child,
    );
  }

  Widget _buildChart(List<InvoiceModel> invoices, bool isDark, Color accent) {
    final now = DateTime.now();
    final months = List.generate(6, (i) => DateTime(now.year, now.month - 5 + i));

    List<BarChartGroupData> groups = [];
    for (int i = 0; i < 6; i++) {
      final m = months[i];
      double invoiced = 0;
      double settled = 0;
      
      for (final inv in invoices) {
        if (inv.issuedDate.year == m.year && inv.issuedDate.month == m.month) {
          if (inv.status != InvoiceStatus.draft) {
            invoiced += inv.amount;
          }
          if (inv.status == InvoiceStatus.settled) {
            settled += inv.amount;
          }
        }
      }
      
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: invoiced,
              color: Colors.grey.withOpacity(0.5),
              width: 12,
              borderRadius: BorderRadius.circular(4),
            ),
            BarChartRodData(
              toY: settled,
              color: accent,
              width: 12,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: groups.fold(0.0, (m, g) {
          final maxRod = g.barRods.fold(0.0, (mr, r) => r.toY > mr ? r.toY : mr);
          return maxRod > m ? maxRod : m;
        }) * 1.2,
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (val, meta) {
                if (val < 0 || val >= 6) return const SizedBox.shrink();
                final date = months[val.toInt()];
                return Text(DateFormat.MMM().format(date), style: GoogleFonts.spaceGrotesk(fontSize: 10, color: isDark ? Colors.white54 : Colors.black54));
              },
              reservedSize: 22,
            ),
          ),
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: groups,
      ),
    );
  }

  Widget _buildInvoiceRow(InvoiceModel inv, bool isDark, Color cardBg, Color borderCol, Color textCol) {
    Color statusBg, statusText;
    IconData statusIcon;

    switch (inv.status) {
      case InvoiceStatus.sent:
        statusBg = const Color(0xFF002FA7).withOpacity(0.1);
        statusText = const Color(0xFF002FA7);
        statusIcon = Icons.access_time;
        break;
      case InvoiceStatus.settled:
        statusBg = isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1);
        statusText = isDark ? Colors.white.withOpacity(0.8) : const Color(0xFF1A1A1A);
        statusIcon = Icons.check_circle_outline;
        break;
      case InvoiceStatus.overdue:
        statusBg = const Color(0xFFD4183D).withOpacity(0.1);
        statusText = const Color(0xFFD4183D);
        statusIcon = Icons.error_outline;
        break;
      default: // draft
        statusBg = const Color(0xFF737373).withOpacity(0.1);
        statusText = const Color(0xFF737373);
        statusIcon = Icons.insert_drive_file_outlined;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderCol),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(inv.clientName, style: GoogleFonts.spaceGrotesk(color: textCol, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(inv.invoiceNumber, style: GoogleFonts.jetBrainsMono(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, color: statusText, size: 14),
                      const SizedBox(width: 4),
                      Text(inv.status, style: GoogleFonts.spaceGrotesk(color: statusText, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(NumberFormat.currency(symbol: '\$').format(inv.amount), style: GoogleFonts.jetBrainsMono(color: textCol, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text('Issued: ${DateFormat.yMd().format(inv.issuedDate)}', style: GoogleFonts.spaceGrotesk(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_horiz, color: isDark ? Colors.white54 : Colors.black54),
            color: cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) {
              if (val == 'delete') {
                ref.read(invoicesProvider.notifier).delete(inv.id);
              } else if (val == 'mark_sent') {
                ref.read(invoicesProvider.notifier).updateStatus(inv.id, InvoiceStatus.sent);
              } else if (val == 'mark_settled') {
                ref.read(invoicesProvider.notifier).updateStatus(inv.id, InvoiceStatus.settled);
              }
            },
            itemBuilder: (context) => [
              if (inv.status == InvoiceStatus.draft)
                const PopupMenuItem(value: 'mark_sent', child: Text('Mark as Sent')),
              if (inv.status == InvoiceStatus.sent || inv.status == InvoiceStatus.overdue)
                const PopupMenuItem(value: 'mark_settled', child: Text('Mark as Settled')),
              const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
            ],
          ),
        ],
      ),
    );
  }
}
