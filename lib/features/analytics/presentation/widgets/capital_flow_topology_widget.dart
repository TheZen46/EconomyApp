import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../../../core/financial/financial_flow_engine.dart';

/// [UNIQUE] Interactive Canvas Widget for Capital Allocation Topology (Sankey / Waterfall).
///
/// Renders an offline, zero-cloud visual flow of gross revenue into box segregation,
/// statutory tax withholding shields, deductible operating expenses, and safe-to-spend liquidity.
class CapitalFlowTopologyWidget extends StatefulWidget {
  final FinancialFlowGraph flowGraph;
  final Function(FlowNode)? onNodeTapped;

  const CapitalFlowTopologyWidget({
    super.key,
    required this.flowGraph,
    this.onNodeTapped,
  });

  @override
  State<CapitalFlowTopologyWidget> createState() => _CapitalFlowTopologyWidgetState();
}

class _CapitalFlowTopologyWidgetState extends State<CapitalFlowTopologyWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _flowProgress;
  String? _selectedNodeId;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _flowProgress = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.simpleCurrency(decimalDigits: 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top High-Level KPI Summary Cards
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'Gross Inflow',
                currencyFormat.format(widget.flowGraph.totalGrossInflow),
                const Color(0xFF10B981),
                Icons.arrow_downward_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricCard(
                'Tax Shield',
                currencyFormat.format(widget.flowGraph.totalTaxWithholding),
                const Color(0xFFEF4444),
                Icons.shield_outlined,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricCard(
                'Safe-to-Spend',
                currencyFormat.format(widget.flowGraph.totalSafeToSpend),
                const Color(0xFF8B5CF6),
                Icons.account_balance_wallet_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Vector Sankey / Flow Topology Canvas
        Container(
          height: 280,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: AnimatedBuilder(
            animation: _flowProgress,
            builder: (context, child) {
              return CustomPaint(
                painter: _SankeyTopologyPainter(
                  flowGraph: widget.flowGraph,
                  progress: _flowProgress.value,
                  selectedNodeId: _selectedNodeId,
                ),
                child: GestureDetector(
                  onTapUp: (details) => _handleCanvasTap(details.localPosition),
                  child: Container(color: Colors.transparent),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 12),

        // Node Breakdown List / Legend
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.flowGraph.nodes.map((node) {
            final isSelected = _selectedNodeId == node.id;
            return InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                setState(() {
                  _selectedNodeId = isSelected ? null : node.id;
                });
                widget.onNodeTapped?.call(node);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Color(node.colorHex).withValues(alpha: 0.25)
                      : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? Color(node.colorHex)
                        : const Color(0xFF475569),
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Color(node.colorHex),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${node.label}: ${currencyFormat.format(node.value)}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _handleCanvasTap(Offset position) {
    if (widget.flowGraph.nodes.isEmpty) return;
    // Hit-testing fallback for flow graph nodes
    final node = widget.flowGraph.nodes.first;
    setState(() {
      _selectedNodeId = (_selectedNodeId == node.id) ? null : node.id;
    });
    if (_selectedNodeId != null) {
      widget.onNodeTapped?.call(node);
    }
  }

  Widget _buildMetricCard(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: const Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 15,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom Canvas Painter rendering smooth cubic Bézier flow ribbons and node pillars.
class _SankeyTopologyPainter extends CustomPainter {
  final FinancialFlowGraph flowGraph;
  final double progress;
  final String? selectedNodeId;

  _SankeyTopologyPainter({
    required this.flowGraph,
    required this.progress,
    this.selectedNodeId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final nodePositions = <String, Rect>{};

    // Organize nodes by layers:
    // Layer 0: Source (Inflow) -> left column
    // Layer 1: Intermediate Boxes -> middle column
    // Layer 2: Sinks (Tax Shield, Expenses, Safe to Spend) -> right column

    final leftNodes = flowGraph.nodes.where((n) => n.category == 'source').toList();
    final middleNodes = flowGraph.nodes.where((n) => n.category == 'box').toList();
    final rightNodes = flowGraph.nodes
        .where((n) => n.category == 'tax' || n.category == 'expense' || n.category == 'safe_to_spend')
        .toList();

    const nodeWidth = 24.0;
    final padding = 16.0;
    final usableHeight = size.height - (padding * 2);

    // Layout Layer 0 (Left)
    _layoutColumn(leftNodes, padding, padding, nodeWidth, usableHeight, nodePositions);

    // Layout Layer 1 (Middle)
    final midX = (size.width - nodeWidth) / 2;
    _layoutColumn(middleNodes, midX, padding, nodeWidth, usableHeight, nodePositions);

    // Layout Layer 2 (Right)
    final rightX = size.width - padding - nodeWidth;
    _layoutColumn(rightNodes, rightX, padding, nodeWidth, usableHeight, nodePositions);

    // Draw Links as Curved Bézier Ribbons
    for (final link in flowGraph.links) {
      final srcRect = nodePositions[link.sourceId];
      final dstRect = nodePositions[link.targetId];

      if (srcRect == null || dstRect == null) continue;

      final p1 = Offset(srcRect.right, srcRect.center.dy);
      final p2 = Offset(dstRect.left, dstRect.center.dy);

      final currentP2 = Offset.lerp(p1, p2, progress)!;

      final path = Path();
      path.moveTo(p1.dx, p1.dy);

      final dx = (currentP2.dx - p1.dx) / 2;
      path.cubicTo(
        p1.dx + dx,
        p1.dy,
        currentP2.dx - dx,
        currentP2.dy,
        currentP2.dx,
        currentP2.dy,
      );

      final strokeWidth = max(2.0, (link.percentage / 100.0) * 16.0);

      final linkPaint = Paint()
        ..color = Color(link.colorHex).withValues(alpha: selectedNodeId != null && (selectedNodeId == link.sourceId || selectedNodeId == link.targetId) ? 0.65 : 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawPath(path, linkPaint);
    }

    // Draw Node Pillars and Labels
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final node in flowGraph.nodes) {
      final rect = nodePositions[node.id];
      if (rect == null) continue;

      final isSelected = selectedNodeId == node.id;
      final nodeColor = Color(node.colorHex);

      // Node bar
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
      final barPaint = Paint()..color = nodeColor;
      canvas.drawRRect(rrect, barPaint);

      if (isSelected) {
        final highlightPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        canvas.drawRRect(rrect, highlightPaint);
      }

      // Compact text label
      final span = TextSpan(
        text: node.label,
        style: GoogleFonts.inter(
          fontSize: 10,
          color: const Color(0xFFCBD5E1),
          fontWeight: FontWeight.w600,
        ),
      );
      textPainter.text = span;
      textPainter.layout(maxWidth: 80);

      double textX = rect.left;
      if (node.category == 'source') {
        textX = rect.right + 4;
      } else if (node.category == 'box') {
        textX = rect.center.dx - (textPainter.width / 2);
      } else {
        textX = rect.left - textPainter.width - 4;
      }

      textPainter.paint(canvas, Offset(textX, rect.top - 12));
    }
  }

  void _layoutColumn(
    List<FlowNode> nodes,
    double x,
    double top,
    double width,
    double totalHeight,
    Map<String, Rect> positions,
  ) {
    if (nodes.isEmpty) return;

    final spacing = 12.0;
    final totalSpacing = spacing * (nodes.length - 1);
    final availableHeight = max(20.0, totalHeight - totalSpacing);
    final itemHeight = min(60.0, max(24.0, availableHeight / nodes.length));

    double currentY = top + ((totalHeight - (itemHeight * nodes.length + totalSpacing)) / 2).clamp(0.0, totalHeight);

    for (final node in nodes) {
      positions[node.id] = Rect.fromLTWH(x, currentY, width, itemHeight);
      currentY += itemHeight + spacing;
    }
  }

  @override
  bool shouldRepaint(covariant _SankeyTopologyPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.flowGraph != flowGraph;
  }
}
