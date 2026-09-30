import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/financial_flow_engine.dart';

void main() {
  group('FinancialFlowEngine Tests', () {
    test('computes single-box flow topology accurately', () {
      final graph = FinancialFlowEngine.computeTopology(
        totalGrossInflow: 10000.0,
        boxInflows: {},
        boxExpenses: {'main': 2000.0},
        taxWithholdingRate: 0.25,
      );

      expect(graph.totalGrossInflow, 10000.0);
      expect(graph.totalExpenses, 2000.0);
      // Net operating profit = 10000 - 2000 = 8000. Tax = 8000 * 0.25 = 2000.
      expect(graph.totalTaxWithholding, 2000.0);
      // Safe to spend = 10000 - 2000 - 2000 = 6000.
      expect(graph.totalSafeToSpend, 6000.0);

      // Verify Nodes
      final sourceNode = graph.nodes.firstWhere((n) => n.id == 'node_gross_inflow');
      expect(sourceNode.value, 10000.0);

      final taxNode = graph.nodes.firstWhere((n) => n.id == 'node_tax_shield');
      expect(taxNode.value, 2000.0);

      final safeNode = graph.nodes.firstWhere((n) => n.id == 'node_safe_to_spend');
      expect(safeNode.value, 6000.0);

      // Verify Links
      expect(graph.links.isNotEmpty, true);
      final boxLink = graph.links.firstWhere((l) => l.sourceId == 'node_gross_inflow');
      expect(boxLink.amount, 10000.0);
      expect(boxLink.percentage, 100.0);
    });

    test('computes multi-box segregated flow topology with proportional allocations', () {
      final graph = FinancialFlowEngine.computeTopology(
        totalGrossInflow: 20000.0,
        boxInflows: {
          'Consulting': 12000.0,
          'Design': 8000.0,
        },
        boxExpenses: {
          'Consulting': 2000.0,
          'Design': 1000.0,
        },
        taxWithholdingRate: 0.30,
      );

      expect(graph.totalGrossInflow, 20000.0);
      expect(graph.totalExpenses, 3000.0);
      // Net profit = 20000 - 3000 = 17000. Tax = 17000 * 0.30 = 5100.
      expect(graph.totalTaxWithholding, 5100.0);
      // Safe to spend = 20000 - 3000 - 5100 = 11900.
      expect(graph.totalSafeToSpend, 11900.0);

      final consultingNode = graph.nodes.firstWhere((n) => n.label == 'Consulting');
      expect(consultingNode.value, 12000.0);

      final designNode = graph.nodes.firstWhere((n) => n.label == 'Design');
      expect(designNode.value, 8000.0);

      // Check links from gross to boxes
      final consultingLink = graph.links.firstWhere(
        (l) => l.sourceId == 'node_gross_inflow' && l.targetId == consultingNode.id,
      );
      expect(consultingLink.amount, 12000.0);
      expect(consultingLink.percentage, 60.0);

      final designLink = graph.links.firstWhere(
        (l) => l.sourceId == 'node_gross_inflow' && l.targetId == designNode.id,
      );
      expect(designLink.amount, 8000.0);
      expect(designLink.percentage, 40.0);
    });

    test('handles zero and negative income edge cases gracefully with clamping', () {
      final graph = FinancialFlowEngine.computeTopology(
        totalGrossInflow: -500.0,
        boxInflows: {},
        boxExpenses: {},
        taxWithholdingRate: -0.1,
      );

      expect(graph.totalGrossInflow, 0.0);
      expect(graph.totalTaxWithholding, 0.0);
      expect(graph.totalExpenses, 0.0);
      expect(graph.totalSafeToSpend, 0.0);
    });

    test('serializes graph, nodes, and links to JSON cleanly', () {
      final graph = FinancialFlowEngine.computeTopology(
        totalGrossInflow: 5000.0,
        boxInflows: {'Main': 5000.0},
        boxExpenses: {'Main': 500.0},
        taxWithholdingRate: 0.20,
      );

      final json = graph.toJson();
      expect(json['totalGrossInflow'], 5000.0);
      expect(json['nodes'], isA<List>());
      expect(json['links'], isA<List>());
    });
  });
}
