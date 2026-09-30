import 'dart:math';

/// A node in the financial capital flow topology graph.
class FlowNode {
  final String id;
  final String label;
  final double value;
  final String category; // 'source', 'box', 'tax', 'expense', 'safe_to_spend'
  final int colorHex;

  const FlowNode({
    required this.id,
    required this.label,
    required this.value,
    required this.category,
    required this.colorHex,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'value': value,
        'category': category,
        'colorHex': colorHex,
      };
}

/// A directional link representing financial throughput between two nodes.
class FlowLink {
  final String sourceId;
  final String targetId;
  final double amount;
  final double percentage;
  final int colorHex;

  const FlowLink({
    required this.sourceId,
    required this.targetId,
    required this.amount,
    required this.percentage,
    required this.colorHex,
  });

  Map<String, dynamic> toJson() => {
        'sourceId': sourceId,
        'targetId': targetId,
        'amount': amount,
        'percentage': percentage,
        'colorHex': colorHex,
      };
}

/// Complete mathematical model of capital flow across freelance operations.
class FinancialFlowGraph {
  final double totalGrossInflow;
  final double totalTaxWithholding;
  final double totalExpenses;
  final double totalSafeToSpend;
  final List<FlowNode> nodes;
  final List<FlowLink> links;

  const FinancialFlowGraph({
    required this.totalGrossInflow,
    required this.totalTaxWithholding,
    required this.totalExpenses,
    required this.totalSafeToSpend,
    required this.nodes,
    required this.links,
  });

  Map<String, dynamic> toJson() => {
        'totalGrossInflow': totalGrossInflow,
        'totalTaxWithholding': totalTaxWithholding,
        'totalExpenses': totalExpenses,
        'totalSafeToSpend': totalSafeToSpend,
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'links': links.map((l) => l.toJson()).toList(),
      };
}

/// [UNIQUE] Offline Financial Flow Topology & Capital Allocation Engine.
///
/// Computes Sankey/waterfall vector topologies mapping gross revenue inflows,
/// multi-box segregation, statutory tax withholding reserves, operating expenses,
/// and net safe-to-spend liquidity with zero cloud dependencies.
class FinancialFlowEngine {
  /// Color palette constants (ARGB integers)
  static const int colorGrossIncome = 0xFF10B981; // Emerald Green
  static const int colorBox = 0xFF3B82F6; // Blue
  static const int colorTaxShield = 0xFFEF4444; // Red/Amber
  static const int colorExpense = 0xFFF59E0B; // Amber
  static const int colorSafeToSpend = 0xFF8B5CF6; // Purple

  /// Computes a full capital flow graph given paid invoices/inflows, box breakdowns,
  /// line-item expenses, and effective tax withholding rate.
  static FinancialFlowGraph computeTopology({
    required double totalGrossInflow,
    required Map<String, double> boxInflows,
    required Map<String, double> boxExpenses,
    required double taxWithholdingRate, // e.g. 0.25 for 25%
  }) {
    final cleanInflow = max(0.0, totalGrossInflow);
    final cleanTaxRate = taxWithholdingRate.clamp(0.0, 0.60);

    final nodes = <FlowNode>[];
    final links = <FlowLink>[];

    // Root Inflow Node
    nodes.add(const FlowNode(
      id: 'node_gross_inflow',
      label: 'Gross Inflow',
      value: 0.0, // Updated below
      category: 'source',
      colorHex: colorGrossIncome,
    ));

    // Calculate total expenses across boxes
    double aggregatedExpenses = 0.0;
    boxExpenses.forEach((_, amount) {
      aggregatedExpenses += max(0.0, amount);
    });

    // Effective tax calculated on net profit (or gross if expenses exceed gross)
    final netOperatingProfit = max(0.0, cleanInflow - aggregatedExpenses);
    final calculatedTaxShield = netOperatingProfit * cleanTaxRate;
    final netSafeToSpend = max(0.0, cleanInflow - aggregatedExpenses - calculatedTaxShield);

    // Update root node value
    nodes[0] = FlowNode(
      id: 'node_gross_inflow',
      label: 'Gross Inflow',
      value: cleanInflow,
      category: 'source',
      colorHex: colorGrossIncome,
    );

    // Add Terminal Sink Nodes
    nodes.add(FlowNode(
      id: 'node_tax_shield',
      label: 'Tax Shield (${(cleanTaxRate * 100).toStringAsFixed(0)}%)',
      value: calculatedTaxShield,
      category: 'tax',
      colorHex: colorTaxShield,
    ));

    nodes.add(FlowNode(
      id: 'node_operating_expenses',
      label: 'Operating Expenses',
      value: aggregatedExpenses,
      category: 'expense',
      colorHex: colorExpense,
    ));

    nodes.add(FlowNode(
      id: 'node_safe_to_spend',
      label: 'Safe-to-Spend Nest',
      value: netSafeToSpend,
      category: 'safe_to_spend',
      colorHex: colorSafeToSpend,
    ));

    // Generate Box Nodes & Inflow Links
    if (boxInflows.isEmpty) {
      // Single box fallback
      const boxNodeId = 'box_main';
      nodes.add(FlowNode(
        id: boxNodeId,
        label: 'Main Box',
        value: cleanInflow,
        category: 'box',
        colorHex: colorBox,
      ));

      links.add(FlowLink(
        sourceId: 'node_gross_inflow',
        targetId: boxNodeId,
        amount: cleanInflow,
        percentage: 100.0,
        colorHex: colorGrossIncome,
      ));

      // Terminal links from main box
      if (cleanInflow > 0) {
        if (calculatedTaxShield > 0) {
          links.add(FlowLink(
            sourceId: boxNodeId,
            targetId: 'node_tax_shield',
            amount: calculatedTaxShield,
            percentage: (calculatedTaxShield / cleanInflow) * 100,
            colorHex: colorTaxShield,
          ));
        }
        if (aggregatedExpenses > 0) {
          links.add(FlowLink(
            sourceId: boxNodeId,
            targetId: 'node_operating_expenses',
            amount: aggregatedExpenses,
            percentage: (aggregatedExpenses / cleanInflow) * 100,
            colorHex: colorExpense,
          ));
        }
        if (netSafeToSpend > 0) {
          links.add(FlowLink(
            sourceId: boxNodeId,
            targetId: 'node_safe_to_spend',
            amount: netSafeToSpend,
            percentage: (netSafeToSpend / cleanInflow) * 100,
            colorHex: colorSafeToSpend,
          ));
        }
      }
    } else {
      double totalBoxInflowSum = 0.0;
      boxInflows.forEach((_, val) => totalBoxInflowSum += max(0.0, val));

      // Effective denominator
      final effectiveInflowSum = totalBoxInflowSum > 0 ? totalBoxInflowSum : cleanInflow;

      boxInflows.forEach((boxName, inflowAmount) {
        final boxVal = max(0.0, inflowAmount);
        final boxId = 'box_${boxName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_').toLowerCase()}';

        nodes.add(FlowNode(
          id: boxId,
          label: boxName,
          value: boxVal,
          category: 'box',
          colorHex: colorBox,
        ));

        final pctOfInflow = effectiveInflowSum > 0 ? (boxVal / effectiveInflowSum) * 100 : 0.0;

        links.add(FlowLink(
          sourceId: 'node_gross_inflow',
          targetId: boxId,
          amount: boxVal,
          percentage: pctOfInflow,
          colorHex: colorGrossIncome,
        ));

        // Proportional outflows from this box
        final boxExp = boxExpenses[boxName] ?? 0.0;
        final boxTax = boxVal > 0 && effectiveInflowSum > 0
            ? calculatedTaxShield * (boxVal / effectiveInflowSum)
            : 0.0;
        final boxNet = max(0.0, boxVal - boxExp - boxTax);

        if (boxVal > 0) {
          if (boxTax > 0) {
            links.add(FlowLink(
              sourceId: boxId,
              targetId: 'node_tax_shield',
              amount: boxTax,
              percentage: (boxTax / boxVal) * 100,
              colorHex: colorTaxShield,
            ));
          }
          if (boxExp > 0) {
            links.add(FlowLink(
              sourceId: boxId,
              targetId: 'node_operating_expenses',
              amount: boxExp,
              percentage: (boxExp / boxVal) * 100,
              colorHex: colorExpense,
            ));
          }
          if (boxNet > 0) {
            links.add(FlowLink(
              sourceId: boxId,
              targetId: 'node_safe_to_spend',
              amount: boxNet,
              percentage: (boxNet / boxVal) * 100,
              colorHex: colorSafeToSpend,
            ));
          }
        }
      });
    }

    return FinancialFlowGraph(
      totalGrossInflow: cleanInflow,
      totalTaxWithholding: calculatedTaxShield,
      totalExpenses: aggregatedExpenses,
      totalSafeToSpend: netSafeToSpend,
      nodes: nodes,
      links: links,
    );
  }
}

