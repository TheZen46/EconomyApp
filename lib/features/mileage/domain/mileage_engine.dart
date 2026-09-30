import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Supported distance units for business travel tracking.
enum DistanceUnit {
  miles,
  kilometers,
}

/// Vehicle category for tax rate compliance.
enum VehicleType {
  standardCar,
  motorcycle,
  electricVehicle,
}

/// Preconfigured statutory standard mileage / travel deduction rates.
class MileageRatePreset {
  final String id;
  final String name;
  final double ratePerUnit;
  final DistanceUnit unit;
  final String currency;
  final String jurisdiction;

  const MileageRatePreset({
    required this.id,
    required this.name,
    required this.ratePerUnit,
    required this.unit,
    required this.currency,
    required this.jurisdiction,
  });
}

const List<MileageRatePreset> kMileageRatePresets = [
  MileageRatePreset(
    id: 'us_standard',
    name: 'US IRS Standard Mileage Rate',
    ratePerUnit: 0.67, // $0.67 per mile
    unit: DistanceUnit.miles,
    currency: 'USD',
    jurisdiction: 'USA',
  ),
  MileageRatePreset(
    id: 'uk_standard',
    name: 'UK HMRC Simplified Expense (up to 10k mi)',
    ratePerUnit: 0.45, // £0.45 per mile
    unit: DistanceUnit.miles,
    currency: 'GBP',
    jurisdiction: 'GBR',
  ),
  MileageRatePreset(
    id: 'eu_de_commute',
    name: 'Germany Pendlerpauschale',
    ratePerUnit: 0.30, // €0.30 per km
    unit: DistanceUnit.kilometers,
    currency: 'EUR',
    jurisdiction: 'DEU',
  ),
  MileageRatePreset(
    id: 'it_aci',
    name: 'Italy ACI Business Travel Benchmark',
    ratePerUnit: 0.35, // €0.35 per km
    unit: DistanceUnit.kilometers,
    currency: 'EUR',
    jurisdiction: 'ITA',
  ),
];

/// A single business mileage log record.
class MileageTrip {
  final String id;
  final DateTime date;
  final String purpose;
  final String startLocation;
  final String endLocation;
  final double distance;
  final DistanceUnit unit;
  final VehicleType vehicleType;
  final String? boxId;
  final double ratePerUnit;

  const MileageTrip({
    required this.id,
    required this.date,
    required this.purpose,
    required this.startLocation,
    required this.endLocation,
    required this.distance,
    required this.unit,
    this.vehicleType = VehicleType.standardCar,
    this.boxId,
    required this.ratePerUnit,
  });

  /// Computed deductible value = distance * ratePerUnit.
  double get totalDeductible => distance * ratePerUnit;

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date.toIso8601String(),
        'purpose': purpose,
        'startLocation': startLocation,
        'endLocation': endLocation,
        'distance': distance,
        'unit': unit.name,
        'vehicleType': vehicleType.name,
        'boxId': boxId,
        'ratePerUnit': ratePerUnit,
      };

  factory MileageTrip.fromJson(Map<String, dynamic> json) => MileageTrip(
        id: json['id'] as String,
        date: DateTime.parse(json['date'] as String),
        purpose: json['purpose'] as String,
        startLocation: json['startLocation'] as String,
        endLocation: json['endLocation'] as String,
        distance: (json['distance'] as num).toDouble(),
        unit: DistanceUnit.values.byName(json['unit'] as String),
        vehicleType: VehicleType.values.byName(json['vehicleType'] as String? ?? 'standardCar'),
        boxId: json['boxId'] as String?,
        ratePerUnit: (json['ratePerUnit'] as num).toDouble(),
      );
}

/// Summary report of all business mileage logs in a fiscal period.
class MileageSummary {
  final double totalDistanceMiles;
  final double totalDistanceKm;
  final double totalDeductibleAmount;
  final int tripCount;
  final Map<String, double> deductionsByBoxId;

  const MileageSummary({
    required this.totalDistanceMiles,
    required this.totalDistanceKm,
    required this.totalDeductibleAmount,
    required this.tripCount,
    required this.deductionsByBoxId,
  });
}

/// Engine for calculating and analyzing business mileage tax deductions.
class MileageEngine {
  /// Aggregates a list of [MileageTrip]s into a fiscal [MileageSummary].
  static MileageSummary calculateSummary(List<MileageTrip> trips) {
    double totalMiles = 0.0;
    double totalKm = 0.0;
    double totalDeductible = 0.0;
    final Map<String, double> byBox = {};

    for (final trip in trips) {
      if (trip.unit == DistanceUnit.miles) {
        totalMiles += trip.distance;
        totalKm += trip.distance * 1.60934;
      } else {
        totalKm += trip.distance;
        totalMiles += trip.distance / 1.60934;
      }

      final deductible = trip.totalDeductible;
      totalDeductible += deductible;

      final boxKey = trip.boxId ?? 'main';
      byBox[boxKey] = (byBox[boxKey] ?? 0.0) + deductible;
    }

    return MileageSummary(
      totalDistanceMiles: totalMiles,
      totalDistanceKm: totalKm,
      totalDeductibleAmount: totalDeductible,
      tripCount: trips.length,
      deductionsByBoxId: byBox,
    );
  }
}

/// State notifier for managing in-memory and persistent mileage logs.
class MileageNotifier extends StateNotifier<List<MileageTrip>> {
  MileageNotifier([List<MileageTrip>? initial]) : super(initial ?? []);

  void addTrip(MileageTrip trip) {
    state = [trip, ...state];
  }

  void removeTrip(String id) {
    state = state.where((t) => t.id != id).toList();
  }

  void clearAll() {
    state = [];
  }
}

/// Provider for list of mileage logs.
final mileageTripsProvider = StateNotifierProvider<MileageNotifier, List<MileageTrip>>((ref) {
  return MileageNotifier();
});

/// Provider for fiscal mileage summary.
final mileageSummaryProvider = Provider<MileageSummary>((ref) {
  final trips = ref.watch(mileageTripsProvider);
  return MileageEngine.calculateSummary(trips);
});
