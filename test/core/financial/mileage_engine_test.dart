import 'package:flutter_test/flutter_test.dart';
import 'package:t_aidy/core/financial/mileage_engine.dart';

void main() {
  group('MileageEngine Tests', () {
    final testTrips = [
      MileageTrip(
        id: 'trip-1',
        date: DateTime(2026, 3, 10),
        purpose: 'Client Onsite Consultation',
        startLocation: 'Office HQ',
        endLocation: 'Client Acme Corp',
        distance: 25.0,
        unit: DistanceUnit.miles,
        ratePerUnit: 0.67, // IRS standard
        boxId: 'client-acme',
      ),
      MileageTrip(
        id: 'trip-2',
        date: DateTime(2026, 3, 12),
        purpose: 'Hardware Store Pickup',
        startLocation: 'Office HQ',
        endLocation: 'Apple Store',
        distance: 10.0,
        unit: DistanceUnit.miles,
        ratePerUnit: 0.67,
        boxId: 'internal-ops',
      ),
      MileageTrip(
        id: 'trip-3',
        date: DateTime(2026, 3, 14),
        purpose: 'Airport Transfer for Design Summit',
        startLocation: 'Milan Center',
        endLocation: 'Malpensa Airport',
        distance: 50.0,
        unit: DistanceUnit.kilometers,
        ratePerUnit: 0.35, // €0.35/km
        boxId: 'client-acme',
      ),
    ];

    test('calculates individual trip deductions accurately', () {
      expect(testTrips[0].totalDeductible, 25.0 * 0.67); // 16.75
      expect(testTrips[1].totalDeductible, 10.0 * 0.67); // 6.70
      expect(testTrips[2].totalDeductible, 50.0 * 0.35); // 17.50
    });

    test('calculates consolidated fiscal summary and box attribution', () {
      final summary = MileageEngine.calculateSummary(testTrips);

      expect(summary.tripCount, 3);
      expect(summary.totalDeductibleAmount, closeTo(16.75 + 6.70 + 17.50, 0.01)); // 40.95
      expect(summary.totalDistanceMiles, greaterThan(35.0)); // 35 mi + ~31.06 mi from 50km
      expect(summary.deductionsByBoxId['client-acme'], closeTo(16.75 + 17.50, 0.01));
      expect(summary.deductionsByBoxId['internal-ops'], closeTo(6.70, 0.01));
    });

    test('MileageTrip JSON serialization and deserialization roundtrip', () {
      final trip = testTrips[0];
      final json = trip.toJson();
      final revived = MileageTrip.fromJson(json);

      expect(revived.id, trip.id);
      expect(revived.purpose, trip.purpose);
      expect(revived.distance, trip.distance);
      expect(revived.unit, trip.unit);
      expect(revived.ratePerUnit, trip.ratePerUnit);
      expect(revived.boxId, trip.boxId);
    });
  });
}
