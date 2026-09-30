import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Nature of an inter-box financial transfer.
enum InterBoxTransferType {
  /// Internal service billing (e.g. Box A provides engineering to Box B)
  internalServiceBilling,

  /// Shared cost apportionment (e.g. Splitting a high-tier SaaS subscription across boxes)
  sharedCostApportionment,

  /// Capital contribution / working capital reallocation
  capitalContribution,
}

/// A structured inter-box transfer record.
class InterBoxTransferRecord {
  final String transferId;
  final String sourceBoxId;
  final String sourceBoxName;
  final String targetBoxId;
  final String targetBoxName;
  final double amount;
  final String currency;
  final InterBoxTransferType transferType;
  final DateTime timestamp;
  final String memo;
  final bool isTaxNeutral; // True if within same overarching taxpayer identity
  final String auditDigestSha256;

  const InterBoxTransferRecord({
    required this.transferId,
    required this.sourceBoxId,
    required this.sourceBoxName,
    required this.targetBoxId,
    required this.targetBoxName,
    required this.amount,
    this.currency = 'USD',
    required this.transferType,
    required this.timestamp,
    required this.memo,
    this.isTaxNeutral = true,
    required this.auditDigestSha256,
  });

  Map<String, dynamic> toJson() => {
        'transferId': transferId,
        'sourceBoxId': sourceBoxId,
        'sourceBoxName': sourceBoxName,
        'targetBoxId': targetBoxId,
        'targetBoxName': targetBoxName,
        'amount': amount,
        'currency': currency,
        'transferType': transferType.name,
        'timestamp': timestamp.toIso8601String(),
        'memo': memo,
        'isTaxNeutral': isTaxNeutral,
        'auditDigestSha256': auditDigestSha256,
      };
}

/// Ledger consolidation impact summary for inter-box operations.
class InterBoxConsolidationSummary {
  final double totalTransfersAmount;
  final int totalTransfersCount;
  final Map<String, double> netBoxAdjustments; // Map<BoxId, NetTransferBalance>
  final double eliminatedTaxShieldVariance; // Tax shielding prevented from duplicate deduction
  final List<InterBoxTransferRecord> records;

  const InterBoxConsolidationSummary({
    required this.totalTransfersAmount,
    required this.totalTransfersCount,
    required this.netBoxAdjustments,
    required this.eliminatedTaxShieldVariance,
    required this.records,
  });

  Map<String, dynamic> toJson() => {
        'totalTransfersAmount': totalTransfersAmount,
        'totalTransfersCount': totalTransfersCount,
        'netBoxAdjustments': netBoxAdjustments,
        'eliminatedTaxShieldVariance': eliminatedTaxShieldVariance,
        'records': records.map((r) => r.toJson()).toList(),
      };
}

/// [UNIQUE] Autonomous Multi-Entity Inter-Box Transfer & Tax Neutrality Engine.
///
/// Orchestrates cross-box capital movements, generates cryptographically signed
/// internal billing memos, and eliminates fictitious tax shield deductions across consolidated boxes.
class InterBoxTransferEngine {
  /// Generates a validated, cryptographically sealed inter-box transfer record.
  static InterBoxTransferRecord createTransfer({
    required String sourceBoxId,
    required String sourceBoxName,
    required String targetBoxId,
    required String targetBoxName,
    required double amount,
    String currency = 'USD',
    required InterBoxTransferType transferType,
    required String memo,
    bool isTaxNeutral = true,
    DateTime? timestamp,
  }) {
    if (sourceBoxId == targetBoxId) {
      throw ArgumentError('Source and Target box must be distinct entities.');
    }
    if (amount <= 0) {
      throw ArgumentError('Transfer amount must be positive.');
    }

    final ts = timestamp ?? DateTime.now();
    final rawSeed = '$sourceBoxId->$targetBoxId:$amount:$currency:${transferType.name}:${ts.millisecondsSinceEpoch}:$memo';
    final digest = sha256.convert(utf8.encode(rawSeed)).toString();
    final transferId = 'XFER-${digest.substring(0, 10).toUpperCase()}';

    return InterBoxTransferRecord(
      transferId: transferId,
      sourceBoxId: sourceBoxId,
      sourceBoxName: sourceBoxName,
      targetBoxId: targetBoxId,
      targetBoxName: targetBoxName,
      amount: amount,
      currency: currency,
      transferType: transferType,
      timestamp: ts,
      memo: memo,
      isTaxNeutral: isTaxNeutral,
      auditDigestSha256: digest,
    );
  }

  /// Consolidates a list of inter-box transfers and computes eliminated tax shield variances.
  static InterBoxConsolidationSummary consolidateTransfers(
    List<InterBoxTransferRecord> transfers, {
    double baselineTaxRate = 0.25,
  }) {
    double totalAmount = 0.0;
    final netAdjustments = <String, double>{};
    double eliminatedTaxShield = 0.0;

    for (final xfer in transfers) {
      totalAmount += xfer.amount;

      // Source box experiences an outflow (-), target box experiences an inflow (+)
      netAdjustments[xfer.sourceBoxId] = (netAdjustments[xfer.sourceBoxId] ?? 0.0) - xfer.amount;
      netAdjustments[xfer.targetBoxId] = (netAdjustments[xfer.targetBoxId] ?? 0.0) + xfer.amount;

      if (xfer.isTaxNeutral) {
        // If tax neutral, prevent false double deduction / double taxation
        eliminatedTaxShield += (xfer.amount * baselineTaxRate);
      }
    }

    return InterBoxConsolidationSummary(
      totalTransfersAmount: totalAmount,
      totalTransfersCount: transfers.length,
      netBoxAdjustments: netAdjustments,
      eliminatedTaxShieldVariance: eliminatedTaxShield,
      records: List.unmodifiable(transfers),
    );
  }
}

