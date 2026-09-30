import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/financial_flow_engine.dart';
import 'package:t_aidy/features/receipt_scanning/presentation/widgets/capital_flow_topology_widget.dart';

void main() {
  testWidgets('CapitalFlowTopologyWidget renders metrics, canvas, and handles selection', (tester) async {
    final graph = FinancialFlowEngine.computeTopology(
      totalGrossInflow: 15000.0,
      boxInflows: {'Tech Box': 10000.0, 'Design Box': 5000.0},
      boxExpenses: {'Tech Box': 2000.0, 'Design Box': 1000.0},
      taxWithholdingRate: 0.25,
    );

    FlowNode? tappedNode;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CapitalFlowTopologyWidget(
              flowGraph: graph,
              onNodeTapped: (node) {
                tappedNode = node;
              },
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Metric Cards
    expect(find.text('Gross Inflow'), findsOneWidget);
    expect(find.text('Tax Shield'), findsOneWidget);
    expect(find.text('Safe-to-Spend'), findsOneWidget);
    expect(find.text('\$15,000'), findsOneWidget);

    // Verify Legend / Nodes
    expect(find.textContaining('Tech Box'), findsWidgets);
    expect(find.textContaining('Design Box'), findsWidgets);

    // Tap on a node chip in the legend
    await tester.tap(find.textContaining('Tech Box').first);
    await tester.pumpAndSettle();

    expect(tappedNode, isNotNull);
    expect(tappedNode?.label, 'Tech Box');
  });
}
