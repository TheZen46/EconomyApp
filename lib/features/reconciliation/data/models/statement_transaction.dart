import 'package:equatable/equatable.dart';
import '../../../../core/financial/money.dart';

class StatementTransaction extends Equatable {
  final String id;
  final DateTime date;
  final String description;
  final double amount;
  final String currency;
  final String? referenceNumber;
  final bool isReconciled;
  final String? matchedReceiptId;
  final double matchConfidence;

  Money get amountMoney => Money.fromDecimal(amount, currency: currency);

  const StatementTransaction({
    required this.id,
    required this.date,
    required this.description,
    required this.amount,
    this.currency = 'USD',
    this.referenceNumber,
    this.isReconciled = false,
    this.matchedReceiptId,
    this.matchConfidence = 0.0,
  });

  StatementTransaction copyWith({
    String? id,
    DateTime? date,
    String? description,
    double? amount,
    String? currency,
    String? referenceNumber,
    bool? isReconciled,
    String? matchedReceiptId,
    double? matchConfidence,
  }) {
    return StatementTransaction(
      id: id ?? this.id,
      date: date ?? this.date,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      referenceNumber: referenceNumber ?? this.referenceNumber,
      isReconciled: isReconciled ?? this.isReconciled,
      matchedReceiptId: matchedReceiptId ?? this.matchedReceiptId,
      matchConfidence: matchConfidence ?? this.matchConfidence,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'description': description,
    'amount': amount,
    'currency': currency,
    'reference_number': referenceNumber,
    'is_reconciled': isReconciled,
    'matched_receipt_id': matchedReceiptId,
    'match_confidence': matchConfidence,
  };

  factory StatementTransaction.fromJson(Map<String, dynamic> json) => StatementTransaction(
    id: json['id'] as String,
    date: DateTime.parse(json['date'] as String),
    description: json['description'] as String? ?? 'Transaction',
    amount: (json['amount'] as num).toDouble(),
    currency: json['currency'] as String? ?? 'USD',
    referenceNumber: json['reference_number'] as String?,
    isReconciled: json['is_reconciled'] as bool? ?? false,
    matchedReceiptId: json['matched_receipt_id'] as String?,
    matchConfidence: (json['match_confidence'] as num?)?.toDouble() ?? 0.0,
  );

  @override
  List<Object?> get props => [
    id, date, description, amount, currency, referenceNumber, isReconciled, matchedReceiptId, matchConfidence,
  ];
}
