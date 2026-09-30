import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/mileage_engine.dart';
import 'package:t_aidy/features/boxes/data/models/box_model.dart';
import 'package:t_aidy/features/boxes/data/providers/boxes_provider.dart';
import 'package:t_aidy/features/mileage/presentation/pages/mileage_page.dart';

void main() {
  final sampleTrips = [
    MileageTrip(
      id: 'trip-1',
      date: DateTime(2026, 3, 10),
      purpose: 'Client Consultation',
      startLocation: 'Studio',
      endLocation: 'Client Site',
      distance: 20.0,
      unit: DistanceUnit.miles,
      ratePerUnit: 0.67,
      boxId: 'client-box',
    ),
  ];

  final List<BoxModel> sampleBoxes = [
    BoxModel(
      id: 'client-box',
      name: 'Client Alpha',
      color: 0xFF3B82F6,
      icon: 'business',
      budget: 5000.0,
      spent: 1200.0,
      currency: 'USD',
    ),
  ];

  testWidgets('MileagePage renders total deduction, trip details, and add button', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mileageTripsProvider.overrideWith((ref) => MileageNotifier(sampleTrips)),
          boxesProvider.overrideWith((ref) => _FakeBoxesNotifier(sampleBoxes)),
        ],
        child: const MaterialApp(
          home: MileagePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mileage & Travel Log'), findsOneWidget);
    expect(find.text('TOTAL MILEAGE DEDUCTION'), findsOneWidget);
    expect(find.text('Client Consultation'), findsOneWidget);
    expect(find.text('Studio → Client Site'), findsOneWidget);
    expect(find.text('\$13.40'), findsNWidgets(2)); // Total and Trip row
  });
}

class _FakeBoxesNotifier extends BoxesNotifier {
  _FakeBoxesNotifier(List<BoxModel> initial) {
    state = initial;
  }
}
